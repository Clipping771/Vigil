/// Build-time configuration, injected with `--dart-define` or
/// `--dart-define-from-file=.env` (see .env.example). Nothing here is secret:
/// the Supabase anon key is public by design and access is enforced by RLS.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isValid => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
