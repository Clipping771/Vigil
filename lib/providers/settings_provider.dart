import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppSettings {
  final int allowedLateMinutes;
  final int allowedOvertimeMinutes;
  final bool autoReportingEnabled;
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
    this.aiProvider = 'Gemini',
    this.geminiApiKey = '',
    this.chatGptApiKey = '',
    this.claudeApiKey = '',
    this.selectedModel,
    this.availableModels = const [],
    this.isFetchingModels = false,
  });

  AppSettings copyWith({
    int? allowedLateMinutes,
    int? allowedOvertimeMinutes,
    bool? autoReportingEnabled,
    String? aiProvider,
    String? geminiApiKey,
    String? chatGptApiKey,
    String? claudeApiKey,
    String? selectedModel,
    List<String>? availableModels,
    bool? isFetchingModels,
  }) {
    return AppSettings(
      allowedLateMinutes: allowedLateMinutes ?? this.allowedLateMinutes,
      allowedOvertimeMinutes: allowedOvertimeMinutes ?? this.allowedOvertimeMinutes,
      autoReportingEnabled: autoReportingEnabled ?? this.autoReportingEnabled,
      aiProvider: aiProvider ?? this.aiProvider,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      chatGptApiKey: chatGptApiKey ?? this.chatGptApiKey,
      claudeApiKey: claudeApiKey ?? this.claudeApiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      availableModels: availableModels ?? this.availableModels,
      isFetchingModels: isFetchingModels ?? this.isFetchingModels,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  void updateLateMinutes(int minutes) {
    state = state.copyWith(allowedLateMinutes: minutes);
  }

  void updateOvertimeMinutes(int minutes) {
    state = state.copyWith(allowedOvertimeMinutes: minutes);
  }

  void toggleAutoReporting(bool enabled) {
    state = state.copyWith(autoReportingEnabled: enabled);
  }

  void updateAiProvider(String provider) {
    state = state.copyWith(aiProvider: provider);
  }

  void updateGeminiApiKey(String key) {
    state = state.copyWith(geminiApiKey: key);
  }

  void updateChatGptApiKey(String key) {
    state = state.copyWith(chatGptApiKey: key);
  }

  void updateClaudeApiKey(String key) {
    state = state.copyWith(claudeApiKey: key);
  }

  void updateSelectedModel(String? model) {
    state = state.copyWith(selectedModel: model);
  }

  Future<void> fetchModels() async {
    state = state.copyWith(isFetchingModels: true, availableModels: [], selectedModel: null);
    try {
      if (state.aiProvider == 'Gemini') {
        if (state.geminiApiKey.isEmpty) throw Exception('API key required');
        final response = await http.get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=${state.geminiApiKey}'));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final models = (data['models'] as List).map((m) => m['name'].toString().replaceFirst('models/', '')).toList();
          state = state.copyWith(availableModels: models);
        } else {
          throw Exception('Failed to fetch models');
        }
      } else if (state.aiProvider == 'ChatGPT') {
        if (state.chatGptApiKey.isEmpty) throw Exception('API key required');
        final response = await http.get(
          Uri.parse('https://api.openai.com/v1/models'),
          headers: {'Authorization': 'Bearer ${state.chatGptApiKey}'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final models = (data['data'] as List).map((m) => m['id'].toString()).toList();
          models.sort();
          state = state.copyWith(availableModels: models);
        } else {
          throw Exception('Failed to fetch models');
        }
      } else if (state.aiProvider == 'Claude') {
        if (state.claudeApiKey.isEmpty) throw Exception('API key required');
        final response = await http.get(
          Uri.parse('https://api.anthropic.com/v1/models'),
          headers: {
            'x-api-key': state.claudeApiKey,
            'anthropic-version': '2023-06-01',
          },
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final models = (data['data'] as List).map((m) => m['id'].toString()).toList();
          state = state.copyWith(availableModels: models);
        } else {
          // Fallback to static list if API structure isn't exactly as expected or unauthorized for listing models
          state = state.copyWith(availableModels: ['claude-3-5-sonnet-20240620', 'claude-3-opus-20240229', 'claude-3-sonnet-20240229', 'claude-3-haiku-20240307']);
        }
      }
    } catch (e) {
      // If network fails or empty, fallback to empty or handle error
      if (state.aiProvider == 'Claude') {
        state = state.copyWith(availableModels: ['claude-3-5-sonnet-20240620', 'claude-3-opus-20240229', 'claude-3-sonnet-20240229', 'claude-3-haiku-20240307']);
      } else {
        state = state.copyWith(availableModels: []);
      }
    } finally {
      state = state.copyWith(isFetchingModels: false);
    }
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
