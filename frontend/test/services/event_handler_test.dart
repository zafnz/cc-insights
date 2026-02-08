import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        BackendProvider,
        ToolInvocationEvent,
        ToolCompletionEvent,
        TextEvent,
        UserInputEvent,
        TurnCompleteEvent,
        SessionInitEvent,
        SessionStatusEvent,
        ContextCompactionEvent,
        ToolKind,
        ToolCallStatus,
        TextKind,
        SessionStatus,
        CompactionTrigger,
        TokenUsage,
        ModelTokenUsage;
import 'package:cc_insights_v2/models/agent.dart';
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

/// Helper to create TextEvent with default boilerplate fields.
TextEvent makeText({
  String text = 'Test text',
  TextKind kind = TextKind.text,
  String? parentCallId,
  String? model,
  Map<String, dynamic>? raw,
}) {
  return TextEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    text: text,
    kind: kind,
    parentCallId: parentCallId,
    model: model,
    raw: raw,
  );
}

/// Helper to create UserInputEvent with default boilerplate fields.
UserInputEvent makeUserInput({
  String text = 'Test user message',
  bool isSynthetic = false,
  Map<String, dynamic>? extensions,
  Map<String, dynamic>? raw,
}) {
  return UserInputEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    text: text,
    isSynthetic: isSynthetic,
    extensions: extensions,
    raw: raw,
  );
}

/// Helper to create SessionInitEvent with default boilerplate fields.
SessionInitEvent makeSessionInit({
  String? model,
  Map<String, dynamic>? raw,
}) {
  return SessionInitEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    model: model,
    raw: raw,
  );
}

/// Helper to create SessionStatusEvent with default boilerplate fields.
SessionStatusEvent makeSessionStatus({
  required SessionStatus status,
  String? message,
  Map<String, dynamic>? extensions,
  Map<String, dynamic>? raw,
}) {
  return SessionStatusEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    status: status,
    message: message,
    extensions: extensions,
    raw: raw,
  );
}

/// Helper to create ContextCompactionEvent with default boilerplate fields.
ContextCompactionEvent makeCompaction({
  CompactionTrigger trigger = CompactionTrigger.auto,
  int? preTokens,
  String? summary,
  Map<String, dynamic>? raw,
}) {
  return ContextCompactionEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    trigger: trigger,
    preTokens: preTokens,
    summary: summary,
    raw: raw,
  );
}

