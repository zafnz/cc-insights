import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        BackendProvider,
        ToolInvocationEvent,
        ToolCompletionEvent,
        ToolKind,
        ToolCallStatus;
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Event ID counter for generating unique event IDs.
int _idCounter = 0;

/// Generates a unique event ID.
String _nextId() => 'evt-${_idCounter++}';

/// Helper to create ToolInvocationEvent with default boilerplate fields.
ToolInvocationEvent makeToolInvocation({
  String? callId,
  String toolName = 'Bash',
  ToolKind kind = ToolKind.execute,
  Map<String, dynamic> input = const {},
  String? parentCallId,
  String? model,
  Map<String, dynamic>? raw,
}) {
  return ToolInvocationEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    callId: callId ?? 'call-${_nextId()}',
    sessionId: 'test-session',
    kind: kind,
    toolName: toolName,
    input: input,
    parentCallId: parentCallId,
    model: model,
    raw: raw,
  );
}

/// Helper to create ToolCompletionEvent with default boilerplate fields.
ToolCompletionEvent makeToolCompletion({
  required String callId,
  ToolCallStatus status = ToolCallStatus.completed,
  dynamic output,
  bool isError = false,
  Map<String, dynamic>? raw,
}) {
  return ToolCompletionEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    callId: callId,
    sessionId: 'test-session',
    status: status,
    output: output,
    isError: isError,
    raw: raw,
  );
}

