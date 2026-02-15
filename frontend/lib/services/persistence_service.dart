import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/output_entry.dart';
import 'log_service.dart';
import 'persistence_models.dart';

part 'persistence_service_index.dart';
part 'persistence_service_archive.dart';

/// Service for persisting project, chat, and conversation data.
///
/// Handles file operations for the CC-Insights persistence layer:
/// - `projects.json`: Master index of all projects, worktrees, and chats
/// - `<chatId>.meta.json`: Chat metadata (model, permissions, usage)
/// - `<chatId>.chat.jsonl`: Append-only conversation history
///
/// All paths are relative to `~/.ccinsights/` (or a custom directory if set).
class _PersistenceBase {
  /// Log level for non-critical warnings (e.g. missing files, skipped writes).
  static const int _kWarningLevel = 900;

  /// Per-file write queue to serialize appends and prevent interleaving.
  ///
  /// Concurrent async writes to the same file can interleave bytes, corrupting
  /// both JSON structure and multi-byte UTF-8 characters. This map chains
  /// writes per file path so each write completes before the next begins.
  final Map<String, Future<void>> _writeQueues = {};

  /// The base directory for all CC-Insights data.
  ///
  /// Can be overridden via the --config-dir CLI flag for test isolation.
  static String? _baseDirOverride;

  /// Sets the base directory override.
  ///
  /// This should be called once during app initialization if a custom
  /// config directory is specified via --config-dir.
  static void setBaseDir(String baseDir) {
    _baseDirOverride = baseDir;
  }

  /// The base directory for all CC-Insights data.
  static String get baseDir =>
      _baseDirOverride ?? '${Platform.environment['HOME']}/.ccinsights';

  /// Path to the master projects index file.
  static String get projectsJsonPath => '$baseDir/projects.json';

  /// Path to the backup of the projects index file.
  static String get projectsJsonBackupPath => '$baseDir/projects.json.bak';

  /// Directory for a specific project's data.
  static String projectDir(String projectId) => '$baseDir/projects/$projectId';

  /// Directory for a project's chat files.
  static String chatsDir(String projectId) => '${projectDir(projectId)}/chats';

  /// Path to a chat's conversation history (JSONL format).
  static String chatJsonlPath(String projectId, String chatId) =>
      '${chatsDir(projectId)}/$chatId.chat.jsonl';

  /// Path to a chat's metadata file.
  static String chatMetaPath(String projectId, String chatId) =>
      '${chatsDir(projectId)}/$chatId.meta.json';

