import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/output_entry.dart';
import '../../screens/raw_json_viewer.dart';
import '../../services/runtime_config.dart';
import '../tool_card.dart';
import 'auto_compaction_entry.dart';
import 'context_entry.dart';
import 'session_entry.dart';
import 'system_notification_entry.dart';
import 'text_entry.dart';
import 'unknown_message_entry.dart';
import 'user_input_entry.dart';

/// Keys for testing the OutputEntryWidget.
class OutputEntryWidgetKeys {
  /// Key for the debug icon button.
  static const debugIcon = Key('outputEntry_debugIcon');

  /// Key for the copy content button.
  static const copyContent = Key('outputEntry_copyContent');
}

/// Renders a single output entry based on its type.
///
/// Dispatches to the appropriate widget for each entry type.
/// When [RuntimeConfig.showRawMessages] is enabled and the entry has
/// raw messages, wraps the widget with a debug icon that opens
/// the [RawJsonViewer].
///
/// When [isSubagent] is true, applies a subtle visual distinction
/// (left border) to indicate the entry is from a subagent conversation.
class OutputEntryWidget extends StatelessWidget {
  const OutputEntryWidget({
    super.key,
    required this.entry,
    this.projectDir,
    this.isSubagent = false,
  });

  final OutputEntry entry;

  /// The project directory for resolving relative file paths.
  final String? projectDir;

  /// Whether this entry is from a subagent conversation.
  ///
  /// When true, applies a subtle left border to visually distinguish
  /// subagent output from primary conversation output.
  final bool isSubagent;

  /// Formatter for [HH:MM] timestamps shown beside entries.
  static final _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    Widget child;
    List<Map<String, dynamic>>? rawMessages;
    bool showTimestamp = true;

    switch (entry) {
      case final TextOutputEntry e:
        child = TextEntryWidget(entry: e, projectDir: projectDir);
        rawMessages = e.rawMessages;
      case final ToolUseOutputEntry e:
        child = ToolCard(entry: e, projectDir: projectDir);
        rawMessages = e.rawMessages;
      case final UserInputEntry e:
        child = UserInputEntryWidget(entry: e);
      case final ContextSummaryEntry e:
        child = ContextSummaryEntryWidget(
          entry: e,
          projectDir: projectDir,
        );
      case ContextClearedEntry():
        child = const ContextClearedEntryWidget();
        showTimestamp = false;
      case final SessionMarkerEntry e:
        child = SessionMarkerEntryWidget(entry: e);
        showTimestamp = false;
      case final AutoCompactionEntry e:
        child = AutoCompactionEntryWidget(entry: e);
        showTimestamp = false;
      case final UnknownMessageEntry e:
        child = UnknownMessageEntryWidget(entry: e);
      case final SystemNotificationEntry e:
        child = SystemNotificationEntryWidget(
          entry: e,
          projectDir: projectDir,
        );
      default:
        return const SizedBox.shrink();
    }

    // Wrap with action icons (copy button, and debug icon if enabled)
    final config = RuntimeConfig.instance;
    final showDebug = config.showRawMessages &&
        rawMessages != null &&
        rawMessages.isNotEmpty;
    final copyableContent = _extractCopyableContent(entry);
    if (showDebug || copyableContent != null) {
      child = _EntryWithActionIcons(
        rawMessages: showDebug ? rawMessages : null,
        copyableContent: copyableContent,
        child: child,
      );
    }

    // Add timestamp on the left for message-type entries
    if (showTimestamp && config.showTimestamps) {
      child = _TimestampedEntry(
        timestamp: entry.timestamp,
        child: child,
      );
    }

    // Wrap with subagent indicator if viewing a subagent conversation
    if (isSubagent) {
      return _SubagentEntryWrapper(child: child);
    }

    return child;
  }
}

/// Extracts human-readable copyable content from an output entry.
///
/// Returns null if the entry type doesn't support copying.
String? _extractCopyableContent(OutputEntry entry) {
  switch (entry) {
    case final TextOutputEntry e:
      return e.text.isNotEmpty ? e.text : null;
    case final ToolUseOutputEntry e:
      return _extractToolCopyContent(e);
    default:
      return null;
  }
}

/// Extracts copyable content for tool use entries based on tool type.
String? _extractToolCopyContent(ToolUseOutputEntry entry) {
  switch (entry.toolName) {
    case 'Bash':
      return _extractBashCopyContent(entry);
    case 'Read':
      return entry.toolInput['file_path'] as String?;
    case 'Write':
      return entry.toolInput['file_path'] as String?;
    case 'Edit':
      return _extractEditCopyContent(entry);
    case 'TodoWrite':
      return _extractTodoCopyContent(entry);
    default:
      return _extractGenericToolCopyContent(entry);
  }
}

