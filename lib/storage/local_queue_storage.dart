import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/sync_status.dart';

class LocalQueueStorage {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final path = join(await getDatabasesPath(), 'waiting_queue.db');
    _database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE clients (
            id TEXT PRIMARY KEY,
            tenant_id TEXT,
            registered_by TEXT,
            name TEXT NOT NULL,
            lat REAL,
            lng REAL,
            location_accuracy_m REAL,
            created_at TEXT NOT NULL,
            sync_status TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_clients_owner '
          'ON clients(sync_status, tenant_id, registered_by)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Pending rows are now scoped to a room and to their auth user.
          await db.execute('ALTER TABLE clients ADD COLUMN tenant_id TEXT');
          await db.execute('ALTER TABLE clients ADD COLUMN registered_by TEXT');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_clients_owner '
            'ON clients(sync_status, tenant_id, registered_by)',
          );
        }
      },
    );
    return _database!;
  }

  Future<void> saveClient(Map<String, dynamic> client) async {
    final db = await database;
    await db.insert('clients', client,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pending registrations for one user in one room (shown in the UI).
  Future<List<Map<String, dynamic>>> getUnsyncedClients({
    required String tenantId,
    required String userId,
  }) async {
    final db = await database;
    return db.query(
      'clients',
      where: 'sync_status != ? AND tenant_id = ? AND registered_by = ?',
      whereArgs: ['synced', tenantId, userId],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  /// Records to upload: pending + failed (retry).
  /// When [userId] is given, only that user's registrations are returned.
  Future<List<Map<String, dynamic>>> getPendingClients({String? userId}) async {
    final db = await database;
    if (userId == null) {
      return db.query(
        'clients',
        where: 'sync_status = ? OR sync_status = ?',
        whereArgs: ['pending', 'failed'],
        orderBy: 'created_at ASC, id ASC',
      );
    }
    return db.query(
      'clients',
      where: '(sync_status = ? OR sync_status = ?) AND registered_by = ?',
      whereArgs: ['pending', 'failed', userId],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    final db = await database;
    await db.update('clients', {'sync_status': status.name},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Once the server owns the record, the local copy is removed
  /// so the official entry comes only from Supabase (no duplicates).
  Future<void> deleteClient(String id) async {
    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  /// Records stuck in "syncing" after an app crash go back to "pending".
  Future<void> resetStuckSyncing({String? userId}) async {
    final db = await database;
    await db.update(
      'clients',
      {'sync_status': SyncStatus.pending.name},
      where: userId == null
          ? 'sync_status = ?'
          : 'sync_status = ? AND registered_by = ?',
      whereArgs: userId == null ? ['syncing'] : ['syncing', userId],
    );
  }
}
