import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

/// Logger for ACP protocol messages.
///
/// Logs all incoming and outgoing JSON-RPC messages to a file for debugging.
/// Each message is written as a JSONL entry with metadata including timestamp,
/// direction, and connection ID.
///
/// Usage:
/// ```dart
/// // Enable logging (call once at startup)
/// ACPLogger.instance.enable('/tmp/acp.jsonl');
///
/// // Wrap the ACP stream (each wrap gets a unique connection ID)
/// final loggedStream = ACPLogger.instance.wrapStream(stream);
///
/// // Use loggedStream instead of stream
/// final connection = ClientSideConnection((_) => client, loggedStream);
///
/// // Disable when done
/// ACPLogger.instance.disable();
/// ```
///
/// Log format:
/// ```json
/// {"ts": "2024-01-15T10:30:00.000Z", "conn": "a1b2c3", "dir": "in", "msg": {...}}
/// ```
///
/// Filtering by connection:
/// ```bash
/// cat /tmp/acp.jsonl | jq 'select(.conn == "a1b2c3")'
/// ```
class ACPLogger {
  static ACPLogger? _instance;

  /// Gets the singleton instance of the ACP logger.
  static ACPLogger get instance {
    _instance ??= ACPLogger._();
    return _instance!;
  }

  ACPLogger._();

  IOSink? _sink;
  String? _logPath;
  bool _enabled = false;
  int _connectionCounter = 0;

  /// Whether logging is currently enabled.
  bool get isEnabled => _enabled;

  /// The path to the log file, if logging is enabled.
  String? get logPath => _logPath;

  /// Enables logging to the specified file.
  ///
  /// Creates or truncates the file at [path]. All subsequent ACP messages
  /// will be logged to this file in JSONL format.
  ///
  /// Each log entry has the format:
  /// ```json
  /// {"ts": "2024-01-15T10:30:00.000Z", "conn": "a1b2c3", "dir": "in", "msg": {...}}
  /// ```
  ///
  /// Where:
  /// - `ts` is the ISO8601 timestamp
  /// - `conn` is a short connection ID (unique per wrapStream call)
  /// - `dir` is "in" (from agent), "out" (to agent), or "info" (metadata)
  /// - `msg` is the raw JSON-RPC message or info payload
  void enable(String path) {
    if (_enabled) {
      disable();
    }

    try {
      final file = File(path);
      _sink = file.openWrite(mode: FileMode.write);
      _logPath = path;
      _enabled = true;
      _connectionCounter = 0;
      debugPrint('[ACPLogger] Logging enabled: $path');

      // Write header
      _logInfo(null, {'event': 'logging_started', 'path': path});
    } catch (e) {
      debugPrint('[ACPLogger] Failed to enable logging: $e');
      _enabled = false;
      _sink = null;
      _logPath = null;
    }
  }

  /// Disables logging and closes the log file.
  void disable() {
    if (!_enabled) return;

    _logInfo(null, {'event': 'logging_stopped'});
    _sink?.close();
    _sink = null;
    _logPath = null;
    _enabled = false;
    debugPrint('[ACPLogger] Logging disabled');
  }

  /// Generates a short unique connection ID.
  String _generateConnectionId() {
    _connectionCounter++;
    // Use a combination of counter and timestamp for uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${timestamp.toRadixString(36).substring(4)}${_connectionCounter.toRadixString(36)}';
  }

  /// Logs a message with the given direction and connection ID.
  void _log(String? connectionId, String direction, Map<String, dynamic> message) {
    if (!_enabled || _sink == null) return;

    try {
      final entry = <String, dynamic>{
        'ts': DateTime.now().toUtc().toIso8601String(),
        if (connectionId != null) 'conn': connectionId,
        'dir': direction,
        'msg': message,
      };
      _sink!.writeln(jsonEncode(entry));
    } catch (e) {
      debugPrint('[ACPLogger] Failed to write log entry: $e');
    }
  }

  /// Logs an info message (metadata, not a protocol message).
  void _logInfo(String? connectionId, Map<String, dynamic> info) {
    _log(connectionId, 'info', info);
  }

  /// Wraps an [AcpStream] to log all messages.
  ///
  /// Returns a new [AcpStream] that logs all incoming and outgoing messages
  /// while passing them through unchanged. Each call to this method generates
  /// a unique connection ID that is included in all log entries for that stream.
  ///
  /// The connection ID is logged in an info message when the stream is wrapped,
  /// making it easy to identify which connection each message belongs to.
  AcpStream wrapStream(AcpStream stream) {
    if (!_enabled) {
      return stream;
    }

    final connectionId = _generateConnectionId();
    _logInfo(connectionId, {'event': 'connection_started'});

    // Wrap readable stream to log incoming messages
    final loggingReadable = stream.readable.map((message) {
      _log(connectionId, 'in', message);
      return message;
    });

    // Wrap writable sink to log outgoing messages
    final loggingWritable = _LoggingSink(
      stream.writable,
      (message) => _log(connectionId, 'out', message),
      () => _logInfo(connectionId, {'event': 'connection_closed'}),
    );

    return AcpStream(
      readable: loggingReadable,
      writable: loggingWritable,
    );
  }

  /// Flushes the log file.
  Future<void> flush() async {
    await _sink?.flush();
  }
}

/// A [StreamSink] wrapper that logs messages before forwarding them.
class _LoggingSink implements StreamSink<Map<String, dynamic>> {
  final StreamSink<Map<String, dynamic>> _inner;
  final void Function(Map<String, dynamic>) _onMessage;
  final void Function() _onClose;

  _LoggingSink(this._inner, this._onMessage, this._onClose);

  @override
  void add(Map<String, dynamic> event) {
    _onMessage(event);
    _inner.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _inner.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<Map<String, dynamic>> stream) {
    return _inner.addStream(stream.map((event) {
      _onMessage(event);
      return event;
    }));
  }

  @override
  Future close() {
    _onClose();
    return _inner.close();
  }

  @override
  Future get done => _inner.done;
}
