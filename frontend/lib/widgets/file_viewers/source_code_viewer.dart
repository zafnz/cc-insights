import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Displays source code with syntax highlighting.
///
/// This viewer wraps the content in a code fence for GptMarkdown,
/// which provides syntax highlighting based on the specified language.
/// Supports common languages like dart, json, yaml, javascript, etc.
class SourceCodeViewer extends StatelessWidget {
  const SourceCodeViewer({
    super.key,
    required this.content,
    required this.language,
  });

  /// The source code content to display.
  final String content;

  /// The programming language for syntax highlighting.
  ///
  /// Common values: dart, json, yaml, xml, html, css, javascript,
  /// python, java, c, cpp, rust, go, typescript, etc.
  final String language;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Wrap content in code fence for syntax highlighting
    final markdownContent = '```$language\n$content\n```';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: GptMarkdown(
            markdownContent,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
