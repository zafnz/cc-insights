import 'package:acp_dart/acp_dart.dart';
import 'package:cc_insights_v2/acp/session_update_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionUpdateHandler', () {
    test('routes AgentMessageChunk to onAgentMessage callback', () {
      // Arrange
      String? received;
      final handler = SessionUpdateHandler(
        onAgentMessage: (text) => received = text,
      );

      // Act
      handler.handleUpdate(AgentMessageChunkSessionUpdate(
        content: TextContentBlock(text: 'Hello'),
      ));

      // Assert
      expect(received, equals('Hello'));
    });

    test('routes AgentThoughtChunk to onThinkingMessage callback', () {
      // Arrange
      String? received;
      final handler = SessionUpdateHandler(
        onThinkingMessage: (text) => received = text,
      );

      // Act
      handler.handleUpdate(AgentThoughtChunkSessionUpdate(
        content: TextContentBlock(text: 'Thinking...'),
      ));

      // Assert
      expect(received, equals('Thinking...'));
    });

    test('creates ToolCallInfo for ToolCall update', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Read',
        status: ToolCallStatus.pending,
      ));

      // Assert
      expect(received?.toolCallId, equals('tc1'));
      expect(received?.title, equals('Read'));
      expect(received?.status, equals(ToolCallStatus.pending));
    });

    test('identifies Task tool as isTaskTool', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Task',
        status: ToolCallStatus.pending,
        rawInput: {'subagent_type': 'explore'},
      ));

      // Assert
      expect(received?.isTaskTool, isTrue);
    });

    test('identifies tool with agent in title as isTaskTool', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'SubAgent Runner',
        status: ToolCallStatus.pending,
      ));

      // Assert
      expect(received?.isTaskTool, isTrue);
    });

    test('identifies tool with subagent_type in rawInput as isTaskTool', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Execute',
        status: ToolCallStatus.pending,
        rawInput: {'subagent_type': 'researcher'},
      ));

      // Assert
      expect(received?.isTaskTool, isTrue);
    });

    test('regular tool is not isTaskTool', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Read',
        status: ToolCallStatus.pending,
      ));

      // Assert
      expect(received?.isTaskTool, isFalse);
    });

    test('routes ToolCallUpdate correctly', () {
      // Arrange
      ToolCallUpdateInfo? received;
      final handler = SessionUpdateHandler(
        onToolCallUpdate: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallUpdateSessionUpdate(
        toolCallId: 'tc1',
        status: ToolCallStatus.completed,
      ));

      // Assert
      expect(received?.toolCallId, equals('tc1'));
      expect(received?.status, equals(ToolCallStatus.completed));
    });

    test('routes PlanSessionUpdate correctly', () {
      // Arrange
      List<PlanEntry>? received;
      final handler = SessionUpdateHandler(
        onPlan: (entries) => received = entries,
      );

      // Act
      handler.handleUpdate(PlanSessionUpdate(
        entries: [
          PlanEntry(
            content: 'Test task',
            priority: PlanEntryPriority.medium,
            status: PlanEntryStatus.pending,
          ),
          PlanEntry(
            content: 'Another task',
            priority: PlanEntryPriority.high,
            status: PlanEntryStatus.inProgress,
          ),
        ],
      ));

      // Assert
      expect(received, isNotNull);
      final entries = received!;
      expect(entries.length, 2);
      expect(entries[0].content, 'Test task');
      expect(entries[0].priority, PlanEntryPriority.medium);
      expect(entries[0].status, PlanEntryStatus.pending);
      expect(entries[1].content, 'Another task');
      expect(entries[1].priority, PlanEntryPriority.high);
      expect(entries[1].status, PlanEntryStatus.inProgress);
    });

    test('routes mode change correctly', () {
      // Arrange
      String? received;
      final handler = SessionUpdateHandler(
        onModeChange: (modeId) => received = modeId,
      );

      // Act
      handler.handleUpdate(CurrentModeUpdateSessionUpdate(
        currentModeId: 'code',
      ));

      // Assert
      expect(received, equals('code'));
    });

    test('routes user message correctly', () {
      // Arrange
      String? received;
      final handler = SessionUpdateHandler(
        onUserMessage: (text) => received = text,
      );

      // Act
      handler.handleUpdate(UserMessageChunkSessionUpdate(
        content: TextContentBlock(text: 'User said this'),
      ));

      // Assert
      expect(received, equals('User said this'));
    });

    test('routes available commands correctly', () {
      // Arrange
      List<AvailableCommand>? received;
      final handler = SessionUpdateHandler(
        onCommands: (commands) => received = commands,
      );

      // Act
      handler.handleUpdate(AvailableCommandsUpdateSessionUpdate(
        availableCommands: [
          AvailableCommand(name: '/help', description: 'Show help'),
          AvailableCommand(name: '/clear', description: 'Clear history'),
        ],
      ));

      // Assert
      expect(received, isNotNull);
      final commands = received!;
      expect(commands.length, 2);
      expect(commands[0].name, '/help');
      expect(commands[0].description, 'Show help');
      expect(commands[1].name, '/clear');
    });

    test('can register and retrieve tool call conversation mapping', () {
      // Arrange
      final handler = SessionUpdateHandler();

      // Act
      handler.registerToolCallConversation('tc1', 'conv1');

      // Assert
      expect(handler.getConversationForToolCall('tc1'), equals('conv1'));
    });

    test('returns null for unregistered tool call conversation', () {
      // Arrange
      final handler = SessionUpdateHandler();

      // Assert
      expect(handler.getConversationForToolCall('tc1'), isNull);
    });

    test('can unregister tool call conversation mapping', () {
      // Arrange
      final handler = SessionUpdateHandler();
      handler.registerToolCallConversation('tc1', 'conv1');

      // Act
      handler.unregisterToolCallConversation('tc1');

      // Assert
      expect(handler.getConversationForToolCall('tc1'), isNull);
    });

    test('can clear all conversation mappings', () {
      // Arrange
      final handler = SessionUpdateHandler();
      handler.registerToolCallConversation('tc1', 'conv1');
      handler.registerToolCallConversation('tc2', 'conv2');
      handler.registerToolCallConversation('tc3', 'conv3');

      // Act
      handler.clearConversationMappings();

      // Assert
      expect(handler.getConversationForToolCall('tc1'), isNull);
      expect(handler.getConversationForToolCall('tc2'), isNull);
      expect(handler.getConversationForToolCall('tc3'), isNull);
    });

    test('ignores updates when no callback is registered', () {
      // Arrange - handler with no callbacks
      final handler = SessionUpdateHandler();

      // Act - should not throw
      handler.handleUpdate(AgentMessageChunkSessionUpdate(
        content: TextContentBlock(text: 'Hello'),
      ));
      handler.handleUpdate(AgentThoughtChunkSessionUpdate(
        content: TextContentBlock(text: 'Thinking'),
      ));
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Read',
        status: ToolCallStatus.pending,
      ));
      handler.handleUpdate(ToolCallUpdateSessionUpdate(
        toolCallId: 'tc1',
        status: ToolCallStatus.completed,
      ));
      handler.handleUpdate(PlanSessionUpdate(entries: []));
      handler.handleUpdate(CurrentModeUpdateSessionUpdate(currentModeId: 'code'));

      // Assert - no exceptions thrown
      expect(true, isTrue);
    });

    test('multiple registrations overwrite previous mapping', () {
      // Arrange
      final handler = SessionUpdateHandler();
      handler.registerToolCallConversation('tc1', 'conv1');

      // Act
      handler.registerToolCallConversation('tc1', 'conv2');

      // Assert
      expect(handler.getConversationForToolCall('tc1'), equals('conv2'));
    });

    test('ToolCallInfo includes all fields from update', () {
      // Arrange
      ToolCallInfo? received;
      final handler = SessionUpdateHandler(
        onToolCall: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallSessionUpdate(
        toolCallId: 'tc1',
        title: 'Edit',
        status: ToolCallStatus.inProgress,
        kind: ToolKind.edit,
        rawInput: {'file': 'test.txt', 'content': 'hello'},
      ));

      // Assert
      expect(received, isNotNull);
      final info = received!;
      expect(info.toolCallId, equals('tc1'));
      expect(info.title, equals('Edit'));
      expect(info.status, equals(ToolCallStatus.inProgress));
      expect(info.kind, equals(ToolKind.edit));
      expect(info.rawInput, isNotNull);
      expect(info.rawInput!['file'], equals('test.txt'));
      expect(info.isTaskTool, isFalse);
    });

    test('ToolCallUpdateInfo includes all fields from update', () {
      // Arrange
      ToolCallUpdateInfo? received;
      final handler = SessionUpdateHandler(
        onToolCallUpdate: (info) => received = info,
      );

      // Act
      handler.handleUpdate(ToolCallUpdateSessionUpdate(
        toolCallId: 'tc1',
        status: ToolCallStatus.completed,
        title: 'Updated Title',
        kind: ToolKind.read,
        rawOutput: {'result': 'success'},
      ));

      // Assert
      expect(received, isNotNull);
      final updateInfo = received!;
      expect(updateInfo.toolCallId, equals('tc1'));
      expect(updateInfo.status, equals(ToolCallStatus.completed));
      expect(updateInfo.title, equals('Updated Title'));
      expect(updateInfo.kind, equals(ToolKind.read));
      expect(updateInfo.rawOutput, isNotNull);
      expect(updateInfo.rawOutput!['result'], equals('success'));
    });
  });
}
