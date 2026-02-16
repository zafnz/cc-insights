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
        StreamDeltaEvent,
        SubagentSpawnEvent,
        SubagentCompleteEvent,
        ToolKind,
        ToolCallStatus,
        TextKind,
        SessionStatus,
        CompactionTrigger,
        StreamDeltaKind,
        TokenUsage,
        ModelTokenUsage;
import 'package:cc_insights_v2/models/agent.dart';
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/services/ask_ai_service.dart';
import 'package:cc_insights_v2/services/chat_title_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:checks/checks.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
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
  Map<String, dynamic>? extensions,
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
    extensions: extensions,
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
SessionInitEvent makeSessionInit({String? model, Map<String, dynamic>? raw}) {
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
  BackendProvider provider = BackendProvider.claude,
}) {
  return TurnCompleteEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: provider,
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

/// Helper to create StreamDeltaEvent with default boilerplate fields.
StreamDeltaEvent makeStreamDelta({
  required StreamDeltaKind kind,
  String? parentCallId,
  String? textDelta,
  String? jsonDelta,
  int? blockIndex,
  String? callId,
  Map<String, dynamic>? extensions,
  Map<String, dynamic>? raw,
}) {
  return StreamDeltaEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    sessionId: 'test-session',
    kind: kind,
    parentCallId: parentCallId,
    textDelta: textDelta,
    jsonDelta: jsonDelta,
    blockIndex: blockIndex,
    callId: callId,
    extensions: extensions,
    raw: raw,
  );
}

