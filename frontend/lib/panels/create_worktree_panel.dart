import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/worktree_service.dart';
import '../state/selection_state.dart';

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

class _CreateWorktreePanelState extends State<CreateWorktreePanel> {
  final _branchController = TextEditingController();
  final _rootController = TextEditingController();

  bool _isCreating = false;
  bool _isLoading = true;
  String? _errorMessage;
  List<String>? _errorSuggestions;
  List<String> _availableBranches = [];
  List<String> _existingWorktreeBranches = [];

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Help text explaining what a worktree is
        const _WorktreeHelpCard(),
        // Form fields
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branch name field with autocomplete
                _BranchNameField(
                  controller: _branchController,
                  availableBranches: _availableBranches,
                  existingWorktreeBranches: _existingWorktreeBranches,
                ),
                const SizedBox(height: 16),
                // Worktree root directory
                _WorktreeRootField(controller: _rootController),
                const SizedBox(height: 8),
                // Note about directory location
                const _DirectoryNote(),
                const SizedBox(height: 8),
                // Preview of full path
                _PathPreview(
                  root: _rootController.text,
                  branch: _branchController.text,
                ),
                // Error card if error
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _ErrorCard(
                    message: _errorMessage!,
                    suggestions: _errorSuggestions,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Action buttons
        _ActionBar(
          isCreating: _isCreating,
          onCancel: _handleCancel,
          onCreate: _handleCreate,
        ),
      ],
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
      margin: const EdgeInsets.all(16),
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
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'What is a Git Worktree?',
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A worktree lets you work on multiple branches simultaneously '
                    'without switching. Each worktree is a separate directory '
                    'with its own branch checked out, sharing the same '
                    'repository history.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This is useful for:',
                    style: textTheme.bodyMedium?.copyWith(
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
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u2022 ',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branch name text field with autocomplete.
class _BranchNameField extends StatelessWidget {
  const _BranchNameField({
    required this.controller,
    required this.availableBranches,
    required this.existingWorktreeBranches,
  });

  final TextEditingController controller;
  final List<String> availableBranches;
  final List<String> existingWorktreeBranches;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Branch Name',
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            if (query.isEmpty) {
              return availableBranches.take(10);
            }
            return availableBranches.where(
              (branch) => branch.toLowerCase().contains(query),
            );
          },
          onSelected: (String selection) {
            controller.text = selection;
          },
          fieldViewBuilder: (
            context,
            textEditingController,
            focusNode,
            onFieldSubmitted,
          ) {
            // Sync with our controller
            textEditingController.text = controller.text;
            textEditingController.addListener(() {
              controller.text = textEditingController.text;
            });

            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'Enter branch name or select from existing',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.call_split,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              onSubmitted: (_) => onFieldSubmitted(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(option),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        if (existingWorktreeBranches.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Branches already in worktrees: '
            '${existingWorktreeBranches.join(", ")}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Worktree root directory text field.
class _WorktreeRootField extends StatelessWidget {
  const _WorktreeRootField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Worktree Root Directory',
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'Enter directory path',
            border: const OutlineInputBorder(),
            prefixIcon: Icon(
              Icons.folder_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Warning note about directory location.
class _DirectoryNote extends StatelessWidget {
  const _DirectoryNote();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(
          Icons.warning_amber_outlined,
          size: 16,
          color: colorScheme.error.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'This directory must be outside the project repository',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.error.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the computed full path for the worktree.
class _PathPreview extends StatelessWidget {
  const _PathPreview({
    required this.root,
    required this.branch,
  });

  final String root;
  final String branch;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (root.isEmpty || branch.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sanitize branch for path preview (basic sanitization)
    final sanitizedBranch = branch
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[^\w\-/]'), '');

    if (sanitizedBranch.isEmpty) {
      return const SizedBox.shrink();
    }

    final fullPath = path.join(root, 'cci', sanitizedBranch);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Full path:',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fullPath,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrains Mono',
                    color: colorScheme.onSurface,
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
      padding: const EdgeInsets.all(12),
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
                size: 18,
                color: colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          if (suggestions != null && suggestions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: suggestions!.map((suggestion) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
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
            onPressed: isCreating ? null : onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isCreating ? null : onCreate,
            icon: isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.add, size: 18),
            label: Text(isCreating ? 'Creating...' : 'Create Worktree'),
          ),
        ],
      ),
    );
  }
}
