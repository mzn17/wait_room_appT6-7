import 'package:flutter/material.dart';
import '../models/client.dart';
import '../models/sync_status.dart';

class ClientCard extends StatelessWidget {
  final Client client;
  final bool isMine;

  const ClientCard({super.key, required this.client, this.isMine = false});

  bool get _isOfficial => client.syncStatus == SyncStatus.synced;

  String get _syncLabel => switch (client.syncStatus) {
        SyncStatus.pending => 'Waiting to sync',
        SyncStatus.syncing => 'Syncing...',
        SyncStatus.failed => 'Sync failed, will retry',
        SyncStatus.synced => '',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: client.queueNumber != null
              ? Text('${client.queueNumber}')
              : const Icon(Icons.hourglass_empty),
        ),
        title: Row(
          children: [
            Flexible(child: Text(client.name)),
            if (isMine) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('You', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        ),
        subtitle: Text(
          _isOfficial
              ? client.locationText
              : '$_syncLabel · ${client.locationText}',
        ),
        trailing: _isOfficial
            ? Icon(
                client.hasLocation ? Icons.location_on : Icons.location_off,
                color: client.hasLocation ? Colors.green : Colors.grey,
              )
            : const Icon(Icons.cloud_upload_outlined, color: Colors.orange),
      ),
    );
  }
}
