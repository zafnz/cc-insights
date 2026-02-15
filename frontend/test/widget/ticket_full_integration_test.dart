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
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
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
    test(
        'create tickets manually -> dispatch (link chat) -> simulate turn '
        'complete -> mark done -> verify status transitions', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-full-lifecycle'),
      );

      // 1. Create a ticket
      final ticket = ticketBoard.createTicket(
        title: 'Implement user profile page',
        kind: TicketKind.feature,
        description: 'Build the user profile page with avatar and settings.',
        priority: TicketPriority.high,
        effort: TicketEffort.medium,
        category: 'Frontend',
        tags: {'ui', 'profile'},
      );

      expect(ticket.status, TicketStatus.ready);
      expect(ticket.displayId, 'TKT-001');

      // 2. Simulate dispatch: set status to active and link chat
      ticketBoard.setStatus(ticket.id, TicketStatus.active);

      final chat = resources.track(
        ChatState.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(
        ticket.id,
        chat.data.id,
        chat.data.name,
        '/tmp/test',
      );
      ticketBoard.linkWorktree(ticket.id, '/tmp/test', 'tkt-1-profile');

      final dispatched = ticketBoard.getTicket(ticket.id)!;
      expect(dispatched.status, TicketStatus.active);
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
      expect(afterTurn.status, TicketStatus.inReview);
      expect(afterTurn.costStats, isNotNull);
      expect(afterTurn.costStats!.totalTokens, 7000);

      // 4. Mark completed
      ticketBoard.markCompleted(ticket.id);

      final completed = ticketBoard.getTicket(ticket.id)!;
      expect(completed.status, TicketStatus.completed);
      expect(completed.isTerminal, isTrue);

      handler.dispose();
    });
  });

  // ===========================================================================
  // 2. Agent proposal lifecycle
  // ===========================================================================
  group('Agent proposal lifecycle', () {
    test(
        'proposeBulk -> user reviews -> approves subset -> verify tickets '
        'are ready and unchecked are deleted', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-proposal-lifecycle'),
      );

      // 1. Create proposals
      final proposals = [
        const TicketProposal(
          title: 'Setup CI/CD pipeline',
          description: 'Configure GitHub Actions for automated testing.',
          kind: TicketKind.chore,
          priority: TicketPriority.high,
        ),
        const TicketProposal(
          title: 'Add unit tests for auth module',
          description: 'Write comprehensive unit tests.',
          kind: TicketKind.test,
          priority: TicketPriority.medium,
          dependsOnIndices: [0],
        ),
        const TicketProposal(
          title: 'Deploy to staging',
          description: 'Set up staging environment.',
          kind: TicketKind.chore,
          priority: TicketPriority.low,
          dependsOnIndices: [0, 1],
        ),
      ];

      // 2. Propose bulk
      final created = ticketBoard.proposeBulk(
        proposals,
        sourceChatId: 'chat-agent-1',
        sourceChatName: 'Planning Agent',
      );

      expect(created.length, 3);
      expect(ticketBoard.detailMode, TicketDetailMode.bulkReview);
      expect(ticketBoard.proposedTickets.length, 3);

      // All should be draft
      for (final t in created) {
        expect(ticketBoard.getTicket(t.id)!.status, TicketStatus.draft);
      }

      // All should be checked by default
      expect(ticketBoard.proposalCheckedIds.length, 3);

      // Verify dependencies resolved correctly
      final ciTicketId = created[0].id;
      final testTicketId = created[1].id;
      expect(created[1].dependsOn, [ciTicketId]);
      expect(created[2].dependsOn, [ciTicketId, testTicketId]);

      // 3. Uncheck the third ticket (deploy to staging)
      ticketBoard.toggleProposalChecked(created[2].id);
      expect(ticketBoard.proposalCheckedIds.length, 2);

      // 4. Track review events via stream
      int? callbackApproved;
      int? callbackRejected;
      final reviewSub = ticketBoard.onBulkReviewComplete.listen((result) {
        callbackApproved = result.approvedCount;
        callbackRejected = result.rejectedCount;
      });
      addTearDown(reviewSub.cancel);

      // 5. Approve
      ticketBoard.approveBulk();

      // 6. Verify results
      expect(callbackApproved, 2);
      expect(callbackRejected, 1);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);

      // Approved tickets should be ready
      expect(ticketBoard.getTicket(created[0].id)!.status, TicketStatus.ready);
      expect(ticketBoard.getTicket(created[1].id)!.status, TicketStatus.ready);

      // Rejected ticket should be deleted
      expect(ticketBoard.getTicket(created[2].id), isNull);

      // Dependency from deleted ticket should be cleaned up from surviving tickets
      // created[2] was deleted but it wasn't a dependency of anything, so no cleanup needed
      // created[1] still depends on created[0]
      expect(ticketBoard.getTicket(created[1].id)!.dependsOn, [ciTicketId]);

      // Proposal state should be cleared
      expect(ticketBoard.proposedTickets, isEmpty);
    });

    test('rejectAll deletes all proposed tickets', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-reject-all'),
      );

      final proposals = [
        const TicketProposal(
          title: 'Task A',
          kind: TicketKind.feature,
        ),
        const TicketProposal(
          title: 'Task B',
          kind: TicketKind.feature,
        ),
      ];

      final created = ticketBoard.proposeBulk(
        proposals,
        sourceChatId: 'chat-1',
        sourceChatName: 'Agent',
      );

      int? callbackRejected;
      final rejectSub = ticketBoard.onBulkReviewComplete.listen((result) {
        callbackRejected = result.rejectedCount;
      });
      addTearDown(rejectSub.cancel);

      ticketBoard.rejectAll();

      expect(callbackRejected, 2);
      expect(ticketBoard.tickets, isEmpty);
      expect(ticketBoard.getTicket(created[0].id), isNull);
      expect(ticketBoard.getTicket(created[1].id), isNull);
    });
  });

  // ===========================================================================
  // 3. Dependency chain: A -> B -> C auto-unblock cascade
  // ===========================================================================
  group('Dependency chain auto-unblock', () {
    test(
        'A depends on B, B depends on C -> complete C -> B auto-unblocks -> '
        'complete B -> A auto-unblocks', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dep-chain'),
      );

      // Create tickets: C is foundational, B depends on C, A depends on B
      final c = ticketBoard.createTicket(
        title: 'Foundation work (C)',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final b = ticketBoard.createTicket(
        title: 'Middle layer (B)',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [c.id],
      );
      final a = ticketBoard.createTicket(
        title: 'Top feature (A)',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [b.id],
      );

      // Verify initial states
      expect(ticketBoard.getTicket(c.id)!.status, TicketStatus.active);
      expect(ticketBoard.getTicket(b.id)!.status, TicketStatus.blocked);
      expect(ticketBoard.getTicket(a.id)!.status, TicketStatus.blocked);

      // Track onTicketReady events via stream
      final readyTicketIds = <int>[];
      final readySub = ticketBoard.onTicketReady.listen((ticket) {
        readyTicketIds.add(ticket.id);
      });
      addTearDown(readySub.cancel);

      // Complete C -> B should auto-unblock to ready
      ticketBoard.markCompleted(c.id);

      expect(ticketBoard.getTicket(c.id)!.status, TicketStatus.completed);
      expect(ticketBoard.getTicket(b.id)!.status, TicketStatus.ready);
      expect(ticketBoard.getTicket(a.id)!.status, TicketStatus.blocked);
      expect(readyTicketIds, contains(b.id));

      // Complete B -> A should auto-unblock to ready
      ticketBoard.markCompleted(b.id);

      expect(ticketBoard.getTicket(b.id)!.status, TicketStatus.completed);
      expect(ticketBoard.getTicket(a.id)!.status, TicketStatus.ready);
      expect(readyTicketIds, contains(a.id));
    });

    test('completing one dep of two does not unblock dependent', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-partial-deps'),
      );

      final dep1 = ticketBoard.createTicket(
        title: 'Dep 1',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dep2 = ticketBoard.createTicket(
        title: 'Dep 2',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );
      final dependent = ticketBoard.createTicket(
        title: 'Depends on both',
        kind: TicketKind.feature,
        status: TicketStatus.blocked,
        dependsOn: [dep1.id, dep2.id],
      );

      // Complete dep1 only
      ticketBoard.markCompleted(dep1.id);
      expect(
        ticketBoard.getTicket(dependent.id)!.status,
        TicketStatus.blocked,
      );

      // Complete dep2 -> now should unblock
      ticketBoard.markCompleted(dep2.id);
      expect(
        ticketBoard.getTicket(dependent.id)!.status,
        TicketStatus.ready,
      );
    });
  });

  // ===========================================================================
  // 4. Split and complete
  // ===========================================================================
  group('Split and complete', () {
    test(
        'create ticket -> split into subtasks -> complete subtasks -> '
        'parent stays split', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-split-complete'),
      );

      // Create parent ticket
      final parent = ticketBoard.createTicket(
        title: 'Large refactoring task',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Backend',
      );

      expect(parent.status, TicketStatus.ready);

      // Split into 2 subtasks
      final children = ticketBoard.splitTicket(parent.id, [
        (title: 'Refactor module A', kind: TicketKind.feature),
        (title: 'Refactor module B', kind: TicketKind.feature),
      ]);

      expect(children.length, 2);

      // Verify parent is now split
      final updatedParent = ticketBoard.getTicket(parent.id)!;
      expect(updatedParent.status, TicketStatus.split);
      expect(updatedParent.kind, TicketKind.split);
      expect(updatedParent.isTerminal, isTrue);

      // Verify children inherit parent properties
      for (final child in children) {
        final t = ticketBoard.getTicket(child.id)!;
        expect(t.status, TicketStatus.ready);
        expect(t.priority, TicketPriority.high);
        expect(t.effort, TicketEffort.large);
        expect(t.category, 'Backend');
        expect(t.dependsOn, [parent.id]);
      }

      // Complete both subtasks
      ticketBoard.markCompleted(children[0].id);
      ticketBoard.markCompleted(children[1].id);

      // Parent should still be split (not unblocked -- split is terminal)
      final parentAfter = ticketBoard.getTicket(parent.id)!;
      expect(parentAfter.status, TicketStatus.split);
      expect(parentAfter.isTerminal, isTrue);
    });

    test('split with empty subtasks throws ArgumentError', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-split-empty'),
      );

      final parent = ticketBoard.createTicket(
        title: 'Task',
        kind: TicketKind.feature,
      );

      expect(
        () => ticketBoard.splitTicket(parent.id, []),
        throwsArgumentError,
      );
    });

    test('split nonexistent ticket throws ArgumentError', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-split-nonexistent'),
      );

      expect(
        () => ticketBoard.splitTicket(999, [
          (title: 'Sub', kind: TicketKind.feature),
        ]),
        throwsArgumentError,
      );
    });
  });

  // ===========================================================================
  // 5. Search and filter persistence
  // ===========================================================================
  group('Search and filter', () {
    test(
        'set search query and filters -> verify filtering -> clear -> '
        'all visible', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-search-filter'),
      );

      // Create varied tickets
      ticketBoard.createTicket(
        title: 'Build login page',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
        category: 'Auth',
      );
      ticketBoard.createTicket(
        title: 'Fix memory leak',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
        priority: TicketPriority.critical,
        category: 'Core',
      );
      ticketBoard.createTicket(
        title: 'Login tests',
        kind: TicketKind.test,
        status: TicketStatus.ready,
        priority: TicketPriority.medium,
        category: 'Auth',
      );
      ticketBoard.createTicket(
        title: 'Deploy script',
        kind: TicketKind.chore,
        status: TicketStatus.completed,
        priority: TicketPriority.low,
        category: 'Infra',
      );

      // All 4 visible initially
      expect(ticketBoard.filteredTickets.length, 4);

      // Search for 'login'
      ticketBoard.setSearchQuery('login');
      expect(ticketBoard.filteredTickets.length, 2);
      expect(
        ticketBoard.filteredTickets.map((t) => t.title),
        containsAll(['Build login page', 'Login tests']),
      );

      // Add status filter for ready
      ticketBoard.setStatusFilter(TicketStatus.ready);
      expect(ticketBoard.filteredTickets.length, 2);

      // Add kind filter for feature -- now only 'Build login page' matches
      ticketBoard.setKindFilter(TicketKind.feature);
      expect(ticketBoard.filteredTickets.length, 1);
      expect(ticketBoard.filteredTickets.first.title, 'Build login page');

      // Clear all filters
      ticketBoard.setSearchQuery('');
      ticketBoard.setStatusFilter(null);
      ticketBoard.setKindFilter(null);
      expect(ticketBoard.filteredTickets.length, 4);

      // Test priority filter
      ticketBoard.setPriorityFilter(TicketPriority.critical);
      expect(ticketBoard.filteredTickets.length, 1);
      expect(ticketBoard.filteredTickets.first.title, 'Fix memory leak');
      ticketBoard.setPriorityFilter(null);

      // Test category filter
      ticketBoard.setCategoryFilter('Auth');
      expect(ticketBoard.filteredTickets.length, 2);
      ticketBoard.setCategoryFilter(null);

      // Test displayId search
      ticketBoard.setSearchQuery('TKT-002');
      expect(ticketBoard.filteredTickets.length, 1);
      expect(ticketBoard.filteredTickets.first.title, 'Fix memory leak');
      ticketBoard.setSearchQuery('');
    });

    test('grouped tickets reflect filters and group-by', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-grouped'),
      );

      ticketBoard.createTicket(
        title: 'Auth feature',
        kind: TicketKind.feature,
        status: TicketStatus.active,
        category: 'Auth',
      );
      ticketBoard.createTicket(
        title: 'Auth bugfix',
        kind: TicketKind.bugfix,
        status: TicketStatus.ready,
        category: 'Auth',
      );
      ticketBoard.createTicket(
        title: 'Data migration',
        kind: TicketKind.chore,
        status: TicketStatus.ready,
        category: 'Data',
      );

      // Default group-by is category
      final byCategory = ticketBoard.groupedTickets;
      expect(byCategory.keys, containsAll(['Auth', 'Data']));
      expect(byCategory['Auth']!.length, 2);
      expect(byCategory['Data']!.length, 1);

      // Switch to group-by status
      ticketBoard.setGroupBy(TicketGroupBy.status);
      final byStatus = ticketBoard.groupedTickets;
      expect(byStatus.keys, containsAll(['Active', 'Ready']));

      // Switch to group-by kind
      ticketBoard.setGroupBy(TicketGroupBy.kind);
      final byKind = ticketBoard.groupedTickets;
      expect(byKind.keys, containsAll(['Feature', 'Bug Fix', 'Chore']));

      // Apply filter and verify grouping reflects it
      ticketBoard.setStatusFilter(TicketStatus.ready);
      final filteredGrouped = ticketBoard.groupedTickets;
      expect(filteredGrouped.containsKey('Feature'), isFalse);
      expect(filteredGrouped.keys, containsAll(['Bug Fix', 'Chore']));
    });
  });

  // ===========================================================================
  // 6. Graph view accuracy
  // ===========================================================================
  group('Graph view accuracy', () {
    test('graph layout produces correct nodes and edges for dependency chain',
        () {
      final ticketBoard = resources.track(
        TicketBoardState('test-graph-layout'),
      );

      // Create A -> B -> C chain
      final a = ticketBoard.createTicket(
        title: 'Foundation',
        kind: TicketKind.feature,
      );
      final b = ticketBoard.createTicket(
        title: 'Middle layer',
        kind: TicketKind.feature,
        dependsOn: [a.id],
      );
      final c = ticketBoard.createTicket(
        title: 'Top feature',
        kind: TicketKind.feature,
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
    });

    test('disconnected components are placed side by side', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-graph-disconnected'),
      );

      // Component 1: A -> B
      final a = ticketBoard.createTicket(
        title: 'Comp1 A',
        kind: TicketKind.feature,
      );
      ticketBoard.createTicket(
        title: 'Comp1 B',
        kind: TicketKind.feature,
        dependsOn: [a.id],
      );

      // Component 2: standalone C
      ticketBoard.createTicket(
        title: 'Comp2 C',
        kind: TicketKind.feature,
      );

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
        TicketBoardState('test-graph-single'),
      );

      ticketBoard.createTicket(
        title: 'Lone ticket',
        kind: TicketKind.feature,
      );

      final layout = TicketGraphLayout.compute(ticketBoard.tickets);
      expect(layout.nodePositions.length, 1);
      expect(layout.edges, isEmpty);
    });
  });

  // ===========================================================================
  // 7. Persistence full cycle
  // ===========================================================================
  group('Persistence full cycle', () {
    test(
        'create various tickets in various states with deps and links -> '
        'save -> recreate and load -> verify everything restored', () async {
      final projectId =
          'test-persist-full-${DateTime.now().millisecondsSinceEpoch}';
      final storage = TicketStorageService();

      final ticketBoard = resources.track(
        TicketBoardState(projectId, storage: storage),
      );

      // Create tickets in various states
      final t1 = ticketBoard.createTicket(
        title: 'Ready feature',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Frontend',
        description: 'Ready feature description',
        tags: {'ui', 'critical'},
      );

      final t2 = ticketBoard.createTicket(
        title: 'Active bugfix',
        kind: TicketKind.bugfix,
        status: TicketStatus.active,
        priority: TicketPriority.critical,
        effort: TicketEffort.small,
        category: 'Backend',
      );

      final t3 = ticketBoard.createTicket(
        title: 'Blocked research',
        kind: TicketKind.research,
        status: TicketStatus.blocked,
        priority: TicketPriority.medium,
        effort: TicketEffort.medium,
        category: 'Backend',
        dependsOn: [t2.id],
      );

      final t4 = ticketBoard.createTicket(
        title: 'Completed chore',
        kind: TicketKind.chore,
        status: TicketStatus.completed,
        priority: TicketPriority.low,
        effort: TicketEffort.small,
        category: 'Infra',
      );

      // Add links to t2
      ticketBoard.linkWorktree(t2.id, '/path/to/worktree', 'tkt-2-active');
      ticketBoard.linkChat(t2.id, 'chat-456', 'TKT-002', '/path/to/worktree');

      // Add cost stats to t4
      ticketBoard.accumulateCostStats(
        t4.id,
        tokens: 10000,
        cost: 0.50,
        agentTimeMs: 30000,
      );

      // Save
      await ticketBoard.save();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Recreate and load
      final ticketBoard2 = resources.track(
        TicketBoardState(projectId, storage: storage),
      );
      await ticketBoard2.load();

      // Verify ticket count
      expect(ticketBoard2.tickets.length, 4);

      // Verify t1
      final loaded1 = ticketBoard2.getTicket(t1.id)!;
      expect(loaded1.title, 'Ready feature');
      expect(loaded1.kind, TicketKind.feature);
      expect(loaded1.status, TicketStatus.ready);
      expect(loaded1.priority, TicketPriority.high);
      expect(loaded1.effort, TicketEffort.large);
      expect(loaded1.category, 'Frontend');
      expect(loaded1.description, 'Ready feature description');
      expect(loaded1.tags, containsAll(['ui', 'critical']));

      // Verify t2 with links
      final loaded2 = ticketBoard2.getTicket(t2.id)!;
      expect(loaded2.title, 'Active bugfix');
      expect(loaded2.status, TicketStatus.active);
      expect(loaded2.linkedWorktrees.length, 1);
      expect(loaded2.linkedWorktrees.first.worktreeRoot, '/path/to/worktree');
      expect(loaded2.linkedWorktrees.first.branch, 'tkt-2-active');
      expect(loaded2.linkedChats.length, 1);
      expect(loaded2.linkedChats.first.chatId, 'chat-456');
      expect(loaded2.linkedChats.first.chatName, 'TKT-002');

      // Verify t3 with dependency
      final loaded3 = ticketBoard2.getTicket(t3.id)!;
      expect(loaded3.title, 'Blocked research');
      expect(loaded3.status, TicketStatus.blocked);
      expect(loaded3.dependsOn, [t2.id]);

      // Verify t4 with cost stats
      final loaded4 = ticketBoard2.getTicket(t4.id)!;
      expect(loaded4.title, 'Completed chore');
      expect(loaded4.status, TicketStatus.completed);
      expect(loaded4.costStats, isNotNull);
      expect(loaded4.costStats!.totalTokens, 10000);
      expect(loaded4.costStats!.totalCost, 0.50);
      expect(loaded4.costStats!.agentTimeMs, 30000);

      // Verify nextId is preserved
      final t5 = ticketBoard2.createTicket(
        title: 'New ticket',
        kind: TicketKind.feature,
      );
      expect(t5.id, 5);
    });
  });

  // ===========================================================================
  // 8. Edge cases
  // ===========================================================================
  group('Edge cases', () {
    test('cancel all tickets', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-cancel-all'),
      );

      final tickets = <TicketData>[];
      for (var i = 0; i < 5; i++) {
        tickets.add(ticketBoard.createTicket(
          title: 'Task $i',
          kind: TicketKind.feature,
        ));
      }

      // Cancel all
      for (final t in tickets) {
        ticketBoard.markCancelled(t.id);
      }

      // All should be cancelled and terminal
      for (final t in tickets) {
        final updated = ticketBoard.getTicket(t.id)!;
        expect(updated.status, TicketStatus.cancelled);
        expect(updated.isTerminal, isTrue);
      }
    });

    test('delete ticket with dependents cascades dependency removal', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-delete-cascade'),
      );

      final a = ticketBoard.createTicket(
        title: 'Base ticket',
        kind: TicketKind.feature,
      );
      final b = ticketBoard.createTicket(
        title: 'Depends on base',
        kind: TicketKind.feature,
        dependsOn: [a.id],
      );
      final c = ticketBoard.createTicket(
        title: 'Also depends on base',
        kind: TicketKind.feature,
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
        TicketBoardState('test-delete-selection'),
      );

      final t = ticketBoard.createTicket(
        title: 'Selected ticket',
        kind: TicketKind.feature,
      );

      ticketBoard.selectTicket(t.id);
      expect(ticketBoard.selectedTicket, isNotNull);

      ticketBoard.deleteTicket(t.id);
      expect(ticketBoard.selectedTicket, isNull);
    });

    test('very long title is handled correctly', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-long-title'),
      );

      final longTitle = 'A' * 500;
      final t = ticketBoard.createTicket(
        title: longTitle,
        kind: TicketKind.feature,
      );

      expect(ticketBoard.getTicket(t.id)!.title, longTitle);
      expect(ticketBoard.getTicket(t.id)!.title.length, 500);

      // Branch name should be capped at 50 chars
      final branch = TicketDispatchService.deriveBranchName(t.id, longTitle);
      expect(branch.length, lessThanOrEqualTo(50));
    });

    test('empty description is allowed', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-empty-desc'),
      );

      final t = ticketBoard.createTicket(
        title: 'No description ticket',
        kind: TicketKind.feature,
        description: '',
      );

      expect(ticketBoard.getTicket(t.id)!.description, '');
    });

    test('duplicate category names work correctly with grouping', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dup-categories'),
      );

      ticketBoard.createTicket(
        title: 'Task 1',
        kind: TicketKind.feature,
        category: 'Frontend',
      );
      ticketBoard.createTicket(
        title: 'Task 2',
        kind: TicketKind.bugfix,
        category: 'Frontend',
      );
      ticketBoard.createTicket(
        title: 'Task 3',
        kind: TicketKind.feature,
        category: 'Backend',
      );

      // Verify grouping puts both into Frontend
      final grouped = ticketBoard.groupedTickets;
      expect(grouped['Frontend']!.length, 2);
      expect(grouped['Backend']!.length, 1);

      // Verify allCategories
      expect(ticketBoard.allCategories, ['Backend', 'Frontend']);
    });

    test('ticket without category goes to Uncategorized group', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-uncategorized'),
      );

      ticketBoard.createTicket(
        title: 'No category',
        kind: TicketKind.feature,
      );

      final grouped = ticketBoard.groupedTickets;
      expect(grouped.containsKey('Uncategorized'), isTrue);
      expect(grouped['Uncategorized']!.length, 1);
    });

    test('addDependency to nonexistent ticket throws ArgumentError', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dep-nonexistent'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );

      expect(
        () => ticketBoard.addDependency(t.id, 999),
        throwsArgumentError,
      );
    });

    test('self-dependency throws ArgumentError', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-self-dep'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );

      expect(
        () => ticketBoard.addDependency(t.id, t.id),
        throwsArgumentError,
      );
    });

    test('duplicate dependency is idempotent', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dup-dep'),
      );

      final a = ticketBoard.createTicket(
        title: 'A',
        kind: TicketKind.feature,
      );
      final b = ticketBoard.createTicket(
        title: 'B',
        kind: TicketKind.feature,
      );

      ticketBoard.addDependency(b.id, a.id);
      ticketBoard.addDependency(b.id, a.id); // duplicate

      // Should have exactly one dependency, not two
      expect(ticketBoard.getTicket(b.id)!.dependsOn, [a.id]);
    });

    test('duplicate worktree link is idempotent', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dup-link'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );

      ticketBoard.linkWorktree(t.id, '/path', 'branch');
      ticketBoard.linkWorktree(t.id, '/path', 'branch'); // duplicate

      expect(ticketBoard.getTicket(t.id)!.linkedWorktrees.length, 1);
    });

    test('duplicate chat link is idempotent', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-dup-chat-link'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );

      ticketBoard.linkChat(t.id, 'chat-1', 'Name', '/path');
      ticketBoard.linkChat(t.id, 'chat-1', 'Name', '/path'); // duplicate

      expect(ticketBoard.getTicket(t.id)!.linkedChats.length, 1);
    });

    test('getTicketsForChat returns matching tickets', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-tickets-for-chat'),
      );

      final t1 = ticketBoard.createTicket(
        title: 'T1',
        kind: TicketKind.feature,
      );
      final t2 = ticketBoard.createTicket(
        title: 'T2',
        kind: TicketKind.feature,
      );
      ticketBoard.createTicket(
        title: 'T3',
        kind: TicketKind.feature,
      );

      ticketBoard.linkChat(t1.id, 'shared-chat', 'Chat', '/path');
      ticketBoard.linkChat(t2.id, 'shared-chat', 'Chat', '/path');

      final forChat = ticketBoard.getTicketsForChat('shared-chat');
      expect(forChat.length, 2);
      expect(forChat.map((t) => t.id), containsAll([t1.id, t2.id]));
    });

    test('nextReadyTicket returns highest-priority ready ticket', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-next-ready'),
      );

      ticketBoard.createTicket(
        title: 'Low priority',
        kind: TicketKind.feature,
        priority: TicketPriority.low,
      );
      ticketBoard.createTicket(
        title: 'High priority',
        kind: TicketKind.feature,
        priority: TicketPriority.high,
      );
      ticketBoard.createTicket(
        title: 'Critical priority',
        kind: TicketKind.feature,
        priority: TicketPriority.critical,
      );

      final next = ticketBoard.nextReadyTicket!;
      expect(next.title, 'Critical priority');
    });

    test('categoryProgress counts correctly', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-category-progress'),
      );

      ticketBoard.createTicket(
        title: 'Done 1',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Frontend',
      );
      ticketBoard.createTicket(
        title: 'Not done 1',
        kind: TicketKind.feature,
        status: TicketStatus.ready,
        category: 'Frontend',
      );
      ticketBoard.createTicket(
        title: 'Done 2',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Frontend',
      );
      ticketBoard.createTicket(
        title: 'Done backend',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
        category: 'Backend',
      );

      final progress = ticketBoard.categoryProgress;
      expect(progress['Frontend']!.completed, 2);
      expect(progress['Frontend']!.total, 3);
      expect(progress['Backend']!.completed, 1);
      expect(progress['Backend']!.total, 1);
    });
  });

  // ===========================================================================
  // 9. Dispatch integration with TicketDispatchService
  // ===========================================================================
  group('Dispatch service integration', () {
    test('beginInWorktree creates chat, links, sets status, navigates', () async {
      final ticketBoard = resources.track(
        TicketBoardState('test-dispatch-svc'),
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(ProjectState(
        const ProjectData(name: 'test-proj', repoRoot: '/test/repo'),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      ));
      final selection = resources.track(SelectionState(project));
      final fakeGit = FakeGitService();

      final ticket = ticketBoard.createTicket(
        title: 'Implement notifications',
        kind: TicketKind.feature,
        description: 'Add push notifications.',
        priority: TicketPriority.high,
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
      expect(updated.status, TicketStatus.active);
      expect(updated.linkedWorktrees.length, 1);
      expect(updated.linkedChats.length, 1);
      expect(updated.linkedChats.first.chatName, 'TKT-001');

      // Chat should have ticket prompt as draft
      final chat = worktree.chats.first;
      expect(chat.draftText, isNotNull);
      expect(chat.draftText!, contains('TKT-001'));
      expect(chat.draftText!, contains('Implement notifications'));

      // Selection should be updated
      expect(selection.selectedChat, isNotNull);
    });

    test('buildTicketPrompt includes dependency context', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-prompt-deps'),
      );

      final dep = ticketBoard.createTicket(
        title: 'Database schema',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );
      final ticket = ticketBoard.createTicket(
        title: 'API endpoints',
        kind: TicketKind.feature,
        description: 'Build REST API endpoints.',
        priority: TicketPriority.high,
        category: 'Backend',
        tags: {'api', 'rest'},
        dependsOn: [dep.id],
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(ProjectState(
        const ProjectData(name: 'test', repoRoot: '/test/repo'),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      ));
      final selection = resources.track(SelectionState(project));

      final dispatch = TicketDispatchService(
        ticketBoard: ticketBoard,
        project: project,
        selection: selection,
        worktreeService: WorktreeService(),
      );

      final prompt = dispatch.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('TKT-002'));
      expect(prompt, contains('API endpoints'));
      expect(prompt, contains('Build REST API endpoints.'));
      expect(prompt, contains('**Kind:** Feature'));
      expect(prompt, contains('**Priority:** High'));
      expect(prompt, contains('**Category:** Backend'));
      expect(prompt, contains('Completed Dependencies'));
      expect(prompt, contains('[x] TKT-001: Database schema'));
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
  // 10. Status transition via EventHandler
  // ===========================================================================
  group('EventHandler status transitions', () {
    test('permission request -> needsInput -> response -> active', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-perm-transitions'),
      );

      final ticket = ticketBoard.createTicket(
        title: 'Active task',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      final chat = resources.track(
        ChatState.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, 'TKT-001', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Permission request -> needsInput
      handler.handleEvent(chat, _makePermissionRequest());
      expect(
        ticketBoard.getTicket(ticket.id)!.status,
        TicketStatus.needsInput,
      );

      // Permission response -> active
      handler.handlePermissionResponse(chat);
      expect(
        ticketBoard.getTicket(ticket.id)!.status,
        TicketStatus.active,
      );

      handler.dispose();
    });

    test('terminal tickets are not transitioned by events', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-terminal-no-transition'),
      );

      final ticket = ticketBoard.createTicket(
        title: 'Completed task',
        kind: TicketKind.feature,
        status: TicketStatus.completed,
      );

      final chat = resources.track(
        ChatState.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, 'TKT-001', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Turn complete should not change status
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 100, outputTokens: 50),
          costUsd: 0.01,
          durationMs: 1000,
        ),
      );
      expect(
        ticketBoard.getTicket(ticket.id)!.status,
        TicketStatus.completed,
      );

      handler.dispose();
    });

    test('cost stats accumulate across multiple turns', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-cost-accumulate'),
      );

      final ticket = ticketBoard.createTicket(
        title: 'Multi-turn task',
        kind: TicketKind.feature,
        status: TicketStatus.active,
      );

      final chat = resources.track(
        ChatState.create(name: 'TKT-001', worktreeRoot: '/tmp/test'),
      );
      ticketBoard.linkChat(ticket.id, chat.data.id, 'TKT-001', '/tmp/test');

      final handler = EventHandler(ticketBoard: ticketBoard);

      // Turn 1
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 1000, outputTokens: 500),
          costUsd: 0.05,
          durationMs: 3000,
        ),
      );

      // Turn 2
      handler.handleEvent(
        chat,
        _makeTurnComplete(
          usage: const TokenUsage(inputTokens: 2000, outputTokens: 800),
          costUsd: 0.08,
          durationMs: 5000,
        ),
      );

      final updated = ticketBoard.getTicket(ticket.id)!;
      expect(updated.costStats!.totalTokens, 4300); // 1500 + 2800
      expect(updated.costStats!.totalCost, 0.13);
      expect(updated.costStats!.agentTimeMs, 8000);

      handler.dispose();
    });
  });

  // ===========================================================================
  // 11. View mode and detail mode
  // ===========================================================================
  group('View mode and detail mode', () {
    test('showCreateForm clears selection and sets create mode', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-modes'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );
      ticketBoard.selectTicket(t.id);
      expect(ticketBoard.selectedTicket, isNotNull);

      ticketBoard.showCreateForm();
      expect(ticketBoard.detailMode, TicketDetailMode.create);
      expect(ticketBoard.selectedTicket, isNull);
    });

    test('selectTicket sets detail mode', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-select-mode'),
      );

      final t = ticketBoard.createTicket(
        title: 'Ticket',
        kind: TicketKind.feature,
      );

      ticketBoard.showCreateForm();
      expect(ticketBoard.detailMode, TicketDetailMode.create);

      ticketBoard.selectTicket(t.id);
      expect(ticketBoard.detailMode, TicketDetailMode.detail);
    });

    test('setViewMode toggles between list and graph', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-view-mode'),
      );

      expect(ticketBoard.viewMode, TicketViewMode.list);

      ticketBoard.setViewMode(TicketViewMode.graph);
      expect(ticketBoard.viewMode, TicketViewMode.graph);

      ticketBoard.setViewMode(TicketViewMode.list);
      expect(ticketBoard.viewMode, TicketViewMode.list);
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
        description: 'A comprehensive description',
        status: TicketStatus.inReview,
        kind: TicketKind.bugfix,
        priority: TicketPriority.critical,
        effort: TicketEffort.large,
        category: 'Testing',
        tags: {'tag1', 'tag2'},
        dependsOn: [1, 2, 3],
        linkedWorktrees: [
          const LinkedWorktree(
            worktreeRoot: '/path/wt',
            branch: 'branch-name',
          ),
        ],
        linkedChats: [
          const LinkedChat(
            chatId: 'chat-1',
            chatName: 'Chat Name',
            worktreeRoot: '/path/wt',
          ),
        ],
        sourceConversationId: 'conv-123',
        costStats: const TicketCostStats(
          totalTokens: 5000,
          totalCost: 0.25,
          agentTimeMs: 15000,
          waitingTimeMs: 3000,
        ),
        createdAt: now,
        updatedAt: now,
      );

      final json = ticket.toJson();
      final restored = TicketData.fromJson(json);

      expect(restored.id, ticket.id);
      expect(restored.title, ticket.title);
      expect(restored.description, ticket.description);
      expect(restored.status, ticket.status);
      expect(restored.kind, ticket.kind);
      expect(restored.priority, ticket.priority);
      expect(restored.effort, ticket.effort);
      expect(restored.category, ticket.category);
      expect(restored.tags, ticket.tags);
      expect(restored.dependsOn, ticket.dependsOn);
      expect(restored.linkedWorktrees.length, 1);
      expect(
        restored.linkedWorktrees.first.worktreeRoot,
        '/path/wt',
      );
      expect(restored.linkedChats.length, 1);
      expect(restored.linkedChats.first.chatId, 'chat-1');
      expect(restored.sourceConversationId, 'conv-123');
      expect(restored.costStats!.totalTokens, 5000);
      expect(restored.costStats!.totalCost, 0.25);
      expect(restored.costStats!.agentTimeMs, 15000);
      expect(restored.costStats!.waitingTimeMs, 3000);
    });

    test('copyWith with clear flags works correctly', () {
      final now = DateTime.now();
      final ticket = TicketData(
        id: 1,
        title: 'Test',
        description: 'Desc',
        status: TicketStatus.ready,
        kind: TicketKind.feature,
        priority: TicketPriority.medium,
        effort: TicketEffort.medium,
        category: 'Cat',
        sourceConversationId: 'conv-1',
        costStats: const TicketCostStats(
          totalTokens: 100,
          totalCost: 0.01,
          agentTimeMs: 1000,
          waitingTimeMs: 500,
        ),
        createdAt: now,
        updatedAt: now,
      );

      final cleared = ticket.copyWith(
        clearCategory: true,
        clearSourceConversationId: true,
        clearCostStats: true,
      );

      expect(cleared.category, isNull);
      expect(cleared.sourceConversationId, isNull);
      expect(cleared.costStats, isNull);
    });

    test('TicketProposal fromJson works with minimal fields', () {
      final proposal = TicketProposal.fromJson({
        'title': 'Minimal proposal',
      });

      expect(proposal.title, 'Minimal proposal');
      expect(proposal.description, '');
      expect(proposal.kind, TicketKind.feature);
      expect(proposal.priority, TicketPriority.medium);
      expect(proposal.effort, TicketEffort.medium);
      expect(proposal.category, isNull);
      expect(proposal.tags, isEmpty);
      expect(proposal.dependsOnIndices, isEmpty);
    });
  });

  // ===========================================================================
  // 13. Notification behavior
  // ===========================================================================
  group('Notification behavior', () {
    test('CRUD operations trigger notifyListeners', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-notifications'),
      );

      var notificationCount = 0;
      ticketBoard.addListener(() {
        notificationCount++;
      });

      // Create should notify
      final t = ticketBoard.createTicket(
        title: 'Task',
        kind: TicketKind.feature,
      );
      expect(notificationCount, greaterThan(0));
      final countAfterCreate = notificationCount;

      // Update should notify
      ticketBoard.updateTicket(t.id, (ticket) => ticket.copyWith(title: 'New'));
      expect(notificationCount, greaterThan(countAfterCreate));
      final countAfterUpdate = notificationCount;

      // Delete should notify
      ticketBoard.deleteTicket(t.id);
      expect(notificationCount, greaterThan(countAfterUpdate));
    });

    test('filter and search changes trigger notifyListeners', () {
      final ticketBoard = resources.track(
        TicketBoardState('test-filter-notify'),
      );

      var notified = false;
      ticketBoard.addListener(() {
        notified = true;
      });

      ticketBoard.setSearchQuery('test');
      expect(notified, isTrue);

      notified = false;
      ticketBoard.setStatusFilter(TicketStatus.active);
      expect(notified, isTrue);

      notified = false;
      ticketBoard.setKindFilter(TicketKind.bugfix);
      expect(notified, isTrue);

      notified = false;
      ticketBoard.setPriorityFilter(TicketPriority.high);
      expect(notified, isTrue);

      notified = false;
      ticketBoard.setCategoryFilter('Frontend');
      expect(notified, isTrue);

      notified = false;
      ticketBoard.setGroupBy(TicketGroupBy.status);
      expect(notified, isTrue);
    });
  });
}
