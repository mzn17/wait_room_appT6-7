import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/client.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../storage/local_queue_storage.dart';

class SyncService {
  final LocalQueueStorage _storage;
  final QueueRepository _repository;
  bool _isSyncing = false;

  SyncService(this._storage, this._repository);

  /// Uploads the pending registrations of [userId] (all of their rooms).
  /// A null [userId] keeps the legacy behaviour and syncs every local row.
  Future<void> synchronize({String? userId}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      await _storage.resetStuckSyncing(userId: userId);
      final pending = await _storage.getPendingClients(userId: userId);

      for (final record in pending) {
        final id = record['id'] as String;
        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);
          await _repository.registerOnServer(Client.fromLocalMap(record));
          await _storage.deleteClient(id); // server now owns it
        } on PostgrestException {
          // Server rejected it: mark failed (still retried next time)
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        } catch (_) {
          // Network problem: not a real failure, try again later
          await _storage.updateSyncStatus(id, SyncStatus.pending);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
