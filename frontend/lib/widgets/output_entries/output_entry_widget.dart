import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    Widget child;
    List<Map<String, dynamic>>? rawMessages;

    switch (entry) {
      case final TextOutputEntry e:
        child = TextEntryWidget(entry: e);
        rawMessages = e.rawMessages;
      case final ToolUseOutputEntry e:
        child = ToolCard(entry: e, projectDir: projectDir);
        rawMessages = e.rawMessages;
      case final UserInputEntry e:
        child = UserInputEntryWidget(entry: e);
      case final ContextSummaryEntry e:
        child = ContextSummaryEntryWidget(entry: e);
      case ContextClearedEntry():
        child = const ContextClearedEntryWidget();
      case final SessionMarkerEntry e:
        child = SessionMarkerEntryWidget(entry: e);
      case final AutoCompactionEntry e:
        child = AutoCompactionEntryWidget(entry: e);
      case final UnknownMessageEntry e:
        child = UnknownMessageEntryWidget(entry: e);
      case final SystemNotificationEntry e:
        child = SystemNotificationEntryWidget(entry: e);
      default:
        return const SizedBox.shrink();
    }

    // Wrap with debug icon if enabled and has raw messages
    final config = RuntimeConfig.instance;
    if (config.showRawMessages &&
        rawMessages != null &&
        rawMessages.isNotEmpty) {
      child = _EntryWithDebugIcon(
        rawMessages: rawMessages,
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

/// Wrapper widget that adds a debug icon to the right of an entry.
class _EntryWithDebugIcon extends StatelessWidget {
  final Widget child;
  final List<Map<String, dynamic>> rawMessages;

  const _EntryWithDebugIcon({
    required this.child,
    required this.rawMessages,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: IconButton(
            key: OutputEntryWidgetKeys.debugIcon,
            icon: Icon(
              Icons.data_object,
              size: 14,
              color: colorScheme.outline.withValues(alpha: 0.5),
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
                    rawMessages: rawMessages,
                    title:
                        'Raw JSON (${rawMessages.length} message${rawMessages.length == 1 ? '' : 's'})',
                  ),
                ),
              );
            },
          ),
        ),
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
