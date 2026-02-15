import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import '../services/ask_ai_service.dart';
import '../services/file_system_service.dart';
import '../services/git_operations_service.dart';
import '../services/git_service.dart';
import '../services/log_service.dart';
import '../services/persistence_service.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/base_selector_dialog.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/conflict_resolution_dialog.dart';
import '../widgets/create_pr_dialog.dart';
import '../widgets/insights_widgets.dart';
import 'information_panel_widgets.dart';
import 'panel_wrapper.dart';

// Re-export so existing importers (tests) still find InformationPanelKeys.
export 'information_panel_widgets.dart' show InformationPanelKeys;

/// Information panel - shows git branch/status info for the selected worktree.
class InformationPanel extends StatelessWidget {
  const InformationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    // Show branch name in header, or fallback to "Information"
    final title = worktree?.data.branch ?? 'Information';

    return PanelWrapper(
      title: title,
      icon: Icons.call_split,
      trailing: worktree != null
          ? _RefreshButton(key: InformationPanelKeys.refreshButton)
          : null,
      child: const _InformationContent(),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({super.key});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final watcher = context.read<WorktreeWatcherService>();
      await watcher.forceFetchAndRefreshAll();
    } catch (_) {
      // Provider not available (e.g., in tests)
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Fetch and refresh git status',
      child: InkWell(
        onTap: _refreshing ? null : _handleRefresh,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: _refreshing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

class _InformationContent extends StatelessWidget {
  const _InformationContent();

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) {
      return const _NoWorktreeSelected();
    }

    return ListenableBuilder(
      listenable: worktree,
      builder: (context, _) => _WorktreeInfo(
        worktree: worktree,
        onStatusChanged: () {
          // Force an immediate refresh of the git status
          try {
            final watcher =
                context.read<WorktreeWatcherService>();
            watcher.forceRefresh(worktree);
          } catch (_) {
            // Provider not available (e.g., in tests)
          }
        },
      ),
    );
  }
}

class _NoWorktreeSelected extends StatelessWidget {
  const _NoWorktreeSelected();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Select a worktree to view information',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WorktreeInfo extends StatefulWidget {
  const _WorktreeInfo({
    required this.worktree,
    required this.onStatusChanged,
  });

  final WorktreeState worktree;
  final VoidCallback onStatusChanged;

  @override
  State<_WorktreeInfo> createState() => _WorktreeInfoState();
}

class _WorktreeInfoState extends State<_WorktreeInfo> {
  bool _loading = false;

  WorktreeState get worktree => widget.worktree;
  VoidCallback get onStatusChanged => widget.onStatusChanged;
  WorktreeData get data => worktree.data;
  String get worktreeRoot => data.worktreeRoot;

