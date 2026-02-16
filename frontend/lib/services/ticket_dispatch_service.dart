import 'dart:developer' as developer;

import '../models/chat.dart';
import '../models/project.dart';
import '../models/ticket.dart';
import '../models/worktree.dart';
import '../state/selection_state.dart';
import '../state/ticket_board_state.dart';
import 'project_restore_service.dart';
import 'worktree_service.dart';

/// Service for dispatching agents to work on tickets.
///
/// Handles creating (or selecting) a worktree, creating a chat, composing the
/// initial prompt with ticket context, and linking everything together.
class TicketDispatchService {
  final TicketRepository _ticketBoard;
  final ProjectState _project;
  final SelectionState _selection;
  final WorktreeService _worktreeService;
  final ProjectRestoreService _restoreService;

  /// Creates a [TicketDispatchService] with required dependencies.
  TicketDispatchService({
    required TicketRepository ticketBoard,
    required ProjectState project,
    required SelectionState selection,
    required WorktreeService worktreeService,
    ProjectRestoreService? restoreService,
  })  : _ticketBoard = ticketBoard,
        _project = project,
        _selection = selection,
        _worktreeService = worktreeService,
        _restoreService = restoreService ?? ProjectRestoreService();

  /// Derives a git-safe branch name from a ticket.
  ///
  /// Format: `tkt-{id}-{slugified-title}`, max 50 characters.
  /// - Converts to lowercase
  /// - Replaces spaces and non-alphanumeric chars with hyphens
  /// - Collapses consecutive hyphens
  /// - Trims leading/trailing hyphens from the slug portion
  /// - Truncates to 50 characters total
  static String deriveBranchName(int ticketId, String title) {
    final prefix = 'tkt-$ticketId-';

    // Slugify the title
    var slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    // Truncate to fit within 50 chars total
    final maxSlugLength = 50 - prefix.length;
    if (slug.length > maxSlugLength) {
      slug = slug.substring(0, maxSlugLength);
      // Remove trailing hyphen if we cut mid-word
      slug = slug.replaceAll(RegExp(r'-+$'), '');
    }

    return '$prefix$slug';
  }

