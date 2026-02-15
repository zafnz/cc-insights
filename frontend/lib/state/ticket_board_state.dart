import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import '../services/persistence_service.dart';

/// Result emitted when a bulk review completes.
typedef BulkReviewResult = ({int approvedCount, int rejectedCount});

/// Mode for the ticket detail panel.
enum TicketDetailMode {
  /// Viewing a ticket's details.
  detail,

  /// Creating a new ticket.
  create,

  /// Editing an existing ticket.
  edit,

  /// Bulk reviewing multiple tickets.
  bulkReview;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case detail:
        return 'Detail';
      case create:
        return 'Create';
      case edit:
        return 'Edit';
      case bulkReview:
        return 'Bulk Review';
    }
  }
}

/// State management for the ticket board.
///
/// Manages CRUD operations, selection, filtering, grouping, and dependency
/// validation for tickets. Uses [PersistenceService] for storage.
class TicketBoardState extends ChangeNotifier {
  final String projectId;
  final PersistenceService _persistence;

  /// Save queue to serialize save operations.
  Future<void>? _pendingSave;

  /// Internal ticket storage.
  List<TicketData> _tickets = [];

  /// The next ID to assign when creating a ticket.
  int _nextId = 1;

  /// The currently selected ticket ID, if any.
  int? _selectedTicketId;

  /// The current view mode for displaying tickets.
  TicketViewMode _viewMode = TicketViewMode.list;

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

  /// The current detail panel mode.
  TicketDetailMode _detailMode = TicketDetailMode.detail;

  /// The chat ID that proposed the current bulk tickets, if any.
  String? _proposalSourceChatId;

  /// The chat name that proposed the current bulk tickets, if any.
  String? _proposalSourceChatName;

  /// Which proposed tickets are checked for approval.
  Set<int> _proposalCheckedIds = {};

  /// Which proposed ticket is being inline-edited, if any.
  int? _proposalEditingId;

  /// IDs of tickets created by the current proposal batch.
  List<int> _proposalTicketIds = [];

  // Cached computed values — nulled by _invalidate*() methods.
  List<String>? _cachedAllCategories;
  TicketData? _cachedNextReadyTicket;
  bool _hasComputedNextReady = false;
  List<TicketData>? _cachedFilteredTickets;
  Map<String, List<TicketData>>? _cachedGroupedTickets;
  Map<String, ({int completed, int total})>? _cachedCategoryProgress;

  final StreamController<BulkReviewResult> _bulkReviewCompleteController =
      StreamController<BulkReviewResult>.broadcast(sync: true);

  /// Stream that emits when a bulk review completes (approved or rejected).
  ///
  /// Used by [InternalToolsService] to send the tool result back to the agent.
  Stream<BulkReviewResult> get onBulkReviewComplete =>
      _bulkReviewCompleteController.stream;

  final StreamController<TicketData> _ticketReadyController =
      StreamController<TicketData>.broadcast(sync: true);

  /// Stream that emits when a ticket automatically becomes ready.
  ///
  /// Fires when [_autoUnblockDependents] transitions a ticket from
  /// [TicketStatus.blocked] to [TicketStatus.ready]. Does not fire for
  /// manual status changes.
  Stream<TicketData> get onTicketReady => _ticketReadyController.stream;

  /// Creates a [TicketBoardState] for the given project.
  ///
  /// The [persistence] parameter is optional for testing; if not provided,
  /// a default instance is created.
  TicketBoardState(this.projectId, {PersistenceService? persistence})
      : _persistence = persistence ?? PersistenceService();

  @override
  void dispose() {
    _bulkReviewCompleteController.close();
    _ticketReadyController.close();
    super.dispose();
  }

  /// Unmodifiable view of all tickets.
  List<TicketData> get tickets => List.unmodifiable(_tickets);

  /// The currently selected ticket, if any.
  TicketData? get selectedTicket {
    if (_selectedTicketId == null) return null;
    return _tickets.where((t) => t.id == _selectedTicketId).firstOrNull;
  }

