import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/output_entry.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'tool_card_inputs.dart';
import 'tool_card_results.dart';

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
                    _getToolIcon(entry.toolName),
                    size: 16,
                    color: _getToolColor(entry.toolName),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatToolName(entry.toolName),
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  if (entry.toolName == 'Task') ...[
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
                    child: _buildToolSummaryWidget(context, entry),
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
                  if (!(entry.toolName == 'Task' &&
                      hasResult &&
                      entry.result is Map))
                    _buildToolInput(
                      context,
                      entry.toolName,
                      entry.toolInput,
                      entry: entry,
                    ),
                  if (hasResult) ...[
                    const SizedBox(height: 8),
                    _buildToolResult(context, entry),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Formats tool name for display.
  ///
  /// MCP tools have names like `mcp__<mcp-name>__<tool_name>` and are
  /// formatted as `MCP(mcp-name:tool_name)`.
  String _formatToolName(String toolName) {
    final mcpMatch = RegExp(r'^mcp__([^_]+)__(.+)$').firstMatch(toolName);
    if (mcpMatch != null) {
      final mcpName = mcpMatch.group(1)!;
      final mcpToolName = mcpMatch.group(2)!;
      return 'MCP($mcpName:$mcpToolName)';
    }
    return toolName;
  }

  /// Returns true if the tool name matches the MCP pattern.
  bool _isMcpTool(String toolName) {
    return toolName.startsWith('mcp__');
  }

  IconData _getToolIcon(String toolName) {
    if (_isMcpTool(toolName)) {
      return Icons.extension;
    }
    return switch (toolName) {
      'Read' => Icons.description,
      'Write' => Icons.edit_document,
      'Edit' => Icons.edit,
      'Glob' => Icons.folder_open,
      'Grep' => Icons.find_in_page,
      'Bash' => Icons.terminal,
      'Task' => Icons.account_tree,
      'AskUserQuestion' => Icons.help,
      'WebSearch' => Icons.travel_explore,
      'WebFetch' => Icons.link,
      'TodoWrite' => Icons.checklist,
      'NotebookEdit' => Icons.code,
      _ => Icons.extension,
    };
  }

  Color _getToolColor(String toolName) {
    if (_isMcpTool(toolName)) {
      return Colors.indigo;
    }
    return switch (toolName) {
      'Read' || 'Write' || 'Edit' => Colors.blue,
      'Glob' || 'Grep' => Colors.purple,
      'Bash' => Colors.orange,
      'Task' => Colors.deepOrange,
      'AskUserQuestion' => Colors.green,
      'WebSearch' || 'WebFetch' => Colors.cyan,
      'TodoWrite' => Colors.teal,
      _ => Colors.grey,
    };
  }

  /// Builds the tool summary widget, including error text when tools fail.
  Widget _buildToolSummaryWidget(
    BuildContext context,
    ToolUseOutputEntry entry,
  ) {
    final summary = _getToolSummary(
      entry.toolName,
      entry.toolInput,
      widget.projectDir,
    );
    final isError = entry.isError;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // For any tool with an error, show the error message after the summary
    if (isError) {
      final resultText = entry.toolName == 'Bash'
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

  String _getToolSummary(
    String toolName,
    Map<String, dynamic> input,
    String? projectDir,
  ) {
    final config = RuntimeConfig.instance;

    return switch (toolName) {
      'Bash' => config.bashToolSummary == BashToolSummary.description
          ? input['description'] as String? ?? input['command'] as String? ?? ''
          : input['command'] as String? ?? '',
      'Read' || 'Write' || 'Edit' => _formatFilePath(
          input['file_path'] as String? ?? '',
          projectDir,
          config.toolSummaryRelativeFilePaths,
        ),
      'Grep' => input['pattern'] as String? ?? '',
      'Glob' => input['pattern'] as String? ?? '',
      'WebSearch' => input['query'] as String? ?? '',
      'WebFetch' => input['url'] as String? ?? '',
      'Task' => input['description'] as String? ?? '',
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

  Widget _buildToolInput(
    BuildContext context,
    String toolName,
    Map<String, dynamic> input, {
    ToolUseOutputEntry? entry,
  }) {
    return switch (toolName) {
      'Bash' => BashInputWidget(input: input),
      'Read' => ReadInputWidget(
          input: input,
          projectDir: widget.projectDir,
        ),
      'Write' => WriteInputWidget(
          input: input,
          projectDir: widget.projectDir,
        ),
      'Edit' => EditInputWidget(
          entry: entry!,
          projectDir: widget.projectDir,
        ),
      'Glob' => GlobInputWidget(input: input),
      'Grep' => GrepInputWidget(input: input),
      'WebSearch' => WebSearchInputWidget(input: input),
      'WebFetch' => WebFetchInputWidget(input: input),
      'Task' => TaskInputWidget(input: input),
      'AskUserQuestion' => AskUserQuestionInputWidget(
          input: input,
          result: entry?.result,
        ),
      'TodoWrite' => const SizedBox.shrink(),
      _ => GenericInputWidget(input: input),
    };
  }

  Widget _buildToolResult(BuildContext context, ToolUseOutputEntry entry) {
    final isError = entry.isError;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // Don't show result text for Edit/Write tools - the input view shows everything
    if ((entry.toolName == 'Edit' || entry.toolName == 'Write') && !isError) {
      return const SizedBox.shrink();
    }

    // Special rendering for TodoWrite
    if (entry.toolName == 'TodoWrite' && entry.result is Map) {
      return TodoWriteResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Task tool results
    if (entry.toolName == 'Task' && entry.result is Map) {
      return TaskResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Read tool with image content
    if (entry.toolName == 'Read' && isImageResult(entry.result)) {
      return ImageResultWidget(content: entry.result);
    }

    // Special rendering for Bash results (black box with grey text)
    if (entry.toolName == 'Bash' && !isError) {
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
    final resultText = entry.toolName == 'Bash'
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
}
