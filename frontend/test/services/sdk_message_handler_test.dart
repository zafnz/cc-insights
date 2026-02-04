import 'dart:async';

import 'package:cc_insights_v2/models/agent.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/ask_ai_service.dart';
import 'package:cc_insights_v2/services/sdk_message_handler.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter_test/flutter_test.dart';

/// Mock AskAiService that returns a predefined title.
class MockAskAiService extends AskAiService {
  String? titleToReturn;
  bool shouldFail = false;
  String? lastPrompt;
  String? lastWorkingDirectory;

  @override
  Future<sdk.SingleRequestResult?> ask({
    required String prompt,
    required String workingDirectory,
    String model = 'haiku',
    List<String>? allowedTools,
    int? maxTurns,
    int timeoutSeconds = 60,
  }) async {
    lastPrompt = prompt;
    lastWorkingDirectory = workingDirectory;

    if (shouldFail) {
      return null;
    }

    final title = titleToReturn ?? 'Generated Title';
    return sdk.SingleRequestResult(
      result: '=====\n$title\n=====',
      isError: false,
      usage: const sdk.Usage(inputTokens: 10, outputTokens: 5),
      durationMs: 100,
      durationApiMs: 80,
      numTurns: 1,
      totalCostUsd: 0.001,
    );
  }
}

