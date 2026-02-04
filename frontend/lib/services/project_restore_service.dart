import 'dart:developer' as developer;

import 'package:path/path.dart' as p;

import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import 'persistence_models.dart';
import 'persistence_service.dart';

/// Service for restoring projects, worktrees, and chats from persistence.
///
/// This service handles the logic for:
/// - Restoring existing projects from `projects.json`
/// - Creating new projects when they don't exist
/// - Lazy-loading chat history when a chat is selected
///
/// The restore process follows the persistence architecture:
/// 1. Load `projects.json` to find the project by root path
/// 2. Restore `ProjectState` and `WorktreeState` objects
/// 3. Create `ChatState` objects (without loading history)
/// 4. History is loaded lazily when a chat is selected
class ProjectRestoreService {
  final PersistenceService _persistence;

  /// Creates a [ProjectRestoreService] with the given persistence service.
  ///
  /// If no persistence service is provided, a default instance is created.
  ProjectRestoreService([PersistenceService? persistence])
      : _persistence = persistence ?? PersistenceService();

  /// Restores or creates a project for the given root path.
  ///
  /// Returns a tuple of (ProjectState, isNew) where:
  /// - `ProjectState` is the restored or newly created project
  /// - `isNew` is true if this is a new project, false if restored
  ///
  /// If the project exists in `projects.json`:
  /// - Restores the project with all worktrees and chats
  /// - Does NOT load chat history (lazy load on selection)
  ///
  /// If the project doesn't exist:
  /// - Creates a new project with a primary worktree
  /// - Saves the new project to `projects.json`
  ///
  /// [autoValidate] controls whether worktrees are validated on creation.
  /// [watchFilesystem] controls whether filesystem watchers are enabled.
  /// Both default to true for production use; set to false for tests.
  Future<(ProjectState, bool isNew)> restoreOrCreateProject(
    String projectRoot, {
    bool autoValidate = true,
    bool watchFilesystem = true,
  }) async {
    final projectsIndex = await _persistence.loadProjectsIndex();
    final projectId = PersistenceService.generateProjectId(projectRoot);

    final existingProject = projectsIndex.projects[projectRoot];
    if (existingProject != null) {
      developer.log(
        'Restoring existing project: ${existingProject.name}',
        name: 'ProjectRestoreService',
      );
      final project = await _restoreProject(
        projectRoot,
        existingProject,
        autoValidate: autoValidate,
        watchFilesystem: watchFilesystem,
      );
      return (project, false);
    } else {
      developer.log(
        'Creating new project at: $projectRoot',
        name: 'ProjectRestoreService',
      );
      final project = await _createNewProject(
        projectRoot,
        projectId,
        projectsIndex,
        autoValidate: autoValidate,
        watchFilesystem: watchFilesystem,
      );
      return (project, true);
    }
  }

  /// Restores a project from persistence data.
  ///
  /// Creates ProjectState with:
  /// - Persisted name and ID
  /// - Primary worktree with persisted chats
  /// - Linked worktrees with persisted chats
  Future<ProjectState> _restoreProject(
    String projectRoot,
    ProjectInfo projectInfo, {
    required bool autoValidate,
    required bool watchFilesystem,
  }) async {
    // Find the primary worktree and linked worktrees
    WorktreeState? primaryWorktree;
    final linkedWorktrees = <WorktreeState>[];

    for (final entry in projectInfo.worktrees.entries) {
      final worktreePath = entry.key;
      final worktreeInfo = entry.value;

      final worktreeState = await _restoreWorktree(
        worktreePath,
        worktreeInfo,
        projectInfo.id,
        projectRoot,
      );

      if (worktreeInfo.isPrimary) {
        primaryWorktree = worktreeState;
      } else {
        linkedWorktrees.add(worktreeState);
      }
    }

    // If no primary worktree was found, create one at the project root
    if (primaryWorktree == null) {
      developer.log(
        'No primary worktree found, creating at project root',
        name: 'ProjectRestoreService',
      );
      primaryWorktree = WorktreeState(
        WorktreeData(
          worktreeRoot: projectRoot,
          isPrimary: true,
          branch: 'main', // TODO: Get actual branch from git
        ),
      );
    }

    return ProjectState(
      ProjectData(name: projectInfo.name, repoRoot: projectRoot),
      primaryWorktree,
      linkedWorktrees: linkedWorktrees,
      autoValidate: autoValidate,
      watchFilesystem: watchFilesystem,
    );
  }

