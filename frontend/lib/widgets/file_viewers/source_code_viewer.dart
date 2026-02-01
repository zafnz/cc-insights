import 'package:code_highlight_view/code_highlight_view.dart';
import 'package:code_highlight_view/themes/atom-one-dark.dart';
import 'package:code_highlight_view/themes/atom-one-light.dart';
import 'package:flutter/material.dart';

/// Displays source code with syntax highlighting.
///
/// Uses code_highlight_view for syntax highlighting without any container
/// decoration - just the highlighted code filling the available space.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Start with the base theme and override the background to be transparent
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final theme = Map<String, TextStyle>.from(baseTheme);
    // Remove background color so it inherits from the panel
    theme['root'] = const TextStyle(backgroundColor: Colors.transparent);

    return SingleChildScrollView(
      child: CodeHighlightView(
        content,
        language: language,
        theme: theme,
        isSelectable: true,
        padding: const EdgeInsets.all(16),
        textStyle: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          height: 1.5,
        ),
      ),
    );
  }
}
