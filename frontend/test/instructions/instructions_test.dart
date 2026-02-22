import 'package:cc_insights_v2/instructions/instructions.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();

  tearDown(() async {
    await resources.disposeAll();
  });

  group('gitToolsSystemPrompt', () {
    test('mentions all tool names', () {
      expect(gitToolsSystemPrompt, contains('git_commit_context'));
      expect(gitToolsSystemPrompt, contains('git_commit'));
      expect(gitToolsSystemPrompt, contains('git_log'));
      expect(gitToolsSystemPrompt, contains('git_diff'));
    });

    test('advises preferring tools over shell', () {
      expect(gitToolsSystemPrompt, contains('Prefer these over running git'));
    });
  });

  group('mergeConflictGuidance', () {
    test('describes the rebase_and_merge conflict flow', () {
      expect(mergeConflictGuidance, contains('rebase_and_merge'));
      expect(mergeConflictGuidance, contains('launch_agent'));
      expect(mergeConflictGuidance, contains('wait_for_agents'));
    });
  });

  group('orchestratorSystemPrompt', () {
    test('includes merge conflict guidance', () {
      expect(orchestratorSystemPrompt, contains('rebase_and_merge'));
      expect(orchestratorSystemPrompt, contains('launch_agent'));
    });

    test('describes the orchestrator role', () {
      expect(orchestratorSystemPrompt, contains('project orchestrator'));
      expect(
        orchestratorSystemPrompt,
        contains('NEVER perform implementation work yourself'),
      );
    });
  });

  group('buildOrchestrationLaunchMessage', () {
    test('includes ticket IDs', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [1, 2, 3],
        worktreePath: '/tmp/wt',
        branch: 'feat-test',
      );

      expect(message, contains('1, 2, 3'));
    });

    test('includes base worktree path and branch', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [5],
        worktreePath: '/home/user/project/.worktrees/feat',
        branch: 'feat-dark-mode',
      );

      expect(
        message,
        contains('Base worktree: /home/user/project/.worktrees/feat'),
      );
      expect(message, contains('Base branch: feat-dark-mode'));
    });

    test('uses default instructions when none provided', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [10],
        worktreePath: '/tmp/wt',
        branch: 'main',
      );

      expect(message, contains('Respect dependencies'));
      expect(message, contains('parallel execution'));
    });

    test('uses custom instructions when provided', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [7],
        worktreePath: '/tmp/wt',
        branch: 'main',
        instructions: 'Run sequentially, no parallelism.',
      );

      expect(message, contains('Run sequentially, no parallelism.'));
      expect(message, isNot(contains('Respect dependencies')));
      expect(message, contains('Base worktree: /tmp/wt'));
    });

    test('falls back to default when instructions is empty string', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [1],
        worktreePath: '/tmp/wt',
        branch: 'main',
        instructions: '',
      );

      expect(message, contains('Respect dependencies'));
      expect(message, contains('parallel execution'));
    });

    test('falls back to default when instructions is whitespace only', () {
      final message = buildOrchestrationLaunchMessage(
        ticketIds: [1],
        worktreePath: '/tmp/wt',
        branch: 'main',
        instructions: '   ',
      );

      expect(message, contains('Respect dependencies'));
      expect(message, contains('parallel execution'));
    });
  });

  group('buildTicketPrompt', () {
    late TicketRepository ticketBoard;

    setUp(() {
      ticketBoard = resources.track(TicketRepository('test-instructions'));
    });

    test('includes ticket ID and title', () {
      final ticket = ticketBoard.createTicket(
        title: 'Add dark mode',
        kind: TicketKind.feature,
        description: 'Implement dark mode toggle.',
      );

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('TKT-001'));
      expect(prompt, contains('Add dark mode'));
    });

    test('includes description', () {
      final ticket = ticketBoard.createTicket(
        title: 'Test ticket',
        kind: TicketKind.feature,
        description: 'Detailed description here.',
      );

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('Detailed description here.'));
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

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('**Kind:** Bug Fix'));
      expect(prompt, contains('**Priority:** High'));
      expect(prompt, contains('**Effort:** Large'));
      expect(prompt, contains('**Category:** Backend'));
      expect(prompt, contains('api'));
      expect(prompt, contains('urgent'));
    });

    test('lists completed dependencies', () {
      final dep = ticketBoard.createTicket(
        title: 'Setup database',
        kind: TicketKind.feature,
      );
      ticketBoard.markCompleted(dep.id);

      final ticket = ticketBoard.createTicket(
        title: 'Add user auth',
        kind: TicketKind.feature,
        dependsOn: [dep.id],
      );

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('## Completed Dependencies'));
      expect(prompt, contains('[x] ${dep.displayId}: Setup database'));
    });

    test('lists incomplete dependencies as blockers', () {
      final dep = ticketBoard.createTicket(
        title: 'Setup database',
        kind: TicketKind.feature,
      );

      final ticket = ticketBoard.createTicket(
        title: 'Add user auth',
        kind: TicketKind.feature,
        dependsOn: [dep.id],
      );

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, contains('## Incomplete Dependencies'));
      expect(
        prompt,
        contains('[ ] ${dep.displayId}: Setup database (Ready)'),
      );
    });

    test('handles ticket with no dependencies', () {
      final ticket = ticketBoard.createTicket(
        title: 'Standalone task',
        kind: TicketKind.chore,
      );

      final prompt = buildTicketPrompt(ticket, ticketBoard.tickets);

      expect(prompt, isNot(contains('Dependencies')));
      expect(prompt, contains('TKT-001'));
    });
  });
}
