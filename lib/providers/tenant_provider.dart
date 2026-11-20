import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tenant.dart';
import '../models/tenant_member.dart';
import '../repositories/tenant_repository.dart';

/// Loads the rooms available to the signed-in user and tracks the active one.
class TenantProvider extends ChangeNotifier {
  final TenantRepository _repository;

  final List<Tenant> _tenants = [];
  Tenant? _currentTenant;
  bool _loading = false;
  bool _busy = false;
  String? _errorMessage;
  String? _loadedUserId;
  bool _disposed = false;

  TenantProvider(this._repository);

  List<Tenant> get tenants => List.unmodifiable(_tenants);
  Tenant? get currentTenant => _currentTenant;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;

  Future<void> loadForUser({String? userId}) async {
    if (_loading) return;
    if (userId != null && _loadedUserId == userId && _tenants.isNotEmpty) {
      return;
    }
    _load(userId);
  }

  Future<void> _load(String? userId) async {
    _loading = true;
    _errorMessage = null;
    _notify();
    try {
      final rooms = await _repository.fetchMyTenants();
      _tenants
        ..clear()
        ..addAll(rooms);
      _loadedUserId = userId;
      final currentId = _currentTenant?.id;
      _currentTenant = _tenants.isEmpty
          ? null
          : _tenants.firstWhere(
              (t) => t.id == currentId,
              orElse: () => _tenants.first,
            );
    } catch (e) {
      _errorMessage = _friendlyError(e);
    } finally {
      _loading = false;
      _notify();
    }
  }

  void select(Tenant tenant) {
    final match = _tenants.where((t) => t.id == tenant.id);
    _currentTenant = match.isEmpty ? tenant : match.first;
    _errorMessage = null;
    _notify();
  }

  Future<bool> createTenant(String name) async {
    if (name.trim().isEmpty) {
      _errorMessage = 'Give the room a name.';
      _notify();
      return false;
    }
    _busy = true;
    _errorMessage = null;
    _notify();
    try {
      final tenant = await _repository.createTenant(name);
      _tenants.add(tenant);
      _currentTenant = tenant;
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(e);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> joinTenant(String inviteCode) async {
    if (inviteCode.trim().isEmpty) {
      _errorMessage = 'Enter an invite code.';
      _notify();
      return false;
    }
    _busy = true;
    _errorMessage = null;
    _notify();
    try {
      final tenant = await _repository.joinTenant(inviteCode);
      _tenants.removeWhere((t) => t.id == tenant.id);
      _tenants.add(tenant);
      _currentTenant = tenant;
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(e);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<List<TenantMember>> fetchMembers(String tenantId) =>
      _repository.fetchMembers(tenantId);

  Future<String?> addMember({
    required String tenantId,
    required String email,
  }) async {
    try {
      await _repository.addMember(tenantId: tenantId, email: email);
      return null;
    } catch (e) {
      return _friendlyError(e);
    }
  }

  Future<String?> removeMember({
    required String tenantId,
    required String userId,
  }) async {
    try {
      await _repository.removeMember(tenantId: tenantId, userId: userId);
      return null;
    } catch (e) {
      return _friendlyError(e);
    }
  }

  void reset() {
    _tenants.clear();
    _currentTenant = null;
    _loadedUserId = null;
    _errorMessage = null;
    _loading = false;
    _busy = false;
    _notify();
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final message = error.message;
      if (message.contains('Authentication required')) {
        return 'Please sign in again.';
      }
      if (message.contains('duplicate key') ||
          message.contains('already a member')) {
        return 'You are already a member of this room.';
      }
      return message;
    }
    return 'Could not reach the server. Check your connection.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
