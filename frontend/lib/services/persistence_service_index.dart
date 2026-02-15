part of 'persistence_service.dart';

/// Mixin for index manipulation methods.
mixin _IndexMixin on _PersistenceBase {
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
  /// Throws on failure — callers are responsible for error handling.
  Future<void> updateChatSessionId({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String? sessionId,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for session ID update: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for session ID update: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
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
  }

  /// Renames a chat in the projects.json index.
  ///
  /// This updates the chat name in the worktree's chat list in projects.json.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> renameChatInIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
    required String newName,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for chat rename: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for chat rename: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
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
  }

  /// Removes a chat reference from the projects.json index.
  ///
  /// This removes the chat from the worktree's chat list in projects.json.
  /// Does not delete the chat files from disk - use [deleteChat] for that.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> removeChatFromIndex({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for chat removal: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for chat removal: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
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
  }

  /// Updates the tags assigned to a worktree in projects.json.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> updateWorktreeTags({
    required String projectRoot,
    required String worktreePath,
    required List<String> tags,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for tag update: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for tag update: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
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
  }

  /// Updates the base branch for a worktree in projects.json.
  ///
  /// Pass null for [base] to clear and revert to the project default.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> updateWorktreeBase({
    required String projectRoot,
    required String worktreePath,
    required String? base,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for base update: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for base update: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final updatedWorktree = base != null
        ? worktree.copyWith(base: base)
        : worktree.copyWith(clearBase: true);
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
      'Updated base for worktree $worktreePath: '
      '${base ?? 'cleared'}',
      name: 'PersistenceService',
    );
  }

  /// Hides a worktree by setting `hidden: true` in projects.json.
  ///
  /// The worktree entry remains in projects.json with its chats and tags
  /// preserved. Hidden worktrees are filtered from the UI by default but
  /// can be shown via a toggle in the worktree panel header.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> hideWorktreeFromIndex({
    required String projectRoot,
    required String worktreePath,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for worktree hide: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for hide: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    // Set hidden flag on the worktree
    final updatedWorktree = worktree.copyWith(hidden: true);
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
      'Hidden worktree $worktreePath in projects.json (hidden flag set)',
      name: 'PersistenceService',
    );
  }

  /// Unhides a worktree by setting `hidden: false` in projects.json.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> unhideWorktreeFromIndex({
    required String projectRoot,
    required String worktreePath,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for worktree unhide: $projectRoot',
          name: 'PersistenceService',
          level: _PersistenceBase._kWarningLevel,
        );
        return;
      }

      final worktree = project.worktrees[worktreePath];
      if (worktree == null) {
        developer.log(
          'Worktree not found for unhide: $worktreePath',
          name: 'PersistenceService',
          level: _PersistenceBase._kWarningLevel,
        );
        return;
      }

      final updatedWorktree = worktree.copyWith(hidden: false);
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
        'Unhidden worktree $worktreePath in projects.json',
        name: 'PersistenceService',
      );
    } catch (e) {
      developer.log(
        'Failed to unhide worktree $worktreePath: $e',
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
        level: _PersistenceBase._kWarningLevel,
      );
      return [];
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for removal: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
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
}
