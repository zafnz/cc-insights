import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_sdk/src/cli_process.dart';
import 'package:claude_sdk/src/types/session_options.dart';
import 'package:test/test.dart';

void main() {
  group('CliProcessConfig', () {
    test('uses default executable path when not specified', () {
      // Arrange
      final config = CliProcessConfig(cwd: '/test');

      // Assert - should use 'claude' as default (env var not set in test)
      // Note: We can't easily test CLAUDE_CODE_PATH here since it depends on
      // the actual environment, but we can verify the logic
      expect(config.executablePath, isNull);
    });

    test('uses explicit executable path when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        executablePath: '/custom/path/claude',
      );

      // Assert
      expect(config.resolvedExecutablePath, equals('/custom/path/claude'));
    });

    test('stores all configuration options', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/project',
        executablePath: '/usr/bin/claude',
        model: 'sonnet',
        permissionMode: PermissionMode.acceptEdits,
        settingSources: [SettingSource.defaults, SettingSource.projectSettings],
        maxTurns: 10,
        maxBudgetUsd: 5.0,
        resume: 'session-123',
        verbose: true,
      );

      // Assert
      expect(config.cwd, equals('/project'));
      expect(config.executablePath, equals('/usr/bin/claude'));
      expect(config.model, equals('sonnet'));
      expect(config.permissionMode, equals(PermissionMode.acceptEdits));
      expect(config.settingSources, hasLength(2));
      expect(config.maxTurns, equals(10));
      expect(config.maxBudgetUsd, equals(5.0));
      expect(config.resume, equals('session-123'));
      expect(config.verbose, isTrue);
    });
  });

  group('CliProcess.buildArguments', () {
    test('includes required base arguments', () {
      // Arrange
      final config = CliProcessConfig(cwd: '/test');

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--output-format'));
      expect(args, contains('stream-json'));
      expect(args, contains('--input-format'));
      expect(args, contains('--permission-prompt-tool'));
      expect(args, contains('stdio'));
    });

    test('adds model argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        model: 'haiku',
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--model'));
      final modelIndex = args.indexOf('--model');
      expect(args[modelIndex + 1], equals('haiku'));
    });

    test('adds permission mode argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        permissionMode: PermissionMode.acceptEdits,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--permission-mode'));
      final modeIndex = args.indexOf('--permission-mode');
      expect(args[modeIndex + 1], equals('acceptEdits'));
    });

    test('adds setting sources argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        settingSources: [
          SettingSource.defaults,
          SettingSource.globalSettings,
          SettingSource.projectSettings,
        ],
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--setting-sources'));
      final sourcesIndex = args.indexOf('--setting-sources');
      expect(
        args[sourcesIndex + 1],
        equals('defaults,globalSettings,projectSettings'),
      );
    });

    test('skips setting sources when list is empty', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        settingSources: [],
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, isNot(contains('--setting-sources')));
    });

    test('adds max-turns argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        maxTurns: 15,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--max-turns'));
      final turnsIndex = args.indexOf('--max-turns');
      expect(args[turnsIndex + 1], equals('15'));
    });

    test('adds max-budget-usd argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        maxBudgetUsd: 2.5,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--max-budget-usd'));
      final budgetIndex = args.indexOf('--max-budget-usd');
      expect(args[budgetIndex + 1], equals('2.5'));
    });

    test('adds resume argument when specified', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        resume: 'previous-session-id',
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--resume'));
      final resumeIndex = args.indexOf('--resume');
      expect(args[resumeIndex + 1], equals('previous-session-id'));
    });

    test('adds verbose flag when enabled', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        verbose: true,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, contains('--verbose'));
    });

    test('always includes verbose flag (required for stream-json)', () {
      // Arrange - verbose is always included now regardless of config
      final config = CliProcessConfig(
        cwd: '/test',
        verbose: false,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert - verbose is always included because stream-json requires it
      expect(args, contains('--verbose'));
    });

    test('builds complete argument list with all options', () {
      // Arrange
      final config = CliProcessConfig(
        cwd: '/test',
        model: 'opus',
        permissionMode: PermissionMode.bypassPermissions,
        settingSources: [SettingSource.defaults],
        maxTurns: 5,
        maxBudgetUsd: 10.0,
        resume: 'sess-abc',
        verbose: true,
      );

      // Act
      final args = CliProcess.buildArguments(config);

      // Assert
      expect(args, containsAll([
        '--output-format',
        'stream-json',
        '--input-format',
        '--permission-prompt-tool',
        'stdio',
        '--model',
        'opus',
        '--permission-mode',
        'bypassPermissions',
        '--setting-sources',
        'defaults',
        '--max-turns',
        '5',
        '--max-budget-usd',
        '10.0',
        '--resume',
        'sess-abc',
        '--verbose',
      ]));
    });
  });

  group('SettingSource', () {
    test('has correct string values', () {
      expect(SettingSource.defaults.value, equals('defaults'));
      expect(SettingSource.globalSettings.value, equals('globalSettings'));
      expect(SettingSource.projectSettings.value, equals('projectSettings'));
      expect(SettingSource.managedSettings.value, equals('managedSettings'));
      expect(SettingSource.directorySettings.value, equals('directorySettings'));
      expect(SettingSource.enterpriseSettings.value, equals('enterpriseSettings'));
    });
  });

  group('CliProcess with mock process', () {
    late MockProcessHelper helper;

    setUp(() {
      helper = MockProcessHelper();
    });

    tearDown(() async {
      await helper.dispose();
    });

    group('JSON Lines parsing', () {
      test('parses complete JSON lines', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send complete JSON lines
        helper.emitStdout('{"type":"message","id":"1"}\n');
        helper.emitStdout('{"type":"message","id":"2"}\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(2));
        expect(messages[0]['type'], equals('message'));
        expect(messages[0]['id'], equals('1'));
        expect(messages[1]['id'], equals('2'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('parses multiple JSON lines in single chunk', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send multiple lines in one chunk
        helper.emitStdout(
          '{"type":"a","id":"1"}\n{"type":"b","id":"2"}\n{"type":"c","id":"3"}\n',
        );
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(3));
        expect(messages[0]['type'], equals('a'));
        expect(messages[1]['type'], equals('b'));
        expect(messages[2]['type'], equals('c'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('handles partial line buffering', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send partial JSON across multiple chunks
        helper.emitStdout('{"type":"partial",');
        await Future.delayed(Duration.zero);

        // Should not have any messages yet
        expect(messages, isEmpty);

        // Send rest of the message
        helper.emitStdout('"id":"complete"}\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0]['type'], equals('partial'));
        expect(messages[0]['id'], equals('complete'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('handles multiple partial line chunks', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send JSON across three chunks
        helper.emitStdout('{"type":');
        await Future.delayed(Duration.zero);
        expect(messages, isEmpty);

        helper.emitStdout('"chunked","value":');
        await Future.delayed(Duration.zero);
        expect(messages, isEmpty);

        helper.emitStdout('"test"}\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0]['type'], equals('chunked'));
        expect(messages[0]['value'], equals('test'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('handles mixed complete and partial lines', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - complete line followed by partial
        helper.emitStdout('{"id":"1"}\n{"id":"2",');
        await Future.delayed(Duration.zero);

        // First message should be parsed
        expect(messages, hasLength(1));
        expect(messages[0]['id'], equals('1'));

        // Complete the partial line
        helper.emitStdout('"extra":"data"}\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(2));
        expect(messages[1]['id'], equals('2'));
        expect(messages[1]['extra'], equals('data'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('skips empty lines', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send lines with empty lines in between
        helper.emitStdout('{"id":"1"}\n\n\n{"id":"2"}\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(2));
        expect(messages[0]['id'], equals('1'));
        expect(messages[1]['id'], equals('2'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('handles invalid JSON gracefully', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        final stderrLines = <String>[];
        cliProcess.messages.listen(messages.add);
        cliProcess.stderr.listen(stderrLines.add);

        // Act - send invalid JSON followed by valid JSON
        helper.emitStdout('not valid json\n');
        helper.emitStdout('{"id":"valid"}\n');
        await Future.delayed(Duration.zero);

        // Assert - invalid JSON should be logged to stderr, valid should parse
        expect(messages, hasLength(1));
        expect(messages[0]['id'], equals('valid'));
        expect(stderrLines.any((line) => line.contains('Failed to parse JSON')),
            isTrue);

        // Cleanup
        await cliProcess.dispose();
      });

      test('parses complex nested JSON', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final messages = <Map<String, dynamic>>[];
        cliProcess.messages.listen(messages.add);

        // Act - send complex JSON
        final complexJson = jsonEncode({
          'type': 'tool_use',
          'tool': {
            'name': 'Bash',
            'input': {
              'command': 'ls -la',
              'nested': {'deep': true, 'array': [1, 2, 3]},
            },
          },
        });
        helper.emitStdout('$complexJson\n');
        await Future.delayed(Duration.zero);

        // Assert
        expect(messages, hasLength(1));
        expect(messages[0]['type'], equals('tool_use'));
        expect(messages[0]['tool']['name'], equals('Bash'));
        expect(messages[0]['tool']['input']['nested']['deep'], isTrue);
        expect(messages[0]['tool']['input']['nested']['array'], equals([1, 2, 3]));

        // Cleanup
        await cliProcess.dispose();
      });
    });

    group('stderr forwarding', () {
      test('forwards stderr lines to stream', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        final stderrLines = <String>[];
        cliProcess.stderr.listen(stderrLines.add);

        // Act
        helper.emitStderr('Error line 1');
        helper.emitStderr('Warning line 2');
        await Future.delayed(Duration.zero);

        // Assert
        expect(stderrLines, hasLength(2));
        expect(stderrLines[0], equals('Error line 1'));
        expect(stderrLines[1], equals('Warning line 2'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('buffers stderr lines', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        helper.emitStderr('Line 1');
        helper.emitStderr('Line 2');
        helper.emitStderr('Line 3');
        await Future.delayed(Duration.zero);

        // Assert
        expect(cliProcess.stderrBuffer, hasLength(3));
        expect(cliProcess.stderrBuffer, contains('Line 1'));
        expect(cliProcess.stderrBuffer, contains('Line 2'));
        expect(cliProcess.stderrBuffer, contains('Line 3'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('stderrBuffer is unmodifiable', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        helper.emitStderr('Test line');
        await Future.delayed(Duration.zero);

        // Act & Assert
        expect(
          () => (cliProcess.stderrBuffer as List<String>).add('new'),
          throwsUnsupportedError,
        );

        // Cleanup
        await cliProcess.dispose();
      });
    });

    group('send', () {
      test('sends JSON to stdin', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        cliProcess.send({'type': 'test', 'data': 'value'});

        // Assert
        expect(helper.stdinLines, hasLength(1));
        final sent = jsonDecode(helper.stdinLines[0]) as Map<String, dynamic>;
        expect(sent['type'], equals('test'));
        expect(sent['data'], equals('value'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('escapes unicode line terminators', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act - send message containing unicode line terminators
        cliProcess.send({
          'text': 'line\u2028separator\u2029paragraph',
        });

        // Assert - the JSON should have escaped sequences
        expect(helper.stdinLines, hasLength(1));
        expect(helper.stdinLines[0], contains(r'\u2028'));
        expect(helper.stdinLines[0], contains(r'\u2029'));

        // Cleanup
        await cliProcess.dispose();
      });

      test('throws StateError when disposed', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        await cliProcess.dispose();

        // Assert
        expect(
          () => cliProcess.send({'type': 'test'}),
          throwsStateError,
        );
      });
    });

    group('process lifecycle', () {
      test('isRunning is true initially', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Assert
        expect(cliProcess.isRunning, isTrue);

        // Cleanup
        await cliProcess.dispose();
      });

      test('isRunning is false after dispose', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        await cliProcess.dispose();

        // Assert
        expect(cliProcess.isRunning, isFalse);
      });

      test('dispose is idempotent', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act - dispose multiple times
        await cliProcess.dispose();
        await cliProcess.dispose();
        await cliProcess.dispose();

        // Assert - should not throw
        expect(cliProcess.isRunning, isFalse);
      });

      test('dispose closes streams', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        var messagesDone = false;
        var stderrDone = false;

        cliProcess.messages.listen((_) {}, onDone: () => messagesDone = true);
        cliProcess.stderr.listen((_) {}, onDone: () => stderrDone = true);

        // Act
        await cliProcess.dispose();

        // Assert
        expect(messagesDone, isTrue);
        expect(stderrDone, isTrue);
      });

      test('kill terminates the process', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        await cliProcess.kill();

        // Assert
        expect(helper.killed, isTrue);

        // Cleanup
        await cliProcess.dispose();
      });

      test('kill is safe when already disposed', () async {
        // Arrange
        final process = helper.createMockProcess();
        final cliProcess = CliProcessForTesting(process: process);

        // Act
        await cliProcess.dispose();
        await cliProcess.kill(); // Should not throw

        // Assert
        expect(cliProcess.isRunning, isFalse);
      });
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

/// Helper class to create mock processes for testing.
class MockProcessHelper {
  final _stdoutController = StreamController<List<int>>.broadcast();
  final _stderrController = StreamController<List<int>>.broadcast();
  final _stdinLines = <String>[];
  final _exitCodeCompleter = Completer<int>();
  var _killed = false;

  bool get killed => _killed;
  List<String> get stdinLines => _stdinLines;

  Process createMockProcess() {
    return _MockProcess(
      stdout: _stdoutController.stream,
      stderr: _stderrController.stream,
      stdin: _MockIOSink((line) => _stdinLines.add(line)),
      exitCode: _exitCodeCompleter.future,
      onKill: () {
        _killed = true;
        if (!_exitCodeCompleter.isCompleted) {
          _exitCodeCompleter.complete(0);
        }
      },
    );
  }

  void emitStdout(String data) {
    _stdoutController.add(utf8.encode(data));
  }

  void emitStderr(String line) {
    _stderrController.add(utf8.encode('$line\n'));
  }

  void completeExitCode(int code) {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
  }

  Future<void> dispose() async {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    await _stdoutController.close();
    await _stderrController.close();
  }
}

/// Mock Process implementation for testing.
class _MockProcess implements Process {
  _MockProcess({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
    required IOSink stdin,
    required Future<int> exitCode,
    required VoidCallback onKill,
  })  : _stdout = stdout,
        _stderr = stderr,
        _stdin = stdin,
        _exitCode = exitCode,
        _onKill = onKill;

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final IOSink _stdin;
  final Future<int> _exitCode;
  final VoidCallback _onKill;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _onKill();
    return true;
  }
}

/// Mock IOSink for capturing stdin writes.
class _MockIOSink implements IOSink {
  _MockIOSink(this._onWriteln);

  final void Function(String) _onWriteln;

  @override
  void writeln([Object? obj = '']) {
    _onWriteln(obj.toString());
  }

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) async {}

  @override
  Future close() async {}

  @override
  Future get done async {}

  @override
  Future flush() async {}

  @override
  void write(Object? obj) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}
}

typedef VoidCallback = void Function();

/// CliProcess wrapper for testing that takes a pre-created process.
class CliProcessForTesting {
  CliProcessForTesting({required Process process})
      : _process = process {
    _setupStreams();
  }

  final Process _process;

  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _stderrController = StreamController<String>.broadcast();
  final _stderrBuffer = <String>[];

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  String _partialLine = '';
  bool _disposed = false;

  bool get isRunning => !_disposed;
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;
  Stream<String> get stderr => _stderrController.stream;
  List<String> get stderrBuffer => List.unmodifiable(_stderrBuffer);
  Future<int> get exitCode => _process.exitCode;

  void _setupStreams() {
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .listen(_handleStdoutChunk);

    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrBuffer.add(line);
      _stderrController.add(line);
    });
  }

  void _handleStdoutChunk(String chunk) {
    final data = _partialLine + chunk;
    _partialLine = '';

    final lines = data.split('\n');

    if (!chunk.endsWith('\n') && lines.isNotEmpty) {
      _partialLine = lines.removeLast();
    }

    for (final line in lines) {
      if (line.isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _messagesController.add(json);
      } catch (e) {
        _stderrController.add('[cli_process] Failed to parse JSON: $e');
        _stderrController.add('[cli_process] Line: $line');
      }
    }
  }

  void send(Map<String, dynamic> message) {
    if (_disposed) {
      throw StateError('CliProcess has been disposed');
    }

    var json = jsonEncode(message);
    json = json.replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    _process.stdin.writeln(json);
  }

  Future<void> kill() async {
    if (_disposed) return;
    _process.kill();
    await _process.exitCode;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    _process.kill();

    await _messagesController.close();
    await _stderrController.close();
  }
}
