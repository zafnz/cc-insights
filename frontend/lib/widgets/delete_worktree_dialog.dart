import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/ask_ai_service.dart';
import '../services/file_system_service.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/project_config_service.dart';
import '../services/script_execution_service.dart';
import 'commit_dialog.dart';

/// Keys for testing DeleteWorktreeDialog widgets.
class DeleteWorktreeDialogKeys {
  DeleteWorktreeDialogKeys._();

  static const dialog = Key('delete_worktree_dialog');
  static const logList = Key('delete_worktree_log_list');
  static const cancelButton = Key('delete_worktree_cancel');
  static const deleteButton = Key('delete_worktree_delete');
  static const discardButton = Key('delete_worktree_discard');
  static const commitButton = Key('delete_worktree_commit');
  static const forceDeleteButton = Key('delete_worktree_force_delete');
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
  required String base,
  required String projectId,
  required GitService gitService,
  required PersistenceService persistenceService,
  required AskAiService askAiService,
  required FileSystemService fileSystemService,
  ProjectConfigService? configService,
  ScriptExecutionService? scriptService,
}) async {
  final result = await showDialog<DeleteWorktreeResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DeleteWorktreeDialog(
      worktreePath: worktreePath,
      repoRoot: repoRoot,
      branch: branch,
      base: base,
      projectId: projectId,
      gitService: gitService,
      persistenceService: persistenceService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
      configService: configService,
      scriptService: scriptService,
    ),
  );
  return result ?? DeleteWorktreeResult.cancelled;
}

/// Status of a log entry.
enum LogEntryStatus {
  /// Operation is currently running.
  running,

  /// Operation completed successfully.
  success,

  /// Operation completed with a warning.
  warning,

  /// Operation failed with an error.
  error,
}

/// A single log entry in the delete worktree dialog.
class LogEntry {
  final String message;
  final LogEntryStatus status;
  final String? detail;

  const LogEntry({
    required this.message,
    required this.status,
    this.detail,
  });

  LogEntry copyWith({
    String? message,
    LogEntryStatus? status,
    String? detail,
  }) {
    return LogEntry(
      message: message ?? this.message,
      status: status ?? this.status,
      detail: detail ?? this.detail,
    );
  }
}

/// Current action state of the dialog.
enum _ActionState {
  /// Initial state, checking worktree status.
  checking,

  /// Waiting for user to handle uncommitted changes.
  waitingUncommitted,

  /// Processing (stashing, fetching, checking merge status).
  processing,

  /// Ready to delete worktree.
  readyToDelete,

  /// Upstream is up-to-date but commits not merged into base.
  upstreamWarning,

  /// Branch has unmerged commits - user must confirm force delete.
  hasUnmergedCommits,

  /// Deleting worktree.
  deleting,

  /// Deletion failed, needs force.
  needsForce,

  /// Commit dialog is open.
  committing,

  /// Deletion failed with an unrecoverable error.
  failed,

  /// Deletion complete.
  complete,
}

/// Dialog for deleting a worktree with a running log of operations.
class DeleteWorktreeDialog extends StatefulWidget {
  const DeleteWorktreeDialog({
    super.key,
    required this.worktreePath,
    required this.repoRoot,
    required this.branch,
    required this.base,
    required this.projectId,
    required this.gitService,
    required this.persistenceService,
    required this.askAiService,
    required this.fileSystemService,
    this.configService,
    this.scriptService,
  });

  final String worktreePath;
  final String repoRoot;
  final String branch;
  final String base;
  final String projectId;
  final GitService gitService;
  final PersistenceService persistenceService;
  final AskAiService askAiService;
  final FileSystemService fileSystemService;
  final ProjectConfigService? configService;
  final ScriptExecutionService? scriptService;

  @override
  State<DeleteWorktreeDialog> createState() => _DeleteWorktreeDialogState();
}

