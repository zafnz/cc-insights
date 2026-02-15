
import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SelectionState', () {
    // Helper functions for test setup
    WorktreeData createWorktreeData({
      required String path,
      required bool isPrimary,
      String branch = 'main',
    }) {
      return WorktreeData(
        worktreeRoot: path,
        isPrimary: isPrimary,
        branch: branch,
      );
    }

    WorktreeState createWorktreeState({
      required String path,
      required bool isPrimary,
      String branch = 'main',
    }) {
      return WorktreeState(
        createWorktreeData(path: path, isPrimary: isPrimary, branch: branch),
      );
    }

    ProjectState createProjectState() {
      const projectData = ProjectData(name: 'Test Project', repoRoot: '/repo');
      final primaryWorktree = createWorktreeState(
        path: '/repo',
        isPrimary: true,
      );
      return ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    group('constructor', () {
      test('initializes with project', () {
        // Arrange
        final project = createProjectState();

        // Act
        final selection = SelectionState(project);

        // Assert
        check(selection.project).equals(project);
      });
    });

    group('selectedWorktree', () {
      test('delegates to project.selectedWorktree', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedWorktree).equals(project.selectedWorktree);
        check(selection.selectedWorktree).equals(project.primaryWorktree);
      });

      test('reflects changes from project', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final project = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        final selection = SelectionState(project);

        // Act
        project.selectWorktree(linkedWorktree);

        // Assert
        check(selection.selectedWorktree).equals(linkedWorktree);
      });
    });

    group('selectWorktree()', () {
      test('changes selection and notifies listeners', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final project = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        final selection = SelectionState(project);
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectWorktree(linkedWorktree);

        // Assert
        check(selection.selectedWorktree).equals(linkedWorktree);
        check(notified).isTrue();
      });
    });

    group('selectedChat', () {
      test('returns null when no worktree is selected', () {
        // Arrange
        final project = createProjectState();
        project.selectWorktree(null);
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedChat).isNull();
      });

      test('returns null when worktree has no selected chat', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedChat).isNull();
      });

      test('follows hierarchy from worktree', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedChat).equals(chat);
      });

      test('returns null after switching to worktree without chat', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final project = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);

        // Act
        selection.selectWorktree(linkedWorktree);

        // Assert
        check(selection.selectedChat).isNull();
      });
    });

    group('selectChat()', () {
      test('changes selection within current worktree', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat);
        final selection = SelectionState(project);
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectChat(chat);

        // Assert
        check(selection.selectedChat).equals(chat);
        check(notified).isTrue();
      });

      test('does nothing when no worktree is selected', () {
        // Arrange
        final project = createProjectState();
        project.selectWorktree(null);
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        final selection = SelectionState(project);
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectChat(chat);

        // Assert
        check(notified).isTrue(); // Still notifies even if no-op
      });
    });

    group('selectedConversation', () {
      test('returns null when no chat is selected', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedConversation).isNull();
      });

      test('returns primary conversation by default', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedConversation).isNotNull();
        check(selection.selectedConversation!.isPrimary).isTrue();
      });

      test('follows chat conversation selection', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        chat.addSubagentConversation('agent-1', 'Explore', 'Task');
        project.primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);

        final subagentConv = chat.data.subagentConversations.values.first;
        chat.selectConversation(subagentConv.id);

        // Assert
        check(selection.selectedConversation).isNotNull();
        check(selection.selectedConversation!.id).equals(subagentConv.id);
        check(selection.selectedConversation!.isPrimary).isFalse();
      });
    });

    group('selectConversation()', () {
      test('selects primary conversation with null ID', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        chat.addSubagentConversation('agent-1', 'Explore', null);
        project.primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);

        final subagentConv = chat.data.subagentConversations.values.first;
        chat.selectConversation(subagentConv.id);
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectConversation(chat.data.primaryConversation);

        // Assert
        check(selection.selectedConversation!.isPrimary).isTrue();
        check(notified).isTrue();
      });

      test('selects subagent conversation by ID', () {
        // Arrange
        final project = createProjectState();
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/repo');
        chat.addSubagentConversation('agent-1', 'Explore', null);
        project.primaryWorktree.addChat(chat, select: true);
        final selection = SelectionState(project);
        final subagentConv = chat.data.subagentConversations.values.first;
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectConversation(subagentConv);

        // Assert
        check(selection.selectedConversation!.id).equals(subagentConv.id);
        check(notified).isTrue();
      });
    });

    group('file selection', () {
      test('selectedFilePath is null initially', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);

        // Assert
        check(selection.selectedFilePath).isNull();
      });

      test('selectFile() updates path and notifies', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.selectFile('/path/to/file.dart');

        // Assert
        check(selection.selectedFilePath).equals('/path/to/file.dart');
        check(notified).isTrue();
      });

      test('selectFile() does not notify for same path', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);
        selection.selectFile('/path/to/file.dart');
        var notifyCount = 0;
        selection.addListener(() => notifyCount++);

        // Act
        selection.selectFile('/path/to/file.dart');

        // Assert
        check(notifyCount).equals(0);
      });

      test('clearFileSelection() clears path', () {
        // Arrange
        final project = createProjectState();
        final selection = SelectionState(project);
        selection.selectFile('/path/to/file.dart');
        var notified = false;
        selection.addListener(() => notified = true);

        // Act
        selection.clearFileSelection();

        // Assert
        check(selection.selectedFilePath).isNull();
        check(notified).isTrue();
      });

      test('file selection is independent of entity hierarchy', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final project = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        final selection = SelectionState(project);
        selection.selectFile('/path/to/file.dart');

        // Act - change worktree
        selection.selectWorktree(linkedWorktree);

        // Assert - file selection preserved
        check(selection.selectedFilePath).equals('/path/to/file.dart');
      });
    });

    group('lazy history loading', () {
      test('selectChat triggers history loading for unloaded chat', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService();
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat);

        // Act
        selection.selectChat(chat);

        // Allow async loading to complete
        await Future<void>.delayed(Duration.zero);

        // Assert
        check(fakeRestoreService.loadChatHistoryCalls).isNotEmpty();
        check(fakeRestoreService.loadChatHistoryCalls.first.chat).equals(chat);
      });

      test('selectChat does not load history if already loaded', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService();
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        // Mark history as already loaded to simulate a previously loaded chat
        chat.markHistoryAsLoaded();
        project.primaryWorktree.addChat(chat);

        // Act
        selection.selectChat(chat);

        // Allow async processing
        await Future<void>.delayed(Duration.zero);

        // Assert - no loading should have occurred
        check(fakeRestoreService.loadChatHistoryCalls).isEmpty();
      });

      test('hasLoadedHistory returns false for empty chat', () {
        // Arrange
        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');

        // Assert
        check(chat.hasLoadedHistory).isFalse();
      });

      test('hasLoadedHistory returns true when marked as loaded', () {
        // Arrange
        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        chat.markHistoryAsLoaded();

        // Assert
        check(chat.hasLoadedHistory).isTrue();
      });

      test('selectChat sets isLoadingChatHistory during load', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService();
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat);

        // Act
        selection.selectChat(chat);

        // Assert - loading should have started and completed
        await Future<void>.delayed(Duration.zero);
        check(selection.isLoadingChatHistory).isFalse();
      });

      test('selectChat handles loading errors gracefully', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService(
          shouldThrowOnLoad: true,
        );
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        project.primaryWorktree.addChat(chat);

        // Act - should not throw
        selection.selectChat(chat);

        // Allow async error handling
        await Future<void>.delayed(Duration.zero);

        // Assert - chat should still be selected despite error
        check(selection.selectedChat).equals(chat);
        // Error should be set
        check(selection.chatHistoryError).isNotNull();
        check(selection.chatHistoryError!).contains('Test Chat');
        // Loading should be false
        check(selection.isLoadingChatHistory).isFalse();
      });

      test('selecting new chat clears previous error', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService(
          shouldThrowOnLoad: true,
        );
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat1 = ChatState.create(name: 'Chat 1', worktreeRoot: '/repo');
        final chat2 = ChatState.create(name: 'Chat 2', worktreeRoot: '/repo');
        chat2.markHistoryAsLoaded();
        project.primaryWorktree.addChat(chat1);
        project.primaryWorktree.addChat(chat2);

        // Trigger error on first chat
        selection.selectChat(chat1);
        await Future<void>.delayed(Duration.zero);
        check(selection.chatHistoryError).isNotNull();

        // Act - select second chat
        selection.selectChat(chat2);

        // Assert - error should be cleared
        check(selection.chatHistoryError).isNull();
      });

      test('selectChat resets to primary conversation', () async {
        // Arrange
        final project = createProjectState();
        final fakeRestoreService = _FakeProjectRestoreService();
        final selection = SelectionState(project, restoreService: fakeRestoreService);

        final chat = ChatState.create(name: 'Test Chat', worktreeRoot: '/repo');
        chat.addSubagentConversation('agent-1', 'Explore', 'task');
        final subagentConv = chat.data.subagentConversations.values.first;
        chat.selectConversation(subagentConv.id);
        project.primaryWorktree.addChat(chat);

        // Pre-condition: subagent is selected
        check(chat.selectedConversation.isPrimary).isFalse();

        // Act
        selection.selectChat(chat);

        // Assert - should reset to primary
        check(chat.selectedConversation.isPrimary).isTrue();
      });
    });
  });
}

/// Fake ProjectRestoreService for testing lazy loading.
class _FakeProjectRestoreService extends ProjectRestoreService {
  final List<_LoadChatHistoryCall> loadChatHistoryCalls = [];
  final bool shouldThrowOnLoad;
  final int entriesToLoad = 0;

  _FakeProjectRestoreService({
    this.shouldThrowOnLoad = false,
  });

  @override
  Future<int> loadChatHistory(ChatState chat, String projectId) async {
    loadChatHistoryCalls.add(_LoadChatHistoryCall(
      chat: chat,
      projectId: projectId,
    ));

    if (shouldThrowOnLoad) {
      throw Exception('Simulated load error');
    }

    // Simulate loading entries if configured
    if (entriesToLoad > 0) {
      final entries = List.generate(
        entriesToLoad,
        (i) => UserInputEntry(
          timestamp: DateTime.now(),
          text: 'Entry $i',
        ),
      );
      chat.loadEntriesFromPersistence(entries);
    }

    return entriesToLoad;
  }
}

/// Record of a call to loadChatHistory.
class _LoadChatHistoryCall {
  final ChatState chat;
  final String projectId;

  _LoadChatHistoryCall({
    required this.chat,
    required this.projectId,
  });
}
