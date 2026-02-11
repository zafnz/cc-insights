import 'package:flutter/foundation.dart';

import 'output_entry.dart';
import 'timing_stats.dart';

/// Statistics for a single chat.
///
/// Represents cost and usage data for one chat instance, either active
/// (currently running) or historical (closed and persisted to tracking.jsonl).
@immutable
class ChatStats {
  /// The name of the chat.
  final String chatName;

  /// The worktree name this chat belongs to.
  final String worktree;

  /// Backend that produced this chat ('claude' or 'codex').
  final String backend;

  /// Per-model usage breakdown with costs.
  final List<ModelUsageInfo> modelUsage;

  /// Timing statistics for the chat.
  final TimingStats timing;

  /// ISO 8601 timestamp when this entry was created/closed.
  final String timestamp;

  /// Whether this chat is currently active.
  ///
  /// True for chats in the current project state, false for historical
  /// entries loaded from tracking.jsonl.
  final bool isActive;

  /// Creates a [ChatStats] instance.
  const ChatStats({
    required this.chatName,
    required this.worktree,
    required this.backend,
    required this.modelUsage,
    required this.timing,
    required this.timestamp,
    required this.isActive,
  });

  /// Total cost in USD across all models.
  double get totalCost {
    return modelUsage.fold(0.0, (sum, m) => sum + m.costUsd);
  }

  /// Total tokens consumed across all models.
  int get totalTokens {
    return modelUsage.fold(0, (sum, m) => sum + m.totalTokens);
  }

  /// Whether this chat has cost data.
  ///
  /// Codex backend doesn't report costs, so we distinguish "cost is $0.00"
  /// from "cost is unknown".
  bool get hasCostData => backend != 'codex';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatStats &&
        other.chatName == chatName &&
        other.worktree == worktree &&
        other.backend == backend &&
        listEquals(other.modelUsage, modelUsage) &&
        other.timing == timing &&
        other.timestamp == timestamp &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(
        chatName,
        worktree,
        backend,
        Object.hashAll(modelUsage),
        timing,
        timestamp,
        isActive,
      );

  @override
  String toString() {
    return 'ChatStats(chatName: $chatName, worktree: $worktree, '
        'backend: $backend, totalCost: \$${totalCost.toStringAsFixed(4)}, '
        'totalTokens: $totalTokens, isActive: $isActive)';
  }
}

/// Aggregated statistics for a worktree.
///
/// Combines data from all chats (active and historical) that belong to
/// this worktree.
@immutable
class WorktreeStats {
  /// The name of the worktree.
  final String worktreeName;

  /// The filesystem path to the worktree, or null if deleted.
  final String? worktreePath;

  /// All chats belonging to this worktree.
  final List<ChatStats> chats;

  /// Set of backend types used by chats in this worktree.
  final Set<String> backends;

  /// Creates a [WorktreeStats] instance.
  const WorktreeStats({
    required this.worktreeName,
    required this.worktreePath,
    required this.chats,
    required this.backends,
  });

  /// Total cost in USD across all chats with cost data.
  ///
  /// Only includes chats where [ChatStats.hasCostData] is true.
  double get totalCost {
    return chats
        .where((c) => c.hasCostData)
        .fold(0.0, (sum, c) => sum + c.totalCost);
  }

  /// Total tokens consumed across all chats.
  ///
  /// Includes all chats regardless of backend.
  int get totalTokens {
    return chats.fold(0, (sum, c) => sum + c.totalTokens);
  }

  /// Total timing statistics merged from all chats.
  TimingStats get totalTiming {
    return chats.fold(
      const TimingStats.zero(),
      (acc, c) => acc.merge(c.timing),
    );
  }

  /// Number of chats in this worktree.
  int get chatCount => chats.length;

  /// Aggregated model usage merged by model name.
  List<ModelUsageInfo> get aggregatedModelUsage {
    return mergeModelUsage(chats.expand((c) => c.modelUsage).toList());
  }

  /// Whether this worktree has been deleted.
  bool get isDeleted => worktreePath == null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorktreeStats &&
        other.worktreeName == worktreeName &&
        other.worktreePath == worktreePath &&
        listEquals(other.chats, chats) &&
        setEquals(other.backends, backends);
  }

  @override
  int get hashCode => Object.hash(
        worktreeName,
        worktreePath,
        Object.hashAll(chats),
        Object.hashAll(backends),
      );

  @override
  String toString() {
    return 'WorktreeStats(worktreeName: $worktreeName, '
        'worktreePath: $worktreePath, chatCount: $chatCount, '
        'totalCost: \$${totalCost.toStringAsFixed(4)}, '
        'totalTokens: $totalTokens, isDeleted: $isDeleted)';
  }
}

/// Aggregated statistics for the entire project.
///
/// Combines data from all worktrees (active and deleted).
@immutable
class ProjectStats {
  /// The project name.
  final String projectName;

  /// All worktrees in the project.
  final List<WorktreeStats> worktrees;

  /// Creates a [ProjectStats] instance.
  const ProjectStats({
    required this.projectName,
    required this.worktrees,
  });

  /// Total cost in USD across all worktrees.
  double get totalCost {
    return worktrees.fold(0.0, (sum, w) => sum + w.totalCost);
  }

  /// Total tokens consumed across all worktrees.
  int get totalTokens {
    return worktrees.fold(0, (sum, w) => sum + w.totalTokens);
  }

  /// Total timing statistics merged from all worktrees.
  TimingStats get totalTiming {
    return worktrees.fold(
      const TimingStats.zero(),
      (acc, w) => acc.merge(w.totalTiming),
    );
  }

  /// Total number of chats across all worktrees.
  int get totalChats {
    return worktrees.fold(0, (sum, w) => sum + w.chatCount);
  }

  /// Aggregated model usage merged by model name across all worktrees.
  List<ModelUsageInfo> get aggregatedModelUsage {
    return mergeModelUsage(
      worktrees.expand((w) => w.aggregatedModelUsage).toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectStats &&
        other.projectName == projectName &&
        listEquals(other.worktrees, worktrees);
  }

  @override
  int get hashCode => Object.hash(
        projectName,
        Object.hashAll(worktrees),
      );

  @override
  String toString() {
    return 'ProjectStats(projectName: $projectName, '
        'worktrees: ${worktrees.length}, totalChats: $totalChats, '
        'totalCost: \$${totalCost.toStringAsFixed(4)}, '
        'totalTokens: $totalTokens)';
  }
}

/// Merges model usage entries by model name.
///
/// For entries with the same model name, sums all token counts and costs.
/// For context window, takes the maximum value.
///
/// Returns a list with one entry per distinct model name.
List<ModelUsageInfo> mergeModelUsage(List<ModelUsageInfo> entries) {
  if (entries.isEmpty) return [];

  final result = <String, ModelUsageInfo>{};

  for (final model in entries) {
    final existing = result[model.modelName];
    if (existing != null) {
      // Merge with existing entry
      result[model.modelName] = ModelUsageInfo(
        modelName: model.modelName,
        inputTokens: existing.inputTokens + model.inputTokens,
        outputTokens: existing.outputTokens + model.outputTokens,
        cacheReadTokens: existing.cacheReadTokens + model.cacheReadTokens,
        cacheCreationTokens:
            existing.cacheCreationTokens + model.cacheCreationTokens,
        costUsd: existing.costUsd + model.costUsd,
        contextWindow: existing.contextWindow > model.contextWindow
            ? existing.contextWindow
            : model.contextWindow,
      );
    } else {
      // First occurrence of this model
      result[model.modelName] = model;
    }
  }

  return result.values.toList();
}
