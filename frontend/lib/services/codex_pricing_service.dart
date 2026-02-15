import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/codex_pricing.dart';
import 'log_service.dart';

/// Service that manages dynamic Codex/GPT pricing data.
///
/// On initialization:
/// 1. Loads cached pricing from `~/.ccinsights/codex-pricing.json` (if present)
/// 2. Kicks off a background download from the GitHub URL
/// 3. Merges downloaded pricing and saves to disk for next startup
///
/// The [lookupCodexPricing] function in `codex_pricing.dart` uses this
/// service's pricing table, falling back to the hardcoded table.
class CodexPricingService {
  CodexPricingService._();

  static final CodexPricingService instance = CodexPricingService._();

  static const _pricingUrl =
      'https://raw.githubusercontent.com/zafnz/cc-insights/refs/heads/main/codex-pricing.json';

  /// Dynamic pricing table loaded from file/network.
  /// Keyed by lowercase model name.
  Map<String, CodexModelPricing> _dynamicPricing = {};

  /// Whether any dynamic pricing has been loaded.
  bool get hasDynamicPricing => _dynamicPricing.isNotEmpty;

  /// Look up pricing from the dynamic table. Returns null if not found.
  CodexModelPricing? lookup(String modelName) {
    final lower = modelName.toLowerCase();
    return _dynamicPricing[lower];
  }

  /// All dynamic pricing entries (for prefix matching in lookupCodexPricing).
  Iterable<MapEntry<String, CodexModelPricing>> get entries =>
      _dynamicPricing.entries;

  /// Initialize the service: load from disk, then fetch in background.
  void initialize() {
    _loadFromDisk();
    _fetchInBackground();
  }

  /// Load pricing from a JSON string. Used for testing and direct injection.
  @visibleForTesting
  void loadFromJson(String jsonContent) {
    final parsed = _parsePricingJson(jsonContent);
    if (parsed.isNotEmpty) {
      _dynamicPricing = parsed;
    }
  }

  /// Clear all dynamic pricing. Used for testing.
  @visibleForTesting
  void reset() {
    _dynamicPricing = {};
  }

  /// Path to the cached pricing file.
  static String get _cacheFilePath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.ccinsights/codex-pricing.json';
  }

  /// Load pricing from ~/.ccinsights/codex-pricing.json.
  void _loadFromDisk() {
    try {
      final file = File(_cacheFilePath);
      if (!file.existsSync()) return;

      final content = file.readAsStringSync();
      final parsed = _parsePricingJson(content);
      if (parsed.isNotEmpty) {
        _dynamicPricing = parsed;
        LogService.instance.info(
          'CodexPricing',
          'Loaded ${parsed.length} models from cache',
        );
      }
    } catch (e) {
      LogService.instance.warn(
        'CodexPricing',
        'Failed to load cached pricing: $e',
      );
    }
  }

  /// Download pricing from GitHub in the background.
  Future<void> _fetchInBackground() async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_pricingUrl));
        final response = await request.close();

        if (response.statusCode != 200) {
          LogService.instance.error(
            'CodexPricing',
            'Failed to download pricing: HTTP ${response.statusCode}',
          );
          await response.drain<void>();
          return;
        }

        final body = await response.transform(utf8.decoder).join();
        final parsed = _parsePricingJson(body);
        if (parsed.isNotEmpty) {
          _dynamicPricing = parsed;
          LogService.instance.info(
            'CodexPricing',
            'Downloaded ${parsed.length} models from remote',
          );
          _saveToDisk(body);
        }
      } finally {
        client.close();
      }
    } catch (e) {
      LogService.instance.error(
        'CodexPricing',
        'Failed to download pricing: $e',
      );
    }
  }

  /// Save the raw JSON to disk for next startup.
  void _saveToDisk(String jsonContent) {
    try {
      final file = File(_cacheFilePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonContent);
    } catch (e) {
      LogService.instance.warn(
        'CodexPricing',
        'Failed to save pricing cache: $e',
      );
    }
  }

  /// Parse the pricing JSON format into a map of CodexModelPricing.
  ///
  /// Expected format:
  /// ```json
  /// {
  ///   "models": {
  ///     "gpt-5.2": { "input": 1.75, "cachedInput": 0.175, "output": 14.00 },
  ///     ...
  ///   }
  /// }
  /// ```
  static Map<String, CodexModelPricing> _parsePricingJson(String content) {
    final result = <String, CodexModelPricing>{};
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final models = json['models'] as Map<String, dynamic>?;
      if (models == null) return result;

      for (final entry in models.entries) {
        final data = entry.value as Map<String, dynamic>;
        final input = (data['input'] as num?)?.toDouble();
        final cachedInput = (data['cachedInput'] as num?)?.toDouble();
        final output = (data['output'] as num?)?.toDouble();

        if (input != null && output != null) {
          result[entry.key.toLowerCase()] = CodexModelPricing(
            inputPerMillion: input,
            cachedInputPerMillion: cachedInput ?? 0.0,
            outputPerMillion: output,
          );
        }
      }
    } catch (e) {
      LogService.instance.warn(
        'CodexPricing',
        'Failed to parse pricing JSON: $e',
      );
    }
    return result;
  }
}
