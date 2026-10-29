import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

/// Default model per provider, used until the user fetches and picks one.
const defaultAiModels = {
  'Gemini': 'gemini-2.5-flash',
  'ChatGPT': 'gpt-4o-mini',
  'Claude': 'claude-haiku-5-5',
};

const _claudeFallbackModels = ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'];

class AppSettings {
  // Organization-wide compliance rules (stored in `organization_settings`).
  final int allowedLateMinutes;
  final int allowedOvertimeMinutes;
  final bool autoReportingEnabled;
  final String reportFrequency;
  final String? deliveryEmail;
  final bool isSaving;

  // AI assistant (bring-your-own-key, stored only on this device).
  final String aiProvider;
  final String geminiApiKey;
  final String chatGptApiKey;
  final String claudeApiKey;
  final String? selectedModel;
  final List<String> availableModels;
  final bool isFetchingModels;

  const AppSettings({
    this.allowedLateMinutes = 15,
    this.allowedOvertimeMinutes = 30,
    this.autoReportingEnabled = false,
    this.reportFrequency = 'Weekly',
    this.deliveryEmail,
    this.isSaving = false,
    this.aiProvider = 'Gemini',
    this.geminiApiKey = '',
    this.chatGptApiKey = '',
    this.claudeApiKey = '',
    this.selectedModel,
    this.availableModels = const [],
    this.isFetchingModels = false,
  });

  String get activeApiKey => switch (aiProvider) {
        'ChatGPT' => chatGptApiKey,
        'Claude' => claudeApiKey,
        _ => geminiApiKey,
      };

  String get activeModel => selectedModel ?? defaultAiModels[aiProvider]!;

