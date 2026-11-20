import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/auth_status.dart';
import '../services/auth_service.dart';

/// Holds the Supabase session and exposes the signed-in user.
class AuthProvider extends ChangeNotifier {
  final AuthService _service;
  StreamSubscription<AuthState>? _subscription;

  AuthStatus _status = AuthStatus.unknown;
  bool _busy = false;
  String? _errorMessage;
  String? _infoMessage;
  bool _disposed = false;

  AuthProvider(this._service) {
    final user = _service.currentUser;
    _status =
        user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated;
    _subscription = _service.authStateChanges.listen(
      _onAuthState,
      onError: (_) => _setStatus(AuthStatus.unauthenticated),
    );
  }

  AuthStatus get status => _status;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get busy => _busy;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;

  User? get user => _service.currentUser;
  String? get userId => user?.id;
  String get email => user?.email ?? '';

  String get displayName {
    final metadata = user?.userMetadata;
    final name = metadata?['display_name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    final mail = email;
    if (mail.contains('@')) return mail.split('@').first;
    return mail.isEmpty ? 'Guest' : mail;
  }

  void _onAuthState(AuthState state) {
    _setStatus(state.session == null
        ? AuthStatus.unauthenticated
        : AuthStatus.authenticated);
  }

  void _setStatus(AuthStatus status) {
    if (_disposed) return;
    _status = status;
    _busy = false;
    notifyListeners();
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _busy = true;
    _errorMessage = null;
    _infoMessage = null;
    _notify();
    try {
      await _service.signIn(email: email, password: password);
      _status = AuthStatus.authenticated;
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'Unable to sign in. Check your connection.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _busy = true;
    _errorMessage = null;
    _infoMessage = null;
    _notify();
    try {
      final response = await _service.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (response.session == null) {
        _infoMessage =
            'Account created. Confirm your email, then sign in to continue.';
        _status = AuthStatus.unauthenticated;
      } else {
        _status = AuthStatus.authenticated;
      }
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (_) {
      _errorMessage = 'Unable to create the account. Check your connection.';
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> signOut() async {
    _busy = true;
    _notify();
    try {
      await _service.signOut();
    } catch (_) {
      // A failed sign-out should still clear the local UI state.
    } finally {
      _status = AuthStatus.unauthenticated;
      _busy = false;
      _notify();
    }
  }

  void clearMessages() {
    _errorMessage = null;
    _infoMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
