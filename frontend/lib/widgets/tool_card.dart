import 'dart:convert' show base64Decode;
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/output_entry.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'diff_view.dart';
import 'markdown_style_helper.dart';

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
                  // (the _TaskResultWidget already shows the prompt)
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
      'Bash' => _BashInputWidget(input: input),
      'Read' => _ReadInputWidget(
          input: input,
          projectDir: widget.projectDir,
        ),
      'Write' => _WriteInputWidget(
          input: input,
          projectDir: widget.projectDir,
        ),
      'Edit' => _EditInputWidget(
          entry: entry!,
          projectDir: widget.projectDir,
        ),
      'Glob' => _GlobInputWidget(input: input),
      'Grep' => _GrepInputWidget(input: input),
      'WebSearch' => _WebSearchInputWidget(input: input),
      'WebFetch' => _WebFetchInputWidget(input: input),
      'Task' => _TaskInputWidget(input: input),
      'AskUserQuestion' => _AskUserQuestionInputWidget(
          input: input,
          result: entry?.result,
        ),
      'TodoWrite' => const SizedBox.shrink(),
      _ => _GenericInputWidget(input: input),
    };
  }

  Widget _buildToolResult(BuildContext context, ToolUseOutputEntry entry) {
    final isError = entry.isError;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    // Don't show result text for Edit tools - the diff view shows everything
    if (entry.toolName == 'Edit' && !isError) {
      return const SizedBox.shrink();
    }

    // Special rendering for TodoWrite
    if (entry.toolName == 'TodoWrite' && entry.result is Map) {
      return _TodoWriteResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Task tool results
    if (entry.toolName == 'Task' && entry.result is Map) {
      return _TaskResultWidget(
        result: entry.result as Map<String, dynamic>,
      );
    }

    // Special rendering for Read tool with image content
    if (entry.toolName == 'Read' && _isImageResult(entry.result)) {
      return _ImageResultWidget(content: entry.result);
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

// -----------------------------------------------------------------------------
// Tool-specific input widgets
// -----------------------------------------------------------------------------

/// Renders Bash command input.
class _BashInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _BashInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final command = input['command'] as String? ?? '';
    final description = input['description'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null) ...[
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
        ],
        ClickToScrollContainer(
          maxHeight: 200,
          padding: const EdgeInsets.all(8),
          backgroundColor: Colors.black87,
          borderRadius: BorderRadius.circular(4),
          child: SelectableText(
            '\$ $command',
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: 12,
              color: Colors.greenAccent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders Read tool input.
class _ReadInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final String? projectDir;

  const _ReadInputWidget({required this.input, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final offset = input['offset'];
    final limit = input['limit'];

    return _FilePathWidget(
      filePath: filePath,
      icon: Icons.description,
      projectDir: projectDir,
      extraInfo: [
        if (offset != null) 'from line $offset',
        if (limit != null) '$limit lines',
      ],
    );
  }
}

/// Renders Write tool input.
class _WriteInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final String? projectDir;

  const _WriteInputWidget({required this.input, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final content = input['content'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilePathWidget(
          filePath: filePath,
          icon: Icons.edit_document,
          projectDir: projectDir,
        ),
        const SizedBox(height: 4),
        ClickToScrollContainer(
          maxHeight: 150,
          padding: const EdgeInsets.all(8),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: SelectableText(
            content.length > 500 ? '${content.substring(0, 500)}...' : content,
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders Edit tool input with diff view.
class _EditInputWidget extends StatelessWidget {
  final ToolUseOutputEntry entry;
  final String? projectDir;

  const _EditInputWidget({required this.entry, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final input = entry.toolInput;
    final filePath = input['file_path'] as String? ?? '';
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';

    // Extract structuredPatch from the result if available
    List<Map<String, dynamic>>? structuredPatch;
    final result = entry.result;
    if (result is Map<String, dynamic>) {
      final patchData = result['structuredPatch'];
      if (patchData is List) {
        structuredPatch = patchData.cast<Map<String, dynamic>>();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilePathWidget(
          filePath: filePath,
          icon: Icons.edit,
          projectDir: projectDir,
        ),
        const SizedBox(height: 8),
        DiffView(
          oldText: oldString,
          newText: newString,
          structuredPatch: structuredPatch,
          maxHeight: 300,
        ),
      ],
    );
  }
}

/// Renders Glob tool input.
class _GlobInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GlobInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Row(
      children: [
        const Icon(Icons.search, size: 14, color: Colors.purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: pattern,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (path != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: path,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders Grep tool input.
class _GrepInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GrepInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    final glob = input['glob'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Row(
      children: [
        const Icon(Icons.find_in_page, size: 14, color: Colors.purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '/',
                  style: GoogleFonts.getFont(monoFont, fontSize: 12),
                ),
                TextSpan(
                  text: pattern,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '/',
                  style: GoogleFonts.getFont(monoFont, fontSize: 12),
                ),
                if (glob != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: glob,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else if (path != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: path,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders WebSearch tool input.
class _WebSearchInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _WebSearchInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final query = input['query'] as String? ?? '';

    return Row(
      children: [
        const Icon(Icons.search, size: 14, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '"$query"',
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}

/// Renders WebFetch tool input.
class _WebFetchInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _WebFetchInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final url = input['url'] as String? ?? '';
    final prompt = input['prompt'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                url,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 11,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        if (prompt.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Prompt: $prompt',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Renders Task tool input (subagent).
class _TaskInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _TaskInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final description = input['description'] as String? ?? '';
    final prompt = input['prompt'] as String? ?? '';
    final subagentType = input['subagent_type'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree, size: 14, color: Colors.orange),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                subagentType,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (prompt.isNotEmpty) ...[
          const SizedBox(height: 4),
          ClickToScrollContainer(
            maxHeight: 100,
            padding: const EdgeInsets.all(8),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            child: SelectableText(
              prompt,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders Task tool result with structured prompt and markdown content.
class _TaskResultWidget extends StatelessWidget {
  final Map<String, dynamic> result;

  const _TaskResultWidget({required this.result});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    final prompt = result['prompt'] as String? ?? '';
    final contentBlocks = result['content'];
    final resultText = _extractResultText(contentBlocks);

    return ClickToScrollContainer(
      maxHeight: 400,
      backgroundColor: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Task section header
          _SectionDivider(label: 'Task'),
          Padding(
            padding: const EdgeInsets.all(8),
            child: SelectableText(
              prompt,
              style: GoogleFonts.getFont(
                monoFont,
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          // Result section header
          if (resultText.isNotEmpty) ...[
            _SectionDivider(label: 'Result'),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectionArea(
                child: MarkdownBody(
                  data: resultText,
                  styleSheet: buildMarkdownStyleSheet(
                    context,
                    fontSize: 12,
                  ),
                  onTapLink: (text, href, title) {
                    if (href != null) launchUrl(Uri.parse(href));
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _extractResultText(dynamic contentBlocks) {
    if (contentBlocks is List) {
      final texts = <String>[];
      for (final item in contentBlocks) {
        if (item is Map && item['type'] == 'text') {
          final text = item['text'] as String?;
          if (text != null) texts.add(text);
        }
      }
      return texts.join('\n\n');
    }
    if (contentBlocks is String) return contentBlocks;
    return '';
  }
}

/// Section divider header used within Task result widget.
class _SectionDivider extends StatelessWidget {
  final String label;

  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// Renders AskUserQuestion tool input with optional result showing selected answers.
class _AskUserQuestionInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final dynamic result;

  const _AskUserQuestionInputWidget({
    required this.input,
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    final questions = input['questions'] as List<dynamic>? ?? [];

    // Extract answers from result if available
    Map<String, String>? answers;
    if (result is Map<String, dynamic>) {
      final answersData = result['answers'];
      if (answersData is Map) {
        answers = Map<String, String>.from(
          answersData.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _QuestionItemWidget(
            question: questions[i] as Map<String, dynamic>,
            selectedAnswer: answers?[
                (questions[i] as Map<String, dynamic>)['question'] as String?],
          ),
        ],
      ],
    );
  }
}

/// Renders a single question item with optional selected answer display.
class _QuestionItemWidget extends StatelessWidget {
  final Map<String, dynamic> question;
  final String? selectedAnswer;

  const _QuestionItemWidget({
    required this.question,
    this.selectedAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final questionText = question['question'] as String? ?? '';
    final header = question['header'] as String? ?? '';
    final options = question['options'] as List<dynamic>? ?? [];
    final multiSelect = question['multiSelect'] as bool? ?? false;

    // Parse selected answers (may be comma-separated for multi-select)
    final selectedLabels = selectedAnswer?.split(', ').toSet() ?? <String>{};

    // Check if answer is a custom "Other" response (not matching any option)
    final optionLabels =
        options.map((o) => (o as Map<String, dynamic>)['label'] as String?).toSet();
    final isOtherAnswer = selectedAnswer != null &&
        !selectedLabels.any((s) => optionLabels.contains(s));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.help_outline, size: 14, color: Colors.green),
            const SizedBox(width: 8),
            if (header.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  header,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (multiSelect)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'multi',
                  style: TextStyle(fontSize: 9, color: Colors.blue),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          questionText,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in options)
                _OptionChip(
                  option: opt as Map<String, dynamic>,
                  isSelected: selectedLabels.contains(
                    (opt)['label'] as String?,
                  ),
                ),
              // Show "Other" chip with custom text if answer doesn't match options
              if (isOtherAnswer)
                _OtherAnswerChip(answer: selectedAnswer!),
            ],
          ),
        ],
      ],
    );
  }
}

/// Renders an option chip for question options.
class _OptionChip extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool isSelected;

  const _OptionChip({
    required this.option,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String?;

    return Tooltip(
      message: description ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? Colors.green
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 14, color: Colors.green),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.green : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a chip showing the user's custom "Other" answer.
class _OtherAnswerChip extends StatelessWidget {
  final String answer;

  const _OtherAnswerChip({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            'Other: ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders generic tool input.
class _GenericInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const _GenericInputWidget({required this.input});

  @override
  Widget build(BuildContext context) {
    final buffer = StringBuffer();
    input.forEach((key, value) {
      final valueStr = value is String && value.length > 100
          ? '${value.substring(0, 100)}...'
          : value.toString();
      buffer.writeln('$key: $valueStr');
    });

    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        buffer.toString().trimRight(),
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Renders TodoWrite result.
class _TodoWriteResultWidget extends StatelessWidget {
  final Map<String, dynamic> result;

  const _TodoWriteResultWidget({required this.result});

  @override
  Widget build(BuildContext context) {
    final newTodos = result['newTodos'] as List?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Todos Updated:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        if (newTodos != null)
          ...newTodos.map((todo) {
            final todoMap = todo as Map<String, dynamic>;
            final content = todoMap['content'] as String? ?? '';
            final status = todoMap['status'] as String? ?? 'pending';

            Color statusColor;
            IconData statusIcon;
            switch (status) {
              case 'completed':
                statusColor = Colors.green;
                statusIcon = Icons.check_circle;
              case 'in_progress':
                statusColor = Colors.blue;
                statusIcon = Icons.pending;
              default:
                statusColor = Colors.grey;
                statusIcon = Icons.radio_button_unchecked;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
                        decoration: status == 'completed'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Image result widget for Read tool
// -----------------------------------------------------------------------------

/// Renders an image result from the Read tool.
///
/// Supports two formats:
/// 1. Map format: `{type: image, file: {base64: "..."}}` (from CC-Insights SDK)
/// 2. List format: `[{type: image, source: {type: base64, data: "..."}}]` (Anthropic API)
class _ImageResultWidget extends StatelessWidget {
  final dynamic content;

  const _ImageResultWidget({required this.content});

  @override
  Widget build(BuildContext context) {
    String? base64Data;
    String mediaType = 'image/png';
    int? originalSize;

    // Format 1: Map with {type: image, file: {base64: "..."}}
    if (content is Map) {
      final file = content['file'] as Map<String, dynamic>?;
      if (file != null) {
        base64Data = file['base64'] as String?;
        mediaType = content['type'] as String? ?? 'image/png';
        originalSize = content['originalSize'] as int?;
      }
    }
    // Format 2: List with [{type: image, source: {type: base64, data: "..."}}]
    else if (content is List) {
      final imageBlock = (content as List).firstWhere(
        (block) => block is Map && block['type'] == 'image',
        orElse: () => null,
      );
      if (imageBlock != null) {
        final source = imageBlock['source'] as Map<String, dynamic>?;
        if (source != null) {
          base64Data = source['data'] as String?;
          mediaType = source['media_type'] as String? ?? 'image/png';
          originalSize = imageBlock['originalSize'] as int?;
        }
      }
    }

    if (base64Data == null || base64Data.isEmpty) {
      return const SizedBox.shrink();
    }

    // Decode the base64 image data
    final imageBytes = base64Decode(base64Data);

    final sizeInfo = originalSize != null ? _formatFileSize(originalSize) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Image Preview:',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              mediaType,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
            if (sizeInfo != null) ...[
              const SizedBox(width: 8),
              Text(
                sizeInfo,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outline
                  .withValues(alpha: 0.2),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image,
                        size: 32,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Formats file size in human-readable format.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Checks if a tool result contains image content.
///
/// Supports two formats:
/// 1. Map format: `{type: image, file: {base64: "..."}}` (from CC-Insights SDK)
/// 2. List format: `[{type: image, source: {type: base64, data: "..."}}]` (Anthropic API)
bool _isImageResult(dynamic result) {
  // Format 1: Map with type: image and file.base64
  if (result is Map) {
    if (result['type'] == 'image') {
      final file = result['file'];
      if (file is Map && file['base64'] != null) {
        return true;
      }
    }
  }

  // Format 2: List containing an image block
  if (result is List) {
    return result.any((block) {
      if (block is! Map) return false;
      if (block['type'] != 'image') return false;
      final source = block['source'];
      if (source is! Map) return false;
      return source['type'] == 'base64' && source['data'] != null;
    });
  }

  return false;
}

// -----------------------------------------------------------------------------
// File path widget with Cmd/Ctrl+click support
// -----------------------------------------------------------------------------

/// A file path widget that displays file info and supports Cmd/Ctrl+click to open.
class _FilePathWidget extends StatelessWidget {
  final String filePath;
  final IconData icon;
  final String? projectDir;
  final List<String>? extraInfo;

  const _FilePathWidget({
    required this.filePath,
    required this.icon,
    this.projectDir,
    this.extraInfo,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: _ClickableFilePath(
            filePath: filePath,
            extraInfo: extraInfo,
            projectDir: projectDir,
            onOpen: () => _openFile(filePath),
          ),
        ),
      ],
    );
  }

  void _openFile(String path) {
    // Resolve relative paths using projectDir if available
    String fullPath = path;
    if (!path.startsWith('/') && projectDir != null) {
      fullPath = '$projectDir/$path';
    }

    final uri = Uri.file(fullPath);
    launchUrl(uri);
  }
}

/// A file path widget that is selectable and Cmd/Ctrl+clickable.
///
/// Shows a hand cursor when the modifier key is pressed.
class _ClickableFilePath extends StatefulWidget {
  final String filePath;
  final List<String>? extraInfo;
  final String? projectDir;
  final VoidCallback onOpen;

  const _ClickableFilePath({
    required this.filePath,
    required this.onOpen,
    this.extraInfo,
    this.projectDir,
  });

  @override
  State<_ClickableFilePath> createState() => _ClickableFilePathState();
}

class _ClickableFilePathState extends State<_ClickableFilePath> {
  bool _isHovering = false;
  bool _modifierPressed = false;
  int _lastPointerDevice = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // Only update if we're hovering over this widget
    if (!_isHovering) return false;

    final isModifierKey = Platform.isMacOS
        ? event.logicalKey == LogicalKeyboardKey.metaLeft ||
            event.logicalKey == LogicalKeyboardKey.metaRight
        : event.logicalKey == LogicalKeyboardKey.controlLeft ||
            event.logicalKey == LogicalKeyboardKey.controlRight;

    if (isModifierKey) {
      final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_modifierPressed != isDown) {
        setState(() => _modifierPressed = isDown);
        // Directly set the system cursor via method channel
        final cursorKind = isDown ? 'click' : 'text';
        SystemChannels.mouseCursor.invokeMethod<void>(
          'activateSystemCursor',
          <String, dynamic>{
            'device': _lastPointerDevice,
            'kind': cursorKind,
          },
        );
      }
    }
    return false;
  }

  void _updateModifierState() {
    final isPressed = Platform.isMacOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (_modifierPressed != isPressed) {
      setState(() => _modifierPressed = isPressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return MouseRegion(
      cursor: _modifierPressed
          ? SystemMouseCursors.click
          : SystemMouseCursors.text,
      onEnter: (event) {
        _isHovering = true;
        _lastPointerDevice = event.device;
        _updateModifierState();
      },
      onExit: (_) {
        _isHovering = false;
        if (_modifierPressed) {
          setState(() => _modifierPressed = false);
        }
      },
      onHover: (event) {
        _lastPointerDevice = event.device;
        _updateModifierState();
      },
      child: Listener(
        onPointerDown: (event) {
          final isModifierPressed = Platform.isMacOS
              ? HardwareKeyboard.instance.isMetaPressed
              : HardwareKeyboard.instance.isControlPressed;

          if (isModifierPressed && event.buttons == kPrimaryButton) {
            widget.onOpen();
          }
        },
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: widget.filePath,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
              if (widget.extraInfo != null &&
                  widget.extraInfo!.isNotEmpty) ...[
                TextSpan(
                  text: ' (${widget.extraInfo!.join(", ")})',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
