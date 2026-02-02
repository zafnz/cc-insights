import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../config/fonts.dart';
import '../services/ask_ai_service.dart';
import '../services/git_service.dart';

/// Keys for testing CommitDialog widgets.
class CommitDialogKeys {
  CommitDialogKeys._();

  static const dialog = Key('commit_dialog');
  static const fileList = Key('commit_dialog_file_list');
  static const messageField = Key('commit_dialog_message_field');
  static const editTab = Key('commit_dialog_edit_tab');
  static const previewTab = Key('commit_dialog_preview_tab');
  static const aiButton = Key('commit_dialog_ai_button');
  static const commitButton = Key('commit_dialog_commit_button');
  static const cancelButton = Key('commit_dialog_cancel_button');
  static const spinner = Key('commit_dialog_spinner');
  static const errorMessage = Key('commit_dialog_error');
}

/// Shows the commit dialog and returns true if a commit was made.
Future<bool> showCommitDialog({
  required BuildContext context,
  required String worktreePath,
  required GitService gitService,
  required AskAiService askAiService,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CommitDialog(
      worktreePath: worktreePath,
      gitService: gitService,
      askAiService: askAiService,
    ),
  );
  return result ?? false;
}

/// Dialog for staging and committing changes.
class CommitDialog extends StatefulWidget {
  const CommitDialog({
    super.key,
    required this.worktreePath,
    required this.gitService,
    required this.askAiService,
  });

  final String worktreePath;
  final GitService gitService;
  final AskAiService askAiService;

