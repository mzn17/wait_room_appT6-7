import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_connectivity.dart';
import '../services/connectivity_service.dart';

class ConnectivityProvider extends ChangeNotifier {
  final ConnectivityService _service;
  final Duration _debounce;
  StreamSubscription<bool>? _subscription;
  Timer? _debounceTimer;

  AppConnectivity _status = AppConnectivity.checking;
  bool _checkingBackend = false;
  bool _checkAgain = false;
  bool _disposed = false;

  ConnectivityProvider(
    this._service, {
    Duration debounce = const Duration(milliseconds: 700),
  }) : _debounce = debounce;

  AppConnectivity get status => _status;
  bool get isOnline => _status == AppConnectivity.online;

  Future<void> initialize() async {
    _subscription = _service.networkChanges.listen(
      _handleNetworkChange,
      onError: (_) => _setStatus(AppConnectivity.checking),
    );
    final connected = await _service.hasNetwork();
    if (_disposed) return;
    _handleNetworkChange(connected);
  }

  void _handleNetworkChange(bool connected) {
    _debounceTimer?.cancel();
    if (!connected) {
      _setStatus(AppConnectivity.offline);
      return;
    }
    _debounceTimer = Timer(_debounce, _checkBackend);
  }

  Future<void> _checkBackend() async {
    if (_disposed) return;
    if (_checkingBackend) {
      _checkAgain = true;
      return;
    }
    _checkingBackend = true;
    try {
      do {
        _checkAgain = false;
        final available = await _service.isSupabaseAvailable();
        if (_disposed) return;
        _setStatus(available
            ? AppConnectivity.online
            : AppConnectivity.backendUnavailable);
      } while (_checkAgain && !_disposed);
    } finally {
      _checkingBackend = false;
    }
  }

  void _setStatus(AppConnectivity s) {
    if (_disposed || _status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
