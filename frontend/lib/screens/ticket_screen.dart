import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../panels/ticket_bulk_review_panel.dart';
import '../panels/ticket_create_form.dart';
import '../panels/ticket_detail_panel.dart';
import '../panels/ticket_graph_view.dart';
import '../panels/ticket_list_panel.dart';
import '../state/ticket_board_state.dart';

/// Ticket management screen with list and detail panels.
///
/// Layout structure:
/// - When [TicketViewMode.list]: Row with fixed-width left panel (320px) for
///   ticket list + flexible right panel switching on [TicketDetailMode]
/// - When [TicketViewMode.graph]: Row with fixed-width left panel + flexible
///   [TicketGraphView] for the dependency graph visualization
class TicketScreen extends StatelessWidget {
  const TicketScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.watch<TicketBoardState>();

    return Row(
      children: [
        // Left panel: Ticket List (fixed width)
        SizedBox(
          width: 320,
          child: Material(
            color: colorScheme.surface,
            child: const TicketListPanel(),
          ),
        ),
        // Divider
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        // Right panel: graph view or detail mode
        Expanded(
          child: Material(
            color: colorScheme.surface,
            child: ticketBoard.viewMode == TicketViewMode.graph
                ? const TicketGraphView()
                : switch (ticketBoard.detailMode) {
                    TicketDetailMode.detail => const TicketDetailPanel(),
                    TicketDetailMode.edit => TicketCreateForm(
                        editingTicket: ticketBoard.selectedTicket,
                      ),
                    TicketDetailMode.create => const TicketCreateForm(),
                    TicketDetailMode.bulkReview =>
                      const TicketBulkReviewPanel(),
                  },
          ),
        ),
      ],
    );
  }
}
