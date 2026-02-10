import 'package:flutter/material.dart';

import '../models/output_entry.dart';
import '../models/timing_stats.dart';

/// Displays cumulative token usage and cost with a detailed tooltip.
///
/// Shows a compact display with total tokens and cost in USD. On hover,
/// displays a rich tooltip with breakdown by input/output tokens, cache
/// usage, and optionally per-model usage statistics.
class CostIndicator extends StatelessWidget {
  /// The aggregated usage information to display.
  final UsageInfo usage;

  /// Display label for the current agent (e.g. Claude, Codex).
  final String agentLabel;

  /// Per-model usage breakdown for the tooltip.
  ///
  /// When provided and non-empty, the tooltip will include a section
  /// showing usage statistics for each model used in the conversation.
  final List<ModelUsageInfo> modelUsage;

  /// Timing statistics for the tooltip.
  ///
  /// When provided and non-zero, the tooltip will include a section
  /// showing how long the agent worked and how long the user took to respond.
  final TimingStats? timingStats;

  /// Whether to display cost values in the compact view and tooltip.
  ///
  /// Set to false when the backend doesn't provide cost data.
  final bool showCost;

  /// Creates a [CostIndicator] widget.
  const CostIndicator({
    super.key,
    required this.usage,
    required this.agentLabel,
    this.modelUsage = const [],
    this.timingStats,
    this.showCost = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: _buildTooltipContent(context),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      preferBelow: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.token,
              size: 14,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              _formatTokenCount(usage.totalTokens),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (showCost) ...[
              const SizedBox(width: 8),
              Text(
                '\$${_formatCost(usage.costUsd)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds the rich tooltip content with usage details.
  TextSpan _buildTooltipContent(BuildContext context) {
    final children = <InlineSpan>[
      const TextSpan(
        text: 'Usage Details\n\n',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: 'Input tokens: ${_formatNumber(usage.inputTokens)}\n'),
      TextSpan(text: 'Output tokens: ${_formatNumber(usage.outputTokens)}\n'),
      TextSpan(text: 'Cache read: ${_formatNumber(usage.cacheReadTokens)}\n'),
      TextSpan(
        text: 'Cache creation: ${_formatNumber(usage.cacheCreationTokens)}\n',
      ),
    ];

    if (showCost) {
      children.add(TextSpan(
        text: '\nTotal cost: \$${_formatCost(usage.costUsd)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
    }

    // Add per-model breakdown if available
    if (modelUsage.isNotEmpty) {
      children.add(const TextSpan(text: '\n\n────────────────────\n'));

      for (final model in modelUsage) {
        children.add(TextSpan(
          text: '\n${model.displayName}\n',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
        children.add(TextSpan(
          text: 'Input/Output: ${_formatNumber(model.inputTokens)} / '
              '${_formatNumber(model.outputTokens)}\n',
        ));
        children.add(TextSpan(
          text: 'Cache: ${_formatNumber(model.cacheReadTokens)} read, '
              '${_formatNumber(model.cacheCreationTokens)} created\n',
        ));
        if (showCost) {
          children.add(TextSpan(
            text: 'Cost: \$${_formatCost(model.costUsd)}\n',
          ));
        }
      }
    }

    // Add timing statistics if available
    final timing = timingStats;
    if (timing != null &&
        (timing.claudeWorkingMs > 0 || timing.userResponseMs > 0)) {
      children.add(const TextSpan(text: '\n────────────────────\n'));
      children.add(const TextSpan(
        text: '\nTime\n',
        style: TextStyle(fontWeight: FontWeight.bold),
      ));
      children.add(TextSpan(
        text: '$agentLabel worked: '
            '${TimingStats.formatDuration(timing.claudeWorkingDuration)}'
            ' (${timing.claudeWorkCount}x)\n',
      ));
      children.add(TextSpan(
        text: '$agentLabel waited for you: '
            '${TimingStats.formatDuration(timing.userResponseDuration)}'
            ' (${timing.userResponseCount}x)\n',
      ));
      children.add(TextSpan(
        text: '(includes wait time)',
        style: TextStyle(
          fontSize: 10,
          color: Colors.grey[400],
          fontStyle: FontStyle.italic,
        ),
      ));
    }

    return TextSpan(
      style: const TextStyle(fontSize: 12),
      children: children,
    );
  }

  /// Formats a token count with k/M suffixes for large numbers.
  ///
  /// Examples:
  /// - 1234 -> "1.2k"
  /// - 1234567 -> "1.2M"
  /// - 999 -> "999"
  String _formatTokenCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}k';
    }
    return count.toString();
  }

  /// Formats a number with commas for thousands separator.
  String _formatNumber(int value) {
    if (value < 1000) return value.toString();

    final str = value.toString();
    final buffer = StringBuffer();
    final length = str.length;

    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }

    return buffer.toString();
  }

  /// Formats a USD cost with appropriate precision.
  ///
  /// Shows 2 decimal places for costs >= $0.01, otherwise 4 decimal places.
  String _formatCost(double cost) {
    if (cost >= 0.01 || cost == 0) {
      return cost.toStringAsFixed(2);
    }
    return cost.toStringAsFixed(4);
  }
}
