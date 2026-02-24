import 'dart:convert';

import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/widgets/tool_card.dart';
import 'package:cc_insights_v2/widgets/tool_card_cci_orch.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  ToolUseOutputEntry createOrchEntry({
    required String toolName,
    Map<String, dynamic> toolInput = const {},
    dynamic result,
    bool isError = false,
  }) {
    return ToolUseOutputEntry(
      timestamp: DateTime.now(),
      toolName: 'mcp__cci__$toolName',
      toolKind: ToolKind.mcp,
      toolUseId: 'test-id',
      toolInput: toolInput,
      result: result,
      isError: isError,
    );
  }

  Widget createTestApp({
    required ToolUseOutputEntry entry,
    String? projectDir,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ToolCard(
            entry: entry,
            projectDir: projectDir,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Detection helper tests
  // -------------------------------------------------------------------------

  group('cciOrchToolName', () {
    test('detects all orchestrator tools', () {
      final tools = [
        'launch_agent',
        'tell_agent',
        'ask_agent',
        'wait_for_agents',
        'check_agents',
        'create_ticket',
        'list_tickets',
        'get_ticket',
        'update_ticket',
        'create_worktree',
        'rebase_and_merge',
        'set_tags',
        'list_tags',
      ];

      for (final tool in tools) {
        check(cciOrchToolName('mcp__cci__$tool'))
            .isNotNull()
            .equals(tool);
      }
    });

    test('returns null for git tools', () {
      check(cciOrchToolName('mcp__cci__git_commit')).isNull();
      check(cciOrchToolName('mcp__cci__git_diff')).isNull();
    });

    test('returns null for non-cci MCP tools', () {
      check(cciOrchToolName('mcp__other__launch_agent')).isNull();
    });

    test('returns null for non-MCP tool names', () {
      check(cciOrchToolName('Bash')).isNull();
      check(cciOrchToolName('Read')).isNull();
    });
  });

  group('cciOrchFriendlyName', () {
    test('returns friendly names', () {
      check(cciOrchFriendlyName('launch_agent')).equals('Launch Agent');
      check(cciOrchFriendlyName('ask_agent')).equals('Ask Agent');
      check(cciOrchFriendlyName('update_ticket')).equals('Update Ticket');
      check(cciOrchFriendlyName('rebase_and_merge')).equals('Rebase & Merge');
    });

    test('returns null for unknown', () {
      check(cciOrchFriendlyName('unknown_tool')).isNull();
    });
  });

  group('cciOrchSummary', () {
    test('launch_agent shows name and ticket', () {
      final summary = cciOrchSummary('launch_agent', {
        'name': 'tkt-040-impl',
        'ticket_id': 40,
        'worktree': '/path/to/wt',
        'instructions': 'Do something',
      });
      check(summary).equals('tkt-040-impl TKT-40');
    });

    test('launch_agent falls back to truncated instructions', () {
      final summary = cciOrchSummary('launch_agent', {
        'worktree': '/path',
        'instructions': 'A' * 60,
      });
      check(summary.length).isLessOrEqual(50);
    });

    test('ask_agent shows agent and message', () {
      final summary = cciOrchSummary('ask_agent', {
        'agent_id': 'agent-chat-1234567890',
        'message': 'What is the status?',
      });
      check(summary).contains('What is the status?');
    });

    test('update_ticket shows id and status', () {
      final summary = cciOrchSummary('update_ticket', {
        'ticket_id': 41,
        'status': 'active',
      });
      check(summary).contains('TKT-41');
      check(summary).contains('active');
    });

    test('create_ticket shows count', () {
      final summary = cciOrchSummary('create_ticket', {
        'tickets': [
          {'title': 'A', 'description': 'a', 'kind': 'feature'},
          {'title': 'B', 'description': 'b', 'kind': 'bugfix'},
        ],
      });
      check(summary).equals('2 tickets');
    });

    test('wait_for_agents shows count', () {
      final summary = cciOrchSummary('wait_for_agents', {
        'agent_ids': ['a1', 'a2', 'a3'],
      });
      check(summary).equals('3 agents');
    });
  });

  // -------------------------------------------------------------------------
  // Widget rendering tests
  // -------------------------------------------------------------------------

  group('ToolCard renders orchestrator tools', () {
    testWidgets('shows friendly name for launch_agent', (tester) async {
      final entry = createOrchEntry(
        toolName: 'launch_agent',
        toolInput: {
          'worktree': '/Users/test/wt',
          'instructions': 'Implement the feature',
          'name': 'worker-1',
        },
        result: jsonEncode({
          'agent_id': 'agent-chat-123',
          'chat_id': 'chat-123',
          'worktree': '/Users/test/wt',
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      expect(find.text('Launch Agent'), findsOneWidget);
      expect(find.byIcon(Icons.rocket_launch_outlined), findsOneWidget);
    });

    testWidgets('shows friendly name for ask_agent', (tester) async {
      final entry = createOrchEntry(
        toolName: 'ask_agent',
        toolInput: {
          'agent_id': 'agent-chat-1771936840339',
          'message': 'What is the status of your work?',
          'timeout_seconds': 30,
        },
        result: jsonEncode({
          'response': 'All tests pass.',
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      expect(find.text('Ask Agent'), findsOneWidget);
      expect(find.byIcon(Icons.question_answer_outlined), findsOneWidget);
    });

    testWidgets('shows friendly name for update_ticket', (tester) async {
      final entry = createOrchEntry(
        toolName: 'update_ticket',
        toolInput: {
          'ticket_id': 41,
          'status': 'active',
        },
        result: jsonEncode({
          'success': true,
          'previous_status': 'ready',
          'new_status': 'active',
          'unblocked_tickets': [43, 49],
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      expect(find.text('Update Ticket'), findsOneWidget);
      expect(find.byIcon(Icons.update), findsOneWidget);
    });

    testWidgets('expands to show input and result for launch_agent',
        (tester) async {
      final entry = createOrchEntry(
        toolName: 'launch_agent',
        toolInput: {
          'worktree': '/Users/test/project/wt',
          'instructions': 'Implement TKT-40',
          'name': 'tkt-040-impl',
          'ticket_id': 40,
        },
        result: jsonEncode({
          'agent_id': 'agent-chat-123456',
          'chat_id': 'chat-123456',
          'worktree': '/Users/test/project/wt',
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Expand
      await tester.tap(find.text('Launch Agent'));
      await safePumpAndSettle(tester);

      // Input: should show name badge and instructions
      expect(find.text('tkt-040-impl'), findsOneWidget);
      expect(find.text('TKT-40'), findsOneWidget);
      expect(find.text('Implement TKT-40'), findsOneWidget);

      // Result: should show "Agent launched"
      expect(find.text('Agent launched'), findsOneWidget);
    });

    testWidgets('expands to show input and result for ask_agent',
        (tester) async {
      final entry = createOrchEntry(
        toolName: 'ask_agent',
        toolInput: {
          'agent_id': 'agent-chat-1771936840339',
          'message': 'Did all tests pass?',
          'timeout_seconds': 30,
        },
        result: jsonEncode({
          'response': 'All tests pass (13/13). No issues.',
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Expand
      await tester.tap(find.text('Ask Agent'));
      await safePumpAndSettle(tester);

      // Input: should show message
      expect(find.text('Did all tests pass?'), findsOneWidget);

      // Result: should show response text
      expect(find.text('All tests pass (13/13). No issues.'), findsOneWidget);
    });

    testWidgets('expands to show status transition for update_ticket',
        (tester) async {
      final entry = createOrchEntry(
        toolName: 'update_ticket',
        toolInput: {
          'ticket_id': 41,
          'status': 'active',
        },
        result: jsonEncode({
          'success': true,
          'previous_status': 'ready',
          'new_status': 'active',
          'unblocked_tickets': [43, 49],
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Expand
      await tester.tap(find.text('Update Ticket'));
      await safePumpAndSettle(tester);

      // Input: should show ticket id and target status
      expect(find.text('TKT-41'), findsOneWidget);

      // Result: should show status badges
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('active'), findsAtLeast(1));

      // Should show unblocked tickets
      expect(find.text('Unblocked: '), findsOneWidget);
      expect(find.text('TKT-43'), findsOneWidget);
      expect(find.text('TKT-49'), findsOneWidget);
    });

    testWidgets('expands to show ticket list for list_tickets',
        (tester) async {
      final entry = createOrchEntry(
        toolName: 'list_tickets',
        toolInput: {
          'status': ['active', 'blocked'],
        },
        result: jsonEncode({
          'tickets': [
            {
              'id': 1,
              'display_id': 'TKT-001',
              'title': 'First ticket',
              'status': 'active',
              'kind': 'feature',
            },
            {
              'id': 2,
              'display_id': 'TKT-002',
              'title': 'Second ticket',
              'status': 'blocked',
              'kind': 'bugfix',
            },
          ],
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Expand
      await tester.tap(find.text('List Tickets'));
      await safePumpAndSettle(tester);

      // Result: should show ticket rows
      expect(find.text('TKT-001'), findsOneWidget);
      expect(find.text('First ticket'), findsOneWidget);
      expect(find.text('TKT-002'), findsOneWidget);
      expect(find.text('Second ticket'), findsOneWidget);
    });

    testWidgets('shows tell_agent with restarted badge', (tester) async {
      final entry = createOrchEntry(
        toolName: 'tell_agent',
        toolInput: {
          'agent_id': 'agent-chat-123',
          'message': 'Please continue working',
        },
        result: jsonEncode({
          'success': true,
          'restarted': true,
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      expect(find.text('Tell Agent'), findsOneWidget);

      // Expand
      await tester.tap(find.text('Tell Agent'));
      await safePumpAndSettle(tester);

      // Result: should show "Message sent" and "restarted" badge
      expect(find.text('Message sent'), findsOneWidget);
      expect(find.text('restarted'), findsOneWidget);
    });

    testWidgets('shows create_worktree result', (tester) async {
      final entry = createOrchEntry(
        toolName: 'create_worktree',
        toolInput: {
          'branch_name': 'feat/my-feature',
          'base_ref': 'main',
        },
        result: jsonEncode({
          'success': true,
          'worktree_path': '/Users/test/wt/feat-my-feature',
          'branch': 'feat/my-feature',
        }),
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      expect(find.text('Create Worktree'), findsOneWidget);

      // Expand
      await tester.tap(find.text('Create Worktree'));
      await safePumpAndSettle(tester);

      // Input
      expect(find.text('feat/my-feature'), findsAtLeast(1));
      expect(find.text('main'), findsOneWidget);

      // Result
      expect(find.text('Worktree created'), findsOneWidget);
    });

    testWidgets('non-cci MCP tools still use generic rendering',
        (tester) async {
      final entry = ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: 'mcp__websearch__search',
        toolKind: ToolKind.mcp,
        toolUseId: 'test-id',
        toolInput: {'key': 'value'},
        result: 'some result',
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Should fall through to generic MCP formatting
      expect(find.text('MCP(websearch:search)'), findsOneWidget);
    });
  });

  group('create_ticket input widget', () {
    testWidgets('shows numbered ticket proposals', (tester) async {
      final entry = createOrchEntry(
        toolName: 'create_ticket',
        toolInput: {
          'tickets': [
            {
              'title': 'Add auth',
              'description': 'Implement auth',
              'kind': 'feature',
              'priority': 'high',
            },
            {
              'title': 'Fix login',
              'description': 'Fix login bug',
              'kind': 'bugfix',
            },
          ],
        },
        result: 'Created 2 tickets',
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Expand
      await tester.tap(find.text('Create Tickets'));
      await safePumpAndSettle(tester);

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('Add auth'), findsOneWidget);
      expect(find.text('Fix login'), findsOneWidget);
      expect(find.text('feature'), findsOneWidget);
      expect(find.text('bugfix'), findsOneWidget);
    });
  });

  group('error fallback', () {
    testWidgets('shows error for orchestrator tool with isError',
        (tester) async {
      final entry = createOrchEntry(
        toolName: 'launch_agent',
        toolInput: {'worktree': '/path', 'instructions': 'do stuff'},
        result: 'Error: agent failed to start',
        isError: true,
      );

      await tester.pumpWidget(createTestApp(entry: entry));
      await safePumpAndSettle(tester);

      // Error icon should appear
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}
