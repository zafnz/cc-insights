import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_tab.dart';
import '../services/script_execution_service.dart';
import '../widgets/keyboard_focus_manager.dart';
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

  /// The new terminal button.
  static const newTerminalButton = Key('terminal_new_button');
}

/// Panel that displays script execution output with tabbed terminals.
///
/// Shows:
/// - Tabbed interface for multiple terminals
/// - Script execution output in read-only terminals
/// - Interactive shell terminals
/// - Auto-closes after 2 seconds on success (exit code 0) for script tabs
class TerminalOutputPanel extends StatefulWidget {
  const TerminalOutputPanel({super.key});

  @override
  State<TerminalOutputPanel> createState() => _TerminalOutputPanelState();
}

class _TerminalOutputPanelState extends State<TerminalOutputPanel> {
  /// List of all terminal tabs (both script output and interactive shells).
  final List<TerminalTab> _tabs = [];

  /// Currently active tab index.
  int _activeTabIndex = 0;

  /// Map of script IDs to terminal tab IDs (for script execution output).
  final Map<String, String> _scriptToTabId = {};

  /// Stream subscriptions for terminal output.
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};

  /// Keyboard focus manager resume callback.
  VoidCallback? _keyboardResume;

  /// Whether a terminal currently has focus.
  bool _terminalHasFocus = false;

  @override
  void dispose() {
    // Clean up all subscriptions
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Kill all PTYs
    for (final tab in _tabs) {
      if (tab.isAlive) {
        tab.pty.kill();
      }
    }

    // Resume keyboard interception if we suspended it
    _keyboardResume?.call();

    super.dispose();
  }

  void _createNewTerminal() {
    final workingDir = Directory.current.path;

    // Start a new shell in PTY
    final pty = Pty.start(
      Platform.environment['SHELL'] ?? '/bin/sh',
      workingDirectory: workingDir,
      environment: Platform.environment,
    );

    final terminal = Terminal();

    // Wire up terminal input to PTY
    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    // Wire up terminal resize to PTY
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      pty.resize(height, width);
    };

    final tab = TerminalTab(
      name: 'Terminal ${_tabs.length + 1}',
      terminal: terminal,
      pty: pty,
      workingDirectory: workingDir,
    );

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });

    // Subscribe to PTY output
    final sub = pty.output.listen((data) {
      final text = String.fromCharCodes(data);
      terminal.write(text);
    });
    _subscriptions[tab.id] = sub;

    // Handle PTY exit
    pty.exitCode.then((code) {
      if (mounted) {
        // Terminal died, could show a message or auto-close
      }
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    final tab = _tabs[index];

    // Cancel subscription
    _subscriptions[tab.id]?.cancel();
    _subscriptions.remove(tab.id);

    // Remove from script mapping if it's a script tab
    _scriptToTabId.removeWhere((key, value) => value == tab.id);

    // Kill PTY if still alive
    if (tab.isAlive) {
      tab.pty.kill();
    }

    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
      } else if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      }
    });
  }

  void _onTerminalFocusChanged(bool hasFocus) {
    if (hasFocus == _terminalHasFocus) return;

    setState(() {
      _terminalHasFocus = hasFocus;
    });

    if (hasFocus) {
      // Terminal got focus - suspend keyboard interception
      final manager = KeyboardFocusManager.maybeOf(context);
      _keyboardResume = manager?.suspend();
    } else {
      // Terminal lost focus - resume keyboard interception
      _keyboardResume?.call();
      _keyboardResume = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scriptService = context.watch<ScriptExecutionService>();
    final script = scriptService.focusedScript;

    // If there's a focused script and we don't have a tab for it, create one
    if (script != null && !_scriptToTabId.containsKey(script.id)) {
      _createScriptTab(script);
    }

    // If there's a focused script, switch to its tab
    if (script != null && _scriptToTabId.containsKey(script.id)) {
      final tabId = _scriptToTabId[script.id]!;
      final tabIndex = _tabs.indexWhere((t) => t.id == tabId);
      if (tabIndex != -1 && tabIndex != _activeTabIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _activeTabIndex = tabIndex;
            });
          }
        });
      }
    }

    return PanelWrapper(
      key: TerminalOutputPanelKeys.panel,
      title: 'Terminal',
      icon: Icons.terminal,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: TerminalOutputPanelKeys.newTerminalButton,
            icon: const Icon(Icons.add, size: 16),
            onPressed: _createNewTerminal,
            tooltip: 'New Terminal',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          if (script != null && _tabs.isNotEmpty)
            _buildScriptActions(context, script),
        ],
      ),
      child: _tabs.isEmpty
          ? const _NoTerminalsPlaceholder()
          : Column(
              children: [
                // Tab bar
                if (_tabs.length > 1) _buildTabBar(),
                // Terminal view
                Expanded(
                  child: _buildTerminalView(_tabs[_activeTabIndex]),
                ),
                // Status bar for script tabs
                if (_isScriptTab(_tabs[_activeTabIndex]))
                  _buildScriptStatusBar(context, script),
              ],
            ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isActive = index == _activeTabIndex;

          return GestureDetector(
            onTap: () {
              setState(() {
                _activeTabIndex = index;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.surface
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tab.name,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isActive
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _closeTab(index),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTerminalView(TerminalTab tab) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isScriptTab = _isScriptTab(tab);

    return Focus(
      onFocusChange: _onTerminalFocusChanged,
      child: GestureDetector(
        onTap: !isScriptTab
            ? () {
                // Ensure focus when terminal is tapped
                _onTerminalFocusChanged(true);
              }
            : null,
        child: Container(
          color: colorScheme.surfaceContainerLowest,
          child: TerminalView(
            tab.terminal,
            theme: TerminalTheme(
              cursor: colorScheme.primary,
              selection: colorScheme.primaryContainer,
              foreground: colorScheme.onSurface,
              background: colorScheme.surfaceContainerLowest,
              black:
                  isDark ? const Color(0xFF2E3436) : const Color(0xFF000000),
              red: isDark ? const Color(0xFFCC0000) : const Color(0xFFCC0000),
              green:
                  isDark ? const Color(0xFF4E9A06) : const Color(0xFF4E9A06),
              yellow:
                  isDark ? const Color(0xFFC4A000) : const Color(0xFFC4A000),
              blue: isDark ? const Color(0xFF3465A4) : const Color(0xFF3465A4),
              magenta:
                  isDark ? const Color(0xFF75507B) : const Color(0xFF75507B),
              cyan: isDark ? const Color(0xFF06989A) : const Color(0xFF06989A),
              white:
                  isDark ? const Color(0xFFD3D7CF) : const Color(0xFFFFFFFF),
              brightBlack:
                  isDark ? const Color(0xFF555753) : const Color(0xFF555753),
              brightRed:
                  isDark ? const Color(0xFFEF2929) : const Color(0xFFEF2929),
              brightGreen:
                  isDark ? const Color(0xFF8AE234) : const Color(0xFF8AE234),
              brightYellow:
                  isDark ? const Color(0xFFFCE94F) : const Color(0xFFFCE94F),
              brightBlue:
                  isDark ? const Color(0xFF729FCF) : const Color(0xFF729FCF),
              brightMagenta:
                  isDark ? const Color(0xFFAD7FA8) : const Color(0xFFAD7FA8),
              brightCyan:
                  isDark ? const Color(0xFF34E2E2) : const Color(0xFF34E2E2),
              brightWhite:
                  isDark ? const Color(0xFFEEEEEC) : const Color(0xFFFFFFFF),
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
            autofocus: !isScriptTab,
            readOnly: isScriptTab,
          ),
        ),
      ),
    );
  }

  Widget _buildScriptActions(BuildContext context, RunningScript script) {
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

  Widget _buildScriptStatusBar(BuildContext context, RunningScript? script) {
    if (script == null) return const SizedBox.shrink();

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
        ],
      ),
    );
  }

  bool _isScriptTab(TerminalTab tab) {
    return _scriptToTabId.containsValue(tab.id);
  }

  void _createScriptTab(RunningScript script) {
    final terminal = Terminal();

    // Get PTY from script and connect to terminal
    final tab = TerminalTab(
      name: script.name,
      terminal: terminal,
      pty: script.pty,
      workingDirectory: script.workingDirectory,
    );

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
      _scriptToTabId[script.id] = tab.id;
    });

    // Subscribe to script output stream (already has data)
    final sub = script.outputStream.listen((data) {
      final text = String.fromCharCodes(data);
      terminal.write(text);
    });
    _subscriptions[tab.id] = sub;
  }
}

class _NoTerminalsPlaceholder extends StatelessWidget {
  const _NoTerminalsPlaceholder();

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
              'No terminals open',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Click + to open a new terminal',
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
