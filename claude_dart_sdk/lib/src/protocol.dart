import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'types/content_blocks.dart';
import 'types/sdk_messages.dart';
import 'types/errors.dart';

/// Outgoing message types (Dart → Backend).
sealed class OutgoingMessage {
  const OutgoingMessage();

  Map<String, dynamic> toJson();
}

class SessionCreateMessage extends OutgoingMessage {
  const SessionCreateMessage({
    required this.id,
    required this.prompt,
    required this.cwd,
    this.options,
    this.content,
  });

  final String id;
  final String prompt;
  final String cwd;
  final Map<String, dynamic>? options;
  final List<ContentBlock>? content;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'session.create',
        'id': id,
        'payload': {
          'prompt': prompt,
          'cwd': cwd,
          if (options != null) 'options': options,
          if (content != null)
            'content': content!.map((c) => c.toJson()).toList(),
        },
      };
}

class SessionSendMessage extends OutgoingMessage {
  const SessionSendMessage({
    required this.id,
    required this.sessionId,
    this.message,
    this.content,
  }) : assert(
         message != null || content != null,
         'Either message or content must be provided',
       );

  final String id;
  final String sessionId;
  final String? message;
  final List<ContentBlock>? content;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'session.send',
        'id': id,
        'session_id': sessionId,
        'payload': {
          if (message != null) 'message': message,
          if (content != null)
            'content': content!.map((c) => c.toJson()).toList(),
        },
      };
}

class SessionInterruptMessage extends OutgoingMessage {
  const SessionInterruptMessage({
    required this.id,
    required this.sessionId,
  });

  final String id;
  final String sessionId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'session.interrupt',
        'id': id,
        'session_id': sessionId,
        'payload': {},
      };
}

class SessionKillMessage extends OutgoingMessage {
  const SessionKillMessage({
    required this.id,
    required this.sessionId,
  });

  final String id;
  final String sessionId;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'session.kill',
        'id': id,
        'session_id': sessionId,
        'payload': {},
      };
}

class CallbackResponseMessage extends OutgoingMessage {
  const CallbackResponseMessage({
    required this.id,
    required this.sessionId,
    required this.payload,
  });

  final String id;
  final String sessionId;
  final Map<String, dynamic> payload;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'callback.response',
        'id': id,
        'session_id': sessionId,
        'payload': payload,
      };
}

class QueryCallMessage extends OutgoingMessage {
  const QueryCallMessage({
    required this.id,
    required this.sessionId,
    required this.method,
    this.args,
  });

  final String id;
  final String sessionId;
  final String method;
  final List<dynamic>? args;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'query.call',
        'id': id,
        'session_id': sessionId,
        'payload': {
          'method': method,
          if (args != null) 'args': args,
        },
      };
}

/// Incoming message types (Backend → Dart).
sealed class IncomingMessage {
  const IncomingMessage();

  static IncomingMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    switch (type) {
      case 'session.created':
        return SessionCreatedMessage.fromJson(json);
      case 'sdk.message':
        return SdkMessageMessage.fromJson(json);
      case 'callback.request':
        return CallbackRequestMessage.fromJson(json);
      case 'query.result':
        return QueryResultMessage.fromJson(json);
      case 'session.interrupted':
        return SessionInterruptedMessage.fromJson(json);
      case 'session.killed':
        return SessionKilledMessage.fromJson(json);
      case 'error':
        return ErrorMessage.fromJson(json);
      default:
        return UnknownIncomingMessage(json);
    }
  }
}

class SessionCreatedMessage extends IncomingMessage {
  const SessionCreatedMessage({
    required this.id,
    required this.sessionId,
    this.sdkSessionId,
  });

  final String id;
  final String sessionId;
  final String? sdkSessionId;

  factory SessionCreatedMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return SessionCreatedMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      sdkSessionId: payload['sdk_session_id'] as String?,
    );
  }
}

class SdkMessageMessage extends IncomingMessage {
  const SdkMessageMessage({
    required this.sessionId,
    required this.payload,
  });

  final String sessionId;
  final SDKMessage payload;

  factory SdkMessageMessage.fromJson(Map<String, dynamic> json) {
    return SdkMessageMessage(
      sessionId: json['session_id'] as String? ?? '',
      payload: SDKMessage.fromJson(json['payload'] as Map<String, dynamic>),
    );
  }
}

class CallbackRequestMessage extends IncomingMessage {
  const CallbackRequestMessage({
    required this.id,
    required this.sessionId,
    required this.callbackType,
    this.toolName,
    this.toolInput,
    this.suggestions,
    this.hookEvent,
    this.hookInput,
    this.toolUseId,
    this.agentId,
    this.blockedPath,
    this.decisionReason,
    this.rawJson,
  });

  final String id;
  final String sessionId;
  final String callbackType; // 'can_use_tool' or 'hook'
  final String? toolName;
  final Map<String, dynamic>? toolInput;
  final List<dynamic>? suggestions;
  final String? hookEvent;
  final dynamic hookInput;
  // Permission context from SDK (for can_use_tool callbacks)
  final String? toolUseId;
  final String? agentId;
  final String? blockedPath;
  final String? decisionReason;
  // Original JSON for debugging
  final Map<String, dynamic>? rawJson;

