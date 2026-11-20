import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/tenant.dart';
import '../models/tenant_member.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/loading_widget.dart';

/// Multi-user management for one waiting room.
class MembersScreen extends StatefulWidget {
  final Tenant tenant;

  const MembersScreen({super.key, required this.tenant});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<TenantMember> _members = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members =
          await context.read<TenantProvider>().fetchMembers(widget.tenant.id);
      if (!mounted) return;
      setState(() => _members = members);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load members.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMember() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a member'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email of an existing account',
            hintText: 'person@example.com',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (email == null || !mounted || email.trim().isEmpty) return;

    final error = await context.read<TenantProvider>().addMember(
          tenantId: widget.tenant.id,
          email: email,
        );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Member added')),
    );
    await _load();
  }

  Future<void> _removeMember(TenantMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          '${member.displayName} (${member.email}) will lose access to '
          '${widget.tenant.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await context.read<TenantProvider>().removeMember(
          tenantId: widget.tenant.id,
          userId: member.userId,
        );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          if (widget.tenant.isOwner)
            IconButton(
              tooltip: 'Add member',
              onPressed: _addMember,
              icon: const Icon(Icons.person_add_alt_1),
            ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: Text(widget.tenant.name),
            subtitle: Text(
              widget.tenant.isOwner
                  ? 'You manage this room'
                  : 'You are a member of this room',
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _body(currentUserId)),
        ],
      ),
    );
  }

  Widget _body(String? currentUserId) {
    if (_loading && _members.isEmpty) {
      return const LoadingWidget(message: 'Loading members...');
    }
    if (_error != null && _members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _members.length,
        itemBuilder: (context, index) {
          final member = _members[index];
          final isMe = member.userId == currentUserId;
          final canRemove = widget.tenant.isOwner && !member.isOwner;
          return ListTile(
            leading: CircleAvatar(
              child: Text(
                member.displayName.isEmpty
                    ? '?'
                    : member.displayName.characters.first.toUpperCase(),
              ),
            ),
            title: Row(
              children: [
                Flexible(child: Text(member.displayName)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  const Text('(you)',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ],
              ],
            ),
            subtitle: Text(member.email),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text(
                    member.isOwner ? 'Owner' : 'Member',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => _removeMember(member),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
