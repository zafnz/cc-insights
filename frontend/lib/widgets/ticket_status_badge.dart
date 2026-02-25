import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';

/// Test keys for the [TicketIssueHeader].
class TicketIssueHeaderKeys {
  TicketIssueHeaderKeys._();

  static const Key launchWorktreeButton = Key('ticket-header-launch-worktree');
}

/// Pill-shaped status badge showing Open (green) or Closed (purple).
class TicketStatusBadge extends StatelessWidget {
  final bool isOpen;

  const TicketStatusBadge({super.key, required this.isOpen});

  @override
  Widget build(BuildContext context) {
    final color = isOpen ? Colors.green : Colors.purple;
    final icon = isOpen ? Icons.radio_button_checked : Icons.check_circle;
    final label = isOpen ? 'Open' : 'Closed';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// GitHub Issues-style header for a ticket detail view.
///
/// Shows the status badge, title with ticket number, action buttons,
/// author/date meta line, and a bottom border separator.
class TicketIssueHeader extends StatelessWidget {
  final TicketData ticket;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onLaunchWorktree;
  final bool isLaunchingWorktree;

  const TicketIssueHeader({
    super.key,
    required this.ticket,
    this.onEdit,
    this.onDelete,
    this.onLaunchWorktree,
    this.isLaunchingWorktree = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subdued = theme.colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: status badge + action buttons
          Row(
            children: [
              TicketStatusBadge(isOpen: ticket.isOpen),
              const Spacer(),
              if (onLaunchWorktree != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OutlinedButton.icon(
                    key: TicketIssueHeaderKeys.launchWorktreeButton,
                    onPressed:
                        isLaunchingWorktree ? null : onLaunchWorktree,
                    icon: isLaunchingWorktree
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.account_tree, size: 16),
                    label: const Text('Launch Worktree'),
                  ),
                ),
              if (onEdit != null)
                OutlinedButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Title + ticket number
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: ticket.title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                TextSpan(
                  text: ' ${ticket.displayId}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: subdued,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Meta line: author opened on date
          Text(
            '${ticket.author} opened on ${DateFormat.yMMMd().format(ticket.createdAt)}',
            style: TextStyle(fontSize: 13, color: subdued),
          ),
        ],
      ),
    );
  }
}
