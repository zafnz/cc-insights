import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/output_entry.dart';
import '../clickable_code_span.dart';

/// Displays a system notification entry.
///
/// Shows feedback from the SDK that doesn't come through normal assistant
/// messages, such as "Unknown skill: clear" for unrecognized slash commands
/// or local command output like /cost and /context.
///
/// Content is rendered as Markdown using GptMarkdown.
class SystemNotificationEntryWidget extends StatelessWidget {
  /// Creates a system notification entry widget.
  const SystemNotificationEntryWidget({
    super.key,
    required this.entry,
    this.projectDir,
  });

  /// The entry data to display.
  final SystemNotificationEntry entry;

  /// The project directory for resolving relative file paths.
  final String? projectDir;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectionArea(
              child: GptMarkdown(
                entry.message,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
                onLinkTap: (url, title) {
                  launchUrl(Uri.parse(url));
                },
                highlightBuilder: makeHighlightBuilder(
                  projectDir: projectDir,
                  defaultColor: colorScheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
