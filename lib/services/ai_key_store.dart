import 'package:shared_preferences/shared_preferences.dart';

/// AI provider API keys kept on this device, separately for each user and only
/// until they sign out, so the next person on a shared device cannot use them.
class AiKeyStore {
  static const _prefix = 'ai_key_';
  static const _providers = ['Gemini', 'ChatGPT', 'Claude'];

  static String _name(String userId, String provider) => '$_prefix${userId}_${provider.toLowerCase()}';

  /// The saved keys of [userId], by provider. Also removes keys saved before
  /// they were per-user, since it is unknown whose those are.
  static Future<Map<String, String>> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final provider in _providers) {
      await prefs.remove('$_prefix${provider.toLowerCase()}');
    }
    return {
      for (final provider in _providers) provider: prefs.getString(_name(userId, provider)) ?? '',
    };
  }

  static Future<void> save(String userId, String provider, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_name(userId, provider), key);
  }

  /// Removes every saved key on this device, whoever saved it.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final name in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(name);
    }
  }
}
