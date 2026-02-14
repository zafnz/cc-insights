import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Log level for application messages.
enum LogLevel {
  trace,
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
    required this.level,
    required this.source,
    required this.message,
    this.meta,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;
  final Map<String, dynamic>? meta;

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      if (meta != null && meta!.isNotEmpty) 'meta': meta,
    };
  }

  /// Converts to a single-line JSON string for JSONL format.
  String toJsonLine() => jsonEncode(toJson());
}

/// Central logging service for the application.
///
/// Writes logs to disk (if configured) and maintains an in-memory ring buffer
/// for the log viewer UI. Extends [ChangeNotifier] with rate-limited
/// notifications (max 10/sec) to keep the UI performant.
///
/// Usage:
/// ```dart
/// LogService.instance.info('MyService', 'Service started');
/// LogService.instance.debug('Git', 'Fetching status', meta: {'worktree': 'main'});
/// ```
class LogService extends ChangeNotifier {
  LogService._();

  static final LogService instance = LogService._();

  // ---------------------------------------------------------------------------
  // In-memory buffer
  // ---------------------------------------------------------------------------

  /// Maximum number of entries kept in memory.
  static const int maxBufferSize = 10000;

  final List<LogEntry> _entries = [];

  /// All buffered log entries (unmodifiable view).
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Number of entries in the buffer.
  int get entryCount => _entries.length;

  /// Unique source names seen so far.
  final Set<String> _sources = {};

  /// Set of all unique source names for filter dropdowns.
  Set<String> get sources => Set.unmodifiable(_sources);

  // ---------------------------------------------------------------------------
  // Unhandled error stream
  // ---------------------------------------------------------------------------

  final StreamController<LogEntry> _unhandledErrorController =
      StreamController<LogEntry>.broadcast();

  /// Stream of log entries from unhandled async exceptions.
  ///
  /// UI widgets can listen to this to show transient error notifications
  /// (e.g. snackbars) without polling.
  Stream<LogEntry> get unhandledErrors => _unhandledErrorController.stream;

  /// Logs an unhandled async exception. Writes to the normal log and also
  /// pushes to [unhandledErrors] so the UI can show a notification.
  void logUnhandledException(Object error, StackTrace? stack) {
    final message = error.toString();
    final meta = stack != null ? {'stack': stack.toString()} : null;
    log(source: 'Unhandled', level: LogLevel.error, message: message, meta: meta);
    // Push the most recent entry to the stream
    _unhandledErrorController.add(_entries.last);
  }

  // ---------------------------------------------------------------------------
  // Rate-limited notifications
  // ---------------------------------------------------------------------------

  Timer? _notifyTimer;
  bool _dirty = false;

  void _markDirty() {
    _dirty = true;
    _notifyTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_dirty) {
          _dirty = false;
          notifyListeners();
        } else {
          _notifyTimer?.cancel();
          _notifyTimer = null;
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // File logging state
  // ---------------------------------------------------------------------------

  IOSink? _sink;
  String? _logFilePath;

  /// The current minimum log level for file output.
  /// Public field for direct access.
  LogLevel minimumLevel = LogLevel.debug;

  /// Minimum log level for stdout output, or null if stdout logging is disabled.
  ///
  /// When non-null, log entries at this level or above are also written to
  /// stdout. Set via `--stdout-log-level <level>` CLI flag.
  LogLevel? stdoutMinimumLevel;

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
    required String source,
    required LogLevel level,
    required String message,
    Map<String, dynamic>? meta,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      source: source,
      message: message,
      meta: meta,
    );

    // Add to in-memory buffer (always, regardless of level)
    _entries.add(entry);
    if (_entries.length > maxBufferSize) {
      _entries.removeAt(0);
    }
    _sources.add(source);

    // Write to disk if file logging is enabled and level meets threshold
    if (level.meetsThreshold(minimumLevel) && _sink != null) {
      _sink!.writeln(entry.toJsonLine());
    }

    // Write to stdout if stdout logging is enabled and level meets threshold
    if (stdoutMinimumLevel != null && level.meetsThreshold(stdoutMinimumLevel!)) {
      stdout.writeln(
        '${entry.timestamp.toIso8601String()} '
        '[${level.name.toUpperCase()}] '
        '${entry.source}: ${entry.message}',
      );
    }

    // Rate-limited UI notification
    _markDirty();
  }

  /// Logs a trace message.
  void trace(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.trace, message: message, meta: meta);
  }

  /// Logs a debug message.
  void debug(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.debug, message: message, meta: meta);
  }

  /// Logs an info message.
  void info(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.info, message: message, meta: meta);
  }

  /// Logs a notice message.
  void notice(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.notice, message: message, meta: meta);
  }

  /// Logs a warning message.
  void warn(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.warn, message: message, meta: meta);
  }

  /// Logs an error message.
  void error(String source, String message, {Map<String, dynamic>? meta}) {
    log(source: source, level: LogLevel.error, message: message, meta: meta);
  }

  // ---------------------------------------------------------------------------
  // Testing
  // ---------------------------------------------------------------------------

  /// Clears the in-memory buffer and cancels pending timers. For use in tests only.
  @visibleForTesting
  void clearBuffer() {
    _entries.clear();
    _sources.clear();
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _dirty = false;
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  /// Disposes resources.
  @override
  void dispose() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _unhandledErrorController.close();
    disableFileLogging();
    super.dispose();
  }
}
