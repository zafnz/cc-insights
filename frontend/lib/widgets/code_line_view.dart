import 'package:code_highlight_view/themes/atom-one-dark.dart';
import 'package:code_highlight_view/themes/atom-one-light.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

import '../config/fonts.dart';

/// A unified code viewer with line numbers and optional diff mode.
///
/// Renders syntax-highlighted code line-by-line with a line number gutter.
/// When [isDiff] is true, computes a unified diff between [oldSource] and
/// [source], showing added/removed/context lines with colored backgrounds
/// and +/- prefix indicators.
///
/// Uses the `highlight` package for syntax highlighting and
/// `diff_match_patch` for diff computation.
class CodeLineView extends StatelessWidget {
  const CodeLineView({
    super.key,
    required this.source,
    this.language,
    this.isDiff = false,
    this.oldSource,
  });

  /// The code to display (the "new" version in diff mode).
  final String source;

  /// Language for syntax highlighting (e.g. 'dart', 'json').
  /// If null, renders as plain text with no highlighting.
  final String? language;

  /// Whether to show diff decorations (+/- prefix, colored backgrounds).
  final bool isDiff;

  /// The original text for diff computation. Required when [isDiff] is true.
  final String? oldSource;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final theme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    final lines = isDiff
        ? _buildDiffLines(theme)
        : _buildPlainLines(theme);

    // Calculate gutter width based on max line number
    final maxLineNum = lines.fold<int>(
      0,
      (max, l) => (l.lineNumber ?? 0) > max ? (l.lineNumber ?? 0) : max,
    );
    final gutterWidth = maxLineNum.toString().length * 8.0 + 24.0;

    final lineNumberColor =
        colorScheme.onSurface.withValues(alpha: 0.4);
    final textColor = colorScheme.onSurface;

    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return _CodeLineRow(
          line: line,
          gutterWidth: gutterWidth,
          showDiffPrefix: isDiff,
          lineNumberColor: lineNumberColor,
          textColor: textColor,
        );
      },
    );
  }

  /// Builds highlighted lines for plain (non-diff) viewing.
  List<_CodeLine> _buildPlainLines(Map<String, TextStyle> theme) {
    final sourceLines = source.split('\n');
    final result = <_CodeLine>[];

    for (int i = 0; i < sourceLines.length; i++) {
      final spans = _highlightLine(sourceLines[i], theme);
      result.add(_CodeLine(
        spans: spans,
        lineNumber: i + 1,
        type: _DiffLineType.context,
      ));
    }

    return result;
  }

  /// Builds highlighted lines for diff viewing.
  List<_CodeLine> _buildDiffLines(Map<String, TextStyle> theme) {
    final old = oldSource ?? '';
    final current = source;

    final diffLines = _computeLineDiffs(old, current);
    final result = <_CodeLine>[];

    for (final dl in diffLines) {
      final spans = _highlightLine(dl.text, theme);
      result.add(_CodeLine(
        spans: spans,
        lineNumber: dl.lineNumber,
        type: dl.type,
      ));
    }

    return result;
  }

  /// Syntax-highlights a single line of code, returning TextSpans.
  List<TextSpan> _highlightLine(
    String line,
    Map<String, TextStyle> theme,
  ) {
    if (language == null || line.isEmpty) {
      return [TextSpan(text: line)];
    }

    try {
      final result = highlight.parse(line, language: language);
      if (result.nodes == null || result.nodes!.isEmpty) {
        return [TextSpan(text: line)];
      }
      return _convertNodes(result.nodes!, theme);
    } catch (_) {
      return [TextSpan(text: line)];
    }
  }

  /// Converts highlight AST nodes to Flutter TextSpans with theme styles.
  /// Same algorithm as CodeHighlightView._convert().
  static List<TextSpan> _convertNodes(
    List<Node> nodes,
    Map<String, TextStyle> theme,
  ) {
    List<TextSpan> spans = [];
    var currentSpans = spans;
    List<List<TextSpan>> stack = [];

    void traverse(Node node) {
      if (node.value != null) {
        currentSpans.add(
          node.className == null
              ? TextSpan(text: node.value)
              : TextSpan(
                  text: node.value,
                  style: theme[node.className!],
                ),
        );
      } else if (node.children != null) {
        List<TextSpan> tmp = [];
        currentSpans.add(
          TextSpan(children: tmp, style: theme[node.className!]),
        );
        stack.add(currentSpans);
        currentSpans = tmp;

        for (int i = 0; i < node.children!.length; i++) {
          traverse(node.children![i]);
          if (i == node.children!.length - 1) {
            currentSpans =
                stack.isEmpty ? spans : stack.removeLast();
          }
        }
      }
    }

    for (var node in nodes) {
      traverse(node);
    }

    return spans;
  }

  /// Computes line-level diffs between old and new text.
  /// Adapted from DiffView._computeLineDiffs.
  static List<_RawDiffLine> _computeLineDiffs(
    String oldText,
    String newText,
  ) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(oldText, newText);
    dmp.diffCleanupSemantic(diffs);

    final result = <_RawDiffLine>[];

    int oldLineNumber = 1;
    int newLineNumber = 1;

    String currentLineBuffer = '';
    _DiffLineType? currentLineType;

    void flushLine(_DiffLineType type, int? lineNum) {
      if (currentLineBuffer.isNotEmpty || currentLineType != null) {
        result.add(_RawDiffLine(
          text: currentLineBuffer,
          type: type,
          lineNumber: lineNum,
        ));
        currentLineBuffer = '';
        currentLineType = null;
      }
    }

    for (final diff in diffs) {
      final text = diff.text;
      final operation = diff.operation;

      _DiffLineType lineType;
      switch (operation) {
        case DIFF_DELETE:
          lineType = _DiffLineType.removed;
        case DIFF_INSERT:
          lineType = _DiffLineType.added;
        case DIFF_EQUAL:
        default:
          lineType = _DiffLineType.context;
      }

      final lines = text.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final lineContent = lines[i];
        final isLastPart = i == lines.length - 1;

        if (currentLineType != null && currentLineType != lineType) {
          currentLineBuffer += lineContent;
          if (!isLastPart) {
            final lineNum = currentLineType == _DiffLineType.removed
                ? oldLineNumber
                : (currentLineType == _DiffLineType.added
                    ? newLineNumber
                    : newLineNumber);
            flushLine(currentLineType!, lineNum);

            if (currentLineType == _DiffLineType.removed) {
              oldLineNumber++;
            } else if (currentLineType == _DiffLineType.added) {
              newLineNumber++;
            } else {
              oldLineNumber++;
              newLineNumber++;
            }
          }
          currentLineType = lineType;
        } else {
          currentLineType = lineType;
          currentLineBuffer += lineContent;

          if (!isLastPart) {
            final lineNum = lineType == _DiffLineType.removed
                ? oldLineNumber
                : (lineType == _DiffLineType.added
                    ? newLineNumber
                    : newLineNumber);
            flushLine(lineType, lineNum);

            if (lineType == _DiffLineType.removed) {
              oldLineNumber++;
            } else if (lineType == _DiffLineType.added) {
              newLineNumber++;
            } else {
              oldLineNumber++;
              newLineNumber++;
            }
          }
        }
      }
    }

    // Flush remaining content
    if (currentLineBuffer.isNotEmpty) {
      final lineType = currentLineType ?? _DiffLineType.context;
      final lineNum = lineType == _DiffLineType.removed
          ? oldLineNumber
          : newLineNumber;
      flushLine(lineType, lineNum);
    }

    return result;
  }
}

