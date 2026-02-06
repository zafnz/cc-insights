import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sdk_logger.dart';
import 'types/session_options.dart';

/// Diagnostic trace — only prints when [SdkLogger.debugEnabled] is true.
void _t(String tag, String msg) => SdkLogger.instance.trace(tag, msg);

/// Setting sources for the CLI.
enum SettingSource {
  defaults('defaults'),
  globalSettings('globalSettings'),
  projectSettings('projectSettings'),
  managedSettings('managedSettings'),
  directorySettings('directorySettings'),
  enterpriseSettings('enterpriseSettings');

  const SettingSource(this.value);
  final String value;
}

/// Configuration for spawning the claude-cli process.
class CliProcessConfig {
  const CliProcessConfig({
    this.executablePath,
    required this.cwd,
    this.model,
    this.permissionMode,
    this.settingSources,
    this.maxTurns,
    this.maxBudgetUsd,
    this.resume,
    this.includePartialMessages = false,
  });

  /// Path to the claude executable.
  /// Defaults to CLAUDE_CODE_PATH environment variable or 'claude'.
  final String? executablePath;

  /// Working directory for the session.
  final String cwd;

  /// Model to use (e.g., 'sonnet', 'opus', 'haiku').
  final String? model;

  /// Permission mode for the session.
  final PermissionMode? permissionMode;

  /// Settings sources to load.
  final List<SettingSource>? settingSources;

  /// Maximum conversation turns.
  final int? maxTurns;

  /// Maximum budget in USD.
  final double? maxBudgetUsd;

  /// Resume an existing session by session ID.
  final String? resume;

  /// Include partial message chunks as they arrive (streaming).
  final bool includePartialMessages;

  /// Get the executable path, using environment variable or default.
  String get resolvedExecutablePath {
    if (executablePath != null) return executablePath!;
    return Platform.environment['CLAUDE_CODE_PATH'] ?? 'claude';
  }
}

/// Manages a claude-cli subprocess.
class CliProcess {
  CliProcess._({
    required Process process,
    required CliProcessConfig config,
  })  : _process = process,
        _config = config {
    _setupStreams();
  }

  final Process _process;
  final CliProcessConfig _config;

  final _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _stderrController = StreamController<String>.broadcast();
  final _stderrBuffer = <String>[];
  static const _maxStderrBufferSize = 1000;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  String _partialLine = '';
  bool _disposed = false;

  /// Whether the process is running.
  bool get isRunning => !_disposed;

  /// Stream of parsed JSON messages from stdout.
  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  /// Stream of stderr lines (for logging).
  Stream<String> get stderr => _stderrController.stream;

  /// Get buffered stderr lines (for error reporting).
  List<String> get stderrBuffer => List.unmodifiable(_stderrBuffer);

  /// Process exit code (available after termination).
  Future<int> get exitCode => _process.exitCode;

  /// The configuration used to spawn this process.
  CliProcessConfig get config => _config;

  /// Build CLI arguments from configuration.
  static List<String> buildArguments(CliProcessConfig config) {
    final args = <String>[
      '--output-format',
      'stream-json',
      '--input-format',
      'stream-json',
      '--verbose',
      '--permission-prompt-tool',
      'stdio',
    ];

    if (config.model != null) {
      args.addAll(['--model', config.model!]);
    }

    if (config.permissionMode != null) {
      args.addAll(['--permission-mode', config.permissionMode!.value]);
    }

    if (config.settingSources != null && config.settingSources!.isNotEmpty) {
      final sources = config.settingSources!.map((s) => s.value).join(',');
      args.addAll(['--setting-sources', sources]);
    }

    if (config.maxTurns != null) {
      args.addAll(['--max-turns', config.maxTurns.toString()]);
    }

    if (config.maxBudgetUsd != null) {
      args.addAll(['--max-budget-usd', config.maxBudgetUsd.toString()]);
    }

    if (config.resume != null) {
      args.addAll(['--resume', config.resume!]);
    }

    if (config.includePartialMessages) {
      args.add('--include-partial-messages');
    }

    return args;
  }

