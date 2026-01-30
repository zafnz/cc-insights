import 'dart:io';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/testing/message_log_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageTransformer', () {
    late MessageTransformer transformer;

    setUp(() {
      transformer = MessageTransformer();
    });

    test('transforms assistant text message', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'assistant',
            'message': {
              'content': [
                {'type': 'text', 'text': 'Hello, world!'},
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, hasLength(1));
      expect(outputs[0], isA<TextOutputEntry>());
      expect((outputs[0] as TextOutputEntry).text, 'Hello, world!');
      expect((outputs[0] as TextOutputEntry).contentType, 'text');
    });

    test('transforms assistant thinking message', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'assistant',
            'message': {
              'content': [
                {'type': 'thinking', 'thinking': 'Let me think...'},
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, hasLength(1));
      expect(outputs[0], isA<TextOutputEntry>());
      expect((outputs[0] as TextOutputEntry).text, 'Let me think...');
      expect((outputs[0] as TextOutputEntry).contentType, 'thinking');
    });

    test('transforms assistant tool_use message', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'assistant',
            'message': {
              'model': 'claude-opus-4-5-20251101',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'tool_123',
                  'name': 'Read',
                  'input': {'file_path': '/tmp/test.txt'},
                },
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, hasLength(1));
      expect(outputs[0], isA<ToolUseOutputEntry>());
      final toolEntry = outputs[0] as ToolUseOutputEntry;
      expect(toolEntry.toolName, 'Read');
      expect(toolEntry.toolUseId, 'tool_123');
      expect(toolEntry.toolInput, {'file_path': '/tmp/test.txt'});
      expect(toolEntry.model, 'claude-opus-4-5-20251101');
    });

    test('transforms multiple content blocks', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'assistant',
            'message': {
              'content': [
                {'type': 'text', 'text': 'I will read the file.'},
                {
                  'type': 'tool_use',
                  'id': 'tool_456',
                  'name': 'Read',
                  'input': {'file_path': '/tmp/file.txt'},
                },
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, hasLength(2));
      expect(outputs[0], isA<TextOutputEntry>());
      expect(outputs[1], isA<ToolUseOutputEntry>());
    });

    test('transforms user message', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'user',
            'message': {
              'content': [
                {'type': 'text', 'text': 'Please help me.'},
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, hasLength(1));
      expect(outputs[0], isA<UserInputEntry>());
      expect((outputs[0] as UserInputEntry).text, 'Please help me.');
    });

    test('ignores non-sdk.message entries', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'session.created',
          'session_id': '123',
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, isEmpty);
    });

    test('ignores synthetic tool result messages', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        direction: 'OUT',
        message: {
          'type': 'sdk.message',
          'payload': {
            'type': 'user',
            'is_synthetic': true,
            'tool_use_result': {'tool_use_id': 'tool_123', 'result': 'ok'},
            'message': {
              'content': [
                {'type': 'tool_result', 'tool_use_id': 'tool_123'},
              ],
            },
          },
        },
      );

      final outputs = transformer.transform(entry);

      expect(outputs, isEmpty);
    });
  });

  group('LogEntry', () {
    test('parses from JSON', () {
      final json = {
        'timestamp': '2026-01-27T23:10:10.841Z',
        'direction': 'OUT',
        'message': {
          'type': 'sdk.message',
          'payload': {'type': 'assistant'},
        },
      };

      final entry = LogEntry.fromJson(json);

      expect(entry.direction, 'OUT');
      expect(entry.messageType, 'sdk.message');
      expect(entry.payloadType, 'assistant');
    });
  });

  group('MessageLogPlayer', () {
    test('loads and parses log file', () async {
      // Create a temp file with test data
      final tempDir = await Directory.systemTemp.createTemp('log_test');
      final tempFile = File('${tempDir.path}/test.jsonl');
      await tempFile.writeAsString('''
{"timestamp":"2026-01-27T23:10:10.000Z","direction":"OUT","message":{"type":"sdk.message","payload":{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}}}
{"timestamp":"2026-01-27T23:10:11.000Z","direction":"OUT","message":{"type":"sdk.message","payload":{"type":"user","message":{"content":[{"type":"text","text":"Hi there"}]}}}}
''');

      try {
        final player = MessageLogPlayer(tempFile.path);
        await player.load();

        expect(player.entries, hasLength(2));
        expect(player.stats['loaded'], true);
        expect(player.stats['totalLines'], 2);

        final outputs = player.toOutputEntries();
        expect(outputs, hasLength(2));
        expect(outputs[0], isA<TextOutputEntry>());
        expect(outputs[1], isA<UserInputEntry>());
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('handles malformed lines gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('log_test');
      final tempFile = File('${tempDir.path}/test.jsonl');
      await tempFile.writeAsString('''
{"timestamp":"2026-01-27T23:10:10.000Z","direction":"OUT","message":{"type":"sdk.message","payload":{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}}}
not valid json
{"timestamp":"2026-01-27T23:10:11.000Z","direction":"OUT","message":{"type":"sdk.message","payload":{"type":"user","message":{"content":[{"type":"text","text":"Hi"}]}}}}
''');

      try {
        final player = MessageLogPlayer(tempFile.path);
        await player.load();

        // Should skip the malformed line
        expect(player.entries, hasLength(2));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws on missing file', () async {
      final player = MessageLogPlayer('/nonexistent/path/file.jsonl');

      expect(
        () => player.load(),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  // Integration test with real log file (if available)
  group('Real log file integration', () {
    const realLogPath = '/tmp/test.msgs.jsonl';

    test('loads and parses real log file', () async {
      final file = File(realLogPath);
      if (!await file.exists()) {
        markTestSkipped('Real log file not found at $realLogPath');
        return;
      }

      final player = MessageLogPlayer(realLogPath);
      await player.load();

      final stats = player.stats;
      // ignore: avoid_print
      print('Log file stats: $stats');

      expect(stats['loaded'], true);
      expect(stats['totalLines'], greaterThan(0));

      final outputs = player.toOutputEntries();
      // ignore: avoid_print
      print('Generated ${outputs.length} output entries');

      // Print first few entries for inspection
      for (var i = 0; i < outputs.length && i < 5; i++) {
        final entry = outputs[i];
        // ignore: avoid_print
        print('  [$i] ${entry.runtimeType}: ${_summarize(entry)}');
      }
    });
  });
}

String _summarize(OutputEntry entry) {
  return switch (entry) {
    TextOutputEntry e => 'text(${e.contentType}): ${e.text.substring(0, e.text.length.clamp(0, 50))}...',
    ToolUseOutputEntry e => 'tool: ${e.toolName}',
    UserInputEntry e => 'user: ${e.text.substring(0, e.text.length.clamp(0, 50))}...',
    ContextSummaryEntry _ => 'context_summary',
    ContextClearedEntry _ => 'context_cleared',
    _ => 'unknown',
  };
}
