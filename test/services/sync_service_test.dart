import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room/models/client.dart';
import 'package:waiting_room/models/sync_status.dart';
import 'package:waiting_room/repositories/queue_repository.dart';
import 'package:waiting_room/services/sync_service.dart';
import 'package:waiting_room/storage/local_queue_storage.dart';

class MockStorage extends Mock implements LocalQueueStorage {}

class MockRepo extends Mock implements QueueRepository {}

class FakeClient extends Fake implements Client {}

final record = {
  'id': 'abc',
  'tenant_id': 'room-1',
  'registered_by': 'user-1',
  'name': 'Ali',
  'lat': null,
  'lng': null,
  'location_accuracy_m': null,
  'created_at': '2026-01-01T10:00:00.000Z',
  'sync_status': 'pending',
};

void main() {
  late MockStorage storage;
  late MockRepo repo;
  late SyncService sync;

  setUpAll(() {
    registerFallbackValue(FakeClient());
    registerFallbackValue(SyncStatus.pending);
  });

  setUp(() {
    storage = MockStorage();
    repo = MockRepo();
    sync = SyncService(storage, repo);
    when(() => storage.resetStuckSyncing(userId: null))
        .thenAnswer((_) async {});
    when(() => storage.updateSyncStatus(any(), any())).thenAnswer((_) async {});
    when(() => storage.deleteClient(any())).thenAnswer((_) async {});
    when(() => storage.getPendingClients(userId: null))
        .thenAnswer((_) async => [record]);
  });

  test('removes the local copy after a successful upload', () async {
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {});
    await sync.synchronize();
    verify(() => storage.deleteClient('abc')).called(1);
  });

  test('uploads the room and user attached to the local row', () async {
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {});
    await sync.synchronize();
    final client = verify(() => repo.registerOnServer(captureAny()))
        .captured
        .single as Client;
    expect(client.tenantId, 'room-1');
    expect(client.registeredBy, 'user-1');
  });

  test('network error returns the record to pending', () async {
    when(() => repo.registerOnServer(any())).thenThrow(Exception('offline'));
    await sync.synchronize();
    verify(() => storage.updateSyncStatus('abc', SyncStatus.pending)).called(1);
    verifyNever(() => storage.deleteClient(any()));
  });

  test('server rejection marks the record failed', () async {
    when(() => repo.registerOnServer(any()))
        .thenThrow(const PostgrestException(message: 'rejected'));
    await sync.synchronize();
    verify(() => storage.updateSyncStatus('abc', SyncStatus.failed)).called(1);
  });

  test('scopes the sync to the signed-in user', () async {
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {});
    when(() => storage.resetStuckSyncing(userId: 'user-1'))
        .thenAnswer((_) async {});
    when(() => storage.getPendingClients(userId: 'user-1'))
        .thenAnswer((_) async => [record]);
    await sync.synchronize(userId: 'user-1');
    verify(() => storage.getPendingClients(userId: 'user-1')).called(1);
    verify(() => storage.resetStuckSyncing(userId: 'user-1')).called(1);
  });

  test('a second call during a running sync is ignored', () async {
    when(() => repo.registerOnServer(any())).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    final first = sync.synchronize();
    await sync.synchronize();
    await first;
    verify(() => repo.registerOnServer(any())).called(1);
  });
}
