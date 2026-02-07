import 'package:flutter/material.dart';

import '../services/git_service.dart' show WorktreeInfo;

/// Keys for testing RestoreWorktreeDialog widgets.
class RestoreWorktreeDialogKeys {
  RestoreWorktreeDialogKeys._();

  /// The dialog itself.
  static const dialog = Key('restore_worktree_dialog');

  /// The cancel button.
  static const cancelButton = Key('restore_worktree_cancel');

  /// The empty state text.
  static const emptyText = Key('restore_worktree_empty');
}

/// Shows a dialog to select a worktree to restore.
///
/// [restorableWorktrees] is the list of git worktrees that exist on disk
/// but are not tracked in the app. Each entry has a path and branch.
///
/// Returns the selected [WorktreeInfo] or null if cancelled.
Future<WorktreeInfo?> showRestoreWorktreeDialog({
  required BuildContext context,
  required List<WorktreeInfo> restorableWorktrees,
}) async {
  return showDialog<WorktreeInfo>(
    context: context,
    builder: (context) => _RestoreWorktreeDialog(
      restorableWorktrees: restorableWorktrees,
    ),
  );
}

/// Dialog for selecting a worktree to restore.
///
/// Shows a list of worktrees with their branch names and paths.
/// If the list is empty, shows an empty state message.
class _RestoreWorktreeDialog extends StatelessWidget {
  const _RestoreWorktreeDialog({
    required this.restorableWorktrees,
  });

  /// The list of worktrees available to restore.
  final List<WorktreeInfo> restorableWorktrees;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      key: RestoreWorktreeDialogKeys.dialog,
      title: Row(
        children: [
          Icon(
            Icons.restore,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Restore Worktree'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: restorableWorktrees.isEmpty
            ? _buildEmptyState(textTheme, colorScheme)
            : _buildWorktreeList(textTheme, colorScheme),
      ),
      actions: [
        TextButton(
          key: RestoreWorktreeDialogKeys.cancelButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// Builds the empty state when no worktrees are available to restore.
  Widget _buildEmptyState(TextTheme textTheme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Text(
        'No worktrees available to restore',
        key: RestoreWorktreeDialogKeys.emptyText,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Builds the list of restorable worktrees.
  Widget _buildWorktreeList(TextTheme textTheme, ColorScheme colorScheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 400,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: restorableWorktrees.length,
        itemBuilder: (context, index) {
          final worktree = restorableWorktrees[index];
          return InkWell(
            key: Key('restore_worktree_item_$index'),
            onTap: () => Navigator.of(context).pop(worktree),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 12.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Branch name
                  Text(
                    worktree.branch ?? '(detached HEAD)',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Worktree path
                  Text(
                    worktree.path,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
