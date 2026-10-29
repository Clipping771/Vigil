import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/agent_service.dart';

typedef ChatMessage = ({bool fromAgent, String text});

/// Conversation with Vigil AI, kept for the session so it survives closing the panel.
final agentMessagesProvider = StateProvider<List<ChatMessage>>((ref) => [
      (
        fromAgent: true,
        text: 'Hi, I am Vigil AI. Try "switch to dark mode", "who is rostered?" or "open leave". '
            'Add your API key in Settings first.',
      ),
    ]);

/// App-bar button that opens the Vigil AI panel (like Gemini in Google Workspace).
class AiAssistantButton extends StatelessWidget {
  const AiAssistantButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Vigil AI',
      icon: const Icon(Icons.auto_awesome_outlined),
      onPressed: () => showDialog<void>(
        context: context,
        barrierColor: Colors.black12,
        builder: (ctx) => const Align(
          alignment: Alignment.bottomRight,
          child: Padding(padding: EdgeInsets.all(16), child: AgentChatPanel()),
        ),
      ),
    );
  }
}

/// The Vigil AI chat panel.
class AgentChatPanel extends ConsumerStatefulWidget {
  const AgentChatPanel({super.key});

  @override
  ConsumerState<AgentChatPanel> createState() => _AgentChatPanelState();
}

class _AgentChatPanelState extends ConsumerState<AgentChatPanel> {
  bool _loading = false;
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _loading) return;
    final messages = ref.read(agentMessagesProvider.notifier);
    messages.state = [...messages.state, (fromAgent: false, text: text)];
    setState(() => _loading = true);
    _controller.clear();
    _scrollToEnd();

    // Navigation commands should act on the page behind this dialog.
    final pageContext = Navigator.of(context).context;
    final reply = await ref.read(agentServiceProvider).executeCommand(text, pageContext);
    messages.state = [...messages.state, (fromAgent: true, text: reply)];
    if (!mounted) return;
    setState(() => _loading = false);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final messages = ref.watch(agentMessagesProvider);

    final size = MediaQuery.sizeOf(context);
    return Material(
      elevation: 6,
      color: cs.surfaceContainerHigh,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width < 420 ? size.width - 32 : 380,
        height: size.height < 600 ? size.height - 120 : 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Vigil AI', style: t.titleMedium)),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length + (_loading ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == messages.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    );
                  }
                  final m = messages[i];
                  return Align(
                    alignment: m.fromAgent ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: m.fromAgent ? cs.surfaceContainerHighest : cs.primary,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(m.fromAgent ? 4 : 18),
                          bottomRight: Radius.circular(m.fromAgent ? 18 : 4),
                        ),
                      ),
                      child: Text(m.text, style: t.bodyMedium?.copyWith(color: m.fromAgent ? cs.onSurface : cs.onPrimary)),
                    ),
                  );
                },
              ),
            ),
            if (messages.length <= 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in const ['Who is rostered?', 'Any open issues?', 'Switch to dark mode'])
                      ActionChip(label: Text(s), onPressed: () => _send(s)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask Vigil AI',
                        isDense: true,
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.outline)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.outline)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(tooltip: 'Send', icon: const Icon(Icons.arrow_upward), onPressed: _loading ? null : _send),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
