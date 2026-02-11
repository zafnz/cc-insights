import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendProvider, ToolInvocationEvent, ToolKind;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/panels/ticket_bulk_review_panel.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-bulk-int-${_idCounter++}';

/// Helper to create a ToolInvocationEvent for create_tickets.
ToolInvocationEvent makeCreateTicketsEvent({
  String? callId,
  required Map<String, dynamic> input,
}) {
  return ToolInvocationEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    callId: callId ?? 'call-${_nextId()}',
    sessionId: 'test-session',
    kind: ToolKind.execute,
    toolName: 'create_tickets',
    input: input,
  );
}

/// Creates a valid ticket proposal JSON map.
Map<String, dynamic> makeProposalJson({
  String title = 'Test Ticket',
  String description = 'Test description',
  String kind = 'feature',
  String priority = 'medium',
  String effort = 'medium',
  String? category,
  List<int>? dependsOnIndices,
}) {
  return {
    'title': title,
    'description': description,
    'kind': kind,
    'priority': priority,
    'effort': effort,
    if (category != null) 'category': category,
    if (dependsOnIndices != null) 'dependsOnIndices': dependsOnIndices,
  };
}

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    _idCounter = 0;
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('Phase 2 Integration - Full proposal flow', () {
    test('simulate tool event, review, partial approve via state', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-1'));
      final chat = resources.track(
        ChatState.create(name: 'Agent Chat', worktreeRoot: '/tmp/test'),
      );
      final handler = EventHandler(ticketBoard: ticketBoard);

      // Simulate agent calling create_tickets with 3 proposals
      final event = makeCreateTicketsEvent(
        callId: 'flow-call-1',
        input: {
          'tickets': [
            makeProposalJson(
              title: 'Set up database',
              description: 'Create database schema',
              kind: 'feature',
              category: 'Backend',
            ),
            makeProposalJson(
              title: 'Add user model',
              description: 'Create User model class',
              kind: 'feature',
              category: 'Backend',
            ),
            makeProposalJson(
              title: 'Write migration tests',
              description: 'Test database migrations',
              kind: 'test',
              category: 'Testing',
            ),
          ],
        },
      );

      handler.handleEvent(chat, event);

      // Verify proposals are staged
      expect(ticketBoard.proposedTickets.length, 3);
      expect(ticketBoard.detailMode, TicketDetailMode.bulkReview);
      expect(ticketBoard.proposalCheckedIds.length, 3);

      // Uncheck the third proposal (Write migration tests)
      final proposed = ticketBoard.proposedTickets;
      ticketBoard.toggleProposalChecked(proposed[2].id);
      expect(ticketBoard.proposalCheckedIds.length, 2);
      expect(
        ticketBoard.proposalCheckedIds.contains(proposed[2].id),
        isFalse,
      );

      // Approve (2 checked, 1 unchecked)
      ticketBoard.approveBulk();

      // Verify: 2 tickets promoted to ready, 1 deleted
      expect(ticketBoard.tickets.length, 2);

      final kept1 = ticketBoard.getTicket(proposed[0].id);
      expect(kept1, isNotNull);
      expect(kept1!.status, TicketStatus.ready);
      expect(kept1.title, 'Set up database');

      final kept2 = ticketBoard.getTicket(proposed[1].id);
      expect(kept2, isNotNull);
      expect(kept2!.status, TicketStatus.ready);
      expect(kept2.title, 'Add user model');

      // Deleted ticket is gone
      expect(ticketBoard.getTicket(proposed[2].id), isNull);

      // Mode returns to detail
      expect(ticketBoard.detailMode, TicketDetailMode.detail);

      // Tool result was sent back
      expect(handler.hasPendingTicketReview, isFalse);
      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      expect(toolEntry.result, isNotNull);
      expect(toolEntry.result.toString(), contains('2 of 3'));
      expect(toolEntry.result.toString(), contains('1 were rejected'));

      handler.dispose();
    });

    testWidgets('full flow with widget: propose, uncheck, approve',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ticketBoard = resources.track(TicketBoardState('int-test-2'));

      // Stage proposals directly on the state
      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Create API endpoint',
            kind: TicketKind.feature,
            category: 'Backend',
            description: 'REST endpoint for users',
          ),
          const TicketProposal(
            title: 'Add error handling',
            kind: TicketKind.bugfix,
            category: 'Backend',
            description: 'Handle 404 errors',
          ),
          const TicketProposal(
            title: 'Update docs',
            kind: TicketKind.docs,
            category: 'Docs',
            description: 'Update API docs',
          ),
        ],
        sourceChatId: 'chat-1',
        sourceChatName: 'Dev Agent',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
              child: const TicketBulkReviewPanel(),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // All 3 proposals should be visible
      expect(find.text('Create API endpoint'), findsOneWidget);
      expect(find.text('Add error handling'), findsOneWidget);
      expect(find.text('Update docs'), findsOneWidget);
      expect(find.text('Approve 3'), findsOneWidget);

      // Uncheck the third proposal by tapping its checkbox
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(3));
      await tester.tap(checkboxes.at(2));
      await safePumpAndSettle(tester);

      expect(find.text('Approve 2'), findsOneWidget);

      // Tap Approve
      await tester.tap(find.byKey(TicketBulkReviewKeys.approveButton));
      await safePumpAndSettle(tester);

      // Verify: 2 tickets kept as ready, 1 deleted
      expect(ticketBoard.tickets.length, 2);
      expect(
        ticketBoard.getTicket(proposals[0].id)?.status,
        TicketStatus.ready,
      );
      expect(
        ticketBoard.getTicket(proposals[1].id)?.status,
        TicketStatus.ready,
      );
      expect(ticketBoard.getTicket(proposals[2].id), isNull);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);
    });
  });

  group('Phase 2 Integration - Reject all flow', () {
    test('reject all via state deletes all proposals, mode returns to detail',
        () {
      final ticketBoard = resources.track(TicketBoardState('int-test-3'));
      final chat = resources.track(
        ChatState.create(name: 'Agent Chat', worktreeRoot: '/tmp/test'),
      );
      final handler = EventHandler(ticketBoard: ticketBoard);

      // Create a pre-existing ticket (should survive rejection)
      final preExisting = ticketBoard.createTicket(
        title: 'Pre-existing ticket',
        kind: TicketKind.feature,
      );

      // Simulate agent calling create_tickets
      final event = makeCreateTicketsEvent(
        callId: 'reject-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'Proposal A', description: 'Desc A'),
            makeProposalJson(title: 'Proposal B', description: 'Desc B'),
            makeProposalJson(title: 'Proposal C', description: 'Desc C'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      expect(ticketBoard.proposedTickets.length, 3);
      expect(ticketBoard.tickets.length, 4); // 1 pre-existing + 3 proposals

      // Reject all
      ticketBoard.rejectAll();

      // All proposals deleted, pre-existing survives
      expect(ticketBoard.tickets.length, 1);
      expect(ticketBoard.tickets.first.id, preExisting.id);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);

      // Tool result reflects rejection
      expect(handler.hasPendingTicketReview, isFalse);
      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      expect(toolEntry.result, isNotNull);
      expect(toolEntry.result.toString(), contains('rejected by the user'));

      handler.dispose();
    });

    testWidgets('reject all via widget removes all proposals', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ticketBoard = resources.track(TicketBoardState('int-test-4'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Bad idea A',
            kind: TicketKind.feature,
            description: 'Should be rejected',
          ),
          const TicketProposal(
            title: 'Bad idea B',
            kind: TicketKind.feature,
            description: 'Should also be rejected',
          ),
        ],
        sourceChatId: 'chat-2',
        sourceChatName: 'Test Agent',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
              child: const TicketBulkReviewPanel(),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      expect(find.text('Bad idea A'), findsOneWidget);
      expect(find.text('Bad idea B'), findsOneWidget);

      // Tap Reject All
      await tester.tap(find.byKey(TicketBulkReviewKeys.rejectAllButton));
      await safePumpAndSettle(tester);

      // All proposals deleted
      expect(ticketBoard.getTicket(proposals[0].id), isNull);
      expect(ticketBoard.getTicket(proposals[1].id), isNull);
      expect(ticketBoard.tickets, isEmpty);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);
    });
  });

  group('Phase 2 Integration - Edit before approve', () {
    test('edit title via state then approve preserves edited value', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-5'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Original Title',
            kind: TicketKind.feature,
            description: 'Some description',
          ),
          const TicketProposal(
            title: 'Another Ticket',
            kind: TicketKind.bugfix,
            description: 'Bug description',
          ),
        ],
        sourceChatId: 'chat-3',
        sourceChatName: 'Agent Chat',
      );

      // Edit the first proposal's title
      ticketBoard.updateTicket(
        proposals[0].id,
        (t) => t.copyWith(title: 'Edited Title'),
      );

      // Verify the edit took effect before approval
      final editedTicket = ticketBoard.getTicket(proposals[0].id);
      expect(editedTicket?.title, 'Edited Title');

      // Approve all
      ticketBoard.approveBulk();

      // The edited title should persist after approval
      final approvedTicket = ticketBoard.getTicket(proposals[0].id);
      expect(approvedTicket, isNotNull);
      expect(approvedTicket!.status, TicketStatus.ready);
      expect(approvedTicket.title, 'Edited Title');

      // The second ticket should also be approved with its original title
      final secondTicket = ticketBoard.getTicket(proposals[1].id);
      expect(secondTicket, isNotNull);
      expect(secondTicket!.title, 'Another Ticket');
      expect(secondTicket.status, TicketStatus.ready);
    });

    testWidgets('edit title in inline edit card then approve', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final ticketBoard = resources.track(TicketBoardState('int-test-6'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Needs editing',
            kind: TicketKind.feature,
            description: 'Will be edited',
            category: 'Backend',
          ),
          const TicketProposal(
            title: 'Keep as is',
            kind: TicketKind.bugfix,
            description: 'No changes',
          ),
        ],
        sourceChatId: 'chat-4',
        sourceChatName: 'Editor Agent',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<TicketBoardState>.value(
              value: ticketBoard,
              child: const TicketBulkReviewPanel(),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Tap the first row to open inline edit card
      await tester.tap(find.text('Needs editing'));
      await safePumpAndSettle(tester);

      // Edit card should be visible
      expect(find.byKey(TicketBulkReviewKeys.editCard), findsOneWidget);

      // Find the title TextField and clear it, then enter new text
      final titleFields = find.byType(TextField);
      // The first TextField in the edit card should be the title field
      final titleField = tester.widgetList<TextField>(titleFields).firstWhere(
        (tf) => tf.controller?.text == 'Needs editing',
      );
      expect(titleField.controller, isNotNull);

      // Find the corresponding widget in the tree and enter text
      final titleFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Needs editing',
      );
      await tester.tap(titleFinder);
      await safePumpAndSettle(tester);

      // Clear and type new title
      await tester.enterText(titleFinder, 'Edited via UI');
      await safePumpAndSettle(tester);

      // Verify the state was updated
      final editedTicket = ticketBoard.getTicket(proposals[0].id);
      expect(editedTicket?.title, 'Edited via UI');

      // Now approve
      await tester.tap(find.byKey(TicketBulkReviewKeys.approveButton));
      await safePumpAndSettle(tester);

      // Verify edited title persisted after approval
      final approved = ticketBoard.getTicket(proposals[0].id);
      expect(approved, isNotNull);
      expect(approved!.title, 'Edited via UI');
      expect(approved.status, TicketStatus.ready);
    });
  });

  group('Phase 2 Integration - Dependency resolution', () {
    test('proposals with dependsOnIndices resolve to real ticket IDs', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-7'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Base infrastructure',
            kind: TicketKind.feature,
            description: 'Set up project structure',
          ),
          const TicketProposal(
            title: 'Database layer',
            kind: TicketKind.feature,
            description: 'Depends on base infrastructure',
            dependsOnIndices: [0],
          ),
          const TicketProposal(
            title: 'API endpoints',
            kind: TicketKind.feature,
            description: 'Depends on both base and database',
            dependsOnIndices: [0, 1],
          ),
          const TicketProposal(
            title: 'Tests for API',
            kind: TicketKind.test,
            description: 'Depends on API endpoints only',
            dependsOnIndices: [2],
          ),
        ],
        sourceChatId: 'chat-5',
        sourceChatName: 'Planner Agent',
      );

      // Verify index-based dependencies were converted to real IDs
      // Index 0 -> proposals[0].id
      // Index 1 -> proposals[1].id
      // Index 2 -> proposals[2].id

      // proposals[0] has no dependencies
      expect(proposals[0].dependsOn, isEmpty);

      // proposals[1] depends on proposals[0]
      expect(proposals[1].dependsOn, [proposals[0].id]);

      // proposals[2] depends on proposals[0] and proposals[1]
      expect(proposals[2].dependsOn, [proposals[0].id, proposals[1].id]);

      // proposals[3] depends on proposals[2]
      expect(proposals[3].dependsOn, [proposals[2].id]);

      // Also verify via getTicket (state-level check)
      final t1 = ticketBoard.getTicket(proposals[1].id)!;
      expect(t1.dependsOn, [proposals[0].id]);

      final t2 = ticketBoard.getTicket(proposals[2].id)!;
      expect(t2.dependsOn, [proposals[0].id, proposals[1].id]);

      final t3 = ticketBoard.getTicket(proposals[3].id)!;
      expect(t3.dependsOn, [proposals[2].id]);
    });

    test('dependencies survive approval and point to correct IDs', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-8'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Foundation',
            kind: TicketKind.feature,
            description: 'Base work',
          ),
          const TicketProposal(
            title: 'Build on foundation',
            kind: TicketKind.feature,
            description: 'Depends on foundation',
            dependsOnIndices: [0],
          ),
        ],
        sourceChatId: 'chat-6',
        sourceChatName: 'Agent',
      );

      // Approve all
      ticketBoard.approveBulk();

      // Both should be ready
      final t0 = ticketBoard.getTicket(proposals[0].id)!;
      final t1 = ticketBoard.getTicket(proposals[1].id)!;
      expect(t0.status, TicketStatus.ready);
      expect(t1.status, TicketStatus.ready);

      // Dependency should still point from t1 to t0
      expect(t1.dependsOn, [t0.id]);
    });

    test('deleted unchecked ticket is removed from dependsOn of kept tickets',
        () {
      final ticketBoard = resources.track(TicketBoardState('int-test-9'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Will be deleted',
            kind: TicketKind.feature,
            description: 'This one gets unchecked',
          ),
          const TicketProposal(
            title: 'Depends on deleted',
            kind: TicketKind.feature,
            description: 'Has dependency on index 0',
            dependsOnIndices: [0],
          ),
        ],
        sourceChatId: 'chat-7',
        sourceChatName: 'Agent',
      );

      // Verify dependency is set
      expect(proposals[1].dependsOn, [proposals[0].id]);

      // Uncheck the first proposal (the dependency target)
      ticketBoard.toggleProposalChecked(proposals[0].id);

      // Approve: first is deleted, second is kept
      ticketBoard.approveBulk();

      // First ticket should be gone
      expect(ticketBoard.getTicket(proposals[0].id), isNull);

      // Second ticket should be ready, and its dependency on the deleted
      // ticket should have been cleaned up
      final kept = ticketBoard.getTicket(proposals[1].id)!;
      expect(kept.status, TicketStatus.ready);
      expect(kept.dependsOn, isEmpty);
    });

    test('out-of-range dependency indices are silently dropped', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-10'));

      final proposals = ticketBoard.proposeBulk(
        [
          const TicketProposal(
            title: 'Base ticket',
            kind: TicketKind.feature,
            description: 'First ticket',
          ),
          const TicketProposal(
            title: 'Has bad deps',
            kind: TicketKind.feature,
            description: 'References invalid indices',
            dependsOnIndices: [0, 5, -1, 99],
          ),
        ],
        sourceChatId: 'chat-8',
        sourceChatName: 'Agent',
      );

      // Only index 0 is valid; 5, -1, 99 are out of range
      expect(proposals[1].dependsOn, [proposals[0].id]);
    });
  });

  group('Phase 2 Integration - End-to-end via EventHandler', () {
    test('full round-trip: tool event -> proposals -> approve -> tool result',
        () {
      final ticketBoard = resources.track(TicketBoardState('int-test-11'));
      final chat = resources.track(
        ChatState.create(name: 'Planning Chat', worktreeRoot: '/tmp/test'),
      );
      final handler = EventHandler(ticketBoard: ticketBoard);

      // Step 1: Simulate the tool event from the agent
      final event = makeCreateTicketsEvent(
        callId: 'e2e-call-1',
        input: {
          'tickets': [
            makeProposalJson(
              title: 'Auth service',
              description: 'Set up OAuth2',
              kind: 'feature',
              priority: 'high',
              category: 'Auth',
            ),
            makeProposalJson(
              title: 'JWT tokens',
              description: 'Token management',
              kind: 'feature',
              priority: 'medium',
              category: 'Auth',
              dependsOnIndices: [0],
            ),
          ],
        },
      );

      handler.handleEvent(chat, event);

      // Step 2: Verify proposals are staged
      expect(ticketBoard.proposedTickets.length, 2);
      expect(ticketBoard.detailMode, TicketDetailMode.bulkReview);
      expect(handler.hasPendingTicketReview, isTrue);

      // Step 3: Verify proposal metadata
      expect(ticketBoard.proposalSourceChatName, 'Planning Chat');
      expect(ticketBoard.proposalSourceChatId, chat.data.id);

      // Step 4: Verify dependency resolution happened
      final proposed = ticketBoard.proposedTickets;
      expect(proposed[1].dependsOn, [proposed[0].id]);

      // Step 5: Approve all
      ticketBoard.approveBulk();

      // Step 6: Verify final state
      expect(ticketBoard.tickets.length, 2);
      expect(ticketBoard.tickets[0].status, TicketStatus.ready);
      expect(ticketBoard.tickets[1].status, TicketStatus.ready);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);

      // Step 7: Verify tool result was sent
      expect(handler.hasPendingTicketReview, isFalse);
      final entries = chat.data.primaryConversation.entries;
      final toolEntry = entries.first as ToolUseOutputEntry;
      expect(toolEntry.result, isNotNull);
      expect(
        toolEntry.result.toString(),
        contains('2 ticket proposals were approved'),
      );

      handler.dispose();
    });

    test('onBulkReviewComplete callback is properly wired and fired', () {
      final ticketBoard = resources.track(TicketBoardState('int-test-12'));
      final chat = resources.track(
        ChatState.create(name: 'Callback Chat', worktreeRoot: '/tmp/test'),
      );
      final handler = EventHandler(ticketBoard: ticketBoard);

      final event = makeCreateTicketsEvent(
        callId: 'callback-call-1',
        input: {
          'tickets': [
            makeProposalJson(title: 'Callback test A', description: 'A'),
            makeProposalJson(title: 'Callback test B', description: 'B'),
          ],
        },
      );

      handler.handleEvent(chat, event);

      // The callback should be wired on ticketBoard
      expect(ticketBoard.onBulkReviewComplete, isNotNull);

      // Approve triggers the callback
      ticketBoard.approveBulk();

      // After callback fires, it should be cleared
      expect(ticketBoard.onBulkReviewComplete, isNull);
      expect(handler.hasPendingTicketReview, isFalse);

      handler.dispose();
    });
  });
}
