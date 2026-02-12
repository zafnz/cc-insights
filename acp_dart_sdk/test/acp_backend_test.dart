import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('createSession calls session/new and emits SessionInitEvent', () async {
    final process = _MockAcpProcess();
    final backend = AcpBackend.createForTesting(process: process);

    final options = SessionOptions(
      mcpServers: {
        'local': const McpStdioServerConfig(
          command: 'mcp-server',
          args: ['--mode', 'test'],
        ),
      },
    );

    final session = await backend.createSession(
      prompt: 'Hello',
      cwd: '/tmp/project',
      options: options,
    );

    expect(process.calls, isNotEmpty);
    expect(process.calls.first.method, 'session/new');
    expect(process.calls.first.params?['cwd'], '/tmp/project');
    final mcpServers =
        process.calls.first.params?['mcpServers'] as List<dynamic>?;
    expect(mcpServers, isNotNull);
    expect(mcpServers, hasLength(1));
    final server = mcpServers!.first as Map<String, dynamic>;
    expect(server['name'], 'local');
    expect(server['type'], 'stdio');
    expect(server['command'], 'mcp-server');
    expect(server['args'], ['--mode', 'test']);

    final event = await session.events.first;
    expect(event, isA<SessionInitEvent>());
    final init = event as SessionInitEvent;
    expect(init.sessionId, 'session-123');
    expect(init.cwd, '/tmp/project');
    expect(init.provider, BackendProvider.acp);

    await backend.dispose();
  });
}

class _MockAcpProcess implements AcpProcess {
  final calls = <_CallRecord>[];

  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

  @override
  AcpInitializeResult? get initializeResult => const AcpInitializeResult(
        protocolVersion: 1,
        agentCapabilities: {'loadSession': true},
      );

  @override
  Map<String, dynamic>? get agentCapabilities =>
      initializeResult?.agentCapabilities;

  @override
  Stream<JsonRpcNotification> get notifications =>
      _notificationsController.stream;

  @override
  Stream<JsonRpcServerRequest> get serverRequests =>
      _serverRequestsController.stream;

  @override
  Stream<String> get logs => _logsController.stream;

  @override
  Stream<LogEntry> get logEntries => _logEntriesController.stream;

  @override
  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic>? params,
  ) async {
    calls.add(_CallRecord(method, params));

    if (method == 'session/new') {
      return {'sessionId': 'session-123'};
    }

    return {};
  }

  @override
  void sendNotification(String method, Map<String, dynamic>? params) {}

  @override
  void sendResponse(Object id, Map<String, dynamic> result) {}

  @override
  void sendError(Object id, int code, String message, {dynamic data}) {}

  @override
  Future<void> dispose() async {
    await _notificationsController.close();
    await _serverRequestsController.close();
    await _logsController.close();
    await _logEntriesController.close();
  }
}

class _CallRecord {
  _CallRecord(this.method, this.params);

  final String method;
  final Map<String, dynamic>? params;
}
