import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Represents an individual terminal tab.
class TerminalTab {
  /// Unique identifier for this tab.
  final String id;

  /// Display name for the tab.
  String name;

  /// The xterm terminal instance.
  final Terminal terminal;

  /// The PTY (pseudo-terminal) for this tab.
  final Pty pty;

  /// The working directory for this terminal.
  final String workingDirectory;

  /// Whether this terminal is still running (tracked separately).
  bool _isAlive = true;

  TerminalTab({
    String? id,
    required this.name,
    required this.terminal,
    required this.pty,
    required this.workingDirectory,
  }) : id = id ?? _uuid.v4() {
    // Track when PTY exits
    pty.exitCode.then((_) => _isAlive = false);
  }

  /// Whether this terminal is still running (PTY hasn't exited).
  bool get isAlive => _isAlive;
}
