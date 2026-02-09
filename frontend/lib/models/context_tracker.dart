import 'package:flutter/foundation.dart';

/// Tracks context window usage for a conversation.
///
/// This class monitors how much of the available context window has been
/// consumed. It receives updates from SDK messages and notifies listeners
/// when the usage changes.
///
/// The default maximum context window is 200,000 tokens, which can be
/// updated when result messages arrive with model-specific context window
/// information.
class ContextTracker extends ChangeNotifier {
  int _currentTokens = 0;
  int _maxTokens = 200000;
  double? _autocompactBufferPercent;

  /// The current number of tokens used in the context window.
  int get currentTokens => _currentTokens;

  /// The maximum number of tokens available in the context window.
  int get maxTokens => _maxTokens;

  /// The autocompact buffer percentage, if known.
  ///
  /// For Claude chats this is 22.5%. For Codex chats this is null (unknown).
  /// When null, the UI should not show autocompact-specific information.
  double? get autocompactBufferPercent => _autocompactBufferPercent;

  /// The percentage of the context window that has been used (0.0 to 100.0).
  double get percentUsed =>
      _maxTokens > 0 ? (_currentTokens / _maxTokens) * 100 : 0.0;

  /// Updates the current token count from a single API call's usage.
  ///
  /// The usage map should contain per-step (single API call) values:
  /// - `input_tokens`: Number of uncached input tokens
  /// - `cache_creation_input_tokens`: Tokens written to cache for the first time
  /// - `cache_read_input_tokens`: Tokens read from cache
  ///
  /// The effective context window usage for a single step is the sum of all
  /// three fields — they represent the total prompt size sent to the model.
  ///
  /// IMPORTANT: This must receive per-step usage from a single API call, NOT
  /// the cumulative usage from a result message (which sums across all steps
  /// in a turn and would inflate the count).
  void updateFromUsage(Map<String, dynamic> usage) {
    final inputTokens = usage['input_tokens'] as int? ?? 0;
    final cacheCreation = usage['cache_creation_input_tokens'] as int? ?? 0;
    final cacheRead = usage['cache_read_input_tokens'] as int? ?? 0;

    _currentTokens = inputTokens + cacheCreation + cacheRead;
    notifyListeners();
  }

  /// Updates the maximum context window size.
  ///
  /// This is typically called when a result message arrives with the
  /// model's context window information.
  void updateMaxTokens(int maxTokens) {
    if (maxTokens > 0 && maxTokens != _maxTokens) {
      _maxTokens = maxTokens;
      notifyListeners();
    }
  }

  /// Updates the autocompact buffer percentage.
  ///
  /// Pass 22.5 for Claude chats, or null for backends where the
  /// autocompact behavior is unknown (e.g., Codex).
  void updateAutocompactBuffer(double? percent) {
    if (_autocompactBufferPercent != percent) {
      _autocompactBufferPercent = percent;
      notifyListeners();
    }
  }

  /// Resets the current token count to zero.
  ///
  /// Call this after a `/clear` command or when starting a new conversation.
  void reset() {
    _currentTokens = 0;
    notifyListeners();
  }
}
