import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/project_config.dart';
import '../services/project_config_service.dart';
import '../state/selection_state.dart';
import '../widgets/insights_widgets.dart';

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

  // Git settings fields
  static const defaultBaseSelector =
      Key('project_settings_default_base_selector');
  static const customBaseField = Key('project_settings_custom_base_field');
}

/// Category definition for project settings sidebar.
class _SettingsCategory {
  const _SettingsCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
  });

  final String id;
  final String label;
  final IconData icon;
  final String description;
}

const _categories = [
  _SettingsCategory(
    id: 'hooks',
    label: 'Lifecycle Hooks',
    icon: Icons.sync_alt,
    description: 'Scripts that run during worktree operations',
  ),
  _SettingsCategory(
    id: 'actions',
    label: 'User Actions',
    icon: Icons.play_circle_outline,
    description: 'Custom buttons shown in the Actions panel',
  ),
  _SettingsCategory(
    id: 'git',
    label: 'Git',
    icon: Icons.call_split,
    description: 'Default branch comparison settings',
  ),
];

/// Panel for configuring project-specific settings.
///
/// Settings are stored in `.ccinsights/config.json` at the project root.
/// This includes:
/// - Lifecycle hooks (worktree-pre-create, worktree-post-create, etc.)
/// - User-defined action buttons
class ProjectSettingsPanel extends StatefulWidget {
  const ProjectSettingsPanel({super.key, this.configService});

  /// Optional config service for dependency injection (used in tests).
  final ProjectConfigService? configService;

  @override
  State<ProjectSettingsPanel> createState() => _ProjectSettingsPanelState();
}

class _ProjectSettingsPanelState extends State<ProjectSettingsPanel> {
  late final ProjectConfigService _configService;
  ProjectConfig _config = const ProjectConfig.empty();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  String _selectedCategoryId = _categories.first.id;

  // Controllers for lifecycle hooks
  final _preCreateController = TextEditingController();
  final _postCreateController = TextEditingController();
  final _preRemoveController = TextEditingController();
  final _postRemoveController = TextEditingController();

  // User actions - stored as list of (name, command) pairs for editing
  List<_UserActionEntry> _userActions = [];

