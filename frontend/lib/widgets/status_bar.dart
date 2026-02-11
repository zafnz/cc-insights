import 'package:agent_sdk_core/agent_sdk_core.dart' show RateLimitWindow;
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

  /// Formats a window for the toolbar: "5hr 80% (reset in 3h2m)".
  static String _formatToolbarWindow(RateLimitWindow window) {
    final windowLabel = RateLimitState.formatWindowDuration(
        window.windowDurationMins);
    final resetLabel = RateLimitState.formatResetDuration(window.resetsAt);
    final parts = <String>[
      if (windowLabel != null) windowLabel,
      '${window.usedPercent}%',
      if (resetLabel != null) '(reset in $resetLabel)',
    ];
    return parts.join(' ');
  }

  /// Formats a reset time for the tooltip: "Resets Today at 6pm (3h2m)".
  static String _formatTooltipReset(int? resetsAtEpoch) {
    if (resetsAtEpoch == null) return '';
    final resetsAt = DateTime.fromMillisecondsSinceEpoch(
        resetsAtEpoch * 1000, isUtc: true)
        .toLocal();
    final now = DateTime.now();
    final diff = resetsAt.difference(now);
    if (diff.isNegative) return '';

    // Relative day label
    final todayStart = DateTime(now.year, now.month, now.day);
    final resetDayStart =
        DateTime(resetsAt.year, resetsAt.month, resetsAt.day);
    final dayDiff = resetDayStart.difference(todayStart).inDays;

    String dayStr;
    if (dayDiff == 0) {
      dayStr = 'Today';
    } else if (dayDiff == 1) {
      dayStr = 'Tomorrow';
    } else {
      const days = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ];
      dayStr = days[resetsAt.weekday - 1];
    }

    // 12-hour time format
    final hour12 = resetsAt.hour == 0
        ? 12
        : resetsAt.hour > 12
            ? resetsAt.hour - 12
            : resetsAt.hour;
    final amPm = resetsAt.hour >= 12 ? 'pm' : 'am';
    final timeStr = resetsAt.minute > 0
        ? '$hour12:${resetsAt.minute.toString().padLeft(2, '0')}$amPm'
        : '$hour12$amPm';

    // Relative duration
    final durationStr = RateLimitState.formatResetDuration(resetsAtEpoch);
    final durationPart = durationStr != null ? ' ($durationStr)' : '';

    return 'Resets $dayStr at $timeStr$durationPart';
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

    // Build the toolbar text: "Codex: Usage: 5hr 80% (reset in 3h2m), 7d 30% (reset in 3d12h)"
    final toolbarParts = <String>[];
    if (rateLimits.primary != null) {
      toolbarParts.add(_formatToolbarWindow(rateLimits.primary!));
    }
    if (rateLimits.secondary != null) {
      toolbarParts.add(_formatToolbarWindow(rateLimits.secondary!));
    }
    if (toolbarParts.isEmpty) return const SizedBox.shrink();

    // Build the tooltip
    final tooltipLines = <String>['Codex Quota Usage', ''];
    if (rateLimits.primary != null) {
      final w = rateLimits.primary!;
      final windowLabel = RateLimitState.formatWindowDuration(
          w.windowDurationMins);
      tooltipLines.add(
          'Primary${windowLabel != null ? ' ($windowLabel window)' : ''}');
      tooltipLines.add('Used: ${w.usedPercent}%');
      final resetStr = _formatTooltipReset(w.resetsAt);
      if (resetStr.isNotEmpty) tooltipLines.add(resetStr);
    }
    if (rateLimits.primary != null && rateLimits.secondary != null) {
      tooltipLines.add('');
    }
    if (rateLimits.secondary != null) {
      final w = rateLimits.secondary!;
      final windowLabel = RateLimitState.formatWindowDuration(
          w.windowDurationMins);
      tooltipLines.add(
          'Secondary${windowLabel != null ? ' ($windowLabel window)' : ''}');
      tooltipLines.add('Used: ${w.usedPercent}%');
      final resetStr = _formatTooltipReset(w.resetsAt);
      if (resetStr.isNotEmpty) tooltipLines.add(resetStr);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusBarDot(),
        Tooltip(
          message: tooltipLines.join('\n'),
          child: Text(
            'Codex: Usage: ${toolbarParts.join(", ")}',
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
