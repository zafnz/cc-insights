import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('send uses session/prompt with text block', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-1',
      cwd: '/tmp/project',
    );

    await session.send('hello');

    expect(process.requests, hasLength(1));
    final call = process.requests.single;
    expect(call.method, 'session/prompt');
    expect(call.params?['sessionId'], 'sess-1');

    final prompt = call.params?['prompt'] as List<dynamic>;
    expect(prompt, hasLength(1));
    expect(prompt.first, {'type': 'text', 'text': 'hello'});
  });

  test('sendWithContent uses prompt array', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-2',
      cwd: '/tmp/project',
    );

    await session.sendWithContent(const [TextBlock(text: 'hi')]);

    final call = process.requests.single;
    expect(call.method, 'session/prompt');
    final prompt = call.params?['prompt'] as List<dynamic>;
    expect(prompt, [{'type': 'text', 'text': 'hi'}]);
  });

  test('interrupt sends session/cancel notification', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-3',
      cwd: '/tmp/project',
    );

    await session.interrupt();

    expect(process.notificationCalls, hasLength(1));
    final note = process.notificationCalls.single;
    expect(note.method, 'session/cancel');
    expect(note.params, {'sessionId': 'sess-3'});
  });
}

class _MockAcpProcess implements AcpProcess {
  final requests = <_CallRecord>[];
  final notificationCalls = <_CallRecord>[];

  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

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
    requests.add(_CallRecord(method, params));
    return {};
  }

  @override
  void sendNotification(String method, Map<String, dynamic>? params) {
    notificationCalls.add(_CallRecord(method, params));
  }

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
