import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/worktree.dart';
import '../services/ask_ai_service.dart';
import '../services/git_service.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/commit_dialog.dart';
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
            onPressed: data.uncommittedFiles > 0 || data.stagedFiles > 0
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
                  onPressed: null,
                  label: 'Rebase',
                  icon: Icons.low_priority,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  onPressed: null,
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
