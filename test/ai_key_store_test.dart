import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vigil/providers/settings_provider.dart';
import 'package:vigil/services/ai_key_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'test');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppSettings> settingsFor(String? userId) async {
    final notifier = SettingsNotifier(null, userId);
    addTearDown(notifier.dispose);
    late AppSettings latest;
    notifier.addListener((settings) => latest = settings);
    await pumpEventQueue();
    return latest;
  }

  test('one user cannot load another user\'s key', () async {
    await AiKeyStore.save('user-a', 'Claude', 'secret-a');

    expect((await settingsFor('user-a')).claudeApiKey, 'secret-a');
    expect((await settingsFor('user-b')).claudeApiKey, isEmpty);
    expect((await settingsFor(null)).claudeApiKey, isEmpty);
  });

  test('keys saved through the settings belong to the signed-in user', () async {
    final notifier = SettingsNotifier(null, 'user-a');
    addTearDown(notifier.dispose);
    await pumpEventQueue();
    await notifier.updateAiProvider('Gemini');
    await notifier.updateApiKey('  secret-a  ');

    expect((await AiKeyStore.load('user-a'))['Gemini'], 'secret-a');
    expect((await AiKeyStore.load('user-b'))['Gemini'], isEmpty);
  });

  test('sign-out clears every key and keeps other preferences', () async {
    await AiKeyStore.save('user-a', 'Gemini', 'secret-a');
    await AiKeyStore.save('user-b', 'ChatGPT', 'secret-b');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', 'Claude');

    await AiKeyStore.clear();

    expect((await AiKeyStore.load('user-a'))['Gemini'], isEmpty);
    expect((await AiKeyStore.load('user-b'))['ChatGPT'], isEmpty);
    expect(prefs.getString('ai_provider'), 'Claude');
  });

  test('keys saved before they were per-user are removed', () async {
    SharedPreferences.setMockInitialValues({'ai_key_gemini': 'old-secret'});

    final keys = await AiKeyStore.load('user-a');

    expect(keys['Gemini'], isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_key_gemini'), isNull);
  });
}
