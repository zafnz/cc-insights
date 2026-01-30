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
}

/// Indicator shown when Claude is working (thinking/processing).
///
/// Displays a circular progress indicator with status text.
/// When [isCompacting] is true, shows "Compacting context..." instead of
/// the default "Claude is working..." message.
class WorkingIndicator extends StatelessWidget {
  const WorkingIndicator({
    super.key,
    this.isCompacting = false,
  });

  /// Whether context compaction is in progress.
  ///
  /// When true, shows "Compacting context..." instead of "Claude is working..."
  final bool isCompacting;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusText = isCompacting ? 'Compacting context...' : 'Claude is working...';

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
        ],
      ),
    );
  }
}
