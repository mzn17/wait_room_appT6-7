import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:waiting_room/models/app_connectivity.dart';
import 'package:waiting_room/providers/connectivity_provider.dart';
import 'package:waiting_room/services/connectivity_service.dart';

class MockConnectivityService extends Mock implements ConnectivityService {}

void main() {
  late MockConnectivityService service;

  setUp(() {
    service = MockConnectivityService();
    when(() => service.networkChanges).thenAnswer((_) => const Stream.empty());
  });

  ConnectivityProvider build() =>
      ConnectivityProvider(service, debounce: Duration.zero);

  test('offline when there is no network', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => false);
    final p = build();
    await p.initialize();
    expect(p.status, AppConnectivity.offline);
    p.dispose();
  });

  test('backendUnavailable when network exists but Supabase fails', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => false);
    final p = build();
    await p.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.status, AppConnectivity.backendUnavailable);
    p.dispose();
  });

  test('online when network and Supabase are reachable', () async {
    when(() => service.hasNetwork()).thenAnswer((_) async => true);
    when(() => service.isSupabaseAvailable()).thenAnswer((_) async => true);
    final p = build();
    await p.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.isOnline, isTrue);
    p.dispose();
  });
}
