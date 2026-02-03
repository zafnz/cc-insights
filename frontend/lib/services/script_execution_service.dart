import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';

/// Represents a script that is currently running or has completed.
class RunningScript {
  /// Unique identifier for this script execution.
  final String id;

  /// Display name (e.g., "Test", "Run").
  final String name;

  /// The shell command being executed.
  final String command;

  /// The working directory for the script.
  final String workingDirectory;

  /// The underlying PTY.
  final Pty pty;

  /// The exit code future from the PTY.
  final Future<int> _exitCodeFuture;

  /// Stream controller for combined terminal output (raw bytes for xterm).
  final StreamController<Uint8List> _outputController =
      StreamController<Uint8List>.broadcast();

  /// Stream of raw bytes for xterm terminal.
  Stream<Uint8List> get outputStream => _outputController.stream;

  /// Buffered stdout output (for legacy text display if needed).
  final StringBuffer _stdout = StringBuffer();

  /// Buffered stderr output (for legacy text display if needed).
  final StringBuffer _stderr = StringBuffer();

  /// Combined output (stdout and stderr interleaved, for legacy text display).
  final StringBuffer _combined = StringBuffer();

  /// Exit code, or null if still running.
  int? exitCode;

  /// When the script was started.
  final DateTime startTime;

  RunningScript({
    required this.id,
    required this.name,
    required this.command,
    required this.workingDirectory,
    required this.pty,
    required Future<int> exitCodeFuture,
  })  : _exitCodeFuture = exitCodeFuture,
        startTime = DateTime.now();

  /// Whether the script is still running.
  bool get isRunning => exitCode == null;

  /// Whether the script completed successfully (exit code 0).
  bool get isSuccess => exitCode == 0;

  /// Whether the script completed with an error (exit code != 0).
  bool get isError => exitCode != null && exitCode != 0;

  /// Get stdout output.
  String get stdout => _stdout.toString();

  /// Get stderr output.
  String get stderr => _stderr.toString();

  /// Get combined output.
  String get output => _combined.toString();

  /// Append raw bytes to the output stream (for xterm).
  void appendBytes(Uint8List data) {
    _outputController.add(data);
  }

  /// Append to stdout.
  void appendStdout(String data) {
    _stdout.write(data);
    _combined.write(data);
    // Also send to xterm as bytes
    _outputController.add(Uint8List.fromList(utf8.encode(data)));
  }

  /// Append to stderr.
  void appendStderr(String data) {
    _stderr.write(data);
    _combined.write(data);
    // Also send to xterm as bytes
    _outputController.add(Uint8List.fromList(utf8.encode(data)));
  }

  /// Close the output stream (call when script completes).
  void closeOutputStream() {
    _outputController.close();
  }

  /// Duration since start.
  Duration get elapsed => DateTime.now().difference(startTime);
}

/// Service for executing scripts and tracking their output.
///
/// This is a ChangeNotifier that notifies listeners when:
/// - A new script starts
/// - Script output is received
/// - A script completes
class ScriptExecutionService extends ChangeNotifier {
  /// All running and recently completed scripts.
  final Map<String, RunningScript> _scripts = {};

  /// Currently focused script (shown in TerminalOutputPanel).
  String? _focusedScriptId;

  /// Stream subscriptions for cleanup.
  final Map<String, List<StreamSubscription<dynamic>>> _subscriptions = {};

  /// Get all scripts (running and completed).
  List<RunningScript> get scripts => _scripts.values.toList();

  /// Get only running scripts.
  List<RunningScript> get runningScripts =>
      _scripts.values.where((s) => s.isRunning).toList();

  /// Get the currently focused script.
  RunningScript? get focusedScript =>
      _focusedScriptId != null ? _scripts[_focusedScriptId] : null;

  /// Whether there are any running scripts.
  bool get hasRunningScripts => _scripts.values.any((s) => s.isRunning);

  /// Whether there is a focused script with output to show.
  bool get hasOutput => _focusedScriptId != null;

  /// Check if a specific action is currently running.
  bool isActionRunning(String actionName) =>
      _scripts.values.any((s) => s.name == actionName && s.isRunning);