/// Helper to create TurnCompleteEvent with default boilerplate fields.
TurnCompleteEvent makeTurnComplete({
  bool isError = false,
  String? subtype,
  String? result,
  double? costUsd,
  TokenUsage? usage,
  Map<String, ModelTokenUsage>? modelUsage,
  Map<String, dynamic>? extensions,
  Map<String, dynamic>? raw,
}) {
  return TurnCompleteEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    isError: isError,
    subtype: subtype,
    result: result,
    costUsd: costUsd,
    usage: usage,
    modelUsage: modelUsage,
    extensions: extensions,
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

  group('EventHandler - Task 4c: Text, User Input, Lifecycle, Compaction, Turn Complete', () {
    late ChatState chat;
    late EventHandler handler;

    setUp(() {
      chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
      handler = EventHandler();
      _idCounter = 0;
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    group('_handleText', () {
      test('creates TextOutputEntry with contentType text', () {
        handler.handleEvent(chat, makeText(
          text: 'Hello, world!',
          kind: TextKind.text,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Hello, world!');
        check(textEntry.contentType).equals('text');
        check(textEntry.errorType).isNull();
      });

      test('creates thinking entry with contentType thinking', () {
        handler.handleEvent(chat, makeText(
          text: 'Let me think...',
          kind: TextKind.thinking,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Let me think...');
        check(textEntry.contentType).equals('thinking');
        check(textEntry.errorType).isNull();
      });

      test('creates error entry with errorType error', () {
        handler.handleEvent(chat, makeText(
          text: 'Error occurred',
          kind: TextKind.error,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Error occurred');
        check(textEntry.contentType).equals('text');
        check(textEntry.errorType).equals('error');
      });

      test('marks assistant output for main agent only', () {
        // Main agent text (parentCallId null)
        handler.handleEvent(chat, makeText(
          text: 'Main agent response',
          parentCallId: null,
        ));

        // Trigger turn complete to see if flag is read
        handler.handleEvent(chat, makeTurnComplete());

        // The flag should have been set and then reset
        // We verify indirectly - no system notification should be added
        // since we had assistant output
        final entries = chat.data.primaryConversation.entries;
        // Should be: 1 text entry + 0 system notifications (because flag was set)
        check(entries.length).equals(1);
      });

      test('does NOT mark assistant output for subagent', () {
        // Subagent text (parentCallId set)
        handler.handleEvent(chat, makeText(
          text: 'Subagent response',
          parentCallId: 'agent-123',
        ));

        // Trigger turn complete with result but flag not set
        handler.handleEvent(chat, makeTurnComplete(
          result: 'No output message',
        ));

        // Should create system notification because flag wasn't set
        final entries = chat.data.primaryConversation.entries;
        final hasSystemNotification = entries.any((e) => e is SystemNotificationEntry);
        check(hasSystemNotification).isTrue();
      });
    });

    group('_handleUserInput', () {
      test('creates ContextSummaryEntry for synthetic messages', () {
        handler.handleEvent(chat, makeUserInput(
          text: 'This is a context summary',
          isSynthetic: true,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ContextSummaryEntry>();

        final summary = entries.first as ContextSummaryEntry;
        check(summary.summary).equals('This is a context summary');
      });

      test('creates SystemNotificationEntry for local command replay', () {
        handler.handleEvent(chat, makeUserInput(
          text: '<local-command-stdout>Cost: \$0.50</local-command-stdout>',
          extensions: {'isReplay': true},
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<SystemNotificationEntry>();

        final notification = entries.first as SystemNotificationEntry;
        check(notification.message).equals('Cost: \$0.50');
      });

      test('creates ContextSummaryEntry when expectingContextSummary flag is set', () {
        // First trigger compaction without summary
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.auto,
          preTokens: 45000,
          summary: null, // No summary yet
        ));

        // Now send user message - should be treated as summary
        handler.handleEvent(chat, makeUserInput(
          text: 'Compacted summary here',
        ));

        final entries = chat.data.primaryConversation.entries;
        // Should be: AutoCompactionEntry + ContextSummaryEntry
        check(entries.length).equals(2);
        check(entries[1]).isA<ContextSummaryEntry>();

        final summary = entries[1] as ContextSummaryEntry;
        check(summary.summary).equals('Compacted summary here');
      });

      test('resets expectingContextSummary flag after handling', () {
        // Trigger compaction without summary
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.auto,
          summary: null,
        ));

        // First user message creates summary
        handler.handleEvent(chat, makeUserInput(text: 'Summary'));

        // Second user message should NOT create summary (flag was reset)
        handler.handleEvent(chat, makeUserInput(text: 'Normal message'));

        final entries = chat.data.primaryConversation.entries;
        // Should be: AutoCompactionEntry + ContextSummaryEntry (not 2 summaries)
        check(entries.length).equals(2);
      });

      test('no-op for normal user messages', () {
        // Normal user messages don't create entries (ChatState.sendMessage does that)
        handler.handleEvent(chat, makeUserInput(
          text: 'Hello Claude',
          isSynthetic: false,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(0);
      });
    });

    group('_handleSessionInit', () {
      test('no-op (matches SdkMessageHandler behavior)', () {
        handler.handleEvent(chat, makeSessionInit(
          model: 'claude-sonnet-4-5',
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(0);
      });
    });

    group('_handleSessionStatus', () {
      test('sets compacting to true', () {
        check(chat.isCompacting).isFalse();

        handler.handleEvent(chat, makeSessionStatus(
          status: SessionStatus.compacting,
        ));

        check(chat.isCompacting).isTrue();
      });

      test('sets compacting to false', () {
        // First set to true
        handler.handleEvent(chat, makeSessionStatus(
          status: SessionStatus.compacting,
        ));
        check(chat.isCompacting).isTrue();

        // Then set to false (any non-compacting status)
        handler.handleEvent(chat, makeSessionStatus(
          status: SessionStatus.ended,
        ));

        check(chat.isCompacting).isFalse();
      });

      test('syncs permission mode from extensions', () {
        handler.handleEvent(chat, makeSessionStatus(
          status: SessionStatus.resuming,
          extensions: {'permissionMode': 'plan'},
        ));

        check(chat.permissionMode).equals(PermissionMode.plan);
      });
    });

    group('_handleCompaction', () {
      test('creates AutoCompactionEntry with token message', () {
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.auto,
          preTokens: 45000,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<AutoCompactionEntry>();

        final compaction = entries.first as AutoCompactionEntry;
        check(compaction.message).equals('Was 45.0K tokens');
        check(compaction.isManual).isFalse();
      });

      test('creates AutoCompactionEntry with manual flag', () {
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.manual,
          preTokens: 30000,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.first).isA<AutoCompactionEntry>();

        final compaction = entries.first as AutoCompactionEntry;
        check(compaction.isManual).isTrue();
      });

      test('creates ContextClearedEntry for cleared trigger', () {
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.cleared,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<ContextClearedEntry>();
      });

      test('sets expectingContextSummary when no summary provided', () {
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.auto,
          preTokens: 50000,
          summary: null,
        ));

        // Now send a user message - should be treated as summary
        handler.handleEvent(chat, makeUserInput(text: 'Summary text'));

        final entries = chat.data.primaryConversation.entries;
        // AutoCompactionEntry + ContextSummaryEntry
        check(entries.length).equals(2);
        check(entries[1]).isA<ContextSummaryEntry>();
      });

      test('creates ContextSummaryEntry when summary is provided', () {
        handler.handleEvent(chat, makeCompaction(
          trigger: CompactionTrigger.auto,
          preTokens: 50000,
          summary: 'Immediate summary',
        ));

        final entries = chat.data.primaryConversation.entries;
        // AutoCompactionEntry + ContextSummaryEntry
        check(entries.length).equals(2);
        check(entries[1]).isA<ContextSummaryEntry>();

        final summary = entries[1] as ContextSummaryEntry;
        check(summary.summary).equals('Immediate summary');
      });
    });

    group('_handleTurnComplete', () {
      test('updates cumulative usage for main agent', () {
        final usage = const TokenUsage(
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
        );

        final modelUsage = {
          'claude-sonnet-4-5': const ModelTokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 100,
            cacheCreationTokens: 50,
            costUsd: 0.05,
            contextWindow: 200000,
          ),
        };

        handler.handleEvent(chat, makeTurnComplete(
          usage: usage,
          costUsd: 0.05,
          modelUsage: modelUsage,
        ));

        // Verify usage was updated
        check(chat.cumulativeUsage.inputTokens).equals(1000);
        check(chat.cumulativeUsage.outputTokens).equals(500);
        check(chat.cumulativeUsage.cacheReadTokens).equals(100);
        check(chat.cumulativeUsage.cacheCreationTokens).equals(50);
      });

      test('sets working to false for main agent', () {
        // Simulate working state
        chat.setWorking(true);
        check(chat.isWorking).isTrue();

        handler.handleEvent(chat, makeTurnComplete());

        check(chat.isWorking).isFalse();
      });

      test('updates agent status for subagent (completed)', () {
        // Create a subagent first
        chat.addSubagentConversation('agent-123', 'Explore', 'Search task');
        check(chat.activeAgents['agent-123']?.status).equals(AgentStatus.working);

        // Send turn complete for subagent
        handler.handleEvent(chat, makeTurnComplete(
          subtype: 'success',
          extensions: {'parent_tool_use_id': 'agent-123'},
        ));

        check(chat.activeAgents['agent-123']?.status).equals(AgentStatus.completed);
      });

      test('updates agent status for subagent (error subtypes)', () {
        // Create a subagent first
        chat.addSubagentConversation('agent-456', 'Plan', 'Plan task');

        // Send error turn complete
        handler.handleEvent(chat, makeTurnComplete(
          subtype: 'error_max_turns',
          extensions: {'parent_tool_use_id': 'agent-456'},
        ));

        check(chat.activeAgents['agent-456']?.status).equals(AgentStatus.error);
      });

      test('creates SystemNotificationEntry when no assistant output and result present', () {
        // Don't send any assistant text (flag not set)
        handler.handleEvent(chat, makeTurnComplete(
          result: 'Unknown skill: clear',
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<SystemNotificationEntry>();

        final notification = entries.first as SystemNotificationEntry;
        check(notification.message).equals('Unknown skill: clear');
      });

      test('does not create notification when result is null', () {
        handler.handleEvent(chat, makeTurnComplete(
          result: null,
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(0);
      });

      test('does not create notification when result is empty', () {
        handler.handleEvent(chat, makeTurnComplete(
          result: '',
        ));

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(0);
      });

      test('resets hasAssistantOutputThisTurn flag', () {
        // Send text to set the flag
        handler.handleEvent(chat, makeText(text: 'Response'));

        // Send turn complete
        handler.handleEvent(chat, makeTurnComplete());

        // Send another turn complete with result
        // Should create notification because flag was reset
        handler.handleEvent(chat, makeTurnComplete(
          result: 'Next turn message',
        ));

        final entries = chat.data.primaryConversation.entries;
        // TextEntry + SystemNotificationEntry
        check(entries.length).equals(2);
        check(entries[1]).isA<SystemNotificationEntry>();
      });
    });
  });
}
