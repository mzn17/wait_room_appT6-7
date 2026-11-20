import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room/models/tenant.dart';

void main() {
  group('Tenant', () {
    test('reads a room returned by the create/join RPC', () {
      final tenant = Tenant.fromRpcMap({
        'id': 'room-1',
        'name': 'Clinic',
        'invite_code': 'ABCD1234',
        'role': 'owner',
        'created_at': '2026-01-01T10:00:00Z',
      });
      expect(tenant.id, 'room-1');
      expect(tenant.name, 'Clinic');
      expect(tenant.inviteCode, 'ABCD1234');
      expect(tenant.isOwner, isTrue);
    });

    test('reads the embedded tenants relation from tenant_members', () {
      final tenant = Tenant.fromMemberRow({
        'role': 'member',
        'tenants': {
          'id': 'room-2',
          'name': 'Pharmacy',
          'invite_code': 'ZZZZ9999',
          'created_at': '2026-02-01T10:00:00Z',
        },
      });
      expect(tenant.id, 'room-2');
      expect(tenant.name, 'Pharmacy');
      expect(tenant.role, 'member');
      expect(tenant.isOwner, isFalse);
    });
  });
}
