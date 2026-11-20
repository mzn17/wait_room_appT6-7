import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room/models/client.dart';
import 'package:waiting_room/models/sync_status.dart';

void main() {
  group('Client', () {
    test('without location reports hasLocation false', () {
      final c = Client(id: '1', name: 'T', createdAt: DateTime.now());
      expect(c.hasLocation, isFalse);
      expect(c.locationText, 'Location not captured');
    });

    test('toLocalMap keeps accuracy and syncStatus', () {
      final c = Client(
        id: '1',
        name: 'T',
        lat: 36.8065,
        lng: 10.1815,
        locationAccuracy: 5.5,
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );
      final m = c.toLocalMap();
      expect(m['location_accuracy_m'], 5.5);
      expect(m['sync_status'], 'pending');
    });

    test('toSupabaseMap excludes sync_status', () {
      final c = Client(
          id: '1',
          name: 'T',
          createdAt: DateTime.now(),
          syncStatus: SyncStatus.pending);
      expect(c.toSupabaseMap().containsKey('sync_status'), isFalse);
    });

    test('fromSupabaseMap reads queue number and never has coordinates', () {
      final c = Client.fromSupabaseMap({
        'id': 'abc',
        'name': 'Ali',
        'queue_number': 7,
        'has_location': true,
        'created_at': '2026-01-01T10:00:00Z',
      });
      expect(c.queueNumber, 7);
      expect(c.hasLocation, isTrue);
      expect(c.lat, isNull);
      expect(c.syncStatus, SyncStatus.synced);
    });

    test('fromLocalMap falls back to pending on unknown status', () {
      final c = Client.fromLocalMap({
        'id': '1',
        'name': 'T',
        'created_at': '2026-01-01T10:00:00Z',
        'sync_status': 'weird',
      });
      expect(c.syncStatus, SyncStatus.pending);
    });

    test('local map keeps the room and the auth user', () {
      final c = Client(
        id: '1',
        name: 'T',
        tenantId: 'room-1',
        registeredBy: 'user-1',
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final map = c.toLocalMap();

      expect(map['tenant_id'], 'room-1');
      expect(map['registered_by'], 'user-1');
      expect(c.isMine('user-1'), isTrue);
      expect(c.isMine('user-2'), isFalse);
    });

    test('fromSupabaseMap reads the room and owner', () {
      final c = Client.fromSupabaseMap({
        'id': 'abc',
        'tenant_id': 'room-1',
        'registered_by': 'user-1',
        'name': 'Ali',
        'queue_number': 7,
        'has_location': false,
        'created_at': '2026-01-01T10:00:00Z',
      });

      expect(c.tenantId, 'room-1');
      expect(c.registeredBy, 'user-1');
      expect(c.isMine('user-1'), isTrue);
    });
  });
}
