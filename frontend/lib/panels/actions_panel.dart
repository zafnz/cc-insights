import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../models/user_action.dart';
import '../services/log_service.dart';
import '../services/macro_executor.dart';
import '../services/project_config_service.dart';
import '../services/script_execution_service.dart';
import '../state/selection_state.dart';
import '../widgets/edit_action_dialog.dart';
import '../widgets/styled_popup_menu.dart';
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
/// - Otherwise: shows configured commands and macros
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
  ProjectConfig _config = const ProjectConfig.empty();
  String? _lastProjectRoot;
  ProjectConfigService? _configService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Subscribe to config service changes (e.g. saves from ProjectSettingsPanel)
    final configService = context.read<ProjectConfigService>();
    if (_configService != configService) {
      _configService?.removeListener(_onConfigChanged);
      _configService = configService;
      _configService!.addListener(_onConfigChanged);
    }

    final project = context.read<ProjectState>();
    final projectRoot = project.data.repoRoot;

    if (projectRoot != _lastProjectRoot) {
      _lastProjectRoot = projectRoot;
      _config = const ProjectConfig.empty();
      _loadConfig();
    }
  }

  @override
  void dispose() {
    _configService?.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    if (_lastProjectRoot == null || _configService == null) return;
    final config = await _configService!.loadConfig(_lastProjectRoot!);
    if (mounted) {
      setState(() => _config = config);
    }
  }

  Future<void> _handleActionClick(UserAction action) async {
    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) return;

    final workingDirectory = worktree.data.worktreeRoot;

    switch (action) {
      case CommandAction(:final name, :final command, :final autoClose):
        if (command.isEmpty) {
          final result = await showEditActionDialog(
            context,
            actionName: name,
            currentCommand: null,
            autoClose: autoClose,
            workingDirectory: workingDirectory,
          );

          if (result != null && result.command.isNotEmpty && mounted) {
            final newAction = CommandAction(
              name: name,
              command: result.command,
              autoClose: result.autoClose,
            );
            await _configService!.updateUserAction(
              _lastProjectRoot!,
              newAction,
            );
            _runScript(name, result.command, workingDirectory, result.autoClose);
          }
          return;
        }
        _runScript(name, command, workingDirectory, autoClose);
        return;
      case StartChatMacro():
        await MacroExecutor.executeStartChat(context, worktree, action);
        return;
    }
  }

  void _runScript(
    String name,
    String command,
    String workingDirectory,
    AutoCloseBehavior autoClose,
  ) {
    LogService.instance.notice('Actions', 'Running action: $name');
    context.read<ScriptExecutionService>().runScript(
      name: name,
      command: command,
      workingDirectory: workingDirectory,
      autoClose: autoClose,
    );
  }

  Future<void> _handleRightClick(UserAction action, Offset position) async {
    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;
    final workingDirectory = worktree?.data.worktreeRoot;
    final editLabel = action is CommandAction ? 'Edit command' : 'Edit macro';

    final result = await showStyledMenu<String>(
      context: context,
      position: menuPositionFromOffset(position),
      items: [
        styledMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              Text(editLabel),
            ],
          ),
        ),
      ],
    );

    if (result != 'edit' || !mounted) return;

    switch (action) {
      case CommandAction(:final name, :final command, :final autoClose):
        final result = await showEditActionDialog(
          context,
          actionName: name,
          currentCommand: command,
          autoClose: autoClose,
          workingDirectory: workingDirectory,
        );

        if (result != null && mounted) {
          await _configService!.updateUserAction(
            _lastProjectRoot!,
            CommandAction(
              name: name,
              command: result.command,
              autoClose: result.autoClose,
            ),
          );
        }
        return;
      case StartChatMacro():
        selection.showProjectSettingsPanel();
        return;
    }
  }

  String _tooltipForAction(UserAction action) {
    return switch (action) {
      CommandAction(:final command) =>
        command.isNotEmpty ? command : 'Click to configure',
      StartChatMacro(:final instruction) => _instructionPreview(instruction),
    };
  }

  String _instructionPreview(String instruction) {
    final compact = instruction.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) {
      return 'Start chat macro';
    }
    if (compact.length <= 100) {
      return compact;
    }
    return '${compact.substring(0, 100)}...';
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) {
      return const _NoWorktreePlaceholder();
    }

    return _buildActionButtons(context, _config, worktree.data.worktreeRoot);
  }

  Widget _buildActionButtons(
    BuildContext context,
    ProjectConfig config,
    String workingDirectory,
  ) {
    final userActions = config.effectiveUserActions;

    if (userActions.isEmpty) {
      return const _NoActionsPlaceholder();
    }

    final scriptService = context.watch<ScriptExecutionService>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: userActions.map((action) {
          final isRunning = switch (action) {
            CommandAction(:final name) => scriptService.isActionRunning(
              name,
              workingDirectory: workingDirectory,
            ),
            StartChatMacro() => false,
          };
          return _ActionButton(
            key: ActionsPanelKeys.actionButton(action.name),
            action: action,
            tooltip: _tooltipForAction(action),
            isRunning: isRunning,
            onPressed: () => _handleActionClick(action),
            onRightClick: (pos) => _handleRightClick(action, pos),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.action,
    required this.tooltip,
    required this.isRunning,
    required this.onPressed,
    required this.onRightClick,
  });

  final UserAction action;
  final String tooltip;
  final bool isRunning;
  final VoidCallback onPressed;
  final void Function(Offset) onRightClick;

  bool get _isConfigured => switch (action) {
    CommandAction(:final command) => command.isNotEmpty,
    StartChatMacro() => true,
  };

  IconData get _idleIcon => switch (action) {
    CommandAction() => _isConfigured ? Icons.play_arrow : Icons.add,
    StartChatMacro() => action.icon,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Tooltip(
      message: tooltip,
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
                  Icon(_idleIcon, size: 14, color: colorScheme.onSurface),
                const SizedBox(width: 6),
                Text(
                  action.name,
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