  /// Restores a worktree from persistence data.
  ///
  /// Creates WorktreeState with:
  /// - Worktree path and type (primary/linked)
  /// - Chats with IDs and names (without loading history)
  Future<WorktreeState> _restoreWorktree(
    String worktreePath,
    WorktreeInfo worktreeInfo,
    String projectId,
    String projectRoot,
  ) async {
    final chats = <ChatState>[];

    for (final chatRef in worktreeInfo.chats) {
      final chatState = await _restoreChat(
        chatRef,
        worktreePath,
        projectId,
        projectRoot,
      );
      chats.add(chatState);
    }

    return WorktreeState(
      WorktreeData(
        worktreeRoot: worktreePath,
        isPrimary: worktreeInfo.isPrimary,
        branch: worktreeInfo.name, // Use the stored name as the branch
      ),
      chats: chats,
      tags: worktreeInfo.tags,
    );
  }

  /// Restores a chat from persistence data.
  ///
  /// Creates ChatState with:
  /// - Chat ID and name from ChatReference
  /// - Model and permission mode from ChatMeta (if exists)
  /// - Last session ID from ChatReference (for session resume)
  /// - Empty entries (history is lazy-loaded)
  Future<ChatState> _restoreChat(
    ChatReference chatRef,
    String worktreePath,
    String projectId,
    String projectRoot,
  ) async {
    // Create ChatData with the persisted values
    final chatData = ChatData(
      id: chatRef.chatId,
      name: chatRef.name,
      worktreeRoot: worktreePath,
      createdAt: null, // Will be loaded from meta if needed
      primaryConversation: ConversationData.primary(
        id: 'conv-primary-${chatRef.chatId}',
      ),
    );

    final chatState = ChatState(chatData);

    // Initialize persistence with both projectId and projectRoot
    // The projectRoot is needed for updating lastSessionId in projects.json
    await chatState.initPersistence(projectId, projectRoot: projectRoot);

    // Load the chat meta to restore model, permission, context, and usage
    final meta = await _persistence.loadChatMeta(projectId, chatRef.chatId);
    _applyMetaToChat(chatState, meta);
    chatState.restoreFromMeta(
      meta.context,
      meta.usage,
      modelUsage: meta.modelUsage,
    );

    // Restore the last session ID for session resume
    if (chatRef.lastSessionId != null) {
      chatState.setLastSessionIdFromRestore(chatRef.lastSessionId);
      developer.log(
        'Restored session ID for chat ${chatRef.chatId}: ${chatRef.lastSessionId}',
        name: 'ProjectRestoreService',
      );
    }

    developer.log(
      'Restored chat: ${chatRef.name} (${chatRef.chatId})',
      name: 'ProjectRestoreService',
    );

    return chatState;
  }

  /// Applies ChatMeta settings to a ChatState.
  void _applyMetaToChat(ChatState chat, ChatMeta meta) {
    // Find the matching model enum
    final model = ClaudeModel.values.firstWhere(
      (m) => m.apiName == meta.model,
      orElse: () => ClaudeModel.opus,
    );
    chat.setModel(model);

    // Find the matching permission mode enum
    final permissionMode = PermissionMode.values.firstWhere(
      (p) => p.apiName == meta.permissionMode,
      orElse: () => PermissionMode.defaultMode,
    );
    chat.setPermissionMode(permissionMode);
  }

  /// Creates a new project and saves it to persistence.
  ///
  /// Creates ProjectState with:
  /// - Generated project ID from path hash
  /// - Project name from directory name
  /// - Empty primary worktree at project root
  Future<ProjectState> _createNewProject(
    String projectRoot,
    String projectId,
    ProjectsIndex currentIndex, {
    required bool autoValidate,
    required bool watchFilesystem,
  }) async {
    // Extract project name from the directory path using path package
    // This handles trailing slashes and other edge cases correctly
    final projectName = p.basename(projectRoot);

    // Create the primary worktree
    final primaryWorktree = WorktreeState(
      WorktreeData(
        worktreeRoot: projectRoot,
        isPrimary: true,
        branch: 'main', // TODO: Get actual branch from git
      ),
    );

    // Create the project
    final project = ProjectState(
      ProjectData(name: projectName, repoRoot: projectRoot),
      primaryWorktree,
      autoValidate: autoValidate,
      watchFilesystem: watchFilesystem,
    );

    // Save to persistence
    await _saveNewProject(projectRoot, projectId, projectName, currentIndex);

    return project;
  }

