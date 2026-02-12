import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('tool_call emits ToolInvocationEvent', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-1',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-1',
      update: {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'title': 'Read file',
        'kind': 'read',
        'status': 'in_progress',
        'rawInput': {'path': '/tmp/a.txt'},
        'locations': ['/tmp/a.txt'],
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as ToolInvocationEvent;
    expect(event.callId, 'call-1');
    expect(event.toolName, 'Read file');
    expect(event.kind, ToolKind.read);
    expect(event.input, {'path': '/tmp/a.txt'});
    expect(event.locations, ['/tmp/a.txt']);

    await sub.cancel();
    await session.dispose();
  });

  test('tool_call_update completed emits completion (with invocation first)', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-2',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-2',
      update: {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-2',
        'kind': 'execute',
        'status': 'completed',
        'rawInput': {'command': 'ls'},
        'rawOutput': {'stdout': 'ok'},
        'content': {
          'type': 'terminal',
          'terminalId': 'term-1',
        },
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first, isA<ToolInvocationEvent>());
    final completion = events.last as ToolCompletionEvent;
    expect(completion.callId, 'call-2');
    expect(completion.status, ToolCallStatus.completed);
    expect(completion.output, {'stdout': 'ok'});
    expect(completion.extensions?['acp.toolContent'], isNotNull);

    await sub.cancel();
    await session.dispose();
  });

  test('failed tool_call_update maps to failed status', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-3',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-3',
      update: {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-3',
        'kind': 'edit',
        'status': 'failed',
        'rawInput': {'path': '/tmp/a.txt'},
      },
    );

    await Future<void>.delayed(Duration.zero);

    final completion = events.last as ToolCompletionEvent;
    expect(completion.status, ToolCallStatus.failed);
    expect(completion.isError, isTrue);

    await sub.cancel();
    await session.dispose();
  });
}

class _MockAcpProcess implements AcpProcess {
  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

  void emitUpdate({
    required String sessionId,
    required Map<String, dynamic> update,
  }) {
    _notificationsController.add(JsonRpcNotification(
      method: 'session/update',
      params: {
        'sessionId': sessionId,
        'update': update,
      },
    ));
  }

  @override
  AcpInitializeResult? get initializeResult => null;

  @override
  Map<String, dynamic>? get agentCapabilities => null;

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