String? _extractBashCopyContent(ToolUseOutputEntry entry) {
  final command = entry.toolInput['command'] as String?;
  if (command == null) return null;

  final buffer = StringBuffer('\$ $command');

  if (entry.result != null) {
    final output = _extractBashResultText(entry.result);
    if (output.isNotEmpty) {
      buffer.writeln();
      buffer.write(output);
    }
  }

  return buffer.toString();
}

/// Extracts text output from a Bash tool result.
String _extractBashResultText(dynamic result) {
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

String? _extractEditCopyContent(ToolUseOutputEntry entry) {
  final filePath = entry.toolInput['file_path'] as String? ?? '';
  final oldString = entry.toolInput['old_string'] as String? ?? '';
  final newString = entry.toolInput['new_string'] as String? ?? '';
  if (oldString.isEmpty && newString.isEmpty) return null;

  final buffer = StringBuffer();
  buffer.writeln(filePath);
  for (final line in oldString.split('\n')) {
    buffer.writeln('- $line');
  }
  for (final line in newString.split('\n')) {
    buffer.writeln('+ $line');
  }
  return buffer.toString().trimRight();
}

String? _extractTodoCopyContent(ToolUseOutputEntry entry) {
  final result = entry.result;
  if (result is! Map) return null;

  final newTodos = result['newTodos'] as List?;
  if (newTodos == null || newTodos.isEmpty) return null;

  final buffer = StringBuffer();
  for (final todo in newTodos) {
    final todoMap = todo as Map<String, dynamic>;
    final content = todoMap['content'] as String? ?? '';
    final status = todoMap['status'] as String? ?? 'pending';
    final prefix = switch (status) {
      'completed' => '[x]',
      'in_progress' => '[~]',
      _ => '[ ]',
    };
    buffer.writeln('$prefix $content');
  }
  return buffer.toString().trimRight();
}

String? _extractGenericToolCopyContent(ToolUseOutputEntry entry) {
  // For unknown tools, copy the result text if available
  final result = entry.result;
  if (result == null) return null;
  if (result is String) return result.isNotEmpty ? result : null;
  return result.toString();
}

/// Wrapper widget that adds action icons (copy, debug) to the right of an entry.
class _EntryWithActionIcons extends StatefulWidget {
  final Widget child;
  final List<Map<String, dynamic>>? rawMessages;
  final String? copyableContent;

  const _EntryWithActionIcons({
    required this.child,
    this.rawMessages,
    this.copyableContent,
  });

  @override
  State<_EntryWithActionIcons> createState() => _EntryWithActionIconsState();
}

class _EntryWithActionIconsState extends State<_EntryWithActionIcons> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = colorScheme.outline.withValues(alpha: 0.5);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: widget.child),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.copyableContent != null)
                IconButton(
                  key: OutputEntryWidgetKeys.copyContent,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    size: 14,
                    color: _copied ? Colors.green : iconColor,
                  ),
                  tooltip: 'Copy content',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.copyableContent!),
                    );
                    setState(() => _copied = true);
                    Future.delayed(const Duration(seconds: 2), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                ),
              if (widget.rawMessages != null) ...[
                if (widget.copyableContent != null)
                  const SizedBox(height: 2),
                IconButton(
                  key: OutputEntryWidgetKeys.debugIcon,
                  icon: Icon(
                    Icons.data_object,
                    size: 14,
                    color: iconColor,
                  ),
                  tooltip: 'View raw JSON',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => RawJsonViewer(
                          rawMessages: widget.rawMessages!,
                          title:
                              'Raw JSON (${widget.rawMessages!.length} message${widget.rawMessages!.length == 1 ? '' : 's'})',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Wrapper that adds a [HH:MM] timestamp to the left of an entry.
class _TimestampedEntry extends StatelessWidget {
  final DateTime timestamp;
  final Widget child;

  const _TimestampedEntry({
    required this.timestamp,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeText = OutputEntryWidget._timeFormat.format(timestamp);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Timestamp - bottom-aligned
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 2),
          child: Text(
            timeText,
            style: TextStyle(
              fontSize: 10,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
        // Message content - takes remaining space
        Expanded(child: child),
      ],
    );
  }
}

/// Wrapper widget that adds a subtle left border for subagent entries.
class _SubagentEntryWrapper extends StatelessWidget {
  final Widget child;

  const _SubagentEntryWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: colorScheme.tertiary.withValues(alpha: 0.5),
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: child,
    );
  }
}
