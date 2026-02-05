import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/worktree_service.dart';
import '../state/selection_state.dart';

/// Keys for testing CreateWorktreePanel widgets.
class CreateWorktreePanelKeys {
  CreateWorktreePanelKeys._();

  static const branchField = Key('create_worktree_branch_field');
  static const rootField = Key('create_worktree_root_field');
  static const createButton = Key('create_worktree_create_button');
  static const cancelButton = Key('create_worktree_cancel_button');
  static const branchFromDropdown = Key('create_worktree_branch_from_dropdown');
  static const folderPickerButton = Key('create_worktree_folder_picker');
}

/// Panel for creating a new git worktree.
///
/// Displays a form with:
/// - Help text explaining what a worktree is
/// - Branch name field with autocomplete
/// - Worktree root directory field
/// - Error display area with suggestions
/// - Action buttons (Cancel / Create Worktree)
class CreateWorktreePanel extends StatefulWidget {
  const CreateWorktreePanel({super.key});

  @override
  State<CreateWorktreePanel> createState() => _CreateWorktreePanelState();
}

/// Options for the "Branch from" dropdown.
enum BranchFromOption {
  main,
  originMain,
  other,
}

class _CreateWorktreePanelState extends State<CreateWorktreePanel> {
  final _branchController = TextEditingController();
  final _rootController = TextEditingController();

  bool _isCreating = false;
  bool _isLoading = true;
  String? _errorMessage;
  List<String>? _errorSuggestions;
  List<String> _availableBranches = [];
  List<String> _existingWorktreeBranches = [];

  // Branch from selection
  BranchFromOption _branchFromOption = BranchFromOption.main;
  String? _selectedOtherBranch;

  @override
  void initState() {
    super.initState();
    _loadBranchesAndDefaults();
  }

  @override
  void dispose() {
    _branchController.dispose();
    _rootController.dispose();
    super.dispose();
  }

  /// Loads available branches and sets default worktree root.
  Future<void> _loadBranchesAndDefaults() async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();
    final repoRoot = project.data.repoRoot;

