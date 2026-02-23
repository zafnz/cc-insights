import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/design_tokens.dart';
import '../services/menu_action_service.dart';
import '../state/bulk_proposal_state.dart';

// =============================================================================
// Test Keys
// =============================================================================

/// Keys for testing TicketProposalCard widgets.
class TicketProposalCardKeys {
  TicketProposalCardKeys._();

  /// The root container of the card.
  static const card = Key('ticket_proposal_card');

  /// The header text showing count and chat name.
  static const header = Key('ticket_proposal_card_header');

  /// The Expand button.
  static const expandButton = Key('ticket_proposal_card_expand');

  /// The ticket list area.
  static const ticketList = Key('ticket_proposal_card_ticket_list');

  /// The overflow text (e.g. "+2 more").
  static const overflowText = Key('ticket_proposal_card_overflow');

  /// The Reject button.
  static const rejectButton = Key('ticket_proposal_card_reject');

  /// The Approve button.
  static const approveButton = Key('ticket_proposal_card_approve');
}

// =============================================================================
// TicketProposalCard
// =============================================================================

/// Maximum number of ticket titles to show before overflow text.
const _maxVisibleTickets = 4;

/// Compact inline card showing a bulk ticket proposal for review.
///
/// Watches [BulkProposalState] and renders when there is an active proposal.
/// Returns [SizedBox.shrink] when no proposal is active.
///
/// Actions:
/// - **Expand** triggers [MenuAction.showTickets] to navigate to the full
///   bulk review panel.
/// - **Approve** calls [BulkProposalState.approveBulk].
/// - **Reject** calls [BulkProposalState.rejectAll].
class TicketProposalCard extends StatelessWidget {
  const TicketProposalCard({super.key});

  @override
  Widget build(BuildContext context) {
    final bulkState = context.watch<BulkProposalState>();

    if (!bulkState.hasActiveProposal) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final tickets = bulkState.proposedTickets;
    final chatName = bulkState.proposalSourceChatName;

    return Container(
      key: TicketProposalCardKeys.card,
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.15),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
        borderRadius: Radii.largeBorderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          _Header(
            ticketCount: tickets.length,
            chatName: chatName,
          ),
          const SizedBox(height: Spacing.md),
          // Ticket title list
          _TicketList(
            titles: tickets.map((t) => t.title).toList(),
          ),
          const SizedBox(height: Spacing.md),
          // Action buttons
          _ActionButtons(bulkState: bulkState),
        ],
      ),
    );
  }
}

// =============================================================================
// Header
// =============================================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.ticketCount,
    required this.chatName,
  });

  final int ticketCount;
  final String chatName;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.confirmation_number_outlined,
          size: IconSizes.md,
          color: colorScheme.primary,
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Text(
            key: TicketProposalCardKeys.header,
            '$ticketCount ticket${ticketCount == 1 ? '' : 's'} proposed by "$chatName"',
            style: TextStyle(
              fontSize: FontSizes.body,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: Spacing.md),
        TextButton.icon(
          key: TicketProposalCardKeys.expandButton,
          onPressed: () {
            context
                .read<MenuActionService>()
                .triggerAction(MenuAction.showTickets);
          },
          icon: Icon(Icons.open_in_full, size: IconSizes.xs),
          label: const Text('Expand'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            textStyle: const TextStyle(fontSize: FontSizes.bodySmall),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Ticket List
// =============================================================================

class _TicketList extends StatelessWidget {
  const _TicketList({required this.titles});

  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleCount =
        titles.length > _maxVisibleTickets ? _maxVisibleTickets : titles.length;
    final overflowCount = titles.length - visibleCount;

    return Column(
      key: TicketProposalCardKeys.ticketList,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleCount; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Row(
              children: [
                Text(
                  '\u2022',
                  style: TextStyle(
                    fontSize: FontSizes.bodySmall,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    titles[i],
                    style: TextStyle(
                      fontSize: FontSizes.bodySmall,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (overflowCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              key: TicketProposalCardKeys.overflowText,
              '+$overflowCount more',
              style: TextStyle(
                fontSize: FontSizes.bodySmall,
                fontStyle: FontStyle.italic,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Action Buttons
// =============================================================================

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.bulkState});

  final BulkProposalState bulkState;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: TicketProposalCardKeys.rejectButton,
          onPressed: bulkState.rejectAll,
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.error,
            textStyle: const TextStyle(fontSize: FontSizes.bodySmall),
          ),
          child: const Text('Reject'),
        ),
        const SizedBox(width: Spacing.md),
        FilledButton(
          key: TicketProposalCardKeys.approveButton,
          onPressed: bulkState.approveBulk,
          style: FilledButton.styleFrom(
            textStyle: const TextStyle(fontSize: FontSizes.bodySmall),
          ),
          child: const Text('Approve'),
        ),
      ],
    );
  }
}
