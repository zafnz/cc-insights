import 'package:agent_sdk_core/agent_sdk_core.dart' show ToolKind;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/output_entry.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'tool_card_inputs.dart';
import 'tool_card_results.dart';

// ---------------------------------------------------------------------------
// File-level pure helper functions (used by multiple widgets below)
// ---------------------------------------------------------------------------

/// Formats tool name for display.
///
/// MCP tools have names like `mcp__<mcp-name>__<tool_name>` and are
/// formatted as `MCP(mcp-name:tool_name)`.
final _mcpNamePattern = RegExp(r'^mcp__([^_]+)__(.+)$');

String _formatToolName(String toolName) {
  final mcpMatch = _mcpNamePattern.firstMatch(toolName);
  if (mcpMatch != null) {
    final mcpName = mcpMatch.group(1)!;
    final mcpToolName = mcpMatch.group(2)!;
    return 'MCP($mcpName:$mcpToolName)';
  }
  return toolName;
}

IconData _getToolIcon(ToolKind toolKind, String toolName) {
  return switch (toolKind) {
    ToolKind.execute => Icons.terminal,
    ToolKind.read => Icons.description,
    ToolKind.edit => switch (toolName) {
        'Write' => Icons.edit_document,
        'NotebookEdit' => Icons.code,
        _ => Icons.edit,
      },
    ToolKind.search => switch (toolName) {
        'Glob' => Icons.folder_open,
        _ => Icons.find_in_page,
      },
    ToolKind.fetch => Icons.link,
    ToolKind.browse => Icons.travel_explore,
    ToolKind.think => Icons.account_tree,
    ToolKind.ask => Icons.help,
    ToolKind.memory => Icons.checklist,
    ToolKind.mcp => Icons.extension,
    ToolKind.delete => Icons.delete_outline,
    ToolKind.move => Icons.drive_file_move_outline,
    ToolKind.other => Icons.extension,
  };
}

Color _getToolColor(ToolKind toolKind) {
  return switch (toolKind) {
    ToolKind.execute => Colors.orange,
    ToolKind.read || ToolKind.edit => Colors.blue,
    ToolKind.search => Colors.purple,
    ToolKind.fetch || ToolKind.browse => Colors.cyan,
    ToolKind.think => Colors.deepOrange,
    ToolKind.ask => Colors.green,
    ToolKind.memory => Colors.teal,
    ToolKind.mcp => Colors.indigo,
    ToolKind.delete || ToolKind.move => Colors.amber,
    ToolKind.other => Colors.grey,
  };
}

String _getToolSummary(
  ToolKind toolKind,
  Map<String, dynamic> input,
  String? projectDir,
) {
  final config = RuntimeConfig.instance;

  return switch (toolKind) {
    ToolKind.execute => config.bashToolSummary == BashToolSummary.description
        ? input['description'] as String? ?? input['command'] as String? ?? ''
        : input['command'] as String? ?? '',
    ToolKind.read || ToolKind.edit => _formatFilePath(
        input['file_path'] as String? ?? '',
        projectDir,
        config.toolSummaryRelativeFilePaths,
      ),
    ToolKind.search => input['pattern'] as String? ?? '',
    ToolKind.browse => input['query'] as String? ?? '',
    ToolKind.fetch => input['url'] as String? ?? '',
    ToolKind.think => input['description'] as String? ?? '',
    _ => '',
  };
}

/// Formats a file path, optionally making it relative to the project dir.
String _formatFilePath(String filePath, String? projectDir, bool useRelative) {
  if (!useRelative ||
      projectDir == null ||
      projectDir.isEmpty ||
      filePath.isEmpty) {
    return filePath;
  }

  // Ensure projectDir ends with a separator for proper prefix matching
  final normalizedProjectDir =
      projectDir.endsWith('/') ? projectDir : '$projectDir/';

  if (filePath.startsWith(normalizedProjectDir)) {
    return filePath.substring(normalizedProjectDir.length);
  }

  return filePath;
}

