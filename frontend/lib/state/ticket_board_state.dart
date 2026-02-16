import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import '../services/ticket_storage_service.dart';

/// Repository for ticket data persistence and CRUD operations.
///
/// Manages ticket storage, dependency validation, and status transitions.
/// Uses [TicketStorageService] for persistence.
class TicketRepository extends ChangeNotifier {
  final String projectId;
  final TicketStorageService _storage;

  /// Save queue to serialize save operations.
  Future<void>? _pendingSave;

  /// Internal ticket storage.
  List<TicketData> _tickets = [];

  /// The next ID to assign when creating a ticket.
  int _nextId = 1;

  final StreamController<TicketData> _ticketReadyController =
      StreamController<TicketData>.broadcast(sync: true);

  /// Stream that emits when a ticket automatically becomes ready.
  ///
  /// Fires when [_autoUnblockDependents] transitions a ticket from
  /// [TicketStatus.blocked] to [TicketStatus.ready]. Does not fire for
  /// manual status changes.
  Stream<TicketData> get onTicketReady => _ticketReadyController.stream;

  /// Creates a [TicketRepository] for the given project.
  ///
  /// The [storage] parameter is optional for testing; if not provided,
  /// a default instance is created.
  TicketRepository(this.projectId, {TicketStorageService? storage})
      : _storage = storage ?? TicketStorageService();

  @override
  void dispose() {
    _ticketReadyController.close();
    super.dispose();
  }

  /// Unmodifiable view of all tickets.
  List<TicketData> get tickets => List.unmodifiable(_tickets);

  /// Count of tickets with status == active.
  int get activeCount =>
      _tickets.where((t) => t.status == TicketStatus.active).length;

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
  /// [TicketStatus.ready], the [onTicketReady] stream emits the ticket.
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
  // Priority Sorting
  // ===========================================================================

  /// Compares tickets by priority (descending: critical > high > medium > low),
  /// then by ID (ascending) as tiebreaker.
  static int comparePriority(TicketData a, TicketData b) {
    const priorityOrder = {
      TicketPriority.critical: 4,
      TicketPriority.high: 3,
      TicketPriority.medium: 2,
      TicketPriority.low: 1,
    };
    final priorityCompare = (priorityOrder[b.priority] ?? 0)
        .compareTo(priorityOrder[a.priority] ?? 0);
    if (priorityCompare != 0) return priorityCompare;
    return a.id.compareTo(b.id);
  }

  // ===========================================================================
  // Persistence
  // ===========================================================================

  /// Loads tickets from persistence.
  Future<void> load() async {
    try {
      final data = await _storage.loadTickets(projectId);
      if (data == null) {
        developer.log(
          'No tickets file found for project $projectId',
          name: 'TicketRepository',
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
        name: 'TicketRepository',
      );

      notifyListeners();
    } catch (e) {
      developer.log(
        'Failed to load tickets: $e',
        name: 'TicketRepository',
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

        await _storage.saveTickets(projectId, data);

        developer.log(
          'Saved ${_tickets.length} tickets for project $projectId',
          name: 'TicketRepository',
        );
      } catch (e) {
        developer.log(
          'Failed to save tickets: $e',
          name: 'TicketRepository',
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
        name: 'TicketRepository',
        error: e,
      );
    });
  }
}
