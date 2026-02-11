import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_sdk_core/agent_sdk_core.dart';

/// JSON-RPC server notification.
class JsonRpcNotification {
  const JsonRpcNotification({required this.method, this.params});

  final String method;
  final Map<String, dynamic>? params;
}

/// JSON-RPC server request.
class JsonRpcServerRequest {
  const JsonRpcServerRequest({
    required this.id,
    required this.method,
    this.params,
  });

  final Object id;
  final String method;
  final Map<String, dynamic>? params;
}

/// JSON-RPC error response.
class JsonRpcError implements Exception {
  const JsonRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  final int code;
  final String message;
  final dynamic data;

  @override
  String toString() => 'JsonRpcError($code): $message';
}

/// Lightweight JSON-RPC client for line-delimited stdin/stdout.
class JsonRpcClient {
  JsonRpcClient({
    required Stream<String> input,
    required void Function(String) output,
  })  : _output = output,
        _inputSub = input.listen(null) {
    _initEdgeLogging();
    _inputSub
      ..onData(_handleLine)
      ..onError(_handleError)
      ..onDone(_handleDone);
  }

  final void Function(String) _output;
  final StreamSubscription<String> _inputSub;

  File? _edgeLogFile;
  final _notifications = StreamController<JsonRpcNotification>.broadcast();
  final _serverRequests =
      StreamController<JsonRpcServerRequest>.broadcast();
  final _protocolLogEntries = StreamController<LogEntry>.broadcast();

  final _pending = <Object, Completer<Map<String, dynamic>>>{};

  int _nextId = 1;
  bool _disposed = false;

  Stream<JsonRpcNotification> get notifications => _notifications.stream;
  Stream<JsonRpcServerRequest> get serverRequests => _serverRequests.stream;

  /// Stream of structured protocol log entries.
  Stream<LogEntry> get protocolLogEntries => _protocolLogEntries.stream;

  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic>? params,
  ) {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _send({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });

    return completer.future;
  }

  void sendNotification(String method, Map<String, dynamic>? params) {
    _send({
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    });
  }

  void sendResponse(Object id, Map<String, dynamic> result) {
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });
  }

  void sendError(Object id, int code, String message, {dynamic data}) {
    _send({
      'jsonrpc': '2.0',
      'id': id,
      'error': {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      },
    });
  }

  void _send(Map<String, dynamic> message) {
    if (_disposed) return;
    final json = jsonEncode(message)
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
    _logEdge('sdk-stdin', message);
    SdkLogger.instance.logOutgoing(message);
    _protocolLogEntries.add(LogEntry(
      level: LogLevel.debug,
      message: 'SEND',
      timestamp: DateTime.now(),
      direction: LogDirection.stdin,
      data: message,
    ));
    _output(json);
  }

  void _handleLine(String line) {
    if (_disposed || line.isEmpty) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      _logEdge('sdk-stdout', {'raw': line});
      _protocolLogEntries.add(LogEntry(
        level: LogLevel.warning,
        message: 'Failed to parse JSON-RPC line',
        timestamp: DateTime.now(),
        direction: LogDirection.stdout,
        text: line,
      ));
      return;
    }

    _logEdge('sdk-stdout', json);
    SdkLogger.instance.logIncoming(json);
    _protocolLogEntries.add(LogEntry(
      level: LogLevel.debug,
      message: 'RECV',
      timestamp: DateTime.now(),
      direction: LogDirection.stdout,
      data: json,
    ));

    if (json.containsKey('method')) {
      final method = json['method'] as String?;
      if (method == null || method.isEmpty) return;
      final params = json['params'] as Map<String, dynamic>?;
      if (json.containsKey('id')) {
        final id = json['id'] as Object;
        _serverRequests.add(
          JsonRpcServerRequest(id: id, method: method, params: params),
        );
      } else {
        _notifications.add(JsonRpcNotification(method: method, params: params));
      }
      return;
    }

    if (json.containsKey('id')) {
      final id = json['id'] as Object;
      final completer = _pending.remove(id);
      if (completer == null) return;

      if (json.containsKey('error')) {
        final err = json['error'] as Map<String, dynamic>? ?? {};
        completer.completeError(JsonRpcError(
          code: (err['code'] as num?)?.toInt() ?? -1,
          message: err['message'] as String? ?? 'Unknown error',
          data: err['data'],
        ));
      } else {
        final result = json['result'] as Map<String, dynamic>? ?? {};
        completer.complete(result);
      }
    }
  }

  void _initEdgeLogging() {
    final env = Platform.environment;
    final path =
        env['CODEX_RPC_LOG_FILE'] ??
            env['CC_INSIGHTS_CODEX_RPC_LOG_FILE'];
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _edgeLogFile = file;
    } catch (_) {
      _edgeLogFile = null;
    }
  }

  void _logEdge(String type, Object message) {
    final file = _edgeLogFile;
    if (file == null) return;

    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'type': type,
      'message': message,
    };

    try {
      file.writeAsStringSync(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // Ignore write errors to avoid impacting runtime behavior.
    }
  }

  void _handleError(Object error) {
    if (_disposed) return;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _handleDone() {
    if (_disposed) return;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('JSON-RPC connection closed'));
      }
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('JSON-RPC client disposed'));
      }
    }
    _pending.clear();
    await _inputSub.cancel();
    await _notifications.close();
    await _serverRequests.close();
    await _protocolLogEntries.close();
  }
}
