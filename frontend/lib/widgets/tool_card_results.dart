import 'dart:convert' show base64Decode;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'markdown_style_helper.dart';

/// Renders Task tool result with structured prompt and markdown content.
class TaskResultWidget extends StatelessWidget {
  final Map<String, dynamic> result;

  const TaskResultWidget({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    final prompt = result['prompt'] as String? ?? '';
    final contentBlocks = result['content'];
    final resultText = _extractResultText(contentBlocks);

    return ClickToScrollContainer(
      maxHeight: 400,
      backgroundColor: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Task section header
          const SectionDivider(label: 'Task'),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              prompt,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // Result section header
          if (resultText.isNotEmpty) ...[
            const SectionDivider(label: 'Result'),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectionArea(
                child: MarkdownBody(
                  data: resultText,
                  styleSheet: buildMarkdownStyleSheet(
                    context,
                    fontSize: 12,
                  ),
                  onTapLink: (text, href, title) {
                    if (href != null) launchUrl(Uri.parse(href));
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _extractResultText(dynamic contentBlocks) {
    if (contentBlocks is List) {
      final texts = <String>[];
      for (final item in contentBlocks) {
        if (item is Map && item['type'] == 'text') {
          final text = item['text'] as String?;
          if (text != null) texts.add(text);
        }
      }
      return texts.join('\n\n');
    }
    if (contentBlocks is String) return contentBlocks;
    return '';
  }
}

/// Section divider header used within Task result widget.
class SectionDivider extends StatelessWidget {
  final String label;

  const SectionDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// Renders TodoWrite result.
class TodoWriteResultWidget extends StatelessWidget {
  final Map<String, dynamic> result;

  const TodoWriteResultWidget({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final newTodos = result['newTodos'] as List?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todos Updated:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        if (newTodos != null)
          ...newTodos.map((todo) {
            final todoMap = todo as Map<String, dynamic>;
            final content = todoMap['content'] as String? ?? '';
            final status = todoMap['status'] as String? ?? 'pending';

            Color statusColor;
            IconData statusIcon;
            switch (status) {
              case 'completed':
                statusColor = Colors.green;
                statusIcon = Icons.check_circle;
              case 'in_progress':
                statusColor = Colors.blue;
                statusIcon = Icons.pending;
              default:
                statusColor = Colors.grey;
                statusIcon = Icons.radio_button_unchecked;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
                        decoration: status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Image result widget for Read tool
// -----------------------------------------------------------------------------

/// Renders an image result from the Read tool.
///
/// Supports two formats:
/// 1. Map format: `{type: image, file: {base64: "..."}}` (from CC-Insights SDK)
/// 2. List format: `[{type: image, source: {type: base64, data: "..."}}]` (Anthropic API)
class ImageResultWidget extends StatelessWidget {
  final dynamic content;

  const ImageResultWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    String? base64Data;
    String mediaType = 'image/png';
    int? originalSize;

    // Format 1: Map with {type: image, file: {base64: "..."}}
    if (content is Map) {
      final file = content['file'] as Map<String, dynamic>?;
      if (file != null) {
        base64Data = file['base64'] as String?;
        mediaType = content['type'] as String? ?? 'image/png';
        originalSize = content['originalSize'] as int?;
      }
    }
    // Format 2: List with [{type: image, source: {type: base64, data: "..."}}]
    else if (content is List) {
      final imageBlock = (content as List).firstWhere(
        (block) => block is Map && block['type'] == 'image',
        orElse: () => null,
      );
      if (imageBlock != null) {
        final source = imageBlock['source'] as Map<String, dynamic>?;
        if (source != null) {
          base64Data = source['data'] as String?;
          mediaType = source['media_type'] as String? ?? 'image/png';
          originalSize = imageBlock['originalSize'] as int?;
        }
      }
    }

    if (base64Data == null || base64Data.isEmpty) {
      return const SizedBox.shrink();
    }

    // Decode the base64 image data
    final imageBytes = base64Decode(base64Data);

    final sizeInfo = originalSize != null ? _formatFileSize(originalSize) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Image Preview:',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              mediaType,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
            if (sizeInfo != null) ...[
              const SizedBox(width: 8),
              Text(
                sizeInfo,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image,
                        size: 32,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Formats file size in human-readable format.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Checks if a tool result contains image content.
///
/// Supports two formats:
/// 1. Map format: `{type: image, file: {base64: "..."}}` (from CC-Insights SDK)
/// 2. List format: `[{type: image, source: {type: base64, data: "..."}}]` (Anthropic API)
bool isImageResult(dynamic result) {
  // Format 1: Map with type: image and file.base64
  if (result is Map) {
    if (result['type'] == 'image') {
      final file = result['file'];
      if (file is Map && file['base64'] != null) {
        return true;
      }
    }
  }

  // Format 2: List containing an image block
  if (result is List) {
    return result.any((block) {
      if (block is! Map) return false;
      if (block['type'] != 'image') return false;
      final source = block['source'];
      if (source is! Map) return false;
      return source['type'] == 'base64' && source['data'] != null;
    });
  }

  return false;
}
