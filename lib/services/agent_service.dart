import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_shell.dart' show appDestinations, canAccessPath;
import 'agent_actions.dart';
import 'agent_context.dart';

final agentServiceProvider = Provider((ref) => AgentService(ref));

class AgentUnavailable implements Exception {
  final String message;
  const AgentUnavailable(this.message);
  @override
  String toString() => message;
}

/// One turn of the conversation sent to the model.
typedef AgentTurn = ({bool fromAgent, String text});

/// How many earlier messages are sent with each question.
const agentHistoryTurns = 12;

/// A reply to show, plus any changes waiting for the user's approval.
typedef AgentAnswer = ({String text, List<AgentProposal> proposals});

class AgentService {
  final Ref _ref;

  AgentService(this._ref);

  /// Answers [prompt] from a fresh snapshot of the organization's data, with
  /// the earlier conversation in [history]. Page and theme changes the model
  /// asks for are carried out on [context]; data changes come back as
  /// proposals that only run once the user approves them.
  Future<AgentAnswer> executeCommand(String prompt, BuildContext context, {List<AgentTurn> history = const []}) async {
    AgentAnswer say(String text) => (text: text, proposals: const <AgentProposal>[]);
    final me = _ref.read(authProvider).currentUser;
    if (me == null) return say('Please sign in first.');

    try {
      final now = DateTime.now();
      final data = await loadAgentData(me, now: now);
      final system = _systemPrompt(me, formatAgentContext(me: me, data: data, settings: _ref.read(settingsProvider), now: now));
      // Recent turns only, starting with a user message (Claude and Gemini require it).
      final recent = history.length > agentHistoryTurns ? history.sublist(history.length - agentHistoryTurns) : history;
      final turns = [...recent.skipWhile((t) => t.fromAgent), (fromAgent: false, text: prompt)];
      final raw = await _callLLM(turns, system);
      final error = _errorIn(raw);
      if (error != null) return say(error);

      final reply = parseAgentReply(raw);
      var text = reply.text;
      if (reply.action != null && context.mounted) {
        final done = _runAction(reply.action!, me, context);
        if (text.isEmpty) text = done;
      }
      final review = resolveProposals(reply.proposals, me, data);
      if (review.rejected.isNotEmpty) {
        text = [if (text.isNotEmpty) text, "I couldn't prepare: ${review.rejected.join('; ')}."].join('\n\n');
      }
      if (text.isEmpty && review.proposals.isEmpty) text = "Sorry, I didn't get an answer. Please try rephrasing.";
      return (text: text, proposals: review.proposals);
    } on TimeoutException {
      return say('The AI service took too long to answer. Please try again.');
    } on http.ClientException catch (e) {
      debugPrint('Agent network error: $e');
      return say("Couldn't reach the AI service. Check your connection and try again.");
    } catch (e) {
      debugPrint('Agent error: $e');
      return say("Sorry, I couldn't process that request. Please try again.");
    }
  }

  String _systemPrompt(Employee me, String context) {
    final pages = [
      for (final d in appDestinations)
        if (d.visibleTo(me)) '${d.path} (${d.label})',
    ].join(', ');
    return '''
You are Vigil AI, the assistant inside Vigil, a workforce attendance, rostering and compliance app.
You are talking to ${me.fullName} (${me.role}).

How to answer:
- Answer from the DATA section below. It is live and was loaded just now. Use real names, dates, times and numbers.
- Work things out yourself: count, add up hours, compare people, spot patterns, find who is late or missing, check rest gaps and leave clashes. Double-check arithmetic and dates against "Now".
- If the data does not contain the answer (for example it is older than the window shown), say so plainly and say which page in the app has it. Never invent people, shifts or numbers.
- ${me.isManager ? 'You can see the whole organization.' : 'You only have this user\'s own records; if they ask about colleagues, explain that a manager can see that.'}
- Reply in the same language and style as the user (English, Bengali, or Bengali written in English letters).
- Be concise and direct: lead with the answer, then the key details. Plain text only: no markdown tables, no ** or #. Short "- " bullet lists are fine.
- You can prepare changes, but a person must approve each one (see "Doing things"). Never say a change is done until the conversation shows it was approved and done.
- Give practical advice when asked (e.g. Fair Work breaks, rest between shifts, how to cover a shift), based on the data and rules.

Actions: when the user asks to open a page or change the theme, or when opening a page clearly helps, add ONE final line exactly like:
ACTION: {"type":"navigate","path":"/leave"}
ACTION: {"type":"theme","mode":"dark"}
Pages this user can open: $pages. Mode is "light" or "dark".

Doing things (human approval required): when the user asks you to change something, or agrees to a change you suggested, prepare it as a proposal. Each one appears as a card with Approve / Cancel; nothing happens until the user taps Approve. Write one sentence saying what you prepared and why, then put each proposal on its own line at the end, using the #id values from DATA without the "#":
PROPOSE: {"type":"approve_leave","id":"1a2b3c4d"}
PROPOSE: {"type":"add_shift","employee_id":"5e6f7a8b","start":"2026-11-03T09:00","end":"2026-11-03T17:00","site":"Oakleigh HQ"}
Changes this user may prepare:
${proposalTypesFor(me).map((t) => '- $t').join('\n')}
For "all"/bulk requests, propose one card per record (at most 10). Check the data first (pending status, overlaps, rest gaps, leave clashes) and mention any concern. If something is not in this list (e.g. adding staff, editing settings), say which page does it. Earlier messages show "[User approved and it was done: ...]" or "[User declined: ...]" after each card.

DATA
$context''';
  }

