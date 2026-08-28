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
import '../providers/auth_provider.dart';

final agentServiceProvider = Provider((ref) => AgentService(ref));

class AgentService {
  final Ref _ref;

  AgentService(this._ref);

  Future<String> executeCommand(String prompt, BuildContext context) async {
    final systemPrompt = '''
    You are Vigil AI, an intelligent workforce management assistant built into the 'Vigil' app.
    Your job is to read the user's natural language command and convert it into a structured JSON object.
    
    Available Actions:
    1. toggle_theme: Switch to light mode or dark mode. 
       Payload: "light" or "dark".
       
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
      return await _handleAction(data, context);
    } catch (e) {
      return "Network or parsing error connecting to the agent: $e";
    }
  }

  Future<String> _callLLM(String prompt, String systemPrompt) async {
    final settings = _ref.read(settingsProvider);
    final provider = settings.aiProvider;
    final model = settings.selectedModel;

    if (provider == 'Gemini') {
      final apiKey = settings.geminiApiKey;
      if (apiKey.isEmpty) return '{"action": "error", "payload": "Gemini API key is not configured in settings."}';
      
      final actualModel = model ?? 'gemini-1.5-flash';
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$actualModel:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
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
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        return '{"action": "error", "payload": "Gemini API Error: ${response.body}"}';
      }
    } else if (provider == 'ChatGPT') {
      final apiKey = settings.chatGptApiKey;
      if (apiKey.isEmpty) return '{"action": "error", "payload": "ChatGPT API key is not configured in settings."}';
      
      final actualModel = model ?? 'gpt-3.5-turbo';
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({
          'model': actualModel,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return '{"action": "error", "payload": "ChatGPT API Error: ${response.body}"}';
      }
    } else if (provider == 'Claude') {
      final apiKey = settings.claudeApiKey;
      if (apiKey.isEmpty) return '{"action": "error", "payload": "Claude API key is not configured in settings."}';
      
      final actualModel = model ?? 'claude-3-haiku-20240307';
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01'
        },
        body: jsonEncode({
          'model': actualModel,
          'max_tokens': 1024,
          'system': systemPrompt,
          'messages': [
            {'role': 'user', 'content': prompt}
          ]
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['content'][0]['text'];
      } else {
        return '{"action": "error", "payload": "Claude API Error: ${response.body}"}';
      }
    }
    
    return '{"action": "error", "payload": "Unknown AI Provider."}';
  }

  Future<String> _handleAction(Map<String, dynamic> data, BuildContext context) async {
    final action = data['action'];
    final payload = data['payload'];

    switch (action) {
      case 'toggle_theme':
        if (payload == 'light') {
          _ref.read(themeProvider.notifier).setTheme(AppTheme.arcticLight);
          return "I've switched the theme to Arctic Light.";
        } else if (payload == 'dark') {
          _ref.read(themeProvider.notifier).setTheme(AppTheme.deepSpace);
          return "I've switched the theme to Deep Space.";
        }
        return "I didn't understand which theme you wanted.";
      
      case 'navigate':
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
          final exceptions = await _ref.read(exceptionStreamProvider.future);
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
