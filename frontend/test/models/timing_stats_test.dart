import 'package:cc_insights_v2/models/timing_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimingStats', () {
    test('zero constructor creates empty stats', () {
      const stats = TimingStats.zero();
      expect(stats.claudeWorkingMs, 0);
      expect(stats.userResponseMs, 0);
      expect(stats.claudeWorkCount, 0);
      expect(stats.userResponseCount, 0);
    });

    test('duration getters return correct values', () {
      const stats = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      expect(stats.claudeWorkingDuration, const Duration(milliseconds: 5000));
      expect(stats.userResponseDuration, const Duration(milliseconds: 3000));
    });

    test('average calculations work correctly', () {
      const stats = TimingStats(
        claudeWorkingMs: 6000,
        userResponseMs: 4000,
        claudeWorkCount: 3,
        userResponseCount: 2,
      );

      expect(
        stats.averageClaudeWorkingTime,
        const Duration(milliseconds: 2000),
      );
      expect(
        stats.averageUserResponseTime,
        const Duration(milliseconds: 2000),
      );
    });

    test('average returns zero when count is zero', () {
      const stats = TimingStats.zero();

      expect(stats.averageClaudeWorkingTime, Duration.zero);
      expect(stats.averageUserResponseTime, Duration.zero);
    });

    test('addClaudeWorkingTime accumulates correctly', () {
      const stats = TimingStats.zero();

      final updated = stats.addClaudeWorkingTime(const Duration(seconds: 5));

      expect(updated.claudeWorkingMs, 5000);
      expect(updated.claudeWorkCount, 1);
      // Other fields unchanged
      expect(updated.userResponseMs, 0);
      expect(updated.userResponseCount, 0);
    });

    test('addUserResponseTime accumulates correctly', () {
      const stats = TimingStats.zero();

      final updated = stats.addUserResponseTime(const Duration(seconds: 10));

      expect(updated.userResponseMs, 10000);
      expect(updated.userResponseCount, 1);
      // Other fields unchanged
      expect(updated.claudeWorkingMs, 0);
      expect(updated.claudeWorkCount, 0);
    });

    test('multiple additions accumulate', () {
      var stats = const TimingStats.zero();

      stats = stats.addClaudeWorkingTime(const Duration(seconds: 5));
      stats = stats.addClaudeWorkingTime(const Duration(seconds: 3));
      stats = stats.addUserResponseTime(const Duration(seconds: 2));

      expect(stats.claudeWorkingMs, 8000);
      expect(stats.claudeWorkCount, 2);
      expect(stats.userResponseMs, 2000);
      expect(stats.userResponseCount, 1);
    });

    test('merge combines two stats correctly', () {
      const stats1 = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      const stats2 = TimingStats(
        claudeWorkingMs: 2000,
        userResponseMs: 1000,
        claudeWorkCount: 1,
        userResponseCount: 2,
      );

      final merged = stats1.merge(stats2);

      expect(merged.claudeWorkingMs, 7000);
      expect(merged.userResponseMs, 4000);
      expect(merged.claudeWorkCount, 3);
      expect(merged.userResponseCount, 3);
    });

    test('copyWith creates modified copy', () {
      const original = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      final modified = original.copyWith(claudeWorkingMs: 10000);

      expect(modified.claudeWorkingMs, 10000);
      expect(modified.userResponseMs, 3000); // unchanged
      expect(modified.claudeWorkCount, 2); // unchanged
      expect(modified.userResponseCount, 1); // unchanged
    });

    test('toJson serializes correctly', () {
      const stats = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      final json = stats.toJson();

      expect(json['claudeWorkingMs'], 5000);
      expect(json['userResponseMs'], 3000);
      expect(json['claudeWorkCount'], 2);
      expect(json['userResponseCount'], 1);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'claudeWorkingMs': 5000,
        'userResponseMs': 3000,
        'claudeWorkCount': 2,
        'userResponseCount': 1,
      };

      final stats = TimingStats.fromJson(json);

      expect(stats.claudeWorkingMs, 5000);
      expect(stats.userResponseMs, 3000);
      expect(stats.claudeWorkCount, 2);
      expect(stats.userResponseCount, 1);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final stats = TimingStats.fromJson(json);

      expect(stats.claudeWorkingMs, 0);
      expect(stats.userResponseMs, 0);
      expect(stats.claudeWorkCount, 0);
      expect(stats.userResponseCount, 0);
    });

    test('equality works correctly', () {
      const stats1 = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      const stats2 = TimingStats(
        claudeWorkingMs: 5000,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      const stats3 = TimingStats(
        claudeWorkingMs: 5001,
        userResponseMs: 3000,
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      expect(stats1, equals(stats2));
      expect(stats1, isNot(equals(stats3)));
    });

    test('formatDuration formats correctly', () {
      // Hours
      expect(
        TimingStats.formatDuration(const Duration(hours: 2, minutes: 30)),
        '2h 30m',
      );

      // Minutes
      expect(
        TimingStats.formatDuration(const Duration(minutes: 5, seconds: 30)),
        '5m 30s',
      );

      // Seconds
      expect(
        TimingStats.formatDuration(const Duration(seconds: 3, milliseconds: 500)),
        '3.5s',
      );

      // Milliseconds
      expect(
        TimingStats.formatDuration(const Duration(milliseconds: 750)),
        '750ms',
      );
    });

    test('toString provides readable output', () {
      const stats = TimingStats(
        claudeWorkingMs: 65000, // 1m 5s
        userResponseMs: 3500, // 3.5s
        claudeWorkCount: 2,
        userResponseCount: 1,
      );

      final str = stats.toString();

      expect(str, contains('claudeWorking:'));
      expect(str, contains('userResponse:'));
      expect(str, contains('claudeWorkCount: 2'));
      expect(str, contains('userResponseCount: 1'));
    });
  });
}
