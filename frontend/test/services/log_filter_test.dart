import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/services/log_filter.dart';
import 'package:cc_insights_v2/services/log_service.dart';

void main() {
  LogEntry _entry({
    String source = 'App',
    LogLevel level = LogLevel.info,
    String message = 'hello world',
    Map<String, dynamic>? meta,
  }) {
    return LogEntry(
      timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      level: level,
      source: source,
      message: message,
      meta: meta,
    );
  }

  group('LogFilter.parse', () {
    test('returns null for empty string', () {
      expect(LogFilter.parse(''), isNull);
      expect(LogFilter.parse('   '), isNull);
    });

    test('returns null for invalid queries', () {
      expect(LogFilter.parse('no accessor'), isNull);
      expect(LogFilter.parse('.source'), isNull); // no operator
      expect(LogFilter.parse('source == "App"'), isNull); // missing leading dot
      expect(LogFilter.parse('. == "App"'), isNull); // empty field
    });

    test('parses .source == "App"', () {
      final filter = LogFilter.parse('.source == "App"');
      expect(filter, isNotNull);
    });

    test('parses .level == "error"', () {
      final filter = LogFilter.parse('.level == "error"');
      expect(filter, isNotNull);
    });

    test('parses .message contains "timeout"', () {
      final filter = LogFilter.parse('.message contains "timeout"');
      expect(filter, isNotNull);
    });

    test('parses .meta.worktree == "main"', () {
      final filter = LogFilter.parse('.meta.worktree == "main"');
      expect(filter, isNotNull);
    });

    test('parses .source != "Flutter"', () {
      final filter = LogFilter.parse('.source != "Flutter"');
      expect(filter, isNotNull);
    });

    test('handles single-quoted values', () {
      final filter = LogFilter.parse(".source == 'App'");
      expect(filter, isNotNull);
      expect(filter!.matches(_entry(source: 'App')), isTrue);
    });

    test('handles unquoted values', () {
      final filter = LogFilter.parse('.source == App');
      expect(filter, isNotNull);
      expect(filter!.matches(_entry(source: 'App')), isTrue);
    });

    test('returns null for value that is just quotes', () {
      expect(LogFilter.parse('.source == ""'), isNull);
    });
  });

  group('LogFilter.matches — eq operator', () {
    test('matches source field', () {
      final filter = LogFilter.parse('.source == "App"')!;
      expect(filter.matches(_entry(source: 'App')), isTrue);
      expect(filter.matches(_entry(source: 'Flutter')), isFalse);
    });

    test('matches level field', () {
      final filter = LogFilter.parse('.level == "error"')!;
      expect(filter.matches(_entry(level: LogLevel.error)), isTrue);
      expect(filter.matches(_entry(level: LogLevel.info)), isFalse);
    });

    test('matches message field', () {
      final filter = LogFilter.parse('.message == "hello world"')!;
      expect(filter.matches(_entry(message: 'hello world')), isTrue);
      expect(filter.matches(_entry(message: 'other')), isFalse);
    });

    test('matches meta field', () {
      final filter = LogFilter.parse('.meta.worktree == "main"')!;
      expect(
        filter.matches(_entry(meta: {'worktree': 'main'})),
        isTrue,
      );
      expect(
        filter.matches(_entry(meta: {'worktree': 'feature'})),
        isFalse,
      );
      expect(filter.matches(_entry()), isFalse); // no meta
    });

    test('matches nested meta fields', () {
      final filter = LogFilter.parse('.meta.context.id == "123"')!;
      expect(
        filter.matches(_entry(meta: {
          'context': {'id': '123'},
        })),
        isTrue,
      );
      expect(
        filter.matches(_entry(meta: {
          'context': {'id': '456'},
        })),
        isFalse,
      );
    });
  });

  group('LogFilter.matches — neq operator', () {
    test('excludes matching entries', () {
      final filter = LogFilter.parse('.source != "Flutter"')!;
      expect(filter.matches(_entry(source: 'App')), isTrue);
      expect(filter.matches(_entry(source: 'Flutter')), isFalse);
    });

    test('matches when field is missing (meta)', () {
      final filter = LogFilter.parse('.meta.worktree != "main"')!;
      expect(filter.matches(_entry()), isTrue); // no meta = not equal
    });
  });

  group('LogFilter.matches — contains operator', () {
    test('finds substring in message', () {
      final filter = LogFilter.parse('.message contains "world"')!;
      expect(filter.matches(_entry(message: 'hello world')), isTrue);
      expect(filter.matches(_entry(message: 'hello')), isFalse);
    });

    test('is case-insensitive', () {
      final filter = LogFilter.parse('.message contains "HELLO"')!;
      expect(filter.matches(_entry(message: 'hello world')), isTrue);
    });

    test('works on source field', () {
      final filter = LogFilter.parse('.source contains "lut"')!;
      expect(filter.matches(_entry(source: 'Flutter')), isTrue);
      expect(filter.matches(_entry(source: 'App')), isFalse);
    });
  });

  group('LogFilter.matches — unknown fields', () {
    test('unknown top-level field returns false for eq', () {
      final filter = LogFilter.parse('.nonexistent == "foo"')!;
      expect(filter.matches(_entry()), isFalse);
    });

    test('unknown top-level field returns true for neq', () {
      final filter = LogFilter.parse('.nonexistent != "foo"')!;
      expect(filter.matches(_entry()), isTrue);
    });
  });
}
