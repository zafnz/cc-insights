import 'package:flutter/material.dart';

import '../models/context_tracker.dart';

/// Formats a token count into a human-readable string.
///
/// Returns:
/// - "1.2M" for values >= 1,000,000
/// - "155k" for values >= 1,000
/// - "999" for values < 1,000
String formatTokens(int tokens) {
  if (tokens >= 1000000) {
    return '${(tokens / 1000000).toStringAsFixed(1)}M';
  } else if (tokens >= 1000) {
    return '${(tokens / 1000).toStringAsFixed(1)}k';
  }
  return tokens.toString();
}

/// Displays context window usage with a progress bar and detailed tooltip.
///
/// Claude Code reserves approximately 22.5% of the context window as an
/// autocompact buffer. This means compaction triggers when usage reaches
/// approximately 77.5% of total context.
///
/// Color coding based on effective usage (relative to autocompact threshold):
/// - Green: < 75% of autocompact threshold
/// - Amber: 75-90% of autocompact threshold
/// - Orange: 90-100% of autocompact threshold
/// - Red: >= autocompact threshold
class ContextIndicator extends StatelessWidget {
  /// The context tracker to display usage for.
  final ContextTracker tracker;

  /// Autocompact buffer percentage (Claude Code reserves this for compaction).
  static const double autocompactBufferPercent = 22.5;

  /// Threshold at which autocompact triggers (~77.5%).
  static const double autocompactThreshold =
      100.0 - autocompactBufferPercent;

  /// Creates a context indicator widget.
  const ContextIndicator({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final currentTokens = tracker.currentTokens;
    final maxTokens = tracker.maxTokens;
    final percent = tracker.percentUsed;

    // Calculate effective usage (how close to autocompact threshold)
    final effectivePercent = (percent / autocompactThreshold) * 100;

    // Calculate remaining space before autocompact
    final autocompactBuffer =
        (maxTokens * autocompactBufferPercent / 100).round();
    final remainingTokens = maxTokens - currentTokens;
    final freeSpace = remainingTokens - autocompactBuffer;
    final freeSpaceStr = freeSpace >= 0
        ? formatTokens(freeSpace)
        : '-${formatTokens(freeSpace.abs())}';

    // Color based on effective usage (relative to autocompact threshold)
    final (barColor, showWarning) = _getColorAndWarning(
      percent: percent,
      effectivePercent: effectivePercent,
    );

    // Calculate percentages for tooltip
    final freeSpacePercent =
        maxTokens > 0 ? (freeSpace / maxTokens) * 100 : 0.0;

    return Tooltip(
      richMessage: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          const TextSpan(
            text: 'Context Window\n\n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: 'Current: ${formatTokens(currentTokens)} '
                '(${percent.toStringAsFixed(1)}%)\n',
          ),
          TextSpan(
            text: 'Free Space: $freeSpaceStr '
                '(${freeSpacePercent.toStringAsFixed(1)}%)\n',
          ),
          TextSpan(
            text: 'Autocompact: ${formatTokens(autocompactBuffer)} '
                '(${autocompactBufferPercent.toStringAsFixed(1)}%)\n',
          ),
          TextSpan(text: 'Max Context: ${formatTokens(maxTokens)}'),
          if (percent >= autocompactThreshold * 0.9)
            const TextSpan(text: '\n\nApproaching autocompact threshold'),
        ],
      ),
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
              showWarning ? Icons.warning_amber_rounded : Icons.memory,
              size: 14,
              color: showWarning ? barColor : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Text(
              '${formatTokens(currentTokens)} / ${formatTokens(maxTokens)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(width: 8),
            // Progress bar showing actual usage
            SizedBox(
              width: 40,
              height: 4,
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                color: showWarning ? barColor : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the bar color and whether to show a warning indicator.
  (Color, bool) _getColorAndWarning({
    required double percent,
    required double effectivePercent,
  }) {
    if (percent >= autocompactThreshold) {
      return (Colors.red, true);
    } else if (effectivePercent > 90) {
      return (Colors.orange, true);
    } else if (effectivePercent > 75) {
      return (Colors.amber, false);
    } else {
      return (Colors.green, false);
    }
  }
}
