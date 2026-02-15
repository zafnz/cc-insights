part of 'persistence_service.dart';

/// Mixin for chat archive methods.
mixin _ArchiveMixin on _PersistenceBase {
  /// Archives a chat by moving it from a worktree's chat list to the project's
  /// archived chats list. Does NOT delete the chat files from disk.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> archiveChat({
    required String projectRoot,
    required String worktreePath,
    required String chatId,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for chat archive: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null) {
      developer.log(
        'Worktree not found for chat archive: $worktreePath',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    // Find the chat reference to archive
    final chatRef = worktree.chats.where((c) => c.chatId == chatId).firstOrNull;
    if (chatRef == null) {
      developer.log(
        'Chat not found for archive: $chatId',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    // Create archived reference and remove from worktree
    final archivedRef = ArchivedChatReference.fromChatReference(
      chatRef,
      worktreePath: worktreePath,
    );
    final updatedChats =
        worktree.chats.where((c) => c.chatId != chatId).toList();

    final updatedWorktree = worktree.copyWith(chats: updatedChats);
    final updatedProject = project.copyWith(
      worktrees: {
        ...project.worktrees,
        worktreePath: updatedWorktree,
      },
      archivedChats: [...project.archivedChats, archivedRef],
    );
    final updatedIndex = projectsIndex.copyWith(
      projects: {
        ...projectsIndex.projects,
        projectRoot: updatedProject,
      },
    );

    await saveProjectsIndex(updatedIndex);

    developer.log(
      'Archived chat $chatId from worktree $worktreePath',
      name: 'PersistenceService',
    );
  }

  /// Restores an archived chat by moving it from the project's archived chats
  /// list to a worktree's chat list.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> restoreArchivedChat({
    required String projectRoot,
    required String targetWorktreePath,
    required String chatId,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project == null) {
        developer.log(
          'Project not found for chat restore: $projectRoot',
          name: 'PersistenceService',
          level: _PersistenceBase._kWarningLevel,
        );
        return;
      }

      // Find the archived chat reference
      final archivedRef =
          project.archivedChats.where((c) => c.chatId == chatId).firstOrNull;
      if (archivedRef == null) {
        developer.log(
          'Archived chat not found for restore: $chatId',
          name: 'PersistenceService',
          level: _PersistenceBase._kWarningLevel,
        );
        return;
      }

      final worktree = project.worktrees[targetWorktreePath];
      if (worktree == null) {
        developer.log(
          'Target worktree not found for chat restore: $targetWorktreePath',
          name: 'PersistenceService',
          level: _PersistenceBase._kWarningLevel,
        );
        return;
      }

      // Move from archived to worktree
      final chatRef = archivedRef.toChatReference();
      final updatedArchived =
          project.archivedChats.where((c) => c.chatId != chatId).toList();
      final updatedWorktree = worktree.copyWith(
        chats: [...worktree.chats, chatRef],
      );
      final updatedProject = project.copyWith(
        worktrees: {
          ...project.worktrees,
          targetWorktreePath: updatedWorktree,
        },
        archivedChats: updatedArchived,
      );
      final updatedIndex = projectsIndex.copyWith(
        projects: {
          ...projectsIndex.projects,
          projectRoot: updatedProject,
        },
      );

      await saveProjectsIndex(updatedIndex);

      developer.log(
        'Restored archived chat $chatId to worktree $targetWorktreePath',
        name: 'PersistenceService',
      );
    } catch (e) {
      developer.log(
        'Failed to restore archived chat $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Archives all chats in a worktree. Used before worktree deletion/hiding
  /// when the archive setting is enabled.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> archiveWorktreeChats({
    required String projectRoot,
    required String worktreePath,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for worktree chat archive: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final worktree = project.worktrees[worktreePath];
    if (worktree == null || worktree.chats.isEmpty) {
      return;
    }

    // Archive all chats
    final archivedRefs = worktree.chats
        .map((chatRef) => ArchivedChatReference.fromChatReference(
              chatRef,
              worktreePath: worktreePath,
            ))
        .toList();

    final updatedWorktree = worktree.copyWith(chats: []);
    final updatedProject = project.copyWith(
      worktrees: {
        ...project.worktrees,
        worktreePath: updatedWorktree,
      },
      archivedChats: [...project.archivedChats, ...archivedRefs],
    );
    final updatedIndex = projectsIndex.copyWith(
      projects: {
        ...projectsIndex.projects,
        projectRoot: updatedProject,
      },
    );

    await saveProjectsIndex(updatedIndex);

    developer.log(
      'Archived ${archivedRefs.length} chats from worktree $worktreePath',
      name: 'PersistenceService',
    );
  }

  /// Returns all archived chats for a project.
  Future<List<ArchivedChatReference>> getArchivedChats({
    required String projectRoot,
  }) async {
    try {
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];
      return project?.archivedChats ?? [];
    } catch (e) {
      developer.log(
        'Failed to load archived chats: $e',
        name: 'PersistenceService',
        error: e,
      );
      return [];
    }
  }

  /// Permanently deletes an archived chat (both files and index entry).
  Future<void> deleteArchivedChat({
    required String projectRoot,
    required String projectId,
    required String chatId,
  }) async {
    try {
      // Remove from archived list in index
      final projectsIndex = await loadProjectsIndex();
      final project = projectsIndex.projects[projectRoot];

      if (project != null) {
        final updatedArchived =
            project.archivedChats.where((c) => c.chatId != chatId).toList();
        final updatedProject =
            project.copyWith(archivedChats: updatedArchived);
        final updatedIndex = projectsIndex.copyWith(
          projects: {
            ...projectsIndex.projects,
            projectRoot: updatedProject,
          },
        );
        await saveProjectsIndex(updatedIndex);
      }

      // Delete the actual files
      await deleteChat(projectId, chatId);

      developer.log(
        'Permanently deleted archived chat $chatId',
        name: 'PersistenceService',
      );
    } catch (e) {
      developer.log(
        'Failed to delete archived chat $chatId: $e',
        name: 'PersistenceService',
        error: e,
      );
    }
  }

  /// Updates the default worktree root for a project in projects.json.
  ///
  /// This sets the default parent directory used when creating new worktrees.
  /// Pass null for [defaultWorktreeRoot] to clear the override and revert to
  /// the calculated default.
  ///
  /// Throws on failure — callers are responsible for error handling.
  Future<void> updateProjectDefaultWorktreeRoot({
    required String projectRoot,
    required String? defaultWorktreeRoot,
  }) async {
    final projectsIndex = await loadProjectsIndex();
    final project = projectsIndex.projects[projectRoot];

    if (project == null) {
      developer.log(
        'Project not found for default worktree root update: $projectRoot',
        name: 'PersistenceService',
        level: _PersistenceBase._kWarningLevel,
      );
      return;
    }

    final updatedProject = ProjectInfo(
      id: project.id,
      name: project.name,
      worktrees: project.worktrees,
      defaultWorktreeRoot: defaultWorktreeRoot,
    );
    final updatedIndex = projectsIndex.copyWith(
      projects: {
        ...projectsIndex.projects,
        projectRoot: updatedProject,
      },
    );

    await saveProjectsIndex(updatedIndex);

    developer.log(
      'Updated default worktree root for project $projectRoot: '
      '${defaultWorktreeRoot ?? 'cleared'}',
      name: 'PersistenceService',
    );
  }
}
