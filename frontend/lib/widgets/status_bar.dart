import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/ticket.dart';
import '../state/ticket_board_state.dart';

/// Status bar showing backend connection status and statistics.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, this.showTicketStats = false});

  /// Whether to show ticket statistics instead of project statistics.
  ///
  /// When true, displays ticket counts. When false (default), displays
  /// worktree/chat/agent statistics.
  final bool showTicketStats;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Backend connection status (green dot)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Connected',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Stats on the right
          if (showTicketStats)
            _TicketStats()
          else
            _ProjectStats(),
        ],
      ),
    );
  }
}

/// A single stat in the status bar.
class _StatusBarStat extends StatelessWidget {
  const _StatusBarStat({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Text(
      '$count $label',
      style: textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Dot separator in status bar.
class _StatusBarDot extends StatelessWidget {
  const _StatusBarDot();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '•',
        style: TextStyle(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Project statistics (worktrees, chats, agents, cost).
class _ProjectStats extends StatelessWidget {
  const _ProjectStats();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();

    // Calculate stats from project state
    final worktreeCount = project.allWorktrees.length;
    final chatCount = project.allWorktrees
        .fold<int>(0, (sum, wt) => sum + wt.chats.length);
    final agentCount = project.allWorktrees.fold<int>(
      0,
      (sum, wt) => sum + wt.chats.fold<int>(
            0,
            (s, chat) => s + chat.data.subagentConversations.length,
          ),
    );
    // Sum total cost from all chats across all worktrees
    final totalCost = project.allWorktrees.fold<double>(
      0,
      (sum, wt) => sum + wt.chats.fold<double>(
            0,
            (s, chat) => s + chat.cumulativeUsage.costUsd,
          ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBarStat(label: 'worktrees', count: worktreeCount),
        const _StatusBarDot(),
        _StatusBarStat(label: 'chats', count: chatCount),
        const _StatusBarDot(),
        _StatusBarStat(label: 'agents', count: agentCount),
        const _StatusBarDot(),
        Text(
          'Total \$${totalCost.toStringAsFixed(2)}',
          style: textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Ticket statistics (total, by status).
class _TicketStats extends StatelessWidget {
  const _TicketStats();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ticketBoard = context.watch<TicketBoardState>();

    final totalCount = ticketBoard.tickets.length;
    final activeCount = ticketBoard.tickets
        .where((t) => t.status == TicketStatus.active)
        .length;
    final readyCount = ticketBoard.tickets
        .where((t) => t.status == TicketStatus.ready)
        .length;
    final blockedCount = ticketBoard.tickets
        .where((t) => t.status == TicketStatus.blocked)
        .length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusBarStat(
          label: totalCount == 1 ? 'ticket' : 'tickets',
          count: totalCount,
        ),
        if (activeCount > 0) ...[
          const _StatusBarDot(),
          _StatusBarStat(label: 'active', count: activeCount),
        ],
        if (readyCount > 0) ...[
          const _StatusBarDot(),
          _StatusBarStat(label: 'ready', count: readyCount),
        ],
        if (blockedCount > 0) ...[
          const _StatusBarDot(),
          _StatusBarStat(label: 'blocked', count: blockedCount),
        ],
      ],
    );
  }
}
