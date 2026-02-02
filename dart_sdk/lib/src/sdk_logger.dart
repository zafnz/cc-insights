import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Log level for SDK messages.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// A log entry from the SDK.
class LogEntry {
  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.sessionId,
    this.data,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String? sessionId;
  final Map<String, dynamic>? data;

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}]');
    buffer.write('[${level.name.toUpperCase()}]');
    if (sessionId != null) {
      buffer.write('[session:$sessionId]');
    }
    buffer.write(' $message');
    if (data != null) {
      buffer.write('\n  ${jsonEncode(data)}');
    }
    return buffer.toString();
  }
}

/// Logger for the Claude SDK.
///
/// Provides configurable logging for debugging CLI communication.
/// Can be enabled via environment variable or programmatically.
///
/// Environment variables:
/// - `CLAUDE_SDK_DEBUG=true` - Enable debug logging
/// - `CLAUDE_SDK_LOG_FILE=/path/to/log` - Write logs to file
///
/// Example:
/// ```dart
/// // Enable programmatically
/// SdkLogger.instance.debugEnabled = true;
///
/// // Subscribe to log stream
/// SdkLogger.instance.logs.listen((entry) {
///   print(entry);
/// });
/// ```
class SdkLogger {
  SdkLogger._() {
    // Check environment variable for debug mode
    final envDebug = Platform.environment['CLAUDE_SDK_DEBUG'];
    if (envDebug != null &&
        (envDebug.toLowerCase() == 'true' || envDebug == '1')) {
      _debugEnabled = true;
    }

    // Check for log file
    final logFilePath = Platform.environment['CLAUDE_SDK_LOG_FILE'];
    if (logFilePath != null && logFilePath.isNotEmpty) {
      _setupFileLogging(logFilePath);
    }
  }

  static final SdkLogger instance = SdkLogger._();

  bool _debugEnabled = false;
  IOSink? _logFileSink;
  String? _logFilePath;

  final _logsController = StreamController<LogEntry>.broadcast();

  /// Whether debug logging is enabled.
  bool get debugEnabled => _debugEnabled;

  /// Enable or disable debug logging.
  set debugEnabled(bool value) {
    _debugEnabled = value;
    if (value) {
      info('Debug logging enabled');
    }
  }

  /// Stream of all log entries.
  ///
  /// Subscribe to receive log entries as they are generated.
  /// This includes debug messages (when enabled), info, warnings, and errors.
  Stream<LogEntry> get logs => _logsController.stream;

  /// Path to the log file, if file logging is enabled.
  String? get logFilePath => _logFilePath;

  /// Enable file logging to the specified path.
  void enableFileLogging(String path) {
    _setupFileLogging(path);
  }

  /// Disable file logging.
  Future<void> disableFileLogging() async {
    await _logFileSink?.flush();
    await _logFileSink?.close();
    _logFileSink = null;
    _logFilePath = null;
  }

  void _setupFileLogging(String path) {
    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _logFileSink = file.openWrite(mode: FileMode.append);
      _logFilePath = path;
      info('File logging enabled: $path');
    } catch (e) {
      error('Failed to setup file logging: $e');
    }
  }

  /// Log a debug message.
  ///
  /// Only emitted when [debugEnabled] is true.
  void debug(String message, {String? sessionId, Map<String, dynamic>? data}) {
    if (!_debugEnabled) return;
    _log(LogLevel.debug, message, sessionId: sessionId, data: data);
  }

  /// Log an info message.
  void info(String message, {String? sessionId, Map<String, dynamic>? data}) {
    _log(LogLevel.info, message, sessionId: sessionId, data: data);
  }

  /// Log a warning message.
  void warning(String message,
      {String? sessionId, Map<String, dynamic>? data}) {
    _log(LogLevel.warning, message, sessionId: sessionId, data: data);
  }

  /// Log an error message.
  void error(String message, {String? sessionId, Map<String, dynamic>? data}) {
    _log(LogLevel.error, message, sessionId: sessionId, data: data);
  }

  /// Log a message sent TO the CLI (stdin).
  void logOutgoing(Map<String, dynamic> message, {String? sessionId}) {
    debug('>>> SEND', sessionId: sessionId, data: message);
  }

  /// Log a message received FROM the CLI (stdout).
  void logIncoming(Map<String, dynamic> message, {String? sessionId}) {
    debug('<<< RECV', sessionId: sessionId, data: message);
  }

  /// Log stderr output from the CLI.
  void logStderr(String line, {String? sessionId}) {
    // Stderr is always logged as info level (it's operational, not debug)
    info('CLI stderr: $line', sessionId: sessionId);
  }

  void _log(
    LogLevel level,
    String message, {
    String? sessionId,
    Map<String, dynamic>? data,
  }) {
    final entry = LogEntry(
      level: level,
      message: message,
      timestamp: DateTime.now(),
      sessionId: sessionId,
      data: data,
    );

    // Emit to stream
    if (!_logsController.isClosed) {
      _logsController.add(entry);
    }

    // Write to file if enabled
    _logFileSink?.writeln(entry.toString());
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await disableFileLogging();
    await _logsController.close();
  }
}
