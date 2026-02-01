import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../services/project_config_service.dart';
import '../services/script_execution_service.dart';
import '../state/selection_state.dart';
import '../widgets/edit_action_dialog.dart';
import 'panel_wrapper.dart';

/// Keys for testing ActionsPanel widgets.
class ActionsPanelKeys {
  ActionsPanelKeys._();

  /// The panel wrapper.
  static const panel = Key('actions_panel');

  /// Prefix for action buttons - use with action name, e.g., "action_button_Test".
  static const actionButtonPrefix = 'action_button_';

  /// Key for a specific action button.
  static Key actionButton(String name) => Key('$actionButtonPrefix$name');
}

/// Panel that displays configurable action buttons for running scripts.
///
/// Actions are loaded from `.ccinsights/config.json` in the project root.
/// - If config doesn't exist or has no `user-actions`: shows defaults (Test, Run)
/// - If `user-actions` is empty `{}`: shows no buttons
/// - Otherwise: shows configured buttons
class ActionsPanel extends StatelessWidget {
  const ActionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      key: ActionsPanelKeys.panel,
      title: 'Actions',
      icon: Icons.play_circle_outline,
      child: _ActionsPanelContent(),
    );
  }
}

class _ActionsPanelContent extends StatefulWidget {
  const _ActionsPanelContent();

  @override
  State<_ActionsPanelContent> createState() => _ActionsPanelContentState();
}

class _ActionsPanelContentState extends State<_ActionsPanelContent> {
  final ProjectConfigService _configService = ProjectConfigService();
  ProjectConfig? _config;
  bool _isLoading = true;
  String? _lastProjectRoot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final project = context.read<ProjectState>();
    final projectRoot = project.data.repoRoot;

    if (projectRoot != _lastProjectRoot) {
      _lastProjectRoot = projectRoot;
      _loadConfig();
    }
  }

  Future<void> _loadConfig() async {
    if (_lastProjectRoot == null) {
      setState(() {
        _config = null;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final config = await _configService.loadConfig(_lastProjectRoot!);
      if (mounted) {
        setState(() {
          _config = config;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _config = const ProjectConfig.empty();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleActionClick(String name, String? command) async {
    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) return;

    final workingDirectory = worktree.data.worktreeRoot;

    if (command == null || command.isEmpty) {
      // Prompt for command first
      final newCommand = await showEditActionDialog(
        context,
        actionName: name,
        currentCommand: null,
        workingDirectory: workingDirectory,
      );

      if (newCommand != null && newCommand.isNotEmpty && mounted) {
        // Save to config
        await _configService.updateUserAction(
          _lastProjectRoot!,
          name,
          newCommand,
        );
        await _loadConfig();

        // Now run the script
        _runScript(name, newCommand, workingDirectory);
      }
    } else {
      _runScript(name, command, workingDirectory);
    }
  }

  void _runScript(String name, String command, String workingDirectory) {
    context.read<ScriptExecutionService>().runScript(
      name: name,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  Future<void> _handleRightClick(
    String name,
    String? currentCommand,
    Offset position,
  ) async {
    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;
    final workingDirectory = worktree?.data.worktreeRoot;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: const [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('Edit command'),
            ],
          ),
        ),
      ],
    );

    if (result == 'edit' && mounted) {
      final newCommand = await showEditActionDialog(
        context,
        actionName: name,
        currentCommand: currentCommand,
        workingDirectory: workingDirectory,
      );

      if (newCommand != null && mounted) {
        await _configService.updateUserAction(
          _lastProjectRoot!,
          name,
          newCommand,
        );
        await _loadConfig();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) {
      return const _NoWorktreePlaceholder();
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final userActions = _config?.effectiveUserActions ?? {};

    if (userActions.isEmpty) {
      return const _NoActionsPlaceholder();
    }

    final scriptService = context.watch<ScriptExecutionService>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: userActions.entries.map((entry) {
          final isRunning = scriptService.isActionRunning(entry.key);
          return _ActionButton(
            key: ActionsPanelKeys.actionButton(entry.key),
            name: entry.key,
            command: entry.value,
            isRunning: isRunning,
            onPressed: () => _handleActionClick(entry.key, entry.value),
            onRightClick: (pos) => _handleRightClick(
              entry.key,
              entry.value,
              pos,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.name,
    required this.command,
    required this.isRunning,
    required this.onPressed,
    required this.onRightClick,
  });

  final String name;
  final String command;
  final bool isRunning;
  final VoidCallback onPressed;
  final void Function(Offset) onRightClick;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isConfigured = command.isNotEmpty;

    return Tooltip(
      message: isConfigured ? command : 'Click to configure',
      child: Material(
        color: isRunning
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: isRunning ? null : onPressed,
          onSecondaryTapUp: (details) => onRightClick(details.globalPosition),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: isRunning
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isRunning)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    isConfigured ? Icons.play_arrow : Icons.add,
                    size: 14,
                    color: colorScheme.onSurface,
                  ),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoWorktreePlaceholder extends StatelessWidget {
  const _NoWorktreePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Select a worktree to see actions',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _NoActionsPlaceholder extends StatelessWidget {
  const _NoActionsPlaceholder();

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
            Text(
              'No actions configured',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Add user-actions to .ccinsights/config.json',
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
