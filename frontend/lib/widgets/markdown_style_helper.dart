import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_config.dart';
import 'clickable_code_span.dart';

/// Builds a [MarkdownStyleSheet] matching the app's theme conventions.
///
/// Uses the configured monospace font for inline code with a background
/// container, and applies the given [fontSize] as the base paragraph size.
MarkdownStyleSheet buildMarkdownStyleSheet(
  BuildContext context, {
  double fontSize = 13,
  Color? codeColor,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final monoFont = RuntimeConfig.instance.monoFontFamily;
  final effectiveCodeColor = codeColor ?? colorScheme.secondary;

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: TextStyle(fontSize: fontSize, color: colorScheme.onSurface),
    code: GoogleFonts.getFont(
      monoFont,
      fontSize: fontSize - 1,
      color: effectiveCodeColor,
      backgroundColor: colorScheme.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    blockquote: TextStyle(
      fontSize: fontSize,
      color: colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      border: Border(
        left: BorderSide(
          color: colorScheme.outline,
          width: 3,
        ),
      ),
    ),
  );
}

/// Returns a builders map with a [ClickableCodeBuilder] for inline code.
///
/// When [projectDir] is non-null, inline code spans will detect file paths
/// and become clickable to open them.
Map<String, MarkdownElementBuilder> buildMarkdownBuilders({
  String? projectDir,
  Color? codeColor,
}) {
  return {
    'code': ClickableCodeBuilder(
      projectDir: projectDir,
      defaultColor: codeColor,
    ),
  };
}
