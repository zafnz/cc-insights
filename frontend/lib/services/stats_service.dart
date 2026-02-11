import 'package:path/path.dart' as p;

import '../models/project.dart';
import '../models/project_stats.dart';
import 'persistence_service.dart';

/// Service for building aggregated project statistics.
///
/// Merges historical cost tracking data from tracking.jsonl with live chat
/// data from the current ProjectState to produce a complete view of project
/// costs and usage.
class StatsService {
  final PersistenceService _persistence;

  StatsService({required PersistenceService persistence})
      : _persistence = persistence;

  /// Builds project statistics by merging historical and live data.
  ///
  /// The [project] provides live chat data from currently loaded worktrees.
  /// The [projectId] is used to load historical entries from tracking.jsonl.
  ///
  /// Returns a [ProjectStats] with:
  /// - Live chats marked as `isActive: true`
  /// - Historical chats marked as `isActive: false`
  /// - Worktrees sorted: active first (alphabetical), then deleted (alphabetical)
  /// - Deleted worktrees have `worktreePath: null`
  Future<ProjectStats> buildProjectStats({
    required ProjectState project,
    required String projectId,
  }) async {
    // Load historical entries from tracking.jsonl
    final historicalEntries = await _persistence.loadCostTracking(projectId);

    // Build a map of worktree name -> list of ChatStats
    final worktreeChatMap = <String, List<ChatStats>>{};

    // Add live chats from project state
    for (final worktree in project.allWorktrees) {
      final worktreeName = p.basename(worktree.data.worktreeRoot);

      // Only add worktrees that have chats
      if (worktree.chats.isEmpty) continue;

      final chatStats = <ChatStats>[];
      for (final chat in worktree.chats) {
        chatStats.add(ChatStats(
          chatName: chat.data.name,
          worktree: worktreeName,
          backend: chat.backendLabel,
          modelUsage: chat.modelUsage,
          timing: chat.timingStats,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isActive: true,
        ));
      }

      worktreeChatMap[worktreeName] = chatStats;
    }

    // Add historical chats
    for (final entry in historicalEntries) {
      final chatStats = ChatStats(
        chatName: entry.chatName,
        worktree: entry.worktree,
        backend: entry.backend,
        modelUsage: entry.modelUsage,
        timing: entry.timing,
        timestamp: entry.timestamp,
        isActive: false,
      );

      final existing = worktreeChatMap[entry.worktree];
      if (existing != null) {
        existing.add(chatStats);
      } else {
        worktreeChatMap[entry.worktree] = [chatStats];
      }
    }

    // Build worktree path map from live worktrees
    final worktreePathMap = <String, String>{};
    for (final worktree in project.allWorktrees) {
      final worktreeName = p.basename(worktree.data.worktreeRoot);
      worktreePathMap[worktreeName] = worktree.data.worktreeRoot;
    }

    // Build WorktreeStats list
    final worktreeStatsList = <WorktreeStats>[];
    for (final entry in worktreeChatMap.entries) {
      final worktreeName = entry.key;
      final chats = entry.value;
      final worktreePath = worktreePathMap[worktreeName];

      // Determine backends used by this worktree
      final backends = <String>{};
      for (final chat in chats) {
        backends.add(chat.backend);
      }

      worktreeStatsList.add(WorktreeStats(
        worktreeName: worktreeName,
        worktreePath: worktreePath,
        chats: chats,
        backends: backends,
      ));
    }

    // Sort worktrees: active first (alphabetical), then deleted (alphabetical)
    worktreeStatsList.sort((a, b) {
      final aDeleted = a.isDeleted;
      final bDeleted = b.isDeleted;

      if (aDeleted && !bDeleted) return 1;
      if (!aDeleted && bDeleted) return -1;

      return a.worktreeName.compareTo(b.worktreeName);
    });

    return ProjectStats(
      projectName: project.data.name,
      worktrees: worktreeStatsList,
    );
  }
}
