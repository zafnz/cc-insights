import 'dart:async';
import 'dart:io';

import 'package:claude_sdk/src/sdk_logger.dart';
import 'package:test/test.dart';

void main() {
  // Note: SdkLogger is a singleton, so we need to be careful with state
  // between tests

  group('SdkLogger', () {
    late StreamSubscription<LogEntry> subscription;
    final receivedLogs = <LogEntry>[];

    setUp(() {
      receivedLogs.clear();
      subscription = SdkLogger.instance.logs.listen(receivedLogs.add);
    });

    tearDown(() async {
      await subscription.cancel();
      SdkLogger.instance.debugEnabled = false;
      await SdkLogger.instance.disableFileLogging();
    });

    test('debugEnabled defaults to false', () {
      // Reset to ensure clean state
      SdkLogger.instance.debugEnabled = false;
      expect(SdkLogger.instance.debugEnabled, isFalse);
    });

    test('debugEnabled can be enabled programmatically', () {
      SdkLogger.instance.debugEnabled = true;
      expect(SdkLogger.instance.debugEnabled, isTrue);
    });

    test('debug messages are not emitted when debugEnabled is false', () async {
      SdkLogger.instance.debugEnabled = false;

      SdkLogger.instance.debug('test debug message');

      // Give stream time to process
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
          receivedLogs.where((e) => e.message == 'test debug message'), isEmpty);
    });

    test('debug messages are emitted when debugEnabled is true', () async {
      SdkLogger.instance.debugEnabled = true;

      SdkLogger.instance.debug('test debug message');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedLogs.any((e) => e.message == 'test debug message'), isTrue);
      final entry =
          receivedLogs.firstWhere((e) => e.message == 'test debug message');
      expect(entry.level, equals(LogLevel.debug));
    });

    test('info messages are always emitted', () async {
      SdkLogger.instance.debugEnabled = false;

      SdkLogger.instance.info('test info message');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedLogs.any((e) => e.message == 'test info message'), isTrue);
      final entry =
          receivedLogs.firstWhere((e) => e.message == 'test info message');
      expect(entry.level, equals(LogLevel.info));
    });

    test('warning messages are always emitted', () async {
      SdkLogger.instance.warning('test warning message');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
          receivedLogs.any((e) => e.message == 'test warning message'), isTrue);
      final entry =
          receivedLogs.firstWhere((e) => e.message == 'test warning message');
      expect(entry.level, equals(LogLevel.warning));
    });

    test('error messages are always emitted', () async {
      SdkLogger.instance.error('test error message');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(receivedLogs.any((e) => e.message == 'test error message'), isTrue);
      final entry =
          receivedLogs.firstWhere((e) => e.message == 'test error message');
      expect(entry.level, equals(LogLevel.error));
    });

    test('log entries include timestamp', () async {
      final beforeLog = DateTime.now();
      SdkLogger.instance.info('timestamp test');
      final afterLog = DateTime.now();

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry =
          receivedLogs.firstWhere((e) => e.message == 'timestamp test');
      expect(entry.timestamp.isAfter(beforeLog.subtract(const Duration(seconds: 1))),
          isTrue);
      expect(
          entry.timestamp.isBefore(afterLog.add(const Duration(seconds: 1))), isTrue);
    });

    test('log entries can include sessionId', () async {
      SdkLogger.instance.info('session test', sessionId: 'test-session-123');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry =
          receivedLogs.firstWhere((e) => e.message == 'session test');
      expect(entry.sessionId, equals('test-session-123'));
    });

    test('log entries can include data', () async {
      SdkLogger.instance.info('data test', data: {'key': 'value', 'count': 42});

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry = receivedLogs.firstWhere((e) => e.message == 'data test');
      expect(entry.data, isNotNull);
      expect(entry.data!['key'], equals('value'));
      expect(entry.data!['count'], equals(42));
    });

    test('logOutgoing logs message with debug level and stdin direction',
        () async {
      SdkLogger.instance.debugEnabled = true;

      SdkLogger.instance.logOutgoing({'type': 'test', 'payload': 'data'});

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry = receivedLogs
          .firstWhere((e) => e.direction == LogDirection.stdin);
      expect(entry.level, equals(LogLevel.debug));
      expect(entry.message, equals('SEND'));
      expect(entry.data, isNotNull);
      expect(entry.data!['type'], equals('test'));
    });

    test('logIncoming logs message with debug level and stdout direction',
        () async {
      SdkLogger.instance.debugEnabled = true;

      SdkLogger.instance.logIncoming({'type': 'response', 'data': 123});

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry = receivedLogs
          .firstWhere((e) => e.direction == LogDirection.stdout);
      expect(entry.level, equals(LogLevel.debug));
      expect(entry.message, equals('RECV'));
      expect(entry.data, isNotNull);
      expect(entry.data!['type'], equals('response'));
    });

    test('logStderr logs with stderr direction and text field', () async {
      SdkLogger.instance.debugEnabled = true;

      SdkLogger.instance.logStderr('some stderr output');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final entry = receivedLogs
          .firstWhere((e) => e.direction == LogDirection.stderr);
      expect(entry.level, equals(LogLevel.info));
      expect(entry.text, equals('some stderr output'));
    });

    test('LogEntry toString includes all components', () {
      final entry = LogEntry(
        level: LogLevel.error,
        message: 'test message',
        timestamp: DateTime(2024, 1, 15, 10, 30, 45),
        sessionId: 'sess-123',
        data: {'foo': 'bar'},
      );

      final str = entry.toString();
      expect(str, contains('[ERROR]'));
      expect(str, contains('[session:sess-123]'));
      expect(str, contains('test message'));
      expect(str, contains('"foo":"bar"'));
    });

    test('LogEntry toString works without optional fields', () {
      final entry = LogEntry(
        level: LogLevel.info,
        message: 'simple message',
        timestamp: DateTime(2024, 1, 15, 10, 30, 45),
      );

      final str = entry.toString();
      expect(str, contains('[INFO]'));
      expect(str, contains('simple message'));
      expect(str, isNot(contains('[session:')));
    });
  });

  group('SdkLogger file logging', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sdk_logger_test_');
    });

    tearDown(() async {
      await SdkLogger.instance.disableFileLogging();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }
    });

    test('enableFileLogging creates log file', () async {
      final logPath = '${tempDir.path}/test.log';

      SdkLogger.instance.enableFileLogging(logPath);
      SdkLogger.instance.info('file logging test');

      // Give file time to flush
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await SdkLogger.instance.disableFileLogging();

      final file = File(logPath);
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains('file logging test'));
    });

    test('logFilePath returns path when file logging is enabled', () {
      final logPath = '${tempDir.path}/path_test.log';

      expect(SdkLogger.instance.logFilePath, isNull);

      SdkLogger.instance.enableFileLogging(logPath);
      expect(SdkLogger.instance.logFilePath, equals(logPath));
    });

    test('disableFileLogging clears logFilePath', () async {
      final logPath = '${tempDir.path}/disable_test.log';

      SdkLogger.instance.enableFileLogging(logPath);
      expect(SdkLogger.instance.logFilePath, isNotNull);

      await SdkLogger.instance.disableFileLogging();
      expect(SdkLogger.instance.logFilePath, isNull);
    });
  });
}
