import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../state/ticket_view_state.dart';

/// A compact dropdown for selecting the ticket sort order.
///
/// Wired to [TicketViewState.sortOrder] / [TicketViewState.setSortOrder].
class TicketSortDropdown extends StatelessWidget {
  const TicketSortDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final viewState = context.watch<TicketViewState>();
    final theme = Theme.of(context);

    return DropdownButtonHideUnderline(
      child: DropdownButton<TicketSortOrder>(
        value: viewState.sortOrder,
        isDense: true,
        icon: Icon(
          Icons.arrow_drop_down,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        items: [
          for (final order in TicketSortOrder.values)
            DropdownMenuItem(
              value: order,
              child: Text(order.label),
            ),
        ],
        onChanged: (order) {
          if (order != null) viewState.setSortOrder(order);
        },
      ),
    );
  }
}
