import 'package:flutter/material.dart';

import '../config/fonts.dart';
import '../models/ticket.dart';
import 'tag_colors.dart';

/// Formats a [DateTime] for display in ticket list items.
///
/// Same day → time (e.g. "14:32"), same year → "22 Jun",
/// different year → "22 Jun 2025".
String _formatDate(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (date.year == today.year &&
      date.month == today.month &&
      date.day == today.day) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final dayStr = date.day.toString();
  final monthStr = months[date.month - 1];
  if (date.year == today.year) {
    return '$dayStr $monthStr';
  }
  return '$dayStr $monthStr ${date.year}';
}

/// A single ticket row in the ticket list panel.
class TicketListItem extends StatelessWidget {
  /// The ticket to display.
  final TicketData ticket;

  /// Whether this item is currently selected (viewed in detail panel).
  final bool isSelected;

  /// Whether this item is part of the multi-selection set.
  final bool isMultiSelected;

  /// Called when the item is tapped.
  final VoidCallback? onTap;

  const TicketListItem({
    super.key,
    required this.ticket,
    this.isSelected = false,
    this.isMultiSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final titleColor = ticket.isOpen
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    final subtitleColor = colorScheme.onSurfaceVariant;

    Color backgroundColor;
    if (isSelected) {
      backgroundColor = colorScheme.primaryContainer.withValues(alpha: 0.4);
    } else if (isMultiSelected) {
      backgroundColor = colorScheme.tertiaryContainer.withValues(alpha: 0.3);
    } else {
      backgroundColor = Colors.transparent;
    }

    return Material(
      color: backgroundColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Multi-select checkbox or status icon
              if (isMultiSelected)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    Icons.check_box,
                    size: 16,
                    color: colorScheme.tertiary,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Icon(
                    ticket.isOpen
                        ? Icons.radio_button_checked
                        : Icons.check_circle,
                    size: 16,
                    color: ticket.isOpen
                        ? Colors.green
                        : Colors.purple,
                  ),
                ),
              // Content area
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(titleColor),
                    const SizedBox(height: 2),
                    _buildSubtitleRow(subtitleColor),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(Color titleColor) {
    final tags = ticket.tags.toList()..sort();
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: ticket.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: titleColor,
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  const WidgetSpan(child: SizedBox(width: 6)),
                  for (final tag in tags) ...[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _TagChip(tag: tag),
                    ),
                    const WidgetSpan(child: SizedBox(width: 4)),
                  ],
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitleRow(Color subtitleColor) {
    final statusWord = ticket.isOpen ? 'opened' : 'closed';
    final date = ticket.isOpen ? ticket.createdAt : (ticket.closedAt ?? ticket.updatedAt);
    final dateStr = _formatDate(date);
    final commentCount = ticket.comments.length;

    return Row(
      children: [
        // #id in monospace
        Text(
          ticket.displayId,
          style: AppFonts.monoTextStyle(
            fontSize: 10,
            color: subtitleColor,
          ),
        ),
        const SizedBox(width: 6),
        // "opened/closed [date] by [author]"
        Expanded(
          child: Text(
            '$statusWord $dateStr by ${ticket.author}',
            style: TextStyle(fontSize: 10, color: subtitleColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Comment count
        if (commentCount > 0) ...[
          const SizedBox(width: 6),
          Icon(Icons.chat_bubble_outline, size: 11, color: subtitleColor),
          const SizedBox(width: 2),
          Text(
            '$commentCount',
            style: TextStyle(fontSize: 10, color: subtitleColor),
          ),
        ],
        // Dependency indicator
        if (ticket.dependsOn.isNotEmpty) ...[
          const SizedBox(width: 6),
          Icon(Icons.link, size: 11, color: subtitleColor),
          const SizedBox(width: 2),
          Text(
            '${ticket.dependsOn.length}',
            style: TextStyle(fontSize: 10, color: subtitleColor),
          ),
        ],
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String tag;

  const _TagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final color = tagColor(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
