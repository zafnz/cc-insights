import 'package:flutter/foundation.dart';

/// Per-million-token pricing for a Codex/GPT model.
///
/// Prices are in USD per million tokens.
// TODO: Fetch pricing dynamically from
// https://raw.githubusercontent.com/zafnz/cc-insights/refs/heads/main/codex-pricing.json
@immutable
class CodexModelPricing {
  final double inputPerMillion;
  final double cachedInputPerMillion;
  final double outputPerMillion;

  const CodexModelPricing({
    required this.inputPerMillion,
    required this.cachedInputPerMillion,
    required this.outputPerMillion,
  });

  /// Calculate cost in USD from token counts.
  double calculateCost({
    required int inputTokens,
    required int cachedInputTokens,
    required int outputTokens,
  }) {
    return (inputTokens * inputPerMillion +
            cachedInputTokens * cachedInputPerMillion +
            outputTokens * outputPerMillion) /
        1000000;
  }
}

/// Hardcoded pricing table for Codex/GPT models.
///
/// Keyed by exact model name. Prices are USD per million tokens.
const codexPricingTable = <String, CodexModelPricing>{
  'gpt-5.2': CodexModelPricing(
    inputPerMillion: 1.75,
    cachedInputPerMillion: 0.175,
    outputPerMillion: 14.00,
  ),
  'gpt-5.1': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5-mini': CodexModelPricing(
    inputPerMillion: 0.25,
    cachedInputPerMillion: 0.025,
    outputPerMillion: 2.00,
  ),
  'gpt-5-nano': CodexModelPricing(
    inputPerMillion: 0.05,
    cachedInputPerMillion: 0.005,
    outputPerMillion: 0.40,
  ),
  'gpt-5.2-chat-latest': CodexModelPricing(
    inputPerMillion: 1.75,
    cachedInputPerMillion: 0.175,
    outputPerMillion: 14.00,
  ),
  'gpt-5.1-chat-latest': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5-chat-latest': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5.2-codex': CodexModelPricing(
    inputPerMillion: 1.75,
    cachedInputPerMillion: 0.175,
    outputPerMillion: 14.00,
  ),
  'gpt-5.1-codex-max': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5.1-codex': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5-codex': CodexModelPricing(
    inputPerMillion: 1.25,
    cachedInputPerMillion: 0.125,
    outputPerMillion: 10.00,
  ),
  'gpt-5.2-pro': CodexModelPricing(
    inputPerMillion: 21.00,
    cachedInputPerMillion: 0.0,
    outputPerMillion: 168.00,
  ),
  'gpt-5-pro': CodexModelPricing(
    inputPerMillion: 15.00,
    cachedInputPerMillion: 0.0,
    outputPerMillion: 120.00,
  ),
};

/// Look up pricing for a Codex/GPT model.
///
/// Tries exact match first, then checks if the model name starts with any
/// known pricing key (longest match wins). Returns null if no match found.
CodexModelPricing? lookupCodexPricing(String modelName) {
  final lower = modelName.toLowerCase();

  // Exact match
  final exact = codexPricingTable[lower];
  if (exact != null) return exact;

  // Prefix match: find the longest key that is a prefix of the model name.
  // E.g. model "gpt-5.2-codex-preview" would match "gpt-5.2-codex".
  CodexModelPricing? best;
  int bestLen = 0;
  for (final entry in codexPricingTable.entries) {
    if (lower.startsWith(entry.key) && entry.key.length > bestLen) {
      best = entry.value;
      bestLen = entry.key.length;
    }
  }
  return best;
}
