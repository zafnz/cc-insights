import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/output_entry.dart';
import '../../services/runtime_config.dart';

/// Displays a text output entry from the assistant.
///
/// Supports both regular text and "thinking" content (shown in italic).
/// Regular content is rendered as Markdown using GptMarkdown.
class TextEntryWidget extends StatelessWidget {
  const TextEntryWidget({super.key, required this.entry});

  final TextOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isThinking = entry.contentType == 'thinking';

    // For thinking content, use plain text (italic)
    if (isThinking) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SelectableText(
          entry.text,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SelectionArea(
        child: GptMarkdown(
          entry.text,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
          onLinkTap: (url, title) {
            launchUrl(Uri.parse(url));
          },
          highlightBuilder: (context, text, style) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                text,
                style: GoogleFonts.getFont(
                  RuntimeConfig.instance.monoFontFamily,
                  fontSize: (style.fontSize ?? 13) - 1,
                  color: colorScheme.secondary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
