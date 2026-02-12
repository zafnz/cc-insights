import 'dart:async';
import 'dart:io';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('creates terminal and returns output', () async {
    final tempDir = await Directory.systemTemp.createTemp('acp-term-');
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-term-1',
      cwd: tempDir.path,
    );

    process.emitRequest(
      id: 1,
      method: 'terminal/create',
      params: {
        'command': '/bin/sh',
        'args': ['-c', 'printf "hello"'],
        'cwd': tempDir.path,
      },
    );

    await _pumpEventQueue();

    final terminalId = process.lastResponse?['terminalId'] as String?;
    expect(terminalId, isNotNull);

    process.emitRequest(
      id: 2,
      method: 'terminal/wait_for_exit',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    process.emitRequest(
      id: 3,
      method: 'terminal/output',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    final output = process.lastResponse?['output'] as String? ?? '';
    expect(output, contains('hello'));
    expect(process.lastResponse?['truncated'], isFalse);

    process.emitRequest(
      id: 4,
      method: 'terminal/release',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    expect(process.lastResponseId, 4);

    await session.dispose();
    await tempDir.delete(recursive: true);
  });

  test('truncates output when outputByteLimit is set', () async {
    final tempDir = await Directory.systemTemp.createTemp('acp-term-');
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-term-2',
      cwd: tempDir.path,
    );

    process.emitRequest(
      id: 10,
      method: 'terminal/create',
      params: {
        'command': '/bin/sh',
        'args': ['-c', 'printf "abcdef"'],
        'cwd': tempDir.path,
        'outputByteLimit': 4,
      },
    );

    await _pumpEventQueue();

    final terminalId = process.lastResponse?['terminalId'] as String?;
    expect(terminalId, isNotNull);

    process.emitRequest(
      id: 11,
      method: 'terminal/wait_for_exit',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    process.emitRequest(
      id: 12,
      method: 'terminal/output',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    final firstOutput = process.lastResponse?['output'] as String? ?? '';
    expect(firstOutput.length, lessThanOrEqualTo(4));
    expect(process.lastResponse?['truncated'], isTrue);

    process.emitRequest(
      id: 13,
      method: 'terminal/output',
      params: {'terminalId': terminalId},
    );

    await _pumpEventQueue();

    final secondOutput = process.lastResponse?['output'] as String? ?? '';
    expect('$firstOutput$secondOutput', 'abcdef');

    await session.dispose();
    await tempDir.delete(recursive: true);
  });
}

Future<void> _pumpEventQueue() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

class _MockAcpProcess implements AcpProcess {
  final _notificationsController =
      StreamController<JsonRpcNotification>.broadcast();
  final _serverRequestsController =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _logsController = StreamController<String>.broadcast();
  final _logEntriesController = StreamController<LogEntry>.broadcast();

  Object? lastResponseId;
  Map<String, dynamic>? lastResponse;
  int? lastErrorCode;

  void emitRequest({
    required Object id,
    required String method,
    required Map<String, dynamic> params,
  }) {
    _serverRequestsController.add(JsonRpcServerRequest(
      id: id,
      method: method,
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
  void sendError(Object id, int code, String message, {dynamic data}) {
    lastErrorCode = code;
  }

  @override
  Future<void> dispose() async {
    await _notificationsController.close();
    await _serverRequestsController.close();
    await _logsController.close();
    await _logEntriesController.close();
  }
}
