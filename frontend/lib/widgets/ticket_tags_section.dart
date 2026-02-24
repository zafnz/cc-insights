import 'package:flutter/material.dart';

import 'ticket_tag_chip.dart';

/// Sidebar section displaying tags on a ticket.
///
/// Shows an uppercase "TAGS" header with a bottom border and a "+" button to
/// add tags. Each tag is rendered as a [TicketTagChip] with an "x" button for
/// removal. In empty state only the header and "+" button are shown.
class TagsSection extends StatelessWidget {
  final List<String> tags;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;

  const TagsSection({
    super.key,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'TAGS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onAddTag,
                behavior: HitTestBehavior.opaque,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                TicketTagChip(
                  tag: tag,
                  removable: true,
                  onRemove: () => onRemoveTag(tag),
                ),
            ],
          ),
      ],
    );
  }
}
