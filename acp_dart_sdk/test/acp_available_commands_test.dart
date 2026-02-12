import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('available_commands_update emits AvailableCommandsEvent', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-cmd-1',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-cmd-1',
      update: {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'id': 'help', 'name': 'Help'},
          {'id': 'status', 'name': 'Status'},
        ],
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as AvailableCommandsEvent;
    expect(event.availableCommands, hasLength(2));

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
