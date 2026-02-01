import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/runtime_config.dart';

/// Displays a unified diff view with line numbers and colors.
///
/// This widget computes character-level diffs using diff_match_patch and
/// converts them to line-level operations for display in a unified diff
/// format similar to CLI tools.
///
/// Alternatively, if [structuredPatch] is provided, it uses pre-computed
/// diff hunks from the SDK instead of computing diffs locally.
class DiffView extends StatelessWidget {
  /// The original text (before changes).
  /// Used when [structuredPatch] is not provided.
  final String oldText;

  /// The new text (after changes).
  /// Used when [structuredPatch] is not provided.
  final String newText;

  /// Maximum height constraint for the diff view.
  /// If null, the view will size to its content.
  final double? maxHeight;

  /// Pre-computed structured patch data from the SDK.
  ///
  /// When provided and non-empty, this takes precedence over computing
  /// diffs from [oldText] and [newText].
  ///
  /// Each hunk should have:
  /// - `oldStart`: Starting line number in original file
  /// - `oldLines`: Number of lines in original
  /// - `newStart`: Starting line number in new file
  /// - `newLines`: Number of lines in new
  /// - `lines`: Pre-formatted diff lines where first character indicates type:
  ///   - `-` for removed lines
  ///   - `+` for added lines
  ///   - ` ` (space) for context lines
  final List<Map<String, dynamic>>? structuredPatch;

  const DiffView({
    super.key,
    required this.oldText,
    required this.newText,
    this.maxHeight,
    this.structuredPatch,
  });

