import 'dart:async';
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

/// A structured log entry.
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

  /// Creates a log entry from JSON (for loading from file).
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      service: json['service'] as String,
      level: LogLevel.values.firstWhere(
        (l) => l.name == json['level'],
        orElse: () => LogLevel.info,
      ),
      type: json['type'] as String,
      worktree: json['worktree'] as String?,
      message: Map<String, dynamic>.from(json['message'] as Map),
    );
  }

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

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${timestamp.toIso8601String()}]');
    buffer.write('[$service]');
    buffer.write('[${level.name.toUpperCase()}]');
    buffer.write('[$type]');
    if (worktree != null) {
      buffer.write('[$worktree]');
    }
    if (message.containsKey('text')) {
      buffer.write(' ${message['text']}');
    } else {
      buffer.write(' ${jsonEncode(message)}');
    }
    return buffer.toString();
  }
}

/// Central logging service for the application.
///
/// All application components should log through this service to enable
/// unified log viewing, filtering, and persistence.
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

  final List<LogEntry> _entries = [];
  final _controller = StreamController<LogEntry>.broadcast();

  // File logging state
  File? _logFile;
  String? _logFilePath;
  final _writeQueue = <String>[];
  bool _isWriting = false;

  // Filtering
  LogLevel _minimumLevel = LogLevel.debug;

  /// Stream of all log entries.
  Stream<LogEntry> get logs => _controller.stream;

  /// All stored log entries.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// The current minimum log level for file output.
  LogLevel get minimumLevel => _minimumLevel;

  /// Sets the minimum log level for file output.
  set minimumLevel(LogLevel level) => _minimumLevel = level;

  /// The current log file path, or null if file logging is disabled.
  String? get logFilePath => _logFilePath;

  /// Maximum entries to keep in memory.
  static const maxEntries = 10000;

  // ---------------------------------------------------------------------------
  // File logging
  // ---------------------------------------------------------------------------

  /// Enables file logging to the specified path.
  void enableFileLogging(String path) {
    if (_logFilePath == path) return;
    try {
      final file = File(path);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      _logFile = file;
      _logFilePath = path;
      info('LogService', 'config', 'File logging enabled: $path');
    } catch (e) {
      error('LogService', 'config', 'Failed to enable file logging: $e');
    }
  }

  /// Disables file logging.
  Future<void> disableFileLogging() async {
    // Wait for pending writes to complete
    while (_isWriting || _writeQueue.isNotEmpty) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _logFile = null;
    _logFilePath = null;
  }

  void _queueWrite(String line) {
    if (_logFile == null) return;
    _writeQueue.add(line);
    _processWriteQueue();
  }

  Future<void> _processWriteQueue() async {
    if (_isWriting || _writeQueue.isEmpty || _logFile == null) return;

    _isWriting = true;
    try {
      while (_writeQueue.isNotEmpty && _logFile != null) {
        final line = _writeQueue.removeAt(0);
        _logFile!.writeAsStringSync('$line\n', mode: FileMode.append);
      }
    } catch (_) {
      // Silently ignore write errors to avoid disrupting the main app
    } finally {
      _isWriting = false;
    }
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
    final entry = LogEntry(
      timestamp: DateTime.now(),
      service: service,
      level: level,
      type: type,
      worktree: worktree,
      message: message,
    );

    // Add to in-memory list
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }

    // Emit to stream
    if (!_controller.isClosed) {
      _controller.add(entry);
    }

    // Write to file if enabled and meets threshold
    if (level.meetsThreshold(_minimumLevel)) {
      _queueWrite(entry.toJsonLine());
    }
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

  /// Clears all in-memory log entries.
  void clear() {
    _entries.clear();
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await disableFileLogging();
    await _controller.close();
  }
}