  /// Spawn a new claude-cli process.
  static Future<CliProcess> spawn(CliProcessConfig config) async {
    final executable = config.resolvedExecutablePath;
    final args = buildArguments(config);

    _t('CliProcess', 'Spawning: $executable ${args.join(' ')}');
    _t('CliProcess', '  cwd: ${config.cwd}');

    final process = await Process.start(
      executable,
      args,
      workingDirectory: config.cwd,
      mode: ProcessStartMode.normal,
    );

    _t('CliProcess', 'Process started (pid: ${process.pid})');

    return CliProcess._(process: process, config: config);
  }

  void _setupStreams() {
    _t('CliProcess', 'Setting up stdout/stderr streams (pid: ${_process.pid})');

    // Parse stdout as JSON Lines with buffering for partial lines
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .listen(_handleStdoutChunk);

    // Forward stderr for logging
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrBuffer.add(line);
      if (_stderrBuffer.length > _maxStderrBufferSize) {
        _stderrBuffer.removeAt(0);
      }
      _t('CliProcess:stderr', line);
      // Log stderr to SDK logger
      SdkLogger.instance.logStderr(line);
      _stderrController.add(line);
    });

    // Monitor process exit
    _process.exitCode.then((code) {
      _t('CliProcess', 'Process exited with code: $code (pid: ${_process.pid})');
    });
  }

  void _handleStdoutChunk(String chunk) {
    // Append to any partial line from previous chunk
    final data = _partialLine + chunk;
    _partialLine = '';

    // Split by newlines
    final lines = data.split('\n');

    // Last element might be a partial line (no trailing newline)
    if (!chunk.endsWith('\n') && lines.isNotEmpty) {
      _partialLine = lines.removeLast();
    }

    // Process complete lines
    for (final line in lines) {
      if (line.isEmpty) continue;

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final type = json['type'] as String? ?? '?';
        final subtype = json['subtype'] as String? ??
            (json['request'] as Map<String, dynamic>?)?['subtype'] as String? ??
            '';
        _t('CliProcess:recv', 'type=$type${subtype.isNotEmpty ? ' subtype=$subtype' : ''}'
            ' (${line.length} chars)');
        // Log incoming message
        SdkLogger.instance.logIncoming(json);
        _messagesController.add(json);
      } catch (e) {
        // If JSON parsing fails, log it as an error
        _t('CliProcess:recv', 'PARSE ERROR: $e');
        _t('CliProcess:recv', '  line: ${line.length > 200 ? '${line.substring(0, 200)}...' : line}');
        SdkLogger.instance.error(
          'Failed to parse JSON from CLI',
          data: {'error': e.toString(), 'line': line},
        );
        _stderrController.add('[cli_process] Failed to parse JSON: $e');
        _stderrController.add('[cli_process] Line: $line');
      }
    }
  }

  /// Send a JSON message to stdin.
  void send(Map<String, dynamic> message) {
    if (_disposed) {
      _t('CliProcess:send', 'ERROR: Attempted send on disposed process');
      throw StateError('CliProcess has been disposed');
    }

    final type = message['type'] as String? ?? '?';
    final subtype = (message['request'] as Map<String, dynamic>?)?['subtype'] as String? ?? '';
    _t('CliProcess:send', 'type=$type${subtype.isNotEmpty ? ' subtype=$subtype' : ''}');

    // Log outgoing message
    SdkLogger.instance.logOutgoing(message);

    var json = jsonEncode(message);
    // Escape Unicode line terminators that could break JSON Lines parsing
    json = json.replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    _process.stdin.writeln(json);
  }

  /// Kill the process.
  Future<void> kill() async {
    if (_disposed) return;

    _process.kill();
    await _process.exitCode;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _t('CliProcess', 'Disposing process (pid: ${_process.pid})');

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    _process.kill();

    await _messagesController.close();
    await _stderrController.close();
    _t('CliProcess', 'Process disposed');
  }
}
