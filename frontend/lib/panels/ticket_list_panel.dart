import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../services/ticket_dispatch_service.dart';
import '../state/ticket_board_state.dart';
import '../widgets/ticket_visuals.dart';
import 'panel_wrapper.dart';

/// Test keys for the ticket list panel.
class TicketListPanelKeys {
  TicketListPanelKeys._();
  static const Key searchField = Key('ticket-list-search');
  static const Key addButton = Key('ticket-list-add');
  static const Key startNextButton = Key('ticket-list-start-next');
  static const Key filterButton = Key('ticket-list-filter');
  static const Key listViewToggle = Key('ticket-list-view-toggle');
  static const Key graphViewToggle = Key('ticket-graph-view-toggle');
  static const Key groupByDropdown = Key('ticket-list-group-by');
}

/// Left sidebar panel showing a searchable, filterable, grouped ticket list.
///
/// Provides search, filter controls, group-by headers, and individual ticket
/// items. Tickets are grouped by the currently selected grouping method
/// (category, status, kind, or priority).
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
    return Column(
      children: [
        const _SearchBar(),
        const _Toolbar(),
        const _SubToolbar(),
        Expanded(child: const _TicketList()),
      ],
    );
  }
}

/// Search bar with magnifying glass icon.
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: TextField(
        key: TicketListPanelKeys.searchField,
        onChanged: ticketBoard.setSearchQuery,
        style: AppFonts.monoTextStyle(
          fontSize: 11,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    );
  }
}

/// Toolbar with filter button, start next button, and add button.
class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.watch<TicketBoardState>();
    final hasActiveFilters = ticketBoard.statusFilter != null ||
        ticketBoard.kindFilter != null ||
        ticketBoard.priorityFilter != null;

    final nextTicket = ticketBoard.nextReadyTicket;
    final hasNext = nextTicket != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Filter button with active indicator
          _FilterButton(
            key: TicketListPanelKeys.filterButton,
            hasActiveFilters: hasActiveFilters,
          ),
          const Spacer(),
          // Start Next button
          IconButton(
            key: TicketListPanelKeys.startNextButton,
            onPressed: hasNext
                ? () => _startNextTicket(context, nextTicket.id)
                : null,
            icon: Icon(
              Icons.play_arrow,
              size: 16,
              color: hasNext ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            iconSize: 16,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: hasNext
                ? 'Start next: ${nextTicket.displayId}'
                : 'No ready tickets',
          ),
          const SizedBox(width: 4),
          // Add button
          IconButton(
            key: TicketListPanelKeys.addButton,
            onPressed: () => ticketBoard.showCreateForm(),
            icon: Icon(
              Icons.add,
              size: 16,
              color: colorScheme.primary,
            ),
            iconSize: 16,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            tooltip: 'New ticket',
          ),
        ],
      ),
    );
  }

  void _startNextTicket(BuildContext context, int ticketId) {
    final dispatch = context.read<TicketDispatchService>();
    dispatch.beginInNewWorktree(ticketId);
  }
}

/// Filter button that opens a popup menu with filter options.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.hasActiveFilters,
  });

  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.read<TicketBoardState>();

    return PopupMenuButton<String>(
      tooltip: 'Filter tickets',
      offset: const Offset(0, 28),
      onSelected: (value) => _handleFilterSelection(value, ticketBoard),
      itemBuilder: (context) => _buildFilterItems(context, ticketBoard),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.filter_list,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                if (hasActiveFilters)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            Text(
              'Filter',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildFilterItems(
    BuildContext context,
    TicketBoardState ticketBoard,
  ) {
    final items = <PopupMenuEntry<String>>[];

    // Status filters
    items.add(const PopupMenuItem<String>(
      enabled: false,
      height: 24,
      child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    ));
    for (final status in TicketStatus.values) {
      final isSelected = ticketBoard.statusFilter == status;
      items.add(PopupMenuItem<String>(
        value: 'status:${status.name}',
        height: 32,
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 12)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Text(status.label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ));
    }

    items.add(const PopupMenuDivider(height: 8));

    // Kind filters
    items.add(const PopupMenuItem<String>(
      enabled: false,
      height: 24,
      child: Text('Kind', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    ));
    for (final kind in TicketKind.values) {
      final isSelected = ticketBoard.kindFilter == kind;
      items.add(PopupMenuItem<String>(
        value: 'kind:${kind.name}',
        height: 32,
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 12)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Text(kind.label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ));
    }

    items.add(const PopupMenuDivider(height: 8));

    // Priority filters
    items.add(const PopupMenuItem<String>(
      enabled: false,
      height: 24,
      child: Text('Priority', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    ));
    for (final priority in TicketPriority.values) {
      final isSelected = ticketBoard.priorityFilter == priority;
      items.add(PopupMenuItem<String>(
        value: 'priority:${priority.name}',
        height: 32,
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 12)
            else
              const SizedBox(width: 12),
            const SizedBox(width: 4),
            Text(priority.label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ));
    }

    items.add(const PopupMenuDivider(height: 8));

    // Clear filters
    items.add(const PopupMenuItem<String>(
      value: 'clear',
      height: 32,
      child: Text('Clear filters', style: TextStyle(fontSize: 12)),
    ));

    return items;
  }

  void _handleFilterSelection(String value, TicketBoardState ticketBoard) {
    if (value == 'clear') {
      ticketBoard.setStatusFilter(null);
      ticketBoard.setKindFilter(null);
      ticketBoard.setPriorityFilter(null);
      return;
    }

    final parts = value.split(':');
    if (parts.length != 2) return;

    switch (parts[0]) {
      case 'status':
        final status = TicketStatus.values.firstWhere((s) => s.name == parts[1]);
        // Toggle: if already selected, clear it
        ticketBoard.setStatusFilter(
          ticketBoard.statusFilter == status ? null : status,
        );
      case 'kind':
        final kind = TicketKind.values.firstWhere((k) => k.name == parts[1]);
        ticketBoard.setKindFilter(
          ticketBoard.kindFilter == kind ? null : kind,
        );
      case 'priority':
        final priority = TicketPriority.values.firstWhere((p) => p.name == parts[1]);
        ticketBoard.setPriorityFilter(
          ticketBoard.priorityFilter == priority ? null : priority,
        );
    }
  }
}

/// Sub-toolbar with view toggle (list/graph) and group-by dropdown.
class _SubToolbar extends StatelessWidget {
  const _SubToolbar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ticketBoard = context.watch<TicketBoardState>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // View toggle: list / graph
          _ViewToggle(
            currentMode: ticketBoard.viewMode,
            onChanged: ticketBoard.setViewMode,
          ),
          const Spacer(),
          // Group-by dropdown
          _GroupByDropdown(
            key: TicketListPanelKeys.groupByDropdown,
            currentGroupBy: ticketBoard.groupBy,
            onChanged: ticketBoard.setGroupBy,
          ),
        ],
      ),
    );
  }
}

