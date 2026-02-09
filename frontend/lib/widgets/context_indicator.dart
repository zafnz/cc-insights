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
/// When the tracker has an [ContextTracker.autocompactBufferPercent] set
/// (e.g., 22.5% for Claude), color thresholds are relative to the
/// autocompact trigger point and the tooltip shows buffer details.
///
/// When the buffer is null (e.g., Codex), simpler thresholds against
/// raw usage percentage are used and autocompact info is omitted.
class ContextIndicator extends StatelessWidget {
  /// The context tracker to display usage for.
  final ContextTracker tracker;

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
    final bufferPercent = tracker.autocompactBufferPercent;

    // Calculate values based on whether we know the autocompact buffer.
    final double effectivePercent;
    final double? autocompactThreshold;
    final int? autocompactBuffer;

    if (bufferPercent != null) {
      autocompactThreshold = 100.0 - bufferPercent;
      effectivePercent = (percent / autocompactThreshold) * 100;
      autocompactBuffer = (maxTokens * bufferPercent / 100).round();
    } else {
      autocompactThreshold = null;
      effectivePercent = percent;
      autocompactBuffer = null;
    }

    // Free space: remaining before autocompact (if known), else total remaining.
    final remainingTokens = maxTokens - currentTokens;
    final freeSpace = autocompactBuffer != null
        ? remainingTokens - autocompactBuffer
        : remainingTokens;
    final freeSpaceStr = freeSpace >= 0
        ? formatTokens(freeSpace)
        : '-${formatTokens(freeSpace.abs())}';

    final (barColor, showWarning) = _getColorAndWarning(
      percent: percent,
      effectivePercent: effectivePercent,
      autocompactThreshold: autocompactThreshold,
    );

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
          if (autocompactBuffer != null)
            TextSpan(
              text: 'Autocompact: ${formatTokens(autocompactBuffer)} '
                  '(${bufferPercent!.toStringAsFixed(1)}%)\n',
            ),
          TextSpan(text: 'Max Context: ${formatTokens(maxTokens)}'),
          if (autocompactThreshold != null &&
              percent >= autocompactThreshold * 0.9)
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
  ///
  /// When [autocompactThreshold] is set, colors are relative to that threshold.
  /// When null, simpler thresholds against raw [percent] are used.
  (Color, bool) _getColorAndWarning({
    required double percent,
    required double effectivePercent,
    required double? autocompactThreshold,
  }) {
    if (autocompactThreshold != null) {
      // Claude-style: color relative to autocompact threshold
      if (percent >= autocompactThreshold) {
        return (Colors.red, true);
      } else if (effectivePercent > 90) {
        return (Colors.orange, true);
      } else if (effectivePercent > 75) {
        return (Colors.amber, false);
      } else {
        return (Colors.green, false);
      }
    } else {
      // No known autocompact: simpler thresholds against raw usage
      if (percent >= 90) {
        return (Colors.red, true);
      } else if (percent >= 75) {
        return (Colors.orange, true);
      } else if (percent >= 60) {
        return (Colors.amber, false);
      } else {
        return (Colors.green, false);
      }
    }
  }
}