/// Extracts error message from tool result, stripping XML-like tags.
String? _extractErrorMessage(String? result) {
  if (result == null || result.isEmpty) return null;

  // Try to extract from <tool_use_error>...</tool_use_error> tags
  final errorMatch = RegExp(
    r'<tool_use_error>(.*?)</tool_use_error>',
    dotAll: true,
  ).firstMatch(result);
  if (errorMatch != null) {
    return errorMatch.group(1)?.trim();
  }

  // If no tags, return the result as-is (truncated if too long)
  final trimmed = result.trim();
  if (trimmed.length > 100) {
    return '${trimmed.substring(0, 100)}...';
  }
  return trimmed;
}

/// Extracts displayable output from a Bash tool result.
///
/// The result can be either:
/// - A [Map] with `stdout`, `stderr`, `interrupted`, `isImage` fields
/// - A plain [String]
/// - null
String _extractBashOutput(dynamic result) {
  if (result == null) return '';
  if (result is Map) {
    final stdout = result['stdout'] as String? ?? '';
    final stderr = result['stderr'] as String? ?? '';
    final parts = <String>[
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ];
    return parts.join('\n');
  }
  return result.toString();
}

// ---------------------------------------------------------------------------
// Main widget
// ---------------------------------------------------------------------------

/// Expandable card showing tool execution details.
///
/// Renders tool inputs and results with specialized formatting for different
/// tool types (Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch,
/// Task, AskUserQuestion, TodoWrite).
class ToolCard extends StatefulWidget {
  /// The tool use entry to display.
  final ToolUseOutputEntry entry;

  /// Called when the card is expanded.
  final VoidCallback? onExpanded;

  /// The project directory for resolving relative file paths.
  final String? projectDir;

