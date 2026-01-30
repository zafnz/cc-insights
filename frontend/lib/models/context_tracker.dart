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

  /// The current number of tokens used in the context window.
  int get currentTokens => _currentTokens;

  /// The maximum number of tokens available in the context window.
  int get maxTokens => _maxTokens;

  /// The percentage of the context window that has been used (0.0 to 100.0).
  double get percentUsed =>
      _maxTokens > 0 ? (_currentTokens / _maxTokens) * 100 : 0.0;

  /// Updates the current token count from raw usage JSON.
  ///
  /// The usage map should contain:
  /// - `input_tokens`: Number of input tokens
  /// - `cache_creation_input_tokens`: Number of tokens used to create cache
  /// - `cache_read_input_tokens`: Number of tokens read from cache
  ///
  /// The current context is calculated as:
  /// input_tokens + cache_creation_input_tokens + cache_read_input_tokens
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

  /// Resets the current token count to zero.
  ///
  /// Call this after a `/clear` command or when starting a new conversation.
  void reset() {
    _currentTokens = 0;
    notifyListeners();
  }
}
