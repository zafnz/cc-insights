import 'package:flutter/material.dart';

import '../services/git_service.dart';
import '../services/runtime_config.dart';
import 'delete_worktree_dialog.dart' show LogEntry, LogEntryStatus;

/// Keys for testing ConflictResolutionDialog widgets.
class ConflictResolutionDialogKeys {
  ConflictResolutionDialogKeys._();

  static const dialog = Key('conflict_resolution_dialog');
  static const logList = Key('conflict_resolution_log_list');
  static const abortButton = Key('conflict_resolution_abort');
  static const resolveWithClaudeButton =
      Key('conflict_resolution_claude');
  static const resolveManuallyButton =
      Key('conflict_resolution_manual');
  static const cancelButton = Key('conflict_resolution_cancel');
}

/// Result of the conflict resolution dialog.
enum ConflictResolutionResult {
  /// Operation completed successfully (no conflicts).
  success,

  /// User chose to abort the operation.
  aborted,

  /// User chose to resolve conflicts with Claude.
  resolveWithClaude,

  /// User chose to resolve conflicts manually.
  resolveManually,

  /// Operation failed with an error.
  failed,
}

/// Shows the conflict resolution dialog for a merge or rebase operation.
///
/// Returns [ConflictResolutionResult] indicating what the user chose.
Future<ConflictResolutionResult> showConflictResolutionDialog({
  required BuildContext context,
  required String worktreePath,
  required String branch,
  required String mainBranch,
  required MergeOperationType operation,
  required GitService gitService,
}) async {
  final result = await showDialog<ConflictResolutionResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ConflictResolutionDialog(
      worktreePath: worktreePath,
      branch: branch,
      mainBranch: mainBranch,
      operation: operation,
      gitService: gitService,
    ),
  );
  return result ?? ConflictResolutionResult.aborted;
}

/// Current action state of the dialog.
enum _ActionState {
  /// Checking for conflicts.
  checking,

  /// No conflicts, performing the operation.
  performing,

  /// Conflicts detected, waiting for user choice.
  hasConflicts,

  /// Performing the operation (after user chose to proceed).
  executing,

  /// Operation complete.
  complete,

  /// Operation failed (error occurred before performing).
  failed,
}

/// Dialog for handling merge/rebase conflict resolution.
class ConflictResolutionDialog extends StatefulWidget {
  const ConflictResolutionDialog({
    super.key,
    required this.worktreePath,
    required this.branch,
    required this.mainBranch,
    required this.operation,
    required this.gitService,
  });

  final String worktreePath;
  final String branch;
  final String mainBranch;
  final MergeOperationType operation;
  final GitService gitService;

  @override
  State<ConflictResolutionDialog> createState() =>
      _ConflictResolutionDialogState();
}

