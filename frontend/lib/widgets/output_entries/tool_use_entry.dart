import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/output_entry.dart';

/// Displays a tool use output entry.
///
/// Shows the tool name, input parameters, and result in an expandable card.
class ToolUseEntryWidget extends StatefulWidget {
  const ToolUseEntryWidget({super.key, required this.entry});

  final ToolUseOutputEntry entry;

  @override
  State<ToolUseEntryWidget> createState() => _ToolUseEntryWidgetState();
}

class _ToolUseEntryWidgetState extends State<ToolUseEntryWidget> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.entry.isExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final entry = widget.entry;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: entry.isError
              ? colorScheme.error.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tool header (clickable to expand/collapse)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: entry.isError
                    ? colorScheme.errorContainer.withValues(alpha: 0.3)
                    : colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(7),
                  bottom: _isExpanded ? Radius.zero : const Radius.circular(7),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getToolIcon(entry.toolName),
                    size: 14,
                    color: entry.isError ? colorScheme.error : colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.toolName,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: entry.isError
                            ? colorScheme.error
                            : colorScheme.primary,
                      ),
                    ),
                  ),
                  if (entry.isError)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.error_outline,
                        size: 14,
                        color: colorScheme.error,
                      ),
                    ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Input section
                  Text(
                    'Input:',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      _formatToolInput(entry.toolInput),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Result section (if available)
                  if (entry.result != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Result:',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          entry.result.toString(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: entry.isError
                                ? colorScheme.error
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            // Collapsed summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _formatToolSummary(entry),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  IconData _getToolIcon(String toolName) {
    return switch (toolName.toLowerCase()) {
      'bash' => Icons.terminal,
      'read' => Icons.description_outlined,
      'write' => Icons.edit_document,
      'edit' => Icons.edit_outlined,
      'glob' => Icons.folder_open,
      'grep' => Icons.search,
      'task' => Icons.smart_toy_outlined,
      'webfetch' => Icons.language,
      'websearch' => Icons.travel_explore,
      _ => Icons.build_outlined,
    };
  }

  String _formatToolInput(Map<String, dynamic> input) {
    if (input.isEmpty) return '(no input)';

    final buffer = StringBuffer();
    for (final entry in input.entries) {
      if (buffer.isNotEmpty) buffer.write('\n');
      final value = entry.value.toString();
      // Truncate long values
      final displayValue =
          value.length > 200 ? '${value.substring(0, 200)}...' : value;
      buffer.write('${entry.key}: $displayValue');
    }
    return buffer.toString();
  }

  String _formatToolSummary(ToolUseOutputEntry entry) {
    final input = entry.toolInput;

    return switch (entry.toolName.toLowerCase()) {
      'bash' => input['command']?.toString() ?? '(command)',
      'read' => input['file_path']?.toString() ?? '(file)',
      'write' => input['file_path']?.toString() ?? '(file)',
      'edit' => input['file_path']?.toString() ?? '(file)',
      'glob' => input['pattern']?.toString() ?? '(pattern)',
      'grep' => input['pattern']?.toString() ?? '(pattern)',
      'task' => input['description']?.toString() ?? '(task)',
      'webfetch' || 'websearch' => input['url']?.toString() ??
          input['query']?.toString() ??
          '(url/query)',
      _ => input.isNotEmpty ? input.values.first.toString() : '(no input)',
    };
  }
}
