import 'package:cc_insights_v2/models/codex_pricing.dart';
import 'package:cc_insights_v2/services/codex_pricing_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodexPricingService', () {
    setUp(() {
      CodexPricingService.instance.reset();
    });

    tearDown(() {
      CodexPricingService.instance.reset();
    });

    test('hasDynamicPricing is false when empty', () {
      check(CodexPricingService.instance.hasDynamicPricing).isFalse();
    });

    test('loadFromJson parses valid pricing JSON', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "test-model": { "input": 2.0, "cachedInput": 0.5, "output": 8.0 }
          }
        }
      ''');

      check(CodexPricingService.instance.hasDynamicPricing).isTrue();
      final pricing = CodexPricingService.instance.lookup('test-model');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(2.0);
      check(pricing.cachedInputPerMillion).equals(0.5);
      check(pricing.outputPerMillion).equals(8.0);
    });

    test('loadFromJson handles missing cachedInput', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "no-cache": { "input": 1.0, "output": 4.0 }
          }
        }
      ''');

      final pricing = CodexPricingService.instance.lookup('no-cache');
      check(pricing).isNotNull();
      check(pricing!.cachedInputPerMillion).equals(0.0);
    });

    test('loadFromJson skips entries missing required fields', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "valid": { "input": 1.0, "output": 4.0 },
            "missing-output": { "input": 1.0 },
            "missing-input": { "output": 4.0 }
          }
        }
      ''');

      check(CodexPricingService.instance.lookup('valid')).isNotNull();
      check(CodexPricingService.instance.lookup('missing-output')).isNull();
      check(CodexPricingService.instance.lookup('missing-input')).isNull();
    });

    test('loadFromJson handles malformed JSON gracefully', () {
      CodexPricingService.instance.loadFromJson('not valid json');
      check(CodexPricingService.instance.hasDynamicPricing).isFalse();
    });

    test('loadFromJson handles missing models key', () {
      CodexPricingService.instance.loadFromJson('{"description": "test"}');
      check(CodexPricingService.instance.hasDynamicPricing).isFalse();
    });

    test('lookup is case-insensitive', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "GPT-Test": { "input": 1.0, "cachedInput": 0.1, "output": 4.0 }
          }
        }
      ''');

      check(CodexPricingService.instance.lookup('gpt-test')).isNotNull();
      check(CodexPricingService.instance.lookup('GPT-TEST')).isNotNull();
    });

    test('reset clears dynamic pricing', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "test": { "input": 1.0, "cachedInput": 0.1, "output": 4.0 }
          }
        }
      ''');

      check(CodexPricingService.instance.hasDynamicPricing).isTrue();
      CodexPricingService.instance.reset();
      check(CodexPricingService.instance.hasDynamicPricing).isFalse();
    });

    test('loadFromJson parses multiple models', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "model-a": { "input": 1.0, "cachedInput": 0.1, "output": 4.0 },
            "model-b": { "input": 2.0, "cachedInput": 0.2, "output": 8.0 },
            "model-c": { "input": 3.0, "cachedInput": 0.3, "output": 12.0 }
          }
        }
      ''');

      check(CodexPricingService.instance.entries.length).equals(3);
    });
  });

  group('lookupCodexPricing with dynamic pricing', () {
    setUp(() {
      CodexPricingService.instance.reset();
    });

    tearDown(() {
      CodexPricingService.instance.reset();
    });

    test('prefers dynamic pricing over hardcoded', () {
      // gpt-5.2 is in the hardcoded table at 1.75 input
      // Load dynamic pricing with different price
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "gpt-5.2": { "input": 99.0, "cachedInput": 0.5, "output": 99.0 }
          }
        }
      ''');

      final pricing = lookupCodexPricing('gpt-5.2');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(99.0);
    });

    test('falls back to hardcoded when model not in dynamic pricing', () {
      // Load dynamic pricing with only one model
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "some-other-model": { "input": 1.0, "cachedInput": 0.1, "output": 4.0 }
          }
        }
      ''');

      // gpt-5-nano is only in hardcoded table
      final pricing = lookupCodexPricing('gpt-5-nano');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(0.05);
    });

    test('dynamic prefix matching works', () {
      CodexPricingService.instance.loadFromJson('''
        {
          "models": {
            "new-model": { "input": 5.0, "cachedInput": 0.5, "output": 20.0 }
          }
        }
      ''');

      // "new-model-v2" should prefix-match "new-model"
      final pricing = lookupCodexPricing('new-model-v2');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(5.0);
    });

    test('uses hardcoded table when no dynamic pricing loaded', () {
      // No dynamic pricing loaded
      final pricing = lookupCodexPricing('gpt-5.2');
      check(pricing).isNotNull();
      check(pricing!.inputPerMillion).equals(1.75);
    });
  });
}