  factory CallbackRequestMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return CallbackRequestMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      callbackType: payload['callback_type'] as String? ?? '',
      toolName: payload['tool_name'] as String?,
      toolInput: payload['tool_input'] as Map<String, dynamic>?,
      suggestions: payload['suggestions'] as List?,
      hookEvent: payload['hook_event'] as String?,
      hookInput: payload['hook_input'],
      toolUseId: payload['tool_use_id'] as String?,
      agentId: payload['agent_id'] as String?,
      blockedPath: payload['blocked_path'] as String?,
      decisionReason: payload['decision_reason'] as String?,
      rawJson: json,
    );
  }
}

class QueryResultMessage extends IncomingMessage {
  const QueryResultMessage({
    required this.id,
    required this.sessionId,
    required this.success,
    this.result,
    this.error,
  });

  final String id;
  final String sessionId;
  final bool success;
  final dynamic result;
  final String? error;

  factory QueryResultMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return QueryResultMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      success: payload['success'] as bool? ?? false,
      result: payload['result'],
      error: payload['error'] as String?,
    );
  }
}

class SessionInterruptedMessage extends IncomingMessage {
  const SessionInterruptedMessage({
    required this.id,
    required this.sessionId,
  });

  final String id;
  final String sessionId;

  factory SessionInterruptedMessage.fromJson(Map<String, dynamic> json) {
    return SessionInterruptedMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
    );
  }
}

class SessionKilledMessage extends IncomingMessage {
  const SessionKilledMessage({
    required this.id,
    required this.sessionId,
  });

  final String id;
  final String sessionId;

  factory SessionKilledMessage.fromJson(Map<String, dynamic> json) {
    return SessionKilledMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
    );
  }
}

class ErrorMessage extends IncomingMessage {
  const ErrorMessage({
    this.id,
    this.sessionId,
    required this.code,
    required this.message,
    this.details,
  });

  final String? id;
  final String? sessionId;
  final String code;
  final String message;
  final dynamic details;

  factory ErrorMessage.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    return ErrorMessage(
      id: json['id'] as String?,
      sessionId: json['session_id'] as String?,
      code: payload['code'] as String? ?? 'UNKNOWN',
      message: payload['message'] as String? ?? 'Unknown error',
      details: payload['details'],
    );
  }
}

class UnknownIncomingMessage extends IncomingMessage {
  const UnknownIncomingMessage(this.raw);

  final Map<String, dynamic> raw;
}

/// Protocol handler for JSON line communication with the backend process.
class Protocol {
  Protocol({
    required this.process,
    required this.onMessage,
    required this.onError,
    bool enableFileLogging = true,
  }) {
    if (enableFileLogging) {
      _setupFileLogging();
    }
    _subscribeToStdout();
    _subscribeToStderr();
  }

  final Process process;
  final void Function(IncomingMessage) onMessage;
  final void Function(ClaudeError) onError;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  final _stderrController = StreamController<String>.broadcast();
  final _stderrBuffer = <String>[]; // Buffer recent stderr lines
  static const _maxBufferSize = 1000;
  IOSink? _logFileSink;
  String? _logFilePath;

  /// Stream of backend stderr log lines.
  /// Note: This replays the last 1000 buffered lines to new subscribers.
  Stream<String> get stderrLogs async* {
    // First, yield all buffered lines
    for (final line in _stderrBuffer) {
      yield line;
    }
    // Then, stream new lines
    yield* _stderrController.stream;
  }

  /// Get buffered stderr lines (for error reporting on startup failure).
  List<String> getBufferedStderr() => List.unmodifiable(_stderrBuffer);

  /// Path to the log file, if file logging is enabled.
  String? get logFilePath => _logFilePath;

  void _setupFileLogging() {
    try {
      final tmpDir = Directory.systemTemp;
      final logDir = Directory(p.join(tmpDir.path, 'claude-agent-insights'));

      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]+'), '-');
      _logFilePath = p.join(logDir.path, 'dart-sdk-$timestamp.log');

      final logFile = File(_logFilePath!);
      _logFileSink = logFile.openWrite(mode: FileMode.append);

      // Log the file location
      _writeLog('Dart SDK logging to: $_logFilePath');
    } catch (e) {
      // If file logging fails, just continue without it
      // ignore: avoid_print
      print('[Protocol] Failed to setup file logging: $e');
    }
  }

  void _writeLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';

    // Write to file if available
    _logFileSink?.writeln(line);

    // Also print for debugging
    // ignore: avoid_print
    print('[backend] $message');
  }

  void _subscribeToStdout() {
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
  }

  void _subscribeToStderr() {
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // Add to buffer (with size limit)
      _stderrBuffer.add(line);
      if (_stderrBuffer.length > _maxBufferSize) {
        _stderrBuffer.removeAt(0);
      }

      // Emit to stream
      _stderrController.add(line);

      // Write to log
      _writeLog(line);
    });
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final message = IncomingMessage.fromJson(json);
      onMessage(message);
    } catch (e) {
      onError(CommunicationError('Failed to parse message: $e'));
    }
  }

  /// Send a message to the backend.
  void send(OutgoingMessage message) {
    final messageJson = message.toJson();
    var json = jsonEncode(messageJson);
    // Escape U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR).
    // Node's readline splits on these Unicode line terminators, breaking JSON parsing.
    json = json.replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
    process.stdin.writeln(json);
  }

  /// Dispose of the protocol handler.
  Future<void> dispose() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    await _stderrController.close();
    await _logFileSink?.flush();
    await _logFileSink?.close();
  }
}
