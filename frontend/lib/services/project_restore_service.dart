import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:path/path.dart' as p;

import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/conversation.dart';
import '../models/cost_tracking.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import 'log_service.dart';
import 'persistence_models.dart';
import 'persistence_service.dart';
import 'project_config_service.dart';
import 'runtime_config.dart';

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
  final ProjectConfigService _configService;

  /// Creates a [ProjectRestoreService] with the given services.
  ///
  /// If no services are provided, default instances are created.
  ProjectRestoreService({
    PersistenceService? persistence,
    ProjectConfigService? configService,
  })  : _persistence = persistence ?? PersistenceService(),
        _configService = configService ?? ProjectConfigService();

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
  ///
  /// Worktrees without a base will inherit the project's defaultBase.
  Future<ProjectState> _restoreProject(
    String projectRoot,
    ProjectInfo projectInfo, {
    required bool autoValidate,
    required bool watchFilesystem,
  }) async {
    // Load project config to get defaultBase for worktrees without a base.
    String? defaultBase;
    try {
      final config = await _configService.loadConfig(projectRoot);
      if (config.defaultBase != null &&
          config.defaultBase!.isNotEmpty &&
          config.defaultBase != 'auto') {
        defaultBase = config.defaultBase;
      }
    } catch (_) {
      // Config load failed; worktrees will use auto-detect.
    }

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
        defaultBase: defaultBase,
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
        base: defaultBase,
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
  ///
  /// If the worktree has no base set and [defaultBase] is provided,
  /// the worktree will inherit that base.
  Future<WorktreeState> _restoreWorktree(
    String worktreePath,
    WorktreeInfo worktreeInfo,
    String projectId,
    String projectRoot, {
    String? defaultBase,
  }) async {
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

    // Use the worktree's persisted base, or fall back to the project default.
    final base = worktreeInfo.base ?? defaultBase;

    return WorktreeState(
      WorktreeData(
        worktreeRoot: worktreePath,
        isPrimary: worktreeInfo.isPrimary,
        branch: worktreeInfo.name, // Use the stored name as the branch
      ),
      chats: chats,
      tags: worktreeInfo.tags,
      base: base,
      hidden: worktreeInfo.hidden,
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

    // Load the chat meta to restore model, permission, context, and usage
    var meta = await _persistence.loadChatMeta(projectId, chatRef.chatId);

    // Migrate legacy chats without agentId by matching backendType to first agent
    if (meta.agentId == null) {
      meta = meta.migrateAgentId((driver) {
        final agent = RuntimeConfig.instance.agentByDriver(driver);
        return agent?.id;
      });
    }

    // Validate that the resolved agent still exists in the registry
    String? missingAgentMessage;
    if (meta.agentId != null) {
      final agent = RuntimeConfig.instance.agentById(meta.agentId!);
      if (agent == null) {
        // Agent ID not found — try name+driver fallback
        final name = meta.backendName;
        final driver = _normalizeDriver(meta.backendType);
        if (name != null) {
          final replacement =
              RuntimeConfig.instance.agentByNameAndDriver(name, driver);
          if (replacement != null) {
            meta = meta.copyWith(agentId: replacement.id);
          } else {
            missingAgentMessage = 'Missing agent "$name" of type $driver';
          }
        } else {
          missingAgentMessage = 'Missing agent (ID: ${meta.agentId})';
        }
      }
    }

    final chatState = ChatState(chatData, agentId: meta.agentId);

    // Initialize persistence with both projectId and projectRoot
    // The projectRoot is needed for updating lastSessionId in projects.json
    await chatState.initPersistence(projectId, projectRoot: projectRoot);

    _applyMetaToChat(chatState, meta);
    chatState.setHasStartedFromRestore(meta.hasStarted);
    chatState.restoreFromMeta(
      meta.context,
      meta.usage,
      modelUsage: meta.modelUsage,
      timing: meta.timing,
    );

    // Restore the last session ID for session resume
    if (chatRef.lastSessionId != null) {
      chatState.setLastSessionIdFromRestore(chatRef.lastSessionId);
      developer.log(
        'Restored session ID for chat ${chatRef.chatId}: ${chatRef.lastSessionId}',
        name: 'ProjectRestoreService',
      );
    }

    // Mark as missing agent if validation failed
    if (missingAgentMessage != null) {
      chatState.markAgentMissing(missingAgentMessage);
    }

    developer.log(
      'Restored chat: ${chatRef.name} (${chatRef.chatId})',
      name: 'ProjectRestoreService',
    );

    return chatState;
  }

  /// Normalizes legacy backendType values to driver names.
  static String _normalizeDriver(String backendType) {
    return switch (backendType) {
      'direct' || 'directCli' || 'directcli' || 'cli' => 'claude',
      _ => backendType,
    };
  }

  /// Applies ChatMeta settings to a ChatState.
  void _applyMetaToChat(ChatState chat, ChatMeta meta) {
    final backend = ChatModelCatalog.backendFromValue(meta.backendType);
    chat.setModel(ChatModelCatalog.defaultForBackend(backend, meta.model));

    // Restore security config from meta (notifyChange: false to avoid spurious notifications)
    if (backend == sdk.BackendType.codex && meta.codexSandboxMode != null) {
      // Codex chat with security config
      chat.setSecurityConfig(
        sdk.CodexSecurityConfig(
          sandboxMode: sdk.CodexSandboxMode.fromWire(meta.codexSandboxMode!),
          approvalPolicy: meta.codexApprovalPolicy != null
              ? sdk.CodexApprovalPolicy.fromWire(meta.codexApprovalPolicy!)
              : sdk.CodexApprovalPolicy.onRequest,
          workspaceWriteOptions: meta.codexWorkspaceWriteOptions != null
              ? sdk.CodexWorkspaceWriteOptions.fromJson(meta.codexWorkspaceWriteOptions!)
              : null,
          webSearch: meta.codexWebSearch != null
              ? sdk.CodexWebSearchMode.fromWire(meta.codexWebSearch!)
              : null,
        ),
        notifyChange: false,
      );
    } else {
      // Claude chat or old meta without Codex fields
      chat.setSecurityConfig(
        sdk.ClaudeSecurityConfig(
          permissionMode: sdk.PermissionMode.fromString(meta.permissionMode),
        ),
        notifyChange: false,
      );
    }
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
        projectRoot: const WorktreeInfo.primary(name: 'main'),
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
    try {
      final entries = await _persistence.loadChatHistory(
        projectId,
        chat.data.id,
      );

      if (entries.isNotEmpty) {
        chat.loadEntriesFromPersistence(entries);
        LogService.instance.debug(
          'ProjectRestoreService',
          'Restored chat "${chat.data.name}" (${chat.data.id}): loaded ${entries.length} entries',
          meta: {'chatId': chat.data.id, 'chatName': chat.data.name},
        );
      } else {
        chat.markHistoryAsLoaded();
        LogService.instance.debug(
          'ProjectRestoreService',
          'Chat "${chat.data.name}" (${chat.data.id}): no persisted history',
          meta: {'chatId': chat.data.id, 'chatName': chat.data.name},
        );
      }

      return entries.length;
    } catch (e, stackTrace) {
      LogService.instance.error(
        'ProjectRestoreService',
        'Failed to load chat history: $e',
        meta: {
          'chatId': chat.data.id,
          'chatName': chat.data.name,
          'projectId': projectId,
          'stack': stackTrace.toString(),
        },
      );
      // Mark as loaded anyway to prevent repeated attempts
      chat.markHistoryAsLoaded();
      return 0;
    }
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

  /// Closes a chat, either archiving or deleting all associated data.
  ///
  /// When [archive] is false (default), this performs:
  /// 1. Stops any active SDK session
  /// 2. Saves cost tracking to the project's tracking.jsonl file
  /// 3. Deletes the chat files from disk (.chat.jsonl and .meta.json)
  /// 4. Removes the chat reference from projects.json
  ///
  /// When [archive] is true, this performs:
  /// 1. Stops any active SDK session
  /// 2. Saves cost tracking to the project's tracking.jsonl file
  /// 3. Moves the chat reference to the project's archived chats list
  ///    (files are preserved on disk for potential restore)
  ///
  /// Note: The caller is responsible for removing the chat from the
  /// WorktreeState (which also calls chat.dispose()).
  Future<void> closeChat(
    String projectRoot,
    String worktreePath,
    ChatState chat, {
    bool archive = false,
  }) async {
    final projectId = chat.projectId;
    final chatId = chat.data.id;

    developer.log(
      '${archive ? "Archiving" : "Closing"} chat: ${chat.data.name} ($chatId)',
      name: 'ProjectRestoreService',
    );

    // Stop active session if any
    await chat.stopSession();

    // Save cost tracking before deleting/archiving the chat
    if (projectId != null) {
      await _saveCostTracking(projectId, worktreePath, chat);
    }

    if (archive) {
      // Archive: keep files, move reference to archived list
      try {
        await _persistence.archiveChat(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
        );
      } catch (e, stack) {
        LogService.instance.logUnhandledException(e, stack);
        rethrow;
      }
    } else {
      // Delete: remove files and index entry
      if (projectId != null) {
        await _persistence.deleteChat(projectId, chatId);
      }

      try {
        await _persistence.removeChatFromIndex(
          projectRoot: projectRoot,
          worktreePath: worktreePath,
          chatId: chatId,
        );
      } catch (e, stack) {
        LogService.instance.logUnhandledException(e, stack);
        rethrow;
      }
    }

    developer.log(
      'Chat ${archive ? "archived" : "closed"}: ${chat.data.name}',
      name: 'ProjectRestoreService',
    );
  }

  /// Saves cost tracking for a chat before closure.
  ///
  /// Extracts the worktree name from the path and creates a cost tracking
  /// entry with the chat's final usage totals.
  Future<void> _saveCostTracking(
    String projectId,
    String worktreePath,
    ChatState chat,
  ) async {
    try {
      // Extract worktree name from path (last component)
      final worktreeName = p.basename(worktreePath);

      // Create cost tracking entry from chat's final state
      final entry = CostTrackingEntry.fromChat(
        worktreeName: worktreeName,
        chatName: chat.data.name,
        modelUsage: chat.modelUsage,
        timing: chat.timingStats,
        backend: chat.backendLabel,
      );

      // Append to tracking.jsonl
      await _persistence.appendCostTracking(projectId, entry);
    } catch (e, stack) {
      LogService.instance.logUnhandledException(e, stack);
      // Don't rethrow - cost tracking failures shouldn't block chat closure
    }
  }

  /// Saves cost tracking for all chats in a worktree.
  ///
  /// This should be called before deleting a worktree to preserve the cost
  /// data for all chats. Each chat's cost totals are appended to the project's
  /// tracking.jsonl file.
  ///
  /// The [worktreeState] should be the WorktreeState containing the chats.
  /// The [projectId] identifies which project's tracking file to append to.
  Future<void> saveWorktreeCostTracking(
    String projectId,
    WorktreeState worktreeState,
  ) async {
    final worktreePath = worktreeState.data.worktreeRoot;

    developer.log(
      'Saving cost tracking for ${worktreeState.chats.length} chats in worktree',
      name: 'ProjectRestoreService',
    );

    // Save cost tracking for each chat
    for (final chat in worktreeState.chats) {
      await _saveCostTracking(projectId, worktreePath, chat);
    }

    developer.log(
      'Cost tracking saved for all chats in worktree',
      name: 'ProjectRestoreService',
    );
  }

  /// Restores an archived chat to a worktree.
  ///
  /// This method:
  /// 1. Moves the chat reference from the archived list to the target worktree
  /// 2. Creates a [ChatState] from the persisted chat files
  /// 3. Returns the [ChatState] for the caller to add to the [WorktreeState]
  Future<ChatState> restoreArchivedChat(
    ArchivedChatReference archivedRef,
    String worktreePath,
    String projectId,
    String projectRoot,
  ) async {
    // Move from archived to worktree in persistence
    await _persistence.restoreArchivedChat(
      projectRoot: projectRoot,
      targetWorktreePath: worktreePath,
      chatId: archivedRef.chatId,
    );

    // Reuse existing _restoreChat to create runtime ChatState
    final chatRef = archivedRef.toChatReference();
    return _restoreChat(chatRef, worktreePath, projectId, projectRoot);
  }
}
