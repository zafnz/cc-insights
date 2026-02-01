import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/file_manager_worktree_panel.dart';
import 'package:cc_insights_v2/panels/file_tree_panel.dart';
import 'package:cc_insights_v2/panels/file_viewer_panel.dart';
import 'package:cc_insights_v2/screens/file_manager_screen.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Integration tests for FileManagerScreen (Tasks 4.1 & 4.3).
///
/// Covers:
/// - Screen renders initial layout
/// - All panels present
/// - Layout controller initialized
/// - Providers accessible
/// - Select worktree → tree loads
/// - Select file → content loads
/// - Error handling (tree load fails, file read fails)
/// - State synchronization across panels
void main() {
  group('FileManagerScreen', () {
    final resources = TestResources();
    late ProjectState project;
    late FakeFileSystemService fakeFileSystem;
    late FileManagerState fileManagerState;

    /// Creates a project with a primary worktree for testing.
    ProjectState createProject() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/Users/test/my-project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      return ProjectState(
        const ProjectData(
          name: 'My Project',
          repoRoot: '/Users/test/my-project',
        ),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    /// Creates a test app with the FileManagerScreen.
    Widget createTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProjectState>.value(value: project),
          ChangeNotifierProvider<FileManagerState>.value(
            value: fileManagerState,
          ),
        ],
        child: const MaterialApp(
          home: FileManagerScreen(),
        ),
      );
    }

    setUp(() {
      project = createProject();
      fakeFileSystem = FakeFileSystemService();
      fileManagerState = resources.track(
        FileManagerState(project, fakeFileSystem),
      );
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    group('Screen Structure (Task 4.1)', () {
      testWidgets('renders initial layout', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Screen should render
        expect(find.byType(FileManagerScreen), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
      });

      testWidgets('all panels present', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // All three panels should be present
        expect(
          find.byType(FileManagerWorktreePanel),
          findsOneWidget,
        );
        expect(find.byType(FileTreePanel), findsOneWidget);
        expect(find.byType(FileViewerPanel), findsOneWidget);
      });

      testWidgets('layout controller initialized', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // EditableMultiSplitView should be present with controller
        expect(find.byType(EditableMultiSplitView), findsOneWidget);
      });

      testWidgets('providers accessible', (tester) async {
        late BuildContext capturedContext;

        final testWidget = Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ProjectState>.value(value: project),
              ChangeNotifierProvider<FileManagerState>.value(
                value: fileManagerState,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: testWidget,
              ),
            ),
          ),
        );
        await safePumpAndSettle(tester);

        // Both providers should be accessible
        expect(
          capturedContext.read<ProjectState>(),
          same(project),
        );
        expect(
          capturedContext.read<FileManagerState>(),
          same(fileManagerState),
        );
      });

      testWidgets('initial two-column layout', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Should have EditableMultiSplitView with two main columns
        final splitView = find.byType(EditableMultiSplitView);
        expect(splitView, findsOneWidget);

        // Column 1: Worktree panel + File tree panel (vertical split)
        expect(
          find.byType(FileManagerWorktreePanel),
          findsOneWidget,
        );
        expect(find.byType(FileTreePanel), findsOneWidget);

        // Column 2: File viewer panel
        expect(find.byType(FileViewerPanel), findsOneWidget);
      });

      testWidgets('edit mode enabled for drag-and-drop', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Drag handles should be visible (indicates edit mode is on)
        expect(find.byIcon(Icons.drag_indicator), findsWidgets);
      });
    });

    group('End-to-End Workflow (Task 4.3)', () {
      testWidgets('select worktree → tree loads', (tester) async {
        // Set up fake file system with directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/lib');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/lib/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/README.md',
          '# Project',
        );

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Initially, file tree panel shows "No worktree selected"
        expect(find.text('No worktree selected'), findsOneWidget);

        // Click on worktree in the worktree panel
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // File tree should now be loaded and visible
        expect(find.text('lib'), findsOneWidget);
        expect(find.text('README.md'), findsOneWidget);
        expect(find.text('No worktree selected'), findsNothing);
      });

      testWidgets('select file → content loads', (tester) async {
        // Set up fake file system with files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/config.yaml',
          'key: value',
        );

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree first
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // File tree should show the file
        expect(find.text('config.yaml'), findsOneWidget);

        // File viewer should show "Select a file to view" initially
        expect(find.text('Select a file to view'), findsOneWidget);

        // Click on the file to select it
        // Must pump past kDoubleTapTimeout for single tap to register
        await tester.tap(find.text('config.yaml'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // File content should now be loaded in viewer
        // (GptMarkdown will render the YAML content)
        expect(find.text('Select a file to view'), findsNothing);
        // The content should be visible (rendered by SourceCodeViewer)
        expect(find.textContaining('key'), findsWidgets);
      });

      testWidgets('expand directory → children appear', (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/app.dart',
          'class App {}',
        );

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // Directory should be visible but not expanded
        expect(find.text('src'), findsOneWidget);
        expect(find.text('app.dart'), findsNothing);

        // Click on directory to expand
        // Must pump past kDoubleTapTimeout for single tap to register
        await tester.tap(find.text('src'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Children should now be visible
        expect(find.text('app.dart'), findsOneWidget);
      });

      testWidgets(
        'select different files updates viewer',
        (tester) async {
          // Set up multiple files
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/file1.txt',
            'Content of file 1',
          );
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/file2.txt',
            'Content of file 2',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // Select first file
          // Must pump past kDoubleTapTimeout for single tap to register
          await tester.tap(find.text('file1.txt'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // First file content should be visible
          expect(find.textContaining('Content of file 1'), findsWidgets);

          // Select second file
          await tester.tap(find.text('file2.txt'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Second file content should now be visible
          expect(find.textContaining('Content of file 2'), findsWidgets);
          // First file content should no longer be visible
          expect(find.textContaining('Content of file 1'), findsNothing);
        },
      );

      testWidgets(
        'worktree selection persists during file browsing',
        (tester) async {
          // Set up file system
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/folder');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/folder/nested.dart',
            'class Nested {}',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          final selectedWorktree = fileManagerState.selectedWorktree;
          expect(selectedWorktree, isNotNull);

          // Expand folder
          await tester.tap(find.text('folder'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Worktree selection should persist
          expect(
            fileManagerState.selectedWorktree,
            same(selectedWorktree),
          );

          // Select file
          await tester.tap(find.text('nested.dart'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Worktree selection should still persist
          expect(
            fileManagerState.selectedWorktree,
            same(selectedWorktree),
          );
        },
      );
    });

    group('Error Handling', () {
      testWidgets('tree load fails → error message', (tester) async {
        // Do NOT add directory to fake file system - will cause error
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree (will trigger failed tree load)
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // Error message should be visible in file tree panel
        expect(find.text('Failed to load file tree'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });

      testWidgets('file read fails → error in viewer', (tester) async {
        // Set up directory with file, but don't actually add the file content
        // This simulates a file that exists in the tree but can't be read
        fakeFileSystem.addDirectory('/Users/test/my-project');

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree first
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // Now add a file to the tree (simulates race condition where file
        // appears but is immediately deleted or becomes unreadable)
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/exists.txt',
          'content',
        );

        // Refresh the tree to see the file
        final refreshButton = find.ancestor(
          of: find.byTooltip('Refresh file tree'),
          matching: find.byType(IconButton),
        );
        await tester.tap(refreshButton);
        await safePumpAndSettle(tester);

        // Now remove the file content (simulates file becoming unreadable)
        fakeFileSystem.clear();
        fakeFileSystem.addDirectory('/Users/test/my-project');
        // File is in tree but no longer has content

        // Try to select file (will fail to read)
        await tester.tap(find.text('exists.txt'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Error should be displayed in viewer panel
        expect(find.text('Failed to load file'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });

      testWidgets(
        'error in one panel does not affect others',
        (tester) async {
          // Set up successful directory
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/good.txt',
            'good content',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree successfully
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // File tree should be loaded
          expect(find.text('good.txt'), findsOneWidget);

          // Remove file content to simulate read failure
          fakeFileSystem.clear();
          fakeFileSystem.addDirectory('/Users/test/my-project');
          // File is in tree but content is gone

          // Try to select file (will fail)
          await tester.tap(find.text('good.txt'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // File viewer should show error
          expect(find.text('Failed to load file'), findsOneWidget);

          // But worktree panel should still be functional
          expect(
            find.byType(FileManagerWorktreePanel),
            findsOneWidget,
          );
          expect(find.text('main'), findsOneWidget);

          // And file tree panel should still show the tree
          expect(find.byType(FileTreePanel), findsOneWidget);
          // File should still be visible in the tree
          final treeFileFinder = find.descendant(
            of: find.byType(FileTreePanel),
            matching: find.text('good.txt'),
          );
          expect(treeFileFinder, findsOneWidget);
        },
      );

      testWidgets('refresh after error recovers', (tester) async {
        // Start with no directory (will fail)
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree (will fail)
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // Error should be shown
        expect(find.text('Failed to load file tree'), findsOneWidget);

        // Now add the directory
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file.txt',
          'content',
        );

        // Click refresh button
        final refreshButton = find.ancestor(
          of: find.byTooltip('Refresh file tree'),
          matching: find.byType(IconButton),
        );
        await tester.tap(refreshButton);
        await safePumpAndSettle(tester);

        // Error should be gone, tree should be loaded
        expect(find.text('Failed to load file tree'), findsNothing);
        expect(find.text('file.txt'), findsOneWidget);
      });
    });

    group('State Synchronization', () {
      testWidgets(
        'worktree selection syncs across all panels',
        (tester) async {
          fakeFileSystem.addDirectory('/Users/test/my-project');

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree in worktree panel
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // State should be updated
          expect(
            fileManagerState.selectedWorktree!.data.branch,
            'main',
          );

          // All panels should reflect the selection:
          // 1. Worktree panel shows selection highlight
          final worktreePanelMaterial = find.ancestor(
            of: find.text('main'),
            matching: find.byType(Material),
          );
          final material = tester.widget<Material>(
            worktreePanelMaterial.first,
          );
          expect(material.color, isNot(Colors.transparent));

          // 2. File tree panel shows loaded tree (not "No worktree")
          expect(find.text('No worktree selected'), findsNothing);
        },
      );

      testWidgets(
        'file selection syncs between tree and viewer',
        (tester) async {
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/sync.txt',
            'synced content',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // Select file in tree
          await tester.tap(find.text('sync.txt'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // State should be updated
          expect(
            fileManagerState.selectedFilePath,
            '/Users/test/my-project/sync.txt',
          );

          // File tree should show selection
          final treeContainer = find.ancestor(
            of: find.text('sync.txt'),
            matching: find.byType(Container),
          );
          final container = tester.widget<Container>(
            treeContainer.last,
          );
          expect(container.color, isNot(Colors.transparent));

          // File viewer should show content
          expect(find.textContaining('synced'), findsWidgets);
        },
      );

      testWidgets('tree expansion state persists', (tester) async {
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/folder');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/folder/file.txt',
          'content',
        );

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select worktree
        await tester.tap(find.text('main'));
        await safePumpAndSettle(tester);

        // Expand folder
        await tester.tap(find.text('folder'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Child should be visible in tree
        final treeFileFinder = find.descendant(
          of: find.byType(FileTreePanel),
          matching: find.text('file.txt'),
        );
        expect(treeFileFinder, findsOneWidget);

        // Select the file
        await tester.tap(treeFileFinder);
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Folder should still be expanded
        expect(treeFileFinder, findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      });

      testWidgets(
        'changing worktree clears file selection',
        (tester) async {
          // Create project with two worktrees
          final linkedWorktree = WorktreeState(
            const WorktreeData(
              worktreeRoot: '/Users/test/my-project-linked',
              isPrimary: false,
              branch: 'feature',
            ),
          );
          project.addWorktree(linkedWorktree);

          // Set up file systems for both
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/file1.txt',
            'content1',
          );
          fakeFileSystem.addDirectory('/Users/test/my-project-linked');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project-linked/file2.txt',
            'content2',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select first worktree and file
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          await tester.tap(find.text('file1.txt'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          expect(
            fileManagerState.selectedFilePath,
            '/Users/test/my-project/file1.txt',
          );

          // Switch to second worktree
          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // File selection should be cleared
          expect(fileManagerState.selectedFilePath, isNull);
          expect(fileManagerState.fileContent, isNull);
        },
      );
    });

    group('Layout and Panel Interaction', () {
      testWidgets('all three panels render simultaneously', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // All panels should be visible at once
        expect(
          find.byType(FileManagerWorktreePanel),
          findsOneWidget,
        );
        expect(find.byType(FileTreePanel), findsOneWidget);
        expect(find.byType(FileViewerPanel), findsOneWidget);
      });

      testWidgets('panels use PanelWrapper', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // All panels should have titles (from PanelWrapper)
        expect(find.text('Worktrees'), findsOneWidget);
        expect(find.text('Files'), findsOneWidget);
        expect(find.text('File Viewer'), findsOneWidget);
      });

      testWidgets('drag handles visible in all panels', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Multiple drag handles should be present
        expect(
          find.byIcon(Icons.drag_indicator),
          findsWidgets,
        );
      });

      testWidgets('EditableMultiSplitView is editable', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // EditableMultiSplitView should be in edit mode
        final splitView = tester.widget<EditableMultiSplitView>(
          find.byType(EditableMultiSplitView),
        );

        // Config should be present (indicates edit mode)
        expect(splitView.config, isNotNull);
      });
    });

    group('Complex Workflows', () {
      testWidgets(
        'complete workflow: select worktree, expand, select file, view',
        (tester) async {
          // Set up complex directory structure
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/src');
          fakeFileSystem.addDirectory('/Users/test/my-project/src/models');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/src/models/user.dart',
            'class User {}',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Step 1: Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);
          expect(find.text('src'), findsOneWidget);

          // Step 2: Expand src
          await tester.tap(find.text('src'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);
          expect(find.text('models'), findsOneWidget);

          // Step 3: Expand models
          await tester.tap(find.text('models'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);
          expect(find.text('user.dart'), findsOneWidget);

          // Step 4: Select file
          await tester.tap(find.text('user.dart'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Step 5: Verify content displayed
          expect(find.textContaining('class User'), findsWidgets);
        },
      );

      testWidgets(
        'navigate tree, select multiple files sequentially',
        (tester) async {
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/a.txt',
            'Content A',
          );
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/b.txt',
            'Content B',
          );
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/c.txt',
            'Content C',
          );

          await tester.pumpWidget(createTestApp());
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // Select files in sequence
          final files = ['a.txt', 'b.txt', 'c.txt'];
          final contents = ['Content A', 'Content B', 'Content C'];

          for (int i = 0; i < files.length; i++) {
            await tester.tap(find.text(files[i]));
            await tester.pump(const Duration(milliseconds: 350));
            await safePumpAndSettle(tester);

            // Verify correct content displayed
            expect(find.textContaining(contents[i]), findsWidgets);

            // Verify previous content not displayed
            for (int j = 0; j < i; j++) {
              expect(find.textContaining(contents[j]), findsNothing);
            }
          }
        },
      );
    });
  });
}
