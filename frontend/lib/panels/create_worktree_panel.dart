import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/project_restore_service.dart';
import '../services/worktree_service.dart';
import '../state/selection_state.dart';
import '../widgets/branch_selector_dialog.dart';

/// Keys for testing CreateWorktreePanel widgets.
class CreateWorktreePanelKeys {
  CreateWorktreePanelKeys._();

  static const branchField = Key('create_worktree_branch_field');
  static const rootField = Key('create_worktree_root_field');
  static const createButton = Key('create_worktree_create_button');
  static const cancelButton = Key('create_worktree_cancel_button');
  static const branchFromDropdown = Key('create_worktree_branch_from_dropdown');
  static const folderPickerButton = Key('create_worktree_folder_picker');
  static const recoverYesButton = Key('create_worktree_recover_yes');
  static const recoverNoButton = Key('create_worktree_recover_no');
  static const recoverCard = Key('create_worktree_recover_card');
  static const branchSelectorButton = Key('create_worktree_branch_selector');
  static const existingWorktreeCard = Key('create_worktree_existing_card');
  static const existingOpenButton = Key('create_worktree_existing_open');
  static const existingDeleteButton = Key('create_worktree_existing_delete');
  static const existingCancelButton = Key('create_worktree_existing_cancel');
  static const prunableCard = Key('create_worktree_prunable_card');
  static const prunableYesButton = Key('create_worktree_prunable_yes');
  static const prunableCancelButton = Key('create_worktree_prunable_cancel');
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

  /// When non-null, shows a recovery prompt for this branch name.
  String? _recoverBranchName;

