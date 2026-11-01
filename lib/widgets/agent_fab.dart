import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../services/agent_actions.dart';
import '../services/agent_service.dart';

class ChatMessage {
  final bool fromAgent;
  final String text;

  /// Changes Vigil AI prepared in this reply, each waiting for approval.
  final List<AgentProposal> proposals;

  const ChatMessage({required this.fromAgent, required this.text, this.proposals = const []});

  ChatMessage withProposals(List<AgentProposal> p) => ChatMessage(fromAgent: fromAgent, text: text, proposals: p);

  /// The message as the model sees it later, including what happened to each card.
  AgentTurn get turn => (fromAgent: fromAgent, text: [text, for (final p in proposals) p.historyNote].where((s) => s.isNotEmpty).join('\n'));
}

/// Conversation with Vigil AI, kept for the session so it survives closing the panel.
final agentMessagesProvider = StateProvider<List<ChatMessage>>((ref) => const [
      ChatMessage(
        fromAgent: true,
        text: 'Hi, I am Vigil AI. I can see your live rosters, attendance, issues and leave, and I can prepare changes '
            'like approving leave, resolving issues or adding shifts. Nothing changes until you tap Approve. '
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
    final history = messages.state.skip(1).map((m) => m.turn).toList(); // Without the greeting.
    messages.state = [...messages.state, ChatMessage(fromAgent: false, text: text)];
    setState(() => _loading = true);
    _controller.clear();
    _scrollToEnd();

    // Navigation commands should act on the page behind this dialog.
    final pageContext = Navigator.of(context).context;
    final reply = await ref.read(agentServiceProvider).executeCommand(text, pageContext, history: history);
    messages.state = [...messages.state, ChatMessage(fromAgent: true, text: reply.text, proposals: reply.proposals)];
    if (!mounted) return;
    setState(() => _loading = false);
    _scrollToEnd();
  }

  /// Runs (or cancels) the proposals at [indexes] of message [messageIndex],
  /// one at a time, recording the outcome on each card.
  Future<void> _decide(int messageIndex, List<int> indexes, {required bool approve}) async {
    final messages = ref.read(agentMessagesProvider.notifier);
    void update(int i, AgentProposal Function(AgentProposal) change) {
      final list = [...messages.state];
      final m = list[messageIndex];
      list[messageIndex] = m.withProposals([...m.proposals]..[i] = change(m.proposals[i]));
      messages.state = list;
    }

    for (final i in indexes) {
      if (messages.state[messageIndex].proposals[i].status != ProposalStatus.pending) continue;
      if (!approve) {
        update(i, (p) => p.copyWith(status: ProposalStatus.cancelled, result: 'Cancelled'));
        continue;
      }
      update(i, (p) => p.copyWith(status: ProposalStatus.running));
      try {
        final result = await ref.read(agentActionsProvider).execute(messages.state[messageIndex].proposals[i]);
        update(i, (p) => p.copyWith(status: ProposalStatus.done, result: result));
      } catch (e) {
        final reason = e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
        update(i, (p) => p.copyWith(status: ProposalStatus.failed, result: reason));
      }
    }
  }

  Widget _proposalCards(int messageIndex, ChatMessage m) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final pending = [
      for (var i = 0; i < m.proposals.length; i++)
        if (m.proposals[i].status == ProposalStatus.pending) i,
    ];
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < m.proposals.length; i++)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              elevation: 0,
              color: cs.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: cs.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.pending_actions_outlined, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(m.proposals[i].summary, style: t.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    switch (m.proposals[i].status) {
                      ProposalStatus.pending => Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          children: [
                            TextButton(onPressed: () => _decide(messageIndex, [i], approve: false), child: const Text('Cancel')),
                            FilledButton.tonal(onPressed: () => _decide(messageIndex, [i], approve: true), child: const Text('Approve')),
                          ],
                        ),
                      ProposalStatus.running => const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      final status => Padding(
                          padding: const EdgeInsets.fromLTRB(26, 0, 4, 6),
                          child: Text(
                            '${switch (status) { ProposalStatus.done => '✓ ', ProposalStatus.failed => '✗ ', _ => '' }}${m.proposals[i].result ?? ''}',
                            style: t.bodySmall?.copyWith(
                              color: switch (status) {
                                ProposalStatus.done => cs.primary,
                                ProposalStatus.failed => cs.error,
                                _ => cs.onSurfaceVariant,
                              },
                            ),
                          ),
                        ),
                    },
                  ],
                ),
              ),
            ),
          if (pending.length > 1)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(onPressed: () => _decide(messageIndex, pending, approve: false), child: const Text('Cancel all')),
                FilledButton(onPressed: () => _decide(messageIndex, pending, approve: true), child: Text('Approve all ${pending.length}')),
              ],
            ),
        ],
      ),
    );
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
                  if (messages.length > 1)
                    IconButton(
                      tooltip: 'New chat',
                      icon: const Icon(Icons.refresh),
                      onPressed: _loading ? null : () => ref.invalidate(agentMessagesProvider),
                    ),
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
                  final bubble = Align(
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
                      child: SelectableText(m.text, style: t.bodyMedium?.copyWith(color: m.fromAgent ? cs.onSurface : cs.onPrimary)),
                    ),
                  );
                  if (m.proposals.isEmpty) return bubble;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [if (m.text.isNotEmpty) bubble, _proposalCards(i, m)],
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
                    for (final s in const ['Who is working right now?', 'Any open issues?', "Who's rostered tomorrow?", 'Hours worked this week'])
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
