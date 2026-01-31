import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../services/agent_service.dart';

/// Status bar showing backend connection status and statistics.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();

    // Try to get AgentService if available
    final agentService = context.watch<AgentService?>();
    final isConnected = agentService?.isConnected ?? false;
    final agentName = agentService?.currentAgent?.name;

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

    // Determine connection status color and text
    final statusColor = isConnected ? Colors.green : Colors.grey;
    final statusText = isConnected
        ? (agentName ?? 'Connected')
        : 'Not connected';

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
          // ACP agent connection status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Stats on the right
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
