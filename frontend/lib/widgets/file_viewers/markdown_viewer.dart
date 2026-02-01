import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/runtime_config.dart';

/// Displays markdown files with preview/raw toggle.
///
/// This viewer supports two modes:
/// - Preview mode: Renders markdown using GptMarkdown
/// - Raw mode: Shows plain text with monospace font
///
/// Use the [onToggleModeChanged] callback to provide a toggle button
/// in the panel header.
class MarkdownViewer extends StatefulWidget {
  const MarkdownViewer({
    super.key,
    required this.content,
  });

  /// The markdown content to display.
  final String content;

  @override
  State<MarkdownViewer> createState() => MarkdownViewerState();
}

/// Public state class for MarkdownViewer.
///
/// Made public to allow testing of toggle functionality.
class MarkdownViewerState extends State<MarkdownViewer> {

  bool _isPreviewMode = true;

  /// Toggles between preview and raw mode.
  void toggleMode() {
    setState(() {
      _isPreviewMode = !_isPreviewMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: _isPreviewMode
              ? GptMarkdown(
                  widget.content,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface,
                  ),
                  onLinkTap: (url, title) {
                    launchUrl(Uri.parse(url));
                  },
                )
              : Text(
                  widget.content,
                  style: GoogleFonts.getFont(
                    RuntimeConfig.instance.monoFontFamily,
                    fontSize: 13,
                    color: colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
        ),
      ),
    );
  }
}