  /// Count of tickets with status == active.
  int get activeCount =>
      _tickets.where((t) => t.status == TicketStatus.active).length;

  /// The current view mode.
  TicketViewMode get viewMode => _viewMode;

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

  /// The current detail panel mode.
  TicketDetailMode get detailMode => _detailMode;

  /// The chat name that proposed the current bulk tickets.
  String get proposalSourceChatName => _proposalSourceChatName ?? '';

  /// The chat ID that proposed the current bulk tickets.
  String? get proposalSourceChatId => _proposalSourceChatId;

  /// All draft tickets from the current proposal batch.
  List<TicketData> get proposedTickets {
    return _tickets.where((t) => _proposalTicketIds.contains(t.id)).toList();
  }

  /// Which proposed tickets are checked for approval.
  Set<int> get proposalCheckedIds => Set.unmodifiable(_proposalCheckedIds);

  /// Which proposed ticket is being inline-edited, if any.
  int? get proposalEditingId => _proposalEditingId;

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

  /// All unique categories from tickets, sorted alphabetically.
  List<String> get allCategories {
    if (_cachedAllCategories != null) return _cachedAllCategories!;
    final categories = _tickets
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

    final ready = _tickets.where((t) => t.status == TicketStatus.ready).toList();
    if (ready.isEmpty) {
      _cachedNextReadyTicket = null;
      _hasComputedNextReady = true;
      return null;
    }

    // Sort by priority (descending) then by ID (ascending)
    ready.sort((a, b) {
      final priorityOrder = {
        TicketPriority.critical: 4,
        TicketPriority.high: 3,
        TicketPriority.medium: 2,
        TicketPriority.low: 1,
      };
      final priorityCompare = (priorityOrder[b.priority] ?? 0)
          .compareTo(priorityOrder[a.priority] ?? 0);
      if (priorityCompare != 0) return priorityCompare;

      // Tie-break by ID
      return a.id.compareTo(b.id);
    });

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

    var filtered = _tickets.toList();

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
      group.sort((a, b) {
        // Priority descending (critical > high > medium > low)
        final priorityOrder = {
          TicketPriority.critical: 4,
          TicketPriority.high: 3,
          TicketPriority.medium: 2,
          TicketPriority.low: 1,
        };
        final priorityCompare = (priorityOrder[b.priority] ?? 0)
            .compareTo(priorityOrder[a.priority] ?? 0);
        if (priorityCompare != 0) return priorityCompare;

        // Then by ID
        return a.id.compareTo(b.id);
      });
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

    for (final ticket in _tickets) {
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
  // CRUD Methods
  // ===========================================================================

  /// Creates a new ticket.
  ///
  /// Assigns the next available ID, sets timestamps, and defaults status to
  /// ready if not specified. Returns the created ticket.
  TicketData createTicket({
    required String title,
    required TicketKind kind,
    String description = '',
    TicketStatus? status,
    TicketPriority priority = TicketPriority.medium,
    TicketEffort effort = TicketEffort.medium,
    String? category,
    Set<String> tags = const {},
    List<int> dependsOn = const [],
  }) {
    final now = DateTime.now();
    final ticket = TicketData(
      id: _nextId++,
      title: title,
      description: description,
      status: status ?? TicketStatus.ready,
      kind: kind,
      priority: priority,
      effort: effort,
      category: category,
      tags: tags,
      dependsOn: dependsOn,
      createdAt: now,
      updatedAt: now,
    );

    _tickets.add(ticket);
    _invalidateTicketData();
    notifyListeners();
    _autoSave();

    return ticket;
  }

  /// Updates a ticket using an updater function.
  ///
  /// Applies the updater to the ticket with the given ID and sets updatedAt.
  /// Does nothing if the ticket is not found.
  void updateTicket(int id, TicketData Function(TicketData) updater) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final updated = updater(_tickets[index]);
    _tickets[index] = updated.copyWith(updatedAt: DateTime.now());

    _invalidateTicketData();
    notifyListeners();
    _autoSave();
  }

  /// Deletes a ticket.
  ///
  /// Removes the ticket and also removes it from other tickets' dependsOn lists.
  void deleteTicket(int id) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _tickets.removeAt(index);

    // Remove this ticket from all dependsOn lists
    for (var i = 0; i < _tickets.length; i++) {
      final ticket = _tickets[i];
      if (ticket.dependsOn.contains(id)) {
        final updatedDeps = ticket.dependsOn.where((d) => d != id).toList();
        _tickets[i] = ticket.copyWith(dependsOn: updatedDeps);
      }
    }

    // Clear selection if deleted ticket was selected
    if (_selectedTicketId == id) {
      _selectedTicketId = null;
    }

    _invalidateTicketData();
    notifyListeners();
    _autoSave();
  }