  AppSettings copyWith({
    int? allowedLateMinutes,
    int? allowedOvertimeMinutes,
    bool? autoReportingEnabled,
    String? reportFrequency,
    String? deliveryEmail,
    bool? isSaving,
    String? aiProvider,
    String? geminiApiKey,
    String? chatGptApiKey,
    String? claudeApiKey,
    String? Function()? selectedModel,
    List<String>? availableModels,
    bool? isFetchingModels,
  }) {
    return AppSettings(
      allowedLateMinutes: allowedLateMinutes ?? this.allowedLateMinutes,
      allowedOvertimeMinutes: allowedOvertimeMinutes ?? this.allowedOvertimeMinutes,
      autoReportingEnabled: autoReportingEnabled ?? this.autoReportingEnabled,
      reportFrequency: reportFrequency ?? this.reportFrequency,
      deliveryEmail: deliveryEmail ?? this.deliveryEmail,
      isSaving: isSaving ?? this.isSaving,
      aiProvider: aiProvider ?? this.aiProvider,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      chatGptApiKey: chatGptApiKey ?? this.chatGptApiKey,
      claudeApiKey: claudeApiKey ?? this.claudeApiKey,
      selectedModel: selectedModel != null ? selectedModel() : this.selectedModel,
      availableModels: availableModels ?? this.availableModels,
      isFetchingModels: isFetchingModels ?? this.isFetchingModels,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._organizationId) : super(const AppSettings()) {
    _loadLocal();
    _loadOrganizationSettings();
  }

  final String? _organizationId;
  final _supabase = Supabase.instance.client;

  static const _kProvider = 'ai_provider';
  static const _kModel = 'ai_model';
  static String _keyFor(String provider) => 'ai_key_${provider.toLowerCase()}';

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      state = state.copyWith(
        aiProvider: prefs.getString(_kProvider) ?? state.aiProvider,
        geminiApiKey: prefs.getString(_keyFor('Gemini')) ?? '',
        chatGptApiKey: prefs.getString(_keyFor('ChatGPT')) ?? '',
        claudeApiKey: prefs.getString(_keyFor('Claude')) ?? '',
        selectedModel: () => prefs.getString(_kModel),
      );
    } catch (e) {
      debugPrint('Could not load local settings: $e');
    }
  }

  Future<void> _loadOrganizationSettings() async {
    if (_organizationId == null) return;
    try {
      final row = await _supabase
          .from('organization_settings')
          .select()
          .eq('organization_id', _organizationId)
          .maybeSingle();
      if (row == null || !mounted) return;
      state = state.copyWith(
        allowedLateMinutes: (row['allowed_late_minutes'] as num?)?.toInt(),
        allowedOvertimeMinutes: (row['allowed_overtime_minutes'] as num?)?.toInt(),
        autoReportingEnabled: row['auto_reporting_enabled'] as bool?,
        reportFrequency: row['report_frequency'] as String?,
        deliveryEmail: row['delivery_email'] as String?,
      );
    } catch (e) {
      debugPrint('Could not load organization settings: $e');
    }
  }

  /// Persists a change to the organization's compliance settings. The local
  /// state is updated optimistically and rolled back if the write is rejected.
  Future<void> _saveOrganizationSettings(AppSettings next) async {
    final previous = state;
    state = next.copyWith(isSaving: true);
    if (_organizationId == null) {
      state = state.copyWith(isSaving: false);
      return;
    }
    try {
      await _supabase.from('organization_settings').upsert({
        'organization_id': _organizationId,
        'allowed_late_minutes': next.allowedLateMinutes,
        'allowed_overtime_minutes': next.allowedOvertimeMinutes,
        'auto_reporting_enabled': next.autoReportingEnabled,
        'report_frequency': next.reportFrequency,
        'delivery_email': next.deliveryEmail,
      });
      if (mounted) state = state.copyWith(isSaving: false);
    } catch (e) {
      if (mounted) state = previous;
      rethrow;
    }
  }

  Future<void> updateLateMinutes(int minutes) =>
      _saveOrganizationSettings(state.copyWith(allowedLateMinutes: minutes.clamp(0, 240)));

  Future<void> updateOvertimeMinutes(int minutes) =>
      _saveOrganizationSettings(state.copyWith(allowedOvertimeMinutes: minutes.clamp(0, 600)));

  Future<void> toggleAutoReporting(bool enabled) =>
      _saveOrganizationSettings(state.copyWith(autoReportingEnabled: enabled));

  Future<void> updateReportFrequency(String frequency) =>
      _saveOrganizationSettings(state.copyWith(reportFrequency: frequency));

  Future<void> updateDeliveryEmail(String email) =>
      _saveOrganizationSettings(state.copyWith(deliveryEmail: email.trim()));

  Future<void> updateAiProvider(String provider) async {
    state = state.copyWith(aiProvider: provider, availableModels: [], selectedModel: () => null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProvider, provider);
    await prefs.remove(_kModel);
  }

  Future<void> updateApiKey(String key) async {
    final trimmed = key.trim();
    state = switch (state.aiProvider) {
      'ChatGPT' => state.copyWith(chatGptApiKey: trimmed),
      'Claude' => state.copyWith(claudeApiKey: trimmed),
      _ => state.copyWith(geminiApiKey: trimmed),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(state.aiProvider), trimmed);
  }

  Future<void> updateSelectedModel(String? model) async {
    state = state.copyWith(selectedModel: () => model);
    final prefs = await SharedPreferences.getInstance();
    if (model == null) {
      await prefs.remove(_kModel);
    } else {
      await prefs.setString(_kModel, model);
    }
  }

  /// Lists the models available for the active provider and API key.
  Future<void> fetchModels() async {
    state = state.copyWith(isFetchingModels: true, availableModels: []);
    try {
      final apiKey = state.activeApiKey;
      if (apiKey.isEmpty) throw Exception('Enter an API key first');
      List<String> models;
      switch (state.aiProvider) {
        case 'Gemini':
          final response = await http.get(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models'),
            headers: {'x-goog-api-key': apiKey},
          );
          if (response.statusCode != 200) throw Exception('Invalid Gemini API key');
          final data = jsonDecode(response.body);
          models = (data['models'] as List)
              .where((m) => (m['supportedGenerationMethods'] as List?)?.contains('generateContent') ?? true)
              .map((m) => m['name'].toString().replaceFirst('models/', ''))
              .toList();
        case 'ChatGPT':
          final response = await http.get(
            Uri.parse('https://api.openai.com/v1/models'),
            headers: {'Authorization': 'Bearer $apiKey'},
          );
          if (response.statusCode != 200) throw Exception('Invalid OpenAI API key');
          final data = jsonDecode(response.body);
          models = (data['data'] as List).map((m) => m['id'].toString()).where((id) => id.startsWith('gpt')).toList()
            ..sort();
        default:
          final response = await http.get(
            Uri.parse('https://api.anthropic.com/v1/models'),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'anthropic-dangerous-direct-browser-access': 'true',
            },
          );
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            models = (data['data'] as List).map((m) => m['id'].toString()).toList();
          } else if (response.statusCode == 401) {
            throw Exception('Invalid Anthropic API key');
          } else {
            models = _claudeFallbackModels;
          }
      }
      state = state.copyWith(availableModels: models);
    } finally {
      state = state.copyWith(isFetchingModels: false);
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final orgId = ref.watch(authProvider.select((s) => s.currentUser?.organizationId));
  return SettingsNotifier(orgId);
});
