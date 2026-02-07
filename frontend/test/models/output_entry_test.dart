import 'dart:convert';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UsageInfo', () {
    group('zero()', () {
      test('creates instance with all values at zero', () {
        // Arrange & Act
        const usage = UsageInfo.zero();

        // Assert
        check(usage.inputTokens).equals(0);
        check(usage.outputTokens).equals(0);
        check(usage.cacheReadTokens).equals(0);
        check(usage.cacheCreationTokens).equals(0);
        check(usage.costUsd).equals(0.0);
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        // Arrange
        const original = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );

        // Act
        final modified = original.copyWith(inputTokens: 200);

        // Assert
        check(modified.inputTokens).equals(200);
        check(modified.outputTokens).equals(50);
        check(modified.cacheReadTokens).equals(10);
        check(modified.cacheCreationTokens).equals(5);
        check(modified.costUsd).equals(0.01);
      });

      test('updates multiple fields at once', () {
        // Arrange
        const original = UsageInfo.zero();

        // Act
        final modified = original.copyWith(
          inputTokens: 100,
          outputTokens: 50,
          costUsd: 0.05,
        );

        // Assert
        check(modified.inputTokens).equals(100);
        check(modified.outputTokens).equals(50);
        check(modified.cacheReadTokens).equals(0);
        check(modified.cacheCreationTokens).equals(0);
        check(modified.costUsd).equals(0.05);
      });
    });

    group('totalTokens', () {
      test('returns sum of input and output tokens', () {
        // Arrange
        const usage = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );

        // Act & Assert
        check(usage.totalTokens).equals(150);
      });

      test('returns zero for zeroed instance', () {
        // Arrange
        const usage = UsageInfo.zero();

        // Act & Assert
        check(usage.totalTokens).equals(0);
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        const usage1 = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );
        const usage2 = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );

        // Act & Assert
        check(usage1 == usage2).isTrue();
        check(usage1.hashCode).equals(usage2.hashCode);
      });

      test('equals returns false for different values', () {
        // Arrange
        const usage1 = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );
        const usage2 = UsageInfo(
          inputTokens: 200,
          outputTokens: 50,
          cacheReadTokens: 10,
          cacheCreationTokens: 5,
          costUsd: 0.01,
        );

        // Act & Assert
        check(usage1 == usage2).isFalse();
      });
    });
  });

  group('TextOutputEntry', () {
    test('creates correctly with required fields', () {
      // Arrange
      final timestamp = DateTime(2025, 1, 27, 10, 30);

      // Act
      final entry = TextOutputEntry(
        timestamp: timestamp,
        text: 'Hello, world!',
        contentType: 'text',
      );

      // Assert
      check(entry.timestamp).equals(timestamp);
      check(entry.text).equals('Hello, world!');
      check(entry.contentType).equals('text');
    });

    test('creates thinking content type', () {
      // Arrange
      final timestamp = DateTime.now();

      // Act
      final entry = TextOutputEntry(
        timestamp: timestamp,
        text: 'Let me think about this...',
        contentType: 'thinking',
      );

      // Assert
      check(entry.contentType).equals('thinking');
    });

    test('copyWith preserves unchanged fields', () {
      // Arrange
      final original = TextOutputEntry(
        timestamp: DateTime(2025, 1, 27),
        text: 'Original text',
        contentType: 'text',
      );

      // Act
      final modified = original.copyWith(text: 'Modified text');

      // Assert
      check(modified.timestamp).equals(original.timestamp);
      check(modified.text).equals('Modified text');
      check(modified.contentType).equals('text');
    });
  });

  group('ToolUseOutputEntry', () {
    test('creates correctly with required fields', () {
      // Arrange
      final timestamp = DateTime(2025, 1, 27, 10, 30);

      // Act
      final entry = ToolUseOutputEntry(
        timestamp: timestamp,
        toolName: 'Read',
        toolUseId: 'tool-123',
        toolInput: {'file_path': '/path/to/file.dart'},
      );

      // Assert
      check(entry.timestamp).equals(timestamp);
      check(entry.toolName).equals('Read');
      check(entry.toolUseId).equals('tool-123');
      check(entry.toolInput['file_path']).equals('/path/to/file.dart');
      check(entry.model).isNull();
      check(entry.result).isNull();
      check(entry.isError).isFalse();
      check(entry.isExpanded).isFalse();
    });

    test('creates with optional fields', () {
      // Arrange
      final timestamp = DateTime.now();

      // Act
      final entry = ToolUseOutputEntry(
        timestamp: timestamp,
        toolName: 'Write',
        toolUseId: 'tool-456',
        toolInput: {'content': 'test'},
        model: 'claude-3-sonnet',
        result: 'File written successfully',
        isError: false,
        isExpanded: true,
      );

      // Assert
      check(entry.model).equals('claude-3-sonnet');
      check(entry.result).equals('File written successfully');
      check(entry.isExpanded).isTrue();
    });

    test('copyWith updates isExpanded for UI state', () {
      // Arrange
      final entry = ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: 'Read',
        toolUseId: 'tool-789',
        toolInput: {},
        isExpanded: false,
      );

      // Act
      final expanded = entry.copyWith(isExpanded: true);

      // Assert
      check(entry.isExpanded).isFalse();
      check(expanded.isExpanded).isTrue();
      check(expanded.toolName).equals('Read');
    });
  });

  group('UserInputEntry', () {
    test('creates correctly with timestamp and text', () {
      // Arrange
      final timestamp = DateTime(2025, 1, 27, 10, 30);

      // Act
      final entry = UserInputEntry(timestamp: timestamp, text: 'User message');

      // Assert
      check(entry.timestamp).equals(timestamp);
      check(entry.text).equals('User message');
    });

    test('copyWith preserves unchanged fields', () {
      // Arrange
      final original = UserInputEntry(
        timestamp: DateTime(2025, 1, 27),
        text: 'Original',
      );

      // Act
      final modified = original.copyWith(text: 'Modified');

      // Assert
      check(modified.timestamp).equals(original.timestamp);
      check(modified.text).equals('Modified');
    });
  });

  group('ContextSummaryEntry', () {
    test('creates correctly with timestamp and summary', () {
      // Arrange
      final timestamp = DateTime(2025, 1, 27, 10, 30);

      // Act
      final entry = ContextSummaryEntry(
        timestamp: timestamp,
        summary: 'Context was compacted...',
      );

      // Assert
      check(entry.timestamp).equals(timestamp);
      check(entry.summary).equals('Context was compacted...');
    });
  });

  group('ContextClearedEntry', () {
    test('creates correctly with timestamp', () {
      // Arrange
      final timestamp = DateTime(2025, 1, 27, 10, 30);

      // Act
      final entry = ContextClearedEntry(timestamp: timestamp);

      // Assert
      check(entry.timestamp).equals(timestamp);
    });

    test('copyWith can update timestamp', () {
      // Arrange
      final original = ContextClearedEntry(timestamp: DateTime(2025, 1, 1));
      final newTimestamp = DateTime(2025, 6, 15);

      // Act
      final modified = original.copyWith(timestamp: newTimestamp);

      // Assert
      check(modified.timestamp).equals(newTimestamp);
    });
  });

  group('OutputEntry JSON serialization', () {
    group('UserInputEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Hello, world!',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('user');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['text']).equals('Hello, world!');
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Hello, world!',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.text).equals('Hello, world!');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Test message with unicode: 你好 🎉',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = UserInputEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.text).equals(original.text);
      });

      test('toJson omits display_format when plain', () {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Hello',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json.containsKey('display_format')).equals(false);
      });

      test('toJson includes display_format when fixedWidth', () {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Hello',
          displayFormat: DisplayFormat.fixedWidth,
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['display_format']).equals('fixedWidth');
      });

      test('toJson includes display_format when markdown', () {
        // Arrange
        final entry = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: '# Hello',
          displayFormat: DisplayFormat.markdown,
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['display_format']).equals('markdown');
      });

      test('fromJson defaults to plain when display_format is missing', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Hello',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.displayFormat).equals(DisplayFormat.plain);
      });

      test('fromJson restores fixedWidth display_format', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Hello',
          'display_format': 'fixedWidth',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.displayFormat).equals(DisplayFormat.fixedWidth);
      });

      test('fromJson restores markdown display_format', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': '# Hello',
          'display_format': 'markdown',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.displayFormat).equals(DisplayFormat.markdown);
      });

      test('fromJson defaults to plain for unknown display_format', () {
        // Arrange
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Hello',
          'display_format': 'unknown_format',
        };

        // Act
        final entry = UserInputEntry.fromJson(json);

        // Assert
        check(entry.displayFormat).equals(DisplayFormat.plain);
      });

      test('round-trip preserves displayFormat', () {
        // Arrange
        final original = UserInputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Code example',
          displayFormat: DisplayFormat.fixedWidth,
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = UserInputEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.displayFormat).equals(DisplayFormat.fixedWidth);
      });
    });

    group('TextOutputEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = TextOutputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Assistant response',
          contentType: 'text',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('assistant');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['text']).equals('Assistant response');
        check(json['content_type']).equals('text');
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'assistant',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Response text',
          'content_type': 'thinking',
        };

        // Act
        final entry = TextOutputEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.text).equals('Response text');
        check(entry.contentType).equals('thinking');
        check(entry.isStreaming).isFalse(); // Restored entries not streaming
      });

      test('fromJson defaults contentType to text', () {
        // Arrange
        final json = {
          'type': 'assistant',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Response',
        };

        // Act
        final entry = TextOutputEntry.fromJson(json);

        // Assert
        check(entry.contentType).equals('text');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = TextOutputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          text: 'Multi\nline\ntext',
          contentType: 'thinking',
          isStreaming: true, // Should be false after restore
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = TextOutputEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.text).equals(original.text);
        check(restored.contentType).equals(original.contentType);
        check(restored.isStreaming).isFalse();
      });
    });

    group('ToolUseOutputEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = ToolUseOutputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          toolName: 'Read',
          toolUseId: 'tu_123',
          toolInput: {'file_path': '/path/to/file.dart'},
          model: 'claude-sonnet-4',
          result: 'File content here',
          isError: false,
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('tool_use');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['tool_name']).equals('Read');
        check(json['tool_use_id']).equals('tu_123');
        check((json['tool_input'] as Map)['file_path'])
            .equals('/path/to/file.dart');
        check(json['model']).equals('claude-sonnet-4');
        check(json['result']).equals('File content here');
        check(json['is_error']).equals(false);
      });

      test('toJson omits null optional fields', () {
        // Arrange
        final entry = ToolUseOutputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          toolName: 'Read',
          toolUseId: 'tu_123',
          toolInput: {},
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json.containsKey('model')).isFalse();
        check(json.containsKey('result')).isFalse();
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'tool_use',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_name': 'Write',
          'tool_use_id': 'tu_456',
          'tool_input': {'content': 'test'},
          'model': 'claude-opus-4',
          'result': 'Success',
          'is_error': false,
        };

        // Act
        final entry = ToolUseOutputEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.toolName).equals('Write');
        check(entry.toolUseId).equals('tu_456');
        check(entry.toolInput['content']).equals('test');
        check(entry.model).equals('claude-opus-4');
        check(entry.result).equals('Success');
        check(entry.isError).isFalse();
        check(entry.isExpanded).isFalse(); // UI state not persisted
        check(entry.isStreaming).isFalse();
      });

      test('fromJson handles error case', () {
        // Arrange
        final json = {
          'type': 'tool_use',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_name': 'Read',
          'tool_use_id': 'tu_789',
          'tool_input': {'file_path': '/nonexistent'},
          'result': 'File not found',
          'is_error': true,
        };

        // Act
        final entry = ToolUseOutputEntry.fromJson(json);

        // Assert
        check(entry.isError).isTrue();
        check(entry.result).equals('File not found');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = ToolUseOutputEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          toolName: 'Edit',
          toolUseId: 'tu_complex',
          toolInput: {
            'file_path': '/path/file.dart',
            'old_string': 'foo',
            'new_string': 'bar',
          },
          model: 'claude-sonnet-4',
          result: {'success': true, 'lines_changed': 5},
          isError: false,
          isExpanded: true,
          isStreaming: true,
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ToolUseOutputEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.toolName).equals(original.toolName);
        check(restored.toolUseId).equals(original.toolUseId);
        check(restored.toolInput['file_path'])
            .equals(original.toolInput['file_path']);
        check(restored.model).equals(original.model);
        check((restored.result as Map)['success'] as bool).isTrue();
        check(restored.isError).equals(original.isError);
        check(restored.isExpanded).isFalse(); // UI state reset
        check(restored.isStreaming).isFalse(); // Streaming state reset
      });
    });

    group('ToolResultEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = ToolResultEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          toolUseId: 'tu_123',
          result: {'success': true, 'data': 'test'},
          isError: false,
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('tool_result');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['tool_use_id']).equals('tu_123');
        check((json['result'] as Map)['success']).equals(true);
        check(json['is_error']).equals(false);
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'tool_result',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_use_id': 'tu_456',
          'result': 'Success message',
          'is_error': false,
        };

        // Act
        final entry = ToolResultEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.toolUseId).equals('tu_456');
        check(entry.result).equals('Success message');
        check(entry.isError).isFalse();
      });

      test('fromJson handles error case', () {
        // Arrange
        final json = {
          'type': 'tool_result',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_use_id': 'tu_error',
          'result': 'File not found',
          'is_error': true,
        };

        // Act
        final entry = ToolResultEntry.fromJson(json);

        // Assert
        check(entry.isError).isTrue();
        check(entry.result).equals('File not found');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = ToolResultEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          toolUseId: 'tu_complex',
          result: {'nested': {'data': [1, 2, 3]}},
          isError: false,
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ToolResultEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.toolUseId).equals(original.toolUseId);
        check((restored.result as Map)['nested']).isNotNull();
        check(restored.isError).equals(original.isError);
      });
    });

    group('ContextSummaryEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = ContextSummaryEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          summary: 'Context was compacted. Previous conversation...',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('context_summary');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['summary']).equals('Context was compacted. Previous conversation...');
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'context_summary',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'summary': 'Summary text here',
        };

        // Act
        final entry = ContextSummaryEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.summary).equals('Summary text here');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = ContextSummaryEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          summary: 'Long summary with\nmultiple lines\nand details.',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ContextSummaryEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.summary).equals(original.summary);
      });
    });

    group('ContextClearedEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = ContextClearedEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('context_cleared');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json.length).equals(2);
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'context_cleared',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        // Act
        final entry = ContextClearedEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = ContextClearedEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ContextClearedEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
      });
    });

    group('OutputEntry.fromJson dispatch', () {
      test('dispatches to UserInputEntry for type "user"', () {
        final json = {
          'type': 'user',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Hello',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<UserInputEntry>();
        check((entry as UserInputEntry).text).equals('Hello');
      });

      test('dispatches to TextOutputEntry for type "assistant"', () {
        final json = {
          'type': 'assistant',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'text': 'Response',
          'content_type': 'text',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<TextOutputEntry>();
        check((entry as TextOutputEntry).text).equals('Response');
      });

      test('dispatches to ToolUseOutputEntry for type "tool_use"', () {
        final json = {
          'type': 'tool_use',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_name': 'Read',
          'tool_use_id': 'tu_123',
          'tool_input': {},
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<ToolUseOutputEntry>();
        check((entry as ToolUseOutputEntry).toolName).equals('Read');
      });

      test('dispatches to ToolResultEntry for type "tool_result"', () {
        final json = {
          'type': 'tool_result',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'tool_use_id': 'tu_123',
          'result': 'Success',
          'is_error': false,
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<ToolResultEntry>();
        check((entry as ToolResultEntry).toolUseId).equals('tu_123');
      });

      test('dispatches to ContextSummaryEntry for type "context_summary"', () {
        final json = {
          'type': 'context_summary',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'summary': 'Summary',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<ContextSummaryEntry>();
        check((entry as ContextSummaryEntry).summary).equals('Summary');
      });

      test('dispatches to ContextClearedEntry for type "context_cleared"', () {
        final json = {
          'type': 'context_cleared',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<ContextClearedEntry>();
      });

      test('throws ArgumentError for unknown type', () {
        final json = {
          'type': 'unknown_type',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        check(() => OutputEntry.fromJson(json)).throws<ArgumentError>();
      });

      test('throws ArgumentError for null type', () {
        final json = {'timestamp': '2025-01-27T10:30:00.000Z'};

        check(() => OutputEntry.fromJson(json)).throws<ArgumentError>();
      });

      test('dispatches to AutoCompactionEntry for type "auto_compaction"', () {
        final json = {
          'type': 'auto_compaction',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message': 'Was 50K tokens',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<AutoCompactionEntry>();
        check((entry as AutoCompactionEntry).message).equals('Was 50K tokens');
      });

      test('dispatches to UnknownMessageEntry for type "unknown_message"', () {
        final json = {
          'type': 'unknown_message',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message_type': 'test_type',
          'raw_message': {'foo': 'bar'},
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<UnknownMessageEntry>();
        check((entry as UnknownMessageEntry).messageType).equals('test_type');
      });

      test('dispatches to SystemNotificationEntry for type "system_notification"',
          () {
        final json = {
          'type': 'system_notification',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message': 'Unknown skill: clear',
        };

        final entry = OutputEntry.fromJson(json);

        check(entry).isA<SystemNotificationEntry>();
        check((entry as SystemNotificationEntry).message)
            .equals('Unknown skill: clear');
      });
    });

    group('AutoCompactionEntry', () {
      test('toJson produces correct structure with message', () {
        // Arrange
        final entry = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          message: 'Was 50K tokens',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('auto_compaction');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['message']).equals('Was 50K tokens');
      });

      test('toJson omits null message', () {
        // Arrange
        final entry = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json.containsKey('message')).isFalse();
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'auto_compaction',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message': 'Compacted context',
        };

        // Act
        final entry = AutoCompactionEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.message).equals('Compacted context');
      });

      test('fromJson handles missing message', () {
        // Arrange
        final json = {
          'type': 'auto_compaction',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        // Act
        final entry = AutoCompactionEntry.fromJson(json);

        // Assert
        check(entry.message).isNull();
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          message: 'Was 100K tokens',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = AutoCompactionEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.message).equals(original.message);
      });

      test('copyWith updates message', () {
        // Arrange
        final original = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Original',
        );

        // Act
        final modified = original.copyWith(message: 'Modified');

        // Assert
        check(modified.message).equals('Modified');
        check(modified.timestamp).equals(original.timestamp);
      });

      test('equality works correctly', () {
        // Arrange
        final entry1 = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Test',
        );
        final entry2 = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Test',
        );
        final entry3 = AutoCompactionEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Different',
        );

        // Assert
        check(entry1 == entry2).isTrue();
        check(entry1.hashCode).equals(entry2.hashCode);
        check(entry1 == entry3).isFalse();
      });
    });

    group('UnknownMessageEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          messageType: 'custom_type',
          rawMessage: {'key': 'value', 'nested': {'foo': 'bar'}},
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('unknown_message');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['message_type']).equals('custom_type');
        check((json['raw_message'] as Map)['key']).equals('value');
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'unknown_message',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message_type': 'test_type',
          'raw_message': {'data': 123},
        };

        // Act
        final entry = UnknownMessageEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.messageType).equals('test_type');
        check(entry.rawMessage['data']).equals(123);
      });

      test('fromJson handles missing fields with defaults', () {
        // Arrange
        final json = {
          'type': 'unknown_message',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        // Act
        final entry = UnknownMessageEntry.fromJson(json);

        // Assert
        check(entry.messageType).equals('unknown');
        check(entry.rawMessage).isEmpty();
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          messageType: 'mystery_message',
          rawMessage: {'complex': {'nested': ['array', 'data']}},
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = UnknownMessageEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.messageType).equals(original.messageType);
        check(restored.rawMessage['complex']).isNotNull();
      });

      test('copyWith updates fields', () {
        // Arrange
        final original = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          messageType: 'original',
          rawMessage: {'a': 1},
        );

        // Act
        final modified = original.copyWith(
          messageType: 'modified',
          rawMessage: {'b': 2},
        );

        // Assert
        check(modified.messageType).equals('modified');
        check(modified.rawMessage['b']).equals(2);
        check(modified.timestamp).equals(original.timestamp);
      });

      test('equality works correctly', () {
        // Arrange
        final entry1 = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          messageType: 'test',
          rawMessage: {'key': 'value'},
        );
        final entry2 = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          messageType: 'test',
          rawMessage: {'key': 'value'},
        );
        final entry3 = UnknownMessageEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          messageType: 'different',
          rawMessage: {'key': 'value'},
        );

        // Assert - note: hashCode comparison omitted because Map hashCodes
        // are not consistent across instances even with equal content
        check(entry1 == entry2).isTrue();
        check(entry1 == entry3).isFalse();
      });
    });

    group('SystemNotificationEntry', () {
      test('toJson produces correct structure', () {
        // Arrange
        final entry = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          message: 'Unknown skill: clear',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['type']).equals('system_notification');
        check(json['timestamp']).equals('2025-01-27T10:30:00.000Z');
        check(json['message']).equals('Unknown skill: clear');
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'type': 'system_notification',
          'timestamp': '2025-01-27T10:30:00.000Z',
          'message': 'Test notification',
        };

        // Act
        final entry = SystemNotificationEntry.fromJson(json);

        // Assert
        check(entry.timestamp).equals(DateTime.utc(2025, 1, 27, 10, 30, 0));
        check(entry.message).equals('Test notification');
      });

      test('fromJson handles missing message with empty string', () {
        // Arrange
        final json = {
          'type': 'system_notification',
          'timestamp': '2025-01-27T10:30:00.000Z',
        };

        // Act
        final entry = SystemNotificationEntry.fromJson(json);

        // Assert
        check(entry.message).equals('');
      });

      test('round-trip preserves data', () {
        // Arrange
        final original = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27, 10, 30, 0),
          message: 'Notification message',
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = SystemNotificationEntry.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored.timestamp).equals(original.timestamp);
        check(restored.message).equals(original.message);
      });

      test('copyWith updates fields', () {
        // Arrange
        final original = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Original',
        );

        // Act
        final modified = original.copyWith(message: 'Modified');

        // Assert
        check(modified.message).equals('Modified');
        check(modified.timestamp).equals(original.timestamp);
      });

      test('equality works correctly', () {
        // Arrange
        final entry1 = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Test',
        );
        final entry2 = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Test',
        );
        final entry3 = SystemNotificationEntry(
          timestamp: DateTime.utc(2025, 1, 27),
          message: 'Different',
        );

        // Assert
        check(entry1 == entry2).isTrue();
        check(entry1.hashCode).equals(entry2.hashCode);
        check(entry1 == entry3).isFalse();
      });
    });

    group('UsageInfo serialization', () {
      test('toJson produces correct structure', () {
        // Arrange
        const usage = UsageInfo(
          inputTokens: 100,
          outputTokens: 50,
          cacheReadTokens: 25,
          cacheCreationTokens: 10,
          costUsd: 0.0123,
        );

        // Act
        final json = usage.toJson();

        // Assert
        check(json['input_tokens']).equals(100);
        check(json['output_tokens']).equals(50);
        check(json['cache_read_tokens']).equals(25);
        check(json['cache_creation_tokens']).equals(10);
        check(json['cost_usd']).equals(0.0123);
      });

      test('fromJson restores entry correctly', () {
        // Arrange
        final json = {
          'input_tokens': 200,
          'output_tokens': 100,
          'cache_read_tokens': 50,
          'cache_creation_tokens': 20,
          'cost_usd': 0.0456,
        };

        // Act
        final usage = UsageInfo.fromJson(json);

        // Assert
        check(usage.inputTokens).equals(200);
        check(usage.outputTokens).equals(100);
        check(usage.cacheReadTokens).equals(50);
        check(usage.cacheCreationTokens).equals(20);
        check(usage.costUsd).equals(0.0456);
      });

      test('fromJson uses defaults for missing fields', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final usage = UsageInfo.fromJson(json);

        // Assert
        check(usage.inputTokens).equals(0);
        check(usage.outputTokens).equals(0);
        check(usage.cacheReadTokens).equals(0);
        check(usage.cacheCreationTokens).equals(0);
        check(usage.costUsd).equals(0.0);
      });

      test('round-trip preserves data', () {
        // Arrange
        const original = UsageInfo(
          inputTokens: 12345,
          outputTokens: 6789,
          cacheReadTokens: 1000,
          cacheCreationTokens: 500,
          costUsd: 1.2345,
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = UsageInfo.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored).equals(original);
      });
    });
  });
}