  // Git settings
  String _defaultBaseSelection = 'auto';
  final _customBaseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _configService = widget.configService ?? ProjectConfigService();
    _loadConfig();
  }

  @override
  void dispose() {
    _preCreateController.dispose();
    _postCreateController.dispose();
    _preRemoveController.dispose();
    _postRemoveController.dispose();
    _customBaseController.dispose();
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

    // Populate default base
    final base = config.defaultBase;
    if (base == null || base == 'auto') {
      _defaultBaseSelection = 'auto';
      _customBaseController.text = '';
    } else if (base == 'main' || base == 'origin/main') {
      _defaultBaseSelection = base;
      _customBaseController.text = '';
    } else {
      _defaultBaseSelection = 'custom';
      _customBaseController.text = base;
    }

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

      // Resolve default base value
      String? defaultBase;
      if (_defaultBaseSelection == 'main' ||
          _defaultBaseSelection == 'origin/main') {
        defaultBase = _defaultBaseSelection;
      } else if (_defaultBaseSelection == 'custom') {
        final custom = _customBaseController.text.trim();
        defaultBase = custom.isNotEmpty ? custom : null;
      }
      // 'auto' or anything else => null (use auto-detect)

      final newConfig = ProjectConfig(
        actions: actions,
        userActions: userActions.isEmpty ? null : userActions,
        defaultBase: defaultBase,
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
    final project = context.watch<ProjectState>();

    return Center(
      key: ProjectSettingsPanelKeys.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(
          children: [
            _SettingsSidebar(
              categories: _categories,
              selectedCategoryId: _selectedCategoryId,
              onCategorySelected: (id) {
                setState(() => _selectedCategoryId = id);
              },
              projectRoot: project.data.repoRoot,
              onClose: _handleClose,
              onSave: _saveConfig,
              isSaving: _isSaving,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _SettingsContent(
                category: _categories.firstWhere(
                  (c) => c.id == _selectedCategoryId,
                ),
                preCreateController: _preCreateController,
                postCreateController: _postCreateController,
                preRemoveController: _preRemoveController,
                postRemoveController: _postRemoveController,
                userActions: _userActions,
                onAddUserAction: _addUserAction,
                onRemoveUserAction: _removeUserAction,
                defaultBaseSelection: _defaultBaseSelection,
                onDefaultBaseChanged: (value) {
                  setState(() => _defaultBaseSelection = value);
                },
                customBaseController: _customBaseController,
                errorMessage: _errorMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar
// -----------------------------------------------------------------------------

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.projectRoot,
    required this.onClose,
    required this.onSave,
    required this.isSaving,
  });

  final List<_SettingsCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final String projectRoot;
  final VoidCallback onClose;
  final VoidCallback onSave;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Extract project name from path
    final projectName = projectRoot.split('/').last;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Project Settings',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              projectName,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'JetBrains Mono',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          // Category list
          for (final category in categories)
            _CategoryTile(
              category: category,
              isSelected: category.id == selectedCategoryId,
              onTap: () => onCategorySelected(category.id),
            ),
          const Spacer(),
          // Footer with actions
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: InsightsFilledButton(
                    onPressed: isSaving ? null : onSave,
                    icon: isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 16),
                    child: Text(isSaving ? 'Saving...' : 'Save'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: InsightsOutlinedButton(
                    key: ProjectSettingsPanelKeys.closeButton,
                    onPressed: onClose,
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final _SettingsCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: isSelected ? colorScheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                category.icon,
                size: 16,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Content area
// -----------------------------------------------------------------------------

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.category,
    required this.preCreateController,
    required this.postCreateController,
    required this.preRemoveController,
    required this.postRemoveController,
    required this.userActions,
    required this.onAddUserAction,
    required this.onRemoveUserAction,
    required this.defaultBaseSelection,
    required this.onDefaultBaseChanged,
    required this.customBaseController,
    this.errorMessage,
  });

  final _SettingsCategory category;
  final TextEditingController preCreateController;
  final TextEditingController postCreateController;
  final TextEditingController preRemoveController;
  final TextEditingController postRemoveController;
  final List<_UserActionEntry> userActions;
  final VoidCallback onAddUserAction;
  final void Function(int) onRemoveUserAction;
  final String defaultBaseSelection;
  final ValueChanged<String> onDefaultBaseChanged;
  final TextEditingController customBaseController;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        // Category header
        Text(
          category.label,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          category.description,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        // Content based on category
        if (category.id == 'hooks') ...[
          _buildHooksContent(context),
        ] else if (category.id == 'actions') ...[
          _buildActionsContent(context),
        ] else if (category.id == 'git') ...[
          _buildGitContent(context),
        ],
        // Error message
        if (errorMessage != null) ...[
          const SizedBox(height: 24),
          _buildErrorCard(context, errorMessage!),
        ],
      ],
    );
  }

  Widget _buildHooksContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _HookRow(
          key: ProjectSettingsPanelKeys.preCreateField,
          title: 'Pre-Create',
          description:
              'Runs before `git worktree add`. Working directory is the repository root.',
          controller: preCreateController,
          placeholder: 'e.g., echo "Creating worktree..."',
        ),
        Divider(
          height: 48,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        _HookRow(
          key: ProjectSettingsPanelKeys.postCreateField,
          title: 'Post-Create',
          description:
              'Runs after worktree is created. Working directory is the new worktree.',
          controller: postCreateController,
          placeholder: 'e.g., npm install',
        ),
        Divider(
          height: 48,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        _HookRow(
          key: ProjectSettingsPanelKeys.preRemoveField,
          title: 'Pre-Remove',
          description:
              'Runs before worktree removal. Working directory is the worktree being removed.',
          controller: preRemoveController,
          placeholder: 'e.g., rm -rf node_modules',
        ),
        Divider(
          height: 48,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        _HookRow(
          key: ProjectSettingsPanelKeys.postRemoveField,
          title: 'Post-Remove',
          description:
              'Runs after worktree removal. Working directory is the repository root.',
          controller: postRemoveController,
          placeholder: 'e.g., echo "Worktree removed"',
        ),
      ],
    );
  }

  Widget _buildActionsContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // User action entries
        for (var i = 0; i < userActions.length; i++) ...[
          _UserActionRow(
            key: ProjectSettingsPanelKeys.userActionField(
              userActions[i].nameController.text.isNotEmpty
                  ? userActions[i].nameController.text
                  : 'new_$i',
            ),
            nameController: userActions[i].nameController,
            commandController: userActions[i].commandController,
            onRemove: () => onRemoveUserAction(i),
          ),
          if (i < userActions.length - 1)
            Divider(
              height: 32,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
        ],
        if (userActions.isNotEmpty) const SizedBox(height: 24),
        // Add action button
        OutlinedButton.icon(
          key: ProjectSettingsPanelKeys.addActionButton,
          onPressed: onAddUserAction,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Action'),
        ),
        // Help text
        const SizedBox(height: 16),
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

  Widget _buildGitContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default base for new worktrees',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          const InsightsDescriptionText(
            'The base branch used for merge and diff operations. '
            'New worktrees inherit this setting unless overridden.',
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            key: ProjectSettingsPanelKeys.defaultBaseSelector,
            value: defaultBaseSelection,
            isExpanded: true,
            onChanged: (value) {
              if (value != null) {
                onDefaultBaseChanged(value);
              }
            },
            items: const [
              DropdownMenuItem(
                value: 'auto',
                child: Text('Auto (detect upstream)'),
              ),
              DropdownMenuItem(
                value: 'main',
                child: Text('main'),
              ),
              DropdownMenuItem(
                value: 'origin/main',
                child: Text('origin/main'),
              ),
              DropdownMenuItem(
                value: 'custom',
                child: Text('Custom...'),
              ),
            ],
          ),
          if (defaultBaseSelection == 'custom') ...[
            const SizedBox(height: 12),
            InsightsTextField(
              key: ProjectSettingsPanelKeys.customBaseField,
              controller: customBaseController,
              hintText: 'e.g., develop, origin/develop',
              monospace: true,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Auto-detect checks for an upstream remote and uses '
            '`origin/main` if it exists, otherwise falls back '
            'to local `main`.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
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

// -----------------------------------------------------------------------------
// Hook row (similar to _SettingRow in SettingsScreen)
// -----------------------------------------------------------------------------

class _HookRow extends StatelessWidget {
  const _HookRow({
    super.key,
    required this.title,
    required this.description,
    required this.controller,
    required this.placeholder,
  });

  final String title;
  final String description;
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          InsightsDescriptionText(description),
          const SizedBox(height: 12),
          InsightsTextField(
            controller: controller,
            hintText: placeholder,
            monospace: true,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// User action row
// -----------------------------------------------------------------------------

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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: name + description
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Action Name',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Button label shown in the Actions panel',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                InsightsTextField(
                  controller: nameController,
                  hintText: 'e.g., Test',
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right side: command
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Command',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: colorScheme.error,
                      ),
                      onPressed: onRemove,
                      tooltip: 'Remove action',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Shell command to run (empty = prompt)',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                InsightsTextField(
                  controller: commandController,
                  hintText: 'e.g., ./test.sh',
                  monospace: true,
                ),
              ],
            ),
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