  String _runAction(Map<String, dynamic> action, Employee me, BuildContext context) {
    switch (action['type']) {
      case 'theme':
        final notifier = _ref.read(themeProvider.notifier);
        final mode = '${action['mode'] ?? ''}'.toLowerCase();
        if (mode == 'light' || mode == 'dark') {
          notifier.setTheme(mode == 'light' ? AppTheme.light : AppTheme.dark);
        } else {
          notifier.toggle();
        }
        return 'Switched to ${_ref.read(themeProvider).currentTheme.label.toLowerCase()} mode.';
      case 'navigate':
        final path = '${action['path'] ?? ''}';
        final known = appDestinations.any((d) => d.path == path);
        if (!known || !canAccessPath(me, path)) return "I can't open that page for you.";
        context.go(path);
        return 'Opening ${appDestinations.firstWhere((d) => d.path == path).label}.';
      default:
        return '';
    }
  }

  /// Returns the readable message when [raw] is our error envelope.
  String? _errorIn(String raw) {
    if (!raw.trimLeft().startsWith('{"action":"error"')) return null;
    try {
      return '${jsonDecode(raw)['payload']}';
    } on FormatException {
      return null;
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
    final text = (await _callLLM([(fromAgent: false, text: prompt)], system)).trim();
    final error = _errorIn(text);
    if (error != null) throw AgentUnavailable(error);
    return text;
  }

  /// Sends a tiny prompt to the configured provider and model. Returns a
  /// success message with the round-trip time, or throws [AgentUnavailable].
  Future<String> testConnection() async {
    var settings = _ref.read(settingsProvider);
    if (settings.aiProvider == 'Ollama' && settings.selectedModel == null) {
      try {
        await _ref.read(settingsProvider.notifier).fetchModels();
      } catch (e) {
        throw AgentUnavailable(e.toString().replaceFirst('Exception: ', ''));
      }
      settings = _ref.read(settingsProvider);
    }
    final watch = Stopwatch()..start();
    final String text;
    try {
      text = (await _callLLM([(fromAgent: false, text: 'Reply with the single word OK.')], 'You are a connectivity check. Answer in one word.')).trim();
    } on http.ClientException {
      throw const AgentUnavailable("Couldn't reach the AI service. Check your internet connection.");
    } on TimeoutException {
      throw const AgentUnavailable('The AI service did not answer in time.');
    }
    watch.stop();
    final error = _errorIn(text);
    if (error != null) throw AgentUnavailable(error);
    if (text.isEmpty) throw const AgentUnavailable('The model returned an empty reply.');
    final secs = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return 'Connected to ${settings.aiProvider == 'ChatGPT' ? 'OpenAI' : settings.aiProvider} · ${settings.activeModel} replied in ${secs}s.';
  }

  Future<String> _callLLM(List<AgentTurn> turns, String systemPrompt) async {
    final settings = _ref.read(settingsProvider);
    final apiKey = settings.activeApiKey;
    final model = settings.activeModel;
    if (settings.needsApiKey && apiKey.isEmpty) {
      return jsonEncode({'action': 'error', 'payload': 'Add your ${settings.aiProvider} API key in Settings → AI Assistant to use Vigil AI.'});
    }
    List<Map<String, String>> chat() => [
          for (final t in turns) {'role': t.fromAgent ? 'assistant' : 'user', 'content': t.text},
        ];
    const timeout = Duration(seconds: 90);

    late final http.Response response;
    switch (settings.aiProvider) {
      case 'Ollama':
        try {
          response = await http
              .post(
                Uri.parse('${settings.ollamaUrl}/api/chat'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'model': model,
                  'stream': false,
                  // Room for the data snapshot; Ollama's default context is small.
                  'options': {'num_ctx': 32768},
                  'messages': [
                    {'role': 'system', 'content': systemPrompt},
                    ...chat(),
                  ],
                }),
              )
              .timeout(const Duration(seconds: 180));
        } catch (_) {
          return jsonEncode({'action': 'error', 'payload': ollamaUnreachableMessage(settings.ollamaUrl)});
        }
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['message']['content'];
        }
      case 'ChatGPT':
        response = await http
            .post(
              Uri.parse('https://api.openai.com/v1/chat/completions'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
              body: jsonEncode({
                'model': model,
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  ...chat(),
                ]
              }),
            )
            .timeout(timeout);
        if (response.statusCode == 200) {
          return jsonDecode(response.body)['choices'][0]['message']['content'];
        }
      case 'Claude':
        response = await http
            .post(
              Uri.parse('https://api.anthropic.com/v1/messages'),
              headers: {
                'Content-Type': 'application/json',
                'x-api-key': apiKey,
                'anthropic-version': '2023-06-01',
                'anthropic-dangerous-direct-browser-access': 'true',
              },
              body: jsonEncode({
                'model': model,
                'max_tokens': 4096,
                'system': systemPrompt,
                'messages': chat(),
              }),
            )
            .timeout(timeout);
        if (response.statusCode == 200) {
          final blocks = jsonDecode(response.body)['content'] as List;
          return blocks.where((b) => b['type'] == 'text').map((b) => b['text']).join();
        }
      default:
        response = await http
            .post(
              Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent'),
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
              body: jsonEncode({
                'system_instruction': {
                  'parts': {'text': systemPrompt}
                },
                'contents': [
                  for (final t in turns)
                    {
                      'role': t.fromAgent ? 'model' : 'user',
                      'parts': [{'text': t.text}]
                    },
                ],
              }),
            )
            .timeout(timeout);
        if (response.statusCode == 200) {
          final parts = jsonDecode(response.body)['candidates'][0]['content']['parts'] as List;
          return parts.map((p) => p['text'] ?? '').join();
        }
    }