  /// When non-null, shows the "already a worktree" card for this worktree.
  WorktreeInfo? _existingWorktreeConflict;

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
        base: _branchFrom,
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
    } on WorktreeAlreadyExistsException catch (e) {
      if (mounted) {
        setState(() {
          _existingWorktreeConflict = e.existingWorktree;
          _errorMessage = null;
          _errorSuggestions = null;
        });
      }
    } on WorktreeBranchExistsException catch (e) {
      if (mounted) {
        setState(() {
          _recoverBranchName = e.branchName;
          _errorMessage = null;
          _errorSuggestions = null;
        });
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

  void _handleRecoverNo() {
    setState(() {
      _recoverBranchName = null;
    });
  }

  Future<void> _handleRecoverYes() async {
    final branch = _recoverBranchName;
    if (branch == null) return;

    final worktreeRoot = _rootController.text.trim();

    setState(() {
      _isCreating = true;
      _recoverBranchName = null;
      _errorMessage = null;
      _errorSuggestions = null;
    });

    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      // Create the worktree using the existing branch
      final worktreeState = await worktreeService.recoverWorktree(
        project: project,
        branch: branch,
        worktreeRoot: worktreeRoot,
      );

      // Add worktree to project state
      project.addWorktree(worktreeState);

      // Recover archived chats that belonged to this branch
      await _recoverArchivedChats(
        project: project,
        worktreeState: worktreeState,
        branch: branch,
      );

      // Select the new worktree
      if (mounted) {
        final selection = context.read<SelectionState>();
        selection.selectWorktree(worktreeState);
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

  Future<void> _handleBranchSelector() async {
    final selected = await showBranchSelectorDialog(
      context: context,
      branches: _availableBranches,
    );

    if (selected != null && mounted) {
      _branchController.text = selected;
    }
  }

  void _handleExistingWorktreeCancel() {
    setState(() {
      _existingWorktreeConflict = null;
    });
  }

  /// Opens the existing worktree (restores it to app tracking).
  Future<void> _handleExistingWorktreeOpen() async {
    final worktree = _existingWorktreeConflict;
    if (worktree == null) return;

    setState(() {
      _isCreating = true;
      _existingWorktreeConflict = null;
      _errorMessage = null;
      _errorSuggestions = null;
    });

    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      // Restore the existing worktree
      final worktreeState = await worktreeService.restoreExistingWorktree(
        project: project,
        worktreePath: worktree.path,
        branch: worktree.branch ?? 'unknown',
      );

      // Add worktree to project state
      project.addWorktree(worktreeState);

      // Recover archived chats
      await _recoverArchivedChats(
        project: project,
        worktreeState: worktreeState,
        branch: worktree.branch ?? 'unknown',
      );

      // Select the restored worktree
      if (mounted) {
        final selection = context.read<SelectionState>();
        selection.selectWorktree(worktreeState);
        selection.showConversationPanel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to restore worktree: $e';
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

  /// Handles the prunable worktree case: prune stale entries, then recover.
  Future<void> _handlePrunableWorktreeRecreate() async {
    final worktree = _existingWorktreeConflict;
    if (worktree == null) return;

    final worktreeRoot = _rootController.text.trim();

    setState(() {
      _isCreating = true;
      _existingWorktreeConflict = null;
      _errorMessage = null;
      _errorSuggestions = null;
    });

    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();
      final worktreeService = WorktreeService(gitService: gitService);

      // Prune the stale entries first
      await gitService.pruneWorktrees(project.data.repoRoot);

      // Now recover the branch into a new worktree
      final worktreeState = await worktreeService.recoverWorktree(
        project: project,
        branch: worktree.branch!,
        worktreeRoot: worktreeRoot,
      );

      // Add worktree to project state
      project.addWorktree(worktreeState);

      // Recover archived chats
      await _recoverArchivedChats(
        project: project,
        worktreeState: worktreeState,
        branch: worktree.branch!,
      );

      // Select the new worktree
      if (mounted) {
        final selection = context.read<SelectionState>();
        selection.selectWorktree(worktreeState);
        selection.showConversationPanel();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to recreate worktree: $e';
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

  /// Handles deleting the conflicting worktree, then retrying create.
  Future<void> _handleExistingWorktreeDelete() async {
    final worktree = _existingWorktreeConflict;
    if (worktree == null) return;

    // Show a confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Worktree'),
        content: Text(
          'Delete the worktree at ${worktree.path}? '
          'This will remove the directory and then retry creating your worktree.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isCreating = true;
      _existingWorktreeConflict = null;
      _errorMessage = null;
      _errorSuggestions = null;
    });

    try {
      final project = context.read<ProjectState>();
      final gitService = context.read<GitService>();

      // Remove the existing worktree
      await gitService.removeWorktree(
        repoRoot: project.data.repoRoot,
        worktreePath: worktree.path,
        force: true,
      );

      if (mounted) {
        setState(() {
          _isCreating = false;
        });
        // Retry the create
        await _handleCreate();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _errorMessage = 'Failed to delete worktree: $e';
          _errorSuggestions = null;
        });
      }
    }
  }

  /// Recovers archived chats whose original worktree path matches the branch.
  ///
  /// Looks for archived chats whose [originalWorktreePath] ends with
  /// `/cci/{branch}` or exactly matches the worktree path, and restores them
  /// to the new worktree.
  Future<void> _recoverArchivedChats({
    required ProjectState project,
    required WorktreeState worktreeState,
    required String branch,
  }) async {
    final projectRoot = project.data.repoRoot;
    final projectId = PersistenceService.generateProjectId(projectRoot);
    final persistenceService = PersistenceService();
    final restoreService = ProjectRestoreService(persistence: persistenceService);

    final archivedChats = await persistenceService.getArchivedChats(
      projectRoot: projectRoot,
    );

    // Match archived chats whose original worktree path ends with /cci/{branch}
    // or exactly matches the worktree's path
    final suffix = '/cci/$branch';
    final worktreePath = worktreeState.data.worktreeRoot;
    final matchingChats = archivedChats
        .where((chat) =>
            chat.originalWorktreePath.endsWith(suffix) ||
            chat.originalWorktreePath == worktreePath)
        .toList();

    for (final archivedRef in matchingChats) {
      final chatState = await restoreService.restoreArchivedChat(
        archivedRef,
        worktreeState.data.worktreeRoot,
        projectId,
        projectRoot,
      );
      worktreeState.addChat(chatState);
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
        }
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 28,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Create Worktree',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a new worktree to work on a different branch without '
                  'switching. Each worktree has its own working directory.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // Branch/worktree name
                _buildLabel('Branch name', textTheme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _branchController,
                        key: CreateWorktreePanelKeys.branchField,
                        autofocus: true,
                        hintText: 'e.g. feature/new-login, bugfix/header-alignment',
                        onSubmitted: (_) => _handleCreate(),
                      ),
                    ),
                    if (_availableBranches.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _IconButton(
                        key: CreateWorktreePanelKeys.branchSelectorButton,
                        icon: Icons.list_alt,
                        onPressed: _handleBranchSelector,
                        tooltip: 'Select existing branch',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'This will be both the branch name and the worktree folder name.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

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
                const SizedBox(height: 20),

                // Worktree base directory
                _buildLabel('Worktree location', textTheme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _rootController,
                        key: CreateWorktreePanelKeys.rootField,
                        hintText: 'Directory where worktrees are stored',
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconButton(
                      key: CreateWorktreePanelKeys.folderPickerButton,
                      icon: Icons.folder_open_outlined,
                      onPressed: _pickFolder,
                      tooltip: 'Browse for folder',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'The new worktree will be created inside this directory.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                // Existing worktree conflict card
                if (_existingWorktreeConflict != null) ...[
                  const SizedBox(height: 20),
                  if (_existingWorktreeConflict!.isPrunable)
                    _PrunableWorktreeCard(
                      worktree: _existingWorktreeConflict!,
                      isCreating: _isCreating,
                      onYes: _handlePrunableWorktreeRecreate,
                      onCancel: _handleExistingWorktreeCancel,
                    )
                  else
                    _ExistingWorktreeCard(
                      worktree: _existingWorktreeConflict!,
                      isCreating: _isCreating,
                      onOpen: _handleExistingWorktreeOpen,
                      onDelete: _handleExistingWorktreeDelete,
                      onCancel: _handleExistingWorktreeCancel,
                    ),
                ],

                // Recovery prompt when branch already exists
                if (_recoverBranchName != null) ...[
                  const SizedBox(height: 20),
                  _RecoverBranchCard(
                    branchName: _recoverBranchName!,
                    isCreating: _isCreating,
                    onYes: _handleRecoverYes,
                    onNo: _handleRecoverNo,
                  ),
                ],

                // Error card if error
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ErrorCard(
                    message: _errorMessage!,
                    suggestions: _errorSuggestions,
                  ),
                ],

                const SizedBox(height: 32),

                // Action buttons (hidden when recovery/conflict prompts show)
                if (_recoverBranchName == null && _existingWorktreeConflict == null)
                  _ActionBar(
                    isCreating: _isCreating,
                    onCancel: _handleCancel,
                    onCreate: _handleCreate,
                  ),

                const SizedBox(height: 32),
                // Help text explaining what a worktree is
                const _WorktreeHelpCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, TextTheme textTheme) {
    return Text(
      text,
      style: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    Key? key,
    bool autofocus = false,
    String? hintText,
    ValueChanged<String>? onSubmitted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      child: TextField(
        key: key,
        controller: controller,
        autofocus: autofocus,
        style: textTheme.bodyMedium,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
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

/// Card prompting the user to recover an existing branch into a worktree.
class _RecoverBranchCard extends StatelessWidget {
  const _RecoverBranchCard({
    required this.branchName,
    required this.isCreating,
    required this.onYes,
    required this.onNo,
  });

  final String branchName;
  final bool isCreating;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: CreateWorktreePanelKeys.recoverCard,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.help_outline,
                size: 18,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A branch named "$branchName" already exists. '
                  'Do you want to recover that branch into a worktree?',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton(
                key: CreateWorktreePanelKeys.recoverNoButton,
                onPressed: isCreating ? null : onNo,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  side: BorderSide(color: colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'No',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: CreateWorktreePanelKeys.recoverYesButton,
                onPressed: isCreating ? null : onYes,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isCreating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Yes, Recover',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card shown when the branch is already checked out in a valid worktree.
///
/// Offers: [Open] the existing worktree, [Delete] it, or [Cancel].
class _ExistingWorktreeCard extends StatelessWidget {
  const _ExistingWorktreeCard({
    required this.worktree,
    required this.isCreating,
    required this.onOpen,
    required this.onDelete,
    required this.onCancel,
  });

  final WorktreeInfo worktree;
  final bool isCreating;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: CreateWorktreePanelKeys.existingWorktreeCard,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${worktree.branch}" branch exists on worktree at '
                  '${worktree.path}. Open it there?',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton(
                key: CreateWorktreePanelKeys.existingDeleteButton,
                onPressed: isCreating ? null : onDelete,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  side: BorderSide(color: colorScheme.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Delete',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                key: CreateWorktreePanelKeys.existingCancelButton,
                onPressed: isCreating ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  side: BorderSide(color: colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: CreateWorktreePanelKeys.existingOpenButton,
                onPressed: isCreating ? null : onOpen,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isCreating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Yes',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card shown when the branch is recorded as a worktree but the directory
/// doesn't exist on disk (prunable).
class _PrunableWorktreeCard extends StatelessWidget {
  const _PrunableWorktreeCard({
    required this.worktree,
    required this.isCreating,
    required this.onYes,
    required this.onCancel,
  });

  final WorktreeInfo worktree;
  final bool isCreating;
  final VoidCallback onYes;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: CreateWorktreePanelKeys.prunableCard,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber,
                size: 18,
                color: colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${worktree.branch}" is recorded as a worktree at '
                  '${worktree.path}, but that doesn\'t exist. '
                  'Prune and recreate?',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton(
                key: CreateWorktreePanelKeys.prunableCancelButton,
                onPressed: isCreating ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  side: BorderSide(color: colorScheme.outline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: CreateWorktreePanelKeys.prunableYesButton,
                onPressed: isCreating ? null : onYes,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isCreating
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Yes',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
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
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        // Cancel button - outlined style
        OutlinedButton(
          key: CreateWorktreePanelKeys.cancelButton,
          onPressed: isCreating ? null : onCancel,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close,
                size: 18,
                color: isCreating
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Cancel',
                style: textTheme.labelLarge?.copyWith(
                  color: isCreating
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Create button - filled primary style
        FilledButton(
          key: CreateWorktreePanelKeys.createButton,
          onPressed: isCreating ? null : onCreate,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            backgroundColor: colorScheme.primary,
            disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCreating)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              else
                Icon(
                  Icons.add,
                  size: 18,
                  color: colorScheme.onPrimary,
                ),
              const SizedBox(width: 8),
              Text(
                isCreating ? 'Creating...' : 'Create Worktree',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Icon button for folder picker.
class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget button = Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colorScheme.onSurfaceVariant,
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
