import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/ask_ai_service.dart';
import '../services/backend_service.dart';
import '../services/file_system_service.dart';
import '../services/git_service.dart';
import '../services/project_restore_service.dart';
import '../services/sdk_message_handler.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/conflict_resolution_dialog.dart';
import '../widgets/create_pr_dialog.dart';
import 'panel_wrapper.dart';

/// Workflow mode for how branches integrate with main.
enum WorkflowMode { local, pr }

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
      child: const _InformationContent(),
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
        data: worktree.data,
        worktreeRoot: worktree.data.worktreeRoot,
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
    required this.data,
    required this.worktreeRoot,
    required this.onStatusChanged,
  });

  final WorktreeData data;
  final String worktreeRoot;
  final VoidCallback onStatusChanged;

  @override
  State<_WorktreeInfo> createState() => _WorktreeInfoState();
}

class _WorktreeInfoState extends State<_WorktreeInfo> {
  WorkflowMode _workflowMode = WorkflowMode.local;
  String _updateSource = 'main';

  WorktreeData get data => widget.data;
  String get worktreeRoot => widget.worktreeRoot;
  VoidCallback get onStatusChanged => widget.onStatusChanged;

  Future<void> _showCommitDialog(BuildContext context) async {
    // Get services from providers
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

  Future<void> _handleUpdateFromMain(
    BuildContext context,
    MergeOperationType operation,
  ) async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    // In PR mode, fetch from origin first
    if (_workflowMode == WorkflowMode.pr) {
      try {
        await gitService.fetch(worktreeRoot);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch from origin: $e')),
        );
        return;
      }
    }

