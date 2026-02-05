import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart'
    as flutter_markdown;
import 'package:gpt_markdown/gpt_markdown.dart' as gpt_md;
import 'package:url_launcher/url_launcher.dart';

import '../services/runtime_config.dart';
import 'markdown_style_helper.dart';

/// A markdown renderer that can switch between different backends.
///
/// Uses the [RuntimeConfig.markdownBackend] setting to determine which
/// rendering library to use. This allows comparing performance between
/// different markdown implementations.
class MarkdownRenderer extends StatelessWidget {
  const MarkdownRenderer({
    super.key,
    required this.data,
    this.projectDir,
    this.codeColor,
    this.fontSize = 13,
  });

  /// The markdown content to render.
  final String data;

  /// Optional project directory for resolving relative file paths.
  final String? projectDir;

  /// Optional custom color for code spans.
  final Color? codeColor;

  /// Base font size for the markdown content.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RuntimeConfig.instance,
      builder: (context, _) {
        final backend = RuntimeConfig.instance.markdownBackend;

        switch (backend) {
          case MarkdownBackend.gptMarkdown:
            return _buildGptMarkdown(context);
          case MarkdownBackend.flutterMarkdownPlus:
            return _buildFlutterMarkdownPlus(context);
        }
      },
    );
  }

  Widget _buildFlutterMarkdownPlus(BuildContext context) {
    return flutter_markdown.MarkdownBody(
      data: data,
      styleSheet: buildMarkdownStyleSheet(
        context,
        fontSize: fontSize,
        codeColor: codeColor,
      ),
      builders: buildMarkdownBuilders(
        projectDir: projectDir,
        codeColor: codeColor,
      ),
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
    );
  }

  Widget _buildGptMarkdown(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return gpt_md.GptMarkdown(
      data,
      style: TextStyle(
        fontSize: fontSize,
        color: colorScheme.onSurface,
      ),
      onLinkTap: (url, title) {
        launchUrl(Uri.parse(url));
      },
    );
  }
}
