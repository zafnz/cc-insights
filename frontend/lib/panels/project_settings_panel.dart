import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../services/project_config_service.dart';
import '../state/selection_state.dart';

/// Keys for testing ProjectSettingsPanel widgets.
class ProjectSettingsPanelKeys {
  ProjectSettingsPanelKeys._();

  static const panel = Key('project_settings_panel');
  static const closeButton = Key('project_settings_close_button');

  // Lifecycle hook fields
  static const preCreateField = Key('project_settings_pre_create_field');
  static const postCreateField = Key('project_settings_post_create_field');
  static const preRemoveField = Key('project_settings_pre_remove_field');
  static const postRemoveField = Key('project_settings_post_remove_field');

  // User action fields
  static const userActionPrefix = 'project_settings_user_action_';
  static Key userActionField(String name) => Key('$userActionPrefix$name');
  static const addActionButton = Key('project_settings_add_action_button');
}

/// Panel for configuring project-specific settings.
///
/// Settings are stored in `.ccinsights/config.json` at the project root.
/// This includes:
/// - Lifecycle hooks (worktree-pre-create, worktree-post-create, etc.)
/// - User-defined action buttons
class ProjectSettingsPanel extends StatefulWidget {
  const ProjectSettingsPanel({super.key});

  @override
  State<ProjectSettingsPanel> createState() => _ProjectSettingsPanelState();
}

class _ProjectSettingsPanelState extends State<ProjectSettingsPanel> {
  final ProjectConfigService _configService = ProjectConfigService();
  ProjectConfig _config = const ProjectConfig.empty();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Controllers for lifecycle hooks
  final _preCreateController = TextEditingController();
  final _postCreateController = TextEditingController();
  final _preRemoveController = TextEditingController();
  final _postRemoveController = TextEditingController();

