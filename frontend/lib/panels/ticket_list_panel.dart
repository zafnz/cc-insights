import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import '../services/internal_tools_service.dart';
import '../services/ticket_dispatch_factory.dart';
import '../services/ticket_dispatch_service.dart';
import '../state/ticket_board_state.dart';
import '../state/ticket_view_state.dart';
import '../widgets/ticket_visuals.dart';
import '../widgets/orchestration_config_dialog.dart';
import 'panel_wrapper.dart';

/// Test keys for the ticket list panel.
class TicketListPanelKeys {
  TicketListPanelKeys._();
  static const Key searchField = Key('ticket-list-search');
  static const Key addButton = Key('ticket-list-add');
  static const Key startNextButton = Key('ticket-list-start-next');
  static const Key filterButton = Key('ticket-list-filter');
  static const Key runButton = Key('ticket-list-run');
  static const Key bulkChangeButton = Key('ticket-list-bulk-change');
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
    );
  }
}

/// Toolbar with filter button, start next button, and add button.
class _Toolbar extends StatelessWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewState = context.watch<TicketViewState>();
    final hasActiveFilters =
        viewState.statusFilter != null ||
        viewState.kindFilter != null ||
        viewState.priorityFilter != null;

    final nextTicket = viewState.nextReadyTicket;
    final hasNext = nextTicket != null;
    final selectedCount = viewState.selectedTicketIds.length;
    final canRun = selectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 280;
          final buttonStyle = IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
          return Row(
            children: [
              // Filter button with active indicator
              _FilterButton(
                key: TicketListPanelKeys.filterButton,
                hasActiveFilters: hasActiveFilters,
                compact: compact,
              ),
              const Spacer(),
              IconButton(
                key: TicketListPanelKeys.runButton,
                onPressed: canRun ? () => _openRunDialog(context) : null,
                icon: Icon(
                  Icons.hub,
                  size: 16,
                  color: canRun
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                tooltip: canRun
                    ? 'Run $selectedCount tickets…'
                    : 'Select tickets to run',
                iconSize: 16,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                padding: EdgeInsets.zero,
                style: buttonStyle,
              ),
              if (canRun)
                _BulkChangeButton(
                  key: TicketListPanelKeys.bulkChangeButton,
                  selectedCount: selectedCount,
                ),
              // Start Next button
              IconButton(
                key: TicketListPanelKeys.startNextButton,
                onPressed: hasNext
                    ? () => _startNextTicket(context, nextTicket.id)
                    : null,
                icon: Icon(
                  Icons.play_arrow,
                  size: 16,
                  color: hasNext
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                style: buttonStyle,
                tooltip: hasNext
                    ? 'Start next: ${nextTicket.displayId}'
                    : 'No ready tickets',
              ),
              const SizedBox(width: 4),
              // Add button
              IconButton(
                key: TicketListPanelKeys.addButton,
                onPressed: () => viewState.showCreateForm(),
                icon: Icon(Icons.add, size: 16, color: colorScheme.primary),
                iconSize: 16,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                style: buttonStyle,
                tooltip: 'New ticket',
              ),
            ],
          );
        },
      ),
    );
  }

  void _startNextTicket(BuildContext context, int ticketId) {
    final dispatch = _createDispatchService(context);
    dispatch.beginInNewWorktree(ticketId);
  }

  Future<void> _openRunDialog(BuildContext context) async {
    final view = context.read<TicketViewState>();
    await showDialog<bool>(
      context: context,
      builder: (_) => OrchestrationConfigDialog(
        ticketIds: view.selectedTicketIds.toList()..sort(),
      ),
    );
  }

  TicketDispatchService _createDispatchService(BuildContext context) {
    return createTicketDispatchService(context);
  }
}

/// The bulk change actions available in the popup menu.
enum BulkChangeAction {
  category,
  status,
  kind,
  priority,
  delete,
}

