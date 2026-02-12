import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:meta/meta.dart';

import 'json_rpc.dart';

/// Configuration for spawning an ACP agent process.
class AcpProcessConfig {
  const AcpProcessConfig({
    this.executablePath,
    this.arguments = const [],
  });

  /// Path to the ACP executable (defaults to 'acp').
  final String? executablePath;

  /// Additional arguments passed to the ACP executable.
  final List<String> arguments;

  String get resolvedExecutablePath => executablePath ?? 'acp';
}

/// Initialize response metadata from an ACP agent.
@immutable
class AcpInitializeResult {
  const AcpInitializeResult({
    this.protocolVersion,
    this.agentCapabilities,
    this.agentInfo,
    this.authMethods,
    this.raw,
  });

  factory AcpInitializeResult.fromJson(Map<String, dynamic> json) {
    return AcpInitializeResult(
      protocolVersion: _asInt(json['protocolVersion']),
      agentCapabilities: _asMap(json['agentCapabilities']),
      agentInfo: _asMap(json['agentInfo']),
      authMethods: (json['authMethods'] as List<dynamic>?)
          ?.map((entry) => entry)
          .toList(),
      raw: json.isEmpty ? null : json,
    );
  }

  final int? protocolVersion;
  final Map<String, dynamic>? agentCapabilities;
  final Map<String, dynamic>? agentInfo;
  final List<dynamic>? authMethods;
  final Map<String, dynamic>? raw;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }
}

/// Manages an ACP agent subprocess.
class AcpProcess {
  AcpProcess._({
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

  AcpInitializeResult? _initializeResult;

  /// Stream of server notifications.
  Stream<JsonRpcNotification> get notifications => _client.notifications;

  /// Stream of server requests (requires response).
  Stream<JsonRpcServerRequest> get serverRequests => _client.serverRequests;

  /// Stream of stderr log lines (for backwards compatibility).
  Stream<String> get logs => _logsController.stream;

  /// Stream of structured log entries.
  Stream<LogEntry> get logEntries => _logEntriesController.stream;

  /// Initialize response metadata from the agent.
  AcpInitializeResult? get initializeResult => _initializeResult;

  /// Shortcut to negotiated agent capabilities.
  Map<String, dynamic>? get agentCapabilities =>
      _initializeResult?.agentCapabilities;

  static Future<AcpProcess> start(
    AcpProcessConfig config, {
    String clientName = 'cc-insights',
    String clientVersion = '0.1.0',
    Map<String, dynamic>? clientCapabilities,
    int protocolVersion = 1,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final args = config.arguments;
    stdout.writeln(
      '[ACP SPAWN] ${config.resolvedExecutablePath} ${args.join(' ')}',
    );
    stdout.flush();

    final process = await Process.start(
      config.resolvedExecutablePath,
      args,
      mode: ProcessStartMode.normal,
    );

    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final client = JsonRpcClient(
      input: lines,
      output: (line) => process.stdin.writeln(line),
    );

    final acp = AcpProcess._(process: process, client: client);
    acp._initializeResult = await _initialize(
      client: client,
      clientName: clientName,
      clientVersion: clientVersion,
      clientCapabilities: clientCapabilities,
      protocolVersion: protocolVersion,
      timeout: timeout,
    );

    stdout.writeln('[ACP READY]');
    stdout.flush();

    return acp;
  }

  @visibleForTesting
  static Future<AcpInitializeResult> initializeForTesting({
    required JsonRpcClient client,
    String clientName = 'cc-insights',
    String clientVersion = '0.1.0',
    Map<String, dynamic>? clientCapabilities,
    int protocolVersion = 1,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return _initialize(
      client: client,
      clientName: clientName,
      clientVersion: clientVersion,
      clientCapabilities: clientCapabilities,
      protocolVersion: protocolVersion,
      timeout: timeout,
    );
  }

  static Future<AcpInitializeResult> _initialize({
    required JsonRpcClient client,
    required String clientName,
    required String clientVersion,
    required int protocolVersion,
    Map<String, dynamic>? clientCapabilities,
    required Duration timeout,
  }) async {
    final result = await client
        .sendRequest('initialize', {
          'protocolVersion': protocolVersion,
          if (clientCapabilities != null)
            'clientCapabilities': clientCapabilities,
          'clientInfo': {
            'name': clientName,
            'version': clientVersion,
          },
        })
        .timeout(timeout);

    return AcpInitializeResult.fromJson(result);
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
