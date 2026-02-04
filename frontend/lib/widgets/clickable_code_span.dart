import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/runtime_config.dart';

/// Returns true if [text] looks like it could be a file path.
///
/// Detection rules:
/// - Contains a forward slash (e.g., `src/main.dart`, `/usr/bin`)
/// - Starts with `~` (home directory reference)
/// - Starts with a backslash (Windows-style path)
/// - Matches a Windows drive letter pattern (e.g., `C:\`)
/// - Starts with `.` (e.g., `.gitignore`)
/// - Has a file extension (e.g., `test.txt`, `foo.bar.baz`)
///
/// Exclusions:
/// - URLs (contain `://`)
/// - Bare identifiers without slashes or dots (e.g., `className`)
/// - Empty strings
bool looksLikeFilePath(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;

  // URLs are not file paths
  if (trimmed.contains('://')) return false;

  // Contains a forward slash -> likely a path
  if (trimmed.contains('/')) return true;

  // Starts with ~ -> home directory
  if (trimmed.startsWith('~')) return true;

  // Starts with backslash -> Windows absolute
  if (trimmed.startsWith(r'\')) return true;

  // Windows drive letter (e.g., C:\)
  if (RegExp(r'^[A-Za-z]:[\\\/]').hasMatch(trimmed)) return true;

  // Starts with dot -> dotfile like .gitignore
  if (trimmed.startsWith('.')) return true;

  // Has a file extension (word chars after a dot at end)
  if (RegExp(r'\.\w+$').hasMatch(trimmed)) return true;

  return false;
}

/// Resolves [text] to an absolute file path.
///
/// - `~` prefix → expands to home directory
/// - `/`, `\`, or drive letter prefix → returned as-is (already absolute)
/// - Otherwise → prepended with [projectDir]
String resolveFilePath(String text, String? projectDir) {
  final trimmed = text.trim();

  // ~ prefix -> relative to home directory
  if (trimmed.startsWith('~')) {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return trimmed.replaceFirst('~', home);
  }

  // Absolute path (Unix or Windows)
  if (trimmed.startsWith('/') ||
      trimmed.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:[\\\/]').hasMatch(trimmed)) {
    return trimmed;
  }

  // Relative path -> resolve against projectDir
  if (projectDir != null && projectDir.isNotEmpty) {
    final base = projectDir.endsWith('/') ? projectDir : '$projectDir/';
    return '$base$trimmed';
  }

  // No projectDir, return as-is
  return trimmed;
}

/// A backtick code span that checks if the text is a file path on hover
/// and becomes clickable if the file exists.
///
/// Used as the return widget from [makeHighlightBuilder] in all
/// `GptMarkdown.highlightBuilder` callbacks.
class ClickableCodeSpan extends StatefulWidget {
  const ClickableCodeSpan({
    super.key,
    required this.text,
    required this.baseStyle,
    required this.backgroundColor,
    this.projectDir,
    this.fileExistsCheck,
  });

  /// The backtick text content.
  final String text;

  /// The monospace text style to use.
  final TextStyle baseStyle;

  /// Background color for the code span container.
  final Color backgroundColor;

  /// The worktree root for resolving relative paths.
  final String? projectDir;

  /// Optional override for file existence checking (for tests).
  final Future<bool> Function(String path)? fileExistsCheck;

  @override
  State<ClickableCodeSpan> createState() => _ClickableCodeSpanState();
}

class _ClickableCodeSpanState extends State<ClickableCodeSpan> {
  bool _isHovering = false;
  bool? _fileExists;
  String? _resolvedPath;

  Future<bool> _checkFileExists(String path) {
    if (widget.fileExistsCheck != null) {
      return widget.fileExistsCheck!(path);
    }
    return File(path).exists();
  }

  void _onHoverEnter(PointerEnterEvent event) {
    setState(() => _isHovering = true);

    // Already checked, skip
    if (_fileExists != null) return;

    // Not a plausible file path, skip
    if (!looksLikeFilePath(widget.text)) return;

    _resolvedPath = resolveFilePath(widget.text, widget.projectDir);

    _checkFileExists(_resolvedPath!).then((exists) {
      if (mounted) {
        setState(() => _fileExists = exists);
      }
    });
  }

  void _onHoverExit(PointerEvent event) {
    setState(() => _isHovering = false);
  }

  void _openFile() {
    if (_resolvedPath == null) return;
    launchUrl(Uri.file(_resolvedPath!));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isClickable = _fileExists == true;

    final textColor =
        isClickable
            ? colorScheme.primary
            : widget.baseStyle.color ?? colorScheme.secondary;

    final decoration =
        isClickable && _isHovering
            ? TextDecoration.underline
            : TextDecoration.none;

    return MouseRegion(
      cursor:
          isClickable
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
      onEnter: _onHoverEnter,
      onExit: _onHoverExit,
      child: GestureDetector(
        onTap: isClickable ? _openFile : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            widget.text,
            style: widget.baseStyle.copyWith(
              color: textColor,
              decoration: decoration,
              decorationColor: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Creates a `highlightBuilder` callback for [GptMarkdown] that supports
/// clickable file paths in backtick spans.
///
/// [projectDir] is used to resolve relative file paths.
/// [defaultColor] overrides the default text color (falls back to
/// `colorScheme.secondary`).
Widget Function(BuildContext, String, TextStyle) makeHighlightBuilder({
  required String? projectDir,
  Color? defaultColor,
}) {
  return (BuildContext context, String text, TextStyle style) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClickableCodeSpan(
      text: text,
      baseStyle: GoogleFonts.getFont(
        RuntimeConfig.instance.monoFontFamily,
        fontSize: (style.fontSize ?? 13) - 1,
        color: defaultColor ?? colorScheme.secondary,
      ),
      backgroundColor: colorScheme.surfaceContainerHighest,
      projectDir: projectDir,
    );
  };
}
