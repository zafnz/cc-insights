import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../services/script_execution_service.dart';
import 'panel_wrapper.dart';

/// Keys for testing TerminalOutputPanel widgets.
class TerminalOutputPanelKeys {
  TerminalOutputPanelKeys._();

  /// The panel wrapper.
  static const panel = Key('terminal_output_panel');

  /// The output text area.
  static const outputArea = Key('terminal_output_area');

  /// The kill button.
  static const killButton = Key('terminal_kill_button');

  /// The close button.
  static const closeButton = Key('terminal_close_button');

  /// The keep open button.
  static const keepOpenButton = Key('terminal_keep_open_button');
}

/// Panel that displays script execution output.
///
/// Shows:
/// - Real-time stdout/stderr output from running scripts
/// - Exit code and status when complete
/// - Auto-closes after 2 seconds on success (exit code 0)
/// - Stays open on error
class TerminalOutputPanel extends StatelessWidget {
  const TerminalOutputPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scriptService = context.watch<ScriptExecutionService>();
    final script = scriptService.focusedScript;

    final title = script != null
        ? 'Terminal - ${script.name}'
        : 'Terminal Output';

    return PanelWrapper(
      key: TerminalOutputPanelKeys.panel,
      title: title,
      icon: Icons.terminal,
      trailing: script != null ? _buildTrailingActions(context, script) : null,
      child: const _TerminalContent(),
    );
  }

  Widget _buildTrailingActions(BuildContext context, RunningScript script) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (script.isRunning)
          IconButton(
            key: TerminalOutputPanelKeys.killButton,
            icon: Icon(
              Icons.stop,
              size: 14,
              color: colorScheme.error,
            ),
            onPressed: () {
              context.read<ScriptExecutionService>().killFocusedScript();
            },
            tooltip: 'Stop script',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          )
        else
          IconButton(
            key: TerminalOutputPanelKeys.closeButton,
            icon: Icon(
              Icons.close,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              context.read<ScriptExecutionService>().clearOutput();
            },
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
      ],
    );
  }
}

class _TerminalContent extends StatefulWidget {
  const _TerminalContent();

  @override
  State<_TerminalContent> createState() => _TerminalContentState();
}

class _TerminalContentState extends State<_TerminalContent> {
  static const _autoCloseDelay = Duration(seconds: 2);

  Timer? _autoCloseTimer;
  bool _userRequestedKeepOpen = false;
  String? _lastScriptId;
  Terminal? _terminal;
  StreamSubscription<List<int>>? _outputSubscription;

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _outputSubscription?.cancel();
    // Note: Terminal doesn't have a dispose method
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scriptService = context.watch<ScriptExecutionService>();
    final script = scriptService.focusedScript;

    if (script == null) {
      return const _NoOutputPlaceholder();
    }

    // Reset state when script changes
    if (script.id != _lastScriptId) {
      _lastScriptId = script.id;
      _autoCloseTimer?.cancel();
      _autoCloseTimer = null;
      _userRequestedKeepOpen = false;

      // Create new terminal and subscribe to output stream
      _outputSubscription?.cancel();
      _terminal = Terminal();
      _outputSubscription = script.outputStream.listen(
        (data) {
          // PTY output is raw bytes, decode to string for xterm
          // PTY already handles proper line endings (\r\n) for terminal emulation
          final text = String.fromCharCodes(data);
          _terminal?.write(text);
        },
        onDone: () {
          // Stream closed, script finished
        },
      );
    }

    // Start auto-close timer when script completes successfully
    if (!script.isRunning && script.isSuccess && !_userRequestedKeepOpen) {
      _autoCloseTimer ??= Timer(_autoCloseDelay, () {
        if (mounted) {
          context.read<ScriptExecutionService>().clearOutput();
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Output area
        Expanded(
          child: _OutputArea(
            key: TerminalOutputPanelKeys.outputArea,
            terminal: _terminal!,
          ),
        ),

        // Status bar
        _StatusBar(
          script: script,
          isAutoClosing: _autoCloseTimer != null && !_userRequestedKeepOpen,
          onKeepOpen: () {
            _autoCloseTimer?.cancel();
            _autoCloseTimer = null;
            setState(() => _userRequestedKeepOpen = true);
          },
          onClose: () {
            _autoCloseTimer?.cancel();
            context.read<ScriptExecutionService>().clearOutput();
          },
        ),
      ],
    );
  }
}

class _OutputArea extends StatelessWidget {
  const _OutputArea({
    super.key,
    required this.terminal,
  });