class _ConflictResolutionDialogState
    extends State<ConflictResolutionDialog> {
  final List<LogEntry> _log = [];
  final ScrollController _scrollController = ScrollController();
  _ActionState _actionState = _ActionState.checking;

  String get _operationLabel =>
      widget.operation == MergeOperationType.rebase
          ? 'Rebase'
          : 'Merge';

  String get _operationVerb =>
      widget.operation == MergeOperationType.rebase
          ? 'rebase'
          : 'merge';

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

  void _addLog(
    String message,
    LogEntryStatus status, {
    String? detail,
  }) {
    setState(() {
      _log.add(LogEntry(
        message: message,
        status: status,
        detail: detail,
      ));
    });
    _scrollToBottom();
  }

  void _updateLastLog(
    LogEntryStatus status, {
    String? message,
    String? detail,
  }) {
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
    // Check for uncommitted changes first
    _addLog('Checking working tree...', LogEntryStatus.running);

    try {
      final status =
          await widget.gitService.getStatus(widget.worktreePath);

      if (!mounted) return;

      final uncommitted = status.uncommittedFiles;
      if (uncommitted > 0) {
        _updateLastLog(
          LogEntryStatus.error,
          message: '${widget.branch} has $uncommitted uncommitted '
              '${uncommitted == 1 ? 'change' : 'changes'}',
          detail: 'Commit or stash your changes before '
              '${_operationVerb == 'merge' ? 'merging' : 'rebasing'}',
        );
        setState(() {
          _actionState = _ActionState.failed;
        });
        return;
      }

      _updateLastLog(
        LogEntryStatus.success,
        message: 'Working tree is clean',
      );
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Failed to check status',
        detail: e.toString(),
      );
      setState(() {
        _actionState = _ActionState.failed;
      });
      return;
    }

    // Check for conflicts
    await _checkForConflicts();
  }

  Future<void> _checkForConflicts() async {
    _addLog(
      'Checking for conflicts with ${widget.mainBranch}...',
      LogEntryStatus.running,
    );

    try {
      final willConflict =
          widget.operation == MergeOperationType.rebase
              ? await widget.gitService.wouldRebaseConflict(
                  widget.worktreePath, widget.mainBranch)
              : await widget.gitService.wouldMergeConflict(
                  widget.worktreePath, widget.mainBranch);

      if (!mounted) return;

      if (willConflict) {
        _updateLastLog(
          LogEntryStatus.warning,
          message: 'Conflicts detected',
        );
        setState(() {
          _actionState = _ActionState.hasConflicts;
        });
      } else {
        _updateLastLog(
          LogEntryStatus.success,
          message: 'No conflicts detected',
        );
        // Perform the operation directly
        await _performOperation();
      }
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: 'Failed to check for conflicts',
        detail: e.toString(),
      );
    }
  }

  Future<void> _performOperation() async {
    setState(() {
      _actionState = _ActionState.performing;
    });

    _addLog(
      '${_operationLabel}ing onto ${widget.mainBranch}...',
      LogEntryStatus.running,
    );

    try {
      final result = widget.operation == MergeOperationType.merge
          ? await widget.gitService
              .merge(widget.worktreePath, widget.mainBranch)
          : await widget.gitService
              .rebase(widget.worktreePath, widget.mainBranch);

      if (!mounted) return;

      if (result.error != null) {
        _updateLastLog(
          LogEntryStatus.error,
          message: '$_operationLabel failed',
          detail: result.error,
        );
        return;
      }

      if (result.hasConflicts) {
        _updateLastLog(
          LogEntryStatus.warning,
          message: '$_operationLabel produced conflicts',
        );
        // This shouldn't happen since we checked, but handle it
        setState(() {
          _actionState = _ActionState.hasConflicts;
        });
        return;
      }

      _updateLastLog(
        LogEntryStatus.success,
        message: '$_operationLabel completed successfully',
      );
      setState(() {
        _actionState = _ActionState.complete;
      });

      // Auto-close on success
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .pop(ConflictResolutionResult.success);
        }
      });
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: '$_operationLabel failed',
        detail: e.toString(),
      );
    }
  }

  Future<void> _handleResolveWithClaude() async {
    setState(() {
      _actionState = _ActionState.executing;
    });

    _addLog(
      '${_operationLabel}ing onto ${widget.mainBranch} '
      '(with conflicts)...',
      LogEntryStatus.running,
    );

    try {
      final result = widget.operation == MergeOperationType.merge
          ? await widget.gitService
              .merge(widget.worktreePath, widget.mainBranch)
          : await widget.gitService
              .rebase(widget.worktreePath, widget.mainBranch);

      if (!mounted) return;

      if (result.error != null) {
        _updateLastLog(
          LogEntryStatus.error,
          message: '$_operationLabel failed',
          detail: result.error,
        );
        return;
      }

      _updateLastLog(
        LogEntryStatus.success,
        message: 'Conflicts ready for Claude to resolve',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .pop(ConflictResolutionResult.resolveWithClaude);
        }
      });
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: '$_operationLabel failed',
        detail: e.toString(),
      );
    }
  }

  Future<void> _handleResolveManually() async {
    setState(() {
      _actionState = _ActionState.executing;
    });

    _addLog(
      '${_operationLabel}ing onto ${widget.mainBranch} '
      '(with conflicts)...',
      LogEntryStatus.running,
    );

    try {
      final result = widget.operation == MergeOperationType.merge
          ? await widget.gitService
              .merge(widget.worktreePath, widget.mainBranch)
          : await widget.gitService
              .rebase(widget.worktreePath, widget.mainBranch);

      if (!mounted) return;

      if (result.error != null) {
        _updateLastLog(
          LogEntryStatus.error,
          message: '$_operationLabel failed',
          detail: result.error,
        );
        return;
      }

      _updateLastLog(
        LogEntryStatus.success,
        message: 'Conflicts ready for manual resolution',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context)
              .pop(ConflictResolutionResult.resolveManually);
        }
      });
    } catch (e) {
      if (!mounted) return;
      _updateLastLog(
        LogEntryStatus.error,
        message: '$_operationLabel failed',
        detail: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: ConflictResolutionDialogKeys.dialog,
      child: Container(
        width: 550,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            Expanded(child: _buildLogList(colorScheme)),
            _buildFooter(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.operation == MergeOperationType.rebase
                    ? Icons.low_priority
                    : Icons.merge,
                color: colorScheme.onPrimaryContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_operationLabel from ${widget.mainBranch}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
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
      case _ActionState.hasConflicts:
        final aiEnabled = RuntimeConfig.instance.aiAssistanceEnabled;
        buttons.addAll([
          Flexible(
            child: Tooltip(
              message: aiEnabled
                  ? 'Resolve conflicts with Claude'
                  : 'AI assistance is disabled in settings',
              child: _ActionButton(
                key: ConflictResolutionDialogKeys
                    .resolveWithClaudeButton,
                label: 'Claude',
                icon: Icons.auto_fix_high,
                onPressed: aiEnabled
                    ? _handleResolveWithClaude
                    : null,
                colorScheme: colorScheme,
                isPrimary: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _ActionButton(
              key: ConflictResolutionDialogKeys
                  .resolveManuallyButton,
              label: 'Manually',
              icon: Icons.edit,
              onPressed: _handleResolveManually,
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: OutlinedButton(
              key: ConflictResolutionDialogKeys.abortButton,
              onPressed: () => Navigator.of(context)
                  .pop(ConflictResolutionResult.aborted),
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onPrimaryContainer,
                side: BorderSide(
                  color: colorScheme.onPrimaryContainer
                      .withValues(alpha: 0.5),
                ),
              ),
              child: const Text('Abort'),
            ),
          ),
        ]);

      case _ActionState.checking:
      case _ActionState.performing:
      case _ActionState.executing:
      case _ActionState.complete:
      case _ActionState.failed:
        buttons.add(
          SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_actionState != _ActionState.complete &&
                    _actionState != _ActionState.failed) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  _actionState == _ActionState.complete
                      ? 'Complete'
                      : _actionState == _ActionState.failed
                          ? 'Failed'
                          : 'Processing...',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
    }

    // Cancel button (not shown when conflicts or complete)
    if (_actionState != _ActionState.hasConflicts &&
        _actionState != _ActionState.complete &&
        _actionState != _ActionState.executing) {
      buttons.addAll([
        const Spacer(),
        TextButton(
          key: ConflictResolutionDialogKeys.cancelButton,
          onPressed: _actionState == _ActionState.performing
              ? null
              : () => Navigator.of(context)
                  .pop(ConflictResolutionResult.aborted),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onPrimaryContainer,
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
        key: ConflictResolutionDialogKeys.logList,
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _log.length,
        itemBuilder: (context, index) {
          final entry = _log[index];
          return _LogEntryWidget(
            entry: entry,
            colorScheme: colorScheme,
          );
        },
      ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return const SizedBox.shrink();
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
        return const Icon(
          Icons.check_circle,
          size: 16,
          color: Colors.green,
        );
      case LogEntryStatus.warning:
        return const Icon(
          Icons.warning_amber,
          size: 16,
          color: Colors.orange,
        );
      case LogEntryStatus.error:
        return const Icon(
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
  final VoidCallback? onPressed;
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
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onPrimaryContainer,
        side: BorderSide(
          color:
              colorScheme.onPrimaryContainer.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
