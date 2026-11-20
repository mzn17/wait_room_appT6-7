/// A waiting room (tenant). Each room owns its own queue.
class Tenant {
  final String id;
  final String name;
  final String inviteCode;

  /// Role of the signed-in user inside this room: owner or member.
  final String role;
  final DateTime createdAt;

  const Tenant({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.role,
    required this.createdAt,
  });

  bool get isOwner => role == 'owner';

  /// Row returned by the create_tenant / join_tenant RPCs (flat shape).
  factory Tenant.fromRpcMap(Map<String, dynamic> map) => Tenant(
        id: map['id'].toString(),
        name: map['name'] as String,
        inviteCode: map['invite_code'] as String,
        role: (map['role'] as String?) ?? 'member',
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  /// Row from `tenant_members` with the embedded `tenants` relation.
  factory Tenant.fromMemberRow(Map<String, dynamic> row) {
    final embedded = row['tenants'];
    final data = embedded is Map
        ? Map<String, dynamic>.from(embedded)
        : Map<String, dynamic>.from(embedded as Map);
    return Tenant(
      id: data['id'].toString(),
      name: data['name'] as String,
      inviteCode: data['invite_code'] as String,
      role: (row['role'] as String?) ?? 'member',
      createdAt: DateTime.parse(data['created_at'] as String),
    );
  }
}
