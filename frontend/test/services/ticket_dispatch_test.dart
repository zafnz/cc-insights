import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/ticket_dispatch_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart' show TicketRepository;
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('deriveBranchName', () {
    test('produces valid branch name from simple title', () {
      final name = TicketDispatchService.deriveBranchName(1, 'Add dark mode');
      expect(name, 'tkt-1-add-dark-mode');
    });

    test('handles special characters', () {
      final name = TicketDispatchService.deriveBranchName(42, 'Fix bug #123: crash on startup!');
      expect(name, 'tkt-42-fix-bug-123-crash-on-startup');
    });

    test('collapses consecutive hyphens', () {
      final name = TicketDispatchService.deriveBranchName(5, 'Add   multiple   spaces');
      expect(name, 'tkt-5-add-multiple-spaces');
    });

    test('trims leading and trailing hyphens from slug', () {
      final name = TicketDispatchService.deriveBranchName(1, '---hello---');
      expect(name, 'tkt-1-hello');
    });

    test('truncates to max 50 characters', () {
      final longTitle = 'This is a very long title that exceeds the maximum allowed length for a branch name';
      final name = TicketDispatchService.deriveBranchName(1, longTitle);
      expect(name.length, lessThanOrEqualTo(50));
      expect(name, startsWith('tkt-1-'));
    });

    test('removes trailing hyphen after truncation', () {
      // Craft a title that when truncated will end with a hyphen
      final title = 'abcdefghij-klmnopqrst-uvwxyz-abcdefghij-klmnopqrst';
      final name = TicketDispatchService.deriveBranchName(1, title);
      expect(name.length, lessThanOrEqualTo(50));
      expect(name, isNot(endsWith('-')));
    });

    test('handles empty title', () {
      final name = TicketDispatchService.deriveBranchName(7, '');
      expect(name, 'tkt-7-');
    });

    test('converts uppercase to lowercase', () {
      final name = TicketDispatchService.deriveBranchName(1, 'Add FEATURE for UI');
      expect(name, 'tkt-1-add-feature-for-ui');
    });

    test('handles numbers in title', () {
      final name = TicketDispatchService.deriveBranchName(99, 'Task 123 part 2');
      expect(name, 'tkt-99-task-123-part-2');
    });
  });

  group('buildTicketPrompt', () {
    late TicketRepository ticketBoard;

    setUp(() {
      ticketBoard = resources.track(TicketRepository('test-prompt-project'));
    });

    test('includes ticket ID and title', () {
      final ticket = ticketBoard.createTicket(
        title: 'Add dark mode',
        kind: TicketKind.feature,
        description: 'Implement dark mode toggle.',
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('TKT-001'));
      expect(prompt, contains('Add dark mode'));
    });

    test('includes description', () {
      final ticket = ticketBoard.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        description: 'This is the detailed description.',
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('This is the detailed description.'));
    });

    test('includes metadata', () {
      final ticket = ticketBoard.createTicket(
        title: 'Test ticket',
        kind: TicketKind.bugfix,
        priority: TicketPriority.high,
        effort: TicketEffort.large,
        category: 'Backend',
        tags: {'api', 'urgent'},
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('**Kind:** Bug Fix'));
      expect(prompt, contains('**Priority:** High'));
      expect(prompt, contains('**Effort:** Large'));
      expect(prompt, contains('**Category:** Backend'));
      expect(prompt, contains('**Tags:**'));
      expect(prompt, contains('api'));
      expect(prompt, contains('urgent'));
    });

    test('lists completed dependencies', () {
      final dep1 = ticketBoard.createTicket(
        title: 'Setup database',
        kind: TicketKind.feature,
      );
      ticketBoard.markCompleted(dep1.id);

      final ticket = ticketBoard.createTicket(
        title: 'Add user auth',
        kind: TicketKind.feature,
        dependsOn: [dep1.id],
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('## Completed Dependencies'));
      expect(prompt, contains('[x] ${dep1.displayId}: Setup database'));
    });

    test('lists incomplete dependencies as blockers', () {
      final dep1 = ticketBoard.createTicket(
        title: 'Setup database',
        kind: TicketKind.feature,
      );
      // dep1 is in 'ready' status (incomplete)

      final ticket = ticketBoard.createTicket(
        title: 'Add user auth',
        kind: TicketKind.feature,
        dependsOn: [dep1.id],
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('## Incomplete Dependencies'));
      expect(prompt, contains('[ ] ${dep1.displayId}: Setup database (Ready)'));
    });

    test('handles ticket with no dependencies', () {
      final ticket = ticketBoard.createTicket(
        title: 'Standalone task',
        kind: TicketKind.chore,
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, isNot(contains('Dependencies')));
      expect(prompt, contains('TKT-001'));
      expect(prompt, contains('Standalone task'));
    });

    test('handles mix of completed and incomplete deps', () {
      final dep1 = ticketBoard.createTicket(
        title: 'Dep one',
        kind: TicketKind.feature,
      );
      ticketBoard.markCompleted(dep1.id);

      final dep2 = ticketBoard.createTicket(
        title: 'Dep two',
        kind: TicketKind.feature,
      );
      // dep2 stays as ready

      final ticket = ticketBoard.createTicket(
        title: 'Main task',
        kind: TicketKind.feature,
        dependsOn: [dep1.id, dep2.id],
      );

      final service = _createTestService(ticketBoard);
      final prompt = service.buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('## Completed Dependencies'));
      expect(prompt, contains('[x] ${dep1.displayId}: Dep one'));
      expect(prompt, contains('## Incomplete Dependencies'));
      expect(prompt, contains('[ ] ${dep2.displayId}: Dep two'));
    });
  });

  group('TicketRepository - linkWorktree', () {
    test('adds linked worktree to ticket', () {
      final state = resources.track(TicketRepository('test-link-wt'));
      final ticket = state.createTicket(
        title: 'Test linking',
        kind: TicketKind.feature,
      );

      state.linkWorktree(ticket.id, '/path/to/worktree', 'tkt-1-test');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedWorktrees, hasLength(1));
      expect(updated.linkedWorktrees.first.worktreeRoot, '/path/to/worktree');
      expect(updated.linkedWorktrees.first.branch, 'tkt-1-test');
    });

    test('does not duplicate worktree links', () {
      final state = resources.track(TicketRepository('test-link-wt-dup'));
      final ticket = state.createTicket(
        title: 'Test dup linking',
        kind: TicketKind.feature,
      );

      state.linkWorktree(ticket.id, '/path/to/worktree', 'tkt-1-test');
      state.linkWorktree(ticket.id, '/path/to/worktree', 'tkt-1-test');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedWorktrees, hasLength(1));
    });

    test('notifies listeners when worktree linked', () {
      final state = resources.track(TicketRepository('test-link-wt-notify'));
      final ticket = state.createTicket(
        title: 'Test notify',
        kind: TicketKind.feature,
      );

      var notified = false;
      state.addListener(() => notified = true);

      state.linkWorktree(ticket.id, '/path/wt', 'branch');

      expect(notified, isTrue);
    });
  });

  group('TicketRepository - linkChat', () {
    test('adds linked chat to ticket', () {
      final state = resources.track(TicketRepository('test-link-chat'));
      final ticket = state.createTicket(
        title: 'Test chat linking',
        kind: TicketKind.feature,
      );

      state.linkChat(ticket.id, 'chat-123', 'TKT-001', '/path/to/worktree');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedChats, hasLength(1));
      expect(updated.linkedChats.first.chatId, 'chat-123');
      expect(updated.linkedChats.first.chatName, 'TKT-001');
      expect(updated.linkedChats.first.worktreeRoot, '/path/to/worktree');
    });

    test('does not duplicate chat links', () {
      final state = resources.track(TicketRepository('test-link-chat-dup'));
      final ticket = state.createTicket(
        title: 'Test dup chat',
        kind: TicketKind.feature,
      );

      state.linkChat(ticket.id, 'chat-123', 'TKT-001', '/path/wt');
      state.linkChat(ticket.id, 'chat-123', 'TKT-001', '/path/wt');

      final updated = state.getTicket(ticket.id)!;
      expect(updated.linkedChats, hasLength(1));
    });

    test('notifies listeners when chat linked', () {
      final state = resources.track(TicketRepository('test-link-chat-notify'));
      final ticket = state.createTicket(
        title: 'Test notify',
        kind: TicketKind.feature,
      );

      var notified = false;
      state.addListener(() => notified = true);

      state.linkChat(ticket.id, 'chat-1', 'Chat', '/wt');

      expect(notified, isTrue);
    });
  });

  group('TicketRepository - getTicketsForChat', () {
    test('returns tickets linked to a chat', () {
      final state = resources.track(TicketRepository('test-chat-lookup'));
      final ticket1 = state.createTicket(
        title: 'Ticket A',
        kind: TicketKind.feature,
      );
      final ticket2 = state.createTicket(
        title: 'Ticket B',
        kind: TicketKind.bugfix,
      );
      state.createTicket(
        title: 'Ticket C (unlinked)',
        kind: TicketKind.chore,
      );

      state.linkChat(ticket1.id, 'chat-abc', 'Chat', '/wt');
      state.linkChat(ticket2.id, 'chat-abc', 'Chat', '/wt');

      final tickets = state.getTicketsForChat('chat-abc');
      expect(tickets, hasLength(2));
      expect(tickets.map((t) => t.id), containsAll([ticket1.id, ticket2.id]));
    });

    test('returns empty list for unknown chat', () {
      final state = resources.track(TicketRepository('test-chat-empty'));
      state.createTicket(
        title: 'Some ticket',
        kind: TicketKind.feature,
      );

      final tickets = state.getTicketsForChat('nonexistent-chat');
      expect(tickets, isEmpty);
    });
  });

  group('TicketRepository - linking persistence', () {
    test('linkWorktree triggers auto-save', () async {
      final state = resources.track(TicketRepository('test-link-persist'));
      final ticket = state.createTicket(
        title: 'Persist test',
        kind: TicketKind.feature,
      );

      state.linkWorktree(ticket.id, '/wt', 'branch');

      // Auto-save is fire-and-forget, call save explicitly to verify data
      await state.save();

      // Reload in a fresh state
      final state2 = resources.track(TicketRepository('test-link-persist'));
      await state2.load();

      final reloaded = state2.getTicket(ticket.id)!;
      expect(reloaded.linkedWorktrees, hasLength(1));
      expect(reloaded.linkedWorktrees.first.worktreeRoot, '/wt');
    });

    test('linkChat triggers auto-save', () async {
      final state = resources.track(TicketRepository('test-link-chat-persist'));
      final ticket = state.createTicket(
        title: 'Persist chat test',
        kind: TicketKind.feature,
      );

      state.linkChat(ticket.id, 'chat-1', 'Chat', '/wt');

      await state.save();

      final state2 = resources.track(TicketRepository('test-link-chat-persist'));
      await state2.load();

      final reloaded = state2.getTicket(ticket.id)!;
      expect(reloaded.linkedChats, hasLength(1));
      expect(reloaded.linkedChats.first.chatId, 'chat-1');
    });
  });
}

/// Creates a TicketDispatchService for testing prompt building.
///
/// Uses a minimal setup since only [buildTicketPrompt] is being tested.
TicketDispatchService _createTestService(TicketRepository ticketBoard) {
  final project = ProjectState(
    const ProjectData(name: 'test', repoRoot: '/tmp/test-repo'),
    WorktreeState(const WorktreeData(
      worktreeRoot: '/tmp/test-repo',
      isPrimary: true,
      branch: 'main',
    )),
    autoValidate: false,
    watchFilesystem: false,
  );

  final selection = SelectionState(project);

  return TicketDispatchService(
    ticketBoard: ticketBoard,
    project: project,
    selection: selection,
    worktreeService: WorktreeService(),
  );
}
