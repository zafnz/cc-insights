import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:codex_sdk/codex_sdk.dart';
import 'package:test/test.dart';

/// Tests for Codex → InsightsEvent conversion (Task 3c).
///
/// Verifies that CodexSession correctly emits InsightsEvents when processing
/// Codex JSON-RPC notifications and server requests.
void main() {
  group('CodexSession InsightsEvent emission', () {
    late CodexSession session;
    late List<InsightsEvent> capturedEvents;
    late StreamSubscription<InsightsEvent> eventSub;

    setUp(() {
      session = CodexSession.forTesting(threadId: 'test-thread');
      capturedEvents = [];
      eventSub = session.events.listen((event) => capturedEvents.add(event));
    });

    tearDown(() async {
      await eventSub.cancel();
      await session.kill();
    });

    /// Helper to wait for events to be processed
    Future<void> waitForEvents() async {
      await Future.delayed(Duration(milliseconds: 10));
    }

    group('SessionInitEvent', () {
      test('emits SessionInitEvent on thread/started', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'thread/started',
          params: {
            'thread': {
              'id': 'test-thread',
              'model': 'o4-mini',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as SessionInitEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.sessionId, 'test-thread');
        expect(event.model, 'o4-mini');
        expect(event.id.startsWith('evt-codex-'), isTrue);
        expect(event.raw, isNotNull);
      });

      test('ignores thread/started with wrong threadId', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'thread/started',
          params: {
            'thread': {
              'id': 'different-thread',
              'model': 'o4-mini',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });
    });

    group('ToolInvocationEvent', () {
      test('emits ToolInvocationEvent for commandExecution started', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-001',
              'type': 'commandExecution',
              'command': 'npm test',
              'cwd': '/Users/zaf/project',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.callId, 'item-001');
        expect(event.sessionId, 'test-thread');
        expect(event.kind, ToolKind.execute);
        expect(event.toolName, 'Bash');
        expect(event.input['command'], 'npm test');
        expect(event.input['cwd'], '/Users/zaf/project');
        expect(event.locations, isNull);
        expect(event.extensions?['codex.itemType'], 'commandExecution');
      });

      test('emits ToolInvocationEvent for fileChange started', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'fileChange',
              'changes': [
                {'path': '/project/src/main.dart', 'diff': '--- a/...\n+++ b/...'},
                {'path': '/project/src/utils.dart', 'diff': '--- a/...\n+++ b/...'},
              ],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.callId, 'item-002');
        expect(event.kind, ToolKind.edit);
        expect(event.toolName, 'FileChange');
        expect(event.locations, ['/project/src/main.dart', '/project/src/utils.dart']);
        expect(event.extensions?['codex.itemType'], 'fileChange');
      });

      test('emits ToolInvocationEvent for mcpToolCall started', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-003',
              'type': 'mcpToolCall',
              'server': 'flutter-test',
              'tool': 'run_tests',
              'arguments': {'project_path': '/project'},
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.callId, 'item-003');
        expect(event.kind, ToolKind.mcp);
        expect(event.toolName, 'mcp__flutter-test__run_tests');
        expect(event.input['server'], 'flutter-test');
        expect(event.input['tool'], 'run_tests');
        expect(event.input['arguments'], {'project_path': '/project'});
        expect(event.extensions?['codex.itemType'], 'mcpToolCall');
      });

      test('mcpToolCall with missing server/tool falls back to McpTool', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-004',
              'type': 'mcpToolCall',
              'arguments': {},
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.toolName, 'McpTool');
      });

      test('ignores item/started with wrong threadId', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'wrong-thread',
            'item': {
              'id': 'item-001',
              'type': 'commandExecution',
              'command': 'ls',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });

      test('ignores item/started with unknown type', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-999',
              'type': 'unknownType',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });
    });

    group('TextEvent', () {
      test('emits TextEvent for agentMessage completed', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-004',
              'type': 'agentMessage',
              'text': 'Here is what I found...',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TextEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.sessionId, 'test-thread');
        expect(event.text, 'Here is what I found...');
        expect(event.kind, TextKind.text);
      });

      test('emits TextEvent for reasoning completed with summary', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-005',
              'type': 'reasoning',
              'summary': ['Analyzing the code structure...', 'Checking patterns...'],
              'content': ['Let me think about this...'],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TextEvent;
        expect(event.kind, TextKind.thinking);
        expect(event.text, 'Analyzing the code structure...\nChecking patterns...');
      });

      test('emits TextEvent for reasoning completed with content fallback', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-006',
              'type': 'reasoning',
              'summary': [],
              'content': ['Thinking deeply...'],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TextEvent;
        expect(event.kind, TextKind.thinking);
        expect(event.text, 'Thinking deeply...');
      });

      test('does not emit TextEvent for empty reasoning', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-007',
              'type': 'reasoning',
              'summary': [],
              'content': [],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });

      test('emits TextEvent for plan completed', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-008',
              'type': 'plan',
              'text': 'I will first read the file...',
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TextEvent;
        expect(event.kind, TextKind.plan);
        expect(event.text, 'I will first read the file...');
      });
    });

    group('ToolCompletionEvent', () {
      test('emits ToolCompletionEvent for successful commandExecution', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-001',
              'type': 'commandExecution',
              'aggregatedOutput': 'All tests passed\n',
              'exitCode': 0,
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.callId, 'item-001');
        expect(event.sessionId, 'test-thread');
        expect(event.status, ToolCallStatus.completed);
        expect(event.isError, isFalse);
        expect(event.output['stdout'], 'All tests passed\n');
        expect(event.output['exit_code'], 0);
      });

      test('emits ToolCompletionEvent for failed commandExecution', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-001',
              'type': 'commandExecution',
              'aggregatedOutput': 'Error: command failed\n',
              'exitCode': 1,
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.status, ToolCallStatus.failed);
        expect(event.isError, isTrue);
        expect(event.output['exit_code'], 1);
      });

      test('emits ToolCompletionEvent for successful fileChange', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'fileChange',
              'status': 'completed',
              'changes': [
                {'path': '/project/src/main.dart', 'diff': '--- a/...\n+++ b/...'},
              ],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.callId, 'item-002');
        expect(event.status, ToolCallStatus.completed);
        expect(event.isError, isFalse);
        expect(event.locations, ['/project/src/main.dart']);
      });

      test('emits ToolCompletionEvent for failed fileChange', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'fileChange',
              'status': 'failed',
              'changes': [],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.status, ToolCallStatus.failed);
        expect(event.isError, isTrue);
      });

      test('emits ToolCompletionEvent for successful mcpToolCall', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-003',
              'type': 'mcpToolCall',
              'result': {'summary': '5 tests passed'},
              'error': null,
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.callId, 'item-003');
        expect(event.status, ToolCallStatus.completed);
        expect(event.isError, isFalse);
        expect(event.output['summary'], '5 tests passed');
      });

      test('emits ToolCompletionEvent for failed mcpToolCall', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-003',
              'type': 'mcpToolCall',
              'result': null,
              'error': {'message': 'Tool execution failed'},
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolCompletionEvent;
        expect(event.status, ToolCallStatus.failed);
        expect(event.isError, isTrue);
        expect(event.output['message'], 'Tool execution failed');
      });
    });

    group('TurnCompleteEvent', () {
      test('emits TurnCompleteEvent with token usage', () async {
        // First, update token usage
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 5000,
                'outputTokens': 1500,
                'cachedInputTokens': 3000,
              },
            },
          },
        ));

        // Then complete the turn
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TurnCompleteEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.sessionId, 'test-thread');
        expect(event.isError, isFalse);
        expect(event.subtype, 'success');
        expect(event.usage?.inputTokens, 5000);
        expect(event.usage?.outputTokens, 1500);
        expect(event.usage?.cacheReadTokens, 3000);
      });

      test('emits TurnCompleteEvent with zero cache when cachedInputTokens is 0', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 1000,
                'outputTokens': 500,
                'cachedInputTokens': 0,
              },
            },
          },
        ));

        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TurnCompleteEvent;
        expect(event.usage?.inputTokens, 1000);
        expect(event.usage?.outputTokens, 500);
        expect(event.usage?.cacheReadTokens, isNull);
      });

      test('emits TurnCompleteEvent without prior token usage', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TurnCompleteEvent;
        expect(event.usage?.inputTokens, 0);
        expect(event.usage?.outputTokens, 0);
        expect(event.usage?.cacheReadTokens, isNull);
      });

      test('emits TurnCompleteEvent with modelUsage when modelContextWindow is present', () async {
        // First, update token usage with modelContextWindow (sibling of total)
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 5000,
                'outputTokens': 1500,
                'cachedInputTokens': 3000,
              },
              'modelContextWindow': 258400,
            },
          },
        ));

        // Then complete the turn
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TurnCompleteEvent;
        expect(event.modelUsage, isNotNull);
        expect(event.modelUsage, hasLength(1));
        expect(event.modelUsage?.values.first.contextWindow, 258400);
      });

      test('emits TurnCompleteEvent without modelUsage when no modelContextWindow', () async {
        // Update token usage WITHOUT modelContextWindow
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 5000,
                'outputTokens': 1500,
                'cachedInputTokens': 3000,
              },
            },
          },
        ));

        // Complete the turn
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as TurnCompleteEvent;
        expect(event.modelUsage, isNull);
      });

      test('uses model name from thread/started as modelUsage key', () async {
        // First, start thread with specific model
        session.injectNotification(JsonRpcNotification(
          method: 'thread/started',
          params: {
            'thread': {
              'id': 'test-thread',
              'model': 'gpt-5.2-codex',
            },
          },
        ));

        // Then update token usage with modelContextWindow (sibling of total)
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 2000,
                'outputTokens': 800,
              },
              'modelContextWindow': 128000,
            },
          },
        ));

        // Complete the turn
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {
            'threadId': 'test-thread',
          },
        ));
        await waitForEvents();
        // Filter out the SessionInitEvent from thread/started
        final turnCompleteEvents = capturedEvents.whereType<TurnCompleteEvent>().toList();
        expect(turnCompleteEvents, hasLength(1));
        final event = turnCompleteEvents.first;
        expect(event.modelUsage, isNotNull);
        expect(event.modelUsage?.containsKey('gpt-5.2-codex'), isTrue);
        expect(event.modelUsage?['gpt-5.2-codex']?.contextWindow, 128000);
      });
    });

    group('PermissionRequestEvent', () {
      test('emits PermissionRequestEvent for commandExecution approval', () async {
        session.injectServerRequest(JsonRpcServerRequest(
          id: 42,
          method: 'item/commandExecution/requestApproval',
          params: {
            'threadId': 'test-thread',
            'command': 'rm -rf node_modules',
            'cwd': '/Users/zaf/project',
            'itemId': 'item-010',
            'commandActions': ['allow', 'deny'],
            'reason': 'This command modifies the filesystem',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as PermissionRequestEvent;
        expect(event.provider, BackendProvider.codex);
        expect(event.sessionId, 'test-thread');
        expect(event.requestId, '42');
        expect(event.toolName, 'Bash');
        expect(event.toolKind, ToolKind.execute);
        expect(event.toolInput['command'], 'rm -rf node_modules');
        expect(event.toolInput['cwd'], '/Users/zaf/project');
        expect(event.toolUseId, 'item-010');
        expect(event.reason, 'This command modifies the filesystem');
        expect(event.extensions?['codex.commandActions'], ['allow', 'deny']);
      });

      test('emits PermissionRequestEvent for fileChange approval', () async {
        session.injectServerRequest(JsonRpcServerRequest(
          id: 43,
          method: 'item/fileChange/requestApproval',
          params: {
            'threadId': 'test-thread',
            'grantRoot': '/Users/zaf/project/src',
            'itemId': 'item-011',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as PermissionRequestEvent;
        expect(event.requestId, '43');
        expect(event.toolName, 'Write');
        expect(event.toolKind, ToolKind.edit);
        expect(event.toolInput['file_path'], '/Users/zaf/project/src');
        expect(event.toolUseId, 'item-011');
        expect(event.extensions?['codex.grantRoot'], '/Users/zaf/project/src');
      });

      test('emits PermissionRequestEvent for user input request', () async {
        session.injectServerRequest(JsonRpcServerRequest(
          id: 44,
          method: 'item/tool/requestUserInput',
          params: {
            'threadId': 'test-thread',
            'questions': [
              {
                'text': 'Which database?',
                'options': ['PostgreSQL', 'SQLite']
              }
            ],
            'itemId': 'item-012',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as PermissionRequestEvent;
        expect(event.requestId, '44');
        expect(event.toolName, 'AskUserQuestion');
        expect(event.toolKind, ToolKind.ask);
        expect(event.toolInput['questions'], hasLength(1));
        expect(event.toolUseId, 'item-012');
      });

      test('ignores permission request with wrong threadId', () async {
        session.injectServerRequest(JsonRpcServerRequest(
          id: 45,
          method: 'item/commandExecution/requestApproval',
          params: {
            'threadId': 'wrong-thread',
            'command': 'ls',
            'itemId': 'item-013',
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });
    });

    group('Event ID generation', () {
      test('generates unique event IDs', () async {
        // Emit multiple events
        session.injectNotification(JsonRpcNotification(
          method: 'thread/started',
          params: {
            'thread': {'id': 'test-thread', 'model': 'o4-mini'},
          },
        ));

        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-001',
              'type': 'agentMessage',
              'text': 'Hello',
            },
          },
        ));

        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {'threadId': 'test-thread'},
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(3));
        final ids = capturedEvents.map((e) => e.id).toSet();
        expect(ids, hasLength(3), reason: 'All event IDs should be unique');

        // All should start with evt-codex-
        for (final id in ids) {
          expect(id.startsWith('evt-codex-'), isTrue);
        }
      });
    });

    group('Edge cases', () {
      test('handles null item in item/started', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': null,
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });

      test('handles null item in item/completed', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': null,
          },
        ));
        await waitForEvents();
        expect(capturedEvents, isEmpty);
      });

      test('handles missing fields gracefully', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'type': 'commandExecution',
              // Missing 'id', 'command', 'cwd'
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.callId, '');
        expect(event.input['command'], '');
        expect(event.input['cwd'], '');
      });

      test('handles empty fileChange changes array', () async {
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'fileChange',
              'changes': [],
            },
          },
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first as ToolInvocationEvent;
        expect(event.locations, isNull);
      });

      test('preserves raw params in all events', () async {
        final params = {
          'threadId': 'test-thread',
          'item': {
            'id': 'item-001',
            'type': 'agentMessage',
            'text': 'Test',
          },
        };

        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: params,
        ));
        await waitForEvents();
        expect(capturedEvents, hasLength(1));
        final event = capturedEvents.first;
        expect(event.raw, equals(params));
      });
    });

    group('Complete workflow', () {
      test('emits events for a complete turn workflow', () async {
        // 1. Thread started
        session.injectNotification(JsonRpcNotification(
          method: 'thread/started',
          params: {
            'thread': {'id': 'test-thread', 'model': 'o4-mini'},
          },
        ));

        // 2. Turn started (no event emitted)
        session.injectNotification(JsonRpcNotification(
          method: 'turn/started',
          params: {
            'threadId': 'test-thread',
            'turn': {'id': 'turn-001'},
          },
        ));

        // 3. Agent message
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-001',
              'type': 'agentMessage',
              'text': 'Let me run the tests',
            },
          },
        ));

        // 4. Command execution started
        session.injectNotification(JsonRpcNotification(
          method: 'item/started',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'commandExecution',
              'command': 'npm test',
              'cwd': '/project',
            },
          },
        ));

        // 5. Command execution completed
        session.injectNotification(JsonRpcNotification(
          method: 'item/completed',
          params: {
            'threadId': 'test-thread',
            'item': {
              'id': 'item-002',
              'type': 'commandExecution',
              'aggregatedOutput': 'All tests passed',
              'exitCode': 0,
            },
          },
        ));

        // 6. Token usage updated
        session.injectNotification(JsonRpcNotification(
          method: 'thread/tokenUsage/updated',
          params: {
            'threadId': 'test-thread',
            'tokenUsage': {
              'total': {
                'inputTokens': 1000,
                'outputTokens': 500,
                'cachedInputTokens': 0,
              },
            },
          },
        ));

        // 7. Turn completed
        session.injectNotification(JsonRpcNotification(
          method: 'turn/completed',
          params: {'threadId': 'test-thread'},
        ));

        // Verify events
        await waitForEvents();
        expect(capturedEvents, hasLength(5));
        expect(capturedEvents[0], isA<SessionInitEvent>());
        expect(capturedEvents[1], isA<TextEvent>());
        expect((capturedEvents[1] as TextEvent).kind, TextKind.text);
        expect(capturedEvents[2], isA<ToolInvocationEvent>());
        expect((capturedEvents[2] as ToolInvocationEvent).toolName, 'Bash');
        expect(capturedEvents[3], isA<ToolCompletionEvent>());
        expect((capturedEvents[3] as ToolCompletionEvent).isError, isFalse);
        expect(capturedEvents[4], isA<TurnCompleteEvent>());
        expect((capturedEvents[4] as TurnCompleteEvent).usage?.inputTokens, 1000);
      });
    });
  });
}
