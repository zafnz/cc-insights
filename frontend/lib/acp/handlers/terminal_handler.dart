import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';

/// Handles terminal/* requests from the ACP agent.
///
/// This handler manages terminal sessions for command execution,
/// tracking running processes with unique IDs and providing methods
/// to create, monitor, and control terminal sessions.
class TerminalHandler {
  final _terminals = <String, TerminalSession>{};

  /// Creates a new terminal session and executes the given command.
  ///
  /// The command is executed using `/bin/sh -c <command>` to support
  /// shell features like pipes, redirects, and environment variable expansion.
  /// Returns a [CreateTerminalResponse] with a unique terminal ID.
  Future<CreateTerminalResponse> create(CreateTerminalRequest params) async {
    final id = 'term_${DateTime.now().microsecondsSinceEpoch}';

    // Build command with arguments
    final command = _buildCommand(params.command, params.args);

    // Build environment from EnvVariable list
    final environment = <String, String>{};
    if (params.env != null) {
      for (final envVar in params.env!) {
        environment[envVar.name] = envVar.value;
      }
    }

    final process = await Process.start(
      '/bin/sh',
      ['-c', command],
      workingDirectory: params.cwd,
      environment: environment.isNotEmpty ? {...Platform.environment, ...environment} : null,
    );

    final session = TerminalSession(
      id: id,
      process: process,
      outputByteLimit: params.outputByteLimit,
    );

    _terminals[id] = session;

    // Start collecting output
    session.startCollecting();

    return CreateTerminalResponse(terminalId: id);
  }

  /// Gets the output from a terminal session.
  ///
  /// Returns the buffered stdout and stderr output since the terminal was created.
  /// If the process has exited, includes the exit status.
  Future<TerminalOutputResponse> output(TerminalOutputRequest params) async {
    final session = _terminals[params.terminalId];
    if (session == null) {
      throw TerminalNotFoundError(params.terminalId);
    }

    final output = session.getOutput();
    final truncated = session.isTruncated;

    return TerminalOutputResponse(
      output: output,
      exitStatus: session.exitStatus,
      truncated: truncated,
    );
  }

  /// Waits for a terminal to exit and returns the exit status.
  ///
  /// This method blocks until the process completes. Returns the exit code
  /// and any signal that caused termination.
  Future<WaitForTerminalExitResponse> waitForExit(WaitForTerminalExitRequest params) async {
    final session = _terminals[params.terminalId];
    if (session == null) {
      throw TerminalNotFoundError(params.terminalId);
    }

    final exitCode = await session.waitForExit();

    return WaitForTerminalExitResponse(exitCode: exitCode, signal: session.signal);
  }

  /// Kills a terminal process.
  ///
  /// Sends SIGTERM to the process. If the process doesn't exit within
  /// a reasonable time, SIGKILL is sent.
  Future<KillTerminalCommandResponse> kill(KillTerminalCommandRequest params) async {
    final session = _terminals[params.terminalId];
    if (session == null) {
      throw TerminalNotFoundError(params.terminalId);
    }

    await session.kill();

    return KillTerminalCommandResponse();
  }

  /// Releases a terminal session and cleans up resources.
  ///
  /// This removes the terminal from tracking. If the process is still
  /// running, it will be killed first.
  Future<ReleaseTerminalResponse> release(ReleaseTerminalRequest params) async {
    final session = _terminals.remove(params.terminalId);
    if (session == null) {
      throw TerminalNotFoundError(params.terminalId);
    }

    await session.dispose();

    return ReleaseTerminalResponse();
  }

  /// Disposes all terminal sessions.
  ///
  /// Kills all running processes and cleans up resources.
  /// Should be called when the handler is no longer needed.
  Future<void> disposeAll() async {
    final futures = <Future<void>>[];
    for (final session in _terminals.values) {
      futures.add(session.dispose());
    }
    await Future.wait(futures);
    _terminals.clear();
  }

  /// Builds the command string with optional arguments.
  String _buildCommand(String command, List<String>? args) {
    if (args == null || args.isEmpty) {
      return command;
    }
    // Escape and join arguments
    final escapedArgs = args.map(_shellEscape).join(' ');
    return '$command $escapedArgs';
  }

