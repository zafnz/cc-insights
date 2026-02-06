import 'package:flutter/foundation.dart';

/// Timing statistics for a chat session.
///
/// Tracks two categories of time:
/// 1. Claude working time - time spent when Claude is processing/generating
/// 2. User response time - time from when a prompt (permission/question) appears
///    until the user responds
///
/// All durations are stored in milliseconds for precision.
@immutable
class TimingStats {
  /// Total time (in milliseconds) that Claude has spent working.
  ///
  /// Accumulated each time Claude finishes processing a request.
  final int claudeWorkingMs;

  /// Total time (in milliseconds) that the user took to respond to prompts.
  ///
  /// Accumulated each time a permission request or question is answered.
  final int userResponseMs;

  /// Number of times Claude completed a work cycle.
  ///
  /// Used to calculate average working time if needed.
  final int claudeWorkCount;

  /// Number of times the user responded to a prompt.
  ///
  /// Used to calculate average response time if needed.
  final int userResponseCount;

  /// Creates a [TimingStats] instance.
  const TimingStats({
    this.claudeWorkingMs = 0,
    this.userResponseMs = 0,
    this.claudeWorkCount = 0,
    this.userResponseCount = 0,
  });

  /// Creates an empty [TimingStats] with zero values.
  const TimingStats.zero()
      : claudeWorkingMs = 0,
        userResponseMs = 0,
        claudeWorkCount = 0,
        userResponseCount = 0;

  /// Total Claude working time as a [Duration].
  Duration get claudeWorkingDuration =>
      Duration(milliseconds: claudeWorkingMs);

  /// Total user response time as a [Duration].
  Duration get userResponseDuration =>
      Duration(milliseconds: userResponseMs);

  /// Average Claude working time per work cycle.
  ///
  /// Returns [Duration.zero] if no work cycles have been recorded.
  Duration get averageClaudeWorkingTime {
    if (claudeWorkCount == 0) return Duration.zero;
    return Duration(milliseconds: claudeWorkingMs ~/ claudeWorkCount);
  }

  /// Average user response time per prompt.
  ///
  /// Returns [Duration.zero] if no responses have been recorded.
  Duration get averageUserResponseTime {
    if (userResponseCount == 0) return Duration.zero;
    return Duration(milliseconds: userResponseMs ~/ userResponseCount);
  }

  /// Adds Claude working time to the stats.
  TimingStats addClaudeWorkingTime(Duration duration) {
    return TimingStats(
      claudeWorkingMs: claudeWorkingMs + duration.inMilliseconds,
      userResponseMs: userResponseMs,
      claudeWorkCount: claudeWorkCount + 1,
      userResponseCount: userResponseCount,
    );
  }

  /// Adds user response time to the stats.
  TimingStats addUserResponseTime(Duration duration) {
    return TimingStats(
      claudeWorkingMs: claudeWorkingMs,
      userResponseMs: userResponseMs + duration.inMilliseconds,
      claudeWorkCount: claudeWorkCount,
      userResponseCount: userResponseCount + 1,
    );
  }

  /// Merges another [TimingStats] into this one.
  TimingStats merge(TimingStats other) {
    return TimingStats(
      claudeWorkingMs: claudeWorkingMs + other.claudeWorkingMs,
      userResponseMs: userResponseMs + other.userResponseMs,
      claudeWorkCount: claudeWorkCount + other.claudeWorkCount,
      userResponseCount: userResponseCount + other.userResponseCount,
    );
  }

  /// Creates a copy with the given fields replaced.
  TimingStats copyWith({
    int? claudeWorkingMs,
    int? userResponseMs,
    int? claudeWorkCount,
    int? userResponseCount,
  }) {
    return TimingStats(
      claudeWorkingMs: claudeWorkingMs ?? this.claudeWorkingMs,
      userResponseMs: userResponseMs ?? this.userResponseMs,
      claudeWorkCount: claudeWorkCount ?? this.claudeWorkCount,
      userResponseCount: userResponseCount ?? this.userResponseCount,
    );
  }

  /// Serializes this [TimingStats] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'claudeWorkingMs': claudeWorkingMs,
      'userResponseMs': userResponseMs,
      'claudeWorkCount': claudeWorkCount,
      'userResponseCount': userResponseCount,
    };
  }

  /// Deserializes a [TimingStats] from a JSON map.
  factory TimingStats.fromJson(Map<String, dynamic> json) {
    return TimingStats(
      claudeWorkingMs: json['claudeWorkingMs'] as int? ?? 0,
      userResponseMs: json['userResponseMs'] as int? ?? 0,
      claudeWorkCount: json['claudeWorkCount'] as int? ?? 0,
      userResponseCount: json['userResponseCount'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimingStats &&
        other.claudeWorkingMs == claudeWorkingMs &&
        other.userResponseMs == userResponseMs &&
        other.claudeWorkCount == claudeWorkCount &&
        other.userResponseCount == userResponseCount;
  }

  @override
  int get hashCode => Object.hash(
        claudeWorkingMs,
        userResponseMs,
        claudeWorkCount,
        userResponseCount,
      );

  @override
  String toString() {
    return 'TimingStats('
        'claudeWorking: ${_formatDuration(claudeWorkingDuration)}, '
        'userResponse: ${_formatDuration(userResponseDuration)}, '
        'claudeWorkCount: $claudeWorkCount, '
        'userResponseCount: $userResponseCount)';
  }

  /// Formats a duration as human-readable string.
  static String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    } else if (d.inSeconds > 0) {
      return '${d.inSeconds}.${(d.inMilliseconds.remainder(1000) ~/ 100)}s';
    } else {
      return '${d.inMilliseconds}ms';
    }
  }

  /// Formats a duration for display (static helper for external use).
  static String formatDuration(Duration d) => _formatDuration(d);
}
