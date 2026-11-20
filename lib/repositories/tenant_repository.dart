import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tenant.dart';
import '../models/tenant_member.dart';

/// Coordinates all tenant (waiting room) operations with Supabase.
class TenantRepository {
  final SupabaseClient _supabase;

  TenantRepository(this._supabase);

  static Tenant _firstTenantRow(dynamic data) {
    if (data is List && data.isNotEmpty) {
      return Tenant.fromRpcMap(Map<String, dynamic>.from(data.first as Map));
    }
    if (data is Map) {
      return Tenant.fromRpcMap(Map<String, dynamic>.from(data));
    }
    throw const PostgrestException(message: 'No room was returned.');
  }

  Future<List<Tenant>> fetchMyTenants() async {
    final rows = await _supabase
        .from('tenant_members')
        .select('role, joined_at, tenants(id, name, invite_code, created_at)')
        .order('joined_at', ascending: true);
    return rows
        .map<Tenant>((row) => Tenant.fromMemberRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<Tenant> createTenant(String name) async {
    final data = await _supabase.rpc(
      'create_tenant',
      params: {'p_name': name.trim()},
    );
    return _firstTenantRow(data);
  }

  Future<Tenant> joinTenant(String inviteCode) async {
    final data = await _supabase.rpc(
      'join_tenant',
      params: {'p_invite_code': inviteCode.trim().toUpperCase()},
    );
    return _firstTenantRow(data);
  }

  Future<List<TenantMember>> fetchMembers(String tenantId) async {
    final data = await _supabase.rpc(
      'list_tenant_members',
      params: {'p_tenant_id': tenantId},
    );
    final rows = data is List ? data : const [];
    return rows
        .map<TenantMember>((row) => TenantMember.fromRpcMap(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  Future<void> addMember({
    required String tenantId,
    required String email,
    String role = 'member',
  }) async {
    await _supabase.rpc('add_tenant_member', params: {
      'p_tenant_id': tenantId,
      'p_email': email.trim(),
      'p_role': role,
    });
  }

  Future<void> removeMember({
    required String tenantId,
    required String userId,
  }) async {
    await _supabase.rpc('remove_tenant_member', params: {
      'p_tenant_id': tenantId,
      'p_user_id': userId,
    });
  }
}
