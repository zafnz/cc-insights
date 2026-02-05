import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../config/fonts.dart';
import 'markdown_style_helper.dart';
import '../models/file_content.dart';
import '../services/ask_ai_service.dart';
import '../services/file_system_service.dart';
import '../services/file_type_detector.dart';
import '../services/git_service.dart';
import '../services/runtime_config.dart';
import 'code_line_view.dart';
import 'file_viewers/binary_file_message.dart';
import 'file_viewers/image_viewer.dart';
import 'file_viewers/markdown_viewer.dart';

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
  static const resizeDivider =
      Key('commit_dialog_resize_divider');
  static const commitMessageItem =
      Key('commit_dialog_commit_message_item');
  static const fileContentView =
      Key('commit_dialog_file_content_view');
  static const diffToggle = Key('commit_dialog_diff_toggle');
  static const diffView = Key('commit_dialog_diff_view');
  static const codeLineView = Key('commit_dialog_code_line_view');
}

/// Shows the commit dialog and returns true if a commit was made.
Future<bool> showCommitDialog({
  required BuildContext context,
  required String worktreePath,
  required GitService gitService,
  required AskAiService askAiService,
  required FileSystemService fileSystemService,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CommitDialog(
      worktreePath: worktreePath,
      gitService: gitService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
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
    required this.fileSystemService,
  });

  final String worktreePath;
  final GitService gitService;
  final AskAiService askAiService;
  final FileSystemService fileSystemService;

  @override
  State<CommitDialog> createState() => _CommitDialogState();
}

