import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendProvider, TurnCompleteEvent;

import '../models/chat.dart';
import '../models/ticket.dart';
import '../state/ticket_board_state.dart';
import 'author_service.dart' show AuthorService;

/// Bridges event processing to ticket tag transitions.
///
/// Extracted from [EventHandler] — all methods follow the same pattern:
/// check if ticketBoard is non-null, get linked tickets, update tags.
/// This has zero interaction with any other event processing state.
class TicketEventBridge {
  TicketRepository? _ticketBoard;

  TicketEventBridge({TicketRepository? ticketBoard})
    : _ticketBoard = ticketBoard;

  /// The current ticket board state, if any.
  TicketRepository? get ticketBoard => _ticketBoard;

  set ticketBoard(TicketRepository? value) => _ticketBoard = value;

  /// Updates linked tickets when a main agent turn completes.
  ///
  /// Adds an 'in-review' tag to open linked tickets so the user knows
  /// the agent has finished a turn and the work is ready for review.
  void onTurnComplete(Chat chat, TurnCompleteEvent event) {
    final board = _ticketBoard;
    if (board == null) return;

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    if (linkedTickets.isEmpty) return;

    final author = AuthorService.agentAuthor(chat.data.name);

    for (final ticket in linkedTickets) {
      if (ticket.isOpen) {
        board.addTag(ticket.id, 'in-review', author, AuthorType.agent);
      }
    }
  }

  /// Handles a permission request for ticket tag transitions.
  ///
  /// When a linked chat requests permission, adds a 'needs-input' tag
  /// to open linked tickets so the user knows attention is needed.
  void onPermissionRequest(Chat chat) {
    final board = _ticketBoard;
    if (board == null) return;

    final author = AuthorService.agentAuthor(chat.data.name);

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    for (final ticket in linkedTickets) {
      if (ticket.isOpen && !ticket.tags.contains('needs-input')) {
        board.addTag(ticket.id, 'needs-input', author, AuthorType.agent);
      }
    }
  }

  /// Notifies the bridge that a permission response was sent.
  ///
  /// Removes the 'needs-input' tag from linked tickets.
  void onPermissionResponse(Chat chat) {
    final board = _ticketBoard;
    if (board == null) return;

    final author = AuthorService.agentAuthor(chat.data.name);

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    for (final ticket in linkedTickets) {
      if (ticket.tags.contains('needs-input')) {
        board.removeTag(ticket.id, 'needs-input', author, AuthorType.agent);
      }
    }
  }
}