  /// Gets a ticket by ID.
  ///
  /// Returns null if not found.
  TicketData? getTicket(int id) {
    return _tickets.where((t) => t.id == id).firstOrNull;
  }

  // ===========================================================================
  // Selection Methods
  // ===========================================================================

  /// Selects a ticket by ID.
  ///
  /// Pass null to clear the selection. Sets detail mode to detail.
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

  /// Sets the detail panel mode directly.
  void setDetailMode(TicketDetailMode mode) {
    _detailMode = mode;
    notifyListeners();
  }

  // ===========================================================================
  // Dependency Methods (DAG validation)
  // ===========================================================================

  /// Adds a dependency relationship.
  ///
  /// Validates that:
  /// - The ticket is not depending on itself
  /// - The target ticket exists
  /// - The dependency does not create a cycle
  ///
  /// Throws [ArgumentError] if validation fails.
  void addDependency(int ticketId, int dependsOnId) {
    // Validate: not self-reference
    if (ticketId == dependsOnId) {
      throw ArgumentError('A ticket cannot depend on itself');
    }

    // Validate: target exists
    final target = getTicket(dependsOnId);
    if (target == null) {
      throw ArgumentError('Target ticket $dependsOnId does not exist');
    }

    // Validate: no cycle
    if (wouldCreateCycle(ticketId, dependsOnId)) {
      throw ArgumentError(
        'Adding this dependency would create a cycle',
      );
    }

    // Add the dependency
    updateTicket(ticketId, (ticket) {
      if (ticket.dependsOn.contains(dependsOnId)) {
        return ticket; // Already exists
      }
      return ticket.copyWith(dependsOn: [...ticket.dependsOn, dependsOnId]);
    });
  }

  /// Removes a dependency relationship.
  void removeDependency(int ticketId, int dependsOnId) {
    updateTicket(ticketId, (ticket) {
      final updated = ticket.dependsOn.where((d) => d != dependsOnId).toList();
      return ticket.copyWith(dependsOn: updated);
    });
  }

  /// Checks if adding a dependency would create a cycle.
  ///
  /// Uses DFS from [toId] following dependsOn links. Returns true if [fromId]
  /// is reachable from [toId], meaning adding fromId -> toId would create a cycle.
  bool wouldCreateCycle(int fromId, int toId) {
    final visited = <int>{};
    final stack = <int>[toId];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();

      if (current == fromId) {
        return true; // Found a path from toId back to fromId
      }

      if (visited.contains(current)) {
        continue;
      }

      visited.add(current);

      // Follow dependencies of current ticket
      final ticket = getTicket(current);
      if (ticket != null) {
        stack.addAll(ticket.dependsOn);
      }
    }

