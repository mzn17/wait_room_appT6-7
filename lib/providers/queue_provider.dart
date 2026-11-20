import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../models/queue_state.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../services/geolocation_service.dart';
import '../services/sync_service.dart';

class QueueProvider extends ChangeNotifier {
  final QueueRepository _repository;
  final GeolocationService _geolocationService;
  final SyncService _syncService;
  final bool Function() _isOnline;
  final Uuid _uuid;
  final int _pageSize;
  final bool _enableRealtime;

  final List<Client> _clients = [];
  List<Client> _pending = [];
  QueueState _state = QueueState.initial;
  String? _errorMessage;
  String? _tenantId;
  String? _userId;
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _disposed = false;
  RealtimeChannel? _channel;

  QueueProvider(
    this._repository,
    this._geolocationService,
    this._syncService, {
    bool Function()? isOnline,
    Uuid? uuid,
    int pageSize = 20,
    bool enableRealtime = true,
  })  : _isOnline = isOnline ?? (() => true),
        _uuid = uuid ?? const Uuid(),
        _pageSize = pageSize,
        _enableRealtime = enableRealtime;

  List<Client> get clients => List.unmodifiable(_clients);
  List<Client> get pending => List.unmodifiable(_pending);
  QueueState get state => _state;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  String? get errorMessage => _errorMessage;
  String? get tenantId => _tenantId;
  String? get userId => _userId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Binds the queue to one room and one signed-in user.
  Future<void> openTenant({
    required String tenantId,
    required String userId,
  }) async {
    if (_tenantId == tenantId &&
        _userId == userId &&
        _state != QueueState.initial) {
      return;
    }
    _tenantId = tenantId;
    _userId = userId;
    _channel?.unsubscribe();
    _channel = null;
    _clients.clear();
    _pending = [];
    _page = 0;
    _hasMore = true;
    _errorMessage = null;
    _state = QueueState.initial;
    _notify();

    await loadPending();
    await fetchInitialQueue();
    startRealtime();

    // A registration created in a previous session may still be pending.
    if (_isOnline() && _pending.isNotEmpty) {
      await syncNow();
    }
  }

  /// Called on sign-out; clears all user-specific data.
  void reset() {
    _channel?.unsubscribe();
    _channel = null;
    _tenantId = null;
    _userId = null;
    _clients.clear();
    _pending = [];
    _page = 0;
    _hasMore = true;
    _isLoadingMore = false;
    _errorMessage = null;
    _state = QueueState.initial;
    _notify();
  }

  Future<void> loadPending() async {
    final tenantId = _tenantId;
    final userId = _userId;
    if (tenantId == null || userId == null) {
      _pending = [];
      _notify();
      return;
    }
    _pending = await _repository.getUnsyncedLocally(
      tenantId: tenantId,
      userId: userId,
    );
    _notify();
  }

  /// [silent] keeps the current list visible (pull-to-refresh / background).
  Future<void> fetchInitialQueue({bool silent = false}) async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    _state = (silent && _clients.isNotEmpty)
        ? QueueState.refreshing
        : QueueState.loading;
    _notify();

    try {
      final data = await _repository.fetchPage(
        tenantId: tenantId,
        offset: 0,
        limit: _pageSize,
      );
      _clients
        ..clear()
        ..addAll(data);
      _page = 0;
      _hasMore = data.length >= _pageSize;
      _errorMessage = null;
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
    } catch (_) {
      if (silent && _clients.isNotEmpty) {
        _state = QueueState.loaded;
      } else {
        _errorMessage = 'Failed to load queue';
        _state = QueueState.error;
      }
    } finally {
      _notify();
    }
  }

  Future<void> loadMore() async {
    final tenantId = _tenantId;
    if (tenantId == null) return;
    if (_isLoadingMore || !_hasMore || _state == QueueState.loading) return;
    _isLoadingMore = true;
    _notify();

    try {
      _page++;
      final next = await _repository.fetchPage(
        tenantId: tenantId,
        offset: _page * _pageSize,
        limit: _pageSize,
      );
      final existing = _clients.map((c) => c.id).toSet();
      _clients.addAll(next.where((c) => !existing.contains(c.id)));
      if (next.length < _pageSize) _hasMore = false;
    } catch (_) {
      _page--;
    } finally {
      _isLoadingMore = false;
      _notify();
    }
  }

  /// Works online and offline. Location is optional.
  Future<void> register(String name) async {
    final tenantId = _tenantId;
    final userId = _userId;
    if (tenantId == null || userId == null) return;

    final position = await _geolocationService.getCurrentPosition();

    final client = Client(
      id: _uuid.v4(), // client-generated id makes retries idempotent
      tenantId: tenantId,
      registeredBy: userId,
      name: name.trim(),
      lat: position?.latitude,
      lng: position?.longitude,
      locationAccuracy: position?.accuracy,
      createdAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );

    await _repository.saveLocally(client);
    await loadPending();

    if (_isOnline()) await syncNow();
  }

  Future<void> syncNow() async {
    final userId = _userId;
    if (_tenantId == null || userId == null) return;
    await _syncService.synchronize(userId: userId);
    await loadPending();
    await fetchInitialQueue(silent: true);
  }

  void startRealtime() {
    final tenantId = _tenantId;
    if (!_enableRealtime || tenantId == null) return;
    _channel ??= _repository.subscribeToInserts(
      tenantId: tenantId,
      onInsert: handleRealtimeInsert,
    );
  }

  /// Ignores duplicates. If more pages exist, the new row will arrive through
  /// pagination in order, so only append when we already hold the tail.
  void handleRealtimeInsert(Client client) {
    if (client.tenantId != null && client.tenantId != _tenantId) return;
    if (_clients.any((c) => c.id == client.id)) return;
    if (_hasMore) return;
    _clients.add(client);
    _clients.sort((a, b) =>
        (a.queueNumber ?? 1 << 30).compareTo(b.queueNumber ?? 1 << 30));
    if (_state == QueueState.empty) _state = QueueState.loaded;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.unsubscribe();
    super.dispose();
  }
}