  @override
  Widget build(BuildContext context) {
    // Use structuredPatch if provided and non-empty, otherwise compute diffs
    final diffItems = (structuredPatch != null && structuredPatch!.isNotEmpty)
        ? _parseStructuredPatch(structuredPatch!)
        : _computeLineDiffs(
            oldText,
            newText,
          ).map((line) => _DiffItem.line(line)).toList();

    // Calculate the width needed for line numbers
    final maxLineNumber = diffItems.fold<int>(0, (max, item) {
      if (item.isHunkHeader) return max;
      final lineNum = item.line!.lineNumber ?? 0;
      return lineNum > max ? lineNum : max;
    });
    final lineNumberWidth = maxLineNumber.toString().length * 10.0 + 16.0;

    Widget content = ListView.builder(
      shrinkWrap: true,
      itemCount: diffItems.length,
      itemBuilder: (context, index) {
        final item = diffItems[index];
        if (item.isHunkHeader) {
          return _HunkHeaderWidget(header: item.hunkHeader!);
        }
        return _DiffLineWidget(
          line: item.line!,
          lineNumberWidth: lineNumberWidth,
        );
      },
    );

    if (maxHeight != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  /// Parses structured patch data into diff items (headers and lines).
  List<_DiffItem> _parseStructuredPatch(List<Map<String, dynamic>> hunks) {
    final result = <_DiffItem>[];

    for (final hunk in hunks) {
      final oldStart = hunk['oldStart'] as int? ?? 1;
      final oldLines = hunk['oldLines'] as int? ?? 0;
      final newStart = hunk['newStart'] as int? ?? 1;
      final newLines = hunk['newLines'] as int? ?? 0;
      final lines = hunk['lines'] as List<dynamic>? ?? [];

      // Add hunk header
      result.add(
        _DiffItem.header('@@ -$oldStart,$oldLines +$newStart,$newLines @@'),
      );

      // Track line numbers as we iterate
      int currentOldLine = oldStart;
      int currentNewLine = newStart;

      for (final lineData in lines) {
        final lineStr = lineData.toString();
        if (lineStr.isEmpty) continue;

        final firstChar = lineStr[0];
        final content = lineStr.length > 1 ? lineStr.substring(1) : '';

        _DiffLineType type;
        int? lineNumber;

        switch (firstChar) {
          case '-':
            type = _DiffLineType.removed;
            lineNumber = currentOldLine;
            currentOldLine++;
          case '+':
            type = _DiffLineType.added;
            lineNumber = currentNewLine;
            currentNewLine++;
          case ' ':
          default:
            type = _DiffLineType.context;
            lineNumber = currentOldLine; // Show old line number for context
            currentOldLine++;
            currentNewLine++;
        }

        result.add(
          _DiffItem.line(
            _DiffLine(text: content, type: type, lineNumber: lineNumber),
          ),
        );
      }
    }

    return result;
  }

  /// Computes line-level diff operations from the two texts.
  List<_DiffLine> _computeLineDiffs(String oldText, String newText) {
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(oldText, newText);
    dmp.diffCleanupSemantic(diffs);

    final result = <_DiffLine>[];

    // Track current position in old and new text for line numbers
    int oldLineNumber = 1;
    int newLineNumber = 1;

    // Buffer for accumulating partial lines
    String currentLineBuffer = '';
    _DiffLineType? currentLineType;

    void flushLine(_DiffLineType type, int? lineNum) {
      if (currentLineBuffer.isNotEmpty || currentLineType != null) {
        result.add(
          _DiffLine(text: currentLineBuffer, type: type, lineNumber: lineNum),
        );
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

      // Split text into lines, preserving line structure
      final lines = text.split('\n');

      for (int i = 0; i < lines.length; i++) {
        final lineContent = lines[i];
        final isLastPart = i == lines.length - 1;

        // Handle line type changes within a line
        if (currentLineType != null && currentLineType != lineType) {
          // Mixed types on same line - flush and continue
          // This happens when edits are inline
          currentLineBuffer += lineContent;
          if (!isLastPart) {
            // We have a newline, flush the buffer
            final lineNum = lineType == _DiffLineType.removed
                ? oldLineNumber
                : (lineType == _DiffLineType.added
                      ? newLineNumber
                      : newLineNumber);
            flushLine(currentLineType!, lineNum);

            // Increment line numbers based on the flushed line type
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
            // We have a newline
            final lineNum = lineType == _DiffLineType.removed
                ? oldLineNumber
                : (lineType == _DiffLineType.added
                      ? newLineNumber
                      : newLineNumber);
            flushLine(lineType, lineNum);

            // Increment line numbers
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

    // Flush any remaining content
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

/// Represents a single line in the diff view.
class _DiffLine {
  final String text;
  final _DiffLineType type;
  final int? lineNumber;

  const _DiffLine({required this.text, required this.type, this.lineNumber});
}

/// Type of diff line operation.
enum _DiffLineType {
  /// Line was removed (exists in old, not in new).
  removed,

  /// Line was added (exists in new, not in old).
  added,

  /// Context line (unchanged, exists in both).
  context,
}

/// Widget that renders a single diff line.
class _DiffLineWidget extends StatelessWidget {
  final _DiffLine line;
  final double lineNumberWidth;

  const _DiffLineWidget({required this.line, required this.lineNumberWidth});

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

    final lineNumberColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.4);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Container(
      color: backgroundColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line number gutter
          Container(
            width: lineNumberWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            alignment: Alignment.centerRight,
            child: SelectableText(
              line.lineNumber?.toString() ?? '',
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 12,
                color: lineNumberColor,
              ),
            ),
          ),
          // Prefix
          Container(
            width: 16,
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText(
              prefix,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 12,
                color: textColor,
              ),
            ),
          ),
          // Line content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              child: SelectableText(
                line.text,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Represents either a hunk header or a diff line in the view.
class _DiffItem {
  final _DiffLine? line;
  final String? hunkHeader;

  const _DiffItem._({this.line, this.hunkHeader});

  factory _DiffItem.line(_DiffLine line) => _DiffItem._(line: line);
  factory _DiffItem.header(String header) => _DiffItem._(hunkHeader: header);

  bool get isHunkHeader => hunkHeader != null;
}

/// Widget that renders a hunk header (e.g., "@@ -119,7 +119,6 @@").
class _HunkHeaderWidget extends StatelessWidget {
  final String header;

  const _HunkHeaderWidget({required this.header});

  @override
  Widget build(BuildContext context) {
    final headerColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SelectableText(
        header,
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: 12,
          color: headerColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
