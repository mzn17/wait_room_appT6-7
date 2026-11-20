import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room/providers/auth_provider.dart';
import 'package:waiting_room/screens/home_gate.dart';
import 'package:waiting_room/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  testWidgets('signed-out users see the sign-in screen', (tester) async {
    final service = MockAuthService();
    when(() => service.currentUser).thenReturn(null);
    when(() => service.authStateChanges)
        .thenAnswer((_) => const Stream<AuthState>.empty());
    final auth = AuthProvider(service);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pump();

    expect(find.text('Waiting Room'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
