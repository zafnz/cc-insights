import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/worktree.dart';
import '../services/persistence_models.dart';
import '../services/persistence_service.dart';
import '../services/project_restore_service.dart';

/// Shows a dialog listing all archived chats for the current project.
///
/// Allows restoring archived chats to their original worktree (if it still
/// exists) or the currently selected worktree, and permanently deleting them.
Future<void> showArchivedChatsDialog({
  required BuildContext context,
  required String projectRoot,
  required String projectId,
  required PersistenceService persistenceService,
  required ProjectRestoreService restoreService,
  required ProjectState project,
  required WorktreeState? selectedWorktree,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _ArchivedChatsDialog(
      projectRoot: projectRoot,
      projectId: projectId,
      persistenceService: persistenceService,
      restoreService: restoreService,
      project: project,
      selectedWorktree: selectedWorktree,
    ),
  );
}

class _ArchivedChatsDialog extends StatefulWidget {
  const _ArchivedChatsDialog({
    required this.projectRoot,
    required this.projectId,
    required this.persistenceService,
    required this.restoreService,
    required this.project,
    required this.selectedWorktree,
  });

  final String projectRoot;
  final String projectId;
  final PersistenceService persistenceService;
  final ProjectRestoreService restoreService;
  final ProjectState project;
  final WorktreeState? selectedWorktree;

  @override
  State<_ArchivedChatsDialog> createState() => _ArchivedChatsDialogState();
}

class _ArchivedChatsDialogState extends State<_ArchivedChatsDialog> {
  List<ArchivedChatReference>? _archivedChats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArchivedChats();
  }

  Future<void> _loadArchivedChats() async {
    try {
      final chats = await widget.persistenceService.getArchivedChats(
        projectRoot: widget.projectRoot,
      );
      if (mounted) {
        setState(() {
          _archivedChats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Finds the worktree to restore to. Returns the original worktree if it
  /// exists in the project, otherwise falls back to the selected worktree.
  WorktreeState? _findRestoreTarget(String originalWorktreePath) {
    for (final wt in widget.project.allWorktrees) {
      if (wt.data.worktreeRoot == originalWorktreePath) {
        return wt;
      }
    }
    return widget.selectedWorktree;
  }

  Future<void> _restoreChat(ArchivedChatReference archivedRef) async {
    final targetWorktree = _findRestoreTarget(archivedRef.originalWorktreePath);
    if (targetWorktree == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No worktree available to restore to')),
        );
      }
      return;
    }

    try {
      final chatState = await widget.restoreService.restoreArchivedChat(
        archivedRef,
        targetWorktree.data.worktreeRoot,
        widget.projectId,
        widget.projectRoot,
      );

      targetWorktree.addChat(chatState);

      developer.log(
        'Restored archived chat ${archivedRef.chatId} to '
        '${targetWorktree.data.worktreeRoot}',
        name: 'ArchivedChatsDialog',
      );

      // Reload the list
      await _loadArchivedChats();
    } catch (e) {
      developer.log(
        'Failed to restore archived chat: $e',
        name: 'ArchivedChatsDialog',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to restore chat: $e')),
        );
      }
    }
  }

  Future<void> _deleteChat(ArchivedChatReference archivedRef) async {
    try {
      await widget.persistenceService.deleteArchivedChat(
        projectRoot: widget.projectRoot,
        projectId: widget.projectId,
        chatId: archivedRef.chatId,
      );

      // Reload the list
      await _loadArchivedChats();
    } catch (e) {
      developer.log(
        'Failed to delete archived chat: $e',
        name: 'ArchivedChatsDialog',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete chat: $e')),
        );
      }
    }
  }

  String _shortenPath(String worktreePath) {
    // Show relative path from project root, or basename if outside
    if (worktreePath.startsWith(widget.projectRoot)) {
      final relative = p.relative(worktreePath, from: widget.projectRoot);
      return relative == '.' ? '(project root)' : relative;
    }
    return p.basename(worktreePath);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      child: Container(
        width: 550,
        constraints: const BoxConstraints(maxHeight: 450),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Archived Chats',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurfaceVariant,
                    ),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(child: _buildContent(colorScheme, textTheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Failed to load archived chats: $_error',
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      );
    }

    final chats = _archivedChats ?? [];
    if (chats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.archive_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              Text(
                'No archived chats',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chats you close with archiving enabled will appear here.',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: chats.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, index) {
          final chat = chats[index];
          return _ArchivedChatItem(
            chat: chat,
            shortenedPath: _shortenPath(chat.originalWorktreePath),
            formattedDate: _formatDate(chat.archivedAt),
            restoreTarget: _findRestoreTarget(chat.originalWorktreePath),
            originalWorktreeExists: widget.project.allWorktrees.any(
              (wt) => wt.data.worktreeRoot == chat.originalWorktreePath,
            ),
            onRestore: () => _restoreChat(chat),
            onDelete: () => _deleteChat(chat),
          );
        },
      ),
    );
  }
}

class _ArchivedChatItem extends StatelessWidget {
  const _ArchivedChatItem({
    required this.chat,
    required this.shortenedPath,
    required this.formattedDate,
    required this.restoreTarget,
    required this.originalWorktreeExists,
    required this.onRestore,
    required this.onDelete,
  });

  final ArchivedChatReference chat;
  final String shortenedPath;
  final String formattedDate;
  final WorktreeState? restoreTarget;
  final bool originalWorktreeExists;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(
        children: [
          // Chat info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chat.name,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        shortenedPath,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formattedDate,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (!originalWorktreeExists && restoreTarget != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Will restore to: ${p.basename(restoreTarget!.data.worktreeRoot)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Action buttons
          IconButton(
            icon: Icon(
              Icons.restore,
              size: 18,
              color: restoreTarget != null
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            tooltip: restoreTarget != null ? 'Restore chat' : 'No worktree available',
            onPressed: restoreTarget != null ? onRestore : null,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: colorScheme.error.withValues(alpha: 0.7),
            ),
            tooltip: 'Delete permanently',
            onPressed: onDelete,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