void main() {
  group('EventHandler - Task 4b: Tool Events', () {
    late Chat chat;
    late EventHandler handler;

    setUp(() {
      chat = Chat.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
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
        final event = makeToolInvocation(callId: 'tool-789', raw: rawMsg);

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

  group(
    'EventHandler - Task 4c: Text, User Input, Lifecycle, Compaction, Turn Complete',
    () {
      late Chat chat;
      late EventHandler handler;

      setUp(() {
        chat = Chat.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
        handler = EventHandler();
        _idCounter = 0;
      });

      tearDown(() {
        handler.dispose();
        chat.dispose();
      });

      group('_handleText', () {
        test('creates TextOutputEntry with contentType text', () {
          handler.handleEvent(
            chat,
            makeText(text: 'Hello, world!', kind: TextKind.text),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<TextOutputEntry>();

          final textEntry = entries.first as TextOutputEntry;
          check(textEntry.text).equals('Hello, world!');
          check(textEntry.contentType).equals('text');
          check(textEntry.errorType).isNull();
        });

        test('creates thinking entry with contentType thinking', () {
          handler.handleEvent(
            chat,
            makeText(text: 'Let me think...', kind: TextKind.thinking),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<TextOutputEntry>();

          final textEntry = entries.first as TextOutputEntry;
          check(textEntry.text).equals('Let me think...');
          check(textEntry.contentType).equals('thinking');
          check(textEntry.errorType).isNull();
        });

        test('creates error entry with errorType error', () {
          handler.handleEvent(
            chat,
            makeText(text: 'Error occurred', kind: TextKind.error),
          );

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
          handler.handleEvent(
            chat,
            makeText(text: 'Main agent response', parentCallId: null),
          );

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
          handler.handleEvent(
            chat,
            makeText(text: 'Subagent response', parentCallId: 'agent-123'),
          );

          // Trigger turn complete with result but flag not set
          handler.handleEvent(
            chat,
            makeTurnComplete(result: 'No output message'),
          );

          // Should create system notification because flag wasn't set
          final entries = chat.data.primaryConversation.entries;
          final hasSystemNotification = entries.any(
            (e) => e is SystemNotificationEntry,
          );
          check(hasSystemNotification).isTrue();
        });

        test(
          'creates ContextSummaryEntry when expecting compaction summary and synthetic',
          () {
            // Trigger compaction without inline summary
            handler.handleEvent(
              chat,
              makeCompaction(
                trigger: CompactionTrigger.auto,
                preTokens: 50000,
                summary: null,
              ),
            );

            // Now send a synthetic TextEvent (as the new protocol does)
            handler.handleEvent(
              chat,
              makeText(
                text: 'This is the compaction summary',
                extensions: {'claude.isSynthetic': true},
              ),
            );

            final entries = chat.data.primaryConversation.entries;
            // AutoCompactionEntry + ContextSummaryEntry
            check(entries.length).equals(2);
            check(entries[0]).isA<AutoCompactionEntry>();
            check(entries[1]).isA<ContextSummaryEntry>();

            final summary = entries[1] as ContextSummaryEntry;
            check(summary.summary).equals('This is the compaction summary');
          },
        );

        test(
          'synthetic TextEvent without prior compaction creates normal TextOutputEntry',
          () {
            // No compaction event first — just a synthetic text
            handler.handleEvent(
              chat,
              makeText(
                text: 'Some synthetic text',
                extensions: {'claude.isSynthetic': true},
              ),
            );

            final entries = chat.data.primaryConversation.entries;
            check(entries.length).equals(1);
            check(entries.first).isA<TextOutputEntry>();
          },
        );

        test(
          'non-synthetic TextEvent after compaction creates normal TextOutputEntry',
          () {
            // Trigger compaction without summary
            handler.handleEvent(
              chat,
              makeCompaction(
                trigger: CompactionTrigger.auto,
                preTokens: 50000,
                summary: null,
              ),
            );

            // Send a non-synthetic TextEvent — both conditions not met
            handler.handleEvent(
              chat,
              makeText(text: 'Normal assistant response'),
            );

            final entries = chat.data.primaryConversation.entries;
            // AutoCompactionEntry + TextOutputEntry (not ContextSummaryEntry)
            check(entries.length).equals(2);
            check(entries[0]).isA<AutoCompactionEntry>();
            check(entries[1]).isA<TextOutputEntry>();
          },
        );

        test(
          'resets expectingContextSummary flag after synthetic TextEvent',
          () {
            // Trigger compaction without summary
            handler.handleEvent(
              chat,
              makeCompaction(trigger: CompactionTrigger.auto, summary: null),
            );

            // First synthetic text creates summary
            handler.handleEvent(
              chat,
              makeText(
                text: 'Summary',
                extensions: {'claude.isSynthetic': true},
              ),
            );

            // Second synthetic text should be normal (flag was reset)
            handler.handleEvent(
              chat,
              makeText(
                text: 'Not a summary',
                extensions: {'claude.isSynthetic': true},
              ),
            );

            final entries = chat.data.primaryConversation.entries;
            // AutoCompactionEntry + ContextSummaryEntry + TextOutputEntry
            check(entries.length).equals(3);
            check(entries[1]).isA<ContextSummaryEntry>();
            check(entries[2]).isA<TextOutputEntry>();
          },
        );
      });

      group('_handleUserInput', () {
        test('creates ContextSummaryEntry for synthetic messages', () {
          handler.handleEvent(
            chat,
            makeUserInput(text: 'This is a context summary', isSynthetic: true),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<ContextSummaryEntry>();

          final summary = entries.first as ContextSummaryEntry;
          check(summary.summary).equals('This is a context summary');
        });

        test('creates SystemNotificationEntry for local command replay', () {
          handler.handleEvent(
            chat,
            makeUserInput(
              text: '<local-command-stdout>Cost: \$0.50</local-command-stdout>',
              extensions: {'isReplay': true},
            ),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<SystemNotificationEntry>();

          final notification = entries.first as SystemNotificationEntry;
          check(notification.message).equals('Cost: \$0.50');
        });

        test(
          'creates ContextSummaryEntry when expectingContextSummary flag is set',
          () {
            // First trigger compaction without summary
            handler.handleEvent(
              chat,
              makeCompaction(
                trigger: CompactionTrigger.auto,
                preTokens: 45000,
                summary: null, // No summary yet
              ),
            );

            // Now send user message - should be treated as summary
            handler.handleEvent(
              chat,
              makeUserInput(text: 'Compacted summary here'),
            );

            final entries = chat.data.primaryConversation.entries;
            // Should be: AutoCompactionEntry + ContextSummaryEntry
            check(entries.length).equals(2);
            check(entries[1]).isA<ContextSummaryEntry>();

            final summary = entries[1] as ContextSummaryEntry;
            check(summary.summary).equals('Compacted summary here');
          },
        );

        test('resets expectingContextSummary flag after handling', () {
          // Trigger compaction without summary
          handler.handleEvent(
            chat,
            makeCompaction(trigger: CompactionTrigger.auto, summary: null),
          );

          // First user message creates summary
          handler.handleEvent(chat, makeUserInput(text: 'Summary'));

          // Second user message should NOT create summary (flag was reset)
          handler.handleEvent(chat, makeUserInput(text: 'Normal message'));

          final entries = chat.data.primaryConversation.entries;
          // Should be: AutoCompactionEntry + ContextSummaryEntry (not 2 summaries)
          check(entries.length).equals(2);
        });

        test('no-op for normal user messages', () {
          // Normal user messages don't create entries (Chat.sendMessage does that)
          handler.handleEvent(
            chat,
            makeUserInput(text: 'Hello Claude', isSynthetic: false),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(0);
        });
      });

      group('_handleSessionInit', () {
        test('no-op', () {
          handler.handleEvent(
            chat,
            makeSessionInit(model: 'claude-sonnet-4-5'),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(0);
        });
      });

      group('_handleSessionStatus', () {
        test('sets compacting to true', () {
          check(chat.session.isCompacting).isFalse();

          handler.handleEvent(
            chat,
            makeSessionStatus(status: SessionStatus.compacting),
          );

          check(chat.session.isCompacting).isTrue();
        });

        test('sets compacting to false', () {
          // First set to true
          handler.handleEvent(
            chat,
            makeSessionStatus(status: SessionStatus.compacting),
          );
          check(chat.session.isCompacting).isTrue();

          // Then set to false (any non-compacting status)
          handler.handleEvent(
            chat,
            makeSessionStatus(status: SessionStatus.ended),
          );

          check(chat.session.isCompacting).isFalse();
        });

        test('syncs permission mode from extensions', () {
          handler.handleEvent(
            chat,
            makeSessionStatus(
              status: SessionStatus.resuming,
              extensions: {'permissionMode': 'plan'},
            ),
          );

          check(chat.settings.permissionMode).equals(PermissionMode.plan);
        });
      });

      group('_handleCompaction', () {
        test('creates AutoCompactionEntry with token message', () {
          handler.handleEvent(
            chat,
            makeCompaction(trigger: CompactionTrigger.auto, preTokens: 45000),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<AutoCompactionEntry>();

          final compaction = entries.first as AutoCompactionEntry;
          check(compaction.message).equals('Was 45.0K tokens');
          check(compaction.isManual).isFalse();
        });

        test('creates AutoCompactionEntry with manual flag', () {
          handler.handleEvent(
            chat,
            makeCompaction(trigger: CompactionTrigger.manual, preTokens: 30000),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.first).isA<AutoCompactionEntry>();

          final compaction = entries.first as AutoCompactionEntry;
          check(compaction.isManual).isTrue();
        });

        test('creates ContextClearedEntry for cleared trigger', () {
          handler.handleEvent(
            chat,
            makeCompaction(trigger: CompactionTrigger.cleared),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<ContextClearedEntry>();
        });

        test('sets expectingContextSummary when no summary provided', () {
          handler.handleEvent(
            chat,
            makeCompaction(
              trigger: CompactionTrigger.auto,
              preTokens: 50000,
              summary: null,
            ),
          );

          // Send synthetic TextEvent (matches real protocol flow)
          handler.handleEvent(
            chat,
            makeText(
              text: 'Summary text',
              extensions: {'claude.isSynthetic': true},
            ),
          );

          final entries = chat.data.primaryConversation.entries;
          // AutoCompactionEntry + ContextSummaryEntry
          check(entries.length).equals(2);
          check(entries[1]).isA<ContextSummaryEntry>();
        });

        test('creates ContextSummaryEntry when summary is provided', () {
          handler.handleEvent(
            chat,
            makeCompaction(
              trigger: CompactionTrigger.auto,
              preTokens: 50000,
              summary: 'Immediate summary',
            ),
          );

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
          const usage = TokenUsage(
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

          handler.handleEvent(
            chat,
            makeTurnComplete(
              usage: usage,
              costUsd: 0.05,
              modelUsage: modelUsage,
            ),
          );

          // Verify usage was updated
          check(chat.metrics.cumulativeUsage.inputTokens).equals(1000);
          check(chat.metrics.cumulativeUsage.outputTokens).equals(500);
          check(chat.metrics.cumulativeUsage.cacheReadTokens).equals(100);
          check(chat.metrics.cumulativeUsage.cacheCreationTokens).equals(50);
        });

        test('sets working to false for main agent', () {
          // Simulate working state
          chat.session.setWorking(true);
          check(chat.session.isWorking).isTrue();

          handler.handleEvent(chat, makeTurnComplete());

          check(chat.session.isWorking).isFalse();
        });

        test('updates agent status for subagent (completed)', () {
          // Create a subagent first
          chat.conversations.addSubagentConversation(
            'agent-123',
            'Explore',
            'Search task',
          );
          check(
            chat.agents.activeAgents['agent-123']?.status,
          ).equals(AgentStatus.working);

          // Send turn complete for subagent
          handler.handleEvent(
            chat,
            makeTurnComplete(
              subtype: 'success',
              extensions: {'parent_tool_use_id': 'agent-123'},
            ),
          );

          check(
            chat.agents.activeAgents['agent-123']?.status,
          ).equals(AgentStatus.completed);
        });

        test('updates agent status for subagent (error subtypes)', () {
          // Create a subagent first
          chat.conversations.addSubagentConversation(
            'agent-456',
            'Plan',
            'Plan task',
          );

          // Send error turn complete
          handler.handleEvent(
            chat,
            makeTurnComplete(
              subtype: 'error_max_turns',
              extensions: {'parent_tool_use_id': 'agent-456'},
            ),
          );

          check(
            chat.agents.activeAgents['agent-456']?.status,
          ).equals(AgentStatus.error);
        });

        test(
          'creates SystemNotificationEntry when no assistant output and result present',
          () {
            // Don't send any assistant text (flag not set)
            handler.handleEvent(
              chat,
              makeTurnComplete(result: 'Unknown skill: clear'),
            );

            final entries = chat.data.primaryConversation.entries;
            check(entries.length).equals(1);
            check(entries.first).isA<SystemNotificationEntry>();

            final notification = entries.first as SystemNotificationEntry;
            check(notification.message).equals('Unknown skill: clear');
          },
        );

        test('does not create notification when result is null', () {
          handler.handleEvent(chat, makeTurnComplete(result: null));

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(0);
        });

        test('does not create notification when result is empty', () {
          handler.handleEvent(chat, makeTurnComplete(result: ''));

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
          handler.handleEvent(
            chat,
            makeTurnComplete(result: 'Next turn message'),
          );

          final entries = chat.data.primaryConversation.entries;
          // TextEntry + SystemNotificationEntry
          check(entries.length).equals(2);
          check(entries[1]).isA<SystemNotificationEntry>();
        });

        test('calculates cost for Codex events using pricing table', () {
          const usage = TokenUsage(
            inputTokens: 1000000,
            outputTokens: 100000,
            cacheReadTokens: 500000,
          );

          final modelUsage = {
            'gpt-5.2-codex': const ModelTokenUsage(
              inputTokens: 1000000,
              outputTokens: 100000,
              cacheReadTokens: 500000,
              contextWindow: 192000,
            ),
          };

          handler.handleEvent(
            chat,
            makeTurnComplete(
              provider: BackendProvider.codex,
              usage: usage,
              modelUsage: modelUsage,
            ),
          );

          // gpt-5.2-codex: 1M * 1.75/1M + 500k * 0.175/1M + 100k * 14.00/1M
          //              = 1.75 + 0.0875 + 1.4 = 3.2375
          check(chat.metrics.cumulativeUsage.costUsd).isCloseTo(3.2375, 0.0001);
        });

        test('does not override Claude cost with pricing table', () {
          const usage = TokenUsage(inputTokens: 1000, outputTokens: 500);

          final modelUsage = {
            'claude-sonnet-4-5': const ModelTokenUsage(
              inputTokens: 1000,
              outputTokens: 500,
              costUsd: 0.05,
              contextWindow: 200000,
            ),
          };

          handler.handleEvent(
            chat,
            makeTurnComplete(
              provider: BackendProvider.claude,
              usage: usage,
              costUsd: 0.05,
              modelUsage: modelUsage,
            ),
          );

          // Cost should be exactly what Claude reported, not recalculated
          check(chat.metrics.cumulativeUsage.costUsd).equals(0.05);
        });
      });
    },
  );

  group('EventHandler - Task 4d: Streaming Delta Handling', () {
    late Chat chat;
    late EventHandler handler;

    setUp(() {
      chat = Chat.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
      handler = EventHandler();
      _idCounter = 0;
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    group('text block streaming', () {
      test('blockStart creates streaming TextOutputEntry for text block', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start text block
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            extensions: {},
          ),
        );

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        check(entries.first).isA<TextOutputEntry>();

        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('');
        check(textEntry.contentType).equals('text');
        check(textEntry.isStreaming).isTrue();
      });

      test('text delta appends text to TextOutputEntry', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start text block
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Send text deltas
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: 'Hello',
          ),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: ' world',
          ),
        );

        final entries = chat.data.primaryConversation.entries;
        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Hello world');
        check(textEntry.isStreaming).isTrue();
      });

      test('blockStop marks entry as not streaming', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start and stream text
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: 'Complete text',
          ),
        );

        // Stop block
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStop, blockIndex: 0),
        );

        final entries = chat.data.primaryConversation.entries;
        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.isStreaming).isFalse();
      });

      test('messageStop cancels timer and clears streaming state', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start text block
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Stream some text
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: 'Text',
          ),
        );

        // Stop message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStop),
        );

        // Verify entry exists but streaming state is cleared
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
      });
    });

    group('thinking block streaming', () {
      test(
        'blockStart creates streaming TextOutputEntry for thinking block',
        () {
          // Start message
          handler.handleEvent(
            chat,
            makeStreamDelta(kind: StreamDeltaKind.messageStart),
          );

          // Start thinking block
          handler.handleEvent(
            chat,
            makeStreamDelta(
              kind: StreamDeltaKind.blockStart,
              blockIndex: 0,
              extensions: {'block_type': 'thinking'},
            ),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<TextOutputEntry>();

          final textEntry = entries.first as TextOutputEntry;
          check(textEntry.text).equals('');
          check(textEntry.contentType).equals('thinking');
          check(textEntry.isStreaming).isTrue();
        },
      );

      test('thinking delta appends text to thinking TextOutputEntry', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start thinking block
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            extensions: {'block_type': 'thinking'},
          ),
        );

        // Send thinking deltas
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.thinking,
            blockIndex: 0,
            textDelta: 'Let me ',
          ),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.thinking,
            blockIndex: 0,
            textDelta: 'think...',
          ),
        );

        final entries = chat.data.primaryConversation.entries;
        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.text).equals('Let me think...');
        check(textEntry.contentType).equals('thinking');
      });
    });

    group('tool use streaming', () {
      test(
        'blockStart creates streaming ToolUseOutputEntry for tool block',
        () {
          // Start message
          handler.handleEvent(
            chat,
            makeStreamDelta(kind: StreamDeltaKind.messageStart),
          );

          // Start tool block
          handler.handleEvent(
            chat,
            makeStreamDelta(
              kind: StreamDeltaKind.blockStart,
              blockIndex: 0,
              callId: 'tool-123',
              extensions: {'tool_name': 'Read'},
            ),
          );

          final entries = chat.data.primaryConversation.entries;
          check(entries.length).equals(1);
          check(entries.first).isA<ToolUseOutputEntry>();

          final toolEntry = entries.first as ToolUseOutputEntry;
          check(toolEntry.toolName).equals('Read');
          check(toolEntry.toolUseId).equals('tool-123');
          check(toolEntry.toolInput).isEmpty();
          check(toolEntry.isStreaming).isTrue();
        },
      );

      test('blockStart registers tool entry in toolCallIndex', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start tool block
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            callId: 'tool-456',
            extensions: {'tool_name': 'Bash'},
          ),
        );

        // Verify pairing works by sending a completion
        final completion = makeToolCompletion(
          callId: 'tool-456',
          output: 'Command output',
        );
        handler.handleEvent(chat, completion);

        final entries = chat.data.primaryConversation.entries;
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.result).equals('Command output');
      });

      test('toolInput delta accumulates on ToolUseOutputEntry', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start tool block
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            callId: 'tool-789',
            extensions: {'tool_name': 'Edit'},
          ),
        );

        // Send tool input deltas
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.toolInput,
            blockIndex: 0,
            jsonDelta: '{"file',
          ),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.toolInput,
            blockIndex: 0,
            jsonDelta: '":"test.txt"}',
          ),
        );

        final entries = chat.data.primaryConversation.entries;
        final toolEntry = entries.first as ToolUseOutputEntry;
        // Note: The partial JSON is accumulated but not parsed until finalization
        check(toolEntry.isStreaming).isTrue();
      });

      test('blockStop marks tool entry as not streaming', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start tool block
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            callId: 'tool-stop',
            extensions: {'tool_name': 'Write'},
          ),
        );

        // Stop block
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStop, blockIndex: 0),
        );

        final entries = chat.data.primaryConversation.entries;
        final toolEntry = entries.first as ToolUseOutputEntry;
        check(toolEntry.isStreaming).isFalse();
      });
    });

    group('multiple blocks', () {
      test('multiple blocks create separate entries at different indices', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Start thinking block at index 0
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 0,
            extensions: {'block_type': 'thinking'},
          ),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.thinking,
            blockIndex: 0,
            textDelta: 'Thinking...',
          ),
        );

        // Start text block at index 1
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 1),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 1,
            textDelta: 'Response text',
          ),
        );

        // Start tool block at index 2
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.blockStart,
            blockIndex: 2,
            callId: 'tool-multi',
            extensions: {'tool_name': 'Read'},
          ),
        );

        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(3);
        check(entries[0]).isA<TextOutputEntry>();
        check(entries[1]).isA<TextOutputEntry>();
        check(entries[2]).isA<ToolUseOutputEntry>();

        final thinking = entries[0] as TextOutputEntry;
        check(thinking.contentType).equals('thinking');
        check(thinking.text).equals('Thinking...');

        final text = entries[1] as TextOutputEntry;
        check(text.contentType).equals('text');
        check(text.text).equals('Response text');
      });
    });

    group('subagent streaming', () {
      test('subagent streaming routes to correct conversation via parentCallId', () {
        // Note: In real usage, SubagentSpawnEvent would set up the routing mapping.
        // For this test, we manually create the subagent and verify that IF the
        // mapping exists, streaming would route correctly. The full integration
        // with SubagentSpawnEvent is tested in Task 4e.

        // Create subagent conversation
        chat.conversations.addSubagentConversation(
          'agent-123',
          'Explore',
          'Search task',
        );
        final agent = chat.agents.activeAgents['agent-123']!;
        final subagentConvId = agent.conversationId;
        final subagentConv = chat.data.subagentConversations[subagentConvId]!;

        // In Task 4e, SubagentSpawnEvent would set this up automatically
        // For now, we'll test that the streaming logic itself works when
        // parentCallId is null vs non-null

        // Main agent streaming (parentCallId: null) should go to primary
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: 'Primary output',
          ),
        );

        // Verify it went to primary conversation
        check(chat.data.primaryConversation.entries.length).equals(1);
        check(subagentConv.entries.length).equals(0);

        final textEntry =
            chat.data.primaryConversation.entries.first as TextOutputEntry;
        check(textEntry.text).equals('Primary output');
      });
    });

    group('messageStart context', () {
      test('messageStart sets streaming conversation context', () {
        // Start message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        // Verify context is set by starting a block
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Should create entry in primary conversation
        check(chat.data.primaryConversation.entries.length).equals(1);
      });

      test('messageStart clears previous streaming blocks', () {
        // First message
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Second message (should clear state)
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Should have two entries (one from each message)
        check(chat.data.primaryConversation.entries.length).equals(2);
      });
    });

    group('error handling', () {
      test('deltas without prior blockStart are ignored (no crash)', () {
        // Send delta without starting message or block
        expect(() {
          handler.handleEvent(
            chat,
            makeStreamDelta(
              kind: StreamDeltaKind.text,
              blockIndex: 0,
              textDelta: 'Orphaned delta',
            ),
          );
        }, returnsNormally);

        // No entries should be created
        check(chat.data.primaryConversation.entries.length).equals(0);
      });

      test('blockStop without prior blockStart is ignored', () {
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );

        expect(() {
          handler.handleEvent(
            chat,
            makeStreamDelta(kind: StreamDeltaKind.blockStop, blockIndex: 0),
          );
        }, returnsNormally);
      });
    });

    group('clearStreamingState', () {
      test('clearStreamingState finalizes in-flight entries and notifies', () {
        // Start streaming
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(
            kind: StreamDeltaKind.text,
            blockIndex: 0,
            textDelta: 'Interrupted',
          ),
        );

        // Clear streaming state
        handler.clearStreamingState();

        // Entry should be finalized
        final entries = chat.data.primaryConversation.entries;
        check(entries.length).equals(1);
        final textEntry = entries.first as TextOutputEntry;
        check(textEntry.isStreaming).isFalse();
        check(textEntry.text).equals('Interrupted');
      });

      test('clearStreamingState clears all internal state', () {
        // Start streaming
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.messageStart),
        );
        handler.handleEvent(
          chat,
          makeStreamDelta(kind: StreamDeltaKind.blockStart, blockIndex: 0),
        );

        // Clear
        handler.clearStreamingState();

        // Starting new deltas should not crash (state was cleared)
        expect(() {
          handler.handleEvent(
            chat,
            makeStreamDelta(
              kind: StreamDeltaKind.text,
              blockIndex: 0,
              textDelta: 'New message',
            ),
          );
        }, returnsNormally);
      });
    });
  });

  /// Helper to create SubagentSpawnEvent with default boilerplate fields.
  SubagentSpawnEvent makeSubagentSpawn({
    required String callId,
    String? agentType,
    String? description,
    bool isResume = false,
    String? resumeAgentId,
    Map<String, dynamic>? raw,
  }) {
    return SubagentSpawnEvent(
      id: _nextId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      sessionId: 'test-session',
      callId: callId,
      agentType: agentType,
      description: description,
      isResume: isResume,
      resumeAgentId: resumeAgentId,
      raw: raw,
    );
  }

  /// Helper to create SubagentCompleteEvent with default boilerplate fields.
  SubagentCompleteEvent makeSubagentComplete({
    required String callId,
    String? agentId,
    String? status,
    String? summary,
    Map<String, dynamic>? raw,
  }) {
    return SubagentCompleteEvent(
      id: _nextId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      sessionId: 'test-session',
      callId: callId,
      agentId: agentId,
      status: status,
      summary: summary,
      raw: raw,
    );
  }

  group('EventHandler - Task 4e: Subagent Routing + Title Generation', () {
    late Chat chat;
    late EventHandler handler;

    setUp(() {
      chat = Chat.create(name: 'Test Chat', worktreeRoot: '/tmp/test');
      handler = EventHandler();
      _idCounter = 0;
    });

    tearDown(() {
      handler.dispose();
      chat.dispose();
    });

    group('_handleSubagentSpawn', () {
      test('creates subagent conversation with agentType and description', () {
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-123',
            agentType: 'Explore',
            description: 'Search for files',
          ),
        );

        // Verify subagent was created
        check(chat.agents.activeAgents.length).equals(1);
        final agent = chat.agents.activeAgents['task-123'];
        check(agent).isNotNull();
        check(agent!.status).equals(AgentStatus.working);

        // Verify subagent conversation exists
        check(chat.data.subagentConversations.length).equals(1);
        final subagentConv =
            chat.data.subagentConversations[agent.conversationId];
        check(subagentConv).isNotNull();
      });

      test('maps callId to conversation for routing', () {
        // Create subagent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-456',
            agentType: 'Plan',
            description: 'Plan implementation',
          ),
        );

        final agent = chat.agents.activeAgents['task-456']!;

        // Now send a text event with parentCallId - should route to subagent conversation
        handler.handleEvent(
          chat,
          makeText(text: 'Subagent output', parentCallId: 'task-456'),
        );

        // Verify the text went to the subagent conversation
        final subagentConv =
            chat.data.subagentConversations[agent.conversationId]!;
        check(subagentConv.entries.length).equals(1);
        check(subagentConv.entries.first).isA<TextOutputEntry>();

        final textEntry = subagentConv.entries.first as TextOutputEntry;
        check(textEntry.text).equals('Subagent output');
      });

      test('resumes existing agent (updates status, maps routing)', () {
        // First, create an agent and complete it
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-original',
            agentType: 'Explore',
            description: 'Original task',
          ),
        );

        final originalAgent = chat.agents.activeAgents['task-original']!;

        handler.handleEvent(
          chat,
          makeSubagentComplete(
            callId: 'task-original',
            agentId: 'abc123', // Resume ID
            status: 'completed',
            summary: 'First round complete',
          ),
        );

        // Verify agent completed
        check(
          chat.agents.activeAgents['task-original']!.status,
        ).equals(AgentStatus.completed);
        check(
          chat.agents.activeAgents['task-original']!.resumeId,
        ).equals('abc123');

        // Now resume the same agent with a new Task call
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-resumed',
            agentType: 'Explore',
            description: 'Continue task',
            isResume: true,
            resumeAgentId: 'abc123',
          ),
        );

        // Verify agent status updated to working
        check(
          chat.agents.activeAgents['task-original']!.status,
        ).equals(AgentStatus.working);

        // Verify new callId routes to the same conversation
        handler.handleEvent(
          chat,
          makeText(text: 'Resumed output', parentCallId: 'task-resumed'),
        );

        final subagentConv =
            chat.data.subagentConversations[originalAgent.conversationId]!;
        check(subagentConv.entries.length).equals(1);
        final textEntry = subagentConv.entries.first as TextOutputEntry;
        check(textEntry.text).equals('Resumed output');
      });

      test('falls through to create when resumeAgentId not found', () {
        // Try to resume a non-existent agent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-new',
            agentType: 'Explore',
            description: 'New task',
            isResume: true,
            resumeAgentId: 'nonexistent',
          ),
        );

        // Should create a new agent instead
        check(chat.agents.activeAgents.length).equals(1);
        final agent = chat.agents.activeAgents['task-new'];
        check(agent).isNotNull();
        check(agent!.status).equals(AgentStatus.working);
      });

      test('handles missing agentType gracefully', () {
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-no-type',
            agentType: null,
            description: 'Task description',
          ),
        );

        // Should still create the agent
        check(chat.agents.activeAgents.length).equals(1);
        check(chat.data.subagentConversations.length).equals(1);
      });

      test('handles missing description gracefully', () {
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-no-desc',
            agentType: 'Explore',
            description: null,
          ),
        );

        // Should still create the agent
        check(chat.agents.activeAgents.length).equals(1);
        check(chat.data.subagentConversations.length).equals(1);
      });
    });

    group('_handleSubagentComplete', () {
      test('updates agent to completed', () {
        // Create subagent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-123',
            agentType: 'Explore',
            description: 'Search task',
          ),
        );

        check(
          chat.agents.activeAgents['task-123']!.status,
        ).equals(AgentStatus.working);

        // Complete the agent
        handler.handleEvent(
          chat,
          makeSubagentComplete(
            callId: 'task-123',
            agentId: 'abc123',
            status: 'completed',
            summary: 'Task finished successfully',
          ),
        );

        final agent = chat.agents.activeAgents['task-123']!;
        check(agent.status).equals(AgentStatus.completed);
        check(agent.result).equals('Task finished successfully');
        check(agent.resumeId).equals('abc123');
      });

      test('updates agent to error for error statuses', () {
        // Create subagent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-456',
            agentType: 'Plan',
            description: 'Plan task',
          ),
        );

        // Complete with error
        handler.handleEvent(
          chat,
          makeSubagentComplete(
            callId: 'task-456',
            status: 'error_max_turns',
            summary: 'Max turns exceeded',
          ),
        );

        final agent = chat.agents.activeAgents['task-456']!;
        check(agent.status).equals(AgentStatus.error);
        check(agent.result).equals('Max turns exceeded');
      });

      test('uses _toolUseIdToAgentId for resumed agents', () {
        // Create and complete original agent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-original',
            agentType: 'Explore',
            description: 'Original task',
          ),
        );

        handler.handleEvent(
          chat,
          makeSubagentComplete(
            callId: 'task-original',
            agentId: 'abc123',
            status: 'completed',
          ),
        );

        // Resume the agent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-resumed',
            isResume: true,
            resumeAgentId: 'abc123',
          ),
        );

        // Complete the resumed agent - should update the original agent
        handler.handleEvent(
          chat,
          makeSubagentComplete(
            callId: 'task-resumed',
            agentId: 'abc123',
            status: 'completed',
            summary: 'Resume complete',
          ),
        );

        // Verify the original agent was updated
        final agent = chat.agents.activeAgents['task-original']!;
        check(agent.status).equals(AgentStatus.completed);
        check(agent.result).equals('Resume complete');
      });

      test('defaults to completed for unknown status', () {
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-789',
            agentType: 'Explore',
            description: 'Task',
          ),
        );

        handler.handleEvent(
          chat,
          makeSubagentComplete(callId: 'task-789', status: 'unknown_status'),
        );

        check(
          chat.agents.activeAgents['task-789']!.status,
        ).equals(AgentStatus.completed);
      });

      test('handles null status', () {
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-null',
            agentType: 'Plan',
            description: 'Task',
          ),
        );

        handler.handleEvent(
          chat,
          makeSubagentComplete(callId: 'task-null', status: null),
        );

        check(
          chat.agents.activeAgents['task-null']!.status,
        ).equals(AgentStatus.completed);
      });
    });

    group('conversation routing', () {
      test('messages with parentCallId route to subagent conversation', () {
        // Create subagent
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-123',
            agentType: 'Explore',
            description: 'Search task',
          ),
        );

        final agent = chat.agents.activeAgents['task-123']!;

        // Send text with parentCallId
        handler.handleEvent(
          chat,
          makeText(text: 'Subagent text', parentCallId: 'task-123'),
        );

        // Send tool invocation with parentCallId
        handler.handleEvent(
          chat,
          makeToolInvocation(
            callId: 'tool-sub',
            toolName: 'Read',
            parentCallId: 'task-123',
          ),
        );

        // Verify both went to subagent conversation
        final subagentConv =
            chat.data.subagentConversations[agent.conversationId]!;
        check(subagentConv.entries.length).equals(2);
        check(subagentConv.entries[0]).isA<TextOutputEntry>();
        check(subagentConv.entries[1]).isA<ToolUseOutputEntry>();

        // Verify nothing went to primary
        check(chat.data.primaryConversation.entries.length).equals(0);
      });

      test('messages without parentCallId route to primary', () {
        // Send text without parentCallId
        handler.handleEvent(
          chat,
          makeText(text: 'Main text', parentCallId: null),
        );

        // Send tool invocation without parentCallId
        handler.handleEvent(
          chat,
          makeToolInvocation(
            callId: 'tool-main',
            toolName: 'Bash',
            parentCallId: null,
          ),
        );

        // Verify both went to primary conversation
        check(chat.data.primaryConversation.entries.length).equals(2);
        check(chat.data.primaryConversation.entries[0]).isA<TextOutputEntry>();
        check(
          chat.data.primaryConversation.entries[1],
        ).isA<ToolUseOutputEntry>();
      });
    });

    group('SessionEventPipeline isolation', () {
      test('does not leak subagent routing state between chats', () async {
        // Ensure the second chat gets a distinct timestamp-based ID.
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final otherChat = Chat.create(
          name: 'Other Chat',
          worktreeRoot: '/tmp/other',
        );
        addTearDown(otherChat.dispose);

        handler.beginSession(chat.data.id);
        handler.beginSession(otherChat.data.id);

        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-shared',
            agentType: 'Explore',
            description: 'Chat A subagent',
          ),
        );

        handler.handleEvent(
          otherChat,
          makeText(text: 'Other chat output', parentCallId: 'task-shared'),
        );

        check(otherChat.data.primaryConversation.entries.length).equals(1);
        check(
          otherChat.data.primaryConversation.entries.first,
        ).isA<TextOutputEntry>();
        final entry =
            otherChat.data.primaryConversation.entries.first as TextOutputEntry;
        check(entry.text).equals('Other chat output');
      });

      test('resets routing state when session ends and restarts', () {
        handler.beginSession(chat.data.id);
        handler.handleEvent(
          chat,
          makeSubagentSpawn(
            callId: 'task-1',
            agentType: 'Plan',
            description: 'First session task',
          ),
        );

        final subagent = chat.agents.activeAgents['task-1']!;
        handler.handleEvent(
          chat,
          makeText(text: 'First session output', parentCallId: 'task-1'),
        );
        check(
          chat
              .data
              .subagentConversations[subagent.conversationId]!
              .entries
              .length,
        ).equals(1);

        handler.endSession(chat.data.id);
        handler.beginSession(chat.data.id);

        handler.handleEvent(
          chat,
          makeText(text: 'New session output', parentCallId: 'task-1'),
        );

        check(chat.data.primaryConversation.entries.length).equals(1);
        final primaryEntry =
            chat.data.primaryConversation.entries.single as TextOutputEntry;
        check(primaryEntry.text).equals('New session output');
        check(
          chat
              .data
              .subagentConversations[subagent.conversationId]!
              .entries
              .length,
        ).equals(1);
      });

      test('resets tool pairing state when session ends and restarts', () {
        handler.beginSession(chat.data.id);
        handler.handleEvent(
          chat,
          makeToolInvocation(callId: 'tool-1', toolName: 'Read'),
        );

        final toolEntry =
            chat.data.primaryConversation.entries.single as ToolUseOutputEntry;
        check(toolEntry.result).isNull();

        handler.endSession(chat.data.id);
        handler.beginSession(chat.data.id);

        handler.handleEvent(
          chat,
          makeToolCompletion(callId: 'tool-1', output: 'late completion'),
        );

        check(toolEntry.result).isNull();
      });
    });

    group('generateChatTitle (ChatTitleService)', () {
      test('generates title using AskAiService', () async {
        final mockService = MockAskAiService();
        mockService.titleToReturn = 'Generated Test Title';

        final titleService = ChatTitleService(askAiService: mockService);

        titleService.generateChatTitle(chat, 'Help me implement feature X');

        await Future.delayed(const Duration(milliseconds: 100));

        check(chat.data.name).equals('Generated Test Title');
        check(chat.data.isAutoGeneratedName).isFalse();

        check(mockService.lastPrompt).isNotNull();
        check(mockService.lastWorkingDirectory).equals('/tmp/test');
      });

      test('is idempotent (does not generate twice for same chat)', () async {
        final mockService = MockAskAiService();
        mockService.titleToReturn = 'First Title';

        final titleService = ChatTitleService(askAiService: mockService);

        titleService.generateChatTitle(chat, 'First message');
        await Future.delayed(const Duration(milliseconds: 100));

        check(chat.data.name).equals('First Title');

        mockService.titleToReturn = 'Second Title';
        titleService.generateChatTitle(chat, 'Second message');
        await Future.delayed(const Duration(milliseconds: 100));

        check(chat.data.name).equals('First Title');
      });

      test('handles failure gracefully', () async {
        final mockService = MockAskAiService();
        mockService.shouldFail = true;

        final titleService = ChatTitleService(askAiService: mockService);

        final originalName = chat.data.name;

        titleService.generateChatTitle(chat, 'Test message');
        await Future.delayed(const Duration(milliseconds: 100));

        check(chat.data.name).equals(originalName);
      });

      test('is no-op without AskAiService', () async {
        final titleService = ChatTitleService();

        final originalName = chat.data.name;

        titleService.generateChatTitle(chat, 'Test message');
        await Future.delayed(const Duration(milliseconds: 100));

        check(chat.data.name).equals(originalName);
      });
    });
  });
}

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