  /// Builds the initial prompt for an agent working on a ticket.
  ///
  /// Includes the ticket title, description, and dependency context.
  /// Completed dependencies are listed with their summaries.
  /// Incomplete dependencies are listed as potential blockers.
  String buildTicketPrompt(TicketData ticket, List<TicketData> allTickets) {
    final buffer = StringBuffer();

    buffer.writeln('# Ticket ${ticket.displayId}: ${ticket.title}');
    buffer.writeln();

    if (ticket.description.isNotEmpty) {
      buffer.writeln(ticket.description);
      buffer.writeln();
    }

    // Add metadata
    buffer.writeln('**Kind:** ${ticket.kind.label}');
    buffer.writeln('**Priority:** ${ticket.priority.label}');
    buffer.writeln('**Effort:** ${ticket.effort.label}');
    if (ticket.category != null) {
      buffer.writeln('**Category:** ${ticket.category}');
    }
    if (ticket.tags.isNotEmpty) {
      buffer.writeln('**Tags:** ${ticket.tags.join(', ')}');
    }
    buffer.writeln();

    // Add dependency context
    if (ticket.dependsOn.isNotEmpty) {
      final completedDeps = <TicketData>[];
      final incompleteDeps = <TicketData>[];

      for (final depId in ticket.dependsOn) {
        final dep = allTickets.where((t) => t.id == depId).firstOrNull;
        if (dep == null) continue;

        if (dep.status == TicketStatus.completed) {
          completedDeps.add(dep);
        } else {
          incompleteDeps.add(dep);
        }
      }

      if (completedDeps.isNotEmpty) {
        buffer.writeln('## Completed Dependencies');
        for (final dep in completedDeps) {
          buffer.writeln('- [x] ${dep.displayId}: ${dep.title}');
        }
        buffer.writeln();
      }

      if (incompleteDeps.isNotEmpty) {
        buffer.writeln('## Incomplete Dependencies (potential blockers)');
        for (final dep in incompleteDeps) {
          buffer.writeln('- [ ] ${dep.displayId}: ${dep.title} (${dep.status.label})');
        }
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  /// Begins work on a ticket in a new worktree.
  ///
  /// Creates a linked worktree with a branch derived from the ticket title,
  /// creates a chat in the new worktree, sets the chat's draft text to the
  /// ticket context prompt, links the ticket to the worktree and chat,
  /// sets the ticket status to active, and navigates to the new chat.
  ///
  /// Throws if the ticket is not found or if worktree creation fails.
  Future<void> beginInNewWorktree(int ticketId) async {
    final ticket = _ticketBoard.getTicket(ticketId);
    if (ticket == null) {
      throw ArgumentError('Ticket $ticketId not found');
    }

    developer.log(
      'Dispatching ticket ${ticket.displayId} to new worktree',
      name: 'TicketDispatchService',
    );

    // 1. Derive branch name
    final branch = deriveBranchName(ticket.id, ticket.title);

    // 2. Calculate worktree root
    final worktreeRoot = await calculateDefaultWorktreeRoot(
      _project.data.repoRoot,
    );

    // 3. Create linked worktree
    final worktreeState = await _worktreeService.createWorktree(
      project: _project,
      branch: branch,
      worktreeRoot: worktreeRoot,
    );

    // 4. Add worktree to project
    _project.addLinkedWorktree(worktreeState, select: true);

    // 5. Create chat and persist it
    final chatState = _createAndConfigureChat(ticket, worktreeState.data.worktreeRoot);
    await _restoreService.addChatToWorktree(
      _project.data.repoRoot,
      worktreeState.data.worktreeRoot,
      chatState,
    );

    // 6. Add chat to worktree and select it
    worktreeState.addChat(chatState, select: true);

    // 7. Link ticket to worktree and chat
    _ticketBoard.linkWorktree(
      ticketId,
      worktreeState.data.worktreeRoot,
      worktreeState.data.branch,
    );
    _ticketBoard.linkChat(
      ticketId,
      chatState.data.id,
      chatState.data.name,
      worktreeState.data.worktreeRoot,
    );

    // 8. Set ticket status to active
    _ticketBoard.setStatus(ticketId, TicketStatus.active);

    // 9. Navigate: select the worktree and chat
    _selection.selectWorktree(worktreeState);
    _selection.selectChat(chatState);

    developer.log(
      'Ticket ${ticket.displayId} dispatched to ${worktreeState.data.branch}',
      name: 'TicketDispatchService',
    );
  }

  /// Begins work on a ticket in an existing worktree.
  ///
  /// Creates a chat in the given worktree, sets the chat's draft text to the
  /// ticket context prompt, links the ticket to the worktree and chat,
  /// sets the ticket status to active, and navigates to the new chat.
  ///
  /// Throws if the ticket is not found.
  Future<void> beginInWorktree(int ticketId, WorktreeState worktree) async {
    final ticket = _ticketBoard.getTicket(ticketId);
    if (ticket == null) {
      throw ArgumentError('Ticket $ticketId not found');
    }

    developer.log(
      'Dispatching ticket ${ticket.displayId} to existing worktree: ${worktree.data.branch}',
      name: 'TicketDispatchService',
    );

    // 1. Create chat and persist it
    final chatState = _createAndConfigureChat(ticket, worktree.data.worktreeRoot);
    await _restoreService.addChatToWorktree(
      _project.data.repoRoot,
      worktree.data.worktreeRoot,
      chatState,
    );

    // 2. Add chat to worktree and select it
    worktree.addChat(chatState, select: true);

    // 3. Link ticket to worktree and chat
    _ticketBoard.linkWorktree(
      ticketId,
      worktree.data.worktreeRoot,
      worktree.data.branch,
    );
    _ticketBoard.linkChat(
      ticketId,
      chatState.data.id,
      chatState.data.name,
      worktree.data.worktreeRoot,
    );

    // 4. Set ticket status to active
    _ticketBoard.setStatus(ticketId, TicketStatus.active);

    // 5. Navigate: select the worktree and chat
    _selection.selectWorktree(worktree);
    _selection.selectChat(chatState);

    developer.log(
      'Ticket ${ticket.displayId} dispatched to ${worktree.data.branch}',
      name: 'TicketDispatchService',
    );
  }

  /// Creates a chat for a ticket and sets its draft text to the ticket prompt.
  ChatState _createAndConfigureChat(TicketData ticket, String worktreeRoot) {
    final chatState = ChatState.create(
      name: ticket.displayId,
      worktreeRoot: worktreeRoot,
    );

    final prompt = buildTicketPrompt(ticket, _ticketBoard.tickets);
    chatState.draftText = prompt;

    return chatState;
  }
}
