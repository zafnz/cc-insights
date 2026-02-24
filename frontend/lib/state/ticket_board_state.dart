import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/ticket.dart';
import '../services/author_service.dart' show AuthorService;
import '../services/ticket_storage_service.dart';

const _uuid = Uuid();

/// Repository for ticket data persistence and CRUD operations.
///
/// Manages ticket storage, dependency validation, and open/close transitions.
/// Uses [TicketStorageService] for persistence.
class TicketRepository extends ChangeNotifier {
  final String projectId;
  final TicketStorageService _storage;

  /// Save queue to serialize save operations.
  Future<void>? _pendingSave;

  /// Internal ticket storage.
  List<TicketData> _tickets = [];

  /// Tag registry tracking all known tags.
  List<TagDefinition> _tagRegistry = [];

  /// The next ID to assign when creating a ticket.
  int _nextId = 1;

  /// Controller for the ticket-ready stream.
  final StreamController<TicketData> _onTicketReadyController =
      StreamController<TicketData>.broadcast();

  /// Emits a ticket when all of its dependencies have been closed,
  /// signalling that the ticket is now actionable.
  Stream<TicketData> get onTicketReady => _onTicketReadyController.stream;

  /// Creates a [TicketRepository] for the given project.
  ///
  /// The [storage] parameter is optional for testing; if not provided,
  /// a default instance is created.
  TicketRepository(this.projectId, {TicketStorageService? storage})
    : _storage = storage ?? TicketStorageService();

  /// Unmodifiable view of all tickets.
  List<TicketData> get tickets => List.unmodifiable(_tickets);

  /// Unmodifiable view of the tag registry.
  List<TagDefinition> get tagRegistry => List.unmodifiable(_tagRegistry);

  /// Count of open tickets.
  int get openCount => _tickets.where((t) => t.isOpen).length;

  /// Count of closed tickets.
  int get closedCount => _tickets.where((t) => !t.isOpen).length;

  // ===========================================================================
  // CRUD Methods
  // ===========================================================================

  /// Creates a new ticket.
  ///
  /// Tags are stored lowercase. No activity event is generated for creation —
  /// the body block serves as the creation record. Returns the created ticket.
  TicketData createTicket({
    required String title,
    String body = '',
    Set<String> tags = const {},
    String? author,
    AuthorType? authorType,
    List<int> dependsOn = const [],
    String? sourceConversationId,
  }) {
    final resolvedAuthor = author ?? AuthorService.currentUser;
    final now = DateTime.now();
    final ticket = TicketData(
      id: _nextId++,
      title: title,
      body: body,
      author: resolvedAuthor,
      isOpen: true,
      tags: tags,
      dependsOn: dependsOn,
      sourceConversationId: sourceConversationId,
      createdAt: now,
      updatedAt: now,
    );

    _tickets.add(ticket);
    notifyListeners();
    _autoSave();

    return ticket;
  }

  /// Updates a ticket's title and/or body.
  ///
  /// Generates [ActivityEventType.titleEdited] and/or
  /// [ActivityEventType.bodyEdited] activity events when values change.
  void updateTicket(
    int id, {
    String? title,
    String? body,
    String? actor,
    AuthorType? actorType,
  }) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    final now = DateTime.now();
    final resolvedActor = actor ?? AuthorService.currentUser;
    final resolvedActorType = actorType ?? AuthorType.user;
    final events = <ActivityEvent>[];

    if (title != null && title != ticket.title) {
      events.add(ActivityEvent(
        id: _uuid.v4(),
        type: ActivityEventType.titleEdited,
        actor: resolvedActor,
        actorType: resolvedActorType,
        timestamp: now,
        data: {'oldTitle': ticket.title, 'newTitle': title},
      ));
    }

    if (body != null && body != ticket.body) {
      events.add(ActivityEvent(
        id: _uuid.v4(),
        type: ActivityEventType.bodyEdited,
        actor: resolvedActor,
        actorType: resolvedActorType,
        timestamp: now,
      ));
    }

    _tickets[index] = ticket.copyWith(
      title: title,
      body: body,
      activityLog: [...ticket.activityLog, ...events],
      updatedAt: now,
    );

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
  // Close / Reopen
  // ===========================================================================

  /// Closes a ticket.
  ///
  /// Sets [TicketData.isOpen] to `false`, sets [TicketData.closedAt] to now,
  /// and records a [ActivityEventType.closed] activity event.
  void closeTicket(int id, String actor, AuthorType actorType) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    if (!ticket.isOpen) return;
    final now = DateTime.now();

