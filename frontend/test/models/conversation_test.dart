import 'package:cc_insights_v2/models/conversation.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversationData', () {
    group('isPrimary', () {
      test('returns true when label is null', () {
        // Arrange
        final conversation = ConversationData.primary(id: 'conv-1');

        // Act & Assert
        check(conversation.isPrimary).isTrue();
        check(conversation.label).isNull();
      });

      test('returns false for subagent conversations', () {
        // Arrange
        final conversation = ConversationData.subagent(
          id: 'conv-2',
          label: 'Explore',
          taskDescription: 'Find all test files',
        );

        // Act & Assert
        check(conversation.isPrimary).isFalse();
        check(conversation.label).equals('Explore');
      });
    });

    group('primary() factory', () {
      test('creates empty primary conversation', () {
        // Arrange & Act
        final conversation = ConversationData.primary(id: 'conv-primary');

        // Assert
        check(conversation.id).equals('conv-primary');
        check(conversation.label).isNull();
        check(conversation.taskDescription).isNull();
        check(conversation.entries).isEmpty();
        check(conversation.totalUsage.totalTokens).equals(0);
      });
    });

    group('subagent() factory', () {
      test('creates subagent conversation with label', () {
        // Arrange & Act
        final conversation = ConversationData.subagent(
          id: 'conv-subagent',
          label: 'Plan',
          taskDescription: 'Create implementation plan',
        );

        // Assert
        check(conversation.id).equals('conv-subagent');
        check(conversation.label).equals('Plan');
        check(
          conversation.taskDescription,
        ).equals('Create implementation plan');
        check(conversation.entries).isEmpty();
        check(conversation.totalUsage.totalTokens).equals(0);
      });

      test('creates subagent conversation without task description', () {
        // Arrange & Act
        final conversation = ConversationData.subagent(
          id: 'conv-subagent',
          label: 'Research',
        );

        // Assert
        check(conversation.label).equals('Research');
        check(conversation.taskDescription).isNull();
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        // Arrange
        final original = ConversationData.primary(id: 'conv-1');

        // Act
        final modified = original.copyWith(
          entries: [UserInputEntry(timestamp: DateTime.now(), text: 'Hello')],
        );

        // Assert
        check(modified.id).equals('conv-1');
        check(modified.label).isNull();
        check(modified.entries.length).equals(1);
      });

      test('updates totalUsage', () {
        // Arrange
        final original = ConversationData.primary(id: 'conv-1');
        const newUsage = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.01,
        );

        // Act
        final modified = original.copyWith(totalUsage: newUsage);

        // Assert
        check(modified.totalUsage.inputTokens).equals(100);
        check(modified.totalUsage.outputTokens).equals(50);
        check(modified.totalUsage.costUsd).equals(0.01);
      });

      test('updates entries list', () {
        // Arrange
        final original = ConversationData.primary(id: 'conv-1');
        final entries = [
          UserInputEntry(timestamp: DateTime.now(), text: 'First'),
          TextOutputEntry(
            timestamp: DateTime.now(),
            text: 'Response',
            contentType: 'text',
          ),
        ];

        // Act
        final modified = original.copyWith(entries: entries);

        // Assert
        check(modified.entries.length).equals(2);
        check((modified.entries[0] as UserInputEntry).text).equals('First');
        check((modified.entries[1] as TextOutputEntry).text).equals('Response');
      });

      test('can change label for subagent', () {
        // Arrange
        final original = ConversationData.subagent(
          id: 'conv-1',
          label: 'Original',
        );

        // Act
        final modified = original.copyWith(label: 'Updated');

        // Assert
        check(modified.label).equals('Updated');
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        final conv1 = ConversationData.primary(id: 'conv-1');
        final conv2 = ConversationData.primary(id: 'conv-1');

        // Act & Assert
        check(conv1 == conv2).isTrue();
        check(conv1.hashCode).equals(conv2.hashCode);
      });

      test('equals returns false for different IDs', () {
        // Arrange
        final conv1 = ConversationData.primary(id: 'conv-1');
        final conv2 = ConversationData.primary(id: 'conv-2');

        // Act & Assert
        check(conv1 == conv2).isFalse();
      });

      test('equals returns false for different labels', () {
        // Arrange
        final conv1 = ConversationData.subagent(id: 'conv-1', label: 'A');
        final conv2 = ConversationData.subagent(id: 'conv-1', label: 'B');

        // Act & Assert
        check(conv1 == conv2).isFalse();
      });
    });

    group('toString()', () {
      test('includes key information', () {
        // Arrange
        final conversation = ConversationData.subagent(
          id: 'conv-123',
          label: 'Test',
          taskDescription: 'Task',
        );

        // Act
        final str = conversation.toString();

        // Assert
        check(str).contains('conv-123');
        check(str).contains('Test');
        check(str).contains('Task');
      });
    });
  });
}
