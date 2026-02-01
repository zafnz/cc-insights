import 'package:flutter/material.dart';

import '../../models/file_content.dart';

/// Displays a message for non-displayable binary files.
///
/// Shows a centered message with file information including name,
/// formatted size, and file type. Used for binary files that cannot
/// be displayed as text or images.
class BinaryFileMessage extends StatelessWidget {
  const BinaryFileMessage({super.key, required this.file});

  /// The binary file content.
  final FileContent file;

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
              Icons.insert_drive_file,
              size: 48,
              color:
                  colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Cannot display binary file',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _FileInfo(file: file),
          ],
        ),
      ),
    );
  }
}

/// Widget displaying file information.
class _FileInfo extends StatelessWidget {
  const _FileInfo({required this.file});

  final FileContent file;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final fileName = file.fileName;
    final fileSize = _formatFileSize(file);
    final fileExtension = _getFileExtension(fileName);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _InfoRow(
          label: 'File',
          value: fileName,
          textTheme: textTheme,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 4),
        _InfoRow(
          label: 'Size',
          value: fileSize,
          textTheme: textTheme,
          colorScheme: colorScheme,
        ),
        if (fileExtension != null) ...[
          const SizedBox(height: 4),
          _InfoRow(
            label: 'Type',
            value: fileExtension,
            textTheme: textTheme,
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }

  /// Formats the file size in human-readable format.
  String _formatFileSize(FileContent file) {
    final bytes = file.binaryContent;
    if (bytes == null) return 'Unknown';

    final size = bytes.length;
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Gets the file extension from the file name.
  String? _getFileExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return null;
    }
    return fileName.substring(lastDot + 1).toUpperCase();
  }
}

/// Widget displaying a single info row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.textTheme,
    required this.colorScheme,
  });

  final String label;
  final String value;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(
              alpha: 0.7,
            ),
          ),
        ),
        Text(
          value,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