  /// Run a script and track its execution.
  ///
  /// Returns the [RunningScript] immediately. Subscribe to this service's
  /// notifications to receive output updates and completion.
  Future<RunningScript> runScript({
    required String name,
    required String command,
    required String workingDirectory,
  }) async {
    final id = '${name}_${DateTime.now().millisecondsSinceEpoch}';

    developer.log(
      'Starting script "$name": $command in $workingDirectory',
      name: 'ScriptExecutionService',
    );

    // Start the process using PTY for proper terminal emulation
    final pty = Pty.start(
      '/bin/sh',
      arguments: ['-c', command],
      workingDirectory: workingDirectory,
      environment: Platform.environment,
    );

    // PTY exitCode is a Future<int>
    final exitCodeFuture = pty.exitCode;

    final script = RunningScript(
      id: id,
      name: name,
      command: command,
      workingDirectory: workingDirectory,
      pty: pty,
      exitCodeFuture: exitCodeFuture,
    );

    _scripts[id] = script;
    _focusedScriptId = id;
    notifyListeners();

    // Track subscriptions for cleanup
    _subscriptions[id] = [];

    // Stream PTY output (combines stdout and stderr)
    // PTY output is already in raw bytes, perfect for xterm
    final outputSub = pty.output.listen((data) {
      // Send raw bytes to xterm
      script.appendBytes(data);
      // Also decode for legacy text buffer
      final text = utf8.decode(data, allowMalformed: true);
      script._stdout.write(text);
      script._combined.write(text);
      notifyListeners();
    });
    _subscriptions[id]!.add(outputSub);

    // Handle completion
    exitCodeFuture.then((code) {
      script.exitCode = code;
      script.closeOutputStream();
      developer.log(
        'Script "$name" completed with exit code $code',
        name: 'ScriptExecutionService',
      );
      notifyListeners();

      // Cleanup subscriptions
      _cleanupSubscriptions(id);
    });

    return script;
  }

  /// Run a script synchronously and wait for completion.
  ///
  /// Useful for lifecycle hooks where we need to wait for the result.
  /// Returns the exit code.
  Future<int> runScriptSync({
    required String name,
    required String command,
    required String workingDirectory,
  }) async {
    final script = await runScript(
      name: name,
      command: command,
      workingDirectory: workingDirectory,
    );

    // Wait for PTY to complete
    return await script._exitCodeFuture;
  }

  /// Focus on a specific script (show it in TerminalOutputPanel).
  void focusScript(String id) {
    if (_scripts.containsKey(id)) {
      _focusedScriptId = id;
      notifyListeners();
    }
  }

  /// Clear a script from the list.
  ///
  /// If the script is still running, it will be killed first.
  void clearScript(String id) {
    final script = _scripts[id];
    // Kill the PTY if still running
    if (script != null && script.isRunning) {
      script.pty.kill();
    }
    _cleanupSubscriptions(id);
    _scripts.remove(id);
    if (_focusedScriptId == id) {
      // Focus the most recent remaining script, or null
      _focusedScriptId = _scripts.keys.lastOrNull;
    }
    notifyListeners();
  }

  /// Clear all completed scripts.
  void clearCompletedScripts() {
    final completedIds =
        _scripts.entries.where((e) => !e.value.isRunning).map((e) => e.key);

    for (final id in completedIds.toList()) {
      _cleanupSubscriptions(id);
      _scripts.remove(id);
    }

    if (_focusedScriptId != null && !_scripts.containsKey(_focusedScriptId)) {
      _focusedScriptId = _scripts.keys.lastOrNull;
    }
    notifyListeners();
  }

  /// Clear the focused script output (hides the terminal panel).
  void clearOutput() {
    if (_focusedScriptId != null) {
      final script = _scripts[_focusedScriptId];
      if (script != null && !script.isRunning) {
        clearScript(_focusedScriptId!);
      } else {
        // Just unfocus, don't remove running scripts
        _focusedScriptId = null;
        notifyListeners();
      }
    }
  }

  /// Kill a running script.
  Future<void> killScript(String id) async {
    final script = _scripts[id];
    if (script != null && script.isRunning) {
      developer.log(
        'Killing script "${script.name}"',
        name: 'ScriptExecutionService',
      );
      script.pty.kill();
    }
  }

  /// Kill the currently focused script.
  Future<void> killFocusedScript() async {
    if (_focusedScriptId != null) {
      await killScript(_focusedScriptId!);
    }
  }

  void _cleanupSubscriptions(String id) {
    final subs = _subscriptions.remove(id);
    if (subs != null) {
      for (final sub in subs) {
        sub.cancel();
      }
    }
  }

  @override
  void dispose() {
    // Kill all running PTYs
    for (final script in _scripts.values) {
      if (script.isRunning) {
        script.pty.kill();
      }
    }
    // Cancel all subscriptions
    for (final id in _subscriptions.keys.toList()) {
      _cleanupSubscriptions(id);
    }
    super.dispose();
  }
}
