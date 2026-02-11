import 'package:cc_insights_v2/models/cost_tracking.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/timing_stats.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CostTrackingEntry', () {
    group('backend field', () {
      test('defaults to claude in constructor', () {
        // Arrange & Act
        const entry = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
        );

        // Assert
        check(entry.backend).equals('claude');
      });

      test('can be set to codex in constructor', () {
        // Arrange & Act
        const entry = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
          backend: 'codex',
        );

        // Assert
        check(entry.backend).equals('codex');
      });
    });

    group('toJson', () {
      test('includes backend field', () {
        // Arrange
        const entry = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
          backend: 'codex',
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['backend']).equals('codex');
      });

      test('includes claude backend when default', () {
        // Arrange
        const entry = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
        );

        // Act
        final json = entry.toJson();

        // Assert
        check(json['backend']).equals('claude');
      });
    });

    group('fromJson', () {
      test('reads backend field', () {
        // Arrange
        final json = {
          'worktree': 'main',
          'chatName': 'Test Chat',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'modelUsage': [],
          'timing': {
            'totalClaudeWorkingTime': 0,
            'totalUserResponseTime': 0,
            'claudeWorkCount': 0,
            'userResponseCount': 0,
          },
          'backend': 'codex',
        };

        // Act
        final entry = CostTrackingEntry.fromJson(json);

        // Assert
        check(entry.backend).equals('codex');
      });

      test('defaults to claude when backend field missing', () {
        // Arrange - old format without backend field
        final json = {
          'worktree': 'main',
          'chatName': 'Test Chat',
          'timestamp': '2026-01-01T00:00:00.000Z',
          'modelUsage': [],
          'timing': {
            'totalClaudeWorkingTime': 0,
            'totalUserResponseTime': 0,
            'claudeWorkCount': 0,
            'userResponseCount': 0,
          },
        };

        // Act
        final entry = CostTrackingEntry.fromJson(json);

        // Assert
        check(entry.backend).equals('claude');
      });
    });

    group('fromChat factory', () {
      test('accepts and uses backend parameter', () {
        // Arrange
        const modelUsage = [
          ModelUsageInfo(
            modelName: 'gpt-4',
            inputTokens: 100,
            outputTokens: 50,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            costUsd: 0.0,
            contextWindow: 8192,
          ),
        ];

        // Act
        final entry = CostTrackingEntry.fromChat(
          worktreeName: 'main',
          chatName: 'Test Chat',
          modelUsage: modelUsage,
          backend: 'codex',
        );

        // Assert
        check(entry.backend).equals('codex');
        check(entry.worktree).equals('main');
        check(entry.chatName).equals('Test Chat');
        check(entry.modelUsage).equals(modelUsage);
      });

      test('uses claude backend when specified', () {
        // Arrange & Act
        final entry = CostTrackingEntry.fromChat(
          worktreeName: 'main',
          chatName: 'Test Chat',
          modelUsage: [],
          backend: 'claude',
        );

        // Assert
        check(entry.backend).equals('claude');
      });
    });

    group('equality', () {
      test('includes backend field', () {
        // Arrange
        const entry1 = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
          backend: 'claude',
        );
        const entry2 = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
          backend: 'claude',
        );
        const entry3 = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [],
          backend: 'codex',
        );

        // Act & Assert
        check(entry1).equals(entry2);
        check(entry1).not((it) => it.equals(entry3));
      });
    });

    group('round-trip serialization', () {
      test('preserves backend for claude', () {
        // Arrange
        const original = CostTrackingEntry(
          worktree: 'main',
          chatName: 'Test Chat',
          timestamp: '2026-01-01T00:00:00.000Z',
          modelUsage: [
            ModelUsageInfo(
              modelName: 'claude-opus-4',
              inputTokens: 1000,
              outputTokens: 500,
              cacheReadTokens: 100,
              cacheCreationTokens: 50,
              costUsd: 0.05,
              contextWindow: 200000,
            ),
          ],
          backend: 'claude',
        );

        // Act
        final json = original.toJson();
        final restored = CostTrackingEntry.fromJson(json);

        // Assert
        check(restored).equals(original);
        check(restored.backend).equals('claude');
      });

      test('preserves backend for codex', () {
        // Arrange
        const original = CostTrackingEntry(
          worktree: 'feature',
          chatName: 'Codex Chat',
          timestamp: '2026-01-01T12:00:00.000Z',
          modelUsage: [
            ModelUsageInfo(
              modelName: 'gpt-4',
              inputTokens: 2000,
              outputTokens: 1000,
              cacheReadTokens: 0,
              cacheCreationTokens: 0,
              costUsd: 0.0,
              contextWindow: 8192,
            ),
          ],
          timing: TimingStats(
            claudeWorkingMs: 5000,
            userResponseMs: 2000,
            claudeWorkCount: 3,
            userResponseCount: 2,
          ),
          backend: 'codex',
        );

        // Act
        final json = original.toJson();
        final restored = CostTrackingEntry.fromJson(json);

        // Assert
        check(restored).equals(original);
        check(restored.backend).equals('codex');
      });
    });
  });
}
