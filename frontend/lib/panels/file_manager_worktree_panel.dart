import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import '../state/file_manager_state.dart';
import 'panel_wrapper.dart';

/// Simplified worktree panel for the File Manager screen.
///
/// Displays all worktrees from [ProjectState] and allows selection via
/// [FileManagerState]. This is a simplified version of [WorktreePanel]
/// without permission bells, merging behavior, or create worktree card.
///
/// Click a worktree to select it and load its file tree.
class FileManagerWorktreePanel extends StatelessWidget {
  const FileManagerWorktreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Worktrees',
      icon: Icons.account_tree,
      child: _WorktreeListContent(),
    );
  }
}

/// Content of the worktree list panel.
class _WorktreeListContent extends StatelessWidget {
  const _WorktreeListContent();

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectState>();
    final fileManagerState = context.watch<FileManagerState>();
    final worktrees = project.allWorktrees;

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: worktrees.length,
      itemBuilder: (context, index) {
        final worktree = worktrees[index];
        final isSelected =
            fileManagerState.selectedWorktree == worktree;

        return _WorktreeListItem(
          worktree: worktree,
          repoRoot: project.data.repoRoot,
          isSelected: isSelected,
          onTap: () => fileManagerState.selectWorktree(worktree),
        );
      },
    );
  }
}

/// A single compact worktree entry in the list.
///
/// Displays branch name, relative path, and git status indicators.
/// Click to select the worktree in [FileManagerState].
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
  ///
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
        repoComponents[commonLength] ==
            worktreeComponents[commonLength]) {
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
    final displayPath =
        _getRelativePath(data.worktreeRoot) ?? data.worktreeRoot;

    return Material(
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Branch name
              Text(
                data.branch,
                style: textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Path + status on same line
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
                  // Status indicators rebuild when worktree
                  // data changes (e.g. git status poll).
                  ListenableBuilder(
                    listenable: worktree,
                    builder: (context, _) =>
                        _InlineStatusIndicators(
                      data: worktree.data,
                    ),
                  ),
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
///
/// Displays commits ahead, commits behind, uncommitted files, and
/// merge conflict indicators inline with appropriate colors.
class _InlineStatusIndicators extends StatelessWidget {
  const _InlineStatusIndicators({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final parts = <TextSpan>[];

    // Commits ahead of main (green arrow up)
    if (data.commitsAheadOfMain > 0) {
      parts.add(
        TextSpan(
          text: '↑${data.commitsAheadOfMain}',
          style: textTheme.labelSmall?.copyWith(
            color: Colors.green,
          ),
        ),
      );
    }

    // Commits behind main (orange arrow down)
    if (data.commitsBehindMain > 0) {
      if (parts.isNotEmpty) {
        parts.add(const TextSpan(text: ' '));
      }
      parts.add(
        TextSpan(
          text: '↓${data.commitsBehindMain}',
          style: textTheme.labelSmall?.copyWith(
            color: Colors.orange,
          ),
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