void main() {
  group('SdkMessageHandler', () {
    late ChatState chat;
    late SdkMessageHandler handler;

    setUp(() {
      chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
      handler = SdkMessageHandler();
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    group('system messages', () {
      test('handles init subtype (no-op)', () {
        // The init subtype is acknowledged but doesn't create entries
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'init',
          'model': 'claude-opus-4-5-20251101',
          'tools': ['Read', 'Write', 'Edit'],
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries).isEmpty();
      });

      test('handles compact_boundary with auto trigger', () {
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
          'compact_metadata': {
            'trigger': 'auto',
            'pre_tokens': 45000,
          },
        });

        final entries = chat.data.primaryConversation.entries;
        // Auto-compaction adds AutoCompactionEntry
        check(entries.length).equals(1);
        check(entries[0]).isA<AutoCompactionEntry>();

        final autoEntry = entries[0] as AutoCompactionEntry;
        check(autoEntry.message).equals('Was 45.0K tokens');
        check(autoEntry.isManual).isFalse();
      });

      test('handles compact_boundary with manual trigger', () {
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
          'compact_metadata': {
            'trigger': 'manual',
            'pre_tokens': 30000,
          },
        });

        final entries = chat.data.primaryConversation.entries;
        // Manual trigger adds AutoCompactionEntry with isManual: true
        check(entries.length).equals(1);
        check(entries.first).isA<AutoCompactionEntry>();

        final autoEntry = entries.first as AutoCompactionEntry;
        check(autoEntry.message).equals('Was 30.0K tokens');
        check(autoEntry.isManual).isTrue();
      });

      test('handles compact_boundary with missing compact_metadata', () {
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
        });

        final entries = chat.data.primaryConversation.entries;
        // Default trigger is 'auto', so AutoCompactionEntry is added
        check(entries.length).equals(1);
        check(entries.first).isA<AutoCompactionEntry>();
      });

      test('handles compact_boundary with pre_tokens in message', () {
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
          'compact_metadata': {
            'trigger': 'auto',
            'pre_tokens': 50000,
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries[0]).isA<AutoCompactionEntry>();

        final autoEntry = entries[0] as AutoCompactionEntry;
        check(autoEntry.message).equals('Was 50.0K tokens');
      });

      test('handles status subtype for compacting state', () {
        // Start compacting
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'status',
          'status': 'compacting',
        });

        check(chat.isCompacting).isTrue();

        // Finish compacting (status: null)
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'status',
          'status': null,
        });

        check(chat.isCompacting).isFalse();
      });
    });

    group('assistant messages', () {
      test('handles text block', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Hello, world!'},
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Hello, world!');
        check(textEntry.contentType).equals('text');
        check(textEntry.isStreaming).isFalse();
      });

      test('handles thinking block', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'thinking', 'thinking': 'Let me think about this...'},
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);

        final thinkingEntry = entries.first as TextOutputEntry;
        check(thinkingEntry.text).equals('Let me think about this...');
        check(thinkingEntry.contentType).equals('thinking');
      });

      test('handles tool_use block', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'model': 'claude-opus-4-5-20251101',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_123',
                'name': 'Read',
                'input': {'file_path': '/path/to/file.dart'},
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ToolUseOutputEntry>();

        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.toolName).equals('Read');
        check(toolEntry.toolUseId).equals('toolu_123');
        check(toolEntry.toolInput['file_path']).equals('/path/to/file.dart');
        check(toolEntry.model).equals('claude-opus-4-5-20251101');
        check(toolEntry.result).isNull();
      });

      test('handles multiple content blocks in one message', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'thinking', 'thinking': 'First I need to...'},
              {'type': 'text', 'text': 'Here is the answer:'},
              {
                'type': 'tool_use',
                'id': 'toolu_multi',
                'name': 'Edit',
                'input': {'file_path': '/test.dart'},
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(3);
        check(entries[0]).isA<TextOutputEntry>();
        check((entries[0] as TextOutputEntry).contentType).equals('thinking');
        check(entries[1]).isA<TextOutputEntry>();
        check((entries[1] as TextOutputEntry).contentType).equals('text');
        check(entries[2]).isA<ToolUseOutputEntry>();
      });

      test('handles empty content list gracefully', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {'content': <Map<String, dynamic>>[]},
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries).isEmpty();
      });

      test('handles missing message field gracefully', () {
        handler.handleMessage(chat, {'type': 'assistant'});

        final entries = chat.data.primaryConversation.entries;
        check(entries).isEmpty();
      });
    });

    group('user messages - tool_result pairing', () {
      test('pairs tool_result with tool_use', () {
        // First: tool_use arrives
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'model': 'claude-opus-4-5-20251101',
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_123',
                'name': 'Read',
                'input': {'file_path': '/path/to/file.dart'},
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.result).isNull();

        // Second: tool_result arrives
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_123',
                'content': 'File contents here...',
              },
            ],
          },
          'tool_use_result': {
            'filePath': '/path/to/file.dart',
            'content': 'class MyClass {}',
          },
        });

        // Entry count should still be 1 (updated in place)
        check(entries.length).equals(1);

        // Same entry should now have result
        check(toolEntry.result).isNotNull();
        check((toolEntry.result as Map)['filePath']).equals(
          '/path/to/file.dart',
        );
        check(toolEntry.isError).isFalse();
      });

      test('handles tool error result', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_456',
                'name': 'Read',
                'input': {'file_path': '/nonexistent'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_456',
                'content': 'File not found',
                'is_error': true,
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.isError).isTrue();
        check(toolEntry.result).equals('File not found');
      });

      test('ignores tool_result for unknown tool_use_id', () {
        // Send tool_result without prior tool_use
        var notified = false;
        chat.addListener(() => notified = true);

        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'unknown_id',
                'content': 'Some result',
              },
            ],
          },
        });

        // Should not notify listeners since no entry was updated
        check(notified).isFalse();
      });

      test('synthetic user messages create ContextSummaryEntry', () {
        // Synthetic user messages contain context summaries after compaction
        handler.handleMessage(chat, {
          'type': 'user',
          'isSynthetic': true,
          'message': {
            'content': [
              {
                'type': 'text',
                'text': 'Previous conversation discussed file organization...',
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ContextSummaryEntry>();

        final summaryEntry = entries.first as ContextSummaryEntry;
        check(summaryEntry.summary).equals(
          'Previous conversation discussed file organization...',
        );
      });

      test('synthetic user messages ignore empty text blocks', () {
        handler.handleMessage(chat, {
          'type': 'user',
          'isSynthetic': true,
          'message': {
            'content': [
              {'type': 'text', 'text': ''},
            ],
          },
        });

        check(chat.data.primaryConversation.entries).isEmpty();
      });

      test('synthetic user messages ignore non-text blocks', () {
        handler.handleMessage(chat, {
          'type': 'user',
          'isSynthetic': true,
          'message': {
            'content': [
              {'type': 'tool_result', 'tool_use_id': 'test', 'content': 'data'},
            ],
          },
        });

        check(chat.data.primaryConversation.entries).isEmpty();
      });

      test(
          'user message after compact_boundary is treated as context summary',
          () {
        // First, receive compact_boundary
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
          'compact_metadata': {
            'trigger': 'manual',
            'pre_tokens': 50000,
          },
        });

        // Next user message (without isSynthetic) should be treated as summary
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': 'This is the context summary after compaction.',
          },
          'isReplay': false,
        });

        final entries = chat.data.primaryConversation.entries;
        // Should have AutoCompactionEntry and ContextSummaryEntry
        check(entries.length).equals(2);
        check(entries[0]).isA<AutoCompactionEntry>();
        check(entries[1]).isA<ContextSummaryEntry>();

        final summaryEntry = entries[1] as ContextSummaryEntry;
        check(summaryEntry.summary)
            .equals('This is the context summary after compaction.');
      });

      test('replay messages after compact_boundary are not treated as summary',
          () {
        // First, receive compact_boundary
        handler.handleMessage(chat, {
          'type': 'system',
          'subtype': 'compact_boundary',
          'compact_metadata': {
            'trigger': 'manual',
            'pre_tokens': 50000,
          },
        });

        // Replay message should be skipped
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': '<local-command-stdout>Compacted</local-command-stdout>',
          },
          'isReplay': true,
        });

        final entries = chat.data.primaryConversation.entries;
        // Should only have AutoCompactionEntry, no ContextSummaryEntry
        check(entries.length).equals(1);
        check(entries[0]).isA<AutoCompactionEntry>();
      });

      test('uses fallback content when tool_use_result missing', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_fallback',
                'name': 'Read',
                'input': {},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_fallback',
                'content': 'fallback content string',
              },
            ],
          },
          // No tool_use_result field
        });

        final toolEntry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(toolEntry.result).equals('fallback content string');
      });

      test('clears pending permission when tool_result arrives (timeout case)',
          () {
        // This handles the timeout case: when the SDK times out waiting for
        // permission, it sends a tool result (denied), and we should dismiss
        // the stale permission widget.

        // First: tool_use arrives
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_timeout_test',
                'name': 'Bash',
                'input': {'command': 'rm -rf /'},
              },
            ],
          },
        });

        // Simulate a pending permission request for this tool
        // (normally this would come from the SDK via permissionRequests stream)
        chat.addPendingPermission(_MockPermissionRequest('toolu_timeout_test'));
        check(chat.isWaitingForPermission).isTrue();
        check(chat.pendingPermissionCount).equals(1);

        // SDK times out and sends a tool_result with error (permission denied)
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_timeout_test',
                'content': 'Permission request timed out',
                'is_error': true,
              },
            ],
          },
        });

        // The pending permission should be cleared
        check(chat.isWaitingForPermission).isFalse();
        check(chat.pendingPermissionCount).equals(0);
      });

      test(
          'clears only matching permission when multiple tools have pending requests',
          () {
        // This ensures parallel tool calls are handled correctly - only the
        // specific tool's permission is cleared, not others.

        // Two tools are running
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_parallel_1',
                'name': 'Bash',
                'input': {'command': 'ls'},
              },
              {
                'type': 'tool_use',
                'id': 'toolu_parallel_2',
                'name': 'Write',
                'input': {'file_path': '/test.txt'},
              },
            ],
          },
        });

        // Both have pending permission requests
        chat.addPendingPermission(_MockPermissionRequest('toolu_parallel_1'));
        chat.addPendingPermission(_MockPermissionRequest('toolu_parallel_2'));
        check(chat.pendingPermissionCount).equals(2);

        // First tool result arrives (timeout/denied)
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_parallel_1',
                'content': 'Permission denied',
                'is_error': true,
              },
            ],
          },
        });

        // Only first permission should be cleared
        check(chat.pendingPermissionCount).equals(1);
        check(chat.pendingPermission!.toolUseId).equals('toolu_parallel_2');
      });
    });

    group('Task tool spawning', () {
      test('creates subagent conversation for Task tool', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_task_789',
                'name': 'Task',
                'input': {
                  'subagent_type': 'Explore',
                  'description': 'Search codebase',
                  'prompt': 'Find all usages of...',
                },
              },
            ],
          },
        });

        // Should have created a subagent conversation
        check(chat.data.subagentConversations).isNotEmpty();
        check(chat.activeAgents).isNotEmpty();

        final agent = chat.activeAgents['toolu_task_789'];
        check(agent).isNotNull();
        check(agent!.sdkAgentId).equals('toolu_task_789');
        check(agent.status).equals(AgentStatus.working);
      });

      test('uses default values when Task input is incomplete', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_task_minimal',
                'name': 'Task',
                'input': {}, // Missing subagent_type/name and description
              },
            ],
          },
        });

        check(chat.data.subagentConversations).isNotEmpty();
        final conv = chat.data.subagentConversations.values.first;
        // Label is null when subagent_type/name is missing (fallback uses subagentNumber)
        check(conv.label).isNull();
        // Task description is null when description is missing
        check(conv.taskDescription).isNull();
        // subagentNumber is used for fallback display "Subagent #N"
        check(conv.subagentNumber).equals(1);
      });

      test('does not create subagent for non-Task tools', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_read',
                'name': 'Read',
                'input': {'file_path': '/test.dart'},
              },
            ],
          },
        });

        check(chat.data.subagentConversations).isEmpty();
        check(chat.activeAgents).isEmpty();
      });
    });

    group('result messages - agent completion', () {
      test('updates agent status to completed on success', () {
        // First spawn a subagent
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_agent_result',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        check(chat.activeAgents['toolu_agent_result']!.status).equals(
          AgentStatus.working,
        );

        // Then send result message
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'parent_tool_use_id': 'toolu_agent_result',
          'usage': {'input_tokens': 100, 'output_tokens': 50},
          'totalCostUsd': 0.01,
        });

        final agent = chat.activeAgents['toolu_agent_result'];
        check(agent).isNotNull();
        check(agent!.status).equals(AgentStatus.completed);
      });

      test('updates agent status to error on error_max_turns', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_error_max',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'error_max_turns',
          'parent_tool_use_id': 'toolu_error_max',
        });

        check(chat.activeAgents['toolu_error_max']!.status).equals(
          AgentStatus.error,
        );
      });

      test('updates agent status to error on error_tool', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_error_tool',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'error_tool',
          'parent_tool_use_id': 'toolu_error_tool',
        });

        check(chat.activeAgents['toolu_error_tool']!.status).equals(
          AgentStatus.error,
        );
      });

      test('updates agent status to error on error_api', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_error_api',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'error_api',
          'parent_tool_use_id': 'toolu_error_api',
        });

        check(chat.activeAgents['toolu_error_api']!.status).equals(
          AgentStatus.error,
        );
      });

      test('updates agent status to error on error_budget', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_error_budget',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'error_budget',
          'parent_tool_use_id': 'toolu_error_budget',
        });

        check(chat.activeAgents['toolu_error_budget']!.status).equals(
          AgentStatus.error,
        );
      });

      test('defaults to completed for unknown result subtype', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_unknown_result',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'unknown_subtype',
          'parent_tool_use_id': 'toolu_unknown_result',
        });

        check(chat.activeAgents['toolu_unknown_result']!.status).equals(
          AgentStatus.completed,
        );
      });

      test('ignores result message without parent_tool_use_id when assistant output exists',
          () {
        // First, send an assistant message (which sets _hasAssistantOutputThisTurn)
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Hello'},
            ],
          },
        });

        // Then send the result message
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'result': 'Success',
          'usage': {'input_tokens': 100, 'output_tokens': 50},
          'totalCostUsd': 0.01,
        });

        // Only the text entry should exist, not a SystemNotificationEntry
        check(chat.data.primaryConversation.entries.length).equals(1);
        check(chat.data.primaryConversation.entries.first)
            .isA<TextOutputEntry>();
      });

      test(
          'creates SystemNotificationEntry when result has message but no assistant output',
          () {
        // Send a result message without any prior assistant message
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'result': 'Unknown skill: clear',
          'usage': {'input_tokens': 0, 'output_tokens': 0},
        });

        // Should create a SystemNotificationEntry
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<SystemNotificationEntry>();
        check((entries.first as SystemNotificationEntry).message)
            .equals('Unknown skill: clear');
      });

      test('does not create SystemNotificationEntry when result is empty', () {
        // Send a result message with empty result string
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'result': '',
          'usage': {'input_tokens': 0, 'output_tokens': 0},
        });

        // No entries should be created
        check(chat.data.primaryConversation.entries).isEmpty();
      });

      test('does not create SystemNotificationEntry when result is null', () {
        // Send a result message without result field
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'usage': {'input_tokens': 0, 'output_tokens': 0},
        });

        // No entries should be created
        check(chat.data.primaryConversation.entries).isEmpty();
      });

      test('resets assistant output flag between turns', () {
        // First turn: assistant message + result
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Hello'},
            ],
          },
        });
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'result': 'Turn 1 done',
        });

        // Second turn: no assistant message, just result
        handler.handleMessage(chat, {
          'type': 'result',
          'subtype': 'success',
          'result': 'Unknown command',
        });

        // Should have: 1 text entry + 1 system notification entry
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(2);
        check(entries[0]).isA<TextOutputEntry>();
        check(entries[1]).isA<SystemNotificationEntry>();
        check((entries[1] as SystemNotificationEntry).message)
            .equals('Unknown command');
      });
    });

    group('conversation routing', () {
      test('routes messages without parentToolUseId to primary conversation',
          () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Main conversation message'},
            ],
          },
        });

        check(chat.data.primaryConversation.entries.length).equals(1);
      });

      test('routes subagent messages to correct conversation', () {
        // First spawn a subagent
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_agent_001',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Explore'},
              },
            ],
          },
        });

        final agent = chat.activeAgents['toolu_agent_001']!;
        final subConv = chat.data.subagentConversations[agent.conversationId]!;
        check(subConv.entries).isEmpty();

        // Now send a message from that subagent
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': 'toolu_agent_001',
          'message': {
            'content': [
              {'type': 'text', 'text': 'I found these files...'},
            ],
          },
        });

        // The message should appear in the subagent conversation
        final updatedSubConv =
            chat.data.subagentConversations[agent.conversationId]!;
        check(updatedSubConv.entries.length).equals(1);
        check((updatedSubConv.entries.first as TextOutputEntry).text).equals(
          'I found these files...',
        );

        // Primary conversation should still just have the Task tool
        check(chat.data.primaryConversation.entries.length).equals(1);
        check(chat.data.primaryConversation.entries.first)
            .isA<ToolUseOutputEntry>();
      });

      test('routes to primary if parentToolUseId not found', () {
        // Send message with unknown parent - should fall back to primary
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': 'unknown_agent',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Orphaned message'},
            ],
          },
        });

        check(chat.data.primaryConversation.entries.length).equals(1);
        check(chat.data.subagentConversations).isEmpty();
      });
    });

    group('clear() method', () {
      test('clears tool pairing state', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_clear',
                'name': 'Read',
                'input': {},
              },
            ],
          },
        });

        handler.clear();

        // Now a tool_result for that ID should not find the entry
        handler.handleMessage(chat, {
          'type': 'user',
          'message': {
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'toolu_clear',
                'content': 'Result',
              },
            ],
          },
        });

        // The tool entry should NOT be updated (pairing state was cleared)
        final entries = chat.data.primaryConversation.entries;
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.result).isNull();
      });

      test('clears agent routing state', () {
        // Spawn a subagent
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_agent_clear',
                'name': 'Task',
                'input': {'subagent_type': 'Explore', 'description': 'Search'},
              },
            ],
          },
        });

        handler.clear();

        // Now a message from that agent should go to primary
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': 'toolu_agent_clear',
          'message': {
            'content': [
              {'type': 'text', 'text': 'Message after clear'},
            ],
          },
        });

        // Message went to primary (2 entries: Task tool + text)
        check(chat.data.primaryConversation.entries.length).equals(2);
        // The subagent conversation should still exist but be empty
        check(chat.data.subagentConversations).isNotEmpty();
        check(chat.data.subagentConversations.values.first.entries).isEmpty();
      });
    });

    group('stream_event handling', () {
      /// Sends a message_start stream event.
      void sendMessageStart({String? parentToolUseId}) {
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'parent_tool_use_id': parentToolUseId,
          'event': {
            'type': 'message_start',
            'message': {'role': 'assistant'},
          },
        });
      }

      /// Sends a content_block_start stream event.
      void sendContentBlockStart(
        int index,
        Map<String, dynamic> contentBlock,
      ) {
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'event': {
            'type': 'content_block_start',
            'index': index,
            'content_block': contentBlock,
          },
        });
      }

      /// Sends a content_block_delta stream event.
      void sendContentBlockDelta(
        int index,
        Map<String, dynamic> delta,
      ) {
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'index': index,
            'delta': delta,
          },
        });
      }

      /// Sends a content_block_stop stream event.
      void sendContentBlockStop(int index) {
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'event': {
            'type': 'content_block_stop',
            'index': index,
          },
        });
      }

      /// Sends a message_stop stream event.
      void sendMessageStop() {
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'event': {'type': 'message_stop'},
        });
      }

      test('content_block_start creates streaming TextOutputEntry', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('');
        check(textEntry.isStreaming).isTrue();
        check(textEntry.contentType).equals('text');
      });

      test('content_block_delta appends text via appendDelta', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'Hello'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': ', world'});

        final entries = chat.data.primaryConversation.entries;
        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Hello, world');
      });

      test('content_block_stop marks entry as not streaming', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'Done'});
        sendContentBlockStop(0);

        final textEntry =
            chat.data.primaryConversation.entries.first as TextOutputEntry;
        check(textEntry.isStreaming).isFalse();
        check(textEntry.text).equals('Done');
      });

      test('assistant message finalizes streaming entry without duplication',
          () {
        // Stream a complete message
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'Streamed'});
        sendContentBlockStop(0);
        sendMessageStop();

        // Now send the final assistant message
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': null,
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Streamed text final'},
            ],
          },
        });

        // Should have exactly 1 entry (no duplicate)
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);

        final textEntry = entries.first as TextOutputEntry;
        // Text should be the authoritative final value
        check(textEntry.text).equals('Streamed text final');
        check(textEntry.isStreaming).isFalse();
      });

      test('thinking_delta creates thinking TextOutputEntry', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'thinking'});
        sendContentBlockDelta(
            0, {'type': 'thinking_delta', 'thinking': 'Hmm...'});
        sendContentBlockDelta(
            0, {'type': 'thinking_delta', 'thinking': ' let me think'});

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);

        final thinkingEntry = entries.first as TextOutputEntry;
        check(thinkingEntry.contentType).equals('thinking');
        check(thinkingEntry.text).equals('Hmm... let me think');
        check(thinkingEntry.isStreaming).isTrue();
      });

      test('tool_use content_block_start creates ToolUseOutputEntry', () {
        sendMessageStart();
        sendContentBlockStart(0, {
          'type': 'tool_use',
          'id': 'tool_123',
          'name': 'Read',
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ToolUseOutputEntry>();

        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.toolName).equals('Read');
        check(toolEntry.toolUseId).equals('tool_123');
        check(toolEntry.isStreaming).isTrue();
      });

      test('input_json_delta accumulates on ToolUseOutputEntry', () {
        sendMessageStart();
        sendContentBlockStart(0, {
          'type': 'tool_use',
          'id': 'tool_456',
          'name': 'Bash',
        });
        sendContentBlockDelta(
            0, {'type': 'input_json_delta', 'partial_json': '{"com'});
        sendContentBlockDelta(
            0, {'type': 'input_json_delta', 'partial_json': 'mand":'});
        sendContentBlockStop(0);

        final toolEntry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(toolEntry.isStreaming).isFalse();
      });

      test('multiple content blocks create separate entries', () {
        sendMessageStart();
        // Thinking block
        sendContentBlockStart(0, {'type': 'thinking'});
        sendContentBlockDelta(
            0, {'type': 'thinking_delta', 'thinking': 'Thinking...'});
        sendContentBlockStop(0);
        // Text block
        sendContentBlockStart(1, {'type': 'text'});
        sendContentBlockDelta(1, {'type': 'text_delta', 'text': 'Answer'});
        sendContentBlockStop(1);
        sendMessageStop();

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(2);
        check((entries[0] as TextOutputEntry).contentType).equals('thinking');
        check((entries[0] as TextOutputEntry).text).equals('Thinking...');
        check((entries[1] as TextOutputEntry).contentType).equals('text');
        check((entries[1] as TextOutputEntry).text).equals('Answer');
      });

      test('message_stop clears streaming state', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'First'});
        sendContentBlockStop(0);
        sendMessageStop();

        // Start a second message - should work independently
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'Second'});
        sendContentBlockStop(0);
        sendMessageStop();

        // Both messages create entries, finalized by their assistant messages
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(2);
      });

      test('clearStreamingState finalizes in-flight entries', () {
        sendMessageStart();
        sendContentBlockStart(0, {'type': 'text'});
        sendContentBlockDelta(0, {'type': 'text_delta', 'text': 'Partial'});

        // Entry should still be streaming
        var textEntry =
            chat.data.primaryConversation.entries.first as TextOutputEntry;
        check(textEntry.isStreaming).isTrue();

        // Clear streaming state (simulates interrupt)
        handler.clearStreamingState();

        // Entry should now be finalized
        textEntry =
            chat.data.primaryConversation.entries.first as TextOutputEntry;
        check(textEntry.isStreaming).isFalse();
        check(textEntry.text).equals('Partial');
      });

      test('subagent stream events route to correct conversation', () {
        // First create a subagent via non-streaming Task tool
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': null,
          'message': {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'task_001',
                'name': 'Task',
                'input': {
                  'subagent_type': 'Explore',
                  'description': 'Test agent',
                  'prompt': 'Do something',
                },
              },
            ],
          },
        });

        // Now stream events for the subagent
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'parent_tool_use_id': 'task_001',
          'event': {
            'type': 'message_start',
            'message': {'role': 'assistant'},
          },
        });
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'parent_tool_use_id': 'task_001',
          'event': {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {'type': 'text'},
          },
        });
        handler.handleMessage(chat, {
          'type': 'stream_event',
          'parent_tool_use_id': 'task_001',
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': 'Subagent reply'},
          },
        });

        // Primary conversation should only have the Task tool entry
        final primaryEntries = chat.data.primaryConversation.entries;
        check(primaryEntries.length).equals(1);
        check(primaryEntries.first).isA<ToolUseOutputEntry>();

        // Subagent conversation should have the streaming text entry
        final subConversations = chat.data.subagentConversations;
        check(subConversations).isNotEmpty();
        final subEntries = subConversations.values.first.entries;
        check(subEntries.length).equals(1);
        check(subEntries.first).isA<TextOutputEntry>();
        check((subEntries.first as TextOutputEntry).text)
            .equals('Subagent reply');
      });

      test('assistant message with no streaming entries creates normally', () {
        // Send an assistant message without any preceding stream events
        handler.handleMessage(chat, {
          'type': 'assistant',
          'parent_tool_use_id': null,
          'message': {
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': 'Direct response'},
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check((entries.first as TextOutputEntry).text)
            .equals('Direct response');
      });
    });

    group('edge cases', () {
      test('handles unknown message type by creating UnknownMessageEntry', () {
        handler.handleMessage(chat, {
          'type': 'unknown_type',
          'data': 'some data',
        });

        // Unknown types create an UnknownMessageEntry for debugging
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<UnknownMessageEntry>();

        final unknownEntry = entries.first as UnknownMessageEntry;
        check(unknownEntry.messageType).equals('unknown_type');
        check(unknownEntry.rawMessage['data']).equals('some data');
      });

      test('handles null message type by creating UnknownMessageEntry', () {
        handler.handleMessage(chat, {'data': 'no type field'});

        // Null type creates an UnknownMessageEntry with 'null' as type
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<UnknownMessageEntry>();

        final unknownEntry = entries.first as UnknownMessageEntry;
        check(unknownEntry.messageType).equals('null');
      });

      test('handles malformed tool_use input gracefully', () {
        handler.handleMessage(chat, {
          'type': 'assistant',
          'message': {
            'content': [
              {
                'type': 'tool_use',
                'id': 'toolu_malformed',
                'name': 'Read',
                'input': 'not a map', // Invalid input type
              },
            ],
          },
        });

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.toolInput).isEmpty();
      });
    });
  });

  group('auto-naming feature', () {
    late ChatState chat;
    late MockAskAiService mockAskAi;
    late SdkMessageHandler handler;

    setUp(() {
      mockAskAi = MockAskAiService();
      handler = SdkMessageHandler(askAiService: mockAskAi);
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    test('generates title when generateChatTitle is called', () async {
      chat = ChatState.create(
        name: 'Initial placeholder name...',
        worktreeRoot: '/tmp/test',
      );

      mockAskAi.titleToReturn = 'Fix Authentication Bug';

      // Call generateChatTitle directly (as conversation_panel does)
      handler.generateChatTitle(chat, 'Help me fix a bug in my authentication code');

      // Wait for async title generation
      await Future<void>.delayed(const Duration(milliseconds: 50));

      check(chat.data.name).equals('Fix Authentication Bug');
      check(chat.isAutoGeneratedName).isFalse();
    });

    test('does not generate title twice for the same chat', () async {
      chat = ChatState.create(
        name: 'My Chat Name',
        worktreeRoot: '/tmp/test',
      );

      mockAskAi.titleToReturn = 'First Title';

      // First call triggers title generation
      handler.generateChatTitle(chat, 'Some user message');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Title should be generated
      check(chat.data.name).equals('First Title');

      // Now try again - should not generate a new title
      mockAskAi.titleToReturn = 'Second Title';
      mockAskAi.lastPrompt = null; // Reset to check if it's called

      handler.generateChatTitle(chat, 'Another message');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Name should remain as first generated title
      check(chat.data.name).equals('First Title');
      check(mockAskAi.lastPrompt).isNull();
    });

    test('does not generate title for empty message', () async {
      chat = ChatState.create(
        name: 'Placeholder...',
        worktreeRoot: '/tmp/test',
      );

      mockAskAi.titleToReturn = 'Should Not Be Used';

      handler.generateChatTitle(chat, '');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Name should remain unchanged
      check(chat.data.name).equals('Placeholder...');
      check(mockAskAi.lastPrompt).isNull();
    });

    test('handles title generation failure gracefully', () async {
      chat = ChatState.create(
        name: 'Placeholder...',
        worktreeRoot: '/tmp/test',
      );

      mockAskAi.shouldFail = true;

      handler.generateChatTitle(chat, 'Some message');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Name should remain unchanged on failure
      check(chat.data.name).equals('Placeholder...');
    });

    test('only generates title once even with rapid calls', () async {
      chat = ChatState.create(
        name: 'Placeholder...',
        worktreeRoot: '/tmp/test',
      );

      mockAskAi.titleToReturn = 'Generated Title';

      // Call multiple times quickly
      handler.generateChatTitle(chat, 'First message');
      handler.generateChatTitle(chat, 'Second message');
      handler.generateChatTitle(chat, 'Third message');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Title should be generated only once
      check(chat.data.name).equals('Generated Title');
      check(chat.isAutoGeneratedName).isFalse();
    });

    test('extracts title from ==== markers correctly', () async {
      chat = ChatState.create(
        name: 'Placeholder...',
        worktreeRoot: '/tmp/test',
      );

      // The mock returns the title wrapped in markers
      mockAskAi.titleToReturn = 'Add Dark Mode';

      handler.generateChatTitle(chat, 'Add dark mode support');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      check(chat.data.name).equals('Add Dark Mode');
    });

    test('works without AskAiService (no-op)', () async {
      final handlerWithoutAi = SdkMessageHandler();
      chat = ChatState.create(
        name: 'Placeholder...',
        worktreeRoot: '/tmp/test',
      );

      handlerWithoutAi.generateChatTitle(chat, 'Some message');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Name should remain unchanged
      check(chat.data.name).equals('Placeholder...');

      handlerWithoutAi.dispose();
    });
  });

  group('OutputEntry mutability', () {
    test('TextOutputEntry supports streaming mutations', () {
      final entry = TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'text',
        isStreaming: true,
      );

      entry.appendDelta('Hello');
      check(entry.text).equals('Hello');

      entry.appendDelta(' world');
      check(entry.text).equals('Hello world');

      entry.isStreaming = false;
      check(entry.isStreaming).isFalse();
    });

    test('ToolUseOutputEntry supports result updates', () {
      final entry = ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: 'Read',
        toolUseId: 'toolu_test',
        toolInput: {'file_path': '/test.dart'},
      );

      check(entry.result).isNull();
      check(entry.isError).isFalse();

      entry.updateResult({'content': 'file contents'}, false);
      check(entry.result).isNotNull();
      check(entry.isError).isFalse();

      entry.updateResult('Error message', true);
      check(entry.result).equals('Error message');
      check(entry.isError).isTrue();
    });
  });
}

/// Creates a mock [sdk.PermissionRequest] for testing.
///
/// This is a helper function that creates a real [sdk.PermissionRequest] with
/// the specified [toolUseId]. The completer is used internally and doesn't
/// need to be completed for testing purposes.
sdk.PermissionRequest _MockPermissionRequest(String toolUseId) {
  return sdk.PermissionRequest(
    id: 'mock_callback_$toolUseId',
    sessionId: 'mock_session',
    toolName: 'MockTool',
    toolInput: const <String, dynamic>{},
    toolUseId: toolUseId,
    completer: Completer<sdk.PermissionResponse>(),
  );
}
