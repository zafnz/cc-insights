import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        BackendProvider,
        PermissionRequestEvent,
        TurnCompleteEvent,
        TokenUsage,
        ToolKind;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/ticket_detail_panel.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/services/ticket_dispatch_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-dispatch-${_idCounter++}';

/// Helper to create a TurnCompleteEvent with optional usage data.
TurnCompleteEvent makeTurnCompleteEvent({
  TokenUsage? usage,
  double? costUsd,
  int? durationMs,
}) {
  return TurnCompleteEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    usage: usage,
    costUsd: costUsd,
    durationMs: durationMs,
  );
}

/// Helper to create a PermissionRequestEvent.
PermissionRequestEvent makePermissionRequestEvent() {
  return PermissionRequestEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    requestId: 'req-${_nextId()}',
    toolName: 'Bash',
    toolKind: ToolKind.execute,
    toolInput: {'command': 'ls'},
  );
}

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;
  late TicketRepository ticketBoard;
  late FakeGitService fakeGit;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    ticketBoard = resources.track(
      TicketRepository('test-dispatch-integration'),
    );
    fakeGit = FakeGitService();
    _idCounter = 0;
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('Dispatch flow - state level', () {
    late ProjectState project;
    late SelectionState selection;

    setUp(() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );

      project = resources.track(
        ProjectState(
          const ProjectData(name: 'test-project', repoRoot: '/test/repo'),
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      selection = resources.track(SelectionState(project));
    });

    test(
      'full dispatch flow: create ticket, dispatch to worktree, verify links and status',
      () async {
        // 1. Create a ticket
        final ticket = ticketBoard.createTicket(
          title: 'Add dark mode',
          kind: TicketKind.feature,
          description: 'Implement dark mode toggle for the app.',
          priority: TicketPriority.high,
        );

        check(ticket.status).equals(TicketStatus.ready);
        check(ticket.linkedWorktrees).isEmpty();
        check(ticket.linkedChats).isEmpty();

        // 2. Verify the branch name derivation
        final expectedBranch = TicketDispatchService.deriveBranchName(
          ticket.id,
          ticket.title,
        );
        check(expectedBranch).equals('tkt-1-add-dark-mode');

        // 3. Create an existing worktree to dispatch into
        // (Using beginInWorktree avoids the complexity of real git worktree
        // creation while still testing the full state flow)
        final worktree = WorktreeState(
          WorktreeData(
            worktreeRoot: '/test/worktrees/$expectedBranch',
            isPrimary: false,
            branch: expectedBranch,
          ),
        );
        project.addLinkedWorktree(worktree);

        // 4. Create dispatch service
        final dispatch = TicketDispatchService(
          ticketBoard: ticketBoard,
          project: project,
          selection: selection,
          worktreeService: WorktreeService(gitService: fakeGit),
          restoreService: ProjectRestoreService(),
        );

        // 5. Dispatch to the worktree
        await dispatch.beginInWorktree(ticket.id, worktree);

        // 6. Verify ticket status changed to active
        final updated = ticketBoard.getTicket(ticket.id)!;
        check(updated.status).equals(TicketStatus.active);

        // 7. Verify ticket linked to worktree
        check(updated.linkedWorktrees).length.equals(1);
        check(
          updated.linkedWorktrees.first.worktreeRoot,
        ).equals('/test/worktrees/$expectedBranch');
        check(updated.linkedWorktrees.first.branch).equals(expectedBranch);

        // 8. Verify ticket linked to chat
        check(updated.linkedChats).length.equals(1);
        check(updated.linkedChats.first.chatName).equals(ticket.displayId);
        check(
          updated.linkedChats.first.worktreeRoot,
        ).equals('/test/worktrees/$expectedBranch');

        // 9. Verify chat was added to the worktree
        check(worktree.chats).length.equals(1);

        // 10. Verify chat has the ticket prompt as draft text
        final chatState = worktree.chats.first;
        check(chatState.viewState.draftText).isNotNull();
        check(chatState.viewState.draftText).contains('TKT-001');
        check(chatState.viewState.draftText).contains('Add dark mode');

        // 11. Verify selection was updated
        check(selection.selectedChat).isNotNull();
        check(selection.selectedChat!.data.name).equals(ticket.displayId);
      },
    );

    test(
      'begin in existing worktree: creates chat in existing worktree',
      () async {
        // 1. Create a ticket
        final ticket = ticketBoard.createTicket(
          title: 'Fix login bug',
          kind: TicketKind.bugfix,
          description: 'Users cannot log in after password reset.',
        );

        // 2. Create an existing linked worktree
        final existingWorktree = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/test/worktrees/fix-login',
            isPrimary: false,
            branch: 'fix-login',
          ),
        );
        project.addLinkedWorktree(existingWorktree);

        // 3. Create dispatch service
        final dispatch = TicketDispatchService(
          ticketBoard: ticketBoard,
          project: project,
          selection: selection,
          worktreeService: WorktreeService(gitService: fakeGit),
          restoreService: ProjectRestoreService(),
        );

        // 4. Begin in existing worktree
        await dispatch.beginInWorktree(ticket.id, existingWorktree);

        // 5. Verify ticket status changed to active
        final updated = ticketBoard.getTicket(ticket.id)!;
        check(updated.status).equals(TicketStatus.active);

        // 6. Verify ticket linked to the existing worktree
        check(updated.linkedWorktrees).length.equals(1);
        check(
          updated.linkedWorktrees.first.worktreeRoot,
        ).equals('/test/worktrees/fix-login');
        check(updated.linkedWorktrees.first.branch).equals('fix-login');

        // 7. Verify ticket linked to chat
        check(updated.linkedChats).length.equals(1);
        check(updated.linkedChats.first.chatName).equals(ticket.displayId);
        check(
          updated.linkedChats.first.worktreeRoot,
        ).equals('/test/worktrees/fix-login');

        // 8. Verify chat was added to the worktree
        check(existingWorktree.chats).length.equals(1);

        // 9. Verify selection was updated to the worktree and chat
        check(selection.selectedChat).isNotNull();
        check(selection.selectedChat!.data.name).equals(ticket.displayId);
      },
    );
  });

  group('Dispatch flow - status transitions end-to-end', () {
    test(
      'dispatch -> turn complete -> inReview -> mark complete -> completed',
      () {
        // 1. Create a ticket and simulate dispatch by setting status + linking
        final ticket = ticketBoard.createTicket(
          title: 'Implement API endpoint',
          kind: TicketKind.feature,
          status: TicketStatus.active,
        );

        final chat = resources.track(
          Chat.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
        );

        // Link the chat to the ticket
        ticketBoard.linkChat(
          ticket.id,
          chat.data.id,
          chat.data.name,
          '/tmp/test',
        );

        // 2. Create event handler with ticket board
        final handler = EventHandler(ticketBoard: ticketBoard);

        // 3. Simulate agent turn complete
        final turnEvent = makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 5000, outputTokens: 2000),
          costUsd: 0.15,
          durationMs: 10000,
        );
        handler.handleEvent(chat, turnEvent);

        // 4. Verify ticket transitioned to inReview
        final afterTurn = ticketBoard.getTicket(ticket.id)!;
        check(afterTurn.status).equals(TicketStatus.inReview);

        // 5. Verify cost stats were accumulated
        check(afterTurn.costStats).isNotNull();
        check(afterTurn.costStats!.totalTokens).equals(7000);
        check(afterTurn.costStats!.totalCost).equals(0.15);
        check(afterTurn.costStats!.agentTimeMs).equals(10000);

        // 6. Mark the ticket as completed
        ticketBoard.markCompleted(ticket.id);

        // 7. Verify terminal status
        final afterComplete = ticketBoard.getTicket(ticket.id)!;
        check(afterComplete.status).equals(TicketStatus.completed);
        check(afterComplete.isTerminal).isTrue();

        handler.dispose();
      },
    );

    test(
      'dispatch -> permission request -> needsInput -> permission response -> active -> turn complete -> inReview',
      () {
        // 1. Create an active ticket with linked chat
        final ticket = ticketBoard.createTicket(
          title: 'Refactor database layer',
          kind: TicketKind.feature,
          status: TicketStatus.active,
        );

        final chat = resources.track(
          Chat.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
        );

        ticketBoard.linkChat(
          ticket.id,
          chat.data.id,
          chat.data.name,
          '/tmp/test',
        );

        final handler = EventHandler(ticketBoard: ticketBoard);

        // 2. Simulate permission request -> needsInput
        final permEvent = makePermissionRequestEvent();
        handler.handleEvent(chat, permEvent);

        final afterPerm = ticketBoard.getTicket(ticket.id)!;
        check(afterPerm.status).equals(TicketStatus.needsInput);

        // 3. Simulate permission response -> back to active
        handler.handlePermissionResponse(chat);

        final afterResponse = ticketBoard.getTicket(ticket.id)!;
        check(afterResponse.status).equals(TicketStatus.active);

        // 4. Simulate turn complete -> inReview
        final turnEvent = makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 3000, outputTokens: 1000),
          costUsd: 0.08,
          durationMs: 5000,
        );
        handler.handleEvent(chat, turnEvent);

        final afterTurn = ticketBoard.getTicket(ticket.id)!;
        check(afterTurn.status).equals(TicketStatus.inReview);

        handler.dispose();
      },
    );

    test('multiple turns accumulate cost stats correctly', () {
      final ticket = ticketBoard.createTicket(
        title: 'Multi-turn task',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      final chat = resources.track(
        Chat.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );

      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Turn 1
      handler.handleEvent(
        chat,
        makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
          costUsd: 0.05,
          durationMs: 3000,
        ),
      );

      // After turn 1: status is inReview, but for the next turn to accumulate
      // we need it non-terminal. inReview is non-terminal, so turn 2 will
      // still accumulate cost and set inReview again.

      // Turn 2
      handler.handleEvent(
        chat,
        makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 2000, outputTokens: 800),
          costUsd: 0.08,
          durationMs: 5000,
        ),
      );

      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.inReview);
      check(updated.costStats!.totalTokens).equals(4300); // 1500 + 2800
      check(updated.costStats!.totalCost).equals(0.13);
      check(updated.costStats!.agentTimeMs).equals(8000);

      handler.dispose();
    });

    test('completed ticket is not transitioned by further turn completes', () {
      final ticket = ticketBoard.createTicket(
        title: 'Already done',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      final chat = resources.track(
        Chat.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );

      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      final handler = EventHandler(ticketBoard: ticketBoard);

      handler.handleEvent(
        chat,
        makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 500, outputTokens: 200),
          costUsd: 0.02,
          durationMs: 1000,
        ),
      );

      // Status should remain completed
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.status).equals(TicketStatus.completed);

      // Cost stats SHOULD still accumulate even for terminal tickets
      check(updated.costStats).isNotNull();
      check(updated.costStats!.totalTokens).equals(700);

      handler.dispose();
    });
  });

  group('Dispatch flow - dependency auto-unblock integration', () {
    test('completing dispatched ticket unblocks dependent ticket', () {
      // 1. Create dependency chain: ticket B depends on ticket A
      final ticketA = ticketBoard.createTicket(
        title: 'Build API',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final ticketB = ticketBoard.createTicket(
        title: 'Build UI',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [ticketA.id],
      );

      final chat = resources.track(
        Chat.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );

      // Link chat to ticket A
      ticketBoard.linkChat(
        ticketA.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );

      // 2. Verify B is blocked
      check(
        ticketBoard.getTicket(ticketB.id)!.status,
      ).equals(TicketStatus.blocked);

      // 3. Complete ticket A (simulating user marking complete after agent work)
      ticketBoard.markCompleted(ticketA.id);

      // 4. Ticket B should now be auto-unblocked to ready
      final updatedB = ticketBoard.getTicket(ticketB.id)!;
      check(updatedB.status).equals(TicketStatus.ready);

      // 5. Ticket A should be completed
      check(
        ticketBoard.getTicket(ticketA.id)!.status,
      ).equals(TicketStatus.completed);
    });

    test('completing one of multiple deps does not unblock', () {
      final dep1 = ticketBoard.createTicket(
        title: 'Database setup',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dep2 = ticketBoard.createTicket(
        title: 'Auth setup',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dependent = ticketBoard.createTicket(
        title: 'Main feature',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [dep1.id, dep2.id],
      );

      // Complete only dep1
      ticketBoard.markCompleted(dep1.id);

      // Dependent should still be blocked (dep2 not complete)
      check(
        ticketBoard.getTicket(dependent.id)!.status,
      ).equals(TicketStatus.blocked);

      // Now complete dep2
      ticketBoard.markCompleted(dep2.id);

      // Now dependent should be unblocked
      check(
        ticketBoard.getTicket(dependent.id)!.status,
      ).equals(TicketStatus.ready);
    });
  });

  group('Dispatch flow - linked chat widget verification', () {
    late ProjectState project;
    late SelectionState selection;
    late TicketViewState viewState;
    late BulkProposalState bulkState;

    setUp(() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      project = resources.track(
        ProjectState(
          const ProjectData(name: 'Test Project', repoRoot: '/test/repo'),
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      selection = resources.track(SelectionState(project));
      viewState = resources.track(TicketViewState(ticketBoard));
      bulkState = resources.track(BulkProposalState(ticketBoard));
    });

    Widget createTestApp() {
      return MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<TicketRepository>.value(
                value: ticketBoard,
              ),
              ChangeNotifierProvider<TicketViewState>.value(value: viewState),
              ChangeNotifierProvider<BulkProposalState>.value(value: bulkState),
              ChangeNotifierProvider<ProjectState>.value(value: project),
              ChangeNotifierProvider<SelectionState>.value(value: selection),
              Provider<GitService>.value(value: fakeGit),
            ],
            child: const TicketDetailPanel(),
          ),
        ),
      );
    }

    testWidgets('Open linked chat button appears after dispatch linking', (
      tester,
    ) async {
      // 1. Create a ticket
      final ticket = ticketBoard.createTicket(
        title: 'Test linked chat visibility',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      viewState.selectTicket(ticket.id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // 2. Open linked chat button should NOT be visible (no linked chats yet)
      expect(
        find.byKey(TicketDetailPanelKeys.openLinkedChatButton),
        findsNothing,
      );

      // 3. Simulate dispatch linking (link chat to ticket)
      ticketBoard.linkChat(
        ticket.id,
        'chat-dispatched',
        'TKT-001',
        '/test/repo',
      );

      await safePumpAndSettle(tester);

      // 4. Open linked chat button should now be visible
      expect(
        find.byKey(TicketDetailPanelKeys.openLinkedChatButton),
        findsOneWidget,
      );
      expect(find.text('Open linked chat'), findsOneWidget);
    });

    testWidgets(
      'Linked work section shows worktree and chat info after dispatch',
      (tester) async {
        // 1. Create a ticket with linked worktree and chat
        final ticket = ticketBoard.createTicket(
          title: 'Test linked work display',
          kind: TicketKind.feature,
          status: TicketStatus.active,
        );
        ticketBoard.linkWorktree(
          ticket.id,
          '/test/worktree/path',
          'tkt-1-test-linked-work-display',
        );
        ticketBoard.linkChat(
          ticket.id,
          'chat-123',
          'TKT-001',
          '/test/worktree/path',
        );
        viewState.selectTicket(ticket.id);

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // 2. Verify linked work section shows worktree branch and chat name
        expect(find.text('tkt-1-test-linked-work-display'), findsOneWidget);
        expect(find.text('TKT-001'), findsWidgets); // Also in header
      },
    );

    testWidgets('Begin buttons disabled for active dispatched ticket', (
      tester,
    ) async {
      // 1. Create a dispatched (active) ticket
      final ticket = ticketBoard.createTicket(
        title: 'Active dispatched ticket',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkChat(ticket.id, 'chat-1', 'TKT-001', '/test/repo');
      viewState.selectTicket(ticket.id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // 2. Begin buttons should be disabled (ticket is active)
      final beginNewWt = tester.widget<FilledButton>(
        find.byKey(TicketDetailPanelKeys.beginNewWorktreeButton),
      );
      final beginInWt = tester.widget<OutlinedButton>(
        find.byKey(TicketDetailPanelKeys.beginInWorktreeButton),
      );

      expect(beginNewWt.onPressed, isNull);
      expect(beginInWt.onPressed, isNull);

      // 3. Open linked chat should be visible
      expect(
        find.byKey(TicketDetailPanelKeys.openLinkedChatButton),
        findsOneWidget,
      );
    });

    testWidgets('Mark Complete and Cancel hidden for completed ticket', (
      tester,
    ) async {
      // 1. Create a completed ticket
      final ticket = ticketBoard.createTicket(
        title: 'Completed dispatched ticket',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      ticketBoard.linkChat(ticket.id, 'chat-1', 'TKT-001', '/test/repo');
      viewState.selectTicket(ticket.id);

      await tester.pumpWidget(createTestApp());
      await safePumpAndSettle(tester);

      // 2. Mark Complete and Cancel should be hidden
      expect(
        find.byKey(TicketDetailPanelKeys.markCompleteButton),
        findsNothing,
      );
      expect(find.byKey(TicketDetailPanelKeys.cancelButton), findsNothing);

      // 3. Begin buttons should be disabled (completed is not ready/needsInput)
      final beginNewWt = tester.widget<FilledButton>(
        find.byKey(TicketDetailPanelKeys.beginNewWorktreeButton),
      );
      expect(beginNewWt.onPressed, isNull);
    });
  });

  group('Dispatch flow - prompt building integration', () {
    test('dispatch builds prompt with ticket info and dependency context', () {
      // 1. Create dependency ticket and mark it completed
      final dep = ticketBoard.createTicket(
        title: 'Setup database',
        kind: TicketKind.feature,
        description: 'Create PostgreSQL schema.',
      );
      ticketBoard.markCompleted(dep.id);

      // 2. Create main ticket with dependency
      final ticket = ticketBoard.createTicket(
        title: 'Build user auth',
        kind: TicketKind.feature,
        description: 'Implement user authentication with JWT tokens.',
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Backend',
        tags: {'auth', 'security'},
        dependsOn: [dep.id],
      );

      // 3. Build prompt using dispatch service
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/tmp/test-repo'),
          WorktreeState(
            const WorktreeData(
              worktreeRoot: '/tmp/test-repo',
              isPrimary: true,
              branch: 'main',
            ),
          ),
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      final selection = resources.track(SelectionState(project));

      final dispatch = TicketDispatchService(
        ticketBoard: ticketBoard,
        project: project,
        selection: selection,
        worktreeService: WorktreeService(),
      );

      final prompt = dispatch.buildTicketPrompt(ticket, ticketBoard.tickets);

      // 4. Verify prompt contains all expected sections
      check(prompt).contains('TKT-002');
      check(prompt).contains('Build user auth');
      check(prompt).contains('Implement user authentication with JWT tokens.');
      check(prompt).contains('**Kind:** Feature');
      check(prompt).contains('**Priority:** High');
      check(prompt).contains('**Effort:** Large');
      check(prompt).contains('**Category:** Backend');
      check(prompt).contains('auth');
      check(prompt).contains('security');
      check(prompt).contains('## Completed Dependencies');
      check(prompt).contains('[x] TKT-001: Setup database');
    });
  });

  group('Dispatch flow - persistence round-trip', () {
    test('ticket links survive save and reload', () async {
      // 1. Create a ticket and add links
      final ticket = ticketBoard.createTicket(
        title: 'Persistent linking test',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.linkWorktree(
        ticket.id,
        '/path/to/worktree',
        'tkt-1-persistent-linking-test',
      );
      ticketBoard.linkChat(
        ticket.id,
        'chat-persist-123',
        'TKT-001',
        '/path/to/worktree',
      );

      // 2. Save explicitly
      await ticketBoard.save();

      // 3. Load in a fresh state
      final ticketBoard2 = resources.track(
        TicketRepository('test-dispatch-integration'),
      );
      await ticketBoard2.load();

      // 4. Verify links survived
      final reloaded = ticketBoard2.getTicket(ticket.id)!;
      check(reloaded.status).equals(TicketStatus.active);
      check(reloaded.linkedWorktrees.length).equals(1);
      check(
        reloaded.linkedWorktrees.first.worktreeRoot,
      ).equals('/path/to/worktree');
      check(
        reloaded.linkedWorktrees.first.branch,
      ).equals('tkt-1-persistent-linking-test');
      check(reloaded.linkedChats.length).equals(1);
      check(reloaded.linkedChats.first.chatId).equals('chat-persist-123');
      check(reloaded.linkedChats.first.chatName).equals('TKT-001');
    });

    test('cost stats survive save and reload', () async {
      // 1. Create a ticket and accumulate cost
      final ticket = ticketBoard.createTicket(
        title: 'Cost persistence test',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      ticketBoard.accumulateCostStats(
        ticket.id,
        tokens: 5000,
        cost: 0.25,
        agentTimeMs: 15000,
      );

      // 2. Save explicitly
      await ticketBoard.save();

      // 3. Load in a fresh state
      final ticketBoard2 = resources.track(
        TicketRepository('test-dispatch-integration'),
      );
      await ticketBoard2.load();

      // 4. Verify cost stats survived
      final reloaded = ticketBoard2.getTicket(ticket.id)!;
      check(reloaded.costStats).isNotNull();
      check(reloaded.costStats!.totalTokens).equals(5000);
      check(reloaded.costStats!.totalCost).equals(0.25);
      check(reloaded.costStats!.agentTimeMs).equals(15000);
    });
  });
}