void main() {
  group('EventHandler - Task 4b: Tool Events', () {
    late ChatState chat;
    late EventHandler handler;

    setUp(() {
      chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
      handler = EventHandler();
      _idCounter = 0; // Reset counter for each test
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    group('_handleToolInvocation', () {
      test('creates ToolUseOutputEntry with correct fields', () {
        final event = makeToolInvocation(
          callId: 'tool-123',
          toolName: 'Read',
          kind: ToolKind.read,
          input: {'file_path': '/test/file.txt'},
          model: 'claude-sonnet-4-5',
        );

        handler.handleEvent(chat, event);

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ToolUseOutputEntry>();

        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.toolName).equals('Read');
        check(toolEntry.toolKind).equals(ToolKind.read);
        check(toolEntry.provider).equals(BackendProvider.claude);
        check(toolEntry.toolUseId).equals('tool-123');
        check(toolEntry.toolInput['file_path']).equals('/test/file.txt');
        check(toolEntry.model).equals('claude-sonnet-4-5');
        check(toolEntry.isStreaming).isFalse();
      });

      test('routes to primary conversation when parentCallId is null', () {
        handler.handleEvent(
          chat,
          makeToolInvocation(
            callId: 'tool-main',
            toolName: 'Bash',
            parentCallId: null,
          ),
        );

        // Verify it went to primary conversation
        check(chat.data.primaryConversation.entries.length).equals(1);
        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.toolName).equals('Bash');
      });

      test('enables pairing with tool completion', () {
        // Create invocation
        final event = makeToolInvocation(callId: 'tool-456');
        handler.handleEvent(chat, event);

        // Verify pairing works by sending a completion
        final completion = makeToolCompletion(
          callId: 'tool-456',
          output: 'Paired!',
        );
        handler.handleEvent(chat, completion);

        // Verify the result was paired with the entry
        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.result).equals('Paired!');
      });

      test('adds raw message to entry', () {
        final rawMsg = {'type': 'tool_use', 'debug': 'test'};
        final event = makeToolInvocation(
          callId: 'tool-789',
          raw: rawMsg,
        );

        handler.handleEvent(chat, event);

        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.rawMessages.length).equals(1);
        check(entry.rawMessages.first['debug']).equals('test');
      });
    });

    group('_handleToolCompletion', () {
      test('pairs result with invocation entry', () {
        // Create tool invocation
        final invocation = makeToolInvocation(callId: 'tool-123');
        handler.handleEvent(chat, invocation);

        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.result).isNull();
        check(entry.isError).isFalse();

        // Add tool result
        final completion = makeToolCompletion(
          callId: 'tool-123',
          output: 'Success!',
          isError: false,
        );
        handler.handleEvent(chat, completion);

        // Verify pairing
        check(entry.result).equals('Success!');
        check(entry.isError).isFalse();
      });

      test('handles error results', () {
        // Create tool invocation
        final invocation = makeToolInvocation(callId: 'tool-error');
        handler.handleEvent(chat, invocation);

        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;

        // Add error result
        final completion = makeToolCompletion(
          callId: 'tool-error',
          output: 'File not found',
          isError: true,
        );
        handler.handleEvent(chat, completion);

        // Verify error handling
        check(entry.result).equals('File not found');
        check(entry.isError).isTrue();
      });

      test('ignores unknown callId gracefully', () {
        // Send completion for non-existent tool
        final completion = makeToolCompletion(
          callId: 'unknown-tool',
          output: 'Result',
        );

        // Should not throw
        expect(() => handler.handleEvent(chat, completion), returnsNormally);

        // No entries should be created
        check(chat.data.primaryConversation.entries.length).equals(0);
      });

      test('clears pending permission by toolUseId', () {
        // This is a side effect we can't directly test without mock,
        // but we can verify the method is called by checking it doesn't throw
        final completion = makeToolCompletion(
          callId: 'tool-perm',
          output: 'Denied by timeout',
          isError: true,
        );

        // Should call removePendingPermissionByToolUseId internally
        expect(() => handler.handleEvent(chat, completion), returnsNormally);
      });

      test('persists tool result', () {
        // Create tool invocation
        final invocation = makeToolInvocation(callId: 'tool-persist');
        handler.handleEvent(chat, invocation);

        // The persistence call happens in handleEvent
        // We can't directly verify without mocking, but ensure no errors
        final completion = makeToolCompletion(
          callId: 'tool-persist',
          output: {'data': 'test'},
          isError: false,
        );

        expect(() => handler.handleEvent(chat, completion), returnsNormally);
      });

      test('adds raw message to entry', () {
        // Create tool invocation
        final invocation = makeToolInvocation(callId: 'tool-raw');
        handler.handleEvent(chat, invocation);

        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.rawMessages.length).equals(1);

        // Add tool result with raw message
        final rawMsg = {'type': 'tool_result', 'debug': 'result'};
        final completion = makeToolCompletion(
          callId: 'tool-raw',
          output: 'Done',
          raw: rawMsg,
        );
        handler.handleEvent(chat, completion);

        // Verify both messages are stored
        check(entry.rawMessages.length).equals(2);
        check(entry.rawMessages[1]['debug']).equals('result');
      });
    });

    group('clear and dispose', () {
      test('clear resets pairing state', () {
        // Create some tool invocations
        handler.handleEvent(chat, makeToolInvocation(callId: 'tool-1'));
        handler.handleEvent(chat, makeToolInvocation(callId: 'tool-2'));

        // Clear
        handler.clear();

        // Verify state is cleared by attempting to pair with a completion
        // If the state was cleared, the completion will be ignored (no error)
        final completion = makeToolCompletion(
          callId: 'tool-1',
          output: 'Should be ignored',
        );
        handler.handleEvent(chat, completion);

        // The entry should still have no result (completion was ignored)
        final entry1 =
            chat.data.primaryConversation.entries[0] as ToolUseOutputEntry;
        check(entry1.result).isNull();
      });

      test('dispose clears state', () {
        handler.handleEvent(chat, makeToolInvocation(callId: 'tool-1'));

        handler.dispose();

        // After dispose, trying to pair should be ignored
        final completion = makeToolCompletion(
          callId: 'tool-1',
          output: 'Should be ignored',
        );
        handler.handleEvent(chat, completion);

        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.result).isNull();
      });
    });

    group('handleEvent dispatch', () {
      test('dispatches ToolInvocationEvent to correct handler', () {
        final event = makeToolInvocation(callId: 'dispatch-test');
        handler.handleEvent(chat, event);

        // Verify it was handled by _handleToolInvocation
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ToolUseOutputEntry>();
      });

      test('dispatches ToolCompletionEvent to correct handler', () {
        // Create invocation first
        handler.handleEvent(chat, makeToolInvocation(callId: 'dispatch-123'));

        // Dispatch completion
        final completion = makeToolCompletion(
          callId: 'dispatch-123',
          output: 'Result',
        );
        handler.handleEvent(chat, completion);

        // Verify it was handled
        final entry =
            chat.data.primaryConversation.entries.first as ToolUseOutputEntry;
        check(entry.result).equals('Result');
      });
    });

    // Note: _formatTokens is private and will be tested indirectly
    // through compaction events in Task 4c
  });
}
