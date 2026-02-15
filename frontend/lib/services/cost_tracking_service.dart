import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../models/cost_tracking.dart';
import 'log_service.dart';
import 'persistence_service.dart';

/// Service for persisting and retrieving cost tracking data.
///
/// Manages the append-only `tracking.jsonl` file for each project,
/// which stores historical cost data from closed chat sessions.
class CostTrackingService {
  /// Path to a project's cost tracking file (JSONL format).
  static String costTrackingPath(String projectId) =>
      '${PersistenceService.projectDir(projectId)}/tracking.jsonl';

  /// Loads cost tracking entries from the project's tracking.jsonl file.
  ///
  /// Returns an empty list if the file doesn't exist.
  /// Skips invalid lines and logs warnings for them.
  Future<List<CostTrackingEntry>> loadCostTracking(String projectId) async {
    final path = costTrackingPath(projectId);
    final file = File(path);

    if (!await file.exists()) {
      developer.log(
        'Cost tracking file not found for project $projectId',
        name: 'CostTrackingService',
      );
      return [];
    }

    final entries = <CostTrackingEntry>[];
    var lineNumber = 0;
    var skippedLines = 0;

    try {
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final lines = content.split('\n');

      for (final line in lines) {
        lineNumber++;
        if (line.trim().isEmpty) continue;

        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final entry = CostTrackingEntry.fromJson(json);
          entries.add(entry);
        } catch (e) {
          skippedLines++;
          developer.log(
            'Skipping invalid line $lineNumber in cost tracking: $e',
            name: 'CostTrackingService',
            error: e,
          );
        }
      }

      if (skippedLines > 0) {
        developer.log(
          'Loaded ${entries.length} cost tracking entries for project $projectId '
          '($skippedLines invalid lines skipped)',
          name: 'CostTrackingService',
          level: 900,
        );
      } else {
        developer.log(
          'Loaded ${entries.length} cost tracking entries for project $projectId',
          name: 'CostTrackingService',
        );
      }

      return entries;
    } catch (e) {
      developer.log(
        'Failed to load cost tracking for project $projectId: $e',
        name: 'CostTrackingService',
        error: e,
      );
      return entries;
    }
  }

  /// Appends a cost tracking entry to the project's tracking.jsonl file.
  ///
  /// Called when a chat is closed or when a worktree is deleted.
  /// The tracking file is append-only to avoid parsing overhead and support
  /// concurrent writes from multiple worktrees.
  ///
  /// Does nothing if the entry has no model usage (no cost to track).
  Future<void> appendCostTracking(
    String projectId,
    CostTrackingEntry entry,
  ) async {
    // Skip entries with no model usage
    if (entry.modelUsage.isEmpty) {
      developer.log(
        'Skipping cost tracking for ${entry.chatName}: no model usage',
        name: 'CostTrackingService',
      );
      return;
    }

    try {
      final trackingPath = costTrackingPath(projectId);
      final file = File(trackingPath);

      // Ensure parent directory exists
      await file.parent.create(recursive: true);

      // Append the entry as a single JSON line
      final jsonLine = '${jsonEncode(entry.toJson())}\n';
      await file.writeAsString(
        jsonLine,
        mode: FileMode.append,
        flush: true, // Ensure write is flushed to disk
      );

      developer.log(
        'Appended cost tracking for ${entry.chatName} in ${entry.worktree} '
        '(total: \$${entry.totalCost.toStringAsFixed(4)})',
        name: 'CostTrackingService',
      );
    } catch (e, stack) {
      LogService.instance.logUnhandledException(e, stack);
      // Don't rethrow - cost tracking failures shouldn't block chat closure
    }
  }
}