/// A single row in the code view.
class _CodeLineRow extends StatelessWidget {
  const _CodeLineRow({
    required this.line,
    required this.gutterWidth,
    required this.showDiffPrefix,
    required this.lineNumberColor,
    required this.textColor,
  });

  final _CodeLine line;
  final double gutterWidth;
  final bool showDiffPrefix;
  final Color lineNumberColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor;
    final String prefix;

    switch (line.type) {
      case _DiffLineType.removed:
        backgroundColor = Colors.red.withValues(alpha: 0.2);
        prefix = '-';
      case _DiffLineType.added:
        backgroundColor = Colors.green.withValues(alpha: 0.2);
        prefix = '+';
      case _DiffLineType.context:
        backgroundColor = Colors.transparent;
        prefix = ' ';
    }

    final baseStyle = AppFonts.monoTextStyle(
      fontSize: 13,
      color: textColor,
      height: 1.5,
    );

    return Container(
      color: showDiffPrefix ? backgroundColor : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line number gutter
          Container(
            width: gutterWidth,
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 2),
            alignment: Alignment.centerRight,
            child: Text(
              line.lineNumber?.toString() ?? '',
              style: AppFonts.monoTextStyle(
                fontSize: 12,
                color: lineNumberColor,
              ),
            ),
          ),
          // Diff prefix column
          if (showDiffPrefix)
            SizedBox(
              width: 16,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  prefix,
                  style: AppFonts.monoTextStyle(
                    fontSize: 13,
                    color: textColor,
                  ),
                ),
              ),
            ),
          // Code content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                  right: 8, top: 2, bottom: 2),
              child: RichText(
                text: TextSpan(
                  style: baseStyle,
                  children: line.spans,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal representation of a code line.
class _CodeLine {
  final List<TextSpan> spans;
  final int? lineNumber;
  final _DiffLineType type;

  const _CodeLine({
    required this.spans,
    this.lineNumber,
    required this.type,
  });
}

/// Raw diff line before syntax highlighting.
class _RawDiffLine {
  final String text;
  final _DiffLineType type;
  final int? lineNumber;

  const _RawDiffLine({
    required this.text,
    required this.type,
    this.lineNumber,
  });
}

/// Type of diff line.
enum _DiffLineType {
  removed,
  added,
  context,
}
