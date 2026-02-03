import 'package:flutter/material.dart';

import '../services/ask_ai_service.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import 'commit_dialog.dart';

/// Keys for testing DeleteWorktreeDialog widgets.
class DeleteWorktreeDialogKeys {
  DeleteWorktreeDialogKeys._();

  static const dialog = Key('delete_worktree_dialog');
  static const progressIndicator = Key('delete_worktree_progress');
  static const errorMessage = Key('delete_worktree_error');
  static const cancelButton = Key('delete_worktree_cancel');
  static const deleteButton = Key('delete_worktree_delete');
}

/// Result of the delete worktree operation.
enum DeleteWorktreeResult {
  /// The worktree was successfully deleted.
  deleted,

  /// The user cancelled the operation.
  cancelled,

  /// The operation failed with an error.
  failed,
}

/// Shows the delete worktree dialog and handles the entire deletion flow.
///
/// Returns [DeleteWorktreeResult.deleted] if the worktree was successfully
/// deleted, [DeleteWorktreeResult.cancelled] if the user cancelled, or
/// [DeleteWorktreeResult.failed] if an error occurred.
Future<DeleteWorktreeResult> showDeleteWorktreeDialog({
  required BuildContext context,
  required String worktreePath,
  required String repoRoot,
  required String branch,
  required String projectId,
  required GitService gitService,
  required PersistenceService persistenceService,
  required AskAiService askAiService,
}) async {
  final result = await showDialog<DeleteWorktreeResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DeleteWorktreeDialog(
      worktreePath: worktreePath,
      repoRoot: repoRoot,
      branch: branch,
      projectId: projectId,
      gitService: gitService,
      persistenceService: persistenceService,
      askAiService: askAiService,
    ),
  );
  return result ?? DeleteWorktreeResult.cancelled;
}

/// Dialog for deleting a worktree with confirmation steps.
class DeleteWorktreeDialog extends StatefulWidget {
  const DeleteWorktreeDialog({
    super.key,
    required this.worktreePath,
    required this.repoRoot,
    required this.branch,
    required this.projectId,
    required this.gitService,
    required this.persistenceService,
    required this.askAiService,
  });

  final String worktreePath;
  final String repoRoot;
  final String branch;
  final String projectId;
  final GitService gitService;
  final PersistenceService persistenceService;
  final AskAiService askAiService;

  @override
  State<DeleteWorktreeDialog> createState() => _DeleteWorktreeDialogState();
}

enum _DialogStep {
  checkingStatus,
  promptUncommittedChanges,
  commitInProgress,
  checkingMergeStatus,
  promptUnmergedBranch,
  deleting,
  promptForceDelete,
  complete,
}

