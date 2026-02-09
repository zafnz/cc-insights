import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart';

import 'json_rpc.dart';

/// Configuration for spawning Codex app-server.
class CodexProcessConfig {
  const CodexProcessConfig({
    this.executablePath,
  });

  /// Path to the codex executable (defaults to 'codex').
  final String? executablePath;

  String get resolvedExecutablePath => executablePath ?? 'codex';
}

/// Manages a Codex app-server subprocess.
class CodexProcess {
  CodexProcess._({
    required Process process,
    required JsonRpcClient client,
  })  : _process = process,
        _client = client {
    _setupStderr();
    _setupProtocolLogs();
  }

  final Process _process;
  final JsonRpcClient _client;

  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();
  StreamSubscription<String>? _stderrSub;
  StreamSubscription<LogEntry>? _protocolLogSub;

  bool _disposed = false;

  /// Stream of server notifications.
  Stream<JsonRpcNotification> get notifications => _client.notifications;

  /// Stream of server requests (requires response).
  Stream<JsonRpcServerRequest> get serverRequests => _client.serverRequests;

  /// Stream of stderr log lines (for backwards compatibility).
  Stream<String> get logs => _logsController.stream;

  /// Stream of structured log entries.
  Stream<LogEntry> get logEntries => _logEntriesController.stream;

  static Future<CodexProcess> start(
    CodexProcessConfig config, {
    String clientName = 'cc-insights',
    String clientVersion = '0.1.0',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    stdout.writeln(
      '[CODEX SPAWN] ${config.resolvedExecutablePath} app-server',
    );
    stdout.flush();
    final process = await Process.start(
      config.resolvedExecutablePath,
      ['app-server'],
      mode: ProcessStartMode.normal,
    );

    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final client = JsonRpcClient(
      input: lines,
      output: (line) => process.stdin.writeln(line),
    );

    final codex = CodexProcess._(process: process, client: client);

    await codex._initialize(
      clientName: clientName,
      clientVersion: clientVersion,
      timeout: timeout,
    );

    stdout.writeln('[CODEX READY]');
    stdout.flush();

    return codex;
  }

  Future<void> _initialize({
    required String clientName,
    required String clientVersion,
    required Duration timeout,
  }) async {
    final result = await _client
        .sendRequest('initialize', {
          'clientInfo': {
            'name': clientName,
            'version': clientVersion,
          },
        })
        .timeout(timeout);

    _client.sendNotification('initialized', null);

    if (result.isEmpty) return;
  }

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic>? params,
  ) {
    return _client.sendRequest(method, params);
  }

  void sendNotification(String method, Map<String, dynamic>? params) {
    _client.sendNotification(method, params);
  }

  void sendResponse(Object id, Map<String, dynamic> result) {
    _client.sendResponse(id, result);
  }

  void sendError(Object id, int code, String message, {dynamic data}) {
    _client.sendError(id, code, message, data: data);
  }

  void _setupStderr() {
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          SdkLogger.instance.logStderr(line);
          _logsController.add(line);
          _logEntriesController.add(LogEntry(
            level: LogLevel.debug,
            message: 'stderr',
            timestamp: DateTime.now(),
            direction: LogDirection.stderr,
            text: line,
          ));
        });
  }

  void _setupProtocolLogs() {
    _protocolLogSub = _client.protocolLogEntries.listen((entry) {
      _logsController.add(entry.toString());
      _logEntriesController.add(entry);
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stderrSub?.cancel();
    await _protocolLogSub?.cancel();
    await _logsController.close();
    await _logEntriesController.close();
    await _client.dispose();
    _process.kill();
    await _process.exitCode;
  }
}
