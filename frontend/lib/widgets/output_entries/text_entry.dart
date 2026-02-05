import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/output_entry.dart';
import '../../services/runtime_config.dart';
import '../markdown_renderer.dart';

/// Displays a text output entry from the assistant.
///
/// Supports both regular text and "thinking" content (shown in italic).
/// Regular content is rendered as Markdown using GptMarkdown.
/// Error content is displayed with error styling.
class TextEntryWidget extends StatelessWidget {
  const TextEntryWidget({
    super.key,
    required this.entry,
    this.projectDir,
  });

  final TextOutputEntry entry;

  /// The project directory for resolving relative file paths.
  final String? projectDir;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isThinking = entry.contentType == 'thinking';
    final isError = entry.errorType != null;

    // For error content, display with error styling
    if (isError) {
      return _buildErrorWidget(context, colorScheme);
    }

    // Streaming cursor character appended while content is arriving
    const streamingCursor = '\u258C';

    // For thinking content, use plain text (italic)
    if (isThinking) {
      final displayText = entry.isStreaming
          ? '${entry.text}$streamingCursor'
          : entry.text;
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText(
          displayText,
          style: GoogleFonts.getFont(
            RuntimeConfig.instance.monoFontFamily,
            fontSize: 13,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // For regular content, render as Markdown
    final displayText = entry.isStreaming
        ? '${entry.text}$streamingCursor'
        : entry.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectionArea(
        child: MarkdownRenderer(
          data: displayText,
          projectDir: projectDir,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, ColorScheme colorScheme) {
    final parsed = _parseApiError(entry.text);
    final errorColor = colorScheme.error;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: errorColor, size: 18),
              const SizedBox(width: 8),
              Text(
                parsed.title,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: errorColor,
                ),
              ),
            ],
          ),
          if (parsed.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              parsed.message,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
            ),
          ],
          if (parsed.details.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              parsed.details,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Parses an API error message to extract structured information.
  ///
  /// Handles formats like:
  /// - "API Error: 500 {"type":"error","error":{"type":"api_error","message":"..."},...}"
  /// - Plain error messages
  _ParsedError _parseApiError(String text) {
    // Try to parse "API Error: <code> <json>" format
    final apiErrorMatch =
        RegExp(r'^API Error:\s*(\d+)\s*(.*)$', dotAll: true).firstMatch(text);
    if (apiErrorMatch != null) {
      final statusCode = apiErrorMatch.group(1) ?? '';
      final jsonPart = apiErrorMatch.group(2) ?? '';

      // Try to parse the JSON part
      try {
        final json = jsonDecode(jsonPart) as Map<String, dynamic>;
        final errorObj = json['error'] as Map<String, dynamic>?;
        final errorType = errorObj?['type'] as String? ?? 'error';
        final errorMessage =
            errorObj?['message'] as String? ?? 'Unknown error';
        final requestId = json['request_id'] as String?;

        return _ParsedError(
          title: 'API Error $statusCode',
          message: errorMessage,
          details: requestId != null ? 'Request ID: $requestId' : '',
          errorType: errorType,
        );
      } catch (_) {
        // JSON parsing failed, use the raw text
        return _ParsedError(
          title: 'API Error $statusCode',
          message: jsonPart.isNotEmpty ? jsonPart : 'Unknown error',
          details: '',
        );
      }
    }

    // Fallback: just show the raw error text
    return _ParsedError(
      title: 'Error',
      message: text,
      details: '',
    );
  }
}

/// Holds parsed error information for display.
class _ParsedError {
  final String title;
  final String message;
  final String details;
  final String? errorType;

  _ParsedError({
    required this.title,
    required this.message,
    required this.details,
    this.errorType,
  });
}
