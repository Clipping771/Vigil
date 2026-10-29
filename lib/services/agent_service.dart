import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/exception_provider.dart';
import '../providers/roster_provider.dart';
import '../providers/staff_provider.dart';

final agentServiceProvider = Provider((ref) => AgentService(ref));

class AgentUnavailable implements Exception {
  final String message;
  const AgentUnavailable(this.message);
  @override
  String toString() => message;
}

class AgentService {
  final Ref _ref;

  AgentService(this._ref);

  Future<String> executeCommand(String prompt, BuildContext context) async {
    final systemPrompt = '''
    You are Vigil AI, an intelligent workforce management assistant built into the 'Vigil' app.
    Your job is to read the user's natural language command and convert it into a structured JSON object.
    
    Available Actions:
    1. toggle_theme: Switch the app's theme. 
       Payload MUST be exactly "light" or "dark".
       
    2. navigate: Go to a specific page.
       Valid paths: "/dashboard", "/rosters", "/staff", "/leave", "/reports", "/settings"
       
    3. chat: General conversation or when no other action fits.
       Payload: Your response text.
       
    4. check_exceptions: Ask about anomalies, warnings, or exceptions.
       Payload: not needed.
       
    5. check_roster: Ask about schedules, shifts, or who is working.
       Payload: not needed.
       
    6. list_staff: Ask for a list of employees or staff.
       Payload: not needed.
       
    Respond ONLY with the JSON object. Do not wrap it in markdown block quotes like ```json.
    ''';

    try {
      final jsonResponseStr = await _callLLM(prompt, systemPrompt);
      String cleanJson = jsonResponseStr.trim();
      if (cleanJson.startsWith('```json')) {
        cleanJson = cleanJson.substring(7, cleanJson.length - 3).trim();
      } else if (cleanJson.startsWith('```')) {
        cleanJson = cleanJson.substring(3, cleanJson.length - 3).trim();
      }

      final data = jsonDecode(cleanJson);
      if (!context.mounted) return 'Action cancelled: the screen was closed.';
      return await _handleAction(data, context);
    } catch (e) {
      debugPrint('Agent error: $e');
      return "Sorry, I couldn't process that request. Please try again.";
    }
  }

  /// Asks the configured model for a short recommendation on how a manager
  /// should handle [exception]. Throws [AgentUnavailable] with a readable reason.
  Future<String> suggestResolution({
    required String type,
    required String severity,
    required String description,
    String? employeeName,
  }) async {
    const system = 'You are a workforce compliance advisor for shift-based teams in Australia. '
        'Given one attendance exception, reply in at most 3 short sentences: the likely cause, '
        'what the manager should verify, and whether to resolve, acknowledge or escalate. '
        'Do not invent facts that are not in the exception. Plain text only.';
    final prompt = 'Exception type: $type\nSeverity: $severity\n'
        'Employee: ${employeeName ?? 'unknown'}\nDetails: $description';
    final text = (await _callLLM(prompt, system)).trim();
    if (text.startsWith('{')) {
      try {
        final data = jsonDecode(text);
        if (data is Map && data['action'] == 'error') throw AgentUnavailable(data['payload'].toString());
      } on FormatException {
        // Model returned JSON-looking text; fall through and show it.
      }
    }
    return text;
  }

  Future<String> _callLLM(String prompt, String systemPrompt) async {
    final settings = _ref.read(settingsProvider);
    final apiKey = settings.activeApiKey;
    final model = settings.activeModel;
    if (apiKey.isEmpty) {
      return jsonEncode({'action': 'error', 'payload': 'Add your ${settings.aiProvider} API key in Settings → AI Assistant to use Vigil AI.'});
    }

    late final http.Response response;
    switch (settings.aiProvider) {
      case 'ChatGPT':
        response = await http.post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': prompt}
            ]
          }),
        );
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['choices'][0]['message']['content'];
        }
      case 'Claude':
        response = await http.post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 1024,
            'system': systemPrompt,
            'messages': [
              {'role': 'user', 'content': prompt}
            ]
          }),
        );
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['content'][0]['text'];
        }
      default:
        response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'system_instruction': {
              'parts': {'text': systemPrompt}
            },
            'contents': [
              {'parts': [{'text': prompt}]}
            ],
          }),
        );
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['candidates'][0]['content']['parts'][0]['text'];
        }
    }

    debugPrint('${settings.aiProvider} API error ${response.statusCode}: ${response.body}');
    final reason = switch (response.statusCode) {
      401 || 403 => 'the API key was rejected',
      404 => 'model "$model" is not available',
      429 => 'the rate limit was reached',
      _ => 'the service returned an error (${response.statusCode})',
    };
    return jsonEncode({'action': 'error', 'payload': 'Vigil AI could not respond: $reason.'});
  }

  Future<String> _handleAction(Map<String, dynamic> data, BuildContext context) async {
    final action = data['action'];
    final payload = data['payload'];

    switch (action) {
      case 'toggle_theme':
        final themeStr = payload?.toString().toLowerCase() ?? '';
        final notifier = _ref.read(themeProvider.notifier);
        if (themeStr.contains('light')) {
          notifier.setTheme(AppTheme.light);
          return "Switched to light mode.";
        } else if (themeStr.contains('dark')) {
          notifier.setTheme(AppTheme.dark);
          return "Switched to dark mode.";
        }
        notifier.toggle();
        return "Switched to ${_ref.read(themeProvider).currentTheme.label.toLowerCase()} mode.";

      case 'navigate':
        const allowedPaths = {'/dashboard', '/rosters', '/staff', '/leave', '/reports', '/settings', '/geofence'};
        if (payload is! String || !allowedPaths.contains(payload)) {
          return "I can't navigate there.";
        }
        try {
          context.go(payload);
          return "Navigating you to $payload.";
        } catch (e) {
          return "I can't seem to navigate there.";
        }

      case 'chat':
        return payload?.toString() ?? "Hello!";

      case 'check_exceptions':
        try {
          final exceptionsAsync = _ref.read(exceptionStreamProvider);
          final exceptions = exceptionsAsync.value ?? [];
          final pending = exceptions.where((e) => e.status == 'pending').toList();
          
          if (pending.isEmpty) {
            return "Great news! There are no pending exceptions right now.";
          } else {
            return "You have ${pending.length} pending exceptions requiring attention. Would you like me to navigate to the dashboard to see them?";
          }
        } catch (e) {
          return "Failed to load exceptions: $e";
        }

      case 'check_roster':
        try {
          final shifts = await _ref.read(rosterProvider.future);
          if (shifts.isEmpty) {
            return "There are no shifts scheduled at the moment.";
          } else {
            return "I found ${shifts.length} total shifts in the system. Go to the Rosters page for details.";
          }
        } catch (e) {
          return "Failed to load roster: $e";
        }

      case 'list_staff':
        try {
          final staff = await _ref.read(staffProvider.future);
          if (staff.isEmpty) {
            return "No staff members found.";
          } else {
            final names = staff.take(5).map((e) => e.fullName).join(', ');
            final extra = staff.length > 5 ? " and ${staff.length - 5} more." : ".";
            return "Here are some of your staff members: $names$extra";
          }
        } catch (e) {
          return "Failed to load staff list: $e";
        }

      case 'error':
      default:
        return payload?.toString() ?? "I'm not sure how to handle that request.";
    }
  }
}
