import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/ticket.dart';
import '../state/rate_limit_state.dart';
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
          const _RateLimitStats(),
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

/// Rate limit display from Codex backend.
///
/// Shows primary and secondary rate limit windows when available.
/// Hidden when no rate limit data has been received.
class _RateLimitStats extends StatelessWidget {
  const _RateLimitStats();

  /// Returns a color based on usage percentage.
  Color _usageColor(int percent, ColorScheme colorScheme) {
    if (percent >= 80) return colorScheme.error;
    if (percent >= 50) return Colors.orange;
    return colorScheme.onSurfaceVariant;
  }

  /// Formats a reset time with relative day and time.
  String _formatResetTimeWithDay(int? resetsAtEpoch) {
    if (resetsAtEpoch == null) return 'unknown';
    final resetsAt =
        DateTime.fromMillisecondsSinceEpoch(resetsAtEpoch * 1000, isUtc: true);
    final now = DateTime.now().toUtc();
    final diff = resetsAt.difference(now);
    if (diff.isNegative) return 'expired';

    final dayDiff = resetsAt.difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final hour = resetsAt.hour;
    final minute = resetsAt.minute;
    final timeStr =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    String dayStr;
    if (dayDiff == 0) {
      dayStr = 'today';
    } else if (dayDiff == 1) {
      dayStr = 'tomorrow';
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      dayStr = days[resetsAt.weekday % 7];
    }

    final totalMinutes = diff.inMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final durationStr =
        mins > 0 ? '${hours}h${mins}m' : '${hours}h';

    return 'Resets $dayStr at $timeStr ($durationStr)';
  }

  @override
  Widget build(BuildContext context) {
    // Use nullable lookup so the widget works without the provider in tests.
    final RateLimitState? rateLimits;
    try {
      rateLimits = context.watch<RateLimitState>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!rateLimits.hasData) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final baseStyle = textTheme.labelSmall;

    // Determine highest usage for the overall color
    final maxUsage = [
      rateLimits.primary?.usedPercent ?? 0,
      rateLimits.secondary?.usedPercent ?? 0,
    ].reduce((a, b) => a > b ? a : b);

    // Build the main display text: "Codex: Usage: X%, Y%"
    final usageParts = <String>[];
    if (rateLimits.primary != null) {
      usageParts.add('${rateLimits.primary!.usedPercent}%');
    }
    if (rateLimits.secondary != null) {
      usageParts.add('${rateLimits.secondary!.usedPercent}%');
    }
    if (usageParts.isEmpty) return const SizedBox.shrink();

    // Build the tooltip with detailed info
    final tooltipLines = <String>[];
    if (rateLimits.primary != null) {
      final resetStr = _formatResetTimeWithDay(rateLimits.primary!.resetsAt);
      tooltipLines.add(
          'Primary: ${rateLimits.primary!.usedPercent}% used. $resetStr');
    }
    if (rateLimits.secondary != null) {
      final resetStr = _formatResetTimeWithDay(rateLimits.secondary!.resetsAt);
      tooltipLines.add(
          'Secondary: ${rateLimits.secondary!.usedPercent}% used. $resetStr');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusBarDot(),
        Tooltip(
          message: tooltipLines.join('\n'),
          child: Text(
            'Codex: Usage: ${usageParts.join(", ")}',
            style: baseStyle?.copyWith(
              color: _usageColor(maxUsage, colorScheme),
            ),
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
