import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client.dart';
import '../storage/local_queue_storage.dart';

class QueueRepository {
  final SupabaseClient _supabase;
  final LocalQueueStorage _local;

  QueueRepository(this._supabase, this._local);

  static const _publicColumns =
      'id, tenant_id, registered_by, name, queue_number, has_location, created_at';

  /// Official queue of one room, ordered by the server-assigned queue number.
  Future<List<Client>> fetchPage({
    required String tenantId,
    required int offset,
    required int limit,
  }) async {
    final rows = await _supabase
        .from('clients')
        .select(_publicColumns)
        .eq('tenant_id', tenantId)
        .order('queue_number', ascending: true)
        .range(offset, offset + limit - 1);
    return rows.map<Client>((r) => Client.fromSupabaseMap(r)).toList();
  }

  /// Idempotent: the RPC ignores an id it already knows.
  Future<void> registerOnServer(Client client) async {
    final tenantId = client.tenantId;
    if (tenantId == null || tenantId.isEmpty) {
      throw const PostgrestException(message: 'Missing waiting room id');
    }
    await _supabase.rpc('register_queue_client', params: {
      'p_tenant_id': tenantId,
      'p_id': client.id,
      'p_name': client.name,
      'p_lat': client.lat,
      'p_lng': client.lng,
      'p_accuracy': client.locationAccuracy,
      'p_requested_at': client.createdAt.toUtc().toIso8601String(),
    });
  }

  Future<void> saveLocally(Client client) =>
      _local.saveClient(client.toLocalMap());

  Future<List<Client>> getUnsyncedLocally({
    required String tenantId,
    required String userId,
  }) async {
    final rows = await _local.getUnsyncedClients(
      tenantId: tenantId,
      userId: userId,
    );
    return rows.map(Client.fromLocalMap).toList();
  }

  RealtimeChannel subscribeToInserts({
    required String tenantId,
    required void Function(Client) onInsert,
  }) {
    return _supabase
        .channel('public:clients:$tenantId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'clients',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'tenant_id',
            value: tenantId,
          ),
          callback: (payload) =>
              onInsert(Client.fromSupabaseMap(payload.newRecord)),
        )
        .subscribe();
  }
}