class _DeleteWorktreeDialogState extends State<DeleteWorktreeDialog> {
  final List<LogEntry> _log = [];
  final ScrollController _scrollController = ScrollController();
  _ActionState _actionState = _ActionState.checking;
  int _uncommittedCount = 0;

  @override
  void initState() {
    super.initState();
    _startWorkflow();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String message, LogEntryStatus status, {String? detail}) {
    setState(() {
      _log.add(LogEntry(message: message, status: status, detail: detail));
    });
    _scrollToBottom();
  }

  void _updateLastLog(LogEntryStatus status, {String? message, String? detail}) {
    if (_log.isEmpty) return;
    setState(() {
      _log[_log.length - 1] = _log.last.copyWith(
        status: status,
        message: message,
        detail: detail,
      );
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startWorkflow() async {
    await _checkUncommittedChanges();
  }

  Future<void> _checkUncommittedChanges() async {
    _addLog('Checking for uncommitted changes...', LogEntryStatus.running);

    try {
      final status = await widget.gitService.getStatus(widget.worktreePath);

      if (!mounted) return;

      _uncommittedCount = status.uncommittedFiles;

      if (_uncommittedCount > 0) {
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Found $_uncommittedCount uncommitted '
              '${_uncommittedCount == 1 ? 'file' : 'files'}',
        );
        setState(() {
          _actionState = _ActionState.waitingUncommitted;
        });
      } else {
        _updateLastLog(LogEntryStatus.success, message: 'Worktree is clean');
        await _continueAfterUncommitted();
      }
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Failed to check status',
        detail: e.toString(),
      );
    }
  }

  Future<void> _handleDiscard() async {
    setState(() {
      _actionState = _ActionState.processing;
    });

    _addLog('Stashing changes for recovery...', LogEntryStatus.running);

    try {
      await widget.gitService.stash(widget.worktreePath);

      if (!mounted) return;

      _updateLastLog(
        LogEntryStatus.success,
        message: 'Changes stashed (recover with `git stash pop`)',
      );

      await _continueAfterUncommitted();
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Failed to stash changes',
        detail: e.toString(),
      );
    }
  }

  Future<void> _handleCommit() async {
    setState(() {
      _actionState = _ActionState.committing;
    });

    final committed = await showCommitDialog(
      context: context,
      worktreePath: widget.worktreePath,
      gitService: widget.gitService,
      askAiService: widget.askAiService,
      fileSystemService: widget.fileSystemService,
    );

    if (!mounted) return;

    if (committed) {
      _addLog('Changes committed', LogEntryStatus.success);
      await _continueAfterUncommitted();
    } else {
      // User cancelled commit, go back to waiting
      setState(() {
        _actionState = _ActionState.waitingUncommitted;
      });
    }
  }

  Future<void> _continueAfterUncommitted() async {
    setState(() {
      _actionState = _ActionState.processing;
    });

    // Fetch from origin
    await _fetchOrigin();

    if (!mounted) return;

    // Run safety check waterfall
    await _runSafetyChecks();
  }

