import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('config_option_update emits ConfigOptionsEvent', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-config-1',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-config-1',
      update: {
        'sessionUpdate': 'config_option_update',
        'configOptions': [
          {'id': 'model', 'category': 'model'},
        ],
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as ConfigOptionsEvent;
    expect(event.configOptions.first['id'], 'model');

    await sub.cancel();
    await session.dispose();
  });

  test('current_mode_update emits SessionModeEvent', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-config-2',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-config-2',
      update: {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'fast',
        'modes': [
          {'id': 'fast', 'name': 'Fast'},
          {'id': 'accurate', 'name': 'Accurate'},
        ],
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as SessionModeEvent;
    expect(event.currentModeId, 'fast');
    expect(event.availableModes, hasLength(2));

    await sub.cancel();
    await session.dispose();
  });

  test('session/new emits config options and mode events', () async {
    final process = _MockAcpProcess()
      ..sessionConfigOptions = [
        {'id': 'model', 'category': 'model'},
      ]
      ..sessionModes = [
        {'id': 'fast', 'name': 'Fast'},
      ]
      ..sessionCurrentModeId = 'fast';

    final backend = AcpBackend.createForTesting(process: process);
    final session = await backend.createSession(
      prompt: '',
      cwd: '/tmp/project',
    );

    final events = await session.events.take(3).toList();
    expect(events[0], isA<SessionInitEvent>());
    expect(events[1], isA<ConfigOptionsEvent>());
    expect(events[2], isA<SessionModeEvent>());

    await backend.dispose();
  });

  test('setModel sends session/set_config_option and emits update', () async {
    final process = _MockAcpProcess()
      ..sessionConfigOptions = [
        {'id': 'model', 'category': 'model'},
      ]
      ..sessionModes = [
        {'id': 'fast', 'name': 'Fast'},
      ]
      ..sessionCurrentModeId = 'fast'
      ..setConfigOptionsResponse = [
        {'id': 'model', 'category': 'model', 'value': 'model-2'},
      ];

    final backend = AcpBackend.createForTesting(process: process);
    final session = await backend.createSession(
      prompt: '',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    await Future<void>.delayed(Duration.zero);
    events.clear();

    await session.setModel('model-2');
    await Future<void>.delayed(Duration.zero);

    final call = process.calls.last;
    expect(call.method, 'session/set_config_option');
    expect(call.params?['configId'], 'model');
    expect(call.params?['value'], 'model-2');
    expect(events.whereType<ConfigOptionsEvent>(), hasLength(1));

    await sub.cancel();
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

  List<Map<String, dynamic>>? sessionConfigOptions;
  List<Map<String, dynamic>>? sessionModes;
  String? sessionCurrentModeId;
  List<Map<String, dynamic>>? setConfigOptionsResponse;

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
  AcpInitializeResult? get initializeResult => const AcpInitializeResult(
        protocolVersion: 1,
      );

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
    calls.add(_CallRecord(method, params));

    if (method == 'session/new') {
      return {
        'sessionId': 'session-456',
        if (sessionConfigOptions != null)
          'configOptions': sessionConfigOptions,
        if (sessionModes != null) 'modes': sessionModes,
        if (sessionCurrentModeId != null)
          'currentModeId': sessionCurrentModeId,
      };
    }

    if (method == 'session/set_config_option') {
      return {
        if (setConfigOptionsResponse != null)
          'configOptions': setConfigOptionsResponse,
      };
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