  /// Escapes a string for safe use in shell commands.
  String _shellEscape(String arg) {
    // If the argument contains special characters, wrap in single quotes
    // and escape any existing single quotes
    if (arg.contains(RegExp(r'[\s\$`"\\!]')) || arg.contains("'")) {
      return "'${arg.replaceAll("'", r"'\''")}'";
    }
    return arg;
  }
}

/// Error thrown when a terminal is not found.
class TerminalNotFoundError extends Error {
  /// The ID of the terminal that was not found.
  final String terminalId;

  /// Creates a new [TerminalNotFoundError] with the given [terminalId].
  TerminalNotFoundError(this.terminalId);

  @override
  String toString() => 'TerminalNotFoundError: Terminal not found: $terminalId';
}

/// Internal class to track a terminal session.
///
/// Manages a running process, buffering its output and tracking
/// its lifecycle state.
class TerminalSession {
  /// Creates a new terminal session.
  TerminalSession({
    required this.id,
    required this.process,
    this.outputByteLimit,
  });

  /// The unique identifier for this terminal session.
  final String id;

  /// The underlying process.
  final Process process;

  /// Optional limit for output bytes.
  final int? outputByteLimit;

  final _outputBuffer = StringBuffer();
  int _outputByteCount = 0;
  bool _isTruncated = false;
  int? _exitCode;
  String? _signal;
  bool _isCollecting = false;
  final _exitCompleter = Completer<int>();
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  /// Whether the output was truncated due to byte limit.
  bool get isTruncated => _isTruncated;

  /// The exit status if the process has exited, null otherwise.
  TerminalExitStatus? get exitStatus {
    if (_exitCode == null && _signal == null) {
      return null;
    }
    return TerminalExitStatus(exitCode: _exitCode, signal: _signal);
  }

  /// The signal that caused termination, if any.
  String? get signal => _signal;

  /// Starts collecting output from stdout and stderr.
  void startCollecting() {
    if (_isCollecting) return;
    _isCollecting = true;

    _stdoutSubscription = process.stdout.transform(utf8.decoder).listen(_appendOutput);
    _stderrSubscription = process.stderr.transform(utf8.decoder).listen(_appendOutput);

    // Track process exit
    process.exitCode.then((code) {
      _exitCode = code;
      if (!_exitCompleter.isCompleted) {
        _exitCompleter.complete(code);
      }
    });
  }

  void _appendOutput(String data) {
    if (_isTruncated) return;

    final dataBytes = utf8.encode(data).length;

    if (outputByteLimit != null && _outputByteCount + dataBytes > outputByteLimit!) {
      // Truncate: add only what fits
      final remainingBytes = outputByteLimit! - _outputByteCount;
      if (remainingBytes > 0) {
        // Find how many characters fit within the remaining bytes
        final chars = data.codeUnits;
        var byteCount = 0;
        var charIndex = 0;
        for (; charIndex < chars.length && byteCount < remainingBytes; charIndex++) {
          byteCount += utf8.encode(String.fromCharCode(chars[charIndex])).length;
        }
        _outputBuffer.write(data.substring(0, charIndex));
        _outputByteCount += byteCount;
      }
      _isTruncated = true;
    } else {
      _outputBuffer.write(data);
      _outputByteCount += dataBytes;
    }
  }

  /// Gets the current output buffer contents.
  String getOutput() => _outputBuffer.toString();

  /// Waits for the process to exit and returns the exit code.
  Future<int> waitForExit() => _exitCompleter.future;

  /// Kills the process.
  Future<void> kill() async {
    // Try SIGTERM first
    process.kill(ProcessSignal.sigterm);

    // Wait briefly for graceful shutdown
    final exited = await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        // Force kill if still running
        process.kill(ProcessSignal.sigkill);
        _signal = 'SIGKILL';
        return -1;
      },
    );

    if (_signal == null && exited == -1) {
      _signal = 'SIGTERM';
    }
  }

  /// Disposes of this session, cleaning up resources.
  Future<void> dispose() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();

    // Kill if still running
    try {
      if (!_exitCompleter.isCompleted) {
        process.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      // Process may have already exited
    }
  }
}
