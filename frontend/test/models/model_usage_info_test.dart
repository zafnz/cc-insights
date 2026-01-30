import 'dart:convert';

import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelUsageInfo', () {
    group('construction', () {
      test('creates instance with required fields', () {
        // Arrange & Act
        const usage = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Assert
        check(usage.modelName).equals('claude-sonnet-4-5-20250929');
        check(usage.inputTokens).equals(1000);
        check(usage.outputTokens).equals(500);
        check(usage.cacheReadTokens).equals(100);
        check(usage.cacheCreationTokens).equals(50);
        check(usage.costUsd).equals(0.05);
        check(usage.contextWindow).equals(200000);
      });
    });

    group('totalTokens', () {
      test('returns sum of input and output tokens', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.totalTokens).equals(1500);
      });

      test('returns zero when both input and output are zero', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'test-model',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.totalTokens).equals(0);
      });
    });

    group('displayName', () {
      test('extracts Sonnet 4.5 from new format model ID', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Sonnet 4.5');
      });

      test('extracts Haiku 4.5 from new format model ID', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-haiku-4-5-20251001',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Haiku 4.5');
      });

      test('extracts Opus 4.5 from new format model ID', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-opus-4-5-20251101',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Opus 4.5');
      });

      test('extracts Sonnet 3.5 from old format model ID', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-3-5-sonnet-20241022',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Sonnet 3.5');
      });

      test('extracts Haiku 3.5 from old format model ID', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-3-5-haiku-20241022',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Haiku 3.5');
      });

      test('returns original name for unknown format', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'unknown-model',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('unknown-model');
      });

      test('handles case-insensitive matching', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'CLAUDE-SONNET-4-5-20250929',
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheCreationTokens: 0,
          costUsd: 0.0,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage.displayName).equals('Sonnet 4.5');
      });
    });

    group('toJson', () {
      test('produces correct structure', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act
        final json = usage.toJson();

        // Assert
        check(json['model_name']).equals('claude-sonnet-4-5-20250929');
        check(json['input_tokens']).equals(1000);
        check(json['output_tokens']).equals(500);
        check(json['cache_read_tokens']).equals(100);
        check(json['cache_creation_tokens']).equals(50);
        check(json['cost_usd']).equals(0.05);
        check(json['context_window']).equals(200000);
      });
    });

    group('fromJson', () {
      test('restores instance correctly', () {
        // Arrange
        final json = {
          'model_name': 'claude-opus-4-5-20251101',
          'input_tokens': 2000,
          'output_tokens': 1000,
          'cache_read_tokens': 200,
          'cache_creation_tokens': 100,
          'cost_usd': 0.15,
          'context_window': 200000,
        };

        // Act
        final usage = ModelUsageInfo.fromJson(json);

        // Assert
        check(usage.modelName).equals('claude-opus-4-5-20251101');
        check(usage.inputTokens).equals(2000);
        check(usage.outputTokens).equals(1000);
        check(usage.cacheReadTokens).equals(200);
        check(usage.cacheCreationTokens).equals(100);
        check(usage.costUsd).equals(0.15);
        check(usage.contextWindow).equals(200000);
      });

      test('uses defaults for missing fields', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final usage = ModelUsageInfo.fromJson(json);

        // Assert
        check(usage.modelName).equals('');
        check(usage.inputTokens).equals(0);
        check(usage.outputTokens).equals(0);
        check(usage.cacheReadTokens).equals(0);
        check(usage.cacheCreationTokens).equals(0);
        check(usage.costUsd).equals(0.0);
        check(usage.contextWindow).equals(0);
      });
    });

    group('round-trip serialization', () {
      test('preserves all data through JSON encode/decode', () {
        // Arrange
        const original = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 12345,
          outputTokens: 6789,
          cacheReadTokens: 1000,
          cacheCreationTokens: 500,
          costUsd: 1.2345,
          contextWindow: 200000,
        );

        // Act
        final json = jsonEncode(original.toJson());
        final restored = ModelUsageInfo.fromJson(
          jsonDecode(json) as Map<String, dynamic>,
        );

        // Assert
        check(restored).equals(original);
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        const usage1 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );
        const usage2 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage1 == usage2).isTrue();
        check(usage1.hashCode).equals(usage2.hashCode);
      });

      test('equals returns false for different modelName', () {
        // Arrange
        const usage1 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );
        const usage2 = ModelUsageInfo(
          modelName: 'claude-opus-4-5-20251101',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage1 == usage2).isFalse();
      });

      test('equals returns false for different inputTokens', () {
        // Arrange
        const usage1 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );
        const usage2 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 2000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act & Assert
        check(usage1 == usage2).isFalse();
      });

      test('equals returns false for different contextWindow', () {
        // Arrange
        const usage1 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );
        const usage2 = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 100000,
        );

        // Act & Assert
        check(usage1 == usage2).isFalse();
      });
    });

    group('toString', () {
      test('produces readable output', () {
        // Arrange
        const usage = ModelUsageInfo(
          modelName: 'claude-sonnet-4-5-20250929',
          inputTokens: 1000,
          outputTokens: 500,
          cacheReadTokens: 100,
          cacheCreationTokens: 50,
          costUsd: 0.05,
          contextWindow: 200000,
        );

        // Act
        final str = usage.toString();

        // Assert
        check(str).contains('ModelUsageInfo');
        check(str).contains('claude-sonnet-4-5-20250929');
        check(str).contains('1000');
        check(str).contains('500');
      });
    });
  });
}