  /// Generates a stable project ID from the project root path.
  ///
  /// Uses the first 8 characters of the SHA-256 hash of the path.
  /// This ensures:
  /// - Same project always gets the same ID
  /// - Different projects get different IDs (high probability)
  /// - IDs are filesystem-safe
  static String generateProjectId(String projectRoot) {
    final bytes = utf8.encode(projectRoot);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 8);
  }

  /// Loads the projects index from disk.
  ///
  /// Returns an empty [ProjectsIndex] if:
  /// - The file doesn't exist
  /// - The file is empty
  /// - The file contains invalid JSON
  ///
  /// On parse failure, attempts to restore from backup.
  Future<ProjectsIndex> loadProjectsIndex() async {
    final file = File(projectsJsonPath);

    if (!await file.exists()) {
      developer.log(
        'projects.json not found, returning empty index',
        name: 'PersistenceService',
      );
      return const ProjectsIndex.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        developer.log(
          'projects.json is empty, returning empty index',
          name: 'PersistenceService',
        );
        return const ProjectsIndex.empty();
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      return ProjectsIndex.fromJson(json);
    } catch (e) {
      developer.log(
        'Failed to parse projects.json: $e',
        name: 'PersistenceService',
        error: e,
      );

      // Try to restore from backup
      final backupFile = File(projectsJsonBackupPath);
      if (await backupFile.exists()) {
        try {
          developer.log(
            'Attempting to restore from backup',
            name: 'PersistenceService',
          );
          final backupContent = await backupFile.readAsString();
          final json = jsonDecode(backupContent) as Map<String, dynamic>;
          final restored = ProjectsIndex.fromJson(json);

          // Restore successful, overwrite corrupted file
          await file.writeAsString(backupContent);
          developer.log(
            'Successfully restored projects.json from backup',
            name: 'PersistenceService',
          );
          return restored;
        } catch (backupError) {
          developer.log(
            'Failed to restore from backup: $backupError',
            name: 'PersistenceService',
            error: backupError,
          );
        }
      }

      return const ProjectsIndex.empty();
    }
  }

  /// Saves the projects index to disk.
  ///
  /// Creates a backup of the existing file before writing.
  /// Creates the base directory if it doesn't exist.
  Future<void> saveProjectsIndex(ProjectsIndex index) async {
    final file = File(projectsJsonPath);
    final backupFile = File(projectsJsonBackupPath);

    try {
      // Ensure base directory exists
      final dir = Directory(baseDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Create backup of existing file
      if (await file.exists()) {
        await file.copy(backupFile.path);
      }

      // Write new content with pretty formatting
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(index.toJson());
      await file.writeAsString(content);

      developer.log(
        'Saved projects.json (${index.projects.length} projects)',
        name: 'PersistenceService',
      );
    } catch (e) {
      developer.log(
        'Failed to save projects.json: $e',
        name: 'PersistenceService',
        error: e,
      );
      rethrow;
    }
  }

  /// Loads chat metadata from disk.
  ///
  /// Returns default metadata if the file doesn't exist or is invalid.
  Future<ChatMeta> loadChatMeta(String projectId, String chatId) async {
    final path = chatMetaPath(projectId, chatId);
    final file = File(path);

    if (!await file.exists()) {
      developer.log(
        'Chat meta not found: $chatId, returning defaults',
        name: 'PersistenceService',
      );
      return ChatMeta.create();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return ChatMeta.create();
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      return ChatMeta.fromJson(json);
    } catch (e) {
      developer.log(
        'Failed to parse chat meta $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
      return ChatMeta.create();
    }
  }

  /// Saves chat metadata to disk.
  ///
  /// Creates the chat directory if it doesn't exist.
  Future<void> saveChatMeta(
    String projectId,
    String chatId,
    ChatMeta meta,
  ) async {
    final path = chatMetaPath(projectId, chatId);

    try {
      await ensureDirectories(projectId);

      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(meta.toJson());
      await File(path).writeAsString(content);

      developer.log('Saved chat meta: $chatId', name: 'PersistenceService');
    } catch (e) {
      developer.log(
        'Failed to save chat meta $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
      rethrow;
    }
  }

  /// Loads chat history from a JSONL file.
  ///
  /// Returns an empty list if the file doesn't exist.
  /// Skips invalid lines and logs warnings for them.
  ///
  /// Tool results are stored as separate [ToolResultEntry] entries in the JSONL
  /// file. During loading, these are merged into their corresponding
  /// [ToolUseOutputEntry] entries via [toolUseId] matching, and then filtered
  /// out of the final list.
  Future<List<OutputEntry>> loadChatHistory(
    String projectId,
    String chatId,
  ) async {
    final path = chatJsonlPath(projectId, chatId);
    final file = File(path);

    if (!await file.exists()) {
      LogService.instance.debug(
        'PersistenceService',
        'Chat history file not found',
        meta: {'chatId': chatId},
      );
      return [];
    }

    final entries = <OutputEntry>[];
    var lineNumber = 0;
    var skippedLines = 0;

    try {
      // Read as bytes and decode with replacement to handle corrupted UTF-8.
      // Concurrent writes can split multi-byte characters across lines,
      // producing invalid UTF-8 that would cause readAsLines() to throw.
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final lines = content.split('\n');

      for (final line in lines) {
        lineNumber++;
        if (line.trim().isEmpty) continue;

        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final entry = OutputEntry.fromJson(json);
          entries.add(entry);
        } catch (e) {
          skippedLines++;
          developer.log(
            'Skipping invalid line $lineNumber in $chatId: $e',
            name: 'PersistenceService',
            error: e,
          );
          // Continue processing remaining lines
        }
      }

      // Apply tool results to their corresponding tool use entries
      final processedEntries = _applyToolResults(entries);

      if (skippedLines > 0) {
        LogService.instance.debug(
          'PersistenceService',
          'Restored chat $chatId: loaded ${processedEntries.length} entries '
          '($skippedLines corrupted lines skipped)',
          meta: {'chatId': chatId},
        );
      } else {
        LogService.instance.debug(
          'PersistenceService',
          'Restored chat $chatId: loaded ${processedEntries.length} entries',
          meta: {'chatId': chatId},
        );
      }

      return processedEntries;
    } catch (e, stackTrace) {
      LogService.instance.error(
        'PersistenceService',
        'Failed to load chat history: $e',
        meta: {'chatId': chatId, 'stack': stackTrace.toString()},
      );
      // Return what we have so far
      return entries;
    }
  }

  /// Applies [ToolResultEntry] entries to their matching [ToolUseOutputEntry].
  ///
  /// Returns a new list with:
  /// - [ToolUseOutputEntry] entries updated with their results
  /// - [ToolResultEntry] entries filtered out (they're now merged)
  /// - All other entries unchanged
  List<OutputEntry> _applyToolResults(List<OutputEntry> entries) {
    // Build a map of toolUseId -> ToolUseOutputEntry for quick lookup
    final toolUseMap = <String, ToolUseOutputEntry>{};
    for (final entry in entries) {
      if (entry is ToolUseOutputEntry) {
        toolUseMap[entry.toolUseId] = entry;
      }
    }

    // Apply results to their corresponding tool use entries
    for (final entry in entries) {
      if (entry is ToolResultEntry) {
        final toolUse = toolUseMap[entry.toolUseId];
        if (toolUse != null) {
          toolUse.updateResult(entry.result, entry.isError);
        }
      }
    }

    // Filter out ToolResultEntry entries (they're now merged)
    return entries.where((e) => e is! ToolResultEntry).toList();
  }

  /// Appends an entry to the chat history JSONL file.
  ///
  /// Creates the file if it doesn't exist.
  /// Each entry is written as a single line with a trailing newline.
  ///
  /// Writes are serialized per file path to prevent concurrent async writes
  /// from interleaving bytes, which can corrupt both JSON structure and
  /// multi-byte UTF-8 characters.
  Future<void> appendChatEntry(
    String projectId,
    String chatId,
    OutputEntry entry,
  ) {
    final path = chatJsonlPath(projectId, chatId);

    // Chain this write after any pending write to the same file.
    final previous = _writeQueues[path] ?? Future<void>.value();
    final current = previous.then((_) async {
      try {
        await ensureDirectories(projectId);

        final json = jsonEncode(entry.toJson());
        final file = File(path);

        // Append with newline
        await file.writeAsString('$json\n', mode: FileMode.append);

        developer.log(
          'Appended entry to $chatId: ${entry.runtimeType}',
          name: 'PersistenceService',
        );
      } catch (e) {
        developer.log(
          'Failed to append entry to $chatId: $e',
          name: 'PersistenceService',
          error: e,
        );
        rethrow;
      }
    });

    // Store the future with error logging so the chain continues for next writes
    _writeQueues[path] = current.catchError((Object e, StackTrace stack) {
      developer.log(
        'Write queue error for $path (continuing chain)',
        name: 'PersistenceService',
        error: e,
        stackTrace: stack,
        level: 1000,
      );
    });

    return current;
  }

  /// Ensures the project and chat directories exist.
  Future<void> ensureDirectories(String projectId) async {
    final chatsDirPath = chatsDir(projectId);
    final dir = Directory(chatsDirPath);

    if (!await dir.exists()) {
      await dir.create(recursive: true);
      developer.log(
        'Created directories for project: $projectId',
        name: 'PersistenceService',
      );
    }
  }

  /// Deletes all files associated with a chat.
  ///
  /// Removes both the `.chat.jsonl` and `.meta.json` files.
  /// Does not update the projects index - caller must do that separately.
  Future<void> deleteChat(String projectId, String chatId) async {
    final jsonlPath = chatJsonlPath(projectId, chatId);
    final metaPath = chatMetaPath(projectId, chatId);

    try {
      final jsonlFile = File(jsonlPath);
      if (await jsonlFile.exists()) {
        await jsonlFile.delete();
        developer.log(
          'Deleted chat history: $chatId',
          name: 'PersistenceService',
        );
      }

      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        await metaFile.delete();
        developer.log('Deleted chat meta: $chatId', name: 'PersistenceService');
      }

      developer.log('Deleted chat files: $chatId', name: 'PersistenceService');
    } catch (e) {
      developer.log(
        'Failed to delete chat $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
      rethrow;
    }
  }
}

/// Service for persisting project, chat, and conversation data.
class PersistenceService extends _PersistenceBase
    with _IndexMixin, _ArchiveMixin {
  /// Sets the base directory override.
  ///
  /// This should be called once during app initialization if a custom
  /// config directory is specified via --config-dir.
  static void setBaseDir(String baseDir) => _PersistenceBase.setBaseDir(baseDir);

  /// The base directory for all CC-Insights data.
  static String get baseDir => _PersistenceBase.baseDir;

  /// Directory for a specific project's data.
  static String projectDir(String projectId) =>
      _PersistenceBase.projectDir(projectId);

  /// Generates a stable project ID from the project root path.
  ///
  /// Uses the first 8 characters of the SHA-256 hash of the path.
  /// This ensures:
  /// - Same project always gets the same ID
  /// - Different projects get different IDs (high probability)
  /// - IDs are filesystem-safe
  static String generateProjectId(String projectRoot) =>
      _PersistenceBase.generateProjectId(projectRoot);
}
