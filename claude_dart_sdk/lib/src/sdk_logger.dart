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

/// Direction of a logged message.
enum LogDirection {
  stdin,
  stdout,
  stderr,
  internal,
}

/// A log entry from the SDK.
class LogEntry {
  const LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.direction,
    this.sessionId,
    this.data,
    this.text,
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final LogDirection? direction;
  final String? sessionId;
  final Map<String, dynamic>? data;
  final String? text;

  /// Convert to a valid JSON object for JSONL output.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
    };

    if (direction != null) {
      json['direction'] = direction!.name;
    }

    if (sessionId != null) {
      json['sessionId'] = sessionId;
    }

    // If we have structured data (JSON content), include it
    if (data != null) {
      json['content'] = data;
    } else if (text != null) {
      // For non-JSON content (like stderr), use text field
      json['text'] = text;
    } else {
      // For simple log messages
      json['message'] = message;
    }

    return json;
  }

  /// Convert to JSONL format (single line JSON).
  String toJsonLine() {
    return jsonEncode(toJson());
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}]');
    buffer.write('[${level.name.toUpperCase()}]');
    if (direction != null) {
      buffer.write('[${direction!.name}]');
    }
    if (sessionId != null) {
      buffer.write('[session:$sessionId]');
    }
    buffer.write(' $message');
    if (data != null) {
      buffer.write('\n  ${jsonEncode(data)}');
    } else if (text != null) {
      buffer.write('\n  $text');
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
  File? _logFile;
  String? _logFilePath;

  // Write queue to prevent concurrent write corruption
  final _writeQueue = <String>[];
  bool _isWriting = false;

  final _logsController = StreamController<LogEntry>.broadcast();

  /// Whether debug logging is enabled.
  bool get debugEnabled => _debugEnabled;

  /// Enable or disable debug logging.
  set debugEnabled(bool value) {
    if (_debugEnabled == value) return;
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
    if (_logFilePath == path) return;
    _setupFileLogging(path);
  }

  /// Disable file logging.
  Future<void> disableFileLogging() async {
    // Wait for pending writes to complete
    while (_isWriting || _writeQueue.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _logFile = null;
    _logFilePath = null;
  }

  void _setupFileLogging(String path) {
    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _logFile = file;
      _logFilePath = path;
      info('File logging enabled: $path');
    } catch (e) {
      error('Failed to setup file logging: $e');
    }
  }

  /// Queue a line to be written to the log file.
  void _queueWrite(String line) {
    if (_logFile == null) return;
    _writeQueue.add(line);
    _processWriteQueue();
  }

  /// Process the write queue sequentially to prevent corruption.
  Future<void> _processWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty || _logFile == null) return;

    _isWriting = true;
    try {
      while (_writeQueue.isNotEmpty && _logFile != null) {
        final line = _writeQueue.removeAt(0);
        // Use sync append for atomic writes at OS level
        _logFile!.writeAsStringSync('$line\n', mode: FileMode.append);
      }
    } catch (e) {
      // Silently ignore write errors to avoid disrupting the main app
    } finally {
      _isWriting = false;
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
    if (!_debugEnabled) return;
    _logMessage(
      LogDirection.stdin,
      message,
      sessionId: sessionId,
    );
  }

  /// Log a message received FROM the CLI (stdout).
  void logIncoming(Map<String, dynamic> message, {String? sessionId}) {
    if (!_debugEnabled) return;
    _logMessage(
      LogDirection.stdout,
      message,
      sessionId: sessionId,
    );
  }

  /// Log stderr output from the CLI.
  void logStderr(String line, {String? sessionId}) {
    if (!_debugEnabled) return;
    _logText(
      LogDirection.stderr,
      line,
      sessionId: sessionId,
    );
  }

  /// Log a structured JSON message with direction.
  void _logMessage(
    LogDirection direction,
    Map<String, dynamic> content, {
    String? sessionId,
  }) {
    final entry = LogEntry(
      level: LogLevel.debug,
      message: direction == LogDirection.stdin ? 'SEND' : 'RECV',
      timestamp: DateTime.now(),
      direction: direction,
      sessionId: sessionId,
      data: content,
    );

    // Emit to stream
    if (!_logsController.isClosed) {
      _logsController.add(entry);
    }

    // Queue write to file as JSONL if enabled
    _queueWrite(entry.toJsonLine());
  }

  /// Log a text message (non-JSON) with direction.
  void _logText(
    LogDirection direction,
    String text, {
    String? sessionId,
  }) {
    final entry = LogEntry(
      level: LogLevel.info,
      message: 'stderr',
      timestamp: DateTime.now(),
      direction: direction,
      sessionId: sessionId,
      text: text,
    );

    // Emit to stream
    if (!_logsController.isClosed) {
      _logsController.add(entry);
    }

    // Queue write to file as JSONL if enabled
    _queueWrite(entry.toJsonLine());
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
      direction: LogDirection.internal,
      sessionId: sessionId,
      data: data,
    );

    // Emit to stream
    if (!_logsController.isClosed) {
      _logsController.add(entry);
    }

    // Queue write to file as JSONL if enabled
    _queueWrite(entry.toJsonLine());
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await disableFileLogging();
    await _logsController.close();
  }
}