  Future<void> _fetchOrigin() async {
    _addLog('Fetching from origin...', LogEntryStatus.running);

    try {
      await widget.gitService.fetch(widget.worktreePath);

      if (!mounted) return;

      _updateLastLog(LogEntryStatus.success, message: 'Fetched latest from origin');
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.warning,
        message: 'Could not fetch (continuing anyway)',
        detail: e.toString(),
      );
    }
  }

  /// Runs the safety check waterfall:
  /// 1. merge-base ancestor check
  /// 2. squash merge (cherry) check
  /// 3. upstream check
  Future<void> _runSafetyChecks() async {
    // Check 1: Is branch an ancestor of base?
    final isMerged = await _checkBaseHasChanges();
    if (!mounted) return;
    if (isMerged) {
      _addLog('Ready to remove worktree', LogEntryStatus.success);
      setState(() {
        _actionState = _ActionState.readyToDelete;
      });
      return;
    }

    // Check 2: Squash merge check
    final isSquashMerged = await _checkSquashMerge();
    if (!mounted) return;
    if (isSquashMerged) {
      _addLog('Ready to remove worktree', LogEntryStatus.success);
      setState(() {
        _actionState = _ActionState.readyToDelete;
      });
      return;
    }

    // Check 3: Upstream check
    await _checkUpstream();
  }

  /// Check 1: merge-base --is-ancestor check.
  /// Returns true if branch is fully merged into base.
  Future<bool> _checkBaseHasChanges() async {
    _addLog(
      'Checking if ${widget.base} has all commits...',
      LogEntryStatus.running,
    );

    try {
      final isMerged = await widget.gitService.isBranchMerged(
        widget.worktreePath,
        widget.branch,
        widget.base,
      );

      if (!mounted) return false;

      if (isMerged) {
        _updateLastLog(
          LogEntryStatus.success,
          message: 'All commits are on ${widget.base}',
        );
        return true;
      } else {
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Branch has commits not on ${widget.base}',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      _updateLastLog(
        LogEntryStatus.warning,
        message: 'Could not check merge status',
        detail: e.toString(),
      );
      return false;
    }
  }

  /// Check 2: git cherry squash merge check.
  /// Returns true if all commits appear on base (likely squash merged).
  Future<bool> _checkSquashMerge() async {
    _addLog(
      'Checking for squash-merged commits on ${widget.base}...',
      LogEntryStatus.running,
    );

    try {
      final unmerged = await widget.gitService.getUnmergedCommits(
        widget.worktreePath,
        widget.branch,
        widget.base,
      );

      if (!mounted) return false;

      if (unmerged.isEmpty) {
        _updateLastLog(
          LogEntryStatus.success,
          message: 'All commits are accounted for on ${widget.base}',
        );
        return true;
      } else {
        _updateLastLog(
          LogEntryStatus.warning,
          message: '${unmerged.length} '
              '${unmerged.length == 1 ? 'commit' : 'commits'} '
              'not on ${widget.base}',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      _updateLastLog(
        LogEntryStatus.warning,
        message: 'Could not verify commits on ${widget.base}',
        detail: e.toString(),
      );
      return false;
    }
  }

  /// Check 3: upstream tracking branch check.
  Future<void> _checkUpstream() async {
    _addLog('Checking upstream tracking branch...', LogEntryStatus.running);

    try {
      final upstream = await widget.gitService.getUpstream(
        widget.worktreePath,
      );

      if (!mounted) return;

      if (upstream == null) {
        _updateLastLog(
          LogEntryStatus.error,
          message: 'No upstream branch found. You will lose work.',
        );
        setState(() {
          _actionState = _ActionState.hasUnmergedCommits;
        });
        return;
      }

      // Upstream exists - check how far behind it is
      final comparison = await widget.gitService.getBranchComparison(
        widget.worktreePath,
        widget.branch,
        upstream,
      );

      if (!mounted) return;

      if (comparison != null && comparison.ahead == 0) {
        // Upstream is up-to-date: warning state
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Upstream $upstream is up-to-date but ${widget.branch} '
              'commits are not merged into ${widget.base}. You can pull '
              '$upstream and retrieve your work, so long as it\'s not '
              'deleted.',
        );
        setState(() {
          _actionState = _ActionState.upstreamWarning;
        });
      } else {
        // Upstream is behind: error state, require force delete
        final behindCount = comparison?.ahead ?? 0;
        _updateLastLog(
          LogEntryStatus.error,
          message: 'Changes are not on ${widget.base} and $upstream is '
              '$behindCount '
              '${behindCount == 1 ? 'commit' : 'commits'} behind. '
              'You will lose work.',
        );
        setState(() {
          _actionState = _ActionState.hasUnmergedCommits;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Could not check upstream status',
        detail: e.toString(),
      );
      setState(() {
        _actionState = _ActionState.hasUnmergedCommits;
      });
    }
  }

  Future<void> _handleDelete({bool force = false}) async {
    setState(() {
      _actionState = _ActionState.deleting;
    });

    // Run pre-remove hook if configured
    final preRemoveSuccess = await _runPreRemoveHook();
    if (!preRemoveSuccess) {
      // Pre-remove hook failed - abort unless force
      if (!force) {
        setState(() {
          _actionState = _ActionState.needsForce;
        });
        return;
      }
      // Force mode - continue despite hook failure
    }

    _addLog('Removing worktree...', LogEntryStatus.running);

    try {
      await widget.gitService.removeWorktree(
        repoRoot: widget.repoRoot,
        worktreePath: widget.worktreePath,
        force: force,
      );

      if (!mounted) return;

      _updateLastLog(LogEntryStatus.success, message: 'Worktree removed');

      // Remove from persistence
      _addLog('Cleaning up...', LogEntryStatus.running);

      try {
        await widget.persistenceService.removeWorktreeFromIndex(
          projectRoot: widget.repoRoot,
          worktreePath: widget.worktreePath,
          projectId: widget.projectId,
        );

        if (!mounted) return;

        _updateLastLog(LogEntryStatus.success, message: 'Cleanup complete');
      } catch (e) {
        if (!mounted) return;

        // Cleanup failed but worktree is deleted, continue anyway
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Cleanup had issues (worktree still deleted)',
          detail: e.toString(),
        );
      }

      // Run post-remove hook if configured
      await _runPostRemoveHook();

      setState(() {
        _actionState = _ActionState.complete;
      });

      // Close dialog - use post-frame callback to ensure state update is processed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop(DeleteWorktreeResult.deleted);
        }
      });
    } catch (e) {
      if (!mounted) return;

      final detail = e is GitException
          ? (e.stderr ?? e.message)
          : e.toString();

      if (!force) {
        // Normal delete failed - offer force delete
        _updateLastLog(
          LogEntryStatus.error,
          message: 'Failed to remove worktree',
          detail: detail,
        );
        setState(() {
          _actionState = _ActionState.needsForce;
        });
      } else {
        // Force delete also failed - nothing more we can do
        _updateLastLog(
          LogEntryStatus.error,
          message: 'Force delete failed',
          detail: detail,
        );
        setState(() {
          _actionState = _ActionState.failed;
        });
      }
    }
  }

  /// Runs the pre-remove hook if configured. Returns true if successful or no hook.
  Future<bool> _runPreRemoveHook() async {
    final configService = widget.configService ?? ProjectConfigService();
    final config = await configService.loadConfig(widget.repoRoot);

    if (!mounted) return false;

    final preRemoveHook = config.getHook('worktree-pre-remove');

    if (preRemoveHook == null || preRemoveHook.isEmpty) {
      return true; // No hook configured
    }

    _addLog('Running pre-remove hook...', LogEntryStatus.running);

    try {
      final exitCode = await _runHook(
        hookName: 'worktree-pre-remove',
        command: preRemoveHook,
        workingDirectory: widget.worktreePath,
      );

      if (!mounted) return false;

      if (exitCode == 0) {
        _updateLastLog(LogEntryStatus.success, message: 'Pre-remove hook completed');
        return true;
      } else {
        _updateLastLog(
          LogEntryStatus.error,
          message: 'Pre-remove hook failed (exit code $exitCode)',
        );
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Pre-remove hook failed',
        detail: e.toString(),
      );
      return false;
    }
  }

  /// Runs the post-remove hook if configured. Failures are logged but don't abort.
  Future<void> _runPostRemoveHook() async {
    final configService = widget.configService ?? ProjectConfigService();
    final config = await configService.loadConfig(widget.repoRoot);

    if (!mounted) return;

    final postRemoveHook = config.getHook('worktree-post-remove');

    if (postRemoveHook == null || postRemoveHook.isEmpty) {
      return; // No hook configured
    }

    _addLog('Running post-remove hook...', LogEntryStatus.running);

    try {
      final exitCode = await _runHook(
        hookName: 'worktree-post-remove',
        command: postRemoveHook,
        workingDirectory: widget.repoRoot, // Run in repo root since worktree is gone
      );

      if (!mounted) return;

      if (exitCode == 0) {
        _updateLastLog(LogEntryStatus.success, message: 'Post-remove hook completed');
      } else {
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Post-remove hook exited with code $exitCode',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.warning,
        message: 'Post-remove hook had issues',
        detail: e.toString(),
      );
    }
  }

  /// Runs a lifecycle hook script and returns the exit code.
  Future<int> _runHook({
    required String hookName,
    required String command,
    required String workingDirectory,
  }) async {
    developer.log(
      'Running hook "$hookName": $command in $workingDirectory',
      name: 'DeleteWorktreeDialog',
    );

    if (widget.scriptService != null) {
      // Use script service to show output in terminal panel
      return await widget.scriptService!.runScriptSync(
        name: hookName,
        command: command,
        workingDirectory: workingDirectory,
      );
    } else {
      // Run directly without UI
      final result = await Process.run(
        '/bin/sh',
        ['-c', command],
        workingDirectory: workingDirectory,
      );
      return result.exitCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: DeleteWorktreeDialogKeys.dialog,
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
            _buildHeader(colorScheme),
            Expanded(
              child: _buildLogList(colorScheme),
            ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Delete ${widget.branch}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildActionButtons(colorScheme),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    final buttons = <Widget>[];

    switch (_actionState) {
      case _ActionState.waitingUncommitted:
        buttons.addAll([
          _ActionButton(
            key: DeleteWorktreeDialogKeys.discardButton,
            label: 'Discard',
            icon: Icons.delete_sweep,
            onPressed: _handleDiscard,
            colorScheme: colorScheme,
          ),
          const SizedBox(width: 8),
          _ActionButton(
            key: DeleteWorktreeDialogKeys.commitButton,
            label: 'Commit All',
            icon: Icons.check_circle_outline,
            onPressed: _handleCommit,
            colorScheme: colorScheme,
          ),
        ]);
        break;

      case _ActionState.readyToDelete:
        buttons.add(
          _ActionButton(
            key: DeleteWorktreeDialogKeys.deleteButton,
            label: 'Delete Worktree',
            icon: Icons.delete_forever,
            onPressed: () => _handleDelete(),
            colorScheme: colorScheme,
            isPrimary: true,
          ),
        );
        break;

      case _ActionState.upstreamWarning:
        buttons.addAll([
          _ActionButton(
            key: DeleteWorktreeDialogKeys.deleteButton,
            label: 'Delete Worktree',
            icon: Icons.delete_forever,
            onPressed: () => _handleDelete(),
            colorScheme: colorScheme,
            isPrimary: true,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(DeleteWorktreeResult.cancelled),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onErrorContainer,
              side: BorderSide(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.5),
              ),
            ),
            child: const Text('Abort'),
          ),
        ]);
        break;

      case _ActionState.hasUnmergedCommits:
        buttons.addAll([
          _ActionButton(
            key: DeleteWorktreeDialogKeys.forceDeleteButton,
            label: 'Force Delete',
            icon: Icons.warning,
            onPressed: () => _handleDelete(force: true),
            colorScheme: colorScheme,
            isPrimary: true,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(DeleteWorktreeResult.cancelled),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onErrorContainer,
              side: BorderSide(color: colorScheme.onErrorContainer.withValues(alpha: 0.5)),
            ),
            child: const Text('Abort'),
          ),
        ]);
        break;

      case _ActionState.needsForce:
        buttons.addAll([
          _ActionButton(
            key: DeleteWorktreeDialogKeys.forceDeleteButton,
            label: 'Force Delete',
            icon: Icons.warning,
            onPressed: () => _handleDelete(force: true),
            colorScheme: colorScheme,
            isPrimary: true,
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(DeleteWorktreeResult.cancelled),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onErrorContainer,
              side: BorderSide(color: colorScheme.onErrorContainer.withValues(alpha: 0.5)),
            ),
            child: const Text('Abort'),
          ),
        ]);
        break;

      case _ActionState.failed:
        buttons.add(
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(DeleteWorktreeResult.failed),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onErrorContainer,
              side: BorderSide(
                color: colorScheme.onErrorContainer.withValues(alpha: 0.5),
              ),
            ),
            child: const Text('Close'),
          ),
        );
        break;

      case _ActionState.checking:
      case _ActionState.processing:
      case _ActionState.deleting:
      case _ActionState.committing:
      case _ActionState.complete:
        // No action buttons, show processing indicator
        buttons.add(
          SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _actionState == _ActionState.complete
                      ? 'Complete'
                      : 'Processing...',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
        break;
    }

    // Always add cancel button (except when complete or when Abort is shown)
    if (_actionState != _ActionState.complete &&
        _actionState != _ActionState.hasUnmergedCommits &&
        _actionState != _ActionState.upstreamWarning &&
        _actionState != _ActionState.needsForce &&
        _actionState != _ActionState.failed) {
      buttons.addAll([
        const Spacer(),
        TextButton(
          key: DeleteWorktreeDialogKeys.cancelButton,
          onPressed: _actionState == _ActionState.deleting ||
                  _actionState == _ActionState.committing
              ? null
              : () => Navigator.of(context).pop(DeleteWorktreeResult.cancelled),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onErrorContainer,
          ),
          child: const Text('Cancel'),
        ),
      ]);
    }

    return Row(children: buttons);
  }

  Widget _buildLogList(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListView.builder(
        key: DeleteWorktreeDialogKeys.logList,
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _log.length,
        itemBuilder: (context, index) {
          final entry = _log[index];
          return _LogEntryWidget(entry: entry, colorScheme: colorScheme);
        },
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    // Show note about stash recovery if we stashed
    final hasStashed = _log.any((e) =>
        e.message.contains('stashed') && e.status == LogEntryStatus.success);

    if (!hasStashed) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Stashed changes can be recovered with `git stash pop`',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single log entry widget.
class _LogEntryWidget extends StatelessWidget {
  const _LogEntryWidget({
    required this.entry,
    required this.colorScheme,
  });

  final LogEntry entry;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIcon(),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: _getTextColor(),
                    fontWeight: entry.status == LogEntryStatus.running
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
                if (entry.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.detail!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    switch (entry.status) {
      case LogEntryStatus.running:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        );
      case LogEntryStatus.success:
        return Icon(
          Icons.check_circle,
          size: 16,
          color: Colors.green,
        );
      case LogEntryStatus.warning:
        return Icon(
          Icons.warning_amber,
          size: 16,
          color: Colors.orange,
        );
      case LogEntryStatus.error:
        return Icon(
          Icons.error,
          size: 16,
          color: Colors.red,
        );
    }
  }

  Color _getTextColor() {
    switch (entry.status) {
      case LogEntryStatus.running:
        return colorScheme.onSurface;
      case LogEntryStatus.success:
        return colorScheme.onSurface;
      case LogEntryStatus.warning:
        return Colors.orange.shade800;
      case LogEntryStatus.error:
        return Colors.red.shade700;
    }
  }
}

/// An action button in the dialog header.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.colorScheme,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final ColorScheme colorScheme;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.error,
          foregroundColor: colorScheme.onError,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onErrorContainer,
        side: BorderSide(color: colorScheme.onErrorContainer.withValues(alpha: 0.5)),
      ),
    );
  }
}