    // Detect main branch
    String? mainBranch;
    try {
      mainBranch =
          await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to detect main branch: $e')),
      );
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not detect main branch')),
      );
      return;
    }

    // In PR mode, rebase/merge against origin/main
    final targetBranch = _workflowMode == WorkflowMode.pr
        ? 'origin/$mainBranch'
        : mainBranch;

    if (!context.mounted) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: targetBranch,
      operation: operation,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final mainWorktreePath =
          project.primaryWorktree.data.worktreeRoot;

      await _openConflictManagerChat(
        context,
        branch: data.branch,
        mainBranch: mainBranch,
        worktreePath: worktreeRoot,
        mainWorktreePath: mainWorktreePath,
        operation: operation,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleMergeIntoMain(BuildContext context) async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    // Detect main branch
    String? mainBranch;
    try {
      mainBranch =
          await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to detect main branch: $e')),
      );
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect main branch')),
      );
      return;
    }

    if (!context.mounted) return;

    // Merge the current branch into main, running in the primary
    // worktree directory (since we can't checkout main in a worktree
    // where another branch is checked out).
    final primaryWorktreePath =
        project.primaryWorktree.data.worktreeRoot;

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
      await _openConflictManagerChat(
        context,
        branch: mainBranch,
        mainBranch: data.branch,
        worktreePath: primaryWorktreePath,
        mainWorktreePath: primaryWorktreePath,
        operation: MergeOperationType.merge,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleCreatePr(BuildContext context) async {
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final project = context.read<ProjectState>();

    // Check gh is installed
    final ghInstalled = await gitService.isGhInstalled();
    if (!ghInstalled) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GitHub CLI (gh) is not installed. '
            'Install it from https://cli.github.com',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // Detect main branch
    String? mainBranch;
    try {
      mainBranch =
          await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to detect main branch: $e')),
      );
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect main branch')),
      );
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

  Future<void> _openConflictManagerChat(
    BuildContext context, {
    required String branch,
    required String mainBranch,
    required String worktreePath,
    required String mainWorktreePath,
    required MergeOperationType operation,
  }) async {
    final selection = context.read<SelectionState>();
    final project = context.read<ProjectState>();
    final backend = context.read<BackendService>();
    final messageHandler = context.read<SdkMessageHandler>();
    final restoreService = context.read<ProjectRestoreService>();
    final worktree = selection.selectedWorktree;
    if (worktree == null) return;

    final operationName =
        operation == MergeOperationType.rebase ? 'rebasing' : 'merging';

    // Build the preamble (sent to Claude but NOT shown in UI)
    final preamble = 'The user is $operationName this child branch '
        '($branch) onto its parent ($mainBranch), and has '
        'encountered a number of merge conflicts. You are to resolve '
        'the conflicts where the solution is obvious go ahead. If '
        'the conflict is not obvious or you may break something STOP '
        'and advise the user.\n'
        'Rules:\n'
        '- Do NOT use origin, only local.\n'
        '- This branch is $branch: $worktreePath\n'
        '- Parent is $mainBranch: $mainWorktreePath\n'
        '- Do NOT do destructive edits\n'
        '- Always ask the user if it is a complicated conflict '
        'resolution.\n\n'
        'Now analyse the conflict and begin work resolving it.';

    // Create the chat
    final chatName = 'Conflict: $operationName $branch '
        'onto $mainBranch';
    final chatData = ChatData.create(
      name: chatName,
      worktreeRoot: worktreePath,
      isAutoGeneratedName: false,
    );
    final chat = ChatState(chatData);

    // Add to worktree and select it
    worktree.addChat(chat, select: true);
    selection.selectChat(chat);

    // Persist the new chat (fire-and-forget)
    restoreService
        .addChatToWorktree(
          project.data.repoRoot,
          worktree.data.worktreeRoot,
          chat,
        )
        .catchError((error) {
      developer.log(
        'Failed to persist conflict chat: $error',
        name: 'InformationPanel',
        level: 900,
      );
    });

    // Start the session with the preamble as the prompt.
    // We do NOT add a UserInputEntry so the preamble is invisible.
    try {
      await chat.startSession(
        backend: backend,
        messageHandler: messageHandler,
        prompt: preamble,
      );
    } catch (e) {
      chat.addEntry(TextOutputEntry(
        timestamp: DateTime.now(),
        text: 'Failed to start conflict resolution session: $e',
        contentType: 'error',
      ));
    }
  }

  Future<void> _handleAbortConflict(BuildContext context) async {
    final gitService = context.read<GitService>();
    final operation = data.conflictOperation;
    try {
      if (operation == MergeOperationType.rebase) {
        await gitService.rebaseAbort(worktreeRoot);
      } else {
        await gitService.mergeAbort(worktreeRoot);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to abort: $e')),
      );
    }
    onStatusChanged();
  }

  Future<void> _handleContinueConflict(
    BuildContext context,
  ) async {
    final gitService = context.read<GitService>();
    final operation = data.conflictOperation;
    try {
      if (operation == MergeOperationType.rebase) {
        await gitService.rebaseContinue(worktreeRoot);
      } else {
        await gitService.mergeContinue(worktreeRoot);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to continue: $e')),
      );
    }
    onStatusChanged();
  }

  Future<void> _handleAskClaudeConflict(
    BuildContext context,
  ) async {
    final project = context.read<ProjectState>();
    final mainBranch = await context
        .read<GitService>()
        .getMainBranch(project.data.repoRoot);
    if (!context.mounted) return;

    final operation = data.conflictOperation ?? MergeOperationType.merge;
    final mainWorktreePath =
        project.primaryWorktree.data.worktreeRoot;

    await _openConflictManagerChat(
      context,
      branch: data.branch,
      mainBranch: mainBranch ?? 'main',
      worktreePath: worktreeRoot,
      mainWorktreePath: mainWorktreePath,
      operation: operation,
    );
  }

  /// Whether the update-from-main buttons should be enabled.
  bool get _canUpdateFromMain =>
      data.commitsBehindMain > 0 && !data.isPrimary;

  /// Whether the merge-into-main button should be enabled.
  /// Enabled when ahead of main and not behind (safe fast-forward merge).
  bool get _canMergeIntoMain =>
      data.commitsAheadOfMain > 0 &&
      data.commitsBehindMain == 0 &&
      !data.isPrimary;

  /// Tooltip for the merge-into-main button when disabled.
  String? get _mergeIntoMainTooltip {
    if (data.isPrimary) return 'Cannot merge primary worktree';
    if (data.commitsAheadOfMain == 0) return 'No commits to merge';
    if (data.commitsBehindMain > 0) {
      return 'Update this branch with the latest from main '
          'before merging it back in';
    }
    return null;
  }

  /// Whether the create-PR button should be enabled.
  bool get _canCreatePr =>
      data.commitsAheadOfMain > 0 && !data.isPrimary;

  /// Tooltip for the create-PR button when disabled.
  String? get _createPrTooltip {
    if (data.isPrimary) {
      return 'Cannot create PR from primary worktree';
    }
    if (data.commitsAheadOfMain == 0) return 'No commits to push';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status counts
          _StatusCounts(data: data),
          const SizedBox(height: 8),

          // Ahead/behind main
          _DivergenceInfo(data: data),
          const SizedBox(height: 16),

          // Stage and commit button (enabled when there are changes)
          _CompactButton(
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
          // Workflow mode toggle (only for non-primary worktrees)
          if (!data.isPrimary) ...[
            const SizedBox(height: 12),
            _CompactToggle<WorkflowMode>(
              value: _workflowMode,
              options: const [
                (WorkflowMode.local, 'Local', Icons.computer),
                (WorkflowMode.pr, 'PRs', Icons.cloud_upload),
              ],
              onChanged: (v) => setState(() => _workflowMode = v),
            ),
          ],
          const SizedBox(height: 12),

          if (data.hasMergeConflict ||
              data.conflictOperation != null) ...[
            // Conflict/operation in progress section
            _ConflictInProgress(
              data: data,
              onAbort: () => _handleAbortConflict(context),
              onAskClaude: () =>
                  _handleAskClaudeConflict(context),
              onContinue: () =>
                  _handleContinueConflict(context),
            ),
          ] else ...[
            // Update from main section
            _SectionDividerWithDropdown(
              prefix: 'Update from ',
              value: _updateSource,
              options: const ['main', 'origin/main'],
              tooltips: const {
                'main':
                    'Use changes from the local main branch.\n'
                    'Use this when working locally and not\n'
                    'in a GitHub Pull Request setup.',
                'origin/main':
                    'Use changes from the remote (origin)\n'
                        'main branch. Use this when using\n'
                        'GitHub to manage your merges.',
              },
              onChanged: (v) =>
                  setState(() => _updateSource = v),
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _CompactButton(
                    onPressed: _canUpdateFromMain
                        ? () => _handleUpdateFromMain(
                              context,
                              MergeOperationType.rebase,
                            )
                        : null,
                    label: 'Rebase',
                    icon: Icons.low_priority,
                    tooltip: _canUpdateFromMain
                        ? null
                        : 'Already up-to-date with main',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CompactButton(
                    onPressed: _canUpdateFromMain
                        ? () => _handleUpdateFromMain(
                              context,
                              MergeOperationType.merge,
                            )
                        : null,
                    label: 'Merge',
                    icon: Icons.merge,
                    tooltip: _canUpdateFromMain
                        ? null
                        : 'Already up-to-date with main',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Integrate section - changes based on workflow mode
            if (_workflowMode == WorkflowMode.local) ...[
              _SectionDivider(
                label: 'Integrate into main',
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 6),
              _CompactButton(
                onPressed: _canMergeIntoMain
                    ? () => _handleMergeIntoMain(context)
                    : null,
                label: 'Merge',
                icon: Icons.merge,
                tooltip: _canMergeIntoMain
                    ? null
                    : _mergeIntoMainTooltip,
              ),
            ] else ...[
              _SectionDivider(
                label: 'Push to remote',
                colorScheme: colorScheme,
              ),
              const SizedBox(height: 6),
              _CompactButton(
                onPressed: _canCreatePr
                    ? () => _handleCreatePr(context)
                    : null,
                label: 'Create & Push PR',
                icon: Icons.cloud_upload,
                tooltip: _canCreatePr
                    ? null
                    : _createPrTooltip,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StatusCounts extends StatelessWidget {
  const _StatusCounts({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Tooltip(
      message: 'Uncommitted: ${data.uncommittedFiles} files\n'
          'Staged: ${data.stagedFiles} files\n'
          'Commits ahead of upstream: ${data.commitsAhead}',
      child: Text(
        'Uncommitted/Staged/Commits: '
        '${data.uncommittedFiles}/${data.stagedFiles}/${data.commitsAhead}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DivergenceInfo extends StatelessWidget {
  const _DivergenceInfo({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final ahead = data.commitsAheadOfMain;
    final behind = data.commitsBehindMain;

    if (ahead == 0 && behind == 0) {
      return Tooltip(
        message: 'Your branch is up to date with main',
        child: Text(
          'Up to date with main',
          style: textTheme.bodySmall?.copyWith(
            color: Colors.green,
          ),
        ),
      );
    }

    final tooltipLines = <String>[];
    if (ahead > 0) {
      tooltipLines.add(
        'Your ${data.branch} branch has $ahead '
        '${ahead == 1 ? 'commit' : 'commits'} not present on main',
      );
    }
    if (behind > 0) {
      tooltipLines.add(
        'The main branch has $behind '
        '${behind == 1 ? 'commit' : 'commits'} not present on '
        'your ${data.branch} branch',
      );
    }
    if (ahead > 0 && behind > 0) {
      tooltipLines.add('Your branches have diverged');
    }

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: RichText(
        text: TextSpan(
          style: textTheme.bodySmall,
          children: [
            if (ahead > 0)
              TextSpan(
                text: '${ahead > 0 ? "↑$ahead ahead" : ""}',
                style: TextStyle(color: Colors.green),
              ),
            if (ahead > 0 && behind > 0)
              const TextSpan(text: '  '),
            if (behind > 0)
              TextSpan(
                text: '↓$behind behind',
                style: TextStyle(color: Colors.orange),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConflictInProgress extends StatelessWidget {
  const _ConflictInProgress({
    required this.data,
    required this.onAbort,
    required this.onAskClaude,
    required this.onContinue,
  });

  final WorktreeData data;
  final VoidCallback onAbort;
  final VoidCallback onAskClaude;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final operationLabel =
        data.conflictOperation == MergeOperationType.rebase
            ? 'Rebase'
            : 'Merge';

    // Conflicts resolved but operation still pending.
    final resolved = !data.hasMergeConflict &&
        data.conflictOperation != null;

    final Color bannerColor;
    final IconData bannerIcon;
    final String bannerText;
    if (resolved) {
      bannerColor = Colors.green.shade700;
      bannerIcon = Icons.check_circle_outline;
      bannerText = 'Conflicts resolved — ready to continue';
    } else {
      bannerColor = Colors.orange.shade700;
      bannerIcon = Icons.warning_amber;
      bannerText = '$operationLabel conflict in progress';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: bannerColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: bannerColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(bannerIcon, size: 14, color: bannerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bannerText,
                  style: textTheme.labelSmall?.copyWith(
                    color: bannerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (resolved)
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  onPressed: onContinue,
                  label: 'Continue',
                  icon: Icons.play_arrow,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  onPressed: onAskClaude,
                  label: 'Ask Claude',
                  icon: Icons.auto_fix_high,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({
    required this.label,
    required this.colorScheme,
  });

  final String label;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Section divider with an inline popup menu for selecting a value.
class _SectionDividerWithDropdown extends StatelessWidget {
  const _SectionDividerWithDropdown({
    required this.prefix,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.colorScheme,
    this.tooltips,
  });

  final String prefix;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final ColorScheme colorScheme;
  final Map<String, String>? tooltips;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    final tooltip = tooltips?[value];

    Widget child = GestureDetector(
      onTap: () {
        final renderBox =
            context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            offset.dx + size.width / 2,
            offset.dy + size.height,
            offset.dx + size.width / 2,
            offset.dy + size.height,
          ),
          items: options
              .map(
                (o) => PopupMenuItem<String>(
                  height: 32,
                  value: o,
                  child: Text(o, style: textTheme.bodySmall),
                ),
              )
              .toList(),
        ).then((selected) {
          if (selected != null) {
            onChanged(selected);
          }
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              '$prefix$value',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );

    if (tooltip != null) {
      child = Tooltip(message: tooltip, child: child);
    }

    return child;
  }
}

/// Compact segmented toggle matching [_CompactButton] sizing.
class _CompactToggle<T> extends StatelessWidget {
  const _CompactToggle({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String, IconData)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: _buildSegment(
              context,
              option: options[i],
              isSelected: options[i].$1 == value,
              isFirst: i == 0,
              isLast: i == options.length - 1,
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ),
      ],
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required (T, String, IconData) option,
    required bool isSelected,
    required bool isFirst,
    required bool isLast,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    final (val, label, icon) = option;
    final contentColor = isSelected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final bgColor = isSelected
        ? colorScheme.surfaceContainerHighest
        : Colors.transparent;
    final borderColor = colorScheme.outlineVariant;

    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(4) : Radius.zero,
      right: isLast ? const Radius.circular(4) : Radius.zero,
    );

    return Material(
      color: bgColor,
      borderRadius: radius,
      child: InkWell(
        onTap: () => onChanged(val),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: radius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: contentColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: textTheme.labelSmall
                      ?.copyWith(color: contentColor),
                  textAlign: TextAlign.center,
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

/// Compact button styled for desktop UI - smaller padding and text.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    style: textTheme.labelSmall?.copyWith(color: contentColor),
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
