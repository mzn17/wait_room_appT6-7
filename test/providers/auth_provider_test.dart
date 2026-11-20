import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room/models/auth_status.dart';
import 'package:waiting_room/providers/auth_provider.dart';
import 'package:waiting_room/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUser extends Mock implements User {}

void main() {
  late MockAuthService service;
  User? currentUser;

  setUp(() {
    currentUser = null;
    service = MockAuthService();
    when(() => service.currentUser).thenAnswer((_) => currentUser);
    when(() => service.authStateChanges)
        .thenAnswer((_) => const Stream<AuthState>.empty());
  });

  AuthProvider build() => AuthProvider(service);

  MockUser user({String name = 'Alice'}) {
    final user = MockUser();
    when(() => user.id).thenReturn('user-1');
    when(() => user.email).thenReturn('alice@example.com');
    when(() => user.userMetadata).thenReturn({'display_name': name});
    return user;
  }

  test('starts unauthenticated without a session', () {
    final provider = build();
    expect(provider.status, AuthStatus.unauthenticated);
    expect(provider.isAuthenticated, isFalse);
    provider.dispose();
  });

  test('signs in and exposes the display name', () async {
    final signedIn = user();
    when(() => service.signIn(
          email: 'alice@example.com',
          password: 'secret1',
        )).thenAnswer((_) async {
      currentUser = signedIn;
    });
    final provider = build();

    final ok = await provider.signIn(
      email: 'alice@example.com',
      password: 'secret1',
    );

    expect(ok, isTrue);
    expect(provider.status, AuthStatus.authenticated);
    expect(provider.displayName, 'Alice');
    provider.dispose();
  });

  test('auth errors are shown without throwing', () async {
    when(() => service.signIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(const AuthException('Invalid login credentials'));
    final provider = build();

    final ok = await provider.signIn(
      email: 'alice@example.com',
      password: 'wrong',
    );

    expect(ok, isFalse);
    expect(provider.errorMessage, 'Invalid login credentials');
    expect(provider.status, AuthStatus.unauthenticated);
    provider.dispose();
  });

  test('sign up asking for email confirmation stays signed out', () async {
    when(() => service.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
        )).thenAnswer((_) async => AuthResponse());
    final provider = build();

    final ok = await provider.signUp(
      email: 'new@example.com',
      password: 'secret1',
      displayName: 'New User',
    );

    expect(ok, isTrue);
    expect(provider.infoMessage, contains('Confirm your email'));
    expect(provider.status, AuthStatus.unauthenticated);
    provider.dispose();
  });

  test('sign out clears the session state', () async {
    currentUser = user();
    when(() => service.signOut()).thenAnswer((_) async {
      currentUser = null;
    });
    final provider = build();
    expect(provider.isAuthenticated, isTrue);

    await provider.signOut();

    expect(provider.status, AuthStatus.unauthenticated);
    expect(provider.isAuthenticated, isFalse);
    provider.dispose();
  });
}
