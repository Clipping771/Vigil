import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../providers/theme_provider.dart';

final agentServiceProvider = Provider((ref) => AgentService(ref));

class AgentService {
  final Ref _ref;
  final String baseUrl = 'http://127.0.0.1:8000';

  AgentService(this._ref);

  Future<String> executeCommand(String prompt, BuildContext context) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/agent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        return _handleAction(data, context);
      } else {
        return "Sorry, I couldn't connect to my AI core.";
      }
    } catch (e) {
      return "Network error connecting to the agent: $e";
    }
  }

  String _handleAction(Map<String, dynamic> data, BuildContext context) {
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
        return payload.toString();

      case 'error':
      default:
        return payload?.toString() ?? "I'm not sure how to handle that request.";
    }
  }
}