    return false;
  }

  /// Gets IDs of tickets that are blocked by the given ticket.
  ///
  /// Returns tickets whose dependsOn list contains [ticketId].
  List<int> getBlockedBy(int ticketId) {
    return _tickets
        .where((t) => t.dependsOn.contains(ticketId))
        .map((t) => t.id)
        .toList();
  }

  // ===========================================================================
  // Status Methods
  // ===========================================================================

  /// Sets the status of a ticket.
  ///
  /// When the new status is [TicketStatus.completed], scans all other tickets
  /// that depend on this one. If a dependent ticket is [TicketStatus.blocked]
  /// and all its dependencies are now complete, it is auto-transitioned to
  /// [TicketStatus.ready].
  void setStatus(int ticketId, TicketStatus status) {
    updateTicket(ticketId, (ticket) => ticket.copyWith(status: status));

    // Auto-unblock dependents when a ticket is completed
    if (status == TicketStatus.completed) {
      _autoUnblockDependents(ticketId);
    }
  }

  /// Scans tickets that depend on [completedTicketId] and unblocks them
  /// if all their dependencies are now complete.
  ///
  /// When a ticket is transitioned from [TicketStatus.blocked] to
  /// [TicketStatus.ready], the [onTicketReady] callback is invoked if set.
  void _autoUnblockDependents(int completedTicketId) {
    for (final ticket in _tickets) {
      if (!ticket.dependsOn.contains(completedTicketId)) continue;
      if (ticket.status != TicketStatus.blocked) continue;

      // Check if ALL dependencies are now completed
      final allDepsComplete = ticket.dependsOn.every((depId) {
        final dep = getTicket(depId);
        return dep != null && dep.status == TicketStatus.completed;
      });

      if (allDepsComplete) {
        updateTicket(ticket.id, (t) => t.copyWith(status: TicketStatus.ready));

        // Emit event after the ticket has been updated
        final readyTicket = getTicket(ticket.id);
        if (readyTicket != null) {
          _ticketReadyController.add(readyTicket);
        }
      }
    }
  }

  /// Marks a ticket as completed.
  void markCompleted(int ticketId) {
    setStatus(ticketId, TicketStatus.completed);
  }

  /// Marks a ticket as cancelled.
  void markCancelled(int ticketId) {
    setStatus(ticketId, TicketStatus.cancelled);
  }

  /// Accumulates cost statistics on a ticket.
  ///
  /// Creates or updates [TicketCostStats] by adding the provided values to
  /// the existing stats. If the ticket has no cost stats yet, creates them
  /// from the provided values.
  void accumulateCostStats(
    int ticketId, {
    required int tokens,
    required double cost,
    required int agentTimeMs,
  }) {
    updateTicket(ticketId, (ticket) {
      final existing = ticket.costStats;
      if (existing != null) {
        return ticket.copyWith(
          costStats: TicketCostStats(
            totalTokens: existing.totalTokens + tokens,
            totalCost: existing.totalCost + cost,
            agentTimeMs: existing.agentTimeMs + agentTimeMs,
            waitingTimeMs: existing.waitingTimeMs,
          ),
        );
      } else {
        return ticket.copyWith(
          costStats: TicketCostStats(
            totalTokens: tokens,
            totalCost: cost,
            agentTimeMs: agentTimeMs,
            waitingTimeMs: 0,
          ),
        );
      }
    });
  }

  // ===========================================================================
  // Split Methods
  // ===========================================================================

  /// Splits a ticket into subtasks.
  ///
  /// The parent ticket is updated to [TicketStatus.split] status and
  /// [TicketKind.split] kind. Each subtask is created as a new ticket
  /// with the parent in its [dependsOn] list, inheriting the parent's
  /// category, priority, and effort.
  ///
  /// Throws [ArgumentError] if:
  /// - The parent ticket does not exist
  /// - The subtasks list is empty
  ///
  /// Returns the list of created child tickets.
  List<TicketData> splitTicket(
    int parentId,
    List<({String title, TicketKind kind})> subtasks,
  ) {
    final parent = getTicket(parentId);
    if (parent == null) {
      throw ArgumentError('Parent ticket $parentId does not exist');
    }
    if (subtasks.isEmpty) {
      throw ArgumentError('Subtasks list must not be empty');
    }

    // Update parent: status -> split, kind -> split
    updateTicket(parentId, (ticket) => ticket.copyWith(
      status: TicketStatus.split,
      kind: TicketKind.split,
    ));

    // Create child tickets
    final children = <TicketData>[];
    for (final subtask in subtasks) {
      final child = createTicket(
        title: subtask.title,
        kind: subtask.kind,
        status: TicketStatus.ready,
        priority: parent.priority,
        effort: parent.effort,
        category: parent.category,
        dependsOn: [parentId],
      );
      children.add(child);
    }

    return children;
  }

  // ===========================================================================
  // Linking Methods
  // ===========================================================================

  /// Links a worktree to a ticket.
  ///
  /// Adds a [LinkedWorktree] entry to the ticket's [linkedWorktrees] list.
  /// Does nothing if the ticket is not found.
  void linkWorktree(int ticketId, String worktreeRoot, String? branch) {
    updateTicket(ticketId, (ticket) {
      // Avoid duplicate links
      final alreadyLinked = ticket.linkedWorktrees.any(
        (w) => w.worktreeRoot == worktreeRoot,
      );
      if (alreadyLinked) return ticket;

      return ticket.copyWith(
        linkedWorktrees: [
          ...ticket.linkedWorktrees,
          LinkedWorktree(worktreeRoot: worktreeRoot, branch: branch),
        ],
      );
    });
  }

  /// Links a chat to a ticket.
  ///
  /// Adds a [LinkedChat] entry to the ticket's [linkedChats] list.
  /// Does nothing if the ticket is not found.
  void linkChat(int ticketId, String chatId, String chatName, String worktreeRoot) {
    updateTicket(ticketId, (ticket) {
      // Avoid duplicate links
      final alreadyLinked = ticket.linkedChats.any(
        (c) => c.chatId == chatId,
      );
      if (alreadyLinked) return ticket;

      return ticket.copyWith(
        linkedChats: [
          ...ticket.linkedChats,
          LinkedChat(
            chatId: chatId,
            chatName: chatName,
            worktreeRoot: worktreeRoot,
          ),
        ],
      );
    });
  }

  /// Returns all tickets that have the given chat ID in their linked chats.
  ///
  /// Useful for showing ticket context when viewing a chat.
  List<TicketData> getTicketsForChat(String chatId) {
    return _tickets
        .where((t) => t.linkedChats.any((c) => c.chatId == chatId))
        .toList();
  }

  // ===========================================================================
  // Bulk Proposal Methods
  // ===========================================================================

  /// Creates draft tickets from a list of proposals.
  ///
  /// Converts [TicketProposal] objects into [TicketData] with status
  /// [TicketStatus.draft]. Dependency indices are mapped to the actual IDs
  /// of the newly created tickets. Out-of-range indices are silently dropped.
  ///
  /// All newly created tickets are auto-checked for approval. Sets the detail
  /// mode to [TicketDetailMode.bulkReview].
  List<TicketData> proposeBulk(
    List<TicketProposal> proposals, {
    required String sourceChatId,
    required String sourceChatName,
  }) {
    _proposalSourceChatId = sourceChatId;
    _proposalSourceChatName = sourceChatName;
    _proposalTicketIds = [];
    _proposalCheckedIds = {};
    _proposalEditingId = null;

    final now = DateTime.now();
    final createdTickets = <TicketData>[];

    // First pass: create all tickets without dependencies
    for (final proposal in proposals) {
      final ticket = TicketData(
        id: _nextId++,
        title: proposal.title,
        description: proposal.description,
        status: TicketStatus.draft,
        kind: proposal.kind,
        priority: proposal.priority,
        effort: proposal.effort,
        category: proposal.category,
        tags: proposal.tags,
        dependsOn: const [],
        createdAt: now,
        updatedAt: now,
      );

      _tickets.add(ticket);
      createdTickets.add(ticket);
      _proposalTicketIds.add(ticket.id);
      _proposalCheckedIds.add(ticket.id);
    }

    // Second pass: resolve dependency indices to actual ticket IDs
    for (var i = 0; i < proposals.length; i++) {
      final proposal = proposals[i];
      if (proposal.dependsOnIndices.isEmpty) continue;

      final resolvedDeps = <int>[];
      for (final index in proposal.dependsOnIndices) {
        if (index >= 0 && index < createdTickets.length) {
          resolvedDeps.add(createdTickets[index].id);
        }
        // Out-of-range indices are silently dropped
      }

      if (resolvedDeps.isNotEmpty) {
        final ticketIndex = _tickets.indexWhere((t) => t.id == createdTickets[i].id);
        if (ticketIndex != -1) {
          _tickets[ticketIndex] = _tickets[ticketIndex].copyWith(dependsOn: resolvedDeps);
          createdTickets[i] = _tickets[ticketIndex];
        }
      }
    }

    _detailMode = TicketDetailMode.bulkReview;

    _invalidateTicketData();
    notifyListeners();
    _autoSave();

    return createdTickets;
  }

  /// Toggles the checked state of a proposed ticket.
  void toggleProposalChecked(int ticketId) {
    if (_proposalCheckedIds.contains(ticketId)) {
      _proposalCheckedIds.remove(ticketId);
    } else {
      _proposalCheckedIds.add(ticketId);
    }
    notifyListeners();
  }

  /// Checks or unchecks all proposed tickets.
  void setProposalAllChecked(bool checked) {
    if (checked) {
      _proposalCheckedIds = Set.from(_proposalTicketIds);
    } else {
      _proposalCheckedIds = {};
    }
    notifyListeners();
  }

  /// Sets the ticket being inline-edited during bulk review.
  void setProposalEditing(int? ticketId) {
    _proposalEditingId = ticketId;
    notifyListeners();
  }

  /// Approves checked proposals and deletes unchecked ones.
  ///
  /// Checked draft tickets are promoted to [TicketStatus.ready].
  /// Unchecked draft tickets are deleted. Returns to detail mode.
  ///
  /// Emits a [BulkReviewResult] on [onBulkReviewComplete] with the counts of
  /// approved and rejected tickets.
  void approveBulk() {
    final approvedCount = _proposalCheckedIds.length;
    final rejectedCount = _proposalTicketIds.length - approvedCount;
    final toDelete = <int>[];

    for (final ticketId in _proposalTicketIds) {
      if (_proposalCheckedIds.contains(ticketId)) {
        // Promote to ready
        final index = _tickets.indexWhere((t) => t.id == ticketId);
        if (index != -1) {
          _tickets[index] = _tickets[index].copyWith(
            status: TicketStatus.ready,
            updatedAt: DateTime.now(),
          );
        }
      } else {
        toDelete.add(ticketId);
      }
    }

    // Delete unchecked tickets
    for (final id in toDelete) {
      _tickets.removeWhere((t) => t.id == id);
      // Remove from other tickets' dependsOn lists
      for (var i = 0; i < _tickets.length; i++) {
        final ticket = _tickets[i];
        if (ticket.dependsOn.contains(id)) {
          final updatedDeps = ticket.dependsOn.where((d) => d != id).toList();
          _tickets[i] = ticket.copyWith(dependsOn: updatedDeps);
        }
      }
    }

    // Clear proposal state
    _proposalTicketIds = [];
    _proposalCheckedIds = {};
    _proposalEditingId = null;
    _proposalSourceChatId = null;
    _proposalSourceChatName = null;
    _detailMode = TicketDetailMode.detail;

    _invalidateTicketData();
    notifyListeners();
    _autoSave();

    // Emit review completion event
    _bulkReviewCompleteController.add((
      approvedCount: approvedCount,
      rejectedCount: rejectedCount,
    ));
  }

  /// Rejects all proposed tickets by deleting them.
  ///
  /// All draft tickets from the current proposal are deleted.
  /// Returns to detail mode.
  ///
  /// Emits a [BulkReviewResult] on [onBulkReviewComplete] with all tickets
  /// counted as rejected.
  void rejectAll() {
    final rejectedCount = _proposalTicketIds.length;

    // Delete all proposal tickets
    for (final id in _proposalTicketIds) {
      _tickets.removeWhere((t) => t.id == id);
      // Remove from other tickets' dependsOn lists
      for (var i = 0; i < _tickets.length; i++) {
        final ticket = _tickets[i];
        if (ticket.dependsOn.contains(id)) {
          final updatedDeps = ticket.dependsOn.where((d) => d != id).toList();
          _tickets[i] = ticket.copyWith(dependsOn: updatedDeps);
        }
      }
    }

    // Clear proposal state
    _proposalTicketIds = [];
    _proposalCheckedIds = {};
    _proposalEditingId = null;
    _proposalSourceChatId = null;
    _proposalSourceChatName = null;
    _detailMode = TicketDetailMode.detail;

    _invalidateTicketData();
    notifyListeners();
    _autoSave();

    // Emit review completion event
    _bulkReviewCompleteController.add((
      approvedCount: 0,
      rejectedCount: rejectedCount,
    ));
  }

  // ===========================================================================
  // Persistence
  // ===========================================================================

  /// Loads tickets from persistence.
  Future<void> load() async {
    try {
      final data = await _persistence.loadTickets(projectId);
      if (data == null) {
        developer.log(
          'No tickets file found for project $projectId',
          name: 'TicketBoardState',
        );
        return;
      }

      final ticketsList = data['tickets'] as List<dynamic>? ?? [];
      _tickets = ticketsList
          .map((json) => TicketData.fromJson(json as Map<String, dynamic>))
          .toList();

      // Restore nextId, or compute from existing tickets
      if (data.containsKey('nextId')) {
        _nextId = data['nextId'] as int;
      } else if (_tickets.isNotEmpty) {
        // If nextId not in file, compute from max ticket ID + 1
        _nextId = _tickets.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
      } else {
        _nextId = 1;
      }

      developer.log(
        'Loaded ${_tickets.length} tickets for project $projectId (nextId: $_nextId)',
        name: 'TicketBoardState',
      );

      _invalidateTicketData();
      notifyListeners();
    } catch (e) {
      developer.log(
        'Failed to load tickets: $e',
        name: 'TicketBoardState',
        error: e,
      );
      // Don't rethrow - continue with empty state
    }
  }

  /// Saves tickets to persistence.
  ///
  /// Multiple concurrent calls are serialized to prevent file corruption.
  Future<void> save() async {
    // Chain this save after any pending save
    final previous = _pendingSave ?? Future<void>.value();
    final current = previous.then((_) async {
      try {
        final data = {
          'tickets': _tickets.map((t) => t.toJson()).toList(),
          'nextId': _nextId,
        };

        await _persistence.saveTickets(projectId, data);

        developer.log(
          'Saved ${_tickets.length} tickets for project $projectId',
          name: 'TicketBoardState',
        );
      } catch (e) {
        developer.log(
          'Failed to save tickets: $e',
          name: 'TicketBoardState',
          error: e,
        );
        rethrow;
      }
    });

    _pendingSave = current.catchError((_) {});
    return current;
  }

  /// Auto-saves after mutations.
  ///
  /// Fire-and-forget - does not wait for completion. Errors are logged but
  /// don't propagate to the caller. For tests, call save() explicitly and await.
  void _autoSave() {
    // Fire and forget - don't await
    save().catchError((e) {
      developer.log(
        'Auto-save failed: $e',
        name: 'TicketBoardState',
        error: e,
      );
    });
  }
}
