import 'package:cc_insights_v2/models/codex_pricing.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodexModelPricing', () {
    test('calculateCost computes correctly', () {
      const pricing = CodexModelPricing(
        inputPerMillion: 1.75,
        cachedInputPerMillion: 0.175,
        outputPerMillion: 14.00,
      );

      final cost = pricing.calculateCost(
        inputTokens: 1000000,
        cachedInputTokens: 0,
        outputTokens: 1000000,
      );

      // 1M * 1.75/1M + 1M * 14.00/1M = 15.75
      check(cost).equals(15.75);
    });

    test('calculateCost includes cached input tokens', () {
      const pricing = CodexModelPricing(
        inputPerMillion: 1.25,
        cachedInputPerMillion: 0.125,
        outputPerMillion: 10.00,
      );

      final cost = pricing.calculateCost(
        inputTokens: 500000,
        cachedInputTokens: 200000,
        outputTokens: 100000,
      );

      // 500k * 1.25/1M + 200k * 0.125/1M + 100k * 10.00/1M
      // = 0.625 + 0.025 + 1.0 = 1.65
      check(cost).equals(1.65);
    });

    test('calculateCost returns 0 for zero tokens', () {
      const pricing = CodexModelPricing(
        inputPerMillion: 1.75,
        cachedInputPerMillion: 0.175,
        outputPerMillion: 14.00,
      );

      final cost = pricing.calculateCost(
        inputTokens: 0,
        cachedInputTokens: 0,
        outputTokens: 0,
      );

      check(cost).equals(0.0);
    });
  });

  group('lookupCodexPricing', () {
    test('exact match returns pricing', () {
      final pricing = lookupCodexPricing('gpt-5.2');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(1.75);
      check(pricing.outputPerMillion).equals(14.00);
    });

    test('exact match is case-insensitive', () {
      final pricing = lookupCodexPricing('GPT-5.2');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(1.75);
    });

    test('codex variant matches exactly', () {
      final pricing = lookupCodexPricing('gpt-5.2-codex');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(1.75);
    });

    test('prefix fallback matches unknown variant', () {
      // "gpt-5.2-codex-preview" isn't in the table but starts with "gpt-5.2-codex"
      final pricing = lookupCodexPricing('gpt-5.2-codex-preview');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(1.75);
    });

    test('prefix fallback picks longest match', () {
      // "gpt-5.1-codex-max" is in the table; "gpt-5.1-codex-max-v2" should
      // match it (longer) rather than "gpt-5.1-codex" or "gpt-5.1".
      final pricing = lookupCodexPricing('gpt-5.1-codex-max-v2');
      check(pricing).isNotNull();
      // gpt-5.1-codex-max has 1.25 input
      check(pricing!.inputPerMillion).equals(1.25);
    });

    test('returns null for unknown model', () {
      final pricing = lookupCodexPricing('totally-unknown-model');
      check(pricing).isNull();
    });

    test('pro model pricing is correct', () {
      final pricing = lookupCodexPricing('gpt-5.2-pro');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(21.00);
      check(pricing.cachedInputPerMillion).equals(0.0);
      check(pricing.outputPerMillion).equals(168.00);
    });

    test('mini model pricing is correct', () {
      final pricing = lookupCodexPricing('gpt-5-mini');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(0.25);
      check(pricing.outputPerMillion).equals(2.00);
    });

    test('nano model pricing is correct', () {
      final pricing = lookupCodexPricing('gpt-5-nano');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(0.05);
      check(pricing.outputPerMillion).equals(0.40);
    });
  });
}