/// Popup menu button for bulk-changing selected tickets.
///
/// Shows a menu with Category, Status, Kind, Priority, and Delete options.
/// Only rendered when tickets are selected (controlled by the parent toolbar).
class _BulkChangeButton extends StatelessWidget {
  const _BulkChangeButton({
    super.key,
    required this.selectedCount,
  });

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<BulkChangeAction>(
      tooltip: 'Bulk change $selectedCount tickets',
      offset: const Offset(0, 28),
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (_) => [
        const PopupMenuItem<BulkChangeAction>(
          value: BulkChangeAction.category,
          height: 32,
          child: Text('Category', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem<BulkChangeAction>(
          value: BulkChangeAction.status,
          height: 32,
          child: Text('Status', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem<BulkChangeAction>(
          value: BulkChangeAction.kind,
          height: 32,
          child: Text('Kind', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem<BulkChangeAction>(
          value: BulkChangeAction.priority,
          height: 32,
          child: Text('Priority', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuDivider(height: 8),
        const PopupMenuItem<BulkChangeAction>(
          value: BulkChangeAction.delete,
          height: 32,
          child: Text('Delete', style: TextStyle(fontSize: 12)),
        ),
      ],
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
            Icon(Icons.edit, size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              'Change',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, BulkChangeAction action) {
    switch (action) {
      case BulkChangeAction.category:
        _changeCategoryBulk(context);
      case BulkChangeAction.status:
        _changeEnumBulk<TicketStatus>(
          context,
          fieldName: 'status',
          values: TicketStatus.values,
          labelOf: (v) => v.label,
          apply: (repo, ids, value) {
            for (final id in ids) {
              repo.updateTicket(id, (t) => t.copyWith(status: value));
            }
          },
        );
      case BulkChangeAction.kind:
        _changeEnumBulk<TicketKind>(
          context,
          fieldName: 'kind',
          values: TicketKind.values,
          labelOf: (v) => v.label,
          apply: (repo, ids, value) {
            for (final id in ids) {
              repo.updateTicket(id, (t) => t.copyWith(kind: value));
            }
          },
        );
      case BulkChangeAction.priority:
        _changeEnumBulk<TicketPriority>(
          context,
          fieldName: 'priority',
          values: TicketPriority.values,
          labelOf: (v) => v.label,
          apply: (repo, ids, value) {
            for (final id in ids) {
              repo.updateTicket(id, (t) => t.copyWith(priority: value));
            }
          },
        );
      case BulkChangeAction.delete:
        _deleteBulk(context);
    }
  }

  Future<void> _changeEnumBulk<T>(
    BuildContext context, {
    required String fieldName,
    required List<T> values,
    required String Function(T) labelOf,
    required void Function(TicketRepository, Set<int>, T) apply,
  }) async {
    final viewState = context.read<TicketViewState>();
    final repo = context.read<TicketRepository>();
    final ids = viewState.selectedTicketIds;

    final value = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Change $fieldName'),
        children: values.map((v) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(v),
            child: Text(labelOf(v)),
          );
        }).toList(),
      ),
    );
    if (value == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm bulk change'),
        content: Text(
          'Are you sure you want to change $fieldName to '
          '${labelOf(value)} for ${ids.length} tickets?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    apply(repo, ids, value);
  }

  Future<void> _changeCategoryBulk(BuildContext context) async {
    final viewState = context.read<TicketViewState>();
    final repo = context.read<TicketRepository>();
    final ids = viewState.selectedTicketIds;
    final categories = viewState.allCategories;

    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => _CategoryPickerDialog(categories: categories),
    );
    if (value == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm bulk change'),
        content: Text(
          'Are you sure you want to change category to '
          '$value for ${ids.length} tickets?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in ids) {
      repo.updateTicket(id, (t) => t.copyWith(category: value));
    }
  }

  Future<void> _deleteBulk(BuildContext context) async {
    final viewState = context.read<TicketViewState>();
    final repo = context.read<TicketRepository>();
    final ids = viewState.selectedTicketIds.toSet();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm bulk delete'),
        content: Text(
          'Are you sure you want to delete ${ids.length} tickets? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in ids) {
      repo.deleteTicket(id);
    }
    viewState.clearTicketSelection();
  }
}

/// Dialog for picking a category from existing ones or entering a new one.
class _CategoryPickerDialog extends StatefulWidget {
  const _CategoryPickerDialog({required this.categories});

  final List<String> categories;

  @override
  State<_CategoryPickerDialog> createState() => _CategoryPickerDialogState();
}

class _CategoryPickerDialogState extends State<_CategoryPickerDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Change category'),
      children: [
        ...widget.categories.map((cat) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(cat),
            child: Text(cat),
          );
        }),
        if (widget.categories.isNotEmpty)
          const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'New category...',
                  ),
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isNotEmpty) {
                      Navigator.of(context).pop(trimmed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final trimmed = _controller.text.trim();
                  if (trimmed.isNotEmpty) {
                    Navigator.of(context).pop(trimmed);
                  }
                },
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Filter button that opens a popup menu with filter options.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.hasActiveFilters,
    this.compact = false,
  });

  final bool hasActiveFilters;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final viewState = context.read<TicketViewState>();

    return PopupMenuButton<String>(
      tooltip: 'Filter tickets',
      offset: const Offset(0, 28),
      onSelected: (value) => _handleFilterSelection(value, viewState),
      itemBuilder: (context) => _buildFilterItems(context, viewState),
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
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
            if (!compact) ...[
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
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildFilterItems(
    BuildContext context,
    TicketViewState viewState,
  ) {
    final items = <PopupMenuEntry<String>>[];

    // Status filters
    items.add(
      const PopupMenuItem<String>(
        enabled: false,
        height: 24,
        child: Text(
          'Status',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
    for (final status in TicketStatus.values) {
      final isSelected = viewState.statusFilter == status;
      items.add(
        PopupMenuItem<String>(
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
        ),
      );
    }

    items.add(const PopupMenuDivider(height: 8));

    // Kind filters
    items.add(
      const PopupMenuItem<String>(
        enabled: false,
        height: 24,
        child: Text(
          'Kind',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
    for (final kind in TicketKind.values) {
      final isSelected = viewState.kindFilter == kind;
      items.add(
        PopupMenuItem<String>(
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
        ),
      );
    }

    items.add(const PopupMenuDivider(height: 8));

    // Priority filters
    items.add(
      const PopupMenuItem<String>(
        enabled: false,
        height: 24,
        child: Text(
          'Priority',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
    for (final priority in TicketPriority.values) {
      final isSelected = viewState.priorityFilter == priority;
      items.add(
        PopupMenuItem<String>(
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
        ),
      );
    }

    items.add(const PopupMenuDivider(height: 8));

    // Clear filters
    items.add(
      const PopupMenuItem<String>(
        value: 'clear',
        height: 32,
        child: Text('Clear filters', style: TextStyle(fontSize: 12)),
      ),
    );

    return items;
  }

  void _handleFilterSelection(String value, TicketViewState viewState) {
    if (value == 'clear') {
      viewState.setStatusFilter(null);
      viewState.setKindFilter(null);
      viewState.setPriorityFilter(null);
      return;
    }

    final parts = value.split(':');
    if (parts.length != 2) return;

    switch (parts[0]) {
      case 'status':
        final status = TicketStatus.values.firstWhere(
          (s) => s.name == parts[1],
        );
        // Toggle: if already selected, clear it
        viewState.setStatusFilter(
          viewState.statusFilter == status ? null : status,
        );
      case 'kind':
        final kind = TicketKind.values.firstWhere((k) => k.name == parts[1]);
        viewState.setKindFilter(viewState.kindFilter == kind ? null : kind);
      case 'priority':
        final priority = TicketPriority.values.firstWhere(
          (p) => p.name == parts[1],
        );
        viewState.setPriorityFilter(
          viewState.priorityFilter == priority ? null : priority,
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
    final viewState = context.watch<TicketViewState>();

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
            currentMode: viewState.viewMode,
            onChanged: viewState.setViewMode,
          ),
          const Spacer(),
          // Group-by dropdown
          _GroupByDropdown(
            key: TicketListPanelKeys.groupByDropdown,
            currentGroupBy: viewState.groupBy,
            onChanged: viewState.setGroupBy,
          ),
        ],
      ),
    );
  }
}

/// Segmented toggle for list/graph view.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.currentMode, required this.onChanged});

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
          child: Text(groupBy.label, style: const TextStyle(fontSize: 12)),
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
    final viewState = context.watch<TicketViewState>();
    final grouped = viewState.groupedTickets;
    final categoryProgress = viewState.categoryProgress;

    // Empty state
    if (grouped.isEmpty) {
      return const _EmptyTicketList();
    }

    // Flatten grouped tickets into a flat list of (header, ticket) items.
    final items = <_ListItem>[];
    for (final entry in grouped.entries) {
      final progress = categoryProgress[entry.key];
      items.add(
        _ListItem.header(
          entry.key,
          completed: progress?.completed ?? 0,
          total: progress?.total ?? 0,
        ),
      );
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
        final isSelected = viewState.selectedTicket?.id == ticket.id;
        final isChecked = viewState.selectedTicketIds.contains(ticket.id);
        final tools = context.watch<InternalToolsService?>();
        final orchestrated =
            tools?.activeOrchestrators.any(
              (state) => state.ticketIds.contains(ticket.id),
            ) ??
            false;
        return _TicketListItem(
          ticket: ticket,
          isSelected: isSelected,
          isChecked: isChecked,
          isOrchestrated: orchestrated,
          onTap: () {
            viewState.toggleTicketSelected(ticket.id);
            viewState.selectTicket(ticket.id);
          },
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

  factory _ListItem.header(
    String name, {
    required int completed,
    required int total,
  }) => _ListItem._(
    isHeader: true,
    headerName: name,
    completed: completed,
    total: total,
  );

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
                backgroundColor: colorScheme.outlineVariant.withValues(
                  alpha: 0.3,
                ),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF4CAF50),
                ),
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
    required this.isChecked,
    required this.isOrchestrated,
    required this.onTap,
  });

  final TicketData ticket;
  final bool isSelected;
  final bool isChecked;
  final bool isOrchestrated;
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
                bottom: BorderSide(color: colorScheme.surfaceContainerHighest),
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: isChecked,
                  onChanged: (_) => onTap(),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
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
                      decoration: isTerminal
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 6),
                if (isOrchestrated) ...[
                  Tooltip(
                    message: 'Orchestrated ticket',
                    child: Icon(
                      Icons.hub,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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
