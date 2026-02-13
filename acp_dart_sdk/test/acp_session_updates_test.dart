import 'dart:async';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('agent_message_chunk emits stream deltas', () async {
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
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Hello'},
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect((events[0] as StreamDeltaEvent).kind, StreamDeltaKind.messageStart);
    expect((events[1] as StreamDeltaEvent).kind, StreamDeltaKind.blockStart);
    final textEvent = events[2] as StreamDeltaEvent;
    expect(textEvent.kind, StreamDeltaKind.text);
    expect(textEvent.textDelta, 'Hello');

    await sub.cancel();
    await session.dispose();
  });

  test('agent_thought_chunk emits thinking stream deltas', () async {
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
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'Thinking...'},
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect((events[0] as StreamDeltaEvent).kind, StreamDeltaKind.messageStart);
    final blockStart = events[1] as StreamDeltaEvent;
    expect(blockStart.kind, StreamDeltaKind.blockStart);
    expect(blockStart.extensions?['block_type'], 'thinking');
    final textEvent = events[2] as StreamDeltaEvent;
    expect(textEvent.kind, StreamDeltaKind.thinking);
    expect(textEvent.textDelta, 'Thinking...');

    await sub.cancel();
    await session.dispose();
  });

  test('plan maps to TextEvent with plan entries extension', () async {
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
        'sessionUpdate': 'plan',
        'entries': [
          {'text': 'Step 1'},
          {'text': 'Step 2'},
        ],
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as TextEvent;
    expect(event.kind, TextKind.plan);
    expect(event.text, 'Step 1\nStep 2');
    expect(event.extensions?['acp.planEntries'], isA<List<dynamic>>());

    await sub.cancel();
    await session.dispose();
  });

  test('user_message_chunk maps to synthetic UserInputEvent', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-4',
      cwd: '/tmp/project',
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-4',
      update: {
        'sessionUpdate': 'user_message_chunk',
        'content': {'type': 'text', 'text': 'Replay'},
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    final event = events.first as UserInputEvent;
    expect(event.isSynthetic, isTrue);
    expect(event.text, 'Replay');

    await sub.cancel();
    await session.dispose();
  });

  test('includePartialMessages emits stream deltas', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-5',
      cwd: '/tmp/project',
      includePartialMessages: true,
    );

    final events = <InsightsEvent>[];
    final sub = session.events.listen(events.add);

    process.emitUpdate(
      sessionId: 'sess-5',
      update: {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'Stream'},
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    expect((events[0] as StreamDeltaEvent).kind, StreamDeltaKind.messageStart);
    expect((events[1] as StreamDeltaEvent).kind, StreamDeltaKind.blockStart);
    expect((events[2] as StreamDeltaEvent).kind, StreamDeltaKind.text);

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