    _tickets[index] = ticket.copyWith(
      isOpen: false,
      closedAt: now,
      updatedAt: now,
      activityLog: [
        ...ticket.activityLog,
        ActivityEvent(
          id: _uuid.v4(),
          type: ActivityEventType.closed,
          actor: actor,
          actorType: actorType,
          timestamp: now,
        ),
      ],
    );

    notifyListeners();
    _autoSave();

    // Check if closing this ticket unblocks any dependents.
    _emitNewlyReady(id);
  }

  /// Reopens a closed ticket.
  ///
  /// Sets [TicketData.isOpen] to `true`, clears [TicketData.closedAt],
  /// and records a [ActivityEventType.reopened] activity event.
  void reopenTicket(int id, String actor, AuthorType actorType) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    if (ticket.isOpen) return;
    final now = DateTime.now();

    _tickets[index] = ticket.copyWith(
      isOpen: true,
      clearClosedAt: true,
      updatedAt: now,
      activityLog: [
        ...ticket.activityLog,
        ActivityEvent(
          id: _uuid.v4(),
          type: ActivityEventType.reopened,
          actor: actor,
          actorType: actorType,
          timestamp: now,
        ),
      ],
    );

    notifyListeners();
    _autoSave();
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
  /// Records a [ActivityEventType.dependencyAdded] activity event.
  /// Throws [ArgumentError] if validation fails.
  void addDependency(
    int ticketId,
    int dependsOnId, {
    String? actor,
    AuthorType? actorType,
  }) {
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
      throw ArgumentError('Adding this dependency would create a cycle');
    }

    final resolvedActor = actor ?? AuthorService.currentUser;
    final resolvedActorType = actorType ?? AuthorType.user;
    final now = DateTime.now();

    // Add the dependency
    _applyUpdate(ticketId, (ticket) {
      if (ticket.dependsOn.contains(dependsOnId)) {
        return ticket; // Already exists
      }
      return ticket.copyWith(
        dependsOn: [...ticket.dependsOn, dependsOnId],
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.dependencyAdded,
            actor: resolvedActor,
            actorType: resolvedActorType,
            timestamp: now,
            data: {'dependsOnId': dependsOnId},
          ),
        ],
      );
    });
  }

  /// Removes a dependency relationship.
  ///
  /// Records a [ActivityEventType.dependencyRemoved] activity event.
  void removeDependency(
    int ticketId,
    int dependsOnId, {
    String? actor,
    AuthorType? actorType,
  }) {
    final resolvedActor = actor ?? AuthorService.currentUser;
    final resolvedActorType = actorType ?? AuthorType.user;
    final now = DateTime.now();

    _applyUpdate(ticketId, (ticket) {
      if (!ticket.dependsOn.contains(dependsOnId)) return ticket;
      return ticket.copyWith(
        dependsOn: ticket.dependsOn.where((d) => d != dependsOnId).toList(),
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.dependencyRemoved,
            actor: resolvedActor,
            actorType: resolvedActorType,
            timestamp: now,
            data: {'dependsOnId': dependsOnId},
          ),
        ],
      );
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
  // Tag Methods
  // ===========================================================================

  /// Adds a tag to a ticket.
  ///
  /// The tag is normalized to lowercase. Records a [ActivityEventType.tagAdded]
  /// activity event and ensures the tag appears in the tag registry.
  void addTag(int id, String tag, String actor, AuthorType actorType) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    final normalized = tag.toLowerCase();

    if (ticket.tags.contains(normalized)) return;

    final now = DateTime.now();
    _tickets[index] = ticket.copyWith(
      tags: {...ticket.tags, normalized},
      activityLog: [
        ...ticket.activityLog,
        ActivityEvent(
          id: _uuid.v4(),
          type: ActivityEventType.tagAdded,
          actor: actor,
          actorType: actorType,
          timestamp: now,
          data: {'tag': normalized},
        ),
      ],
      updatedAt: now,
    );

    _ensureTagInRegistry(normalized);
    notifyListeners();
    _autoSave();
  }

  /// Removes a tag from a ticket.
  ///
  /// Records a [ActivityEventType.tagRemoved] activity event.
  void removeTag(int id, String tag, String actor, AuthorType actorType) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    final normalized = tag.toLowerCase();

    if (!ticket.tags.contains(normalized)) return;

    final now = DateTime.now();
    _tickets[index] = ticket.copyWith(
      tags: ticket.tags.where((t) => t != normalized).toSet(),
      activityLog: [
        ...ticket.activityLog,
        ActivityEvent(
          id: _uuid.v4(),
          type: ActivityEventType.tagRemoved,
          actor: actor,
          actorType: actorType,
          timestamp: now,
          data: {'tag': normalized},
        ),
      ],
      updatedAt: now,
    );

    notifyListeners();
    _autoSave();
  }

  /// Bulk tag operation.
  ///
  /// Compares old vs new tags and generates [ActivityEventType.tagAdded] /
  /// [ActivityEventType.tagRemoved] events for each difference. All tags are
  /// normalized to lowercase.
  void setTags(int id, Set<String> newTags, String actor, AuthorType actorType) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final ticket = _tickets[index];
    final normalizedNew = newTags.map((t) => t.toLowerCase()).toSet();
    final oldTags = ticket.tags;

    if (setEquals(normalizedNew, oldTags)) return;

    final now = DateTime.now();
    final events = <ActivityEvent>[];

    // Tags that were added
    for (final tag in normalizedNew.difference(oldTags)) {
      events.add(ActivityEvent(
        id: _uuid.v4(),
        type: ActivityEventType.tagAdded,
        actor: actor,
        actorType: actorType,
        timestamp: now,
        data: {'tag': tag},
      ));
      _ensureTagInRegistry(tag);
    }

    // Tags that were removed
    for (final tag in oldTags.difference(normalizedNew)) {
      events.add(ActivityEvent(
        id: _uuid.v4(),
        type: ActivityEventType.tagRemoved,
        actor: actor,
        actorType: actorType,
        timestamp: now,
        data: {'tag': tag},
      ));
    }

    _tickets[index] = ticket.copyWith(
      tags: normalizedNew,
      activityLog: [...ticket.activityLog, ...events],
      updatedAt: now,
    );

    notifyListeners();
    _autoSave();
  }

  // ===========================================================================
  // Linking Methods
  // ===========================================================================

  /// Links a worktree to a ticket.
  ///
  /// Adds a [LinkedWorktree] entry to the ticket's [linkedWorktrees] list.
  /// Does nothing if the ticket is not found.
  void linkWorktree(int ticketId, String worktreeRoot, String? branch) {
    _applyUpdate(ticketId, (ticket) {
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

  /// Links a worktree to a ticket with an activity event.
  ///
  /// Adds a [LinkedWorktree] entry and records a
  /// [ActivityEventType.worktreeLinked] activity event.
  void linkWorktreeWithEvent(
    int ticketId,
    String worktreeRoot,
    String? branch,
    String actor,
    AuthorType actorType,
  ) {
    final now = DateTime.now();
    _applyUpdate(ticketId, (ticket) {
      final alreadyLinked = ticket.linkedWorktrees.any(
        (w) => w.worktreeRoot == worktreeRoot,
      );
      if (alreadyLinked) return ticket;

      return ticket.copyWith(
        linkedWorktrees: [
          ...ticket.linkedWorktrees,
          LinkedWorktree(worktreeRoot: worktreeRoot, branch: branch),
        ],
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.worktreeLinked,
            actor: actor,
            actorType: actorType,
            timestamp: now,
            data: {
              'worktreeRoot': worktreeRoot,
              if (branch != null) 'branch': branch,
            },
          ),
        ],
      );
    });
  }

  /// Unlinks a worktree from a ticket.
  ///
  /// Removes the [LinkedWorktree] entry and records a
  /// [ActivityEventType.worktreeUnlinked] activity event.
  void unlinkWorktree(
    int ticketId,
    String worktreeRoot,
    String actor,
    AuthorType actorType,
  ) {
    final now = DateTime.now();
    _applyUpdate(ticketId, (ticket) {
      final exists = ticket.linkedWorktrees.any(
        (w) => w.worktreeRoot == worktreeRoot,
      );
      if (!exists) return ticket;

      return ticket.copyWith(
        linkedWorktrees: ticket.linkedWorktrees
            .where((w) => w.worktreeRoot != worktreeRoot)
            .toList(),
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.worktreeUnlinked,
            actor: actor,
            actorType: actorType,
            timestamp: now,
            data: {'worktreeRoot': worktreeRoot},
          ),
        ],
      );
    });
  }

  /// Links a chat to a ticket.
  ///
  /// Adds a [LinkedChat] entry to the ticket's [linkedChats] list.
  /// Does nothing if the ticket is not found.
  void linkChat(
    int ticketId,
    String chatId,
    String chatName,
    String worktreeRoot,
  ) {
    _applyUpdate(ticketId, (ticket) {
      // Avoid duplicate links
      final alreadyLinked = ticket.linkedChats.any((c) => c.chatId == chatId);
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

  /// Links a chat to a ticket with an activity event.
  ///
  /// Adds a [LinkedChat] entry and records a
  /// [ActivityEventType.chatLinked] activity event.
  void linkChatWithEvent(
    int ticketId,
    String chatId,
    String chatName,
    String worktreeRoot,
    String actor,
    AuthorType actorType,
  ) {
    final now = DateTime.now();
    _applyUpdate(ticketId, (ticket) {
      final alreadyLinked = ticket.linkedChats.any((c) => c.chatId == chatId);
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
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.chatLinked,
            actor: actor,
            actorType: actorType,
            timestamp: now,
            data: {'chatId': chatId, 'chatName': chatName},
          ),
        ],
      );
    });
  }

  /// Unlinks a chat from a ticket.
  ///
  /// Removes the [LinkedChat] entry and records a
  /// [ActivityEventType.chatUnlinked] activity event.
  void unlinkChat(
    int ticketId,
    String chatId,
    String actor,
    AuthorType actorType,
  ) {
    final now = DateTime.now();
    _applyUpdate(ticketId, (ticket) {
      final exists = ticket.linkedChats.any((c) => c.chatId == chatId);
      if (!exists) return ticket;

      return ticket.copyWith(
        linkedChats:
            ticket.linkedChats.where((c) => c.chatId != chatId).toList(),
        activityLog: [
          ...ticket.activityLog,
          ActivityEvent(
            id: _uuid.v4(),
            type: ActivityEventType.chatUnlinked,
            actor: actor,
            actorType: actorType,
            timestamp: now,
            data: {'chatId': chatId},
          ),
        ],
      );
    });
  }

  /// Adds a comment to a ticket.
  ///
  /// Creates a new [TicketComment] with a uuid. Comments do NOT generate
  /// activity events.
  void addComment(
    int id,
    String text,
    String author,
    AuthorType authorType, {
    List<TicketImage> images = const [],
  }) {
    _applyUpdate(id, (ticket) {
      final comment = TicketComment(
        id: _uuid.v4(),
        text: text,
        author: author,
        authorType: authorType,
        images: images,
        createdAt: DateTime.now(),
      );
      return ticket.copyWith(comments: [...ticket.comments, comment]);
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

      // Restore tag registry
      final tagRegistryList = data['tagRegistry'] as List<dynamic>? ?? [];
      _tagRegistry = tagRegistryList
          .map((json) => TagDefinition.fromJson(json as Map<String, dynamic>))
          .toList();

      // Restore nextId, or compute from existing tickets
      if (data.containsKey('nextId')) {
        _nextId = data['nextId'] as int;
      } else if (_tickets.isNotEmpty) {
        // If nextId not in file, compute from max ticket ID + 1
        _nextId =
            _tickets.map((t) => t.id).reduce((a, b) => a > b ? a : b) + 1;
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
          'tagRegistry': _tagRegistry.map((t) => t.toJson()).toList(),
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

  // ===========================================================================
  // Private Helpers
  // ===========================================================================

  /// Ensures a tag exists in the tag registry.
  void _ensureTagInRegistry(String tag) {
    final normalized = tag.toLowerCase();
    if (!_tagRegistry.any((t) => t.name == normalized)) {
      _tagRegistry.add(TagDefinition(name: normalized));
    }
  }

  /// Applies an updater function to a ticket.
  ///
  /// Used internally by dependency, linking, and comment methods.
  void _applyUpdate(int id, TicketData Function(TicketData) updater) {
    final index = _tickets.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final updated = updater(_tickets[index]);
    _tickets[index] = updated.copyWith(updatedAt: DateTime.now());

    notifyListeners();
    _autoSave();
  }

  /// Emits open tickets that were blocked by [closedId] and now have all
  /// dependencies closed onto [onTicketReady].
  void _emitNewlyReady(int closedId) {
    for (final ticket in _tickets) {
      if (!ticket.isOpen) continue;
      if (!ticket.dependsOn.contains(closedId)) continue;

      // Check if ALL dependencies are now closed.
      final allDepsClosed = ticket.dependsOn.every((depId) {
        final dep = getTicket(depId);
        return dep != null && !dep.isOpen;
      });

      if (allDepsClosed) {
        _onTicketReadyController.add(ticket);
      }
    }
  }

  @override
  void dispose() {
    _onTicketReadyController.close();
    super.dispose();
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