/// Segmented toggle for list/graph view.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.currentMode,
    required this.onChanged,
  });

  final TicketViewMode currentMode;
  final ValueChanged<TicketViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 24,
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleSegment(
            key: TicketListPanelKeys.listViewToggle,
            icon: Icons.list,
            isActive: currentMode == TicketViewMode.list,
            onTap: () => onChanged(TicketViewMode.list),
          ),
          _ToggleSegment(
            key: TicketListPanelKeys.graphViewToggle,
            icon: Icons.account_tree,
            isActive: currentMode == TicketViewMode.graph,
            onTap: () => onChanged(TicketViewMode.graph),
          ),
        ],
      ),
    );
  }
}

/// A single segment in the view toggle.
class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    super.key,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 24,
        decoration: BoxDecoration(
          color: isActive
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 14,
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Dropdown button for selecting the group-by method.
class _GroupByDropdown extends StatelessWidget {
  const _GroupByDropdown({
    super.key,
    required this.currentGroupBy,
    required this.onChanged,
  });

  final TicketGroupBy currentGroupBy;
  final ValueChanged<TicketGroupBy> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<TicketGroupBy>(
      tooltip: 'Group by',
      offset: const Offset(0, 24),
      onSelected: onChanged,
      itemBuilder: (context) => TicketGroupBy.values.map((groupBy) {
        return PopupMenuItem<TicketGroupBy>(
          value: groupBy,
          height: 32,
          child: Text(
            groupBy.label,
            style: const TextStyle(fontSize: 12),
          ),
        );
      }).toList(),
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.segment, size: 12, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              currentGroupBy.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrollable ticket list, grouped by the current grouping method.
class _TicketList extends StatelessWidget {
  const _TicketList();

  @override
  Widget build(BuildContext context) {
    final ticketBoard = context.watch<TicketBoardState>();
    final grouped = ticketBoard.groupedTickets;
    final categoryProgress = ticketBoard.categoryProgress;

    // Empty state
    if (grouped.isEmpty) {
      return const _EmptyTicketList();
    }

    // Flatten grouped tickets into a flat list of (header, ticket) items.
    final items = <_ListItem>[];
    for (final entry in grouped.entries) {
      final progress = categoryProgress[entry.key];
      items.add(_ListItem.header(
        entry.key,
        completed: progress?.completed ?? 0,
        total: progress?.total ?? 0,
      ));
      for (final ticket in entry.value) {
        items.add(_ListItem.ticket(ticket));
      }
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.isHeader) {
          return _GroupHeader(
            name: item.headerName!,
            completed: item.completed,
            total: item.total,
          );
        }
        final ticket = item.ticketData!;
        final isSelected = ticketBoard.selectedTicket?.id == ticket.id;
        return _TicketListItem(
          ticket: ticket,
          isSelected: isSelected,
          onTap: () => ticketBoard.selectTicket(ticket.id),
        );
      },
    );
  }
}

/// Represents either a group header or a ticket in the flat list.
class _ListItem {
  final bool isHeader;
  final String? headerName;
  final int completed;
  final int total;
  final TicketData? ticketData;

  const _ListItem._({
    required this.isHeader,
    this.headerName,
    this.completed = 0,
    this.total = 0,
    this.ticketData,
  });

  factory _ListItem.header(String name, {required int completed, required int total}) =>
      _ListItem._(isHeader: true, headerName: name, completed: completed, total: total);

  factory _ListItem.ticket(TicketData data) =>
      _ListItem._(isHeader: false, ticketData: data);
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

/// A group header showing the category name, progress count, and bar.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.completed,
    required this.total,
  });

  final String name;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = total > 0 ? completed / total : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            '$completed/$total',
            style: AppFonts.monoTextStyle(
              fontSize: 10,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 40,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single ticket item in the list.
class _TicketListItem extends StatelessWidget {
  const _TicketListItem({
    required this.ticket,
    required this.isSelected,
    required this.onTap,
  });

  final TicketData ticket;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTerminal = ticket.isTerminal;

    return Opacity(
      opacity: isTerminal ? 0.5 : 1.0,
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            child: Row(
              children: [
                // Status icon
                TicketStatusIcon(status: ticket.status, size: 14),
                const SizedBox(width: 6),
                // Display ID (monospace)
                SizedBox(
                  width: 52,
                  child: Text(
                    ticket.displayId,
                    style: AppFonts.monoTextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Title
                Expanded(
                  child: Text(
                    ticket.title,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      decoration: isTerminal ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 6),
                // Effort badge
                EffortBadge(effort: ticket.effort),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
