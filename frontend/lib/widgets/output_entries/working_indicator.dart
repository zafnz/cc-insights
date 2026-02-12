import 'dart:async';

import 'package:flutter/material.dart';

/// Test keys for the working indicator.
class WorkingIndicatorKeys {
  WorkingIndicatorKeys._();

  /// The root container of the working indicator.
  static const container = Key('working_indicator_container');

  /// The progress indicator spinner.
  static const spinner = Key('working_indicator_spinner');

  /// The text label.
  static const label = Key('working_indicator_label');

  /// The elapsed time label.
  static const elapsed = Key('working_indicator_elapsed');
}

/// Indicator shown when Claude is working (thinking/processing).
///
/// Displays a circular progress indicator with status text and an
/// elapsed time counter that ticks every second.
/// When [isCompacting] is true, shows "Compacting context..." instead of
/// the default "Claude is working..." message.
///
/// If [stopwatch] is provided, the elapsed time is read from it.
/// The stopwatch uses monotonic clock time, so system sleep/suspend
/// is not counted as working time.
class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({
    super.key,
    this.agentName = 'Claude',
    this.isCompacting = false,
    this.stopwatch,
  });

  /// The name of the agent (e.g. "Claude" or "Codex").
  final String agentName;

  /// Whether context compaction is in progress.
  ///
  /// When true, shows "Compacting context..." instead of
  /// `<Agent> is working...` message.
  final bool isCompacting;

  /// Stopwatch tracking active working time.
  ///
  /// Uses monotonic clock so elapsed time excludes system sleep/suspend.
  /// If null, elapsed time shows as zero.
  final Stopwatch? stopwatch;

  @override
  State<WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<WorkingIndicator> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Update every second to show elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Returns the elapsed duration from the stopwatch.
  ///
  /// Uses the stopwatch's monotonic clock, which does not advance
  /// during system sleep/suspend.
  Duration get _elapsed {
    return widget.stopwatch?.elapsed ?? Duration.zero;
  }

  /// Formats elapsed duration as "Xs", "Xm", "XmYs".
  String _formatElapsed(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds < 60) {
      return '${totalSeconds}s';
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return '${minutes}m';
    }
    return '${minutes}m${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusText =
        widget.isCompacting
            ? 'Compacting context...'
            : '${widget.agentName} is working...';
    final elapsed = _formatElapsed(_elapsed);

    return Padding(
      key: WorkingIndicatorKeys.container,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            key: WorkingIndicatorKeys.spinner,
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            statusText,
            key: WorkingIndicatorKeys.label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            elapsed,
            key: WorkingIndicatorKeys.elapsed,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[500],
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
