import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/queue_state.dart';
import '../models/tenant.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/client_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';
import '../widgets/queue_empty_widget.dart';
import 'members_screen.dart';
import 'rooms_screen.dart';

enum _QueueMenuAction { rooms, signOut }

class QueueScreen extends StatefulWidget {
  final Tenant tenant;

  const QueueScreen({super.key, required this.tenant});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _scroll = ScrollController();
  final _name = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        context.read<QueueProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRoom());
  }

  @override
  void didUpdateWidget(covariant QueueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenant.id != widget.tenant.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRoom());
    }
  }

  void _openRoom() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) return;
    if (_name.text.isEmpty) _name.text = auth.displayName;
    context.read<QueueProvider>().openTenant(
          tenantId: widget.tenant.id,
          userId: userId,
        );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final text = _name.text.trim();
    if (text.isEmpty || _submitting) {
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a name before joining.')),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    await context.read<QueueProvider>().register(text);
    if (!mounted) return;
    _name.clear();
    setState(() => _submitting = false);
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MembersScreen(tenant: widget.tenant),
      ),
    );
  }

  Future<void> _onMenu(_QueueMenuAction action) async {
    switch (action) {
      case _QueueMenuAction.rooms:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RoomsScreen()),
        );
        break;
      case _QueueMenuAction.signOut:
        await context.read<AuthProvider>().signOut();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<QueueProvider>();
    final connectivity = context.watch<ConnectivityProvider>();
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.tenant.name, overflow: TextOverflow.ellipsis),
            Text(
              '${auth.displayName} · ${widget.tenant.isOwner ? 'owner' : 'member'}',
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Members',
            onPressed: _openMembers,
            icon: const Icon(Icons.group_outlined),
          ),
          PopupMenuButton<_QueueMenuAction>(
            onSelected: _onMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _QueueMenuAction.rooms,
                child: ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('Switch room'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _QueueMenuAction.signOut,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(status: connectivity.status),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Room code: ${widget.tenant.inviteCode}',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _join(),
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _submitting ? null : _join,
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join'),
                ),
              ],
            ),
          ),
          Expanded(child: _body(queue, auth.userId)),
        ],
      ),
    );
  }

  Widget _body(QueueProvider queue, String? userId) {
    switch (queue.state) {
      case QueueState.initial:
      case QueueState.loading:
        return const LoadingWidget();
      case QueueState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(queue.errorMessage ?? 'Error'),
              TextButton(
                onPressed: queue.fetchInitialQueue,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      case QueueState.empty:
        return queue.pending.isEmpty
            ? const QueueEmptyWidget()
            : _list(queue, userId);
      default:
        return _list(queue, userId);
    }
  }

  Widget _list(QueueProvider queue, String? userId) {
    return RefreshIndicator(
      onRefresh: () => queue.fetchInitialQueue(silent: true),
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (queue.pending.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Not official yet (waiting to sync)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          for (final c in queue.pending)
            ClientCard(client: c, isMine: c.isMine(userId)),
          for (final c in queue.clients)
            ClientCard(client: c, isMine: c.isMine(userId)),
          if (queue.isLoadingMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
