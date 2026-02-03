import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_tab.dart';
import '../services/script_execution_service.dart';
import '../state/selection_state.dart';
import '../widgets/keyboard_focus_manager.dart';
import '../widgets/styled_popup_menu.dart';
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
  static const _autoCloseDelay = Duration(seconds: 5);

  /// List of all terminal tabs (both script output and interactive shells).
  final List<TerminalTab> _tabs = [];

  /// Currently active tab index.
  int _activeTabIndex = 0;

  /// Map of script IDs to terminal tab IDs (for script execution output).
  final Map<String, String> _scriptToTabId = {};

  /// Stream subscriptions for terminal output.
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};

  /// Auto-close countdown timers for successful script tabs.
  final Map<String, Timer> _autoCloseTimers = {};

  /// Track which scripts have auto-close in progress.
  final Set<String> _autoClosingScripts = {};

  /// Track remaining seconds for auto-close countdown.
  final Map<String, int> _autoCloseCountdown = {};

  /// Track scripts that user explicitly chose to keep open (don't auto-close again).
  final Set<String> _keptOpenScripts = {};

  /// Keyboard focus manager resume callback.
  VoidCallback? _keyboardResume;

  /// Whether a terminal currently has focus.
  bool _terminalHasFocus = false;


  @override
  void dispose() {
    // Cancel all timers
    for (final timer in _autoCloseTimers.values) {
      timer.cancel();
    }
    _autoCloseTimers.clear();

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

  /// Counter for terminal numbers per worktree path.
  final Map<String, int> _worktreeTerminalCounts = {};

  void _createNewTerminal() {
    // Use selected worktree's directory, fallback to current directory
    final selectionState = context.read<SelectionState>();
    final selectedWorktree = selectionState.selectedWorktree;
    final workingDir =
        selectedWorktree?.data.worktreeRoot ?? Directory.current.path;

    // Generate tab name based on worktree
    final worktreeName = _getWorktreeName(workingDir);
    final terminalNumber = _getNextTerminalNumber(workingDir);
    final tabName = '($worktreeName) $terminalNumber';

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
      name: tabName,
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

    // Handle PTY exit - auto-close the tab when shell exits
    pty.exitCode.then((code) {
      if (mounted) {
        final tabIndex = _tabs.indexWhere((t) => t.id == tab.id);
        if (tabIndex != -1) {
          _closeTab(tabIndex);
        }
      }
    });
  }

  /// Extracts the worktree name from the path (last directory component).
  String _getWorktreeName(String path) {
    return p.basename(path);
  }

  /// Gets the next terminal number for a worktree, incrementing the counter.
  int _getNextTerminalNumber(String worktreePath) {
    final count = (_worktreeTerminalCounts[worktreePath] ?? 0) + 1;
    _worktreeTerminalCounts[worktreePath] = count;
    return count;
  }

  /// Shows the rename dialog for a terminal tab.
  Future<void> _showRenameDialog(TerminalTab tab) async {
    final controller = TextEditingController(text: tab.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Terminal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName != null && newName.trim().isNotEmpty) {
      setState(() {
        tab.name = newName.trim();
      });
    }
  }

  /// Shows the context menu for a terminal tab.
  void _showTabContextMenu(TerminalTab tab, TapDownDetails details) {
    showStyledMenu<String>(
      context: context,
      position: menuPositionFromOffset(details.globalPosition),
      items: [
        styledMenuItem(
          value: 'rename',
          child: const Text('Rename'),
        ),
      ],
    ).then((value) {
      if (value == 'rename') {
        _showRenameDialog(tab);
      }
    });
  }

  void _closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;

    final tab = _tabs[index];

    // Cancel subscription
    _subscriptions[tab.id]?.cancel();
    _subscriptions.remove(tab.id);

    // If it's a script tab, find and clear the script from the service
    final scriptId = _scriptToTabId.entries
        .firstWhere((e) => e.value == tab.id, orElse: () => const MapEntry('', ''))
        .key;

    if (scriptId.isNotEmpty) {
      // Cancel auto-close timer if it exists
      _autoCloseTimers[scriptId]?.cancel();
      _autoCloseTimers.remove(scriptId);
      _autoClosingScripts.remove(scriptId);
      _autoCloseCountdown.remove(scriptId);
      _keptOpenScripts.remove(scriptId);

      // This is a script tab - clear it from the service
      context.read<ScriptExecutionService>().clearScript(scriptId);
      _scriptToTabId.remove(scriptId);
    }

    // Kill PTY if still alive (for non-script tabs)
    if (tab.isAlive && scriptId.isEmpty) {
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

    // Handle auto-close for successful script tabs
    for (final entry in _scriptToTabId.entries) {
      final scriptId = entry.key;
      final tabId = entry.value;
      final scriptForTab = scriptService.scripts
          .where((s) => s.id == scriptId)
          .firstOrNull;

      if (scriptForTab != null && !scriptForTab.isRunning && scriptForTab.isSuccess) {
        // Script completed successfully - start auto-close timer if not already started
        // Skip if user explicitly chose to keep this script open
        if (!_autoCloseTimers.containsKey(scriptId) && !_keptOpenScripts.contains(scriptId)) {
          _autoClosingScripts.add(scriptId);
          _autoCloseCountdown[scriptId] = _autoCloseDelay.inSeconds;

          // Create a periodic timer that updates countdown every second
          var secondsRemaining = _autoCloseDelay.inSeconds;
          final timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted || !_autoClosingScripts.contains(scriptId)) {
              timer.cancel();
              return;
            }

            secondsRemaining--;
            if (mounted) {
              setState(() {
                _autoCloseCountdown[scriptId] = secondsRemaining;
              });
            }

            if (secondsRemaining <= 0) {
              timer.cancel();
              if (mounted && _autoClosingScripts.contains(scriptId)) {
                final tabIndex = _tabs.indexWhere((t) => t.id == tabId);
                if (tabIndex != -1) {
                  _closeTab(tabIndex);
                }
              }
            }
          });

          _autoCloseTimers[scriptId] = timer;
        }
      }
    }

    return PanelWrapper(
      key: TerminalOutputPanelKeys.panel,
      title: 'Terminal',
      icon: Icons.terminal,
      trailing: IconButton(
        key: TerminalOutputPanelKeys.newTerminalButton,
        icon: const Icon(Icons.add, size: 16),
        onPressed: _createNewTerminal,
        tooltip: 'New Terminal',
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      ),
      child: _tabs.isEmpty
          ? const _NoTerminalsPlaceholder()
          : Column(
              children: [
                // Tab bar (always shown when there are tabs)
                _buildTabBar(),
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
    final scriptService = context.watch<ScriptExecutionService>();

    return Container(
      height: 28,
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
          final isScriptTab = _isScriptTab(tab);

          // Check if this script tab is running
          final scriptId = isScriptTab
              ? _scriptToTabId.entries
                  .firstWhere((e) => e.value == tab.id,
                      orElse: () => const MapEntry('', ''))
                  .key
              : '';
          final script = scriptId.isNotEmpty
              ? scriptService.scripts.firstWhere((s) => s.id == scriptId,
                  orElse: () => scriptService.scripts.first)
              : null;
          final isRunning = script?.isRunning ?? false;

          return GestureDetector(
            onTap: () {
              setState(() {
                _activeTabIndex = index;
              });
            },
            onSecondaryTapDown: isScriptTab
                ? null
                : (details) {
                    _showTabContextMenu(tab, details);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: isActive
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(width: 6),
                  if (isScriptTab && isRunning)
                    InkWell(
                      onTap: () {
                        if (scriptId.isNotEmpty) {
                          scriptService.killScript(scriptId);
                        }
                      },
                      child: Icon(
                        Icons.stop,
                        size: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => _closeTab(index),
                      child: Icon(
                        Icons.close,
                        size: 12,
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

    // Check if this script is auto-closing
    final isAutoClosing = _autoClosingScripts.contains(script.id);

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
          if (isAutoClosing) ...[
            const SizedBox(width: 12),
            Text(
              '• Closing in ${_autoCloseCountdown[script.id] ?? _autoCloseDelay.inSeconds}s',
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: TerminalOutputPanelKeys.keepOpenButton,
              onPressed: () => _cancelAutoClose(script.id),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Keep Open',
                style: textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _cancelAutoClose(String scriptId) {
    // Cancel the timer
    _autoCloseTimers[scriptId]?.cancel();
    _autoCloseTimers.remove(scriptId);

    // Remove from auto-closing set and countdown, mark as kept open
    setState(() {
      _autoClosingScripts.remove(scriptId);
      _autoCloseCountdown.remove(scriptId);
      _keptOpenScripts.add(scriptId);
    });
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
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
      ),
    );
  }
}
