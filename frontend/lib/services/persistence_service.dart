import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/output_entry.dart';
import 'persistence_models.dart';

/// Service for persisting project, chat, and conversation data.
///
/// Handles file operations for the CC-Insights persistence layer:
/// - `projects.json`: Master index of all projects, worktrees, and chats
/// - `<chatId>.meta.json`: Chat metadata (model, permissions, usage)
/// - `<chatId>.chat.jsonl`: Append-only conversation history
///
/// All paths are relative to `~/.ccinsights/`.
class PersistenceService {
  /// The base directory for all CC-Insights data.
  static String get baseDir => '${Platform.environment['HOME']}/.ccinsights';

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
      final encoder = const JsonEncoder.withIndent('  ');
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

      final encoder = const JsonEncoder.withIndent('  ');
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
      developer.log(
        'Chat history not found: $chatId',
        name: 'PersistenceService',
      );
      return [];
    }

    final entries = <OutputEntry>[];
    var lineNumber = 0;

    try {
      final lines = await file.readAsLines();

      for (final line in lines) {
        lineNumber++;
        if (line.trim().isEmpty) continue;

        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final entry = OutputEntry.fromJson(json);
          entries.add(entry);
        } catch (e) {
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

      developer.log(
        'Loaded ${processedEntries.length} entries from $chatId',
        name: 'PersistenceService',
      );

      return processedEntries;
    } catch (e) {
      developer.log(
        'Failed to load chat history $chatId: $e',
        name: 'PersistenceService',
        error: e,
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
  Future<void> appendChatEntry(
    String projectId,
    String chatId,
    OutputEntry entry,
  ) async {
    final path = chatJsonlPath(projectId, chatId);

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

  /// Updates the last session ID for a chat in projects.json.
  ///
  /// This is used to persist the SDK session ID for session resume.
  /// The [sessionId] can be null to clear the session ID (e.g., on session end).
  ///
  /// Parameters:
  /// - [projectRoot]: The absolute path to the project root.
  /// - [worktreePath]: The absolute path to the worktree.
  /// - [chatId]: The chat identifier.
  /// - [sessionId]: The SDK session ID to store, or null to clear.
  ///
  /// This method is designed to be called fire-and-forget - errors are logged
  /// but not thrown to avoid blocking UI operations.
  Future<void> updateChatSessionId({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String? sessionId,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for session ID update: $projectRoot',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      final worktree = project.worktrees[worktreePath];
      if (worktree == null) {
        developer.log(
          'Worktree not found for session ID update: $worktreePath',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      // Find and update the chat reference
      final updatedChats = worktree.chats.map((chat) {
        if (chat.chatId == chatId) {
          return ChatReference(
            name: chat.name,
            chatId: chat.chatId,
            lastSessionId: sessionId,
          );
        }
        return chat;
      }).toList();

      // Rebuild the index with the updated chat
      final updatedWorktree = worktree.copyWith(chats: updatedChats);
      final updatedProject = project.copyWith(
        worktrees: {
          ...project.worktrees,
          worktreePath: updatedWorktree,
        },
      );
      final updatedIndex = projectsIndex.copyWith(
        projects: {
          ...projectsIndex.projects,
          projectRoot: updatedProject,
        },
      );

      await saveProjectsIndex(updatedIndex);

      developer.log(
        'Updated session ID for chat $chatId: ${sessionId ?? 'cleared'}',
        name: 'PersistenceService',
      );
    } catch (e) {
      // Log error but don't throw - this is a fire-and-forget operation
      developer.log(
        'Failed to update session ID for chat $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Renames a chat in the projects.json index.
  ///
  /// This updates the chat name in the worktree's chat list in projects.json.
  ///
  /// This method is designed to be called fire-and-forget - errors are logged
  /// but not thrown to avoid blocking UI operations.
  Future<void> renameChatInIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String newName,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for chat rename: $projectRoot',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      final worktree = project.worktrees[worktreePath];
      if (worktree == null) {
        developer.log(
          'Worktree not found for chat rename: $worktreePath',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      // Find and update the chat reference with the new name
      final updatedChats = worktree.chats.map((chat) {
        if (chat.chatId == chatId) {
          return ChatReference(
            name: newName,
            chatId: chat.chatId,
            lastSessionId: chat.lastSessionId,
          );
        }
        return chat;
      }).toList();

      // Rebuild the index with the updated chat
      final updatedWorktree = worktree.copyWith(chats: updatedChats);
      final updatedProject = project.copyWith(
        worktrees: {
          ...project.worktrees,
          worktreePath: updatedWorktree,
        },
      );
      final updatedIndex = projectsIndex.copyWith(
        projects: {
          ...projectsIndex.projects,
          projectRoot: updatedProject,
        },
      );

      await saveProjectsIndex(updatedIndex);

      developer.log(
        'Renamed chat $chatId to: $newName',
        name: 'PersistenceService',
      );
    } catch (e) {
      // Log error but don't throw - this is a fire-and-forget operation
      developer.log(
        'Failed to rename chat $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Removes a chat reference from the projects.json index.
  ///
  /// This removes the chat from the worktree's chat list in projects.json.
  /// Does not delete the chat files from disk - use [deleteChat] for that.
  ///
  /// This method is designed to be called fire-and-forget - errors are logged
  /// but not thrown to avoid blocking UI operations.
  Future<void> removeChatFromIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for chat removal: $projectRoot',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      final worktree = project.worktrees[worktreePath];
      if (worktree == null) {
        developer.log(
          'Worktree not found for chat removal: $worktreePath',
          name: 'PersistenceService',
          level: 900, // Warning
        );
        return;
      }

      // Filter out the chat with matching chatId
      final updatedChats =
          worktree.chats.where((chat) => chat.chatId != chatId).toList();

      // Rebuild the index with the updated chat list
      final updatedWorktree = worktree.copyWith(chats: updatedChats);
      final updatedProject = project.copyWith(
        worktrees: {
          ...project.worktrees,
          worktreePath: updatedWorktree,
        },
      );
      final updatedIndex = projectsIndex.copyWith(
        projects: {
          ...projectsIndex.projects,
          projectRoot: updatedProject,
        },
      );

      await saveProjectsIndex(updatedIndex);

      developer.log(
        'Removed chat $chatId from projects.json',
        name: 'PersistenceService',
      );
    } catch (e) {
      // Log error but don't throw - this is a fire-and-forget operation
      developer.log(
        'Failed to remove chat $chatId from index: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Updates the tags assigned to a worktree in projects.json.
  ///
  /// This method is designed to be called fire-and-forget - errors are logged
  /// but not thrown to avoid blocking UI operations.
  Future<void> updateWorktreeTags({
    required String projectRoot,
    required String worktreePath,
    required List<String> tags,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for tag update: $projectRoot',
          name: 'PersistenceService',
          level: 900,
        );
        return;
      }

      final worktree = project.worktrees[worktreePath];
      if (worktree == null) {
        developer.log(
          'Worktree not found for tag update: $worktreePath',
          name: 'PersistenceService',
          level: 900,
        );
        return;
      }

      final updatedWorktree = worktree.copyWith(tags: tags);
      final updatedProject = project.copyWith(
        worktrees: {
          ...project.worktrees,
          worktreePath: updatedWorktree,
        },
      );
      final updatedIndex = projectsIndex.copyWith(
        projects: {
          ...projectsIndex.projects,
          projectRoot: updatedProject,
        },
      );

      await saveProjectsIndex(updatedIndex);

      developer.log(
        'Updated tags for worktree $worktreePath: $tags',
        name: 'PersistenceService',
      );
    } catch (e) {
      developer.log(
        'Failed to update tags for worktree $worktreePath: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Removes a worktree from the projects.json index.
  ///
  /// This removes the worktree and all its associated chats from projects.json.
  /// Does not delete the worktree files from disk (that's done via git).
  /// Also deletes all chat files associated with this worktree.
  ///
  /// Returns the list of chat IDs that were in the worktree (for cleanup).
  ///
  /// This method throws on failure since worktree deletion is a critical
  /// operation that should fail visibly.
  Future<List<String>> removeWorktreeFromIndex({
    required String projectRoot,
    required String worktreePath,
    required String projectId,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for worktree removal: $projectRoot',
        name: 'PersistenceService',
        level: 900, // Warning
      );
      return [];
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for removal: $worktreePath',
        name: 'PersistenceService',
        level: 900, // Warning
      );
      return [];
    }

    // Collect chat IDs for cleanup
    final chatIds = worktree.chats.map((chat) => chat.chatId).toList();

    // Remove the worktree from the map
    final updatedWorktrees = Map<String, WorktreeInfo>.from(project.worktrees)
      ..remove(worktreePath);

    // Rebuild the index without this worktree
    final updatedProject = project.copyWith(worktrees: updatedWorktrees);
    final updatedIndex = projectsIndex.copyWith(
      projects: {
        ...projectsIndex.projects,
        projectRoot: updatedProject,
      },
    );

    await saveProjectsIndex(updatedIndex);

    // Delete all chat files for this worktree
    for (final chatId in chatIds) {
      try {
        await deleteChat(projectId, chatId);
      } catch (e) {
        developer.log(
          'Failed to delete chat $chatId during worktree removal: $e',
          name: 'PersistenceService',
          error: e,
        );
        // Continue with other chats
      }
    }

    developer.log(
      'Removed worktree $worktreePath from projects.json '
      '(${chatIds.length} chats)',
      name: 'PersistenceService',
    );

    return chatIds;
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