class _CommitDialogState extends State<CommitDialog>
    with SingleTickerProviderStateMixin {
  // --- Existing state ---
  List<GitFileChange> _files = [];
  final _messageController = TextEditingController();
  bool _isLoadingFiles = true;
  bool _isGeneratingMessage = false;
  bool _userHasEdited = false;
  String? _cachedAiMessage;
  String? _error;
  bool _isCommitting = false;
  late TabController _tabController;

  // --- New state for file viewing ---
  /// Selected item index: 0 = commit message, 1+ = file at index-1.
  int _selectedIndex = 0;

  /// Width of the left panel (resizable).
  double _leftPanelWidth = 280.0;
  static const double _minLeftPanelWidth = 180.0;
  static const double _maxLeftPanelWidth = 500.0;

  /// Loaded file content for the selected file.
  FileContent? _selectedFileContent;

  /// Whether we're currently loading file content.
  bool _isLoadingFileContent = false;

  /// Whether to show diff view vs file content view.
  bool _showDiff = false;

  /// The content of the file at HEAD (old version for diff).
  String? _oldFileContent;

  /// The current working tree content (new version for diff).
  String? _currentFileContent;

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
      final files =
          await widget.gitService.getChangedFiles(widget.worktreePath);
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoadingFiles = false;
      });
      // Start AI generation after files are loaded (if enabled)
      if (RuntimeConfig.instance.aiAssistanceEnabled) {
        _generateAiMessage();
      }
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

    final prompt =
        '''Read the following files and generate a git commit message.

Output the commit message between markers like this:
===BEGIN===
Short summary line (50-72 chars)

- Bullet point explaining a change
- Another bullet point
===END===

Files to commit:
$fileList''';

    try {
      final result = await widget.askAiService.ask(
        prompt: prompt,
        workingDirectory: widget.worktreePath,
        model: RuntimeConfig.instance.aiAssistanceModel,
        allowedTools: ['Bash(git:*)', 'Read'],
        maxTurns: 5,
        timeoutSeconds: 120,
      );

      if (!mounted) return;

      if (result != null && !result.isError) {
        final rawMessage = result.result?.trim() ?? '';
        // Extract message between ===BEGIN=== and ===END=== markers
        final message = _extractCommitMessage(rawMessage);
        if (message.isNotEmpty) {
          // Cache the message
          _cachedAiMessage = message;

          // Only update text field if user hasn't started typing
          if (!_userHasEdited) {
            _messageController.text = message;
          }
        } else {
          setState(() {
            _error = 'AI returned an empty response';
          });
        }
      } else {
        setState(() {
          _error =
              'AI generation failed: ${result?.result ?? 'Unknown error'}';
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

  /// Extracts the commit message from between ===BEGIN=== and ===END===
  /// markers. Falls back to the raw message if markers are not found.
  String _extractCommitMessage(String raw) {
    const beginMarker = '===BEGIN===';
    const endMarker = '===END===';

    final beginIndex = raw.indexOf(beginMarker);
    final endIndex = raw.indexOf(endMarker);

    if (beginIndex != -1 && endIndex != -1 && endIndex > beginIndex) {
      return raw
          .substring(beginIndex + beginMarker.length, endIndex)
          .trim();
    }

    // Fallback: return the raw message trimmed
    return raw.trim();
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

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      // Try to restore state
      try {
        await widget.gitService.resetIndex(widget.worktreePath);
      } catch (_) {
        // Ignore reset errors
      }

      if (!mounted) return;
      setState(() {
        _error = 'Commit failed: $e';
        _isCommitting = false;
      });
    }
  }

  // --- Selection & file loading ---

  void _onItemSelected(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _showDiff = true;
      _selectedFileContent = null;
      _oldFileContent = null;
      _currentFileContent = null;
    });
    if (index > 0) {
      _loadSelectedFileContent(_files[index - 1]);
    }
  }

  Future<void> _loadSelectedFileContent(GitFileChange file) async {
    setState(() => _isLoadingFileContent = true);
    try {
      final fullPath = '${widget.worktreePath}/${file.path}';

      // Load current file content for viewing
      FileContent content;
      if (file.status == GitFileStatus.deleted) {
        // File doesn't exist on disk - create an error-like content
        content = FileContent.error(
          path: fullPath,
          message: 'File has been deleted',
        );
      } else {
        content = await widget.fileSystemService.readFile(fullPath);
      }

      // Load old and current text for diff
      String? oldContent;
      String? currentContent;

      if (file.status == GitFileStatus.untracked ||
          file.status == GitFileStatus.added) {
        oldContent = '';
        currentContent = content.textContent ?? '';
      } else if (file.status == GitFileStatus.deleted) {
        oldContent = await widget.gitService.getFileAtRef(
          widget.worktreePath,
          file.path,
          'HEAD',
        );
        currentContent = '';
      } else {
        // Modified, renamed, copied
        oldContent = await widget.gitService.getFileAtRef(
          widget.worktreePath,
          file.path,
          'HEAD',
        );
        currentContent = content.textContent;
      }

      if (!mounted) return;
      setState(() {
        _selectedFileContent = content;
        _oldFileContent = oldContent;
        _currentFileContent = currentContent;
        _isLoadingFileContent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _selectedFileContent = FileContent.error(
          path: '${widget.worktreePath}/${file.path}',
          message: 'Failed to load: $e',
        );
        _isLoadingFileContent = false;
      });
    }
  }

  // --- Status helpers ---

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

  // --- Build methods ---

  /// Handle keyboard shortcut for commit (Cmd+Enter on Mac, Ctrl+Enter elsewhere)
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isMac = Platform.isMacOS;
    final isModifierPressed = isMac
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;

    if (isModifierPressed && event.logicalKey == LogicalKeyboardKey.enter) {
      final canCommit =
          _messageController.text.trim().isNotEmpty && !_isCommitting;
      if (canCommit) {
        _commit();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    // Dialog sizing - responsive but with reasonable bounds
    final dialogWidth = (size.width * 0.8).clamp(600.0, 1200.0);
    final dialogHeight = (size.height * 0.8).clamp(400.0, 800.0);

    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
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
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
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
          // AI regenerate button (hidden when AI assistance is disabled)
          if (RuntimeConfig.instance.aiAssistanceEnabled)
            Tooltip(
              message: 'Generate commit message with AI',
              child: IconButton(
                key: CommitDialogKeys.aiButton,
                icon: Icon(
                  Icons.auto_awesome,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
                onPressed: _isGeneratingMessage || _isCommitting
                    ? null
                    : _triggerAiRegenerate,
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
        // Left panel: File list (resizable width)
        SizedBox(
          width: _leftPanelWidth,
          child: _buildFileList(colorScheme),
        ),
        // Resizable divider
        _buildResizableDivider(colorScheme),
        // Right panel: Content area
        Expanded(
          child: _buildRightPanel(colorScheme),
        ),
      ],
    );
  }

  Widget _buildResizableDivider(ColorScheme colorScheme) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: CommitDialogKeys.resizeDivider,
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _leftPanelWidth = (_leftPanelWidth + details.delta.dx)
                .clamp(_minLeftPanelWidth, _maxLeftPanelWidth);
          });
        },
        child: Container(
          width: 4,
          color: colorScheme.outlineVariant,
        ),
      ),
    );
  }

  Widget _buildFileList(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // File list with commit message item first
        Expanded(
          child: _isLoadingFiles
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  key: CommitDialogKeys.fileList,
                  itemCount: _files.length + 1, // +1 for commit message
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildCommitMessageItem(colorScheme);
                    }
                    final file = _files[index - 1];
                    return _buildFileItem(
                        file, colorScheme, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCommitMessageItem(ColorScheme colorScheme) {
    final isSelected = _selectedIndex == 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: CommitDialogKeys.commitMessageItem,
          onTap: () => _onItemSelected(0),
          child: Container(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : null,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.edit_note,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Commit Message',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Section divider with file count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Divider(
                  height: 1,
                  color: colorScheme.outlineVariant,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  'Files (${_files.length})',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
              Expanded(
                child: Divider(
                  height: 1,
                  color: colorScheme.outlineVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileItem(
    GitFileChange file,
    ColorScheme colorScheme,
    int index,
  ) {
    final isSelected = _selectedIndex == index;
    final statusColor = _statusColor(file.status, colorScheme);

    return InkWell(
      onTap: () => _onItemSelected(index),
      child: Container(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.12)
            : null,
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Staged indicator
            if (file.isStaged)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
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
      ),
    );
  }

  // --- Right panel ---

  Widget _buildRightPanel(ColorScheme colorScheme) {
    if (_selectedIndex == 0) {
      return _buildMessageEditor(colorScheme);
    }
    return _buildFileViewer(colorScheme);
  }

  Widget _buildFileViewer(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar with file name and diff toggle
        _buildFileViewerToolbar(colorScheme),
        Divider(height: 1, color: colorScheme.outlineVariant),
        // Content
        Expanded(
          key: CommitDialogKeys.fileContentView,
          child: _buildFileViewerContent(colorScheme),
        ),
      ],
    );
  }

  Widget _buildFileViewerToolbar(ColorScheme colorScheme) {
    final file = _files[_selectedIndex - 1];
    final canShowDiff = _selectedFileContent != null &&
        !_selectedFileContent!.isError &&
        _oldFileContent != null;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color:
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
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
          if (canShowDiff)
            IconButton(
              key: CommitDialogKeys.diffToggle,
              icon: Icon(
                _showDiff ? Icons.description : Icons.difference,
                size: 18,
              ),
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: _showDiff
                  ? 'Show file content'
                  : 'Show diff',
              onPressed: () {
                setState(() => _showDiff = !_showDiff);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFileViewerContent(ColorScheme colorScheme) {
    if (_isLoadingFileContent) {
      return const Center(child: CircularProgressIndicator());
    }

    final content = _selectedFileContent;
    if (content == null) {
      return Center(
        child: Text(
          'Select a file to view',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    // For non-text types, use specialized viewers
    if (content.type == FileContentType.image) {
      return ImageViewer(path: content.path);
    }
    if (content.type == FileContentType.binary) {
      return BinaryFileMessage(file: content);
    }
    if (content.type == FileContentType.markdown && !_showDiff) {
      final text = content.textContent;
      if (text == null) return _noContentMessage();
      return MarkdownViewer(content: text);
    }

    if (content.isError && !_showDiff) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              content.error ?? 'Unknown error',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Detect language for syntax highlighting
    final language = _detectLanguage(content);

    if (_showDiff) {
      return CodeLineView(
        key: CommitDialogKeys.diffView,
        source: _currentFileContent ?? '',
        oldSource: _oldFileContent ?? '',
        isDiff: true,
        language: language,
      );
    }

    // File view mode
    final text = content.textContent;
    if (text == null) return _noContentMessage();

    return CodeLineView(
      key: CommitDialogKeys.codeLineView,
      source: text,
      language: language,
    );
  }

  /// Detects the syntax highlighting language for the given content.
  String? _detectLanguage(FileContent content) {
    switch (content.type) {
      case FileContentType.dart:
        return 'dart';
      case FileContentType.json:
        return 'json';
      case FileContentType.markdown:
        return 'markdown';
      case FileContentType.plaintext:
        final ext =
            FileTypeDetector.getFileExtension(content.path);
        if (ext != null) {
          return FileTypeDetector.getLanguageFromExtension(ext);
        }
        return null;
      default:
        return null;
    }
  }

  Widget _noContentMessage() {
    return Center(
      child: Text(
        'No content available',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // --- Message editor (unchanged) ---

  Widget _buildMessageEditor(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs
        Container(
          color: colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.3),
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
                color: colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                    color: colorScheme.primary, width: 2),
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
    // Use ListenableBuilder to rebuild when text changes
    return ListenableBuilder(
      listenable: _messageController,
      builder: (context, _) {
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
                : MarkdownBody(
                    data: message,
                    styleSheet: buildMarkdownStyleSheet(
                      context,
                      fontSize: 13,
                    ),
                  ),
          ),
        );
      },
    );
  }

  // --- Error and footer ---

  Widget _buildError(ColorScheme colorScheme) {
    return Container(
      key: CommitDialogKeys.errorMessage,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            constraints:
                const BoxConstraints(minWidth: 24, minHeight: 24),
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
        color: colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: CommitDialogKeys.cancelButton,
            onPressed: _isCommitting
                ? null
                : () => Navigator.of(context).pop(false),
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Commit'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          Platform.isMacOS ? '\u{2318}\u{21A9}' : 'Ctrl+\u{21A9}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
