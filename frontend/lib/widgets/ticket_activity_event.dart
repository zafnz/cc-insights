import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';
import 'ticket_tag_chip.dart';
import 'ticket_timeline_utils.dart';

/// A compact timeline entry widget for activity events on a ticket.
///
/// Displays a timeline dot (with an icon indicating the event type) on the
/// left, and an event text row on the right showing the actor name, event
/// description (with inline tag chips where applicable), and a right-aligned
/// timestamp.
///
/// Accepts a [CoalescedEvent] which may contain multiple related events from
/// the same actor within a 5-second window — these are rendered as a single
/// combined entry.
class TicketActivityEvent extends StatelessWidget {
  const TicketActivityEvent({
    super.key,
    required this.coalescedEvent,
  });

  /// The coalesced group of activity events to display.
  final CoalescedEvent coalescedEvent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dotColor = _dotColor(coalescedEvent.events.first.type, colorScheme);
    final dotIcon = _dotIcon(coalescedEvent.events.first.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Timeline dot
          _TimelineDot(color: dotColor, icon: dotIcon),
          const SizedBox(width: 10),
          // Event content
          Expanded(
            child: Row(
              children: [
                // Actor + description
                Expanded(
                  child: _EventDescription(
                    coalescedEvent: coalescedEvent,
                    textTheme: textTheme,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 8),
                // Timestamp
                Text(
                  _formatTimestamp(coalescedEvent.timestamp),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The circular timeline dot with an icon inside.
class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surface,
        border: Border.all(color: color, width: 2),
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}

/// The event description row: actor name + badge + event text spans.
class _EventDescription extends StatelessWidget {
  const _EventDescription({
    required this.coalescedEvent,
    required this.textTheme,
    required this.colorScheme,
  });

  final CoalescedEvent coalescedEvent;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final children = <InlineSpan>[];

    // Actor name (bold).
    children.add(TextSpan(
      text: coalescedEvent.actor,
      style: textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
    ));

    // Agent badge (if applicable).
    if (coalescedEvent.actorType == AuthorType.agent) {
      children.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _InlineAgentBadge(),
      ));
    }

    // Event descriptions for each event in the coalesced group.
    for (final event in coalescedEvent.events) {
      _addEventSpans(children, event);
    }

    return Text.rich(
      TextSpan(children: children),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  void _addEventSpans(List<InlineSpan> spans, ActivityEvent event) {
    final baseStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    switch (event.type) {
      case ActivityEventType.tagAdded:
        spans.add(TextSpan(text: ' added ', style: baseStyle));
        final tag = event.data['tag'] as String? ?? '';
        if (tag.isNotEmpty) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TicketTagChip(tag: tag, fontSize: 10),
          ));
        }

      case ActivityEventType.tagRemoved:
        spans.add(TextSpan(text: ' removed ', style: baseStyle));
        final tag = event.data['tag'] as String? ?? '';
        if (tag.isNotEmpty) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: TicketTagChip(tag: tag, fontSize: 10),
          ));
        }

      case ActivityEventType.worktreeLinked:
        final branch = event.data['branch'] as String? ??
            event.data['worktreeRoot'] as String? ??
            '';
        spans.add(TextSpan(text: ' linked worktree ', style: baseStyle));
        if (branch.isNotEmpty) {
          spans.add(TextSpan(
            text: branch,
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.worktreeUnlinked:
        final branch = event.data['branch'] as String? ??
            event.data['worktreeRoot'] as String? ??
            '';
        spans.add(TextSpan(text: ' unlinked worktree ', style: baseStyle));
        if (branch.isNotEmpty) {
          spans.add(TextSpan(
            text: branch,
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.chatLinked:
        final chatName = event.data['chatName'] as String? ?? '';
        spans.add(TextSpan(text: ' linked chat ', style: baseStyle));
        if (chatName.isNotEmpty) {
          spans.add(TextSpan(
            text: chatName,
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.chatUnlinked:
        final chatName = event.data['chatName'] as String? ?? '';
        spans.add(TextSpan(text: ' unlinked chat ', style: baseStyle));
        if (chatName.isNotEmpty) {
          spans.add(TextSpan(
            text: chatName,
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.closed:
        spans.add(TextSpan(text: ' closed this', style: baseStyle));

      case ActivityEventType.reopened:
        spans.add(TextSpan(text: ' reopened this', style: baseStyle));

      case ActivityEventType.dependencyAdded:
        final depId = event.data['ticketId'];
        spans.add(TextSpan(text: ' added dependency ', style: baseStyle));
        if (depId != null) {
          spans.add(TextSpan(
            text: '#$depId',
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.dependencyRemoved:
        final depId = event.data['ticketId'];
        spans.add(TextSpan(text: ' removed dependency ', style: baseStyle));
        if (depId != null) {
          spans.add(TextSpan(
            text: '#$depId',
            style: baseStyle?.copyWith(fontWeight: FontWeight.w500),
          ));
        }

      case ActivityEventType.titleEdited:
        spans.add(TextSpan(text: ' edited the title', style: baseStyle));

      case ActivityEventType.bodyEdited:
        spans.add(TextSpan(text: ' edited the body', style: baseStyle));
    }
  }
}

/// Small inline "agent" badge for use within a Text.rich span.
class _InlineAgentBadge extends StatelessWidget {
  const _InlineAgentBadge();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Text(
          'agent',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Colors.blue.shade700,
          ),
        ),
      ),
    );
  }
}

/// Returns the dot icon for a given [ActivityEventType].
IconData _dotIcon(ActivityEventType type) {
  switch (type) {
    case ActivityEventType.tagAdded:
    case ActivityEventType.tagRemoved:
      return Icons.sell;
    case ActivityEventType.worktreeLinked:
    case ActivityEventType.worktreeUnlinked:
      return Icons.account_tree;
    case ActivityEventType.chatLinked:
    case ActivityEventType.chatUnlinked:
      return Icons.chat_bubble_outline;
    case ActivityEventType.closed:
      return Icons.check_circle;
    case ActivityEventType.reopened:
      return Icons.radio_button_checked;
    case ActivityEventType.dependencyAdded:
    case ActivityEventType.dependencyRemoved:
      return Icons.link;
    case ActivityEventType.titleEdited:
    case ActivityEventType.bodyEdited:
      return Icons.edit;
  }
}

/// Returns the dot colour for a given [ActivityEventType].
///
/// Categories: tag = primary, link = blue, status = green, edit = orange.
Color _dotColor(ActivityEventType type, ColorScheme colorScheme) {
  switch (type) {
    case ActivityEventType.tagAdded:
    case ActivityEventType.tagRemoved:
      return colorScheme.primary;
    case ActivityEventType.worktreeLinked:
    case ActivityEventType.worktreeUnlinked:
    case ActivityEventType.chatLinked:
    case ActivityEventType.chatUnlinked:
    case ActivityEventType.dependencyAdded:
    case ActivityEventType.dependencyRemoved:
      return Colors.blue;
    case ActivityEventType.closed:
    case ActivityEventType.reopened:
      return const Color(0xFF4CAF50);
    case ActivityEventType.titleEdited:
    case ActivityEventType.bodyEdited:
      return Colors.orange;
  }
}

/// Formats a [DateTime] for display in activity event timestamps.
///
/// - Same day as now: time only (e.g. "15:30")
/// - Same year as now: day + abbreviated month (e.g. "22 Jun")
/// - Different year: day + abbreviated month + year (e.g. "22 Jun 2025")
String _formatTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final local = timestamp.toLocal();

  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat('HH:mm').format(local);
  }

  if (local.year == now.year) {
    return DateFormat('d MMM').format(local);
  }

  return DateFormat('d MMM yyyy').format(local);
}
