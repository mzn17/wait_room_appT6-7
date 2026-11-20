import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/tenant.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/loading_widget.dart';

/// Lists the rooms of the signed-in user, and lets them create or join one.
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  Future<String?> _askForText(
    BuildContext context, {
    required String title,
    required String label,
    required String hint,
    required String action,
    bool upperCase = false,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: upperCase
              ? TextCapitalization.characters
              : TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _afterSelection(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  Future<void> _create(BuildContext context) async {
    final provider = context.read<TenantProvider>();
    final name = await _askForText(
      context,
      title: 'Create a waiting room',
      label: 'Room name',
      hint: 'e.g. Clinic - Morning',
      action: 'Create',
    );
    if (name == null || !context.mounted) return;
    final ok = await provider.createTenant(name);
    if (!context.mounted) return;
    if (ok) {
      _afterSelection(context);
    } else if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage!)),
      );
    }
  }

  Future<void> _join(BuildContext context) async {
    final provider = context.read<TenantProvider>();
    final code = await _askForText(
      context,
      title: 'Join a waiting room',
      label: 'Invite code',
      hint: 'ABCD1234',
      action: 'Join',
      upperCase: true,
    );
    if (code == null || !context.mounted) return;
    final ok = await provider.joinTenant(code);
    if (!context.mounted) return;
    if (ok) {
      _afterSelection(context);
    } else if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage!)),
      );
    }
  }

  Future<void> _copyCode(BuildContext context, Tenant tenant) async {
    await Clipboard.setData(ClipboardData(text: tenant.inviteCode));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenants = context.watch<TenantProvider>();
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            tenants.tenants.isEmpty ? 'Find a waiting room' : 'Your rooms'),
      ),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  auth.displayName.isEmpty
                      ? '?'
                      : auth.displayName.characters.first.toUpperCase(),
                ),
              ),
              title: Text(auth.displayName),
              subtitle: Text(auth.email),
            ),
          ),
          if (tenants.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tenants.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(child: _body(context, tenants)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: tenants.busy ? null : () => _join(context),
                      icon: const Icon(Icons.login),
                      label: const Text('Join with a code'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: tenants.busy ? null : () => _create(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Create a room'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, TenantProvider tenants) {
    if (tenants.loading && tenants.tenants.isEmpty) {
      return const LoadingWidget(message: 'Loading your rooms...');
    }
    if (tenants.tenants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'No waiting room yet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your own room, or join one with the invite code '
                'shared by its owner.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: tenants.loading ? null : () => tenants.loadForUser(),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => tenants.loadForUser(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: tenants.tenants.length,
        itemBuilder: (context, index) {
          final tenant = tenants.tenants[index];
          final selected = tenants.currentTenant?.id == tenant.id;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              selected: selected,
              leading: CircleAvatar(
                child: Icon(
                  tenant.isOwner ? Icons.admin_panel_settings : Icons.group,
                ),
              ),
              title: Text(
                tenant.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Row(
                children: [
                  Text(tenant.isOwner ? 'Owner' : 'Member'),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Code: ${tenant.inviteCode}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                tooltip: 'Copy invite code',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copyCode(context, tenant),
              ),
              onTap: () {
                tenants.select(tenant);
                _afterSelection(context);
              },
            ),
          );
        },
      ),
    );
  }
}
