import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendProvider, TurnCompleteEvent;

import '../models/chat.dart';
import '../models/ticket.dart';
import '../state/ticket_board_state.dart';

/// Bridges event processing to ticket status transitions.
///
/// Extracted from [EventHandler] — all methods follow the same pattern:
/// check if ticketBoard is non-null, get linked tickets, update status.
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
  /// Transitions non-terminal linked tickets to [TicketStatus.inReview] and
  /// accumulates cost/usage statistics from the turn.
  void onTurnComplete(Chat chat, TurnCompleteEvent event) {
    final board = _ticketBoard;
    if (board == null) return;

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    if (linkedTickets.isEmpty) return;

    int totalTokens = 0;
    if (event.usage != null) {
      totalTokens = event.usage!.inputTokens + event.usage!.outputTokens;
    }

    final costUsd = event.costUsd ?? 0.0;
    final durationMs = event.durationMs ?? 0;

    for (final ticket in linkedTickets) {
      if (!ticket.isTerminal) {
        board.setStatus(ticket.id, TicketStatus.inReview);
      }

      if (totalTokens > 0 || costUsd > 0 || durationMs > 0) {
        board.accumulateCostStats(
          ticket.id,
          tokens: totalTokens,
          cost: costUsd,
          agentTimeMs: durationMs,
        );
      }
    }
  }

  /// Handles a permission request for ticket status transitions.
  ///
  /// When a linked chat requests permission, transitions linked tickets
  /// to [TicketStatus.needsInput] so the user knows attention is needed.
  void onPermissionRequest(Chat chat) {
    final board = _ticketBoard;
    if (board == null) return;

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    for (final ticket in linkedTickets) {
      if (!ticket.isTerminal && ticket.status == TicketStatus.active) {
        board.setStatus(ticket.id, TicketStatus.needsInput);
      }
    }
  }

  /// Notifies the bridge that a permission response was sent.
  ///
  /// Transitions linked tickets back to [TicketStatus.active] from
  /// [TicketStatus.needsInput].
  void onPermissionResponse(Chat chat) {
    final board = _ticketBoard;
    if (board == null) return;

    final linkedTickets = board.getTicketsForChat(chat.data.id);
    for (final ticket in linkedTickets) {
      if (ticket.status == TicketStatus.needsInput) {
        board.setStatus(ticket.id, TicketStatus.active);
      }
    }
  }
}