  /// Saves a new project to projects.json.
  Future<void> _saveNewProject(
    String projectRoot,
    String projectId,
    String projectName,
    ProjectsIndex currentIndex,
  ) async {
    final newProject = ProjectInfo(
      id: projectId,
      name: projectName,
      worktrees: {
        projectRoot: WorktreeInfo.primary(name: 'main'),
      },
    );

    final updatedIndex = currentIndex.copyWith(
      projects: {
        ...currentIndex.projects,
        projectRoot: newProject,
      },
    );

    await _persistence.saveProjectsIndex(updatedIndex);

    developer.log(
      'Saved new project to persistence: $projectName ($projectId)',
      name: 'ProjectRestoreService',
    );
  }

  /// Loads chat history from persistence into a ChatState.
  ///
  /// This should be called when a chat is selected to lazy-load its history.
  /// The entries are added without triggering persistence (they're already
  /// persisted).
  ///
  /// Returns the number of entries loaded.
  Future<int> loadChatHistory(ChatState chat, String projectId) async {
    final entries = await _persistence.loadChatHistory(
      projectId,
      chat.data.id,
    );

    if (entries.isNotEmpty) {
      chat.loadEntriesFromPersistence(entries);
      developer.log(
        'Loaded ${entries.length} entries for chat: ${chat.data.name}',
        name: 'ProjectRestoreService',
      );
    }

    return entries.length;
  }

  /// Adds a new chat to a worktree and persists it.
  ///
  /// Creates the chat files and updates projects.json.
  Future<void> addChatToWorktree(
    String projectRoot,
    String worktreePath,
    ChatState chat,
  ) async {
    final projectId = PersistenceService.generateProjectId(projectRoot);
    await chat.initPersistence(projectId, projectRoot: projectRoot);

    // Update projects.json with the new chat
    final projectsIndex = await _persistence.loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for path: $projectRoot',
        name: 'ProjectRestoreService',
        level: 900, // Warning level
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for path: $worktreePath',
        name: 'ProjectRestoreService',
        level: 900, // Warning level
      );
      return;
    }

    // Add the chat reference
    final chatRef = ChatReference(
      name: chat.data.name,
      chatId: chat.data.id,
    );

    final updatedWorktree = worktree.copyWith(
      chats: [...worktree.chats, chatRef],
    );

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

    await _persistence.saveProjectsIndex(updatedIndex);

    developer.log(
      'Added chat to persistence: ${chat.data.name}',
      name: 'ProjectRestoreService',
    );
  }

  /// Closes a chat and removes all associated data.
  ///
  /// This performs the following cleanup:
  /// 1. Stops any active SDK session
  /// 2. Deletes the chat files from disk (.chat.jsonl and .meta.json)
  /// 3. Removes the chat reference from projects.json
  ///
  /// Note: The caller is responsible for removing the chat from the
  /// WorktreeState (which also calls chat.dispose()).
  Future<void> closeChat(
    String projectRoot,
    String worktreePath,
    ChatState chat,
  ) async {
    final projectId = chat.projectId;
    final chatId = chat.data.id;

    developer.log(
      'Closing chat: ${chat.data.name} ($chatId)',
      name: 'ProjectRestoreService',
    );

    // Stop active session if any
    await chat.stopSession();

    // Delete disk files (existing method)
    if (projectId != null) {
      await _persistence.deleteChat(projectId, chatId);
    }

    // Remove from projects.json index
    await _persistence.removeChatFromIndex(
      projectRoot: projectRoot,
      worktreePath: worktreePath,
      chatId: chatId,
    );

    developer.log(
      'Chat closed: ${chat.data.name}',
      name: 'ProjectRestoreService',
    );
  }
}
