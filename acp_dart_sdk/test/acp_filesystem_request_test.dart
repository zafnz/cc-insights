import 'dart:async';
import 'dart:io';

import 'package:acp_sdk/acp_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('rejects non-absolute paths', () async {
    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-1',
      cwd: Directory.systemTemp.path,
    );

    process.emitRequest(
      id: 1,
      method: 'fs/read_text_file',
      params: {'path': 'relative.txt'},
    );

    await Future<void>.delayed(Duration.zero);

    expect(process.lastErrorCode, -32602);

    await session.dispose();
  });

  test('reads file within root', () async {
    final tempDir = await Directory.systemTemp.createTemp('acp-read-');
    final file = File('${tempDir.path}/file.txt');
    await file.writeAsString('line1\nline2');

    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-2',
      cwd: tempDir.path,
    );

    process.emitRequest(
      id: 2,
      method: 'fs/read_text_file',
      params: {'path': file.path},
    );

    await Future<void>.delayed(Duration(milliseconds: 10));

    expect(process.lastResponseId, 2);
    expect(process.lastResponse?['content'], 'line1\nline2');

    await session.dispose();
    await tempDir.delete(recursive: true);
  });

  test('out-of-scope read requests permission and denies by default', () async {
    final tempDir = await Directory.systemTemp.createTemp('acp-root-');
    final outsideDir = await Directory.systemTemp.createTemp('acp-outside-');
    final file = File('${outsideDir.path}/secret.txt');
    await file.writeAsString('secret');

    final process = _MockAcpProcess();
    final session = AcpSession(
      process: process,
      sessionId: 'sess-3',
      cwd: tempDir.path,
    );

    final permissionFuture = session.permissionRequests.first;

    process.emitRequest(
      id: 3,
      method: 'fs/read_text_file',
      params: {'path': file.path},
    );

    final permission = await permissionFuture;
    permission.deny('no');

    await Future<void>.delayed(Duration(milliseconds: 10));

    expect(process.lastErrorCode, -32000);

    await session.dispose();
    await tempDir.delete(recursive: true);
    await outsideDir.delete(recursive: true);
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
