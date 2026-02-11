
import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileManagerState', () {
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

    ProjectState createProjectState({
      String name = 'Test Project',
      String repoRoot = '/repo',
    }) {
      final projectData = ProjectData(name: name, repoRoot: repoRoot);
      final primaryWorktree = createWorktreeState(
        path: repoRoot,
        isPrimary: true,
      );
      return ProjectState(
        projectData,
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    SelectionState createSelectionState(ProjectState project) {
      return SelectionState(project);
    }

    FakeFileSystemService createFakeFileSystem() {
      final service = FakeFileSystemService();
      // Set up a basic file tree
      service.addDirectory('/repo');
      service.addDirectory('/repo/src');
      service.addTextFile('/repo/src/main.dart', 'void main() {}');
      service.addTextFile('/repo/README.md', '# Test Project');
      return service;
    }

    group('constructor', () {
      test('initializes with project and file system service', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.project).equals(project);
      });
    });

    group('initial state', () {
      test('selectedWorktree syncs with SelectionState on construction', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        // ProjectState defaults to selecting the primary worktree, so
        // FileManagerState should sync with that selection on construction
        check(state.selectedWorktree).equals(project.primaryWorktree);
      });

      test('rootNode is null initially', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.rootNode).isNull();
      });

      test('selectedFilePath is null initially', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.selectedFilePath).isNull();
      });

      test('fileContent is null initially', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.fileContent).isNull();
      });

      test('isLoadingTree starts loading since synced with SelectionState', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        // Since ProjectState defaults to selecting the primary worktree,
        // FileManagerState will sync with SelectionState and start loading
        // the tree immediately. After the event queue processes, it completes.
        await pumpEventQueue();
        check(state.isLoadingTree).isFalse();
      });

      test('isLoadingFile is false initially', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.isLoadingFile).isFalse();
      });

      test('error is null initially', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();

        // Act
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Assert
        check(state.error).isNull();
      });
    });

    group('selectWorktree()', () {
      test('sets selectedWorktree and notifies listeners', () async {
        // Arrange
        final project = createProjectState();
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);
        final fileService = createFakeFileSystem();
        fileService.addDirectory('/repo-linked');
        final state = FileManagerState(project, fileService, createSelectionState(project));

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act - select a DIFFERENT worktree (not the default primary)
        state.selectWorktree(linkedWorktree);

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree);
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('clears previous tree and file selection', () async {
        // Arrange
        final project = createProjectState();
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);
        final fileService = createFakeFileSystem();
        fileService.addDirectory('/repo-linked');
        fileService.addTextFile('/repo-linked/file.txt', 'content');

        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Select first worktree and file
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        // Verify setup
        check(state.selectedFilePath).isNotNull();

        // Act - select different worktree
        state.selectWorktree(linkedWorktree);

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree);
        check(state.selectedFilePath).isNull();
        check(state.fileContent).isNull();
        check(state.rootNode).isNull();
      });

      test('triggers tree build for selected worktree', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));
        final worktree = project.primaryWorktree;

        // Act
        state.selectWorktree(worktree);
        await pumpEventQueue();

        // Assert
        check(state.rootNode).isNotNull();
        check(state.rootNode!.isDirectory).isTrue();
        check(state.rootNode!.path).equals('/repo');
      });

      test('does nothing when selecting same worktree', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));
        final worktree = project.primaryWorktree;

        state.selectWorktree(worktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.selectWorktree(worktree);

        // Assert
        check(notifyCount).equals(0);
      });

      test('clears error when selecting new worktree', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        // Do not add the directory to simulate error
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Verify error occurred
        check(state.error).isNotNull();

        // Now add directory and select again
        fileService.addDirectory('/repo');

        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);
        fileService.addDirectory('/repo-linked');

        // Act
        state.selectWorktree(linkedWorktree);
        await pumpEventQueue();

        // Assert - error cleared when selecting new worktree
        check(state.error).isNull();
      });
    });

    group('refreshFileTree()', () {
      test('rebuilds tree for current worktree', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Add a new file to the fake file system
        fileService.addTextFile('/repo/new_file.txt', 'new content');

        // Act
        await state.refreshFileTree();

        // Assert
        check(state.rootNode).isNotNull();
        final fileNames = state.rootNode!.children.map((c) => c.name).toList();
        check(fileNames).contains('new_file.txt');
      });

      test('refreshFileTree works when worktree is selected via SelectionState', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Wait for initial sync to complete
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act - refresh the already loaded tree
        await state.refreshFileTree();

        // Assert - tree should be loaded since worktree is selected by default
        check(state.rootNode).isNotNull();
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('sets isLoadingTree during operation', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.delay = const Duration(milliseconds: 50);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);

        // Assert - loading state should be true during operation
        check(state.isLoadingTree).isTrue();

        await pumpEventQueue(times: 10);

        // Assert - loading state should be false after completion
        check(state.isLoadingTree).isFalse();
      });

      test('notifies listeners on completion', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        await state.refreshFileTree();

        // Assert
        check(notifyCount).isGreaterOrEqual(1);
      });
    });

    group('selectFile()', () {
      test('sets selectedFilePath and notifies listeners', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.selectFile('/repo/src/main.dart');

        // Assert
        check(state.selectedFilePath).equals('/repo/src/main.dart');
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('triggers file content loading', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Act
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.dart);
        check(state.fileContent!.textContent).equals('void main() {}');
      });

      test('does nothing when selecting same file', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.selectFile('/repo/src/main.dart');

        // Assert
        check(notifyCount).equals(0);
      });

      test('clears previous file content when selecting new file', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/file1.dart', 'content 1');
        fileService.addTextFile('/repo/file2.dart', 'content 2');
        fileService.delay = const Duration(milliseconds: 10);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 5);

        state.selectFile('/repo/file1.dart');
        await pumpEventQueue(times: 5);

        check(state.fileContent).isNotNull();

        // Act
        state.selectFile('/repo/file2.dart');

        // Assert - file content cleared immediately
        check(state.fileContent).isNull();

        await pumpEventQueue(times: 5);

        // After loading, new content is available
        check(state.fileContent).isNotNull();
        check(state.fileContent!.textContent).equals('content 2');
      });
    });

    group('loadFileContent()', () {
      test('loads file content and notifies', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/README.md');

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        await state.loadFileContent('/repo/README.md');

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.markdown);
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('sets isLoadingFile during operation', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/file.txt', 'content');
        fileService.delay = const Duration(milliseconds: 50);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 10);
        state.selectFile('/repo/file.txt');

        // Assert - loading state should be true during operation
        check(state.isLoadingFile).isTrue();

        await pumpEventQueue(times: 10);

        // Assert - loading state should be false after completion
        check(state.isLoadingFile).isFalse();
      });

      test('handles file not found error', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/nonexistent.txt');

        // Act
        await state.loadFileContent('/repo/nonexistent.txt');

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.isError).isTrue();
        check(state.fileContent!.error!.contains('File not found')).isTrue();
      });

      test('ignores result if file selection changed during load', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/file1.txt', 'content 1');
        fileService.addTextFile('/repo/file2.txt', 'content 2');
        fileService.delay = const Duration(milliseconds: 50);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 15);

        // Start loading file1
        state.selectFile('/repo/file1.txt');

        // Immediately select file2 before file1 finishes loading
        state.selectFile('/repo/file2.txt');

        await pumpEventQueue(times: 15);

        // Assert - should have file2 content, not file1
        check(state.selectedFilePath).equals('/repo/file2.txt');
        check(state.fileContent).isNotNull();
        check(state.fileContent!.textContent).equals('content 2');
      });
    });

    group('toggleExpanded()', () {
      test('toggles directory expansion state', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Verify src directory exists and is not expanded
        check(state.rootNode!.children.any((c) => c.name == 'src')).isTrue();
        check(state.isExpanded('/repo/src')).isFalse();

        // Act
        state.toggleExpanded('/repo/src');

        // Assert - expanded state is tracked separately from tree nodes
        check(state.isExpanded('/repo/src')).isTrue();
      });

      test('toggles back to collapsed', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Expand first
        state.toggleExpanded('/repo/src');
        check(state.isExpanded('/repo/src')).isTrue();

        // Act - toggle again to collapse
        state.toggleExpanded('/repo/src');

        // Assert
        check(state.isExpanded('/repo/src')).isFalse();
      });

      test('notifies listeners', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.toggleExpanded('/repo/src');

        // Assert
        check(notifyCount).equals(1);
      });

      test('does nothing when rootNode is null', () {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.toggleExpanded('/repo/src');

        // Assert
        check(notifyCount).equals(0);
      });

      test('does nothing when path not found', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        final originalTree = state.rootNode;
        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.toggleExpanded('/nonexistent/path');

        // Assert - still notifies but tree should be unchanged
        check(state.rootNode).equals(originalTree);
      });

      test('handles nested directory toggle', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addDirectory('/repo/src');
        fileService.addDirectory('/repo/src/widgets');
        fileService.addTextFile('/repo/src/widgets/button.dart', 'button');
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Act - toggle nested directory
        state.toggleExpanded('/repo/src/widgets');

        // Assert - expanded state is tracked by path
        check(state.isExpanded('/repo/src/widgets')).isTrue();
      });
    });

    group('clearFileSelection()', () {
      test('clears selectedFilePath and fileContent', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        check(state.selectedFilePath).isNotNull();
        check(state.fileContent).isNotNull();

        // Act
        state.clearFileSelection();

        // Assert
        check(state.selectedFilePath).isNull();
        check(state.fileContent).isNull();
      });

      test('notifies listeners', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.clearFileSelection();

        // Assert
        check(notifyCount).equals(1);
      });
    });

    group('clearSelection()', () {
      test('clears file manager internal state but not worktree selection', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        // Act
        state.clearSelection();

        // Assert
        // Note: selectedWorktree is NOT cleared because it's managed by SelectionState
        // clearSelection only clears file manager's internal state (file tree, file content, etc.)
        check(state.rootNode).isNull();
        check(state.selectedFilePath).isNull();
        check(state.fileContent).isNull();
        check(state.error).isNull();
        check(state.isLoadingTree).isFalse();
        check(state.isLoadingFile).isFalse();
      });

      test('notifies listeners', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.clearSelection();

        // Assert
        check(notifyCount).equals(1);
      });
    });

    group('error handling', () {
      test('tree build failure sets error', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        // Do not add directory to cause error
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Assert
        check(state.error).isNotNull();
        check(state.error!.contains('Directory does not exist')).isTrue();
        check(state.rootNode).isNull();
      });

      test('tree build failure clears loading state', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        // Do not add directory to cause error
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Assert
        check(state.isLoadingTree).isFalse();
      });

      test('file read failure returns error content', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Act
        state.selectFile('/repo/nonexistent.txt');
        await pumpEventQueue();

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.isError).isTrue();
      });

      test('file read failure clears loading state', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        // Act
        state.selectFile('/repo/nonexistent.txt');
        await pumpEventQueue();

        // Assert
        check(state.isLoadingFile).isFalse();
      });
    });

    group('loading states', () {
      test('isLoadingTree is true while building tree', () async {
        // Arrange
        final project = createProjectState();
        // Add a linked worktree so we can switch to it later
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);

        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addDirectory('/repo-linked');
        fileService.delay = const Duration(milliseconds: 100);

        final loadingStates = <bool>[];

        // Create state - it will immediately sync with SelectionState and
        // start loading the tree for the primary worktree
        final selectionState = createSelectionState(project);
        final state = FileManagerState(project, fileService, selectionState);

        // Now add listener and switch to a different worktree to trigger
        // a new tree load that we can observe
        state.addListener(() {
          loadingStates.add(state.isLoadingTree);
        });

        // Switch to linked worktree to trigger a new tree load
        state.selectWorktree(linkedWorktree);

        // Wait for the async tree build to complete
        await pumpEventQueue(times: 20);

        // Should have seen loading = true at some point during the operation
        check(loadingStates.contains(true)).isTrue();

        // Last notification should have loading = false (completed)
        check(loadingStates.last).isFalse();
      });

      test('isLoadingFile is true while loading file', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/file.txt', 'content');
        fileService.delay = const Duration(milliseconds: 100);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 15);

        final loadingStates = <bool>[];
        state.addListener(() {
          loadingStates.add(state.isLoadingFile);
        });

        // Act
        state.selectFile('/repo/file.txt');

        await pumpEventQueue(times: 15);

        // Should have seen loading = true at some point during the operation
        check(loadingStates.contains(true)).isTrue();

        // Last notification should have loading = false (completed)
        check(loadingStates.last).isFalse();
      });
    });

    group('notifyListeners', () {
      test('notifies on selectWorktree for a different worktree', () async {
        // Arrange
        final project = createProjectState();
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);
        final fileService = createFakeFileSystem();
        fileService.addDirectory('/repo-linked');
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Wait for initial sync to complete
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act - select a different worktree
        state.selectWorktree(linkedWorktree);

        // Assert - at least one notification for selection change
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('notifies on selectFile', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.selectFile('/repo/src/main.dart');

        // Assert
        check(notifyCount).isGreaterOrEqual(1);
      });

      test('notifies on toggleExpanded', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.toggleExpanded('/repo/src');

        // Assert
        check(notifyCount).equals(1);
      });

      test('notifies on clearFileSelection', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();
        state.selectFile('/repo/src/main.dart');
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.clearFileSelection();

        // Assert
        check(notifyCount).equals(1);
      });

      test('notifies on clearSelection', () async {
        // Arrange
        final project = createProjectState();
        final fileService = createFakeFileSystem();
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue();

        var notifyCount = 0;
        state.addListener(() => notifyCount++);

        // Act
        state.clearSelection();

        // Assert
        check(notifyCount).equals(1);
      });
    });

    group('race condition handling', () {
      test('selecting new file while loading discards old result', () async {
        // Arrange
        final project = createProjectState();
        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/slow.dart', 'slow content');
        fileService.addTextFile('/repo/fast.dart', 'fast content');
        fileService.delay = const Duration(milliseconds: 50);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 10);

        // Act - start loading slow file
        state.selectFile('/repo/slow.dart');

        // Immediately select fast file before slow finishes
        await Future<void>.delayed(const Duration(milliseconds: 10));
        state.selectFile('/repo/fast.dart');

        await pumpEventQueue(times: 15);

        // Assert - should have fast content, not slow
        check(state.selectedFilePath).equals('/repo/fast.dart');
        check(state.fileContent).isNotNull();
        check(state.fileContent!.textContent).equals('fast content');
      });

      test('selecting new worktree while loading discards old tree', () async {
        // Arrange
        final project = createProjectState();
        final linkedWorktree = createWorktreeState(
          path: '/linked',
          isPrimary: false,
        );
        project.addLinkedWorktree(linkedWorktree);

        final fileService = FakeFileSystemService();
        fileService.addDirectory('/repo');
        fileService.addTextFile('/repo/file.txt', 'repo content');
        fileService.addDirectory('/linked');
        fileService.addTextFile('/linked/file.txt', 'linked content');
        fileService.delay = const Duration(milliseconds: 50);
        final state = FileManagerState(project, fileService, createSelectionState(project));

        // Act - start loading repo tree
        state.selectWorktree(project.primaryWorktree);

        // Immediately select linked worktree before repo finishes
        await Future<void>.delayed(const Duration(milliseconds: 10));
        state.selectWorktree(linkedWorktree);

        await pumpEventQueue(times: 15);

        // Assert - should have linked tree, not repo tree
        check(state.selectedWorktree).equals(linkedWorktree);
        check(state.rootNode).isNotNull();
        check(state.rootNode!.path).equals('/linked');
      });
    });
  });
}

/// Helper to pump the event queue allowing async operations to complete.
Future<void> pumpEventQueue({int times = 5}) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