    debugPrint('${settings.aiProvider} API error ${response.statusCode}: ${response.body}');
    final reason = switch (response.statusCode) {
      401 || 403 => 'the API key was rejected',
      404 => settings.aiProvider == 'Ollama'
          ? 'model "$model" is not installed (run: ollama pull $model)'
          : 'model "$model" is not available',
      413 => 'the request was too large for this model',
      429 => 'the rate limit was reached',
      _ => 'the service returned an error (${response.statusCode})',
    };
    return jsonEncode({'action': 'error', 'payload': 'Vigil AI could not respond: $reason.'});
  }
}

/// Splits a model reply into the text to show, an optional trailing
/// `ACTION: {...}` instruction and any `PROPOSE: {...}` lines. Also accepts
/// the older all-JSON reply format.
({String text, Map<String, dynamic>? action, List<Map<String, dynamic>> proposals}) parseAgentReply(String raw) {
  var text = raw.trim();
  Map<String, dynamic>? action;
  final proposals = <Map<String, dynamic>>[];

  // Older/smaller models sometimes answer with a JSON object only.
  if (text.startsWith('{') && text.endsWith('}')) {
    try {
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        final kind = data['action'];
        if (kind == 'navigate') return (text: '', action: {'type': 'navigate', 'path': data['payload']}, proposals: proposals);
        if (kind == 'toggle_theme') return (text: '', action: {'type': 'theme', 'mode': data['payload']}, proposals: proposals);
        final reply = data['reply'] ?? data['payload'];
        if (reply is String) text = reply.trim();
      }
    } on FormatException {
      // Plain text that happens to start with a brace.
    }
  }

  final proposeLine = RegExp(r'^\s*PROPOSE:\s*(\{.*\})\s*$', multiLine: true);
  for (final m in proposeLine.allMatches(text)) {
    try {
      final data = jsonDecode(m.group(1)!);
      if (data is Map<String, dynamic>) proposals.add(data);
    } on FormatException {
      // Skip a malformed proposal; the line is still hidden below.
    }
  }
  text = text.replaceAll(proposeLine, '').trim();

  final match = RegExp(r'^\s*ACTION:\s*(\{.*\})\s*$', multiLine: true).allMatches(text).lastOrNull;
  if (match != null) {
    try {
      final data = jsonDecode(match.group(1)!);
      if (data is Map<String, dynamic>) action = data;
    } on FormatException {
      // Ignore a malformed action line but still hide it.
    }
    text = text.replaceRange(match.start, match.end, '').trim();
  }

  // The chat panel shows plain text.
  text = text.replaceAll('**', '').replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
  return (text: text, action: action, proposals: proposals);
}
