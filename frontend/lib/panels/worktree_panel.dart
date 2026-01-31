import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import '../state/selection_state.dart';
import 'panel_wrapper.dart';

/// Worktree panel - shows the list of worktrees.
class WorktreePanel extends StatelessWidget {
  const WorktreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Worktrees',
      icon: Icons.account_tree,
      child: _WorktreeListContent(),
    );
  }
}

/// Content of the worktree list panel (without header - that's in PanelWrapper).
class _WorktreeListContent extends StatelessWidget {
  const _WorktreeListContent();

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final worktrees = project.allWorktrees;

    // +1 for the ghost "Create New Worktree" card
    final itemCount = worktrees.length + 1;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Last item is the ghost card
        if (index == worktrees.length) {
          return const CreateWorktreeCard();
        }

        final worktree = worktrees[index];
        final isSelected = selection.selectedWorktree == worktree;
        return _WorktreeListItem(
          worktree: worktree,
          repoRoot: project.data.repoRoot,
          isSelected: isSelected,
          onTap: () => selection.selectWorktree(worktree),
        );
      },
    );
  }
}

/// Ghost card for creating a new worktree.
///
/// Displays a subtle "New Worktree" action that when clicked
/// will (in the future) open a dialog to create a new git worktree.
class CreateWorktreeCard extends StatelessWidget {
  const CreateWorktreeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<SelectionState>().showCreateWorktreePanel();
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'New Worktree',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

/// A single compact worktree entry in the list.
class _WorktreeListItem extends StatelessWidget {
  const _WorktreeListItem({
    required this.worktree,
    required this.repoRoot,
    required this.isSelected,
    required this.onTap,
  });

  final WorktreeState worktree;
  final String repoRoot;
  final bool isSelected;
  final VoidCallback onTap;

  /// Computes a relative path from the repo root to the worktree.
  /// Returns null for the primary worktree (at repo root).
  String? _getRelativePath(String worktreePath) {
    // Primary worktree at repo root - show full path
    if (worktreePath == repoRoot) {
      return null;
    }

    // Split paths into components
    final repoComponents = repoRoot.split('/');
    final worktreeComponents = worktreePath.split('/');

    // Find common prefix length
    int commonLength = 0;
    while (commonLength < repoComponents.length &&
        commonLength < worktreeComponents.length &&
        repoComponents[commonLength] == worktreeComponents[commonLength]) {
      commonLength++;
    }

    // Build relative path: go up from repo, then down to worktree
    final upCount = repoComponents.length - commonLength;
    final downPath = worktreeComponents.skip(commonLength).toList();

    final parts = <String>[];
    for (int i = 0; i < upCount; i++) {
      parts.add('..');
    }
    parts.addAll(downPath);

    return parts.isEmpty ? '.' : parts.join('/');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final data = worktree.data;
    // Show relative path for linked worktrees, full path for primary
    final displayPath = _getRelativePath(data.worktreeRoot) ?? data.worktreeRoot;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branch name (normal weight, ~13px)
              Text(
                data.branch,
                style: textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Path + status on same line (muted, monospace, ~11px)
              Row(
                children: [
                  // Path (full for primary, relative for linked)
                  Expanded(
                    child: Text(
                      displayPath,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Inline status indicators
                  InlineStatusIndicators(data: data),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact inline status indicators using arrow format: "↑2 ↓1 ~3"
class InlineStatusIndicators extends StatelessWidget {
  const InlineStatusIndicators({super.key, required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parts = <TextSpan>[];

    // Commits ahead (green arrow up)
    if (data.commitsAhead > 0) {
      parts.add(
        TextSpan(
          text: '↑${data.commitsAhead}',
          style: textTheme.labelSmall?.copyWith(color: Colors.green),
        ),
      );
    }

    // Commits behind (orange arrow down)
    if (data.commitsBehind > 0) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '↓${data.commitsBehind}',
          style: textTheme.labelSmall?.copyWith(color: Colors.orange),
        ),
      );
    }

    // Uncommitted changes (blue tilde)
    if (data.uncommittedFiles > 0) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '~${data.uncommittedFiles}',
          style: textTheme.labelSmall?.copyWith(color: Colors.blue),
        ),
      );
    }

    // Merge conflict (red exclamation)
    if (data.hasMergeConflict) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '!',
          style: textTheme.labelSmall?.copyWith(color: Colors.red),
        ),
      );
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: RichText(text: TextSpan(children: parts)),
    );
  }
}
