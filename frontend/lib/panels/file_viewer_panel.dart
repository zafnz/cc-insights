import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/file_content.dart';
import '../services/file_type_detector.dart';
import '../state/file_manager_state.dart';
import '../widgets/file_viewers/binary_file_message.dart';
import '../widgets/file_viewers/image_viewer.dart';
import '../widgets/file_viewers/markdown_viewer.dart';
import '../widgets/file_viewers/plaintext_viewer.dart';
import '../widgets/file_viewers/source_code_viewer.dart';
import 'panel_wrapper.dart';

/// File viewer panel - displays file contents based on type.
///
/// This panel shows the content of the selected file in the appropriate
/// viewer based on its [FileContentType]. It listens to [FileManagerState]
/// for file content updates and handles loading and error states.
///
/// Supported content types:
/// - Plaintext: PlaintextFileViewer
/// - Dart, JSON: SourceCodeViewer with syntax highlighting
/// - Markdown: MarkdownViewer with preview/raw toggle
/// - Images: ImageViewer with zoom/pan
/// - Binary: BinaryFileMessage
/// - Error: Error message display
class FileViewerPanel extends StatefulWidget {
  const FileViewerPanel({super.key});

  @override
  State<FileViewerPanel> createState() => _FileViewerPanelState();
}

class _FileViewerPanelState extends State<FileViewerPanel> {
  /// GlobalKey to access MarkdownViewer state for toggle.
  final GlobalKey<MarkdownViewerState> _markdownViewerKey =
      GlobalKey<MarkdownViewerState>();

  @override
  Widget build(BuildContext context) {
    final fileManagerState = context.watch<FileManagerState>();
    final fileContent = fileManagerState.fileContent;
    final isLoadingFile = fileManagerState.isLoadingFile;

    // Determine header title - show file name and type
    String title = 'File Viewer';
    if (fileContent != null) {
      final typeLabel = _getFileTypeLabel(fileContent.type);
      title = '${fileContent.fileName} ($typeLabel)';
    }

    return PanelWrapper(
      title: title,
      icon: Icons.description,
      trailing: _buildTrailingWidgets(context, fileContent),
      child: _FileViewerContent(
        fileContent: fileContent,
        isLoadingFile: isLoadingFile,
        markdownViewerKey: _markdownViewerKey,
      ),
    );
  }

  /// Returns a human-readable label for the file type.
  String _getFileTypeLabel(FileContentType type) {
    switch (type) {
      case FileContentType.plaintext:
        return 'Text';
      case FileContentType.dart:
        return 'Dart';
      case FileContentType.json:
        return 'JSON';
      case FileContentType.markdown:
        return 'Markdown';
      case FileContentType.image:
        return 'Image';
      case FileContentType.binary:
        return 'Binary';
      case FileContentType.error:
        return 'Error';
    }
  }

  /// Builds trailing widgets for the panel header based on file type.
  ///
  /// Shows copy button for text content, toggle for markdown, and open in
  /// external editor button.
  Widget? _buildTrailingWidgets(BuildContext context, FileContent? fileContent) {
    if (fileContent == null || fileContent.isError) {
      return null;
    }

    final widgets = <Widget>[];

    // Copy button for text content
    if (fileContent.isText) {
      widgets.add(
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Copy to clipboard',
          onPressed: () {
            final text = fileContent.textContent;
            if (text != null) {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
        ),
      );
    }

    // Toggle button for markdown preview/raw
    if (fileContent.type == FileContentType.markdown) {
      widgets.add(
        IconButton(
          icon: const Icon(Icons.preview, size: 18),
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Toggle Preview/Raw',
          onPressed: () {
            _markdownViewerKey.currentState?.toggleMode();
          },
        ),
      );
    }

    // Open in external editor button
    widgets.add(
      IconButton(
        icon: const Icon(Icons.open_in_new, size: 18),
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        tooltip: 'Open in External Editor',
        onPressed: () => _openInExternalEditor(context, fileContent.path),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// Opens the file in the system's default external editor.
  Future<void> _openInExternalEditor(BuildContext context, String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('start', ['', path], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open file: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

/// Content of the file viewer panel.
///
/// Switches between different states and viewers based on the current
/// [fileContent] and [isLoadingFile] status.
class _FileViewerContent extends StatelessWidget {
  const _FileViewerContent({
    required this.fileContent,
    required this.isLoadingFile,
    required this.markdownViewerKey,
  });

  final FileContent? fileContent;
  final bool isLoadingFile;
  final GlobalKey<MarkdownViewerState> markdownViewerKey;

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (isLoadingFile) {
      return const _LoadingIndicator();
    }

    // No file selected
    final content = fileContent;
    if (content == null) {
      return const _NoFileSelected();
    }

    // Error state
    if (content.type == FileContentType.error) {
      return _ErrorMessage(
        message: content.error ?? 'Unknown error',
      );
    }

    // File content - switch based on type
    return _buildContentViewer(context, content);
  }

  /// Builds the appropriate viewer widget for the file content type.
  ///
  /// Switches between different viewers based on the file type:
  /// - plaintext → PlaintextFileViewer
  /// - dart → SourceCodeViewer (language: "dart")
  /// - json → SourceCodeViewer (language: "json")
  /// - markdown → MarkdownViewer
  /// - image → ImageViewer
  /// - binary → BinaryFileMessage
  /// - error → Error message display
  Widget _buildContentViewer(
    BuildContext context,
    FileContent content,
  ) {
    switch (content.type) {
      case FileContentType.plaintext:
        final textContent = content.textContent;
        if (textContent == null) {
          return const _ErrorMessage(
            message: 'No content available',
          );
        }
        // Check if there's a known syntax highlighting language for this file
        final ext = FileTypeDetector.getFileExtension(content.path);
        final language = ext != null
            ? FileTypeDetector.getLanguageFromExtension(ext)
            : null;
        if (language != null) {
          return SourceCodeViewer(
            content: textContent,
            language: language,
          );
        }
        return PlaintextFileViewer(content: textContent);

      case FileContentType.dart:
        final textContent = content.textContent;
        if (textContent == null) {
          return const _ErrorMessage(
            message: 'No content available',
          );
        }
        return SourceCodeViewer(
          content: textContent,
          language: 'dart',
        );

      case FileContentType.json:
        final textContent = content.textContent;
        if (textContent == null) {
          return const _ErrorMessage(
            message: 'No content available',
          );
        }
        return SourceCodeViewer(
          content: textContent,
          language: 'json',
        );

      case FileContentType.markdown:
        final textContent = content.textContent;
        if (textContent == null) {
          return const _ErrorMessage(
            message: 'No content available',
          );
        }
        return MarkdownViewer(
          key: markdownViewerKey,
          content: textContent,
        );

      case FileContentType.image:
        return ImageViewer(path: content.path);

      case FileContentType.binary:
        return BinaryFileMessage(file: content);

      case FileContentType.error:
        // Already handled above
        return _ErrorMessage(
          message: content.error ?? 'Unknown error',
        );
    }
  }
}

/// Widget shown when no file is selected.
class _NoFileSelected extends StatelessWidget {
  const _NoFileSelected();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a file to view',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget shown while a file is loading.
class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading file...',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget shown when there was an error loading the file.
class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load file',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

