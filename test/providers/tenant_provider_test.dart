import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waiting_room/models/tenant.dart';
import 'package:waiting_room/models/tenant_member.dart';
import 'package:waiting_room/providers/tenant_provider.dart';
import 'package:waiting_room/repositories/tenant_repository.dart';

class MockTenantRepository extends Mock implements TenantRepository {}

Tenant tenant(String id, {String role = 'member'}) => Tenant(
      id: id,
      name: 'Room $id',
      inviteCode: 'CODE$id',
      role: role,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockTenantRepository repo;
  late TenantProvider provider;

  setUp(() {
    repo = MockTenantRepository();
    provider = TenantProvider(repo);
  });

  test('loads rooms and selects the first one', () async {
    final rooms = [tenant('a', role: 'owner'), tenant('b')];
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => rooms);

    await provider.loadForUser(userId: 'u1');

    expect(provider.tenants.length, 2);
    expect(provider.currentTenant?.id, 'a');
    expect(provider.loading, isFalse);
  });

  test('keeps the current room across a refresh', () async {
    final rooms = [tenant('a'), tenant('b')];
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => rooms);
    await provider.loadForUser(userId: 'u1');
    provider.select(rooms.last);

    await provider.loadForUser(userId: 'u2');

    expect(provider.currentTenant?.id, 'b');
  });

  test('does not reload the same user when rooms are already loaded', () async {
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => [tenant('a')]);
    await provider.loadForUser(userId: 'u1');
    await provider.loadForUser(userId: 'u1');
    verify(() => repo.fetchMyTenants()).called(1);
  });

  test('creating a room selects it immediately', () async {
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => []);
    when(() => repo.createTenant('Clinic'))
        .thenAnswer((_) async => tenant('new', role: 'owner'));
    await provider.loadForUser(userId: 'u1');

    final ok = await provider.createTenant('Clinic');

    expect(ok, isTrue);
    expect(provider.currentTenant?.id, 'new');
    expect(provider.tenants.single.name, 'Room new');
  });

  test('joining a room selects it and does not duplicate it', () async {
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => [tenant('a')]);
    when(() => repo.joinTenant('codeb')).thenAnswer((_) async => tenant('b'));
    await provider.loadForUser(userId: 'u1');

    final ok = await provider.joinTenant('codeb');

    expect(ok, isTrue);
    expect(provider.currentTenant?.id, 'b');
    expect(provider.tenants.length, 2);
  });

  test('join failure exposes the server message', () async {
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => []);
    when(() => repo.joinTenant(any()))
        .thenThrow(const PostgrestException(message: 'Invalid invite code'));
    await provider.loadForUser(userId: 'u1');

    final ok = await provider.joinTenant('nope');

    expect(ok, isFalse);
    expect(provider.errorMessage, 'Invalid invite code');
  });

  test('addMember returns an error instead of throwing', () async {
    when(() => repo.addMember(
          tenantId: 'a',
          email: 'missing@example.com',
        )).thenThrow(const PostgrestException(message: 'No account found'));

    final error = await provider.addMember(
      tenantId: 'a',
      email: 'missing@example.com',
    );

    expect(error, 'No account found');
  });

  test('fetchMembers maps the roster', () async {
    when(() => repo.fetchMembers('a')).thenAnswer((_) async => [
          TenantMember(
            userId: 'u1',
            email: 'owner@example.com',
            displayName: 'Owner',
            role: 'owner',
            joinedAt: DateTime(2026, 1, 1),
          ),
        ]);

    final members = await provider.fetchMembers('a');

    expect(members.single.displayName, 'Owner');
    expect(members.single.isOwner, isTrue);
  });

  test('reset clears rooms and the current selection', () async {
    when(() => repo.fetchMyTenants()).thenAnswer((_) async => [tenant('a')]);
    await provider.loadForUser(userId: 'u1');

    provider.reset();

    expect(provider.tenants, isEmpty);
    expect(provider.currentTenant, isNull);
  });
}
