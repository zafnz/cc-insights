import 'dart:convert';
import 'dart:io';

/// Log level for application messages.
enum LogLevel {
  debug,
  info,
  notice,
  warn,
  error;

  /// Returns true if this level is >= the given threshold.
  bool meetsThreshold(LogLevel threshold) => index >= threshold.index;
}

/// A structured log entry (used only for file output).
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.service,
    required this.level,
    required this.type,
    required this.message,
    this.worktree,
  });

  final DateTime timestamp;
  final String service;
  final LogLevel level;
  final String type;
  final String? worktree;
  final Map<String, dynamic> message;

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'service': service,
      'level': level.name,
      'type': type,
      if (worktree != null) 'worktree': worktree,
      'message': message,
    };
  }

  /// Converts to a single-line JSON string for JSONL format.
  String toJsonLine() => jsonEncode(toJson());

  /// Convenience getter for text messages.
  String? get text => message['text'] as String?;
}

/// Central logging service for the application.
///
/// Writes logs directly to disk if a file path is configured.
/// No in-memory storage - this is a write-only service.
///
/// Usage:
/// ```dart
/// // Simple text logging
/// LogService.instance.info('MyService', 'startup', 'Service started');
///
/// // Structured logging
/// LogService.instance.log(
///   service: 'ClaudeSDK',
///   level: LogLevel.debug,
///   type: 'message',
///   worktree: 'feat-new-feature',
///   message: {'direction': 'recv', 'content': {...}},
/// );
/// ```
class LogService {
  LogService._();

  static final LogService instance = LogService._();

  // File logging state
  IOSink? _sink;
  String? _logFilePath;

  // Filtering
  LogLevel _minimumLevel = LogLevel.debug;

  /// The current minimum log level for file output.
  LogLevel get minimumLevel => _minimumLevel;

  /// Sets the minimum log level for file output.
  set minimumLevel(LogLevel level) => _minimumLevel = level;

  /// The current log file path, or null if file logging is disabled.
  String? get logFilePath => _logFilePath;

  // ---------------------------------------------------------------------------
  // File logging
  // ---------------------------------------------------------------------------

  /// Enables file logging to the specified path.
  void enableFileLogging(String path) {
    if (_logFilePath == path && _sink != null) return;

    // Close existing sink if any
    _sink?.close();
    _sink = null;

    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _sink = file.openWrite(mode: FileMode.append);
      _logFilePath = path;
    } catch (e) {
      // Silently fail - logging should not crash the app
      _sink = null;
      _logFilePath = null;
    }
  }

  /// Disables file logging.
  Future<void> disableFileLogging() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _logFilePath = null;
  }

  // ---------------------------------------------------------------------------
  // Logging methods
  // ---------------------------------------------------------------------------

  /// Logs a structured message.
  void log({
    required String service,
    required LogLevel level,
    required String type,
    required Map<String, dynamic> message,
    String? worktree,
  }) {
    // Skip if below threshold or no file configured
    if (!level.meetsThreshold(_minimumLevel) || _sink == null) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      service: service,
      level: level,
      type: type,
      worktree: worktree,
      message: message,
    );

    _sink!.writeln(entry.toJsonLine());
  }

  /// Convenience method for logging a simple text message.
  void logText({
    required String service,
    required LogLevel level,
    required String type,
    required String text,
    String? worktree,
  }) {
    log(
      service: service,
      level: level,
      type: type,
      worktree: worktree,
      message: {'text': text},
    );
  }

  /// Logs a debug message.
  void debug(String service, String type, String text, {String? worktree}) {
    logText(
      service: service,
      level: LogLevel.debug,
      type: type,
      text: text,
      worktree: worktree,
    );
  }

  /// Logs an info message.
  void info(String service, String type, String text, {String? worktree}) {
    logText(
      service: service,
      level: LogLevel.info,
      type: type,
      text: text,
      worktree: worktree,
    );
  }

  /// Logs a notice message.
  void notice(String service, String type, String text, {String? worktree}) {
    logText(
      service: service,
      level: LogLevel.notice,
      type: type,
      text: text,
      worktree: worktree,
    );
  }

  /// Logs a warning message.
  void warn(String service, String type, String text, {String? worktree}) {
    logText(
      service: service,
      level: LogLevel.warn,
      type: type,
      text: text,
      worktree: worktree,
    );
  }

  /// Logs an error message.
  void error(String service, String type, String text, {String? worktree}) {
    logText(
      service: service,
      level: LogLevel.error,
      type: type,
      text: text,
      worktree: worktree,
    );
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await disableFileLogging();
  }
}