  const ToolCard({
    super.key,
    required this.entry,
    this.onExpanded,
    this.projectDir,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final hasResult = entry.result != null;
    final isError = entry.isError;
    final isExpanded = entry.isExpanded;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tool header
          InkWell(
            onTap: () {
              setState(() => entry.isExpanded = !entry.isExpanded);
              if (entry.isExpanded && widget.onExpanded != null) {
                widget.onExpanded!();
              }
            },
            child: Container(
              color: isExpanded
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : null,
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _getToolIcon(entry.toolKind, entry.toolName),
                    size: 16,
                    color: _getToolColor(entry.toolKind),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatToolName(entry.toolName),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (entry.toolKind == ToolKind.think) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.toolInput['subagent_type'] as String? ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ToolSummary(
                      entry: entry,
                      projectDir: widget.projectDir,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasResult)
                    Icon(
                      isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: isError ? Colors.red : Colors.green,
                    )
                  else
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Skip input widget for Task with structured result
                  // (the TaskResultWidget already shows the prompt)
                  if (!(entry.toolKind == ToolKind.think &&
                      hasResult &&
                      entry.result is Map))
                    _ToolInput(
                      entry: entry,
                      projectDir: widget.projectDir,
                    ),
                  if (hasResult) ...[
                    const SizedBox(height: 8),
                    _ToolResult(entry: entry),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted widget classes
// ---------------------------------------------------------------------------

/// Displays the tool summary text in the collapsed card header.
class _ToolSummary extends StatelessWidget {
  const _ToolSummary({
    required this.entry,
    required this.projectDir,
  });

  final ToolUseOutputEntry entry;
  final String? projectDir;

  @override
  Widget build(BuildContext context) {
    final summary = _getToolSummary(entry.toolKind, entry.toolInput, projectDir);
    final isError = entry.isError;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // For any tool with an error, show the error message after the summary
    if (isError) {
      final resultText = entry.toolKind == ToolKind.execute
          ? _extractBashOutput(entry.result)
          : entry.result?.toString();
      final errorMessage = _extractErrorMessage(resultText);
      if (errorMessage != null) {
        return Text.rich(
          TextSpan(
            children: [
              if (summary.isNotEmpty) ...[
                TextSpan(
                  text: summary,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                const TextSpan(text: '  '),
              ],
              TextSpan(
                text: errorMessage,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        );
      }
    }

    // Default: just show the summary
    return Text(
      summary,
      style: GoogleFonts.getFont(
        monoFont,
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

/// Dispatches to the appropriate tool-specific input widget.
class _ToolInput extends StatelessWidget {
  const _ToolInput({
    required this.entry,
    required this.projectDir,
  });

  final ToolUseOutputEntry entry;
  final String? projectDir;

  @override
  Widget build(BuildContext context) {
    return switch (entry.toolKind) {
      ToolKind.execute => BashInputWidget(input: entry.toolInput),
      ToolKind.read => ReadInputWidget(
          input: entry.toolInput,
          projectDir: projectDir,
        ),
      ToolKind.edit => switch (entry.toolName) {
          'Write' => WriteInputWidget(
              input: entry.toolInput,
              projectDir: projectDir,
            ),
          // Edit, NotebookEdit, and other edit tools
          _ => EditInputWidget(
              entry: entry,
              projectDir: projectDir,
            ),
        },
      ToolKind.search => switch (entry.toolName) {
          'Grep' => GrepInputWidget(input: entry.toolInput),
          // Glob and other search tools
          _ => GlobInputWidget(input: entry.toolInput),
        },
      ToolKind.browse => WebSearchInputWidget(input: entry.toolInput),
      ToolKind.fetch => WebFetchInputWidget(input: entry.toolInput),
      ToolKind.think => TaskInputWidget(input: entry.toolInput),
      ToolKind.ask => AskUserQuestionInputWidget(
          input: entry.toolInput,
          result: entry.result,
        ),
      ToolKind.memory => const SizedBox.shrink(),
      ToolKind.mcp || ToolKind.delete || ToolKind.move || ToolKind.other =>
        GenericInputWidget(input: entry.toolInput),
    };
  }
}

/// Renders the tool result section when the card is expanded.
class _ToolResult extends StatelessWidget {
  const _ToolResult({required this.entry});

  final ToolUseOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    final isError = entry.isError;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // Don't show result text for edit tools - the input view shows everything
    if (entry.toolKind == ToolKind.edit && !isError) {
      return const SizedBox.shrink();
    }

    // Special rendering for TodoWrite (memory tools)
    if (entry.toolKind == ToolKind.memory && entry.result is Map) {
      return TodoWriteResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Task tool results (think tools)
    if (entry.toolKind == ToolKind.think && entry.result is Map) {
      return TaskResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Read tool with image content
    if (entry.toolKind == ToolKind.read && isImageResult(entry.result)) {
      return ImageResultWidget(content: entry.result);
    }

    // Special rendering for Bash results (black box with grey text)
    if (entry.toolKind == ToolKind.execute && !isError) {
      final bashOutput = _extractBashOutput(entry.result);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Result:',
            style: TextStyle(
              fontSize: 11,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          ClickToScrollContainer(
            maxHeight: 300,
            padding: const EdgeInsets.all(8),
            backgroundColor: Colors.black87,
            borderRadius: BorderRadius.circular(4),
            child: SelectableText(
              bashOutput,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      );
    }

    // Default result rendering
    final resultText = entry.toolKind == ToolKind.execute
        ? _extractBashOutput(entry.result)
        : entry.result?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isError ? 'Error:' : 'Result:',
          style: TextStyle(
            fontSize: 11,
            color: isError
                ? Colors.red
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 4),
        ClickToScrollContainer(
          maxHeight: 300,
          padding: const EdgeInsets.all(8),
          backgroundColor: isError
              ? Colors.red.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: SelectableText(
            resultText,
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: 11,
              color: isError
                  ? Colors.red
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
