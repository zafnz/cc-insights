import 'package:flutter/material.dart';

import '../models/ticket.dart';
import '../state/ticket_board_state.dart';
import 'ticket_dependency_sections.dart';
import 'ticket_linked_sections.dart';
import 'ticket_tags_section.dart';

/// Assembled sidebar for a ticket detail view.
///
/// Stacks all sidebar sections vertically in a fixed-width, independently
/// scrollable column:
///   1. Tags
///   2. Linked Chats
///   3. Linked Worktrees
///   4. Depends On
///   5. Blocks
class TicketSidebar extends StatelessWidget {
  final TicketData ticket;
  final List<TicketData> allTickets;
  final TicketRepository repo;

  /// Called when a tag "+" button is tapped.
  final VoidCallback? onAddTag;

  /// Called when a linked chat is tapped.
  final ValueChanged<LinkedChat>? onChatTap;

  /// Called when a linked worktree is tapped.
  final ValueChanged<LinkedWorktree>? onWorktreeTap;

  /// Called when a dependency or blocked ticket is tapped.
  final ValueChanged<int>? onTicketTap;

  const TicketSidebar({
    super.key,
    required this.ticket,
    required this.allTickets,
    required this.repo,
    this.onAddTag,
    this.onChatTap,
    this.onWorktreeTap,
    this.onTicketTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TagsSection(
              tags: ticket.tags.toList()..sort(),
              onAddTag: onAddTag ?? () {},
              onRemoveTag: (tag) => repo.removeTag(
                ticket.id,
                tag,
                'user',
                AuthorType.user,
              ),
            ),
            const SizedBox(height: 16),
            LinkedChatsSection(
              linkedChats: ticket.linkedChats,
              onChatTap: onChatTap ?? (_) {},
            ),
            LinkedWorktreesSection(
              linkedWorktrees: ticket.linkedWorktrees,
              onWorktreeTap: onWorktreeTap ?? (_) {},
            ),
            DependsOnSection(
              dependsOn: ticket.dependsOn,
              allTickets: allTickets,
              onTicketTap: onTicketTap ?? (_) {},
            ),
            BlocksSection(
              ticketId: ticket.id,
              allTickets: allTickets,
              onTicketTap: onTicketTap ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }
}