  /// Runs [action] while showing a loading overlay on the panel.
  Future<void> _withLoading(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Dialog-based handlers (remain on widget - need BuildContext for dialogs)
  // ---------------------------------------------------------------------------

  Future<void> _showCommitDialog(BuildContext context) async {
    LogService.instance.info('InfoPanel', 'Stage & Commit: ${data.branch}');
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final fileSystemService = context.read<FileSystemService>();

    final committed = await showCommitDialog(
      context: context,
      worktreePath: worktreeRoot,
      gitService: gitService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
    );

    if (committed) {
      onStatusChanged();
    }
  }

  Future<void> _handleUpdateFromBase(
    BuildContext context,
    MergeOperationType operation,
  ) async {
    LogService.instance.info('InfoPanel', '${operation.name} from base: ${data.branch}');
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();
    final baseRef = data.baseRef ?? 'main';

    if (!context.mounted) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: baseRef,
      operation: operation,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final gitOps = context.read<GitOperationsService>();
      final selection = context.read<SelectionState>();
      await gitOps.openConflictManagerChat(
        worktree: worktree,
        project: project,
        selection: selection,
        branch: data.branch,
        mainBranch: baseRef,
        worktreePath: worktreeRoot,
        mainWorktreePath: project.primaryWorktree.data.worktreeRoot,
        operation: operation,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleMergeIntoMain(BuildContext context) async {
    LogService.instance.info('InfoPanel', 'Merge into main: ${data.branch}');
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    String? mainBranch;
    try {
      mainBranch = await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Failed to detect main branch: $e');
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Could not detect main branch');
      return;
    }

    if (!context.mounted) return;

    final primaryWorktreePath = project.primaryWorktree.data.worktreeRoot;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: primaryWorktreePath,
      branch: mainBranch,
      mainBranch: data.branch,
      operation: MergeOperationType.merge,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final gitOps = context.read<GitOperationsService>();
      final selection = context.read<SelectionState>();
      await gitOps.openConflictManagerChat(
        worktree: worktree,
        project: project,
        selection: selection,
        branch: mainBranch,
        mainBranch: data.branch,
        worktreePath: primaryWorktreePath,
        mainWorktreePath: primaryWorktreePath,
        operation: MergeOperationType.merge,
      );
    }

    onStatusChanged();
  }

  Future<void> _handlePush(
    BuildContext context, {
    bool setUpstream = false,
  }) async {
    LogService.instance.info('InfoPanel', 'Push: ${data.branch}${setUpstream ? ' (set upstream)' : ''}');
    final gitOps = context.read<GitOperationsService>();
    final result = await gitOps.push(worktreeRoot, setUpstream: setUpstream);
    if (!result.success && context.mounted) {
      showErrorSnackBar(context, result.errorMessage!);
    }
    onStatusChanged();
  }

  Future<void> _handlePullRebase(BuildContext context) async {
    final project = context.read<ProjectState>();
    if (data.isPrimary &&
        !data.isRemoteBase &&
        project.linkedWorktrees.isNotEmpty) {
      final choice = await showDialog<PullRebaseChoice>(
        context: context,
        builder: (context) => const PullRebaseWarningDialog(),
      );
      if (choice == null || !context.mounted) return;
      if (choice == PullRebaseChoice.merge) {
        return _handlePullMerge(context);
      }
    }

    LogService.instance.info('InfoPanel', 'Pull rebase: ${data.branch}');
    final gitService = context.read<GitService>();

    final upstream = data.upstreamBranch;
    if (upstream == null) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: upstream,
      operation: MergeOperationType.rebase,
      gitService: gitService,
      fetchFirst: true,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final gitOps = context.read<GitOperationsService>();
      final selection = context.read<SelectionState>();
      await gitOps.openConflictManagerChat(
        worktree: worktree,
        project: project,
        selection: selection,
        branch: data.branch,
        mainBranch: upstream,
        worktreePath: worktreeRoot,
        mainWorktreePath: project.primaryWorktree.data.worktreeRoot,
        operation: MergeOperationType.rebase,
      );
    }

    onStatusChanged();
  }

  Future<void> _handlePullMerge(BuildContext context) async {
    LogService.instance.info('InfoPanel', 'Pull merge: ${data.branch}');
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    final upstream = data.upstreamBranch;
    if (upstream == null) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: upstream,
      operation: MergeOperationType.merge,
      gitService: gitService,
      fetchFirst: true,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final gitOps = context.read<GitOperationsService>();
      final selection = context.read<SelectionState>();
      await gitOps.openConflictManagerChat(
        worktree: worktree,
        project: project,
        selection: selection,
        branch: data.branch,
        mainBranch: upstream,
        worktreePath: worktreeRoot,
        mainWorktreePath: project.primaryWorktree.data.worktreeRoot,
        operation: MergeOperationType.merge,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleCreatePr(BuildContext context) async {
    LogService.instance.info('InfoPanel', 'Create PR: ${data.branch}');
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final project = context.read<ProjectState>();

    final ghInstalled = await gitService.isGhInstalled();
    if (!ghInstalled) {
      if (!context.mounted) return;
      showErrorSnackBar(
        context,
        'GitHub CLI (gh) is not installed. '
        'Install it from https://cli.github.com',
      );
      return;
    }

    String? mainBranch;
    try {
      mainBranch = await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Failed to detect main branch: $e');
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      showErrorSnackBar(context, 'Could not detect main branch');
      return;
    }

    if (!context.mounted) return;

    final created = await showCreatePrDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: mainBranch,
      gitService: gitService,
      askAiService: askAiService,
    );

    if (created) {
      onStatusChanged();
    }
  }

  Future<void> _handleChangeBase(BuildContext context) async {
    final previousValue = worktree.base;
    final result = await showBaseSelectorDialog(
      context,
      currentBase: previousValue,
      branchName: data.branch,
    );

    if (!context.mounted) return;
    if (result == null) return;

    final newBase = result.base;
    if (newBase == previousValue) return;

    LogService.instance.notice('Worktree', 'Base changed: ${data.branch} ${previousValue ?? "none"} -> $newBase');
    worktree.setBase(newBase);

    try {
      final project = context.read<ProjectState>();
      final persistence = context.read<PersistenceService>();
      await persistence.updateWorktreeBase(
        projectRoot: project.data.repoRoot,
        worktreePath: worktreeRoot,
        base: newBase,
      );
    } catch (e, stack) {
      LogService.instance.logUnhandledException(e, stack);
      worktree.setBase(previousValue);
      if (context.mounted) {
        showErrorSnackBar(context, 'Failed to update base branch. Please try again.');
      }
      return;
    }

    onStatusChanged();

    if (result.rebase && context.mounted) {
      LogService.instance.info('InfoPanel', 'Rebase onto new base: ${data.branch} -> $newBase');
      final gitService = context.read<GitService>();

      final conflictResult = await showConflictResolutionDialog(
        context: context,
        worktreePath: worktreeRoot,
        branch: data.branch,
        mainBranch: newBase,
        operation: MergeOperationType.rebase,
        gitService: gitService,
        oldBase: previousValue ?? 'main',
      );

      if (!context.mounted) return;

      if (conflictResult == ConflictResolutionResult.resolveWithClaude) {
        final project = context.read<ProjectState>();
        final gitOps = context.read<GitOperationsService>();
        final selection = context.read<SelectionState>();
        await gitOps.openConflictManagerChat(
          worktree: worktree,
          project: project,
          selection: selection,
          branch: data.branch,
          mainBranch: newBase,
          worktreePath: worktreeRoot,
          mainWorktreePath: project.primaryWorktree.data.worktreeRoot,
          operation: MergeOperationType.rebase,
        );
      }

      onStatusChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Service-delegated handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleAbortConflict(BuildContext context) async {
    final gitOps = context.read<GitOperationsService>();
    final result = await gitOps.abortConflict(worktreeRoot, data.conflictOperation);
    if (!result.success && context.mounted) {
      showErrorSnackBar(context, result.errorMessage!);
    }
    onStatusChanged();
  }

  Future<void> _handleContinueConflict(BuildContext context) async {
    final gitOps = context.read<GitOperationsService>();
    final result = await gitOps.continueConflict(worktreeRoot, data.conflictOperation);
    if (!result.success && context.mounted) {
      showErrorSnackBar(context, result.errorMessage!);
    }
    onStatusChanged();
  }

  Future<void> _handleAskClaudeConflict(BuildContext context) async {
    final gitOps = context.read<GitOperationsService>();
    final project = context.read<ProjectState>();
    final selection = context.read<SelectionState>();
    await gitOps.askClaudeForConflict(
      project: project,
      selection: selection,
      worktree: worktree,
      data: data,
    );
  }

  // ---------------------------------------------------------------------------
  // Enable/disable logic
  // ---------------------------------------------------------------------------

  bool get _canUpdateFromBase =>
      data.isRemoteBase || data.commitsBehindMain > 0;

  bool get _canMergeIntoMain =>
      data.commitsAheadOfMain > 0 &&
      data.commitsBehindMain == 0 &&
      !data.isPrimary;

  bool get _canPush =>
      data.upstreamBranch != null && data.commitsAhead > 0;

  bool get _canCreatePr =>
      data.commitsAheadOfMain > 0 &&
      data.upstreamBranch != null &&
      !data.isPrimary;

  @override
  Widget build(BuildContext context) {
    final baseRef = data.baseRef ?? 'main';

    return Stack(
      children: [
        SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A. Working Tree section (status counts, no label)
              InfoStatusCounts(data: data),
              const SizedBox(height: 8),
              InfoCompactButton(
                key: InformationPanelKeys.commitButton,
                onPressed: data.uncommittedFiles > 0 ||
                        data.stagedFiles > 0
                    ? () => _showCommitDialog(context)
                    : null,
                label: 'Stage and commit all',
                icon: Icons.check_circle_outline,
                tooltip: data.uncommittedFiles == 0 &&
                        data.stagedFiles == 0
                    ? 'No uncommitted files'
                    : null,
              ),

              // B. Base section (non-primary only)
              if (!data.isPrimary) ...[
                const SizedBox(height: 16),
                InfoBaseSection(
                  key: InformationPanelKeys.baseSection,
                  data: data,
                  baseRef: baseRef,
                  onChangeBase: () => _handleChangeBase(context),
                ),
              ],

              // C. Upstream section (non-primary only)
              if (!data.isPrimary) ...[
                const SizedBox(height: 16),
                InfoUpstreamSection(
                  key: InformationPanelKeys.upstreamSection,
                  data: data,
                ),
              ],

              // D. Primary worktree upstream sync (Push/Pull only)
              if (data.isPrimary && data.upstreamBranch != null) ...[
                const SizedBox(height: 16),
                InfoPrimaryUpstreamSection(
                  data: data,
                  canPush: _canPush,
                  onPush: () => _withLoading(
                    () => _handlePush(context),
                  ),
                  onPullMerge: () => _withLoading(
                    () => _handlePullMerge(context),
                  ),
                  onPullRebase: () => _withLoading(
                    () => _handlePullRebase(context),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // E/F. Actions or Conflict section
              if (data.hasMergeConflict ||
                  data.conflictOperation != null) ...[
                InfoConflictInProgress(
                  data: data,
                  onAbort: () => _withLoading(
                    () => _handleAbortConflict(context),
                  ),
                  onAskClaude: () => _withLoading(
                    () => _handleAskClaudeConflict(context),
                  ),
                  onContinue: () => _withLoading(
                    () => _handleContinueConflict(context),
                  ),
                ),
              ] else if (!data.isPrimary) ...[
                InfoActionsSection(
                  data: data,
                  baseRef: baseRef,
                  canUpdateFromBase: _canUpdateFromBase,
                  canMergeIntoMain: _canMergeIntoMain,
                  canPush: _canPush,
                  canCreatePr: _canCreatePr,
                  onRebaseOntoBase: () => _withLoading(
                    () => _handleUpdateFromBase(
                      context,
                      MergeOperationType.rebase,
                    ),
                  ),
                  onMergeBase: () => _withLoading(
                    () => _handleUpdateFromBase(
                      context,
                      MergeOperationType.merge,
                    ),
                  ),
                  onMergeIntoMain: () => _withLoading(
                    () => _handleMergeIntoMain(context),
                  ),
                  onPush: () => _withLoading(
                    () => _handlePush(
                      context,
                      setUpstream: data.upstreamBranch == null,
                    ),
                  ),
                  onPullMerge: () => _withLoading(
                    () => _handlePullMerge(context),
                  ),
                  onPullRebase: () => _withLoading(
                    () => _handlePullRebase(context),
                  ),
                  onCreatePr: () => _withLoading(
                    () => _handleCreatePr(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context)
                  .colorScheme
                  .surface
                  .withValues(alpha: 0.6),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
