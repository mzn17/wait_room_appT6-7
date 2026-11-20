import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:waiting_room/models/client.dart';
import 'package:waiting_room/models/queue_state.dart';
import 'package:waiting_room/models/sync_status.dart';
import 'package:waiting_room/providers/queue_provider.dart';
import 'package:waiting_room/repositories/queue_repository.dart';
import 'package:waiting_room/services/geolocation_service.dart';
import 'package:waiting_room/services/sync_service.dart';

class MockRepo extends Mock implements QueueRepository {}

class MockGeo extends Mock implements GeolocationService {}

class MockSync extends Mock implements SyncService {}

class FakeClient extends Fake implements Client {}

Client c(int n, {String? tenantId = 't1'}) => Client(
      id: '$n',
      name: 'C$n',
      tenantId: tenantId,
      queueNumber: n,
      createdAt: DateTime(2026, 1, 1),
    );

List<Client> range(int from, int to) => [for (var i = from; i <= to; i++) c(i)];

void main() {
  late MockRepo repo;
  late MockGeo geo;
  late MockSync sync;

  QueueProvider build({bool online = false}) => QueueProvider(
        repo,
        geo,
        sync,
        isOnline: () => online,
        enableRealtime: false,
      );

  setUpAll(() => registerFallbackValue(FakeClient()));

  setUp(() {
    repo = MockRepo();
    geo = MockGeo();
    sync = MockSync();
    when(() => geo.getCurrentPosition()).thenAnswer((_) async => null);
    when(() => repo.saveLocally(any())).thenAnswer((_) async {});
    when(() => repo.getUnsyncedLocally(tenantId: 't1', userId: 'u1'))
        .thenAnswer((_) async => []);
    when(() => sync.synchronize(userId: 'u1')).thenAnswer((_) async {});
  });

  test('empty queue gives QueueState.empty', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => []);
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    expect(p.state, QueueState.empty);
  });

  test('fetch error gives QueueState.error', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenThrow(Exception('x'));
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    expect(p.state, QueueState.error);
    expect(p.errorMessage, isNotNull);
  });

  test('loadMore does not duplicate overlapping records', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 20));
    when(() => repo.fetchPage(tenantId: 't1', offset: 20, limit: 20))
        .thenAnswer((_) async => range(20, 25)); // 20 overlaps
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    expect(p.hasMore, isTrue);
    await p.loadMore();
    expect(p.clients.length, 25);
    expect(p.hasMore, isFalse);
  });

  test('realtime insert of a known client is ignored', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 3));
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    p.handleRealtimeInsert(c(2));
    expect(p.clients.length, 3);
  });

  test('realtime insert of a new client is appended when on last page',
      () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 3));
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    p.handleRealtimeInsert(c(4));
    expect(p.clients.last.queueNumber, 4);
  });

  test('realtime insert from another room is ignored', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 3));
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    p.handleRealtimeInsert(c(9, tenantId: 'other-room'));
    expect(p.clients.length, 3);
  });

  test('register offline saves locally and does not sync', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => []);
    final p = build(online: false);
    await p.openTenant(tenantId: 't1', userId: 'u1');
    await p.register('  Ali ');
    final saved =
        verify(() => repo.saveLocally(captureAny())).captured.single as Client;
    expect(saved.name, 'Ali');
    expect(saved.tenantId, 't1');
    expect(saved.registeredBy, 'u1');
    verifyNever(() => sync.synchronize(userId: any(named: 'userId')));
  });

  test('register online saves locally then syncs', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => []);
    final p = build(online: true);
    await p.openTenant(tenantId: 't1', userId: 'u1');
    await p.register('Ali');
    verify(() => repo.saveLocally(any())).called(1);
    verify(() => sync.synchronize(userId: 'u1')).called(1);
  });

  test('opening a room online flushes pending registrations', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => []);
    when(() => repo.getUnsyncedLocally(tenantId: 't1', userId: 'u1'))
        .thenAnswer((_) async => [
              Client(
                id: 'pending-1',
                name: 'Previous',
                tenantId: 't1',
                registeredBy: 'u1',
                createdAt: DateTime(2026, 1, 1),
                syncStatus: SyncStatus.pending,
              ),
            ]);
    final p = build(online: true);

    await p.openTenant(tenantId: 't1', userId: 'u1');

    verify(() => sync.synchronize(userId: 'u1')).called(1);
  });

  test('opening a second room resets the list', () async {
    when(() => repo.fetchPage(tenantId: 't1', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 3));
    when(() => repo.fetchPage(tenantId: 't2', offset: 0, limit: 20))
        .thenAnswer((_) async => range(1, 1));
    when(() => repo.getUnsyncedLocally(tenantId: 't2', userId: 'u1'))
        .thenAnswer((_) async => []);
    final p = build();
    await p.openTenant(tenantId: 't1', userId: 'u1');
    expect(p.clients.length, 3);
    await p.openTenant(tenantId: 't2', userId: 'u1');
    expect(p.tenantId, 't2');
    expect(p.clients.length, 1);
  });
}
