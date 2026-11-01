import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/services/agent_actions.dart';
import 'package:vigil/widgets/agent_fab.dart';

void main() {
  testWidgets('proposal cards wait for approval and record a cancel', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const proposal = AgentProposal(type: 'approve_leave', args: {'id': 'x'}, summary: 'Approve annual leave for Bob Jones');
    final container = ProviderContainer(overrides: [
      agentMessagesProvider.overrideWith((ref) => const [
            ChatMessage(fromAgent: true, text: 'Hi'),
            ChatMessage(fromAgent: false, text: 'approve all pending leave'),
            ChatMessage(fromAgent: true, text: 'I prepared 2 approvals.', proposals: [proposal, proposal]),
          ]),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: AgentChatPanel()))),
    ));

    expect(find.text('Approve annual leave for Bob Jones'), findsNWidgets(2));
    expect(find.text('Approve all 2'), findsOneWidget);

    await tester.tap(find.text('Cancel').first);
    await tester.pump();

    final cards = container.read(agentMessagesProvider).last.proposals;
    expect(cards.map((p) => p.status), [ProposalStatus.cancelled, ProposalStatus.pending]);
    expect(find.text('Approve all 2'), findsNothing); // Only one card is still pending.
    expect(container.read(agentMessagesProvider).last.turn.text, contains('[User declined: Approve annual leave for Bob Jones]'));
    expect(tester.takeException(), isNull);
  });
}