    try {
      // Load all branches
      final allBranches = await gitService.listBranches(repoRoot);

      // Load existing worktrees
      final worktrees = await gitService.discoverWorktrees(repoRoot);

      // Extract branch names from existing worktrees
      final worktreeBranches = worktrees
          .where((wt) => wt.branch != null)
          .map((wt) => wt.branch!)
          .toSet();

      // Filter available branches to exclude existing worktree branches
      final available = allBranches
          .where((branch) => !worktreeBranches.contains(branch))
          .toList();

      // Compute default worktree root
      final defaultRoot = await _computeDefaultWorktreeRoot(project, repoRoot);

      if (mounted) {
        setState(() {
          _availableBranches = available;
          _existingWorktreeBranches = worktreeBranches.toList();
          _rootController.text = defaultRoot;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load branch information: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// Computes the default worktree root directory.
  ///
  /// Uses the project's defaultWorktreeRoot from persistence if set,
  /// otherwise defaults to: `{project_parent_dir}/.{project_name}-wt`
  Future<String> _computeDefaultWorktreeRoot(
    ProjectState project,
    String repoRoot,
  ) async {
    // Try to get from persistence
    final persistenceService = PersistenceService();
    final projectsIndex = await persistenceService.loadProjectsIndex();
    final projectInfo = projectsIndex.projects[repoRoot];

    if (projectInfo?.defaultWorktreeRoot != null) {
      return projectInfo!.defaultWorktreeRoot!;
    }

    // Fall back to default: parent_dir/.project_name-wt
    final parentDir = path.dirname(repoRoot);
    final projectName = path.basename(repoRoot);
    return path.join(parentDir, '.$projectName-wt');
  }

  void _handleCancel() {
    context.read<SelectionState>().showConversationPanel();
  }

  Future<void> _handleCreate() async {
    final branch = _branchController.text.trim();
    final worktreeRoot = _rootController.text.trim();

    // Basic validation
    if (branch.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a branch name.';
        _errorSuggestions = null;
      });
      return;
    }

    if (worktreeRoot.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a worktree root directory.';
        _errorSuggestions = null;
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
      _errorSuggestions = null;
    });

    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      // Create the worktree
      final worktreeState = await worktreeService.createWorktree(
        project: project,
        branch: branch,
        worktreeRoot: worktreeRoot,
      );

      // Add worktree to project state
      project.addWorktree(worktreeState);

      // Select the new worktree
      if (mounted) {
        final selection = context.read<SelectionState>();
        selection.selectWorktree(worktreeState);

        // Return to conversation panel
        selection.showConversationPanel();
      }
    } on WorktreeCreationException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _errorSuggestions =
              e.suggestions.isNotEmpty ? e.suggestions : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred: $e';
          _errorSuggestions = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  /// Get the branch to create from based on current selection.
  String get _branchFrom {
    switch (_branchFromOption) {
      case BranchFromOption.main:
        return 'main';
      case BranchFromOption.originMain:
        return 'origin/main';
      case BranchFromOption.other:
        return _selectedOtherBranch ?? 'main';
    }
  }

  /// Get sorted branches with main and origin/main at top.
  List<String> get _sortedBranches {
    final branches = List<String>.from(_availableBranches);
    // Remove main and origin/main if present
    branches.remove('main');
    branches.remove('origin/main');
    // Sort remaining
    branches.sort();
    // Add main and origin/main at top
    final result = <String>[];
    if (_availableBranches.contains('main')) {
      result.add('main');
    }
    if (_availableBranches.contains('origin/main')) {
      result.add('origin/main');
    }
    result.addAll(branches);
    return result;
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Worktree Base Directory',
      initialDirectory: _rootController.text.isNotEmpty
          ? _rootController.text
          : null,
    );
    if (result != null) {
      setState(() {
        _rootController.text = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch/worktree name
          Text(
            'Branch/worktree name:',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _branchController,
            key: CreateWorktreePanelKeys.branchField,
            autofocus: true,
            onSubmitted: (_) => _handleCreate(),
          ),
          const SizedBox(height: 16),

          // Branch from
          _BranchFromField(
            option: _branchFromOption,
            selectedOtherBranch: _selectedOtherBranch,
            sortedBranches: _sortedBranches,
            onOptionChanged: (option) {
              setState(() {
                _branchFromOption = option;
                if (option != BranchFromOption.other) {
                  _selectedOtherBranch = null;
                }
              });
            },
            onOtherBranchSelected: (branch) {
              setState(() {
                _selectedOtherBranch = branch;
              });
            },
          ),
          const SizedBox(height: 16),

          // Worktree base
          Text(
            'Worktree base:',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _rootController,
                  key: CreateWorktreePanelKeys.rootField,
                ),
              ),
              const SizedBox(width: 8),
              _CompactButton(
                key: CreateWorktreePanelKeys.folderPickerButton,
                label: 'F',
                onPressed: _pickFolder,
                tooltip: 'Browse for folder',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Action buttons
          _ActionBar(
            isCreating: _isCreating,
            onCancel: _handleCancel,
            onCreate: _handleCreate,
          ),

          // Error card if error
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorCard(
              message: _errorMessage!,
              suggestions: _errorSuggestions,
            ),
          ],

          const SizedBox(height: 24),
          // Help text explaining what a worktree is
          const _WorktreeHelpCard(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    Key? key,
    bool autofocus = false,
    ValueChanged<String>? onSubmitted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outline),
      ),
      child: TextField(
        key: key,
        controller: controller,
        autofocus: autofocus,
        style: textTheme.bodyMedium,
        onSubmitted: onSubmitted,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// Expandable help card explaining what a git worktree is.
class _WorktreeHelpCard extends StatefulWidget {
  const _WorktreeHelpCard();

  @override
  State<_WorktreeHelpCard> createState() => _WorktreeHelpCardState();
}

class _WorktreeHelpCardState extends State<_WorktreeHelpCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (always visible)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'What is a Git Worktree?',
                      style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_isExpanded) ...[
            Divider(
              height: 1,
              color: colorScheme.primary.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A worktree lets you work on multiple branches simultaneously '
                    'without switching. Each worktree is a separate directory '
                    'with its own branch checked out, sharing the same '
                    'repository history.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This is useful for:',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildBulletPoint(
                    'Working on a feature while keeping main available for '
                    'quick fixes',
                    colorScheme,
                    textTheme,
                  ),
                  _buildBulletPoint(
                    'Reviewing PRs without disrupting your current work',
                    colorScheme,
                    textTheme,
                  ),
                  _buildBulletPoint(
                    'Running tests on one branch while developing on another',
                    colorScheme,
                    textTheme,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBulletPoint(
    String text,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u2022 ',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branch from field with dropdown selection.
class _BranchFromField extends StatelessWidget {
  const _BranchFromField({
    required this.option,
    required this.selectedOtherBranch,
    required this.sortedBranches,
    required this.onOptionChanged,
    required this.onOtherBranchSelected,
  });

  final BranchFromOption option;
  final String? selectedOtherBranch;
  final List<String> sortedBranches;
  final ValueChanged<BranchFromOption> onOptionChanged;
  final ValueChanged<String> onOtherBranchSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // If "other" is selected, show full branch dropdown
    if (option == BranchFromOption.other) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Branch from:',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _buildFullBranchDropdown(context, colorScheme, textTheme),
        ],
      );
    }

    // Show simple main/origin/other dropdown
    return Row(
      children: [
        Text(
          'Branch from',
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        _buildSimpleDropdown(context, colorScheme, textTheme),
      ],
    );
  }

  Widget _buildSimpleDropdown(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<BranchFromOption>(
        key: CreateWorktreePanelKeys.branchFromDropdown,
        value: option,
        underline: const SizedBox.shrink(),
        isDense: true,
        style: textTheme.bodyMedium,
        dropdownColor: colorScheme.surfaceContainerHigh,
        items: const [
          DropdownMenuItem(
            value: BranchFromOption.main,
            child: Text('main'),
          ),
          DropdownMenuItem(
            value: BranchFromOption.originMain,
            child: Text('origin/main'),
          ),
          DropdownMenuItem(
            value: BranchFromOption.other,
            child: Text('other...'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            onOptionChanged(value);
          }
        },
      ),
    );
  }

  Widget _buildFullBranchDropdown(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colorScheme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        key: CreateWorktreePanelKeys.branchFromDropdown,
        value: selectedOtherBranch,
        hint: Text(
          'Select branch...',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        underline: const SizedBox.shrink(),
        isDense: true,
        isExpanded: true,
        style: textTheme.bodyMedium,
        dropdownColor: colorScheme.surfaceContainerHigh,
        items: sortedBranches.map((branch) {
          return DropdownMenuItem(
            value: branch,
            child: Text(branch),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            onOtherBranchSelected(value);
          }
        },
      ),
    );
  }
}


/// Error card showing error message and suggestions.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    this.suggestions,
  });

  final String message;
  final List<String>? suggestions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
          if (suggestions != null && suggestions!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: suggestions!.map((suggestion) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\u2022 ',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            suggestion,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Action bar with Cancel and Create buttons.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isCreating,
    required this.onCancel,
    required this.onCreate,
  });

  final bool isCreating;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CompactButton(
          key: CreateWorktreePanelKeys.cancelButton,
          label: 'Cancel',
          onPressed: isCreating ? null : onCancel,
        ),
        const SizedBox(width: 8),
        Container(
          width: 1,
          height: 20,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        const SizedBox(width: 8),
        _CompactButton(
          key: CreateWorktreePanelKeys.createButton,
          label: isCreating ? 'Creating...' : 'Create',
          onPressed: isCreating ? null : onCreate,
        ),
      ],
    );
  }
}

/// Compact button styled for desktop UI - smaller padding and text.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPressed != null;

    final contentColor = isEnabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final borderColor = isEnabled
        ? colorScheme.outline
        : colorScheme.outlineVariant.withValues(alpha: 0.3);

    Widget button = Opacity(
      opacity: isEnabled ? 1.0 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: contentColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: contentColor,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
