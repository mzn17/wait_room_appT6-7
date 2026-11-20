import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectivityService {
  final Connectivity _connectivity;
  final SupabaseClient _supabase;

  ConnectivityService(this._supabase, {Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Stream<bool> get networkChanges => _connectivity.onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  Future<bool> isSupabaseAvailable() async {
    try {
      await _supabase.rpc('health_check').timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }
}
