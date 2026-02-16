import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import 'ticket_board_state.dart';

/// Mode for the ticket detail panel.
enum TicketDetailMode {
  /// Viewing a ticket's details.
  detail,

  /// Creating a new ticket.
  create,

  /// Editing an existing ticket.
  edit;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case detail:
        return 'Detail';
      case create:
        return 'Create';
      case edit:
        return 'Edit';
    }
  }
}

/// State management for ticket view (selection, filtering, computed data).
///
/// Manages UI view state like selection, filtering, grouping, and computed
/// data for tickets. Depends on [TicketRepository] for the underlying ticket
/// data. This class separates view concerns from data management.
class TicketViewState extends ChangeNotifier {
  final TicketRepository _repo;

  TicketViewState(this._repo) {
    _repo.addListener(_onTicketDataChanged);
  }

  @override
  void dispose() {
    _repo.removeListener(_onTicketDataChanged);
    super.dispose();
  }

  void _onTicketDataChanged() {
    _invalidateTicketData();
    notifyListeners();
  }

  // ===========================================================================
  // Fields
  // ===========================================================================

  /// The currently selected ticket ID, if any.
  int? _selectedTicketId;

  /// The current view mode for displaying tickets.
  TicketViewMode _viewMode = TicketViewMode.list;

  /// The current detail panel mode.
  TicketDetailMode _detailMode = TicketDetailMode.detail;

  /// The current search query.
  String _searchQuery = '';

  /// The current status filter, if any.
  TicketStatus? _statusFilter;

  /// The current kind filter, if any.
  TicketKind? _kindFilter;

  /// The current priority filter, if any.
  TicketPriority? _priorityFilter;

  /// The current category filter, if any.
  String? _categoryFilter;

  /// The current grouping method.
  TicketGroupBy _groupBy = TicketGroupBy.category;

  // ===========================================================================
  // Cache fields
  // ===========================================================================

  List<String>? _cachedAllCategories;
  TicketData? _cachedNextReadyTicket;
  bool _hasComputedNextReady = false;
  List<TicketData>? _cachedFilteredTickets;
  Map<String, List<TicketData>>? _cachedGroupedTickets;
  Map<String, ({int completed, int total})>? _cachedCategoryProgress;

  // ===========================================================================
  // Cache invalidation methods
  // ===========================================================================

  /// Clears all cached computed values. Called when ticket data changes.
  void _invalidateTicketData() {
    _cachedAllCategories = null;
    _cachedNextReadyTicket = null;
    _hasComputedNextReady = false;
    _cachedFilteredTickets = null;
    _cachedGroupedTickets = null;
    _cachedCategoryProgress = null;
  }

  /// Clears filter-dependent caches. Called when search/filter settings change.
  void _invalidateFilters() {
    _cachedFilteredTickets = null;
    _cachedGroupedTickets = null;
  }

  /// Clears grouping-dependent cache. Called when groupBy setting changes.
  void _invalidateGrouping() {
    _cachedGroupedTickets = null;
  }

  // ===========================================================================
  // Getters
  // ===========================================================================

  /// The currently selected ticket ID, if any.
  int? get selectedTicketId => _selectedTicketId;

  /// The currently selected ticket, if any.
  TicketData? get selectedTicket {
    if (_selectedTicketId == null) return null;
    return _repo.tickets.where((t) => t.id == _selectedTicketId).firstOrNull;
  }

  /// The current view mode.
  TicketViewMode get viewMode => _viewMode;

  /// The current detail panel mode.
  TicketDetailMode get detailMode => _detailMode;

  /// The current search query.
  String get searchQuery => _searchQuery;

  /// The current status filter.
  TicketStatus? get statusFilter => _statusFilter;

  /// The current kind filter.
  TicketKind? get kindFilter => _kindFilter;

  /// The current priority filter.
  TicketPriority? get priorityFilter => _priorityFilter;

  /// The current category filter.
  String? get categoryFilter => _categoryFilter;

  /// The current grouping method.
  TicketGroupBy get groupBy => _groupBy;

  /// All unique categories from tickets, sorted alphabetically.
  List<String> get allCategories {
    if (_cachedAllCategories != null) return _cachedAllCategories!;
    final categories = _repo.tickets
        .where((t) => t.category != null)
        .map((t) => t.category!)
        .toSet()
        .toList();
    categories.sort();
    _cachedAllCategories = categories;
    return categories;
  }

  /// The highest-priority ready ticket, or null if none exist.
  ///
  /// Priority order: critical > high > medium > low.
  /// Ties are broken by ticket ID (lower first).
  TicketData? get nextReadyTicket {
    if (_hasComputedNextReady) return _cachedNextReadyTicket;

    final ready = _repo.tickets.where((t) => t.status == TicketStatus.ready).toList();
    if (ready.isEmpty) {
      _cachedNextReadyTicket = null;
      _hasComputedNextReady = true;
      return null;
    }

    ready.sort(TicketRepository.comparePriority);

    _cachedNextReadyTicket = ready.first;
    _hasComputedNextReady = true;
    return ready.first;
  }

