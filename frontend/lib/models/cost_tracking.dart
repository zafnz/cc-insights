import 'package:flutter/foundation.dart';

import 'output_entry.dart';

/// Cost tracking entry for persistent storage.
///
/// This model represents a single chat's final cost totals that are appended
/// to the project's tracking.jsonl file when a chat is closed or its worktree
/// is deleted. This allows tracking project-wide costs even after chats are
/// removed from memory.
///
/// The tracking.jsonl file is append-only to avoid parsing overhead and
/// support concurrent writes from multiple worktrees.
@immutable
class CostTrackingEntry {
  /// The name of the worktree this chat belonged to.
  final String worktree;

  /// The name of the chat at the time of closure.
  final String chatName;

  /// ISO 8601 timestamp when this entry was recorded.
  final String timestamp;

  /// Per-model usage breakdown with costs.
  ///
  /// Contains the cumulative usage for each model used during the chat's
  /// lifetime. Multiple entries with the same worktree/chatName are possible
  /// because worktrees and chats can be recreated with the same names.
  final List<ModelUsageInfo> modelUsage;

  /// Creates a [CostTrackingEntry] instance.
  const CostTrackingEntry({
    required this.worktree,
    required this.chatName,
    required this.timestamp,
    required this.modelUsage,
  });

  /// Creates a tracking entry from a chat's final state.
  ///
  /// The [worktreeName] is typically the branch name or directory name.
  /// The [chatName] is the user-visible chat name.
  /// The [modelUsage] is the chat's cumulative per-model usage.
  /// The timestamp is set to the current time.
  factory CostTrackingEntry.fromChat({
    required String worktreeName,
    required String chatName,
    required List<ModelUsageInfo> modelUsage,
  }) {
    return CostTrackingEntry(
      worktree: worktreeName,
      chatName: chatName,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      modelUsage: modelUsage,
    );
  }

  /// Serializes this entry to a JSON map for JSONL storage.
  Map<String, dynamic> toJson() {
    return {
      'worktree': worktree,
      'chatName': chatName,
      'timestamp': timestamp,
      'modelUsage': modelUsage
          .map((m) => {
                'modelName': m.modelName,
                'inputTokens': m.inputTokens,
                'outputTokens': m.outputTokens,
                'cacheReadTokens': m.cacheReadTokens,
                'cacheCreationTokens': m.cacheCreationTokens,
                'costUsd': m.costUsd,
                'contextWindow': m.contextWindow,
              })
          .toList(),
    };
  }

  /// Deserializes a tracking entry from a JSON map.
  factory CostTrackingEntry.fromJson(Map<String, dynamic> json) {
    final modelUsageJson = json['modelUsage'] as List<dynamic>? ?? [];

    return CostTrackingEntry(
      worktree: json['worktree'] as String? ?? '',
      chatName: json['chatName'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      modelUsage: modelUsageJson
          .map((m) {
            final map = m as Map<String, dynamic>;
            return ModelUsageInfo(
              modelName: map['modelName'] as String? ?? '',
              inputTokens: map['inputTokens'] as int? ?? 0,
              outputTokens: map['outputTokens'] as int? ?? 0,
              cacheReadTokens: map['cacheReadTokens'] as int? ?? 0,
              cacheCreationTokens: map['cacheCreationTokens'] as int? ?? 0,
              costUsd: (map['costUsd'] as num?)?.toDouble() ?? 0.0,
              contextWindow: map['contextWindow'] as int? ?? 200000,
            );
          })
          .toList(),
    );
  }

  /// Calculates the total cost across all models.
  double get totalCost {
    return modelUsage.fold(0.0, (sum, m) => sum + m.costUsd);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CostTrackingEntry &&
        other.worktree == worktree &&
        other.chatName == chatName &&
        other.timestamp == timestamp &&
        listEquals(other.modelUsage, modelUsage);
  }

  @override
  int get hashCode => Object.hash(
        worktree,
        chatName,
        timestamp,
        Object.hashAll(modelUsage),
      );

  @override
  String toString() {
    return 'CostTrackingEntry(worktree: $worktree, chatName: $chatName, '
        'timestamp: $timestamp, totalCost: \$${totalCost.toStringAsFixed(4)})';
  }
}
