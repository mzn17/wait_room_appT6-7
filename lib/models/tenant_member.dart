/// A member of a waiting room, as exposed by the list_tenant_members RPC.
class TenantMember {
  final String userId;
  final String email;
  final String displayName;
  final String role;
  final DateTime joinedAt;

  const TenantMember({
    required this.userId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.joinedAt,
  });

  bool get isOwner => role == 'owner';

  factory TenantMember.fromRpcMap(Map<String, dynamic> map) => TenantMember(
        userId: map['user_id'].toString(),
        email: (map['email'] as String?) ?? '',
        displayName: (map['display_name'] as String?) ?? '',
        role: (map['role'] as String?) ?? 'member',
        joinedAt: DateTime.parse(map['joined_at'] as String),
      );
}