  /// Filtered tickets based on search and all active filters.
  ///
  /// Search matches displayId, title, and description (case-insensitive).
  /// All filters are AND-combined.
  List<TicketData> get filteredTickets {
    if (_cachedFilteredTickets != null) return _cachedFilteredTickets!;

    var filtered = _repo.tickets.toList();

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        return t.displayId.toLowerCase().contains(query) ||
            t.title.toLowerCase().contains(query) ||
            t.description.toLowerCase().contains(query);
      }).toList();
    }

    // Status filter
    if (_statusFilter != null) {
      filtered = filtered.where((t) => t.status == _statusFilter).toList();
    }

    // Kind filter
    if (_kindFilter != null) {
      filtered = filtered.where((t) => t.kind == _kindFilter).toList();
    }

    // Priority filter
    if (_priorityFilter != null) {
      filtered = filtered.where((t) => t.priority == _priorityFilter).toList();
    }

    // Category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((t) => t.category == _categoryFilter).toList();
    }

    _cachedFilteredTickets = filtered;
    return filtered;
  }

  /// Grouped tickets based on the current grouping method.
  ///
  /// Returns a map of group name to tickets in that group.
  /// Within each group, tickets are sorted by priority (descending) then ID.
  /// Tickets without a category are placed in an "Uncategorized" group.
  Map<String, List<TicketData>> get groupedTickets {
    if (_cachedGroupedTickets != null) return _cachedGroupedTickets!;

    final filtered = filteredTickets;
    final groups = <String, List<TicketData>>{};

    for (final ticket in filtered) {
      String groupKey;
      switch (_groupBy) {
        case TicketGroupBy.category:
          groupKey = ticket.category ?? 'Uncategorized';
        case TicketGroupBy.status:
          groupKey = ticket.status.label;
        case TicketGroupBy.kind:
          groupKey = ticket.kind.label;
        case TicketGroupBy.priority:
          groupKey = ticket.priority.label;
      }

      groups.putIfAbsent(groupKey, () => <TicketData>[]);
      groups[groupKey]!.add(ticket);
    }

    // Sort within each group by priority (descending) then ID
    for (final group in groups.values) {
      group.sort(TicketRepository.comparePriority);
    }

    _cachedGroupedTickets = groups;
    return groups;
  }

  /// Progress by category: completed vs total tickets.
  ///
  /// Returns a map of category name to (completed: int, total: int).
  Map<String, ({int completed, int total})> get categoryProgress {
    if (_cachedCategoryProgress != null) return _cachedCategoryProgress!;

    final progress = <String, ({int completed, int total})>{};

    for (final ticket in _repo.tickets) {
      final category = ticket.category ?? 'Uncategorized';
      final current = progress[category] ?? (completed: 0, total: 0);
      final isCompleted = ticket.status == TicketStatus.completed;

      progress[category] = (
        completed: current.completed + (isCompleted ? 1 : 0),
        total: current.total + 1,
      );
    }

    _cachedCategoryProgress = progress;
    return progress;
  }

  // ===========================================================================
  // Setter methods
  // ===========================================================================

  /// Selects a ticket by ID.
  ///
  /// Pass null to clear the selection. Sets detail mode to detail if id is not null.
  void selectTicket(int? id) {
    _selectedTicketId = id;
    if (id != null) {
      _detailMode = TicketDetailMode.detail;
    }
    notifyListeners();
  }

  /// Sets the view mode.
  void setViewMode(TicketViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  /// Sets the detail panel mode.
  void setDetailMode(TicketDetailMode mode) {
    _detailMode = mode;
    notifyListeners();
  }

  /// Shows the create ticket form.
  ///
  /// Sets detail mode to create and clears selection.
  void showCreateForm() {
    _detailMode = TicketDetailMode.create;
    _selectedTicketId = null;
    notifyListeners();
  }

  /// Shows the detail view for the selected ticket.
  void showDetail() {
    _detailMode = TicketDetailMode.detail;
    notifyListeners();
  }

  /// Sets the search query.
  void setSearchQuery(String query) {
    _searchQuery = query;
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the status filter.
  void setStatusFilter(TicketStatus? status) {
    _statusFilter = status;
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the kind filter.
  void setKindFilter(TicketKind? kind) {
    _kindFilter = kind;
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the priority filter.
  void setPriorityFilter(TicketPriority? priority) {
    _priorityFilter = priority;
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the category filter.
  void setCategoryFilter(String? category) {
    _categoryFilter = category;
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the grouping method.
  void setGroupBy(TicketGroupBy groupBy) {
    _groupBy = groupBy;
    _invalidateGrouping();
    notifyListeners();
  }
}
