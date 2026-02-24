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
/// Manages UI view state like selection, filtering, sorting, and computed
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

  /// Filter by open/closed status.
  bool _isOpenFilter = true;

  /// Tag filters (AND: ticket must have ALL selected tags).
  final Set<String> _tagFilters = {};

  /// The current sort order.
  TicketSortOrder _sortOrder = TicketSortOrder.newest;

  /// Selected ticket IDs for orchestration launch.
  final Set<int> _selectedTicketIds = {};

  // ===========================================================================
  // Cache fields
  // ===========================================================================

  List<TicketData>? _cachedFilteredTickets;

  // ===========================================================================
  // Cache invalidation methods
  // ===========================================================================

  /// Clears all cached computed values. Called when ticket data changes.
  void _invalidateTicketData() {
    _cachedFilteredTickets = null;
  }

  /// Clears filter-dependent caches. Called when search/filter settings change.
  void _invalidateFilters() {
    _cachedFilteredTickets = null;
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

  /// The current open/closed filter.
  bool get isOpenFilter => _isOpenFilter;

  /// The current tag filters.
  Set<String> get tagFilters => Set.unmodifiable(_tagFilters);

  /// The current sort order.
  TicketSortOrder get sortOrder => _sortOrder;

  /// Selected ticket IDs for orchestration launch.
  Set<int> get selectedTicketIds => Set.unmodifiable(_selectedTicketIds);

  /// Count of open tickets (unfiltered).
  int get openCount => _repo.tickets.where((t) => t.isOpen).length;

  /// Count of closed tickets (unfiltered).
  int get closedCount => _repo.tickets.where((t) => !t.isOpen).length;

  /// Filtered and sorted tickets based on all active filters.
  ///
  /// Filtering order:
  /// 1. isOpen matching _isOpenFilter
  /// 2. Search query (title, body, comments text, tag names, #id)
  /// 3. Tag filters (AND: ticket must have ALL selected tags)
  /// 4. Sort by _sortOrder
  List<TicketData> get filteredTickets {
    if (_cachedFilteredTickets != null) return _cachedFilteredTickets!;

    var filtered = _repo.tickets.toList();

    // 1. Filter by isOpen
    filtered = filtered.where((t) => t.isOpen == _isOpenFilter).toList();

    // 2. Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        return t.displayId.toLowerCase().contains(query) ||
            t.title.toLowerCase().contains(query) ||
            t.body.toLowerCase().contains(query) ||
            t.comments.any((c) => c.text.toLowerCase().contains(query)) ||
            t.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }

    // 3. Tag filters (AND)
    if (_tagFilters.isNotEmpty) {
      filtered = filtered.where((t) {
        return _tagFilters.every((tag) => t.tags.contains(tag));
      }).toList();
    }

    // 4. Sort
    switch (_sortOrder) {
      case TicketSortOrder.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case TicketSortOrder.oldest:
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case TicketSortOrder.recentlyUpdated:
        filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    _cachedFilteredTickets = filtered;
    return filtered;
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

  /// Sets the open/closed filter.
  void setIsOpenFilter(bool isOpen) {
    _isOpenFilter = isOpen;
    _invalidateFilters();
    notifyListeners();
  }

  /// Adds a tag filter.
  void addTagFilter(String tag) {
    if (_tagFilters.add(tag)) {
      _invalidateFilters();
      notifyListeners();
    }
  }

  /// Removes a tag filter.
  void removeTagFilter(String tag) {
    if (_tagFilters.remove(tag)) {
      _invalidateFilters();
      notifyListeners();
    }
  }

  /// Clears all tag filters.
  void clearTagFilters() {
    if (_tagFilters.isEmpty) return;
    _tagFilters.clear();
    _invalidateFilters();
    notifyListeners();
  }

  /// Sets the sort order.
  void setSortOrder(TicketSortOrder order) {
    _sortOrder = order;
    _invalidateFilters();
    notifyListeners();
  }

  void toggleTicketSelected(int ticketId) {
    if (_selectedTicketIds.contains(ticketId)) {
      _selectedTicketIds.remove(ticketId);
    } else {
      _selectedTicketIds.add(ticketId);
    }
    notifyListeners();
  }

  void selectAllFilteredTickets() {
    _selectedTicketIds
      ..clear()
      ..addAll(filteredTickets.map((t) => t.id));
    notifyListeners();
  }

  void clearTicketSelection() {
    if (_selectedTicketIds.isEmpty) return;
    _selectedTicketIds.clear();
    notifyListeners();
  }
}