  final Terminal terminal;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: colorScheme.surfaceContainerLowest,
      child: TerminalView(
        terminal,
        theme: TerminalTheme(
          cursor: colorScheme.primary,
          selection: colorScheme.primaryContainer,
          foreground: colorScheme.onSurface,
          background: colorScheme.surfaceContainerLowest,
          black: isDark ? const Color(0xFF2E3436) : const Color(0xFF000000),
          red: isDark ? const Color(0xFFCC0000) : const Color(0xFFCC0000),
          green: isDark ? const Color(0xFF4E9A06) : const Color(0xFF4E9A06),
          yellow: isDark ? const Color(0xFFC4A000) : const Color(0xFFC4A000),
          blue: isDark ? const Color(0xFF3465A4) : const Color(0xFF3465A4),
          magenta: isDark ? const Color(0xFF75507B) : const Color(0xFF75507B),
          cyan: isDark ? const Color(0xFF06989A) : const Color(0xFF06989A),
          white: isDark ? const Color(0xFFD3D7CF) : const Color(0xFFFFFFFF),
          brightBlack: isDark ? const Color(0xFF555753) : const Color(0xFF555753),
          brightRed: isDark ? const Color(0xFFEF2929) : const Color(0xFFEF2929),
          brightGreen: isDark ? const Color(0xFF8AE234) : const Color(0xFF8AE234),
          brightYellow: isDark ? const Color(0xFFFCE94F) : const Color(0xFFFCE94F),
          brightBlue: isDark ? const Color(0xFF729FCF) : const Color(0xFF729FCF),
          brightMagenta: isDark ? const Color(0xFFAD7FA8) : const Color(0xFFAD7FA8),
          brightCyan: isDark ? const Color(0xFF34E2E2) : const Color(0xFF34E2E2),
          brightWhite: isDark ? const Color(0xFFEEEEEC) : const Color(0xFFFFFFFF),
          searchHitBackground: colorScheme.secondaryContainer,
          searchHitBackgroundCurrent: colorScheme.tertiaryContainer,
          searchHitForeground: colorScheme.onSecondaryContainer,
        ),
        textStyle: const TerminalStyle(
          fontSize: 11,
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: ['Courier New', 'monospace'],
        ),
        padding: const EdgeInsets.all(8),
        autofocus: false,
        readOnly: true,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.script,
    required this.isAutoClosing,
    required this.onKeepOpen,
    required this.onClose,
  });

  final RunningScript script;
  final bool isAutoClosing;
  final VoidCallback onKeepOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (script.isRunning) {
      statusColor = colorScheme.primary;
      statusText = 'Running...';
      statusIcon = Icons.sync;
    } else if (script.isSuccess) {
      statusColor = Colors.green;
      statusText = 'Exit code: 0';
      statusIcon = Icons.check_circle;
    } else {
      statusColor = colorScheme.error;
      statusText = 'Exit code: ${script.exitCode}';
      statusIcon = Icons.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: textTheme.labelSmall?.copyWith(color: statusColor),
          ),
          const Spacer(),
          if (isAutoClosing) ...[
            Text(
              'Closing...',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: TerminalOutputPanelKeys.keepOpenButton,
              onPressed: onKeepOpen,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Keep Open'),
            ),
          ],
          if (!script.isRunning && !isAutoClosing)
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}

class _NoOutputPlaceholder extends StatelessWidget {
  const _NoOutputPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.terminal,
              size: 32,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'No script output',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Run an action to see output here',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
