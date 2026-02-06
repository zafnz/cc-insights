import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

import 'runtime_config.dart';

/// Cumulative usage statistics for the AskAI service.
///
/// Extends [ChangeNotifier] so UI can reactively display stats.
class AskAiUsageStats extends ChangeNotifier {
  int _totalQueries = 0;
  int _successfulQueries = 0;
  int _failedQueries = 0;
  double _totalCostUsd = 0.0;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  int _totalCacheReadTokens = 0;
  int _totalCacheCreationTokens = 0;
  int _totalDurationMs = 0;

  /// Total number of queries made.
  int get totalQueries => _totalQueries;

  /// Number of successful queries.
  int get successfulQueries => _successfulQueries;

  /// Number of failed queries.
  int get failedQueries => _failedQueries;

  /// Total cost in USD across all queries.
  double get totalCostUsd => _totalCostUsd;

  /// Total input tokens used.
  int get totalInputTokens => _totalInputTokens;

  /// Total output tokens used.
  int get totalOutputTokens => _totalOutputTokens;

  /// Total cache read tokens.
  int get totalCacheReadTokens => _totalCacheReadTokens;

  /// Total cache creation tokens.
  int get totalCacheCreationTokens => _totalCacheCreationTokens;

  /// Total duration in milliseconds across all queries.
  int get totalDurationMs => _totalDurationMs;

  /// Records a result and notifies listeners.
  void recordResult(SingleRequestResult result) {
    _totalQueries++;
    if (result.isError) {
      _failedQueries++;
    } else {
      _successfulQueries++;
    }
    _totalCostUsd += result.totalCostUsd;
    _totalInputTokens += result.usage.inputTokens;
    _totalOutputTokens += result.usage.outputTokens;
    _totalCacheReadTokens += result.usage.cacheReadInputTokens ?? 0;
    _totalCacheCreationTokens += result.usage.cacheCreationInputTokens ?? 0;
    _totalDurationMs += result.durationMs;
    notifyListeners();
  }

  /// Resets all statistics to zero.
  void reset() {
    _totalQueries = 0;
    _successfulQueries = 0;
    _failedQueries = 0;
    _totalCostUsd = 0.0;
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
    _totalCacheReadTokens = 0;
    _totalCacheCreationTokens = 0;
    _totalDurationMs = 0;
    notifyListeners();
  }

  @override
  String toString() {
    return 'AskAiUsageStats(queries: $_totalQueries ($_successfulQueries ok, $_failedQueries failed), '
        'cost: \$${_totalCostUsd.toStringAsFixed(4)}, '
        'tokens: $_totalInputTokens in / $_totalOutputTokens out, '
        'cache: $_totalCacheReadTokens read / $_totalCacheCreationTokens created)';
  }
}

/// Service for making one-shot AI queries using the Claude CLI.
///
/// This service wraps [ClaudeSingleRequest] from the Dart SDK and adds
/// cumulative usage tracking across all queries.
///
/// Example usage:
/// ```dart
/// final askAi = AskAiService();
///
/// final result = await askAi.ask(
///   prompt: 'Provide a good commit message for the uncommitted files',
///   workingDirectory: '/path/to/repo',
/// );
///
/// if (result != null && !result.isError) {
///   print('Commit message: ${result.result}');
/// }
///
/// print('Total cost so far: \$${askAi.usageStats.totalCostUsd}');
/// ```
class AskAiService {
  /// Creates an AskAiService.
  ///
  /// [claudePath] is an explicit override for the claude CLI executable.
  /// If not provided, the path is resolved from [RuntimeConfig.claudeCliPath]
  /// at request time, falling back to the default PATH lookup.
  AskAiService({String? claudePath}) : _explicitPath = claudePath;

  final String? _explicitPath;

  /// Returns the effective claude CLI path, resolving from settings.
  String? get _effectiveClaudePath {
    if (_explicitPath != null) return _explicitPath;
    final configPath = RuntimeConfig.instance.claudeCliPath;
    return configPath.isEmpty ? null : configPath;
  }

  /// Creates a [ClaudeSingleRequest] with the current effective path.
  ClaudeSingleRequest _createRequest() {
    return ClaudeSingleRequest(
      claudePath: _effectiveClaudePath,
      onLog: (message, {isError = false}) {
        developer.log(
          message,
          name: 'AskAiService',
          level: isError ? 900 : 800,
        );
      },
    );
  }

  /// Cumulative usage statistics across all queries.
  final AskAiUsageStats usageStats = AskAiUsageStats();

  /// Asks Claude a question and returns the result.
  ///
  /// Parameters:
  /// - [prompt]: The question or instruction for Claude.
  /// - [workingDirectory]: The directory to run Claude in (for context).
  /// - [model]: The model to use (default: 'haiku').
  /// - [allowedTools]: List of allowed tools (default: git, gh, Read).
  /// - [timeoutSeconds]: Timeout in seconds (default: 60).
  ///
  /// Returns the [SingleRequestResult] or null if the process failed to start.
  Future<SingleRequestResult?> ask({
    required String prompt,
    required String workingDirectory,
    String model = 'haiku',
    List<String>? allowedTools,
    int? maxTurns,
    int timeoutSeconds = 60,
  }) async {
    final claude = _createRequest();
    final result = await claude.request(
      prompt: prompt,
      workingDirectory: workingDirectory,
      options: SingleRequestOptions(
        model: model,
        allowedTools: allowedTools ?? ['Bash(git:*)', 'Bash(gh:*)', 'Read'],
        maxTurns: maxTurns,
        timeoutSeconds: timeoutSeconds,
      ),
    );

    if (result != null) {
      usageStats.recordResult(result);
      developer.log(
        'Cumulative stats: $usageStats',
        name: 'AskAiService',
      );
    }

    return result;
  }
}
