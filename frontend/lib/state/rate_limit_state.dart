import 'package:agent_sdk_core/agent_sdk_core.dart'
    show RateLimitUpdateEvent, RateLimitWindow, RateLimitCredits;
import 'package:flutter/foundation.dart';

/// Holds the latest rate limit information from the Codex backend.
///
/// Updated by [EventHandler] when a [RateLimitUpdateEvent] arrives.
/// Widgets watch this via Provider to display rate limit status.
class RateLimitState extends ChangeNotifier {
  RateLimitWindow? _primary;
  RateLimitWindow? _secondary;
  RateLimitCredits? _credits;
  String? _planType;
  DateTime? _lastUpdated;

  RateLimitWindow? get primary => _primary;
  RateLimitWindow? get secondary => _secondary;
  RateLimitCredits? get credits => _credits;
  String? get planType => _planType;
  DateTime? get lastUpdated => _lastUpdated;

  /// Whether we have any rate limit data to display.
  bool get hasData => _primary != null || _secondary != null;

  /// Updates the state from a [RateLimitUpdateEvent].
  void update(RateLimitUpdateEvent event) {
    _primary = event.primary;
    _secondary = event.secondary;
    _credits = event.credits;
    _planType = event.planType;
    _lastUpdated = event.timestamp;
    notifyListeners();
  }

  /// Formats a rate limit window for display.
  ///
  /// Returns something like "5hr 4% (resets in 2h35m)" or "7d 43% (resets in 3d12h)".
  static String formatWindow(RateLimitWindow window) {
    final windowLabel = formatWindowDuration(window.windowDurationMins);
    final resetLabel = formatResetDuration(window.resetsAt);
    final parts = <String>[
      if (windowLabel != null) windowLabel,
      '${window.usedPercent}%',
      if (resetLabel != null) '(resets in $resetLabel)',
    ];
    return parts.join(' ');
  }

  /// Formats window duration in minutes to a human-readable label.
  static String? formatWindowDuration(int? mins) {
    if (mins == null) return null;
    if (mins < 60) return '${mins}m';
    if (mins < 1440) {
      final hours = mins ~/ 60;
      return '${hours}hr';
    }
    final days = mins ~/ 1440;
    return '${days}d';
  }

  /// Formats a Unix epoch reset timestamp to a relative duration string.
  static String? formatResetDuration(int? resetsAtEpoch) {
    if (resetsAtEpoch == null) return null;
    final resetsAt =
        DateTime.fromMillisecondsSinceEpoch(resetsAtEpoch * 1000, isUtc: true);
    final now = DateTime.now().toUtc();
    final diff = resetsAt.difference(now);
    if (diff.isNegative) return null;

    final totalMinutes = diff.inMinutes;
    if (totalMinutes < 60) {
      return '${totalMinutes}m';
    }
    if (totalMinutes < 1440) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return mins > 0 ? '${hours}h${mins}m' : '${hours}h';
    }
    final days = totalMinutes ~/ 1440;
    final hours = (totalMinutes % 1440) ~/ 60;
    return hours > 0 ? '${days}d${hours}h' : '${days}d';
  }
}
