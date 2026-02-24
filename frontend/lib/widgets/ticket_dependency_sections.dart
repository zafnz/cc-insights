import 'package:flutter/material.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';

/// Sidebar section displaying tickets this ticket depends on.
///
/// Shows an uppercase "DEPENDS ON" header with a bottom border, followed by a
/// list of dependency tickets. Each entry shows a status icon (green check if
/// closed, grey circle if open), the ticket ID in monospace, and a truncated
/// title. Clicking an entry navigates to that ticket.
///
/// Returns [SizedBox.shrink] when there are no dependencies.
class DependsOnSection extends StatelessWidget {
  /// IDs of tickets this ticket depends on.
  final List<int> dependsOn;

  /// All tickets, used to look up dependency details.
  final List<TicketData> allTickets;

  /// Called when a dependency ticket is tapped.
  final ValueChanged<int> onTicketTap;

  const DependsOnSection({
    super.key,
    required this.dependsOn,
    required this.allTickets,
    required this.onTicketTap,
  });

  @override
  Widget build(BuildContext context) {
    if (dependsOn.isEmpty) return const SizedBox.shrink();

    final ticketMap = {for (final t in allTickets) t.id: t};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(label: 'DEPENDS ON'),
        for (final depId in dependsOn)
          _DependencyTile(
            ticket: ticketMap[depId],
            ticketId: depId,
            onTap: () => onTicketTap(depId),
          ),
      ],
    );
  }
}

/// Sidebar section displaying tickets that depend on (are blocked by) this
/// ticket.
///
/// Performs a reverse lookup across [allTickets] to find tickets whose
/// [TicketData.dependsOn] list contains [ticketId]. Shows an uppercase
/// "BLOCKS" header with a bottom border, followed by the same entry format
/// as [DependsOnSection].
///
/// Returns [SizedBox.shrink] when no tickets are blocked.
class BlocksSection extends StatelessWidget {
  /// The ID of the current ticket.
  final int ticketId;

  /// All tickets, used for the reverse dependency lookup.
  final List<TicketData> allTickets;

  /// Called when a blocked ticket is tapped.
  final ValueChanged<int> onTicketTap;

  const BlocksSection({
    super.key,
    required this.ticketId,
    required this.allTickets,
    required this.onTicketTap,
  });

  @override
  Widget build(BuildContext context) {
    final blockedTickets =
        allTickets.where((t) => t.dependsOn.contains(ticketId)).toList();

    if (blockedTickets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(label: 'BLOCKS'),
        for (final ticket in blockedTickets)
          _DependencyTile(
            ticket: ticket,
            ticketId: ticket.id,
            onTap: () => onTicketTap(ticket.id),
          ),
      ],
    );
  }
}

/// Uppercase section header with a bottom border.
class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      margin: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A single dependency row: status icon + #id (monospace) + truncated title.
class _DependencyTile extends StatelessWidget {
  /// The resolved ticket data (null if the ticket ID wasn't found).
  final TicketData? ticket;

  /// The ticket ID to display.
  final int ticketId;

  /// Called when the tile is tapped.
  final VoidCallback onTap;

  const _DependencyTile({
    required this.ticket,
    required this.ticketId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClosed = ticket != null && !ticket!.isOpen;
    final title = ticket?.title ?? 'Unknown ticket';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(
            children: [
              Icon(
                isClosed ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: isClosed ? Colors.green : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Text(
                '#$ticketId',
                style: AppFonts.monoTextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