  // User actions - stored as list of (name, command) pairs for editing
  List<_UserActionEntry> _userActions = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _preCreateController.dispose();
    _postCreateController.dispose();
    _preRemoveController.dispose();
    _postRemoveController.dispose();
    for (final action in _userActions) {
      action.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final project = context.read<ProjectState>();
    final projectRoot = project.data.repoRoot;

    try {
      final config = await _configService.loadConfig(projectRoot);
      if (mounted) {
        setState(() {
          _config = config;
          _populateControllers(config);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load config: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _populateControllers(ProjectConfig config) {
    // Populate lifecycle hooks
    _preCreateController.text = config.actions['worktree-pre-create'] ?? '';
    _postCreateController.text = config.actions['worktree-post-create'] ?? '';
    _preRemoveController.text = config.actions['worktree-pre-remove'] ?? '';
    _postRemoveController.text = config.actions['worktree-post-remove'] ?? '';

    // Dispose old user action controllers
    for (final action in _userActions) {
      action.dispose();
    }

    // Populate user actions
    final userActions = config.userActions;
    if (userActions != null) {
      _userActions = userActions.entries.map((entry) {
        return _UserActionEntry(
          nameController: TextEditingController(text: entry.key),
          commandController: TextEditingController(text: entry.value),
        );
      }).toList();
    } else {
      // Show defaults as editable entries
      _userActions = ProjectConfig.defaultUserActions.entries.map((entry) {
        return _UserActionEntry(
          nameController: TextEditingController(text: entry.key),
          commandController: TextEditingController(text: entry.value),
        );
      }).toList();
    }
  }

  Future<void> _saveConfig() async {
    final project = context.read<ProjectState>();
    final projectRoot = project.data.repoRoot;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      // Build actions map
      final actions = <String, String>{};
      if (_preCreateController.text.trim().isNotEmpty) {
        actions['worktree-pre-create'] = _preCreateController.text.trim();
      }
      if (_postCreateController.text.trim().isNotEmpty) {
        actions['worktree-post-create'] = _postCreateController.text.trim();
      }
      if (_preRemoveController.text.trim().isNotEmpty) {
        actions['worktree-pre-remove'] = _preRemoveController.text.trim();
      }
      if (_postRemoveController.text.trim().isNotEmpty) {
        actions['worktree-post-remove'] = _postRemoveController.text.trim();
      }

      // Build user actions map
      final userActions = <String, String>{};
      for (final action in _userActions) {
        final name = action.nameController.text.trim();
        final command = action.commandController.text.trim();
        if (name.isNotEmpty) {
          userActions[name] = command;
        }
      }

      final newConfig = ProjectConfig(
        actions: actions,
        userActions: userActions.isEmpty ? null : userActions,
      );

      await _configService.saveConfig(projectRoot, newConfig);

      if (mounted) {
        setState(() {
          _config = newConfig;
          _isSaving = false;
        });

        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save: $e';
          _isSaving = false;
        });
      }
    }
  }

  void _addUserAction() {
    setState(() {
      _userActions.add(_UserActionEntry(
        nameController: TextEditingController(),
        commandController: TextEditingController(),
      ));
    });
  }

  void _removeUserAction(int index) {
    setState(() {
      _userActions[index].dispose();
      _userActions.removeAt(index);
    });
  }

  void _handleClose() {
    context.read<SelectionState>().showConversationPanel();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();

    return Column(
      key: ProjectSettingsPanelKeys.panel,
      children: [
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with project path
                _buildHeader(context, project.data.repoRoot),
                const SizedBox(height: 24),

                // Lifecycle Hooks Section
                _buildSectionHeader(
                  context,
                  'Lifecycle Hooks',
                  'Scripts that run during worktree operations',
                  Icons.sync_alt,
                ),
                const SizedBox(height: 16),
                _buildLifecycleHooksSection(context),
                const SizedBox(height: 32),

                // User Actions Section
                _buildSectionHeader(
                  context,
                  'User Actions',
                  'Custom buttons shown in the Actions panel',
                  Icons.play_circle_outline,
                ),
                const SizedBox(height: 16),
                _buildUserActionsSection(context),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 24),
                  _buildErrorCard(context, _errorMessage!),
                ],
              ],
            ),
          ),
        ),

        // Action bar at bottom
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: ProjectSettingsPanelKeys.closeButton,
                onPressed: _handleClose,
                child: const Text('Close'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveConfig,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, String projectRoot) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.settings,
            size: 24,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project Settings',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  projectRoot,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLifecycleHooksSection(BuildContext context) {
    return Column(
      children: [
        _HookField(
          key: ProjectSettingsPanelKeys.preCreateField,
          label: 'Pre-Create',
          description: 'Runs before git worktree add',
          controller: _preCreateController,
          hookName: 'worktree-pre-create',
        ),
        const SizedBox(height: 12),
        _HookField(
          key: ProjectSettingsPanelKeys.postCreateField,
          label: 'Post-Create',
          description: 'Runs after worktree is created (e.g., npm install)',
          controller: _postCreateController,
          hookName: 'worktree-post-create',
        ),
        const SizedBox(height: 12),
        _HookField(
          key: ProjectSettingsPanelKeys.preRemoveField,
          label: 'Pre-Remove',
          description: 'Runs before worktree removal',
          controller: _preRemoveController,
          hookName: 'worktree-pre-remove',
        ),
        const SizedBox(height: 12),
        _HookField(
          key: ProjectSettingsPanelKeys.postRemoveField,
          label: 'Post-Remove',
          description: 'Runs after worktree removal',
          controller: _postRemoveController,
          hookName: 'worktree-post-remove',
        ),
      ],
    );
  }

  Widget _buildUserActionsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User action entries
        ..._userActions.asMap().entries.map((entry) {
          final index = entry.key;
          final action = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _UserActionRow(
              key: ProjectSettingsPanelKeys.userActionField(
                action.nameController.text.isNotEmpty
                    ? action.nameController.text
                    : 'new_$index',
              ),
              nameController: action.nameController,
              commandController: action.commandController,
              onRemove: () => _removeUserAction(index),
            ),
          );
        }),

        // Add action button
        OutlinedButton.icon(
          key: ProjectSettingsPanelKeys.addActionButton,
          onPressed: _addUserAction,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Action'),
        ),

        // Help text
        const SizedBox(height: 12),
        Text(
          'Actions appear as buttons in the Actions panel. '
          'Leave the command empty to prompt on first click.',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single lifecycle hook field.
class _HookField extends StatelessWidget {
  const _HookField({
    super.key,
    required this.label,
    required this.description,
    required this.controller,
    required this.hookName,
  });

  final String label;
  final String description;
  final TextEditingController controller;
  final String hookName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'JetBrains Mono',
            ),
            decoration: InputDecoration(
              hintText: 'e.g., npm install',
              hintStyle: textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrains Mono',
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// A row for editing a user action (name + command).
class _UserActionRow extends StatelessWidget {
  const _UserActionRow({
    super.key,
    required this.nameController,
    required this.commandController,
    required this.onRemove,
  });

  final TextEditingController nameController;
  final TextEditingController commandController;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name field
          SizedBox(
            width: 120,
            child: TextField(
              controller: nameController,
              style: textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: textTheme.labelSmall,
                hintText: 'Test',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Command field
          Expanded(
            child: TextField(
              controller: commandController,
              style: textTheme.bodySmall?.copyWith(
                fontFamily: 'JetBrains Mono',
              ),
              decoration: InputDecoration(
                labelText: 'Command',
                labelStyle: textTheme.labelSmall,
                hintText: './test.sh',
                hintStyle: textTheme.bodySmall?.copyWith(
                  fontFamily: 'JetBrains Mono',
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Remove button
          IconButton(
            icon: Icon(
              Icons.close,
              size: 18,
              color: colorScheme.error,
            ),
            onPressed: onRemove,
            tooltip: 'Remove action',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Helper class to hold controllers for a user action entry.
class _UserActionEntry {
  _UserActionEntry({
    required this.nameController,
    required this.commandController,
  });

  final TextEditingController nameController;
  final TextEditingController commandController;

  void dispose() {
    nameController.dispose();
    commandController.dispose();
  }
}
