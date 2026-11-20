import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/auth_status.dart';
import '../providers/auth_provider.dart';
import '../providers/tenant_provider.dart';
import '../widgets/loading_widget.dart';
import 'auth_screen.dart';
import 'queue_screen.dart';
import 'rooms_screen.dart';

/// Shows the sign-in screen or the app, depending on the Supabase session.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: LoadingWidget(message: 'Starting...'));
      case AuthStatus.unauthenticated:
        return const AuthScreen();
      case AuthStatus.authenticated:
        return const _TenantGate();
    }
  }
}

class _TenantGate extends StatefulWidget {
  const _TenantGate();

  @override
  State<_TenantGate> createState() => _TenantGateState();
}

class _TenantGateState extends State<_TenantGate> {
  String? _loadedFor;

  void _ensureLoaded(String? userId) {
    if (userId == null || _loadedFor == userId) return;
    _loadedFor = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TenantProvider>().loadForUser(userId: userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final tenants = context.watch<TenantProvider>();
    _ensureLoaded(auth.userId);

    if (_loadedFor != auth.userId) {
      return const Scaffold(
          body: LoadingWidget(message: 'Loading your rooms...'));
    }
    if (tenants.loading && tenants.tenants.isEmpty) {
      return const Scaffold(
          body: LoadingWidget(message: 'Loading your rooms...'));
    }
    if (tenants.tenants.isEmpty) {
      return const RoomsScreen();
    }
    if (tenants.currentTenant == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && tenants.tenants.isNotEmpty) {
          context.read<TenantProvider>().select(tenants.tenants.first);
        }
      });
      return const Scaffold(body: LoadingWidget(message: 'Opening room...'));
    }

    return QueueScreen(
      key: ValueKey(tenants.currentTenant!.id),
      tenant: tenants.currentTenant!,
    );
  }
}
