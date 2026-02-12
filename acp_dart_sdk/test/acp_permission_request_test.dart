import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('permission request emits event and responds with selected option', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-1',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final eventSub = session.events.listen(events.add);

    process.emitPermissionRequest(
      id: 99,
      params: {
        'sessionId': 'sess-1',
        'toolCall': {
          'toolCallId': 'call-1',
          'title': 'Write file',
          'kind': 'edit',
          'rawInput': {'path': '/tmp/a.txt'},
        },
        'options': [
          {'optionId': 'opt-1', 'name': 'Allow once'},
          {'optionId': 'opt-2', 'name': 'Allow always'},
        ],
      },
    );

    final permission = await session.permissionRequests.first;
    permission.allow(updatedInput: {'optionId': 'opt-2'});

    await Future<void>.delayed(Duration.zero);

    expect(process.lastResponseId, 99);
    expect(process.lastResponse?['outcome'], {
      'outcome': 'selected',
      'optionId': 'opt-2',
    });

    final event = events.whereType<PermissionRequestEvent>().single;
    expect(event.toolName, 'Write file');
    expect(event.toolKind, ToolKind.edit);
    expect(event.extensions?['acp.options'], isA<List<dynamic>>());

    await eventSub.cancel();
    await session.dispose();
  });

  test('deny maps to cancelled outcome', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-2',
      cwd: '/tmp/project',
    );

    process.emitPermissionRequest(
      id: 1,
      params: {
        'sessionId': 'sess-2',
        'toolCall': {
          'toolCallId': 'call-2',
          'kind': 'read',
          'rawInput': {'path': '/tmp/a.txt'},
        },
        'options': [
          {'optionId': 'opt-1', 'name': 'Allow once'},
        ],
      },
    );

    final permission = await session.permissionRequests.first;
    permission.deny('no');

    await Future<void>.delayed(Duration.zero);

    expect(process.lastResponseId, 1);
    expect(process.lastResponse?['outcome'], {
      'outcome': 'cancelled',
    });

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

  Object? lastResponseId;
  Map<String, dynamic>? lastResponse;

  void emitPermissionRequest({
    required Object id,
    required Map<String, dynamic> params,
  }) {
    _serverRequestsController.add(JsonRpcServerRequest(
      id: id,
      method: 'session/request_permission',
      params: params,
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
  void sendResponse(Object id, Map<String, dynamic> result) {
    lastResponseId = id;
    lastResponse = result;
  }

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
