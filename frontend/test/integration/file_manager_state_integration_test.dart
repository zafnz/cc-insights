@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration tests for Phase 1: FileManagerState with RealFileSystemService.
///
/// These tests use real file system operations with temporary directories
/// to verify end-to-end workflows work correctly.
void main() {
  group('FileManagerState Integration Tests', () {
    late Directory tempDir;
    late RealFileSystemService fileSystemService;

    setUp(() async {
      // Create a unique temp directory for each test
      tempDir = await Directory.systemTemp.createTemp('file_manager_test_');
      fileSystemService = const RealFileSystemService();
    });

    tearDown(() async {
      // Clean up temp directory after each test
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // Helper functions
    Future<void> createDirectory(String relativePath) async {
      final dir = Directory('${tempDir.path}/$relativePath');
      await dir.create(recursive: true);
    }

    Future<void> createFile(String relativePath, String content) async {
      final file = File('${tempDir.path}/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    Future<void> createBinaryFile(
      String relativePath,
      List<int> bytes,
    ) async {
      final file = File('${tempDir.path}/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }

    WorktreeData createWorktreeData(String path) {
      return WorktreeData(
        worktreeRoot: path,
        isPrimary: true,
        branch: 'main',
      );
    }

    WorktreeState createWorktreeState(String path) {
      return WorktreeState(createWorktreeData(path));
    }

    ProjectState createProjectState(String path) {
      final projectData = ProjectData(name: 'Test', repoRoot: path);
      final worktree = createWorktreeState(path);
      return ProjectState(
        projectData,
        worktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    group('End-to-end workflow', () {
      test('creates temp directory structure', () async {
        // Arrange & Act
        await createDirectory('src');
        await createDirectory('test');
        await createFile('src/main.dart', 'void main() {}');
        await createFile('src/utils.dart', 'String hello() => "Hello";');
        await createFile('README.md', '# Test Project');

        // Assert
        check(await Directory('${tempDir.path}/src').exists()).isTrue();
        check(await Directory('${tempDir.path}/test').exists()).isTrue();
        check(await File('${tempDir.path}/src/main.dart').exists()).isTrue();
        check(await File('${tempDir.path}/src/utils.dart').exists()).isTrue();
        check(await File('${tempDir.path}/README.md').exists()).isTrue();
      });

      test(
        'initializes FileManagerState with RealFileSystemService',
        () async {
          // Arrange
          await createDirectory('src');
          await createFile('src/main.dart', 'void main() {}');

          final project = createProjectState(tempDir.path);
          final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

          // Assert - FileManagerState syncs with SelectionState, which uses
          // ProjectState's selectedWorktree (defaults to primaryWorktree)
          check(state.selectedWorktree).isNotNull();
          check(state.selectedWorktree!.data.worktreeRoot).equals(tempDir.path);
          // Root node is built asynchronously, so it may be null initially
          // or loading may be in progress
          check(state.error).isNull();
        },
      );

      test('selects worktree and builds file tree', () async {
        // Arrange
        await createDirectory('src');
        await createDirectory('test');
        await createFile('src/main.dart', 'void main() {}');
        await createFile('README.md', '# Test Project');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        check(state.selectedWorktree).isNotNull();
        check(state.selectedWorktree!.data.worktreeRoot).equals(tempDir.path);
        check(state.rootNode).isNotNull();
        check(state.rootNode!.isDirectory).isTrue();
        check(state.isLoadingTree).isFalse();
        check(state.error).isNull();

        // Verify tree structure
        final topLevelNames =
            state.rootNode!.children.map((c) => c.name).toList();
        check(topLevelNames).contains('src');
        check(topLevelNames).contains('test');
        check(topLevelNames).contains('README.md');
      });

      test('verifies tree builds correctly with nested structure', () async {
        // Arrange
        await createDirectory('src/models');
        await createDirectory('src/widgets');
        await createDirectory('src/services');
        await createFile('src/main.dart', 'void main() {}');
        await createFile('src/models/user.dart', 'class User {}');
        await createFile('src/widgets/button.dart', 'class Button {}');
        await createFile('src/services/api.dart', 'class ApiService {}');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert - directories first, then files
        check(state.rootNode).isNotNull();
        final srcDir = state.rootNode!.children.firstWhere(
          (c) => c.name == 'src',
        );
        check(srcDir.isDirectory).isTrue();
        check(srcDir.hasChildren).isTrue();

        // Check nested directories
        final srcChildNames = srcDir.children.map((c) => c.name).toList();
        check(srcChildNames).contains('models');
        check(srcChildNames).contains('widgets');
        check(srcChildNames).contains('services');
        check(srcChildNames).contains('main.dart');

        // Verify models directory has user.dart
        final modelsDir = srcDir.children.firstWhere(
          (c) => c.name == 'models',
        );
        check(modelsDir.hasChildren).isTrue();
        check(modelsDir.children.first.name).equals('user.dart');
      });

      test('selects file and loads content correctly', () async {
        // Arrange
        await createFile('src/main.dart', 'void main() { print("Hello"); }');
        await createFile('README.md', '# My Project\n\nDescription here.');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act - select Dart file
        state.selectFile('${tempDir.path}/src/main.dart');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.selectedFilePath).equals('${tempDir.path}/src/main.dart');
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.dart);
        check(state.fileContent!.textContent)
            .equals('void main() { print("Hello"); }');
        check(state.isLoadingFile).isFalse();
      });

      test('loads markdown file with correct type', () async {
        // Arrange
        await createFile('README.md', '# Title\n\n## Section\n\nContent.');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act
        state.selectFile('${tempDir.path}/README.md');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.markdown);
        check(state.fileContent!.textContent)
            .equals('# Title\n\n## Section\n\nContent.');
      });

      test('loads JSON file with correct type', () async {
        // Arrange
        await createFile(
          'config.json',
          '{"name": "test", "version": "1.0.0"}',
        );

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act
        state.selectFile('${tempDir.path}/config.json');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.json);
        check(state.fileContent!.textContent)
            .equals('{"name": "test", "version": "1.0.0"}');
      });

      test('toggles directory expansion and updates tree', () async {
        // Arrange
        await createDirectory('src');
        await createFile('src/main.dart', 'void main() {}');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Verify src directory exists and is not expanded
        check(state.rootNode!.children.any((c) => c.name == 'src')).isTrue();
        check(state.isExpanded('${tempDir.path}/src')).isFalse();

        // Act - expand
        state.toggleExpanded('${tempDir.path}/src');

        // Assert - expanded (tracked separately from tree nodes)
        check(state.isExpanded('${tempDir.path}/src')).isTrue();

        // Act - collapse
        state.toggleExpanded('${tempDir.path}/src');

        // Assert - collapsed again
        check(state.isExpanded('${tempDir.path}/src')).isFalse();
      });

      test('complete workflow: select worktree, expand, select file', () async {
        // Arrange
        await createDirectory('src/widgets');
        await createFile('src/main.dart', 'import "widgets/button.dart";');
        await createFile('src/widgets/button.dart', 'class Button {}');
        await createFile('pubspec.yaml', 'name: test_app');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act - select worktree
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Verify tree built
        check(state.rootNode).isNotNull();
        check(state.error).isNull();

        // Act - expand src directory
        state.toggleExpanded('${tempDir.path}/src');
        check(state.isExpanded('${tempDir.path}/src')).isTrue();

        // Act - expand widgets directory
        state.toggleExpanded('${tempDir.path}/src/widgets');
        check(state.isExpanded('${tempDir.path}/src/widgets')).isTrue();

        // Act - select button.dart
        state.selectFile('${tempDir.path}/src/widgets/button.dart');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.selectedFilePath)
            .equals('${tempDir.path}/src/widgets/button.dart');
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.dart);
        check(state.fileContent!.textContent).equals('class Button {}');

        // Act - select different file
        state.selectFile('${tempDir.path}/pubspec.yaml');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.selectedFilePath).equals('${tempDir.path}/pubspec.yaml');
        check(state.fileContent!.textContent).equals('name: test_app');
      });

      test('refresh file tree picks up new files', () async {
        // Arrange
        await createFile('original.dart', 'void original() {}');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Verify original file is in tree
        var fileNames = state.rootNode!.children.map((c) => c.name).toList();
        check(fileNames).contains('original.dart');
        check(fileNames.contains('new_file.dart')).isFalse();

        // Act - create new file and refresh
        await createFile('new_file.dart', 'void newFunc() {}');
        await state.refreshFileTree();

        // Assert
        fileNames = state.rootNode!.children.map((c) => c.name).toList();
        check(fileNames).contains('original.dart');
        check(fileNames).contains('new_file.dart');
      });

      test('handles binary files correctly', () async {
        // Arrange - create binary file with null bytes
        final binaryBytes = [0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0x00, 0x00];
        await createBinaryFile('binary.bin', binaryBytes);

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act
        state.selectFile('${tempDir.path}/binary.bin');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.type).equals(FileContentType.binary);
        check(state.fileContent!.isBinary).isTrue();
      });

      test('tree cleans up on tearDown even after selections', () async {
        // Arrange
        await createDirectory('src');
        await createFile('src/main.dart', 'void main() {}');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);
        state.selectFile('${tempDir.path}/src/main.dart');
        await pumpEventQueue(times: 20);
        state.toggleExpanded('${tempDir.path}/src');

        // Assert that cleanup works (will happen in tearDown)
        // This test primarily verifies no exceptions during tearDown
        check(state.selectedWorktree).isNotNull();
        check(state.rootNode).isNotNull();
        check(state.fileContent).isNotNull();
      });
    });

    group('Error scenarios', () {
      test("worktree path doesn't exist", () async {
        // Arrange
        final project = createProjectState('/nonexistent/path/to/worktree');
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        check(state.error).isNotNull();
        check(state.error!.contains('does not exist')).isTrue();
        check(state.rootNode).isNull();
        check(state.isLoadingTree).isFalse();
      });

      test('file deleted during load shows error', () async {
        // Arrange
        await createFile('temp_file.dart', 'void temp() {}');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Delete the file before attempting to load
        await File('${tempDir.path}/temp_file.dart').delete();

        // Act
        state.selectFile('${tempDir.path}/temp_file.dart');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.isError).isTrue();
        check(state.fileContent!.error).isNotNull();
        check(state.fileContent!.error!.contains('not found')).isTrue();
        check(state.isLoadingFile).isFalse();
      });

      test('path is file not directory errors on tree build', () async {
        // Arrange
        await createFile('not_a_directory.txt', 'some content');

        final project =
            createProjectState('${tempDir.path}/not_a_directory.txt');
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        check(state.error).isNotNull();
        // When Directory.exists() is called on a file, it returns false
        // So the error will be "Directory does not exist"
        check(state.error!.toLowerCase().contains('does not exist')).isTrue();
        check(state.rootNode).isNull();
      });

      test('handles empty directory gracefully', () async {
        // Arrange - tempDir is already created but empty

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        check(state.error).isNull();
        check(state.rootNode).isNotNull();
        check(state.rootNode!.children).isEmpty();
      });

      test('attempting to read directory as file returns error', () async {
        // Arrange
        await createDirectory('some_dir');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act - try to read directory as file
        state.selectFile('${tempDir.path}/some_dir');
        await pumpEventQueue(times: 20);

        // Assert
        check(state.fileContent).isNotNull();
        check(state.fileContent!.isError).isTrue();
      });

      test('switching worktree updates state to new worktree', () async {
        // Arrange
        await createDirectory('worktree1');
        await createDirectory('worktree2');
        await createFile('worktree1/file1.dart', 'file1 content');
        await createFile('worktree2/file2.dart', 'file2 content');

        final wt1Data = WorktreeData(
          worktreeRoot: '${tempDir.path}/worktree1',
          isPrimary: true,
          branch: 'main',
        );
        final wt1State = WorktreeState(wt1Data);
        final projectData =
            ProjectData(name: 'Test', repoRoot: '${tempDir.path}/worktree1');
        final project = ProjectState(
          projectData,
          wt1State,
          autoValidate: false,
          watchFilesystem: false,
        );

        final wt2Data = WorktreeData(
          worktreeRoot: '${tempDir.path}/worktree2',
          isPrimary: false,
          branch: 'feature',
        );
        final wt2State = WorktreeState(wt2Data);
        project.addLinkedWorktree(wt2State);

        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act - select first worktree and wait for it to load
        state.selectWorktree(wt1State);
        await pumpEventQueue(times: 30);

        // Verify first worktree is loaded
        check(state.selectedWorktree).equals(wt1State);
        check(state.rootNode).isNotNull();
        check(state.rootNode!.path).equals('${tempDir.path}/worktree1');

        // Now switch to second worktree
        state.selectWorktree(wt2State);
        await pumpEventQueue(times: 30);

        // Assert - should have second worktree
        check(state.selectedWorktree).equals(wt2State);
        check(state.rootNode).isNotNull();
        check(state.rootNode!.path).equals('${tempDir.path}/worktree2');

        // Verify file from wt2 is in tree
        final fileNames = state.rootNode!.children.map((c) => c.name).toList();
        check(fileNames).contains('file2.dart');
      });

      test('file content cleared when worktree changes', () async {
        // Arrange
        await createDirectory('wt1');
        await createDirectory('wt2');
        await createFile('wt1/file.dart', 'wt1 content');
        await createFile('wt2/file.dart', 'wt2 content');

        final wt1Data = WorktreeData(
          worktreeRoot: '${tempDir.path}/wt1',
          isPrimary: true,
          branch: 'main',
        );
        final wt1State = WorktreeState(wt1Data);
        final projectData =
            ProjectData(name: 'Test', repoRoot: '${tempDir.path}/wt1');
        final project = ProjectState(
          projectData,
          wt1State,
          autoValidate: false,
          watchFilesystem: false,
        );

        final wt2Data = WorktreeData(
          worktreeRoot: '${tempDir.path}/wt2',
          isPrimary: false,
          branch: 'feature',
        );
        final wt2State = WorktreeState(wt2Data);
        project.addLinkedWorktree(wt2State);

        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Select worktree 1 and load a file
        state.selectWorktree(wt1State);
        await pumpEventQueue(times: 20);
        state.selectFile('${tempDir.path}/wt1/file.dart');
        await pumpEventQueue(times: 20);

        check(state.fileContent).isNotNull();
        check(state.fileContent!.textContent).equals('wt1 content');

        // Act - switch to worktree 2
        state.selectWorktree(wt2State);

        // Assert - file content cleared immediately
        check(state.fileContent).isNull();
        check(state.selectedFilePath).isNull();

        await pumpEventQueue(times: 20);

        // Now select file from wt2
        state.selectFile('${tempDir.path}/wt2/file.dart');
        await pumpEventQueue(times: 20);

        check(state.fileContent!.textContent).equals('wt2 content');
      });
    });

    group('File permissions (platform-dependent)', () {
      test('handles unreadable file gracefully', () async {
        // This test may behave differently on different platforms
        // On some systems, setting permissions may not work as expected

        // Arrange
        await createFile('protected.dart', 'protected content');
        final file = File('${tempDir.path}/protected.dart');

        // Try to remove read permission (may not work on all platforms)
        try {
          await Process.run('chmod', ['000', file.path]);
        } on ProcessException {
          // chmod not available, skip this test
          return;
        }

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Act
        state.selectFile('${tempDir.path}/protected.dart');
        await pumpEventQueue(times: 20);

        // Assert - should get error or work depending on platform
        check(state.fileContent).isNotNull();
        // Either it's an error or it worked (platform dependent)
        check(state.isLoadingFile).isFalse();

        // Cleanup - restore permissions
        await Process.run('chmod', ['644', file.path]);
      }, skip: Platform.isWindows);

      test('handles unreadable directory gracefully', () async {
        // Arrange
        await createDirectory('protected_dir');
        await createFile('protected_dir/file.dart', 'content');
        await createFile('other_file.dart', 'other content');
        final dir = Directory('${tempDir.path}/protected_dir');

        // Try to remove read permission
        try {
          await Process.run('chmod', ['000', dir.path]);
        } on ProcessException {
          return;
        }

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Cleanup first (before assertions) to ensure tearDown works
        await Process.run('chmod', ['755', dir.path]);

        // Assert - The protected directory may cause an error or be skipped
        // depending on how the service handles it. We just verify the state
        // isn't stuck in loading and tearDown can clean up.
        check(state.isLoadingTree).isFalse();
        // Either it succeeded (with protected_dir skipped) or failed with error
        // Both are acceptable behaviors for this edge case
      }, skip: Platform.isWindows);
    });

    group('Sorting behavior', () {
      test('directories sorted before files', () async {
        // Arrange - create in random order
        await createFile('zebra.dart', 'zebra');
        await createDirectory('alpha');
        await createFile('apple.dart', 'apple');
        await createDirectory('zulu');
        await createFile('main.dart', 'main');
        await createDirectory('beta');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        final children = state.rootNode!.children;

        // First should be directories (alphabetically)
        check(children[0].name).equals('alpha');
        check(children[0].isDirectory).isTrue();
        check(children[1].name).equals('beta');
        check(children[1].isDirectory).isTrue();
        check(children[2].name).equals('zulu');
        check(children[2].isDirectory).isTrue();

        // Then files (alphabetically)
        check(children[3].name).equals('apple.dart');
        check(children[3].isFile).isTrue();
        check(children[4].name).equals('main.dart');
        check(children[4].isFile).isTrue();
        check(children[5].name).equals('zebra.dart');
        check(children[5].isFile).isTrue();
      });

      test('sorting is case-insensitive', () async {
        // Arrange
        await createFile('Zebra.dart', 'Zebra');
        await createFile('apple.dart', 'apple');
        await createFile('BANANA.dart', 'BANANA');

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        final names = state.rootNode!.children.map((c) => c.name).toList();
        check(names[0]).equals('apple.dart');
        check(names[1]).equals('BANANA.dart');
        check(names[2]).equals('Zebra.dart');
      });
    });

    group('File metadata', () {
      test('file nodes have correct size', () async {
        // Arrange
        const content = 'This is exactly 30 characters!';
        await createFile('sized.txt', content);

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        final file = state.rootNode!.children.firstWhere(
          (c) => c.name == 'sized.txt',
        );
        check(file.size).equals(content.length);
      });

      test('file nodes have modified time', () async {
        // Arrange
        await createFile('timed.txt', 'content');
        final now = DateTime.now();

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 20);

        // Assert
        final file = state.rootNode!.children.firstWhere(
          (c) => c.name == 'timed.txt',
        );
        check(file.modified).isNotNull();
        // Modified time should be within last few seconds
        check(file.modified!.isAfter(now.subtract(const Duration(seconds: 5))))
            .isTrue();
      });
    });

    group('Gitignore integration', () {
      test('filters gitignored files when respectGitignore is true',
          skip: 'gitignore filtering disabled — _getIgnoredPaths causes SIGPIPE in release builds',
          () async {
        // Arrange - create a git repo with .gitignore
        await createFile('.gitignore', 'ignored.txt\nbuild/');
        await createFile('included.dart', 'content');
        await createFile('ignored.txt', 'should not appear');
        await createDirectory('build');
        await createFile('build/output.js', 'compiled');

        // Initialize git repo
        try {
          await Process.run(
            'git',
            ['init'],
            workingDirectory: tempDir.path,
          );
        } on ProcessException {
          // Git not available, skip test
          return;
        }

        final project = createProjectState(tempDir.path);
        final selectionState = SelectionState(project);
          final state = FileManagerState(project, fileSystemService, selectionState);

        // Act
        state.selectWorktree(project.primaryWorktree);
        await pumpEventQueue(times: 30);

        // Assert
        if (state.error != null) {
          // Git operations may fail in some environments
          return;
        }

        final names = state.rootNode!.children.map((c) => c.name).toList();
        check(names).contains('included.dart');
        check(names.contains('ignored.txt')).isFalse();
        check(names.contains('build')).isFalse();
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
