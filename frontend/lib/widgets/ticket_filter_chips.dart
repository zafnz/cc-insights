import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/ticket_view_state.dart';
import 'ticket_tag_chip.dart';

/// A row of active tag filter chips with a "Clear all" action.
///
/// Only visible when [TicketViewState.tagFilters] is non-empty.
/// Each chip shows the tag name with an "x" to remove the filter.
class TicketFilterChips extends StatelessWidget {
  const TicketFilterChips({super.key});

  @override
  Widget build(BuildContext context) {
    final viewState = context.watch<TicketViewState>();
    final tags = viewState.tagFilters;

    if (tags.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in tags)
                  TicketTagChip(
                    tag: tag,
                    removable: true,
                    onRemove: () => viewState.removeTagFilter(tag),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: viewState.clearTagFilters,
            behavior: HitTestBehavior.opaque,
            child: Text(
              'Clear all',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
