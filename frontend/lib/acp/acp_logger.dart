import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

/// Logger for ACP protocol messages.
///
/// Logs all incoming and outgoing JSON-RPC messages to a file for debugging.
/// Each message is written as a JSONL entry with metadata (timestamp, direction).
///
/// Usage:
/// ```dart
/// // Enable logging (call once at startup)
/// ACPLogger.instance.enable('/tmp/acp.jsonl');
///
/// // Wrap the ACP stream
/// final loggedStream = ACPLogger.instance.wrapStream(stream);
///
/// // Use loggedStream instead of stream
/// final connection = ClientSideConnection((_) => client, loggedStream);
///
/// // Disable when done
/// ACPLogger.instance.disable();
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
  /// {"ts": "2024-01-15T10:30:00.000Z", "dir": "in", "msg": {...}}
  /// ```
  ///
  /// Where:
  /// - `ts` is the ISO8601 timestamp
  /// - `dir` is "in" (from agent) or "out" (to agent)
  /// - `msg` is the raw JSON-RPC message
  void enable(String path) {
    if (_enabled) {
      disable();
    }

    try {
      final file = File(path);
      _sink = file.openWrite(mode: FileMode.write);
      _logPath = path;
      _enabled = true;
      debugPrint('[ACPLogger] Logging enabled: $path');

      // Write header
      _log('info', {'event': 'logging_started', 'path': path});
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

    _log('info', {'event': 'logging_stopped'});
    _sink?.close();
    _sink = null;
    _logPath = null;
    _enabled = false;
    debugPrint('[ACPLogger] Logging disabled');
  }

  /// Logs a message with the given direction.
  void _log(String direction, Map<String, dynamic> message) {
    if (!_enabled || _sink == null) return;

    try {
      final entry = {
        'ts': DateTime.now().toUtc().toIso8601String(),
        'dir': direction,
        'msg': message,
      };
      _sink!.writeln(jsonEncode(entry));
    } catch (e) {
      debugPrint('[ACPLogger] Failed to write log entry: $e');
    }
  }

  /// Logs an incoming message (from agent).
  void logIncoming(Map<String, dynamic> message) {
    _log('in', message);
  }

  /// Logs an outgoing message (to agent).
  void logOutgoing(Map<String, dynamic> message) {
    _log('out', message);
  }

  /// Wraps an [AcpStream] to log all messages.
  ///
  /// Returns a new [AcpStream] that logs all incoming and outgoing messages
  /// while passing them through unchanged.
  AcpStream wrapStream(AcpStream stream) {
    if (!_enabled) {
      return stream;
    }

    // Wrap readable stream to log incoming messages
    final loggingReadable = stream.readable.map((message) {
      logIncoming(message);
      return message;
    });

    // Wrap writable sink to log outgoing messages
    final loggingWritable = _LoggingSink(
      stream.writable,
      (message) => logOutgoing(message),
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

  _LoggingSink(this._inner, this._onMessage);

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
  Future close() => _inner.close();

  @override
  Future get done => _inner.done;
}
