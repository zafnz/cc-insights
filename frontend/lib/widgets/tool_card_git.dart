import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/design_tokens.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'diff_view.dart';
import 'tool_card_inputs.dart';

// =============================================================================
// Helpers
// =============================================================================

/// Known internal CCI git tool names.
const _cciGitToolNames = {
  'git_commit_context',
  'git_commit',
  'git_log',
  'git_diff',
};

/// MCP tool name pattern: `mcp__<server>__<tool>`.
final _mcpPattern = RegExp(r'^mcp__([^_]+)__(.+)$');

/// Returns the bare CCI git tool name if [toolName] is an internal git MCP
/// tool, or null otherwise.
String? cciGitToolName(String toolName) {
  final match = _mcpPattern.firstMatch(toolName);
  if (match == null) return null;
  final server = match.group(1)!;
  final tool = match.group(2)!;
  if (server == 'cci' && _cciGitToolNames.contains(tool)) return tool;
  return null;
}

/// Friendly display name for a CCI git tool.
String? cciGitFriendlyName(String mcpToolName) {
  return switch (mcpToolName) {
    'git_commit_context' => 'Git Context',
    'git_commit' => 'Git Commit',
    'git_log' => 'Git Log',
    'git_diff' => 'Git Diff',
    _ => null,
  };
}

/// Icon for a CCI git tool.
IconData cciGitIcon(String mcpToolName) {
  return switch (mcpToolName) {
    'git_commit_context' => Icons.fact_check_outlined,
    'git_commit' => Icons.commit,
    'git_log' => Icons.history,
    'git_diff' => Icons.difference,
    _ => Icons.extension,
  };
}

/// Summary text for a CCI git tool header.
String cciGitSummary(String gitName, Map<String, dynamic> input) {
  return switch (gitName) {
    'git_commit_context' => '',
    'git_commit' => _gitCommitSummary(input),
    'git_log' => _gitLogSummary(input),
    'git_diff' => _gitDiffSummary(input),
    _ => '',
  };
}

String _gitCommitSummary(Map<String, dynamic> input) {
  final files = input['files'] as List<dynamic>?;
  final message = input['message'] as String? ?? '';
  final fileCount = files?.length ?? 0;
  final prefix = '$fileCount file${fileCount == 1 ? '' : 's'}';
  if (message.isEmpty) return prefix;
  // Take only the first line of the message for the summary.
  final firstLine = message.split('\n').first;
  final truncated =
      firstLine.length > 60 ? '${firstLine.substring(0, 57)}...' : firstLine;
  return '$prefix: $truncated';
}

String _gitLogSummary(Map<String, dynamic> input) {
  final count = input['count'] as num?;
  if (count == null) return '';
  return '$count commit${count == 1 ? '' : 's'}';
}

String _gitDiffSummary(Map<String, dynamic> input) {
  final staged = input['staged'] as bool? ?? false;
  final files = input['files'] as List<dynamic>?;
  final parts = <String>[
    if (staged) 'staged',
    if (files != null && files.isNotEmpty)
      '${files.length} file${files.length == 1 ? '' : 's'}',
  ];
  return parts.join(', ');
}

// =============================================================================
// Input widgets
// =============================================================================

/// Dispatches to the correct git tool input widget.
class GitToolInputWidget extends StatelessWidget {
  final String gitToolName;
  final Map<String, dynamic> input;

  const GitToolInputWidget({
    super.key,
    required this.gitToolName,
    required this.input,
  });

  @override
  Widget build(BuildContext context) {
    return switch (gitToolName) {
      'git_commit_context' => const SizedBox.shrink(),
      'git_commit' => _GitCommitInput(input: input),
      'git_log' => const SizedBox.shrink(),
      'git_diff' => _GitDiffInput(input: input),
      _ => GenericInputWidget(input: input),
    };
  }
}

