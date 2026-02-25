import 'dart:ui';

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
import 'package:cc_insights_v2/services/ticket_storage_service.dart';
import 'package:cc_insights_v2/services/ticket_dispatch_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/state/ticket_view_state.dart';
import 'package:cc_insights_v2/widgets/ticket_graph_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-full-integ-${_idCounter++}';

/// Helper to create a TurnCompleteEvent with optional usage data.
TurnCompleteEvent _makeTurnComplete({
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
PermissionRequestEvent _makePermissionRequest() {
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

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    _idCounter = 0;
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  // ===========================================================================
  // 1. Complete lifecycle: Create -> Dispatch -> Turn Complete -> Mark Done
  // ===========================================================================
  group('Complete lifecycle', () {
    test('create tickets manually -> dispatch (link chat) -> simulate turn '
        'complete -> mark done -> verify status transitions', () {
      final ticketBoard = resources.track(
        TicketRepository('test-full-lifecycle'),
      );

      // 1. Create a ticket
      final ticket = ticketBoard.createTicket(
        title: 'Implement user profile page',
        tags: {'feature', 'ui', 'profile'},
        body: 'Build the user profile page with avatar and settings.',
      );

      expect(ticket.isOpen, true);
      expect(ticket.displayId, '#1');

      // 2. Simulate dispatch: add active tag and link chat
      ticketBoard.addTag(ticket.id, 'active', 'test', AuthorType.user);

      final chat = resources.track(
        Chat.create(name: '#1', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );
      ticketBoard.linkWorktree(ticket.id, '/tmp/test', 'tkt-1-profile');

      final dispatched = ticketBoard.getTicket(ticket.id)!;
      expect(dispatched.tags, contains('active'));
      expect(dispatched.linkedChats.length, 1);
      expect(dispatched.linkedWorktrees.length, 1);

      // 3. Simulate turn complete via EventHandler
      final handler = EventHandler(ticketBoard: ticketBoard);
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 5000, outputTokens: 2000),
          costUsd: 0.15,
          durationMs: 10000,
        ),
      );

      final afterTurn = ticketBoard.getTicket(ticket.id)!;
      expect(afterTurn.tags, contains('in-review'));

      // 4. Mark completed by closing
      ticketBoard.closeTicket(ticket.id, 'test', AuthorType.user);

      final completed = ticketBoard.getTicket(ticket.id)!;
      expect(completed.isOpen, false);

      handler.dispose();
    });
  });

  // ===========================================================================
  // 2. Agent proposal lifecycle
  // ===========================================================================
  group('Agent proposal lifecycle', () {
    test('proposeBulk -> user reviews -> approves subset -> verify tickets '
        'are open and unchecked are deleted', () {
      final ticketBoard = resources.track(
        TicketRepository('test-proposal-lifecycle'),
      );
      final bulkState = resources.track(BulkProposalState(ticketBoard));

      // 1. Create proposals
      final proposals = [
        const TicketProposal(
          title: 'Setup CI/CD pipeline',
          body: 'Configure GitHub Actions for automated testing.',
          tags: {'chore', 'high'},
        ),
        const TicketProposal(
          title: 'Add unit tests for auth module',
          body: 'Write comprehensive unit tests.',
          tags: {'test', 'medium'},
          dependsOnIndices: [0],
        ),
        const TicketProposal(
          title: 'Deploy to staging',
          body: 'Set up staging environment.',
          tags: {'chore', 'low'},
          dependsOnIndices: [0, 1],
        ),
      ];

      // 2. Propose bulk
      final created = bulkState.proposeBulk(
        proposals,
        sourceChatId: 'chat-agent-1',
        sourceChatName: 'Planning Agent',
      );

      expect(created.length, 3);
      expect(bulkState.hasActiveProposal, isTrue);
      expect(bulkState.proposedTickets.length, 3);

      // All should be open (V2: no draft status)
      for (final t in created) {
        expect(ticketBoard.getTicket(t.id)!.isOpen, true);
      }

      // All should be checked by default
      expect(bulkState.proposalCheckedIds.length, 3);

      // Verify dependencies resolved correctly
      final ciTicketId = created[0].id;
      final testTicketId = created[1].id;
      expect(created[1].dependsOn, [ciTicketId]);
      expect(created[2].dependsOn, [ciTicketId, testTicketId]);

      // 3. Uncheck the third ticket (deploy to staging)
      bulkState.toggleProposalChecked(created[2].id);
      expect(bulkState.proposalCheckedIds.length, 2);

      // 4. Track review events via stream
      int? callbackApproved;
      int? callbackRejected;
      final reviewSub = bulkState.onBulkReviewComplete.listen((result) {
        callbackApproved = result.approvedCount;
        callbackRejected = result.rejectedCount;
      });
      addTearDown(reviewSub.cancel);

      // 5. Approve
      bulkState.approveBulk();

      // 6. Verify results
      expect(callbackApproved, 2);
      expect(callbackRejected, 1);
      expect(bulkState.hasActiveProposal, isFalse);

      // Approved tickets should be open
      expect(ticketBoard.getTicket(created[0].id)!.isOpen, true);
      expect(ticketBoard.getTicket(created[1].id)!.isOpen, true);

      // Rejected ticket should be deleted
      expect(ticketBoard.getTicket(created[2].id), isNull);

      // Dependency from deleted ticket should be cleaned up from surviving
      // tickets. created[2] was deleted but it wasn't a dependency of
      // anything, so no cleanup needed. created[1] still depends on created[0]
      expect(ticketBoard.getTicket(created[1].id)!.dependsOn, [ciTicketId]);

      // Proposal state should be cleared
      expect(bulkState.proposedTickets, isEmpty);
    });

    test('rejectAll deletes all proposed tickets', () {
      final ticketBoard = resources.track(TicketRepository('test-reject-all'));
      final bulkState = resources.track(BulkProposalState(ticketBoard));

      final proposals = [
        const TicketProposal(title: 'Task A', tags: {'feature'}),
        const TicketProposal(title: 'Task B', tags: {'feature'}),
      ];

      final created = bulkState.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent',
      );

      int? callbackRejected;
      final rejectSub = bulkState.onBulkReviewComplete.listen((result) {
        callbackRejected = result.rejectedCount;
      });
      addTearDown(rejectSub.cancel);

      bulkState.rejectAll();

      expect(callbackRejected, 2);
      expect(ticketBoard.tickets, isEmpty);
      expect(ticketBoard.getTicket(created[0].id), isNull);
      expect(ticketBoard.getTicket(created[1].id), isNull);
    });
  });

  // ===========================================================================
  // 3. Dependency chain: A -> B -> C ready via onTicketReady stream
  // ===========================================================================
  group('Dependency chain auto-unblock', () {
    test('A depends on B, B depends on C -> close C -> B emits on '
        'onTicketReady -> close B -> A emits on onTicketReady', () async {
      final ticketBoard = resources.track(TicketRepository('test-dep-chain'));

      // Create tickets: C is foundational, B depends on C, A depends on B
      final c = ticketBoard.createTicket(title: 'Foundation work (C)');
      final b = ticketBoard.createTicket(
        title: 'Middle layer (B)',
        dependsOn: [c.id],
      );
      final a = ticketBoard.createTicket(
        title: 'Top feature (A)',
        dependsOn: [b.id],
      );

      // All tickets start open
      expect(ticketBoard.getTicket(c.id)!.isOpen, true);
      expect(ticketBoard.getTicket(b.id)!.isOpen, true);
      expect(ticketBoard.getTicket(a.id)!.isOpen, true);

      // Track onTicketReady events via stream
      final readyTicketIds = <int>[];
      final readySub = ticketBoard.onTicketReady.listen((ticket) {
        readyTicketIds.add(ticket.id);
      });
      addTearDown(readySub.cancel);

      // Close C -> B should fire on onTicketReady
      ticketBoard.closeTicket(c.id, 'test', AuthorType.user);
      await Future<void>.delayed(Duration.zero);

      expect(ticketBoard.getTicket(c.id)!.isOpen, false);
      expect(ticketBoard.getTicket(b.id)!.isOpen, true);
      expect(ticketBoard.getTicket(a.id)!.isOpen, true);
      expect(readyTicketIds, contains(b.id));

      // Close B -> A should fire on onTicketReady
      ticketBoard.closeTicket(b.id, 'test', AuthorType.user);
      await Future<void>.delayed(Duration.zero);

      expect(ticketBoard.getTicket(b.id)!.isOpen, false);
      expect(ticketBoard.getTicket(a.id)!.isOpen, true);
      expect(readyTicketIds, contains(a.id));
    });

    test('closing one dep of two does not emit onTicketReady for dependent',
        () async {
      final ticketBoard = resources.track(
        TicketRepository('test-partial-deps'),
      );

      final dep1 = ticketBoard.createTicket(title: 'Dep 1');
      final dep2 = ticketBoard.createTicket(title: 'Dep 2');
      final dependent = ticketBoard.createTicket(
        title: 'Depends on both',
        dependsOn: [dep1.id, dep2.id],
      );

      final readyTicketIds = <int>[];
      final readySub = ticketBoard.onTicketReady.listen((ticket) {
        readyTicketIds.add(ticket.id);
      });
      addTearDown(readySub.cancel);

      // Close dep1 only — dependent should NOT be in readyTicketIds
      ticketBoard.closeTicket(dep1.id, 'test', AuthorType.user);
      await Future<void>.delayed(Duration.zero);
      expect(readyTicketIds, isNot(contains(dependent.id)));

      // Close dep2 -> now dependent should emit
      ticketBoard.closeTicket(dep2.id, 'test', AuthorType.user);
      await Future<void>.delayed(Duration.zero);
      expect(readyTicketIds, contains(dependent.id));
    });
  });

  // ===========================================================================
  // 5. Search and filter persistence
  // ===========================================================================
  group('Search and filter', () {
    test('set search query and filters -> verify filtering -> clear -> '
        'all visible', () {
      final ticketBoard = resources.track(
        TicketRepository('test-search-filter'),
      );
      final viewState = resources.track(TicketViewState(ticketBoard));

      // Create varied tickets — all open (V2 default)
      ticketBoard.createTicket(
        title: 'Build login page',
        tags: {'feature', 'high', 'auth'},
      );
      ticketBoard.createTicket(
        title: 'Fix memory leak',
        tags: {'bugfix', 'critical', 'core'},
      );
      ticketBoard.createTicket(
        title: 'Login tests',
        tags: {'test', 'medium', 'auth'},
      );

      // Create one closed ticket
      final deployTicket = ticketBoard.createTicket(
        title: 'Deploy script',
        tags: {'chore', 'low', 'infra'},
      );
      ticketBoard.closeTicket(deployTicket.id, 'test', AuthorType.user);

      // Default filter is open tickets — 3 open visible
      expect(viewState.filteredTickets.length, 3);

      // Search for 'login'
      viewState.setSearchQuery('login');
      expect(viewState.filteredTickets.length, 2);
      expect(
        viewState.filteredTickets.map((t) => t.title),
        containsAll(['Build login page', 'Login tests']),
      );

      // Add tag filter for 'feature' -- now only 'Build login page' matches
      viewState.addTagFilter('feature');
      expect(viewState.filteredTickets.length, 1);
      expect(viewState.filteredTickets.first.title, 'Build login page');

      // Clear all filters
      viewState.setSearchQuery('');
      viewState.clearTagFilters();
      expect(viewState.filteredTickets.length, 3);

      // Test tag filter for 'critical'
      viewState.addTagFilter('critical');
      expect(viewState.filteredTickets.length, 1);
      expect(viewState.filteredTickets.first.title, 'Fix memory leak');
      viewState.clearTagFilters();

      // Test tag filter for 'auth'
      viewState.addTagFilter('auth');
      expect(viewState.filteredTickets.length, 2);
      viewState.clearTagFilters();

      // Test displayId search
      viewState.setSearchQuery('#2');
      expect(viewState.filteredTickets.length, 1);
      expect(viewState.filteredTickets.first.title, 'Fix memory leak');
      viewState.setSearchQuery('');

      // Test closed ticket filter
      viewState.setIsOpenFilter(false);
      expect(viewState.filteredTickets.length, 1);
      expect(viewState.filteredTickets.first.title, 'Deploy script');
      viewState.setIsOpenFilter(true);
    });
  });

  // ===========================================================================
  // 6. Graph view accuracy
  // ===========================================================================
  group('Graph view accuracy', () {
    test(
      'graph layout produces correct nodes and edges for dependency chain',
      () {
        final ticketBoard = resources.track(
          TicketRepository('test-graph-layout'),
        );

        // Create A -> B -> C chain
        final a = ticketBoard.createTicket(title: 'Foundation');
        final b = ticketBoard.createTicket(
          title: 'Middle layer',
          dependsOn: [a.id],
        );
        final c = ticketBoard.createTicket(
          title: 'Top feature',
          dependsOn: [b.id],
        );

        // Compute layout
        final layout = TicketGraphLayout.compute(ticketBoard.tickets);

        // 3 nodes positioned
        expect(layout.nodePositions.length, 3);
        expect(layout.nodePositions.containsKey(a.id), isTrue);
        expect(layout.nodePositions.containsKey(b.id), isTrue);
        expect(layout.nodePositions.containsKey(c.id), isTrue);

        // A should be at the top (layer 0), B in middle, C at bottom
        final aPos = layout.nodePositions[a.id]!;
        final bPos = layout.nodePositions[b.id]!;
        final cPos = layout.nodePositions[c.id]!;

        expect(aPos.dy, lessThan(bPos.dy));
        expect(bPos.dy, lessThan(cPos.dy));

        // 2 edges: A->B and B->C
        expect(layout.edges.length, 2);
        final edgeFromIds = layout.edges.map((e) => e.fromId).toSet();
        final edgeToIds = layout.edges.map((e) => e.toId).toSet();
        expect(edgeFromIds, containsAll([a.id, b.id]));
        expect(edgeToIds, containsAll([b.id, c.id]));

        // Total size should be non-zero
        expect(layout.totalSize.width, greaterThan(0));
        expect(layout.totalSize.height, greaterThan(0));
      },
    );

    test('disconnected components are placed side by side', () {
      final ticketBoard = resources.track(
        TicketRepository('test-graph-disconnected'),
      );

      // Component 1: A -> B
      final a = ticketBoard.createTicket(title: 'Comp1 A');
      ticketBoard.createTicket(title: 'Comp1 B', dependsOn: [a.id]);

      // Component 2: standalone C
      ticketBoard.createTicket(title: 'Comp2 C');

      final layout = TicketGraphLayout.compute(ticketBoard.tickets);

      // All 3 nodes should be positioned
      expect(layout.nodePositions.length, 3);

      // 1 edge (A->B)
      expect(layout.edges.length, 1);
    });

    test('empty ticket list returns empty layout', () {
      final layout = TicketGraphLayout.compute([]);
      expect(layout.nodePositions, isEmpty);
      expect(layout.edges, isEmpty);
      expect(layout.totalSize, Size.zero);
    });

    test('single ticket with no deps produces single node and no edges', () {
      final ticketBoard = resources.track(
        TicketRepository('test-graph-single'),
      );

      ticketBoard.createTicket(title: 'Lone ticket');

      final layout = TicketGraphLayout.compute(ticketBoard.tickets);
      expect(layout.nodePositions.length, 1);
      expect(layout.edges, isEmpty);
    });
  });

  // ===========================================================================
  // 7. Persistence full cycle
  // ===========================================================================
  group('Persistence full cycle', () {
    test('create various tickets with deps and links -> save -> recreate and '
        'load -> verify everything restored', () async {
      final projectId =
          'test-persist-full-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();

      final ticketBoard = resources.track(
        TicketRepository(projectId, storage: storage),
      );

      // Create tickets
      final t1 = ticketBoard.createTicket(
        title: 'Ready feature',
        body: 'Ready feature description',
        tags: {'feature', 'high', 'large', 'frontend', 'ui', 'critical'},
      );

      final t2 = ticketBoard.createTicket(
        title: 'Active bugfix',
        tags: {'bugfix', 'critical', 'small', 'backend'},
      );
      ticketBoard.addTag(t2.id, 'active', 'test', AuthorType.user);

      final t3 = ticketBoard.createTicket(
        title: 'Blocked research',
        tags: {'research', 'medium', 'backend'},
        dependsOn: [t2.id],
      );

      final t4 = ticketBoard.createTicket(
        title: 'Completed chore',
        tags: {'chore', 'low', 'small', 'infra'},
      );
      ticketBoard.closeTicket(t4.id, 'test', AuthorType.user);

      // Add links to t2
      ticketBoard.linkWorktree(t2.id, '/path/to/worktree', 'tkt-2-active');
      ticketBoard.linkChat(t2.id, 'chat-456', '#2', '/path/to/worktree');

      // Save
      await ticketBoard.save();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Recreate and load
      final ticketBoard2 = resources.track(
        TicketRepository(projectId, storage: storage),
      );
      await ticketBoard2.load();

      // Verify ticket count
      expect(ticketBoard2.tickets.length, 4);

      // Verify t1
      final loaded1 = ticketBoard2.getTicket(t1.id)!;
      expect(loaded1.title, 'Ready feature');
      expect(loaded1.body, 'Ready feature description');
      expect(loaded1.isOpen, true);
      expect(loaded1.tags, containsAll(['feature', 'high', 'ui', 'critical']));

      // Verify t2 with links
      final loaded2 = ticketBoard2.getTicket(t2.id)!;
      expect(loaded2.title, 'Active bugfix');
      expect(loaded2.isOpen, true);
      expect(loaded2.tags, contains('active'));
      expect(loaded2.linkedWorktrees.length, 1);
      expect(loaded2.linkedWorktrees.first.worktreeRoot, '/path/to/worktree');
      expect(loaded2.linkedWorktrees.first.branch, 'tkt-2-active');
      expect(loaded2.linkedChats.length, 1);
      expect(loaded2.linkedChats.first.chatId, 'chat-456');
      expect(loaded2.linkedChats.first.chatName, '#2');

      // Verify t3 with dependency
      final loaded3 = ticketBoard2.getTicket(t3.id)!;
      expect(loaded3.title, 'Blocked research');
      expect(loaded3.isOpen, true);
      expect(loaded3.dependsOn, [t2.id]);

      // Verify t4 as closed
      final loaded4 = ticketBoard2.getTicket(t4.id)!;
      expect(loaded4.title, 'Completed chore');
      expect(loaded4.isOpen, false);
      expect(loaded4.closedAt, isNotNull);

      // Verify nextId is preserved
      final t5 = ticketBoard2.createTicket(title: 'New ticket');
      expect(t5.id, 5);
    });
  });

  // ===========================================================================
  // 8. Edge cases
  // ===========================================================================
  group('Edge cases', () {
    test('close all tickets', () {
      final ticketBoard = resources.track(TicketRepository('test-close-all'));

      final tickets = <TicketData>[];
      for (var i = 0; i < 5; i++) {
        tickets.add(ticketBoard.createTicket(title: 'Task $i'));
      }

      // Close all
      for (final t in tickets) {
        ticketBoard.closeTicket(t.id, 'test', AuthorType.user);
      }

      // All should be closed
      for (final t in tickets) {
        final updated = ticketBoard.getTicket(t.id)!;
        expect(updated.isOpen, false);
        expect(updated.closedAt, isNotNull);
      }
    });

    test('delete ticket with dependents cascades dependency removal', () {
      final ticketBoard = resources.track(
        TicketRepository('test-delete-cascade'),
      );

      final a = ticketBoard.createTicket(title: 'Base ticket');
      final b = ticketBoard.createTicket(
        title: 'Depends on base',
        dependsOn: [a.id],
      );
      final c = ticketBoard.createTicket(
        title: 'Also depends on base',
        dependsOn: [a.id],
      );

      // Verify dependencies exist
      expect(ticketBoard.getTicket(b.id)!.dependsOn, [a.id]);
      expect(ticketBoard.getTicket(c.id)!.dependsOn, [a.id]);

      // Delete base ticket
      ticketBoard.deleteTicket(a.id);

      // Base ticket should be gone
      expect(ticketBoard.getTicket(a.id), isNull);

      // Dependencies should be cleaned up
      expect(ticketBoard.getTicket(b.id)!.dependsOn, isEmpty);
      expect(ticketBoard.getTicket(c.id)!.dependsOn, isEmpty);
    });

    test('delete selected ticket clears selection', () {
      final ticketBoard = resources.track(
        TicketRepository('test-delete-selection'),
      );
      final viewState = resources.track(TicketViewState(ticketBoard));

      final t = ticketBoard.createTicket(title: 'Selected ticket');

      viewState.selectTicket(t.id);
      expect(viewState.selectedTicket, isNotNull);

      ticketBoard.deleteTicket(t.id);
      expect(viewState.selectedTicket, isNull);
    });

    test('very long title is handled correctly', () {
      final ticketBoard = resources.track(TicketRepository('test-long-title'));

      final longTitle = 'A' * 500;
      final t = ticketBoard.createTicket(title: longTitle);

      expect(ticketBoard.getTicket(t.id)!.title, longTitle);
      expect(ticketBoard.getTicket(t.id)!.title.length, 500);

      // Branch name should be capped at 50 chars
      final branch = TicketDispatchService.deriveBranchName(t.id, longTitle);
      expect(branch.length, lessThanOrEqualTo(50));
    });

    test('empty body is allowed', () {
      final ticketBoard = resources.track(TicketRepository('test-empty-body'));

      final t = ticketBoard.createTicket(
        title: 'No body ticket',
        body: '',
      );

      expect(ticketBoard.getTicket(t.id)!.body, '');
    });

    test('addDependency to nonexistent ticket throws ArgumentError', () {
      final ticketBoard = resources.track(
        TicketRepository('test-dep-nonexistent'),
      );

      final t = ticketBoard.createTicket(title: 'Ticket');

      expect(() => ticketBoard.addDependency(t.id, 999), throwsArgumentError);
    });

    test('self-dependency throws ArgumentError', () {
      final ticketBoard = resources.track(TicketRepository('test-self-dep'));

      final t = ticketBoard.createTicket(title: 'Ticket');

      expect(() => ticketBoard.addDependency(t.id, t.id), throwsArgumentError);
    });

    test('duplicate dependency is idempotent', () {
      final ticketBoard = resources.track(TicketRepository('test-dup-dep'));

      final a = ticketBoard.createTicket(title: 'A');
      final b = ticketBoard.createTicket(title: 'B');

      ticketBoard.addDependency(b.id, a.id);
      ticketBoard.addDependency(b.id, a.id); // duplicate

      // Should have exactly one dependency, not two
      expect(ticketBoard.getTicket(b.id)!.dependsOn, [a.id]);
    });

    test('duplicate worktree link is idempotent', () {
      final ticketBoard = resources.track(TicketRepository('test-dup-link'));

      final t = ticketBoard.createTicket(title: 'Ticket');

      ticketBoard.linkWorktree(t.id, '/path', 'branch');
      ticketBoard.linkWorktree(t.id, '/path', 'branch'); // duplicate

      expect(ticketBoard.getTicket(t.id)!.linkedWorktrees.length, 1);
    });

    test('duplicate chat link is idempotent', () {
      final ticketBoard = resources.track(
        TicketRepository('test-dup-chat-link'),
      );

      final t = ticketBoard.createTicket(title: 'Ticket');

      ticketBoard.linkChat(t.id, 'chat-1', 'Name', '/path');
      ticketBoard.linkChat(t.id, 'chat-1', 'Name', '/path'); // duplicate

      expect(ticketBoard.getTicket(t.id)!.linkedChats.length, 1);
    });

    test('getTicketsForChat returns matching tickets', () {
      final ticketBoard = resources.track(
        TicketRepository('test-tickets-for-chat'),
      );

      final t1 = ticketBoard.createTicket(title: 'T1');
      final t2 = ticketBoard.createTicket(title: 'T2');
      ticketBoard.createTicket(title: 'T3');

      ticketBoard.linkChat(t1.id, 'shared-chat', 'Chat', '/path');
      ticketBoard.linkChat(t2.id, 'shared-chat', 'Chat', '/path');

      final forChat = ticketBoard.getTicketsForChat('shared-chat');
      expect(forChat.length, 2);
      expect(forChat.map((t) => t.id), containsAll([t1.id, t2.id]));
    });
  });

  // ===========================================================================
  // 9. Dispatch integration with TicketDispatchService
  // ===========================================================================
  group('Dispatch service integration', () {
    test(
      'beginInWorktree creates chat, links, adds active tag, navigates',
      () async {
        final ticketBoard = resources.track(
          TicketRepository('test-dispatch-svc'),
        );

        final primaryWorktree = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/test/repo',
            isPrimary: true,
            branch: 'main',
          ),
        );
        final project = resources.track(
          ProjectState(
            const ProjectData(name: 'test-proj', repoRoot: '/test/repo'),
            primaryWorktree,
            autoValidate: false,
            watchFilesystem: false,
          ),
        );
        final selection = resources.track(SelectionState(project));
        final fakeGit = FakeGitService();

        final ticket = ticketBoard.createTicket(
          title: 'Implement notifications',
          body: 'Add push notifications.',
          tags: {'feature', 'high'},
        );

        final worktree = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/test/worktrees/notifications',
            isPrimary: false,
            branch: 'tkt-1-notifications',
          ),
        );
        project.addLinkedWorktree(worktree);

        final dispatch = TicketDispatchService(
          ticketBoard: ticketBoard,
          project: project,
          selection: selection,
          worktreeService: WorktreeService(gitService: fakeGit),
        );

        await dispatch.beginInWorktree(ticket.id, worktree);

        final updated = ticketBoard.getTicket(ticket.id)!;
        expect(updated.tags, contains('active'));
        expect(updated.linkedWorktrees.length, 1);
        expect(updated.linkedChats.length, 1);
        expect(updated.linkedChats.first.chatName, '#1');

        // Chat should have ticket prompt as draft
        final chat = worktree.chats.first;
        expect(chat.viewState.draftText, isNotNull);
        expect(chat.viewState.draftText!, contains('#1'));
        expect(chat.viewState.draftText!, contains('Implement notifications'));

        // Selection should be updated
        expect(selection.selectedChat, isNotNull);
      },
    );

    test('buildTicketPrompt includes dependency context', () {
      final ticketBoard = resources.track(TicketRepository('test-prompt-deps'));

      final dep = ticketBoard.createTicket(title: 'Database schema');
      // Close the dep so it shows as completed
      ticketBoard.closeTicket(dep.id, 'test', AuthorType.user);

      final ticket = ticketBoard.createTicket(
        title: 'API endpoints',
        body: 'Build REST API endpoints.',
        tags: {'api', 'rest', 'backend'},
        dependsOn: [dep.id],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          primaryWorktree,
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

      expect(prompt, contains('#2'));
      expect(prompt, contains('API endpoints'));
      expect(prompt, contains('Build REST API endpoints.'));
      expect(prompt, contains('Completed Dependencies'));
      expect(prompt, contains('#1'));
      expect(prompt, contains('Database schema'));
    });

    test('deriveBranchName produces correct format', () {
      expect(
        TicketDispatchService.deriveBranchName(1, 'Add dark mode'),
        'tkt-1-add-dark-mode',
      );
      expect(
        TicketDispatchService.deriveBranchName(42, 'Fix BIG Bug!!!'),
        'tkt-42-fix-big-bug',
      );

      // Long title should be truncated to max 50 chars
      final longBranch = TicketDispatchService.deriveBranchName(
        1,
        'This is a very long ticket title that exceeds the maximum length',
      );
      expect(longBranch.length, lessThanOrEqualTo(50));
      expect(longBranch, startsWith('tkt-1-'));
    });
  });

  // ===========================================================================
  // 10. Tag transitions via EventHandler
  // ===========================================================================
  group('EventHandler tag transitions', () {
    test('permission request -> needs-input tag -> response -> tag removed',
        () {
      final ticketBoard = resources.track(
        TicketRepository('test-perm-transitions'),
      );

      final ticket = ticketBoard.createTicket(
        title: 'Active task',
        tags: {'feature', 'active'},
      );

      final chat = resources.track(
        Chat.create(name: '#1', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, '#1', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Permission request -> needs-input tag added
      handler.handleEvent(chat, _makePermissionRequest());
      expect(
        ticketBoard.getTicket(ticket.id)!.tags,
        contains('needs-input'),
      );

      // Permission response -> needs-input tag removed
      handler.handlePermissionResponse(chat);
      expect(
        ticketBoard.getTicket(ticket.id)!.tags.contains('needs-input'),
        false,
      );

      handler.dispose();
    });

    test('closed tickets do not get tags added by events', () {
      final ticketBoard = resources.track(
        TicketRepository('test-closed-no-tags'),
      );

      final ticket = ticketBoard.createTicket(title: 'Completed task');
      ticketBoard.closeTicket(ticket.id, 'test', AuthorType.user);

      final chat = resources.track(
        Chat.create(name: '#1', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, '#1', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      final tagsBefore = Set<String>.from(
        ticketBoard.getTicket(ticket.id)!.tags,
      );

      // Turn complete should not add in-review tag to closed ticket
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 100, outputTokens: 50),
          costUsd: 0.01,
          durationMs: 1000,
        ),
      );

      final tagsAfter = ticketBoard.getTicket(ticket.id)!.tags;
      expect(tagsAfter, equals(tagsBefore));
      expect(ticketBoard.getTicket(ticket.id)!.isOpen, false);

      handler.dispose();
    });

    test('turn complete adds in-review tag to open linked tickets', () {
      final ticketBoard = resources.track(
        TicketRepository('test-turn-complete-tag'),
      );

      final ticket = ticketBoard.createTicket(
        title: 'Multi-turn task',
        tags: {'feature', 'active'},
      );

      final chat = resources.track(
        Chat.create(name: '#1', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, '#1', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Turn 1 — adds in-review tag
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
          costUsd: 0.05,
          durationMs: 3000,
        ),
      );

      expect(
        ticketBoard.getTicket(ticket.id)!.tags,
        contains('in-review'),
      );

      handler.dispose();
    });
  });

  // ===========================================================================
  // 11. View mode and detail mode
  // ===========================================================================
  group('View mode and detail mode', () {
    test('showCreateForm clears selection and sets create mode', () {
      final ticketBoard = resources.track(TicketRepository('test-modes'));
      final viewState = resources.track(TicketViewState(ticketBoard));

      final t = ticketBoard.createTicket(title: 'Ticket');
      viewState.selectTicket(t.id);
      expect(viewState.selectedTicket, isNotNull);

      viewState.showCreateForm();
      expect(viewState.detailMode, TicketDetailMode.create);
      expect(viewState.selectedTicket, isNull);
    });

    test('selectTicket sets detail mode', () {
      final ticketBoard = resources.track(TicketRepository('test-select-mode'));
      final viewState = resources.track(TicketViewState(ticketBoard));

      final t = ticketBoard.createTicket(title: 'Ticket');

      viewState.showCreateForm();
      expect(viewState.detailMode, TicketDetailMode.create);

      viewState.selectTicket(t.id);
      expect(viewState.detailMode, TicketDetailMode.detail);
    });

    test('setViewMode toggles between list and graph', () {
      final ticketBoard = resources.track(TicketRepository('test-view-mode'));
      final viewState = resources.track(TicketViewState(ticketBoard));

      expect(viewState.viewMode, TicketViewMode.list);

      viewState.setViewMode(TicketViewMode.graph);
      expect(viewState.viewMode, TicketViewMode.graph);

      viewState.setViewMode(TicketViewMode.list);
      expect(viewState.viewMode, TicketViewMode.list);
    });
  });

  // ===========================================================================
  // 12. TicketData model edge cases
  // ===========================================================================
  group('TicketData model', () {
    test('toJson/fromJson round trip preserves all fields', () {
      final now = DateTime.now();
      final ticket = TicketData(
        id: 42,
        title: 'Test ticket',
        body: 'A comprehensive body',
        author: 'test',
        isOpen: false,
        tags: {'tag1', 'tag2'},
        dependsOn: [1, 2, 3],
        linkedWorktrees: [
          const LinkedWorktree(worktreeRoot: '/path/wt', branch: 'branch-name'),
        ],
        linkedChats: [
          const LinkedChat(
            chatId: 'chat-1',
            chatName: 'Chat Name',
            worktreeRoot: '/path/wt',
          ),
        ],
        sourceConversationId: 'conv-123',
        createdAt: now,
        updatedAt: now,
        closedAt: now,
      );

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      expect(restored.id, ticket.id);
      expect(restored.title, ticket.title);
      expect(restored.body, ticket.body);
      expect(restored.author, ticket.author);
      expect(restored.isOpen, ticket.isOpen);
      expect(restored.tags, ticket.tags);
      expect(restored.dependsOn, ticket.dependsOn);
      expect(restored.linkedWorktrees.length, 1);
      expect(restored.linkedWorktrees.first.worktreeRoot, '/path/wt');
      expect(restored.linkedChats.length, 1);
      expect(restored.linkedChats.first.chatId, 'chat-1');
      expect(restored.sourceConversationId, 'conv-123');
      expect(restored.closedAt, isNotNull);
    });

    test('copyWith with clear flags works correctly', () {
      final now = DateTime.now();
      final ticket = TicketData(
        id: 1,
        title: 'Test',
        body: 'Body text',
        author: 'test',
        isOpen: false,
        sourceConversationId: 'conv-1',
        createdAt: now,
        updatedAt: now,
        closedAt: now,
      );

      final cleared = ticket.copyWith(
        clearSourceConversationId: true,
        clearClosedAt: true,
      );

      expect(cleared.sourceConversationId, isNull);
      expect(cleared.closedAt, isNull);
      // isOpen should not change since we didn't specify it
      expect(cleared.isOpen, false);
    });

    test('TicketProposal fromJson works with minimal fields', () {
      final proposal = TicketProposal.fromJson({'title': 'Minimal proposal'});

      expect(proposal.title, 'Minimal proposal');
      expect(proposal.body, '');
      expect(proposal.tags, isEmpty);
      expect(proposal.dependsOnIndices, isEmpty);
    });

    test('TicketProposal displayId format is #N', () {
      final ticketBoard = resources.track(
        TicketRepository('test-display-id'),
      );

      final t = ticketBoard.createTicket(title: 'First ticket');
      expect(t.displayId, '#1');

      final t2 = ticketBoard.createTicket(title: 'Second ticket');
      expect(t2.displayId, '#2');
    });
  });

  // ===========================================================================
  // 13. Notification behavior
  // ===========================================================================
  group('Notification behavior', () {
    test('CRUD operations trigger notifyListeners', () {
      final ticketBoard = resources.track(
        TicketRepository('test-notifications'),
      );

      var notificationCount = 0;
      ticketBoard.addListener(() {
        notificationCount++;
      });

      // Create should notify
      final t = ticketBoard.createTicket(title: 'Task');
      expect(notificationCount, greaterThan(0));
      final countAfterCreate = notificationCount;

      // Update should notify
      ticketBoard.updateTicket(t.id, title: 'New');
      expect(notificationCount, greaterThan(countAfterCreate));
      final countAfterUpdate = notificationCount;

      // Delete should notify
      ticketBoard.deleteTicket(t.id);
      expect(notificationCount, greaterThan(countAfterUpdate));
    });

    test('filter and search changes trigger notifyListeners', () {
      final ticketBoard = resources.track(
        TicketRepository('test-filter-notify'),
      );
      final viewState = resources.track(TicketViewState(ticketBoard));

      var notified = false;
      viewState.addListener(() {
        notified = true;
      });

      viewState.setSearchQuery('test');
      expect(notified, isTrue);

      notified = false;
      viewState.setIsOpenFilter(false);
      expect(notified, isTrue);

      notified = false;
      viewState.addTagFilter('bugfix');
      expect(notified, isTrue);

      notified = false;
      viewState.addTagFilter('high');
      expect(notified, isTrue);

      notified = false;
      viewState.addTagFilter('frontend');
      expect(notified, isTrue);

      notified = false;
      viewState.setSortOrder(TicketSortOrder.oldest);
      expect(notified, isTrue);
    });
  });
}