class _DeleteWorktreeDialogState extends State<DeleteWorktreeDialog> {
  _DialogStep _step = _DialogStep.checkingStatus;
  String? _error;
  bool _isProcessing = false;
  GitStatus? _gitStatus;
  String? _mainBranch;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _step = _DialogStep.checkingStatus;
      _isProcessing = true;
      _error = null;
    });

    try {
      // Check for uncommitted changes
      _gitStatus = await widget.gitService.getStatus(widget.worktreePath);

      if (!mounted) return;

      final hasUncommitted =
          _gitStatus!.uncommittedFiles > 0 || _gitStatus!.staged > 0;

      if (hasUncommitted) {
        setState(() {
          _step = _DialogStep.promptUncommittedChanges;
          _isProcessing = false;
        });
      } else {
        // No uncommitted changes, proceed to merge check
        await _checkMergeStatus();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to check worktree status: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleUncommittedAction(String action) async {
    switch (action) {
      case 'discard':
        await _discardChanges();
        break;
      case 'commit':
        await _showCommitDialog();
        break;
      case 'cancel':
        if (mounted) {
          Navigator.of(context).pop(DeleteWorktreeResult.cancelled);
        }
        break;
    }
  }

  Future<void> _discardChanges() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Stash changes so they can be recovered if needed
      await widget.gitService.stash(widget.worktreePath);

      if (!mounted) return;

      // Proceed to merge check
      await _checkMergeStatus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to stash changes: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _showCommitDialog() async {
    setState(() {
      _step = _DialogStep.commitInProgress;
    });

    final committed = await showCommitDialog(
      context: context,
      worktreePath: widget.worktreePath,
      gitService: widget.gitService,
      askAiService: widget.askAiService,
    );

    if (!mounted) return;

    if (committed) {
      // Re-check status after commit
      await _checkStatus();
    } else {
      // User cancelled commit, go back to uncommitted prompt
      setState(() {
        _step = _DialogStep.promptUncommittedChanges;
      });
    }
  }

  Future<void> _checkMergeStatus() async {
    setState(() {
      _step = _DialogStep.checkingMergeStatus;
      _isProcessing = true;
      _error = null;
    });

    try {
      // Fetch to ensure we have latest remote state
      await widget.gitService.fetch(widget.worktreePath);

      if (!mounted) return;

      // Find the main branch
      _mainBranch = await widget.gitService.getMainBranch(widget.repoRoot);

      if (!mounted) return;

      if (_mainBranch == null) {
        // No main branch found, proceed with deletion anyway
        await _proceedWithDeletion();
        return;
      }

      // Check if branch is merged into main
      final isMerged = await widget.gitService.isBranchMerged(
        widget.worktreePath,
        widget.branch,
        _mainBranch!,
      );

      if (!mounted) return;

      if (isMerged) {
        // Branch is merged, safe to delete
        await _proceedWithDeletion();
      } else {
        // Branch not merged, prompt user
        setState(() {
          _step = _DialogStep.promptUnmergedBranch;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // If merge-base check fails, just proceed with deletion but warn user
      setState(() {
        _step = _DialogStep.promptUnmergedBranch;
        _isProcessing = false;
      });
    }
  }

  Future<void> _proceedWithDeletion({bool force = false}) async {
    setState(() {
      _step = _DialogStep.deleting;
      _isProcessing = true;
      _error = null;
    });

    try {
      // Remove the worktree via git
      await widget.gitService.removeWorktree(
        repoRoot: widget.repoRoot,
        worktreePath: widget.worktreePath,
        force: force,
      );

      if (!mounted) return;

      // Remove from persistence
      await widget.persistenceService.removeWorktreeFromIndex(
        projectRoot: widget.repoRoot,
        worktreePath: widget.worktreePath,
        projectId: widget.projectId,
      );

      if (!mounted) return;

      Navigator.of(context).pop(DeleteWorktreeResult.deleted);
    } on GitException catch (e) {
      if (!mounted) return;

      // Check if this is a "dirty worktree" error that can be forced
      final needsForce = e.stderr?.contains('contains modified') == true ||
          e.stderr?.contains('contains untracked') == true ||
          e.stderr?.contains('is dirty') == true;

      if (needsForce && !force) {
        setState(() {
          _step = _DialogStep.promptForceDelete;
          _isProcessing = false;
          _error = e.stderr ?? e.message;
        });
      } else {
        setState(() {
          _error = 'Failed to remove worktree: ${e.stderr ?? e.message}';
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to remove worktree: $e';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: DeleteWorktreeDialogKeys.dialog,
      child: Container(
        width: 450,
        constraints: const BoxConstraints(maxHeight: 350),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildContent(colorScheme),
                ),
              ),
            ),
            if (_error != null) _buildError(colorScheme),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.delete_outline,
            color: colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Delete Worktree',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    switch (_step) {
      case _DialogStep.checkingStatus:
        return _buildCheckingStatus(colorScheme);
      case _DialogStep.promptUncommittedChanges:
        return _buildUncommittedPrompt(colorScheme);
      case _DialogStep.commitInProgress:
        return _buildCommitInProgress(colorScheme);
      case _DialogStep.checkingMergeStatus:
        return _buildCheckingMergeStatus(colorScheme);
      case _DialogStep.promptUnmergedBranch:
        return _buildUnmergedPrompt(colorScheme);
      case _DialogStep.deleting:
        return _buildDeleting(colorScheme);
      case _DialogStep.promptForceDelete:
        return _buildForceDeletePrompt(colorScheme);
      case _DialogStep.complete:
        return _buildComplete(colorScheme);
    }
  }

  Widget _buildCheckingStatus(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          key: DeleteWorktreeDialogKeys.progressIndicator,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Checking worktree status...',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildUncommittedPrompt(ColorScheme colorScheme) {
    final uncommittedCount =
        (_gitStatus?.uncommittedFiles ?? 0) + (_gitStatus?.staged ?? 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Uncommitted Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'This worktree has $uncommittedCount uncommitted '
          '${uncommittedCount == 1 ? 'file' : 'files'}.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          'What would you like to do?',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _handleUncommittedAction('discard'),
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _handleUncommittedAction('commit'),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Commit All'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Note: Discard will stash your changes for potential recovery.',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildCommitInProgress(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          key: DeleteWorktreeDialogKeys.progressIndicator,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Committing changes...',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildCheckingMergeStatus(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          key: DeleteWorktreeDialogKeys.progressIndicator,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Checking if branch has been merged...',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildUnmergedPrompt(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Unmerged Branch',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        RichText(
          text: TextSpan(
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            children: [
              const TextSpan(text: 'The branch '),
              TextSpan(
                text: widget.branch,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' may not have been merged into '),
              TextSpan(
                text: _mainBranch ?? 'main',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Are you sure you want to delete this worktree? '
          'Any unmerged commits will be lost.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildDeleting(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          key: DeleteWorktreeDialogKeys.progressIndicator,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Removing worktree...',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildForceDeletePrompt(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Worktree Has Changes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Git reports that the worktree still has changes:',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Do you want to force remove the worktree?',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildComplete(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 16),
        Text(
          'Worktree deleted successfully.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    // Only show error bar for unexpected errors, not force-delete prompts
    if (_step == _DialogStep.promptForceDelete) {
      return const SizedBox.shrink();
    }

    return Container(
      key: DeleteWorktreeDialogKeys.errorMessage,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onErrorContainer,
            ),
            onPressed: () => setState(() => _error = null),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _buildFooterButtons(colorScheme),
      ),
    );
  }

  List<Widget> _buildFooterButtons(ColorScheme colorScheme) {
    switch (_step) {
      case _DialogStep.checkingStatus:
      case _DialogStep.checkingMergeStatus:
      case _DialogStep.deleting:
      case _DialogStep.commitInProgress:
        return [
          TextButton(
            key: DeleteWorktreeDialogKeys.cancelButton,
            onPressed: null,
            child: const Text('Cancel'),
          ),
        ];

      case _DialogStep.promptUncommittedChanges:
        return [
          TextButton(
            key: DeleteWorktreeDialogKeys.cancelButton,
            onPressed: _isProcessing
                ? null
                : () => _handleUncommittedAction('cancel'),
            child: const Text('Cancel'),
          ),
        ];

      case _DialogStep.promptUnmergedBranch:
        return [
          TextButton(
            key: DeleteWorktreeDialogKeys.cancelButton,
            onPressed:
                _isProcessing ? null : () => Navigator.of(context).pop(
                  DeleteWorktreeResult.cancelled,
                ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: DeleteWorktreeDialogKeys.deleteButton,
            onPressed: _isProcessing ? null : () => _proceedWithDeletion(),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete Anyway'),
          ),
        ];

      case _DialogStep.promptForceDelete:
        return [
          TextButton(
            key: DeleteWorktreeDialogKeys.cancelButton,
            onPressed:
                _isProcessing ? null : () => Navigator.of(context).pop(
                  DeleteWorktreeResult.cancelled,
                ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: DeleteWorktreeDialogKeys.deleteButton,
            onPressed:
                _isProcessing ? null : () => _proceedWithDeletion(force: true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Force Delete'),
          ),
        ];

      case _DialogStep.complete:
        return [
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(DeleteWorktreeResult.deleted),
            child: const Text('Close'),
          ),
        ];
    }
  }
}
