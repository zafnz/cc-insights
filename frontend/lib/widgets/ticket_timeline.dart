import 'package:flutter/material.dart';

import '../models/ticket.dart';
import 'ticket_activity_event.dart';
import 'ticket_comment_block.dart';
import 'ticket_timeline_utils.dart';

/// The ticket timeline widget.
///
/// Renders a vertical scrollable timeline consisting of:
/// 1. The ticket body as the first [TicketCommentBlock]
/// 2. Interleaved activity events and comments sorted chronologically
///
/// A 2px vertical timeline line runs along the left side, connecting
/// activity event dots. The new-comment input is handled by the parent.
class TicketTimeline extends StatelessWidget {
  const TicketTimeline({
    super.key,
    required this.ticket,
  });

  /// The ticket whose timeline to display.
  final TicketData ticket;

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

    return SingleChildScrollView(
      child: Stack(
        children: [
          // Timeline line — 2px, ~13px from left.
          Positioned(
            left: 13,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2,
              color: const Color.fromRGBO(73, 69, 79, 0.4),
            ),
          ),
          // Content column.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Body block (always first).
              Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 12),
                child: TicketCommentBlock(
                  author: ticket.author,
                  authorType: AuthorType.user,
                  ticketAuthor: ticket.author,
                  timestamp: ticket.createdAt,
                  markdownContent: ticket.body,
                  images: ticket.bodyImages,
                ),
              ),
              // Interleaved events and comments.
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: switch (entry) {
                    _ActivityEntry(:final coalescedEvent) =>
                      TicketActivityEvent(coalescedEvent: coalescedEvent),
                    _CommentEntry(:final comment) => Padding(
                        padding: const EdgeInsets.only(left: 34),
                        child: TicketCommentBlock(
                          author: comment.author,
                          authorType: comment.authorType,
                          ticketAuthor: ticket.author,
                          timestamp: comment.createdAt,
                          markdownContent: comment.text,
                          images: comment.images,
                        ),
                      ),
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds a chronologically sorted list of timeline entries by merging
  /// coalesced activity events and comments.
  List<_TimelineEntry> _buildEntries() {
    // Coalesce activity events.
    final coalesced = coalesceEvents(ticket.activityLog);

    final entries = <_TimelineEntry>[
      for (final ce in coalesced) _ActivityEntry(ce),
      for (final c in ticket.comments) _CommentEntry(c),
    ];

    entries.sort();
    return entries;
  }
}

/// A single entry in the merged timeline.
sealed class _TimelineEntry implements Comparable<_TimelineEntry> {
  DateTime get timestamp;

  @override
  int compareTo(_TimelineEntry other) => timestamp.compareTo(other.timestamp);
}

/// An entry backed by a [CoalescedEvent].
class _ActivityEntry extends _TimelineEntry {
  _ActivityEntry(this.coalescedEvent);

  final CoalescedEvent coalescedEvent;

  @override
  DateTime get timestamp => coalescedEvent.timestamp;
}

/// An entry backed by a [TicketComment].
class _CommentEntry extends _TimelineEntry {
  _CommentEntry(this.comment);

  final TicketComment comment;

  @override
  DateTime get timestamp => comment.createdAt;
}
