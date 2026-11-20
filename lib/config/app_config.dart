/// Either edit the defaults below, or pass
/// --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ukccdzypqyqshwxokxhp.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_IdnBxwk-Je0V9PCwWwNygg_0X0H9HuS',
  );
}