/// Renders git_commit tool input: commit message + file list.
class _GitCommitInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GitCommitInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final message = input['message'] as String? ?? '';
    final files = input['files'] as List<dynamic>? ?? [];
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Files
        if (files.isNotEmpty) ...[
          Text(
            'Files (${files.length}):',
            style: TextStyle(
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            files.join(', '),
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Commit message
        Text(
          'Message:',
          style: TextStyle(
            fontSize: FontSizes.code,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        ClickToScrollContainer(
          maxHeight: 200,
          padding: const EdgeInsets.all(8),
          backgroundColor: colorScheme.surfaceContainerHighest,
          borderRadius: Radii.smallBorderRadius,
          child: SelectableText(
            message,
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders git_diff tool input: staged flag + file list.
class _GitDiffInput extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GitDiffInput({required this.input});

  @override
  Widget build(BuildContext context) {
    final staged = input['staged'] as bool? ?? false;
    final files = input['files'] as List<dynamic>?;
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              staged ? Icons.inventory_2_outlined : Icons.edit_note,
              size: IconSizes.xs,
              color: Colors.teal,
            ),
            const SizedBox(width: 8),
            Text(
              staged ? 'Staged changes' : 'Unstaged changes',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        if (files != null && files.isNotEmpty) ...[
          const SizedBox(height: 4),
          SelectableText(
            files.join(', '),
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// Result widgets
// =============================================================================

/// Extracts plain text from a tool result that may be a content-block list.
///
/// MCP tool results arrive as `[{type: text, text: "..."}]`.  This helper
/// unwraps such lists into the concatenated text.  If the result is already a
/// String or Map it is returned as-is.
dynamic _unwrapContentBlocks(dynamic result) {
  if (result is List) {
    final buffer = StringBuffer();
    for (final block in result) {
      if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] ?? '');
      }
    }
    if (buffer.isNotEmpty) return buffer.toString();
  }
  return result;
}

/// Dispatches to the correct git tool result widget.
class GitToolResultWidget extends StatelessWidget {
  final String gitToolName;
  final dynamic result;

  const GitToolResultWidget({
    super.key,
    required this.gitToolName,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final unwrapped = _unwrapContentBlocks(result);
    return switch (gitToolName) {
      'git_commit_context' => _GitCommitContextResult(result: unwrapped),
      'git_commit' => _GitCommitResult(result: unwrapped),
      'git_log' => _GitLogResult(result: unwrapped),
      'git_diff' => _GitDiffResult(result: unwrapped),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Renders git_commit_context result with parsed status, branch, and commits.
class _GitCommitContextResult extends StatelessWidget {
  final dynamic result;

  const _GitCommitContextResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // Parse JSON result
    Map<String, dynamic>? parsed;
    try {
      if (result is String) {
        parsed = jsonDecode(result as String) as Map<String, dynamic>;
      } else if (result is Map) {
        parsed = Map<String, dynamic>.from(result as Map);
      }
    } catch (_) {
      // Fall through to raw text display
    }

    if (parsed == null) {
      return _RawTextFallback(text: result?.toString() ?? '');
    }

    final branch = parsed['branch'] as String?;
    final status = parsed['status'] as Map<String, dynamic>? ?? {};
    final diffStat = parsed['diff_stat'] as String? ?? '';
    final recentCommits = parsed['recent_commits'] as List<dynamic>? ?? [];

    final modified = (status['modified'] as List<dynamic>?) ?? [];
    final untracked = (status['untracked'] as List<dynamic>?) ?? [];
    final deleted = (status['deleted'] as List<dynamic>?) ?? [];
    final staged = (status['staged'] as List<dynamic>?) ?? [];

    final allEmpty =
        modified.isEmpty && untracked.isEmpty && deleted.isEmpty && staged.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Branch
        if (branch != null) ...[
          Row(
            children: [
              Icon(Icons.account_tree, size: IconSizes.xs, color: Colors.teal),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  borderRadius: Radii.smallBorderRadius,
                ),
                child: Text(
                  branch,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: FontSizes.code,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // File status groups
        if (allEmpty)
          Text(
            'Working tree clean',
            style: TextStyle(
              fontSize: FontSizes.code,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          )
        else ...[
          if (staged.isNotEmpty)
            _FileStatusGroup(
              label: 'Staged',
              files: staged,
              color: Colors.green,
              icon: Icons.check_circle_outline,
            ),
          if (modified.isNotEmpty)
            _FileStatusGroup(
              label: 'Modified',
              files: modified,
              color: Colors.orange,
              icon: Icons.edit_outlined,
            ),
          if (untracked.isNotEmpty)
            _FileStatusGroup(
              label: 'Untracked',
              files: untracked,
              color: Colors.blue,
              icon: Icons.add_circle_outline,
            ),
          if (deleted.isNotEmpty)
            _FileStatusGroup(
              label: 'Deleted',
              files: deleted,
              color: Colors.red,
              icon: Icons.remove_circle_outline,
            ),
        ],

        // Diff stat
        if (diffStat.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Diff stat:',
            style: TextStyle(
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            diffStat,
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],

        // Recent commits
        if (recentCommits.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Recent commits:',
            style: TextStyle(
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 2),
          for (final commit in recentCommits)
            if (commit is Map<String, dynamic>)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (commit['sha'] as String? ?? '').padRight(7),
                      style: GoogleFonts.getFont(
                        monoFont,
                        fontSize: FontSizes.code,
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _firstLine(commit['message'] as String? ?? ''),
                        style: GoogleFonts.getFont(
                          monoFont,
                          fontSize: FontSizes.code,
                          color: colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ],
    );
  }

  static String _firstLine(String text) {
    final idx = text.indexOf('\n');
    return idx >= 0 ? text.substring(0, idx) : text;
  }
}

/// A group of files under a status label (Modified, Untracked, etc).
class _FileStatusGroup extends StatelessWidget {
  final String label;
  final List<dynamic> files;
  final Color color;
  final IconData icon;

  const _FileStatusGroup({
    required this.label,
    required this.files,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: IconSizes.xs, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              files.join(', '),
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: FontSizes.code,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders git_commit result as a success row.
///
/// The result is a plain-text string like:
///   "Committed abc1234 (3 files): Add new feature"
class _GitCommitResult extends StatelessWidget {
  final dynamic result;

  const _GitCommitResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final text = result?.toString() ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // Try to extract SHA from "Committed <sha> ..." pattern
    final shaMatch = RegExp(r'Committed\s+(\S+)').firstMatch(text);
    final sha = shaMatch?.group(1);

    if (sha == null) {
      return _RawTextFallback(text: text);
    }

    // Everything after "Committed <sha> " is the summary
    final summary = text.substring(shaMatch!.end).trim();

    return Row(
      children: [
        const Icon(
          Icons.check_circle,
          size: IconSizes.sm,
          color: Colors.green,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.15),
            borderRadius: Radii.smallBorderRadius,
          ),
          child: Text(
            sha,
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: FontSizes.code,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders git_log result as mono text.
class _GitLogResult extends StatelessWidget {
  final dynamic result;

  const _GitLogResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final text = result?.toString() ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return ClickToScrollContainer(
      maxHeight: 300,
      padding: const EdgeInsets.all(8),
      backgroundColor: Colors.black87,
      borderRadius: Radii.smallBorderRadius,
      child: SelectableText(
        text,
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: FontSizes.code,
          color: Colors.grey,
        ),
      ),
    );
  }
}

/// Renders git_diff result using DiffView for color-coded diffs.
class _GitDiffResult extends StatelessWidget {
  final dynamic result;

  const _GitDiffResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final text = result?.toString() ?? '';

    // Handle empty / no-changes case
    if (text.isEmpty || text == '(no changes)') {
      return Text(
        text.isEmpty ? '(no changes)' : text,
        style: TextStyle(
          fontSize: FontSizes.code,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    // Try to parse as unified diff
    final hunks = parseUnifiedDiff(text);

    if (hunks.isNotEmpty) {
      return DiffView(
        oldText: '',
        newText: '',
        structuredPatch: hunks,
        maxHeight: 300,
      );
    }

    // Fallback to raw text if parsing yields no hunks
    final monoFont = RuntimeConfig.instance.monoFontFamily;
    return ClickToScrollContainer(
      maxHeight: 300,
      padding: const EdgeInsets.all(8),
      backgroundColor: Colors.black87,
      borderRadius: Radii.smallBorderRadius,
      child: SelectableText(
        text,
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: FontSizes.code,
          color: Colors.grey,
        ),
      ),
    );
  }
}

/// Fallback widget that shows raw text when JSON parsing fails.
class _RawTextFallback extends StatelessWidget {
  final String text;

  const _RawTextFallback({required this.text});

  @override
  Widget build(BuildContext context) {
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return ClickToScrollContainer(
      maxHeight: 300,
      padding: const EdgeInsets.all(8),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: Radii.smallBorderRadius,
      child: SelectableText(
        text,
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: FontSizes.code,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
