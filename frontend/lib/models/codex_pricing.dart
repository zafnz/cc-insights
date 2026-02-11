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
  // GPT-5 family
  'gpt-5.2': CodexModelPricing(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
  'gpt-5.1': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-5': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-5-mini': CodexModelPricing(inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.00),
  'gpt-5-nano': CodexModelPricing(inputPerMillion: 0.05, cachedInputPerMillion: 0.005, outputPerMillion: 0.40),
  // GPT-5 chat-latest aliases
  'gpt-5.2-chat-latest': CodexModelPricing(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
  'gpt-5.1-chat-latest': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-5-chat-latest': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  // GPT-5 codex variants
  'gpt-5.2-codex': CodexModelPricing(inputPerMillion: 1.75, cachedInputPerMillion: 0.175, outputPerMillion: 14.00),
  'gpt-5.1-codex-max': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-5.1-codex': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-5.1-codex-mini': CodexModelPricing(inputPerMillion: 0.25, cachedInputPerMillion: 0.025, outputPerMillion: 2.00),
  'gpt-5-codex': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'codex-mini-latest': CodexModelPricing(inputPerMillion: 1.50, cachedInputPerMillion: 0.375, outputPerMillion: 6.00),
  // GPT-5 pro
  'gpt-5.2-pro': CodexModelPricing(inputPerMillion: 21.00, cachedInputPerMillion: 0.0, outputPerMillion: 168.00),
  'gpt-5-pro': CodexModelPricing(inputPerMillion: 15.00, cachedInputPerMillion: 0.0, outputPerMillion: 120.00),
  // GPT-4.1 family
  'gpt-4.1': CodexModelPricing(inputPerMillion: 2.00, cachedInputPerMillion: 0.50, outputPerMillion: 8.00),
  'gpt-4.1-mini': CodexModelPricing(inputPerMillion: 0.40, cachedInputPerMillion: 0.10, outputPerMillion: 1.60),
  'gpt-4.1-nano': CodexModelPricing(inputPerMillion: 0.10, cachedInputPerMillion: 0.025, outputPerMillion: 0.40),
  // GPT-4o family
  'gpt-4o': CodexModelPricing(inputPerMillion: 2.50, cachedInputPerMillion: 1.25, outputPerMillion: 10.00),
  'gpt-4o-2024-05-13': CodexModelPricing(inputPerMillion: 5.00, cachedInputPerMillion: 0.0, outputPerMillion: 15.00),
  'gpt-4o-mini': CodexModelPricing(inputPerMillion: 0.15, cachedInputPerMillion: 0.075, outputPerMillion: 0.60),
  // Realtime
  'gpt-realtime': CodexModelPricing(inputPerMillion: 4.00, cachedInputPerMillion: 0.40, outputPerMillion: 16.00),
  'gpt-realtime-mini': CodexModelPricing(inputPerMillion: 0.60, cachedInputPerMillion: 0.06, outputPerMillion: 2.40),
  'gpt-4o-realtime-preview': CodexModelPricing(inputPerMillion: 5.00, cachedInputPerMillion: 2.50, outputPerMillion: 20.00),
  'gpt-4o-mini-realtime-preview': CodexModelPricing(inputPerMillion: 0.60, cachedInputPerMillion: 0.30, outputPerMillion: 2.40),
  // Audio
  'gpt-audio': CodexModelPricing(inputPerMillion: 2.50, cachedInputPerMillion: 0.0, outputPerMillion: 10.00),
  'gpt-audio-mini': CodexModelPricing(inputPerMillion: 0.60, cachedInputPerMillion: 0.0, outputPerMillion: 2.40),
  'gpt-4o-audio-preview': CodexModelPricing(inputPerMillion: 2.50, cachedInputPerMillion: 0.0, outputPerMillion: 10.00),
  'gpt-4o-mini-audio-preview': CodexModelPricing(inputPerMillion: 0.15, cachedInputPerMillion: 0.0, outputPerMillion: 0.60),
  // o-series reasoning models
  'o1': CodexModelPricing(inputPerMillion: 15.00, cachedInputPerMillion: 7.50, outputPerMillion: 60.00),
  'o1-pro': CodexModelPricing(inputPerMillion: 150.00, cachedInputPerMillion: 0.0, outputPerMillion: 600.00),
  'o1-mini': CodexModelPricing(inputPerMillion: 1.10, cachedInputPerMillion: 0.55, outputPerMillion: 4.40),
  'o3-pro': CodexModelPricing(inputPerMillion: 20.00, cachedInputPerMillion: 0.0, outputPerMillion: 80.00),
  'o3': CodexModelPricing(inputPerMillion: 2.00, cachedInputPerMillion: 0.50, outputPerMillion: 8.00),
  'o3-deep-research': CodexModelPricing(inputPerMillion: 10.00, cachedInputPerMillion: 2.50, outputPerMillion: 40.00),
  'o3-mini': CodexModelPricing(inputPerMillion: 1.10, cachedInputPerMillion: 0.55, outputPerMillion: 4.40),
  'o4-mini': CodexModelPricing(inputPerMillion: 1.10, cachedInputPerMillion: 0.275, outputPerMillion: 4.40),
  'o4-mini-deep-research': CodexModelPricing(inputPerMillion: 2.00, cachedInputPerMillion: 0.50, outputPerMillion: 8.00),
  // Search
  'gpt-5-search-api': CodexModelPricing(inputPerMillion: 1.25, cachedInputPerMillion: 0.125, outputPerMillion: 10.00),
  'gpt-4o-mini-search-preview': CodexModelPricing(inputPerMillion: 0.15, cachedInputPerMillion: 0.0, outputPerMillion: 0.60),
  'gpt-4o-search-preview': CodexModelPricing(inputPerMillion: 2.50, cachedInputPerMillion: 0.0, outputPerMillion: 10.00),
  // Specialist
  'computer-use-preview': CodexModelPricing(inputPerMillion: 3.00, cachedInputPerMillion: 0.0, outputPerMillion: 12.00),
  'gpt-image-1.5': CodexModelPricing(inputPerMillion: 5.00, cachedInputPerMillion: 1.25, outputPerMillion: 10.00),
  'chatgpt-image-latest': CodexModelPricing(inputPerMillion: 5.00, cachedInputPerMillion: 1.25, outputPerMillion: 10.00),
  'gpt-image-1': CodexModelPricing(inputPerMillion: 5.00, cachedInputPerMillion: 1.25, outputPerMillion: 0.0),
  'gpt-image-1-mini': CodexModelPricing(inputPerMillion: 2.00, cachedInputPerMillion: 0.20, outputPerMillion: 0.0),
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
