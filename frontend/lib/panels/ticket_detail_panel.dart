import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../services/author_service.dart' hide AuthorType;
import '../state/ticket_board_state.dart';
import '../state/ticket_view_state.dart';
import '../widgets/ticket_comment_input.dart';
import '../widgets/ticket_edit_form.dart';
import '../widgets/ticket_sidebar.dart';
import '../widgets/ticket_status_badge.dart';
import '../widgets/ticket_timeline.dart';

/// Test keys for the ticket detail panel.
class TicketDetailPanelKeys {
  TicketDetailPanelKeys._();

  static const Key editButton = Key('ticket-detail-edit');
}

/// Ticket detail panel assembling issue header, timeline, and sidebar.
///
/// Handles three modes via [TicketViewState.detailMode]:
/// - [TicketDetailMode.detail]: Issue header at top, then two columns
///   (timeline + comment input on the left, sidebar on the right).
/// - [TicketDetailMode.create]: Create ticket form.
/// - [TicketDetailMode.edit]: Edit ticket form.
///
/// Shows "Select a ticket to view details" when no ticket is selected.
class TicketDetailPanel extends StatelessWidget {
  const TicketDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final viewState = context.watch<TicketViewState>();

    return switch (viewState.detailMode) {
      TicketDetailMode.create => const _CreateForm(),
      TicketDetailMode.edit => _buildEditMode(context, viewState),
      TicketDetailMode.detail => _buildDetailMode(context, viewState),
    };
  }

  Widget _buildEditMode(BuildContext context, TicketViewState viewState) {
    final ticket = viewState.selectedTicket;
    if (ticket == null) return const _EmptyState();

    final repo = context.read<TicketRepository>();
    return TicketEditForm(
      ticket: ticket,
      repository: repo,
      onSave: () => viewState.setDetailMode(TicketDetailMode.detail),
      onCancel: () => viewState.setDetailMode(TicketDetailMode.detail),
    );
  }

  Widget _buildDetailMode(BuildContext context, TicketViewState viewState) {
    final ticket = viewState.selectedTicket;
    if (ticket == null) return const _EmptyState();
    return _DetailContent(ticket: ticket);
  }
}

/// Empty state shown when no ticket is selected.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'Select a ticket to view details',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Full detail layout: header + two-column body (timeline | sidebar).
class _DetailContent extends StatelessWidget {
  final TicketData ticket;

  const _DetailContent({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final viewState = context.read<TicketViewState>();
    final repo = context.watch<TicketRepository>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Issue header at top.
          TicketIssueHeader(
            ticket: ticket,
            onEdit: () =>
                viewState.setDetailMode(TicketDetailMode.edit),
          ),
          const SizedBox(height: 12),
          // Two-column layout below header.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline column (left, flex).
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: TicketTimeline(ticket: ticket),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(left: 34),
                        child: TicketCommentInput(
                          ticket: ticket,
                          onComment: (text) => repo.addComment(
                            ticket.id,
                            text,
                            AuthorService.currentUser,
                            AuthorType.user,
                          ),
                          onToggleStatus: () {
                            final actor = AuthorService.currentUser;
                            if (ticket.isOpen) {
                              repo.closeTicket(
                                  ticket.id, actor, AuthorType.user);
                            } else {
                              repo.reopenTicket(
                                  ticket.id, actor, AuthorType.user);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Sidebar column (right, fixed ~200px).
                TicketSidebar(
                  ticket: ticket,
                  allTickets: repo.tickets,
                  repo: repo,
                  onTicketTap: (id) => viewState.selectTicket(id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder create form (V2 create form is a separate ticket).
class _CreateForm extends StatelessWidget {
  const _CreateForm();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Create ticket'));
  }
}