  @override
  State<CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<CommitDialog>
    with SingleTickerProviderStateMixin {
  List<GitFileChange> _files = [];
  final _messageController = TextEditingController();
  bool _isLoadingFiles = true;
  bool _isGeneratingMessage = false;
  bool _userHasEdited = false;
  String? _cachedAiMessage;
  String? _error;
  bool _isCommitting = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _messageController.addListener(_onMessageChanged);
    _loadFiles();
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onMessageChanged() {
    if (_messageController.text.isNotEmpty && !_userHasEdited) {
      setState(() {
        _userHasEdited = true;
      });
    }
  }

  Future<void> _loadFiles() async {
    try {
      final files = await widget.gitService.getChangedFiles(widget.worktreePath);
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoadingFiles = false;
      });
      // Start AI generation after files are loaded
      _generateAiMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load changed files: $e';
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _generateAiMessage() async {
    if (_files.isEmpty) return;

    setState(() {
      _isGeneratingMessage = true;
      _error = null;
    });

    // Build the prompt with file list
    final fileList = _files
        .map((f) => '- ${f.path} (${_statusToString(f.status)})')
        .join('\n');

    final prompt = '''Generate a commit message based on all of the work done in these files, there may be multiple changes reflected in this commit. Refer to other files for context if needed. The commit message should be detailed and contain multiple sections. Reply with ONLY the commit message, no other text, or reply ERROR if there is an error.

Files to commit:
$fileList''';

    try {
      final result = await widget.askAiService.ask(
        prompt: prompt,
        workingDirectory: widget.worktreePath,
        model: 'haiku',
        allowedTools: ['Bash(git:*)', 'Read'],
        maxTurns: 5,
        timeoutSeconds: 120,
      );

      if (!mounted) return;

      if (result != null && !result.isError) {
        final message = result.result?.trim() ?? '';
        if (message.isNotEmpty && message != 'ERROR') {
          // Cache the message
          _cachedAiMessage = message;

          // Only update text field if user hasn't started typing
          if (!_userHasEdited) {
            _messageController.text = message;
          }
        } else {
          setState(() {
            _error = 'AI could not generate a commit message';
          });
        }
      } else {
        setState(() {
          _error = 'AI generation failed: ${result?.result ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'AI generation error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingMessage = false;
        });
      }
    }
  }

  Future<void> _triggerAiRegenerate() async {
    // If we have a cached message and user hasn't explicitly regenerated
    if (_cachedAiMessage != null && _cachedAiMessage!.isNotEmpty) {
      setState(() {
        _messageController.text = _cachedAiMessage!;
        _userHasEdited = false;
      });
      return;
    }

    // Otherwise regenerate
    setState(() {
      _userHasEdited = false;
      _messageController.clear();
    });
    await _generateAiMessage();
  }

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _isCommitting = true;
      _error = null;
    });

    try {
      // Stage all changes
      await widget.gitService.stageAll(widget.worktreePath);

      // Commit
      await widget.gitService.commit(widget.worktreePath, message);

      // Log success
      stdout.writeln('Commit successful: ${message.split('\n').first}');

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      stdout.writeln('Commit failed: $e');

      // Try to restore state
      try {
        await widget.gitService.resetIndex(widget.worktreePath);
      } catch (resetError) {
        stdout.writeln('Failed to reset index: $resetError');
      }

      if (!mounted) return;
      setState(() {
        _error = 'Commit failed: $e';
        _isCommitting = false;
      });
    }
  }

  String _statusToString(GitFileStatus status) {
    switch (status) {
      case GitFileStatus.added:
        return 'added';
      case GitFileStatus.modified:
        return 'modified';
      case GitFileStatus.deleted:
        return 'deleted';
      case GitFileStatus.renamed:
        return 'renamed';
      case GitFileStatus.copied:
        return 'copied';
      case GitFileStatus.untracked:
        return 'untracked';
    }
  }

  String _statusToShortString(GitFileStatus status) {
    switch (status) {
      case GitFileStatus.added:
        return 'A';
      case GitFileStatus.modified:
        return 'M';
      case GitFileStatus.deleted:
        return 'D';
      case GitFileStatus.renamed:
        return 'R';
      case GitFileStatus.copied:
        return 'C';
      case GitFileStatus.untracked:
        return '?';
    }
  }

  Color _statusColor(GitFileStatus status, ColorScheme colorScheme) {
    switch (status) {
      case GitFileStatus.added:
      case GitFileStatus.untracked:
        return Colors.green;
      case GitFileStatus.modified:
        return Colors.orange;
      case GitFileStatus.deleted:
        return Colors.red;
      case GitFileStatus.renamed:
      case GitFileStatus.copied:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    // Dialog sizing - responsive but with reasonable bounds
    final dialogWidth = (size.width * 0.8).clamp(600.0, 1200.0);
    final dialogHeight = (size.height * 0.8).clamp(400.0, 800.0);

    return Dialog(
      key: CommitDialogKeys.dialog,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(colorScheme),
            // Content
            Expanded(
              child: _buildContent(colorScheme),
            ),
            // Error message
            if (_error != null) _buildError(colorScheme),
            // Footer
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
        color: colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Commit Changes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          // AI regenerate button
          Tooltip(
            message: 'Generate commit message with AI',
            child: IconButton(
              key: CommitDialogKeys.aiButton,
              icon: Icon(
                Icons.auto_awesome,
                color: colorScheme.onPrimaryContainer,
                size: 20,
              ),
              onPressed:
                  _isGeneratingMessage || _isCommitting ? null : _triggerAiRegenerate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left panel: File list
        SizedBox(
          width: 280,
          child: _buildFileList(colorScheme),
        ),
        // Divider
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        // Right panel: Commit message
        Expanded(
          child: _buildMessageEditor(colorScheme),
        ),
      ],
    );
  }

  Widget _buildFileList(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Files to commit (${_files.length})',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        // File list
        Expanded(
          child: _isLoadingFiles
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  key: CommitDialogKeys.fileList,
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final file = _files[index];
                    return _buildFileItem(file, colorScheme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFileItem(GitFileChange file, ColorScheme colorScheme) {
    final statusColor = _statusColor(file.status, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          // Status badge
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _statusToShortString(file.status),
              style: AppFonts.monoTextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // File path
          Expanded(
            child: Text(
              file.path,
              style: AppFonts.monoTextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Staged indicator
          if (file.isStaged)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'staged',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.green[300],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageEditor(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs
        Container(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: TabBar(
            controller: _tabController,
            tabs: [
              Tab(
                key: CommitDialogKeys.editTab,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 4),
                    Text('Edit'),
                  ],
                ),
              ),
              Tab(
                key: CommitDialogKeys.previewTab,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.preview, size: 16),
                    SizedBox(width: 4),
                    Text('Preview'),
                  ],
                ),
              ),
            ],
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
          ),
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildEditTab(colorScheme),
              _buildPreviewTab(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditTab(ColorScheme colorScheme) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            key: CommitDialogKeys.messageField,
            controller: _messageController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: AppFonts.monoTextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: _isGeneratingMessage
                  ? 'Generating commit message...'
                  : 'Enter your commit message...',
              hintStyle: AppFonts.monoTextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            enabled: !_isCommitting,
          ),
        ),
        // Spinner overlay when generating
        if (_isGeneratingMessage && !_userHasEdited)
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              key: CommitDialogKeys.spinner,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI generating...',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewTab(ColorScheme colorScheme) {
    final message = _messageController.text;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectionArea(
        child: message.isEmpty
            ? Text(
                'No commit message to preview',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            : GptMarkdown(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme) {
    return Container(
      key: CommitDialogKeys.errorMessage,
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
    final canCommit =
        _messageController.text.trim().isNotEmpty && !_isCommitting;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: CommitDialogKeys.cancelButton,
            onPressed: _isCommitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            key: CommitDialogKeys.commitButton,
            onPressed: canCommit ? _commit : null,
            child: _isCommitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Commit'),
          ),
        ],
      ),
    );
  }
}
