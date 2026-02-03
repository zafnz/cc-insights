import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/ask_ai_service.dart';
import '../services/backend_service.dart';
import '../services/git_service.dart';
import '../services/project_restore_service.dart';
import '../services/sdk_message_handler.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/conflict_resolution_dialog.dart';
import 'panel_wrapper.dart';

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

class _InformationContent extends StatefulWidget {
  const _InformationContent();

  @override
  State<_InformationContent> createState() => _InformationContentState();
}

class _InformationContentState extends State<_InformationContent> {
  WorktreeState? _lastWorktree;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;

    // Start watching worktree when it changes
    if (worktree != null && worktree != _lastWorktree) {
      _lastWorktree = worktree;
      _startWatching(worktree);
    }
  }

  void _startWatching(WorktreeState worktree) {
    // Try to get WorktreeWatcherService - may not be available in tests
    try {
      final watcherService = context.read<WorktreeWatcherService>();
      watcherService.watchWorktree(worktree);
    } catch (_) {
      // Provider not available (e.g., in tests) - silently ignore
    }
  }

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
            final watcherService = context.read<WorktreeWatcherService>();
            watcherService.forceRefresh();
          } catch (_) {
            // Provider not available (e.g., in tests) - silently ignore
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

class _WorktreeInfo extends StatelessWidget {
  const _WorktreeInfo({
    required this.data,
    required this.worktreeRoot,
    required this.onStatusChanged,
  });

  final WorktreeData data;
  final String worktreeRoot;
  final VoidCallback onStatusChanged;

  Future<void> _showCommitDialog(BuildContext context) async {
    // Get services from providers
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();

    final committed = await showCommitDialog(
      context: context,
      worktreePath: worktreeRoot,
      gitService: gitService,
      askAiService: askAiService,
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

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: mainBranch,
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

  /// Whether the update-from-main buttons should be enabled.
  bool get _canUpdateFromMain =>
      data.commitsBehindMain > 0 && !data.isPrimary;

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
          ),
          const SizedBox(height: 12),

          // Update from main section
          _SectionDivider(
            label: 'Update from main',
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Integrate into main section
          _SectionDivider(
            label: 'Integrate into main',
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 6),
          _CompactButton(
            onPressed: null,
            label: 'Merge',
            icon: Icons.merge,
          ),
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
      message: 'Unstaged: ${data.uncommittedFiles} files\n'
          'Staged: ${data.stagedFiles} files\n'
          'Commits ahead of upstream: ${data.commitsAhead}',
      child: Text(
        'Unstaged/Staged/Commits: '
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

/// Compact button styled for desktop UI - smaller padding and text.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

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

    return Opacity(
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
  }
}
