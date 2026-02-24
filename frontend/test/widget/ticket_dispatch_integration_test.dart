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
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/services/ticket_dispatch_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

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
      'full dispatch flow: create ticket, dispatch to worktree, verify links and tags',
      () async {
        // 1. Create a ticket
        final ticket = ticketBoard.createTicket(
          title: 'Add dark mode',
          body: 'Implement dark mode toggle for the app.',
          tags: {'feature', 'high'},
        );

        check(ticket.isOpen).isTrue();
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

        // 6. Verify ticket is still open and tagged as active
        final updated = ticketBoard.getTicket(ticket.id)!;
        check(updated.isOpen).isTrue();
        check(updated.tags.contains('active')).isTrue();

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
        check(chatState.viewState.draftText).contains('#1');
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
          body: 'Users cannot log in after password reset.',
          tags: {'bugfix'},
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

        // 5. Verify ticket is open and tagged active
        final updated = ticketBoard.getTicket(ticket.id)!;
        check(updated.isOpen).isTrue();
        check(updated.tags.contains('active')).isTrue();

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

  group('Dispatch flow - tag transitions end-to-end', () {
    test(
      'dispatch -> turn complete -> in-review tag -> close ticket',
      () {
        // 1. Create a ticket and simulate dispatch by tagging active + linking
        final ticket = ticketBoard.createTicket(
          title: 'Implement API endpoint',
          tags: {'feature', 'active'},
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

        // 4. Verify ticket got 'in-review' tag
        final afterTurn = ticketBoard.getTicket(ticket.id)!;
        check(afterTurn.tags.contains('in-review')).isTrue();
        check(afterTurn.isOpen).isTrue();

        // 5. Close the ticket
        ticketBoard.closeTicket(
          ticket.id,
          'test-user',
          AuthorType.user,
        );

        // 6. Verify ticket is closed
        final afterClose = ticketBoard.getTicket(ticket.id)!;
        check(afterClose.isOpen).isFalse();

        handler.dispose();
      },
    );

    test(
      'dispatch -> permission request -> needs-input tag -> permission response -> tag removed -> turn complete -> in-review tag',
      () {
        // 1. Create an open ticket with linked chat
        final ticket = ticketBoard.createTicket(
          title: 'Refactor database layer',
          tags: {'feature', 'active'},
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

        // 2. Simulate permission request -> needs-input tag
        final permEvent = makePermissionRequestEvent();
        handler.handleEvent(chat, permEvent);

        final afterPerm = ticketBoard.getTicket(ticket.id)!;
        check(afterPerm.tags.contains('needs-input')).isTrue();

        // 3. Simulate permission response -> needs-input tag removed
        handler.handlePermissionResponse(chat);

        final afterResponse = ticketBoard.getTicket(ticket.id)!;
        check(afterResponse.tags.contains('needs-input')).isFalse();

        // 4. Simulate turn complete -> in-review tag
        final turnEvent = makeTurnCompleteEvent(
          usage: const TokenUsage(inputTokens: 3000, outputTokens: 1000),
          costUsd: 0.08,
          durationMs: 5000,
        );
        handler.handleEvent(chat, turnEvent);

        final afterTurn = ticketBoard.getTicket(ticket.id)!;
        check(afterTurn.tags.contains('in-review')).isTrue();

        handler.dispose();
      },
    );

    test('closed ticket is not tagged by further turn completes', () {
      final ticket = ticketBoard.createTicket(
        title: 'Already done',
        tags: {'feature'},
      );
      // Close the ticket
      ticketBoard.closeTicket(ticket.id, 'test-user', AuthorType.user);

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

      // Should remain closed and not get 'in-review' tag
      final updated = ticketBoard.getTicket(ticket.id)!;
      check(updated.isOpen).isFalse();
      check(updated.tags.contains('in-review')).isFalse();

      handler.dispose();
    });
  });

  group('Dispatch flow - dependency auto-unblock integration', () {
    test('closing dispatched ticket unblocks dependent ticket', () {
      // 1. Create dependency chain: ticket B depends on ticket A
      final ticketA = ticketBoard.createTicket(
        title: 'Build API',
        tags: {'feature', 'active'},
      );
      final ticketB = ticketBoard.createTicket(
        title: 'Build UI',
        tags: {'feature'},
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

      // 2. Verify B is open and depends on A
      check(ticketBoard.getTicket(ticketB.id)!.isOpen).isTrue();
      check(ticketBoard.getTicket(ticketB.id)!.dependsOn).contains(ticketA.id);

      // 3. Close ticket A (simulating user marking complete after agent work)
      ticketBoard.closeTicket(ticketA.id, 'test-user', AuthorType.user);

      // 4. Ticket A should be closed
      check(ticketBoard.getTicket(ticketA.id)!.isOpen).isFalse();

      // 5. Ticket B should still be open (it was never closed)
      check(ticketBoard.getTicket(ticketB.id)!.isOpen).isTrue();
    });

    test('closing one of multiple deps fires onTicketReady when all closed', () async {
      final dep1 = ticketBoard.createTicket(
        title: 'Database setup',
        tags: {'feature', 'active'},
      );
      final dep2 = ticketBoard.createTicket(
        title: 'Auth setup',
        tags: {'feature', 'active'},
      );
      final dependent = ticketBoard.createTicket(
        title: 'Main feature',
        tags: {'feature'},
        dependsOn: [dep1.id, dep2.id],
      );

      // Listen for the onTicketReady stream
      final readyTickets = <TicketData>[];
      final sub = ticketBoard.onTicketReady.listen(readyTickets.add);

      // Close only dep1 — dependent should NOT become ready yet
      ticketBoard.closeTicket(dep1.id, 'test-user', AuthorType.user);

      // Allow async events to propagate
      await Future<void>.delayed(Duration.zero);
      check(readyTickets).isEmpty();

      // Now close dep2 — dependent should become ready
      ticketBoard.closeTicket(dep2.id, 'test-user', AuthorType.user);

      await Future<void>.delayed(Duration.zero);
      check(readyTickets).length.equals(1);
      check(readyTickets.first.id).equals(dependent.id);

      await sub.cancel();
    });
  });

  // NOTE: Widget tests for TicketDetailPanel removed pending V2 migration
  // of ticket_detail_panel.dart and ticket_visuals.dart (separate ticket).

  group('Dispatch flow - prompt building integration', () {
    test('dispatch builds prompt with ticket info and dependency context', () {
      // 1. Create dependency ticket and close it
      final dep = ticketBoard.createTicket(
        title: 'Setup database',
        body: 'Create PostgreSQL schema.',
        tags: {'feature'},
      );
      ticketBoard.closeTicket(dep.id, 'test-user', AuthorType.user);

      // 2. Create main ticket with dependency
      final ticket = ticketBoard.createTicket(
        title: 'Build user auth',
        body: 'Implement user authentication with JWT tokens.',
        tags: {'feature', 'high', 'large', 'backend', 'auth', 'security'},
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
      check(prompt).contains('#2');
      check(prompt).contains('Build user auth');
      check(prompt).contains('Implement user authentication with JWT tokens.');
      check(prompt).contains('**Tags:**');
      check(prompt).contains('auth');
      check(prompt).contains('security');
      check(prompt).contains('## Completed Dependencies');
      check(prompt).contains('[x] #1: Setup database');
    });
  });

  group('Dispatch flow - persistence round-trip', () {
    test('ticket links survive save and reload', () async {
      // 1. Create a ticket and add links
      final ticket = ticketBoard.createTicket(
        title: 'Persistent linking test',
        tags: {'feature', 'active'},
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
      check(reloaded.isOpen).isTrue();
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

    test('tags survive save and reload', () async {
      // 1. Create a ticket with tags
      final ticket = ticketBoard.createTicket(
        title: 'Tag persistence test',
        tags: {'feature', 'active'},
      );

      // 2. Save explicitly
      await ticketBoard.save();

      // 3. Load in a fresh state
      final ticketBoard2 = resources.track(
        TicketRepository('test-dispatch-integration'),
      );
      await ticketBoard2.load();

      // 4. Verify tags survived
      final reloaded = ticketBoard2.getTicket(ticket.id)!;
      check(reloaded.tags.contains('feature')).isTrue();
      check(reloaded.tags.contains('active')).isTrue();
    });
  });
}
