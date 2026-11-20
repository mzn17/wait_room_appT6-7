import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/queue_provider.dart';
import 'providers/tenant_provider.dart';
import 'repositories/queue_repository.dart';
import 'repositories/tenant_repository.dart';
import 'screens/home_gate.dart';
import 'services/auth_service.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';
import 'services/sync_service.dart';
import 'storage/local_queue_storage.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    required this.connectivity,
    required this.queue,
    required this.auth,
    required this.tenants,
  });

  final ConnectivityProvider connectivity;
  final QueueProvider queue;
  final AuthProvider auth;
  final TenantProvider tenants;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: tenants),
        ChangeNotifierProvider.value(value: connectivity),
        ChangeNotifierProvider.value(value: queue),
      ],
      child: MaterialApp(
        title: 'Waiting Room',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const AuthGate(),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  final supabase = Supabase.instance.client;

  final storage = LocalQueueStorage();
  final repository = QueueRepository(supabase, storage);
  final syncService = SyncService(storage, repository);

  final connectivity = ConnectivityProvider(ConnectivityService(supabase));
  final auth = AuthProvider(AuthService(supabase));
  final tenants = TenantProvider(TenantRepository(supabase));

  final queue = QueueProvider(
    repository,
    GeolocationService(),
    syncService,
    isOnline: () => connectivity.isOnline,
  );

  // Signing out must clear every user-specific value from memory.
  auth.addListener(() {
    if (!auth.isAuthenticated) {
      tenants.reset();
      queue.reset();
    }
  });

  // Whenever the backend becomes reachable again, push pending registrations.
  var wasOnline = false;
  connectivity.addListener(() {
    final nowOnline = connectivity.isOnline;
    if (nowOnline && !wasOnline) queue.syncNow();
    wasOnline = nowOnline;
  });

  connectivity.initialize();

  runApp(MyApp(
    connectivity: connectivity,
    queue: queue,
    auth: auth,
    tenants: tenants,
  ));
}
