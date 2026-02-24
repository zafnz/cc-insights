import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../state/ticket_view_state.dart';
import '../widgets/ticket_filter_chips.dart';
import '../widgets/ticket_list_item.dart';
import '../widgets/ticket_sort_dropdown.dart';
import '../widgets/ticket_status_tabs.dart';
import 'panel_wrapper.dart';

/// Test keys for the ticket list panel.
class TicketListPanelKeys {
  TicketListPanelKeys._();
  static const Key searchField = Key('ticket-list-search');
  static const Key addButton = Key('ticket-list-add');
}

/// Left sidebar panel showing a searchable, filterable ticket list.
///
/// Layout (top to bottom):
/// 1. Panel header — icon + "Tickets" title + drag handle
/// 2. Search bar — text field + "+" button for create
/// 3. Status tabs (Open/Closed with counts)
/// 4. Sort dropdown
/// 5. Filter chips (conditional on active tag filters)
/// 6. Ticket list — ListView.builder of TicketListItem widgets
class TicketListPanel extends StatelessWidget {
  const TicketListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return PanelWrapper(
      title: 'Tickets',
      icon: Icons.task_alt,
      child: const _TicketListContent(),
    );
  }
}

/// Internal content of the ticket list panel.
class _TicketListContent extends StatelessWidget {
  const _TicketListContent();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SearchBar(),
        _StatusTabsRow(),
        _SortRow(),
        TicketFilterChips(),
        Expanded(child: _TicketList()),
      ],
    );
  }
}

/// Search bar with magnifying glass icon and "+" create button.
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewState = context.read<TicketViewState>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: TicketListPanelKeys.searchField,
              onChanged: viewState.setSearchQuery,
              style: AppFonts.monoTextStyle(
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                hintText: 'Search tickets...',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  child: Icon(
                    Icons.search,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: TicketListPanelKeys.addButton,
            onPressed: () => viewState.showCreateForm(),
            icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
            iconSize: 16,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: 'New ticket',
          ),
        ],
      ),
    );
  }
}

/// Row wrapping the TicketStatusTabs with border decoration.
class _StatusTabsRow extends StatelessWidget {
  const _StatusTabsRow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: const TicketStatusTabs(),
    );
  }
}

/// Row with the sort dropdown.
class _SortRow extends StatelessWidget {
  const _SortRow();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Sort:',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          const TicketSortDropdown(),
        ],
      ),
    );
  }
}

/// The scrollable ticket list using TicketListItem widgets.
class _TicketList extends StatelessWidget {
  const _TicketList();

  @override
  Widget build(BuildContext context) {
    final viewState = context.watch<TicketViewState>();
    final tickets = viewState.filteredTickets;

    if (tickets.isEmpty) {
      return const _EmptyTicketList();
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        final isSelected = viewState.selectedTicketId == ticket.id;
        return TicketListItem(
          ticket: ticket,
          isSelected: isSelected,
          onTap: () => viewState.selectTicket(ticket.id),
        );
      },
    );
  }
}

/// Empty state placeholder.
class _EmptyTicketList extends StatelessWidget {
  const _EmptyTicketList();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt,
            size: 32,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            'No tickets',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
