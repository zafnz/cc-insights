import 'dart:ui';

import 'package:cc_insights_v2/models/file_tree_node.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/file_tree_panel.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Testable subclass of [FileManagerState] that exposes loading state.
///
/// This allows us to test the loading indicator UI directly without
/// relying on async delays in the fake file system.
class _TestableFileManagerState extends FileManagerState {
  bool _testIsLoadingTree = false;

  _TestableFileManagerState(super.project, super.fileSystemService);

  @override
  bool get isLoadingTree => _testIsLoadingTree || super.isLoadingTree;

  /// Sets the loading tree state for testing purposes.
  void setLoadingTree(bool value) {
    _testIsLoadingTree = value;
    notifyListeners();
  }
}

void main() {
  group('FileTreePanel', () {
    final resources = TestResources();
    late ProjectState project;
    late FakeFileSystemService fakeFileSystem;

    /// Creates a project with a primary worktree.
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

    /// Creates a test app with all required providers.
    Widget createTestApp(FileManagerState fileManagerState) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProjectState>.value(value: project),
          ChangeNotifierProvider<FileManagerState>.value(
            value: fileManagerState,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DragHandleProvider(
              dragHandle: const Icon(Icons.drag_indicator),
              child: const FileTreePanel(),
            ),
          ),
        ),
      );
    }

    setUp(() {
      project = createProject();
      fakeFileSystem = FakeFileSystemService();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    group('Initial State', () {
      testWidgets('renders "No worktree selected" initially', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show the no worktree selected message
        expect(find.text('No worktree selected'), findsOneWidget);
        expect(
          find.text('Select a worktree to browse files'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
      });
    });

    group('Loading State', () {
      testWidgets('shows loading indicator during tree build', (tester) async {
        // Set up fake file system with directory
        fakeFileSystem.addDirectory('/Users/test/my-project');

        // Create state and manually set loading state for testing
        // (testing the UI response to isLoadingTree = true)
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // First select a worktree so we're past the "no selection" state
        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Now manually set loading state to test the loading UI
        state.setLoadingTree(true);
        await tester.pump();

        // Should show loading indicator and loading text
        // Note: There are two indicators - one in the main content area
        // and one in the refresh button
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.text('Loading file tree...'), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('shows error message on failure', (tester) async {
        // Do NOT add the directory - this will cause buildFileTree to fail
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select a worktree to trigger tree loading (which will fail)
        state.selectWorktree(project.primaryWorktree);

        // Wait for the async operation to complete
        await safePumpAndSettle(tester);

        // Should show error message
        expect(find.text('Failed to load file tree'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        // The error message from FakeFileSystemService
        expect(find.text('Directory does not exist'), findsOneWidget);
      });
    });

    group('Tree Available State', () {
      testWidgets('shows file tree when tree is available', (tester) async {
        // Set up fake file system with directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/lib');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/lib/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/README.md',
          '# My Project',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select a worktree to trigger tree loading
        state.selectWorktree(project.primaryWorktree);

        // Wait for the async operation to complete
        await safePumpAndSettle(tester);

        // Should show the file tree with items (directories first, then files)
        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('lib'), findsOneWidget);
        expect(find.text('README.md'), findsOneWidget);

        // Should NOT show other states
        expect(find.text('No worktree selected'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Failed to load file tree'), findsNothing);
      });
    });

    group('Tree Rendering (Task 2.2)', () {
      testWidgets('renders flat file list', (tester) async {
        // Set up fake file system with flat structure (no subdirectories)
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/config.yaml',
          'key: value',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/README.md',
          '# Project',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // All files should be visible as a flat list
        expect(find.text('main.dart'), findsOneWidget);
        expect(find.text('config.yaml'), findsOneWidget);
        expect(find.text('README.md'), findsOneWidget);
      });

      testWidgets('renders nested directories', (tester) async {
        // Set up fake file system with nested structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addDirectory('/Users/test/my-project/src/widgets');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/widgets/button.dart',
          'class Button {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Directory should be visible
        expect(find.text('src'), findsOneWidget);

        // Nested items not yet visible (directory is collapsed by default)
        expect(find.text('widgets'), findsNothing);
        expect(find.text('button.dart'), findsNothing);
      });

      testWidgets('indentation increases with depth', (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/level0');
        fakeFileSystem.addDirectory('/Users/test/my-project/level0/level1');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/level0/level1/deep.dart',
          'class Deep {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Expand level0 to see level1
        state.toggleExpanded('/Users/test/my-project/level0');
        await tester.pump();

        // Expand level1 to see deep.dart
        state.toggleExpanded('/Users/test/my-project/level0/level1');
        await tester.pump();

        // All should now be visible
        expect(find.text('level0'), findsOneWidget);
        expect(find.text('level1'), findsOneWidget);
        expect(find.text('deep.dart'), findsOneWidget);

        // Check indentation by examining the left padding
        // depth 0: 8px, depth 1: 24px, depth 2: 40px (16px per level + 8)
        final level0Finder = find.text('level0');
        final level1Finder = find.text('level1');
        final deepFinder = find.text('deep.dart');

        // Get the left positions to verify indentation increases
        final level0Pos = tester.getTopLeft(level0Finder);
        final level1Pos = tester.getTopLeft(level1Finder);
        final deepPos = tester.getTopLeft(deepFinder);

        // Each level should be further right than the previous
        expect(level1Pos.dx, greaterThan(level0Pos.dx));
        expect(deepPos.dx, greaterThan(level1Pos.dx));
      });

      testWidgets('file icons vs folder icons', (tester) async {
        // Set up mix of files and folders
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/data.json',
          '{}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/README.md',
          '# Readme',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Should have folder icon for directory (closed folder)
        // Note: find.byIcon(Icons.folder) is used in PanelWrapper header too
        // so we need at least one folder icon for the 'src' directory
        expect(find.byIcon(Icons.folder), findsWidgets);

        // Should have file-type specific icons
        expect(find.byIcon(Icons.code), findsOneWidget); // .dart
        expect(find.byIcon(Icons.data_object), findsOneWidget); // .json
        expect(find.byIcon(Icons.description), findsOneWidget); // .md
      });

      testWidgets('expand icon appears for folders', (tester) async {
        // Set up directory with children
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file.txt',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Collapsed folder should show chevron_right
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);

        // Files should NOT have chevron icons
        // (expand_more would indicate expanded folder)
        expect(find.byIcon(Icons.expand_more), findsNothing);

        // Expand the folder
        state.toggleExpanded('/Users/test/my-project/src');
        await tester.pump();

        // Now should show expand_more for expanded folder
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });

      testWidgets('hover highlights item', (tester) async {
        // Set up simple file
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file.txt',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Find the container for the file item
        final fileFinder = find.text('file.txt');
        expect(fileFinder, findsOneWidget);

        // Get the Container that holds the file item (parent of Padding)
        final containerFinder = find.ancestor(
          of: fileFinder,
          matching: find.byType(Container),
        );

        // Initially should have transparent background
        final initialContainer = tester.widget<Container>(containerFinder.last);
        expect(initialContainer.color, Colors.transparent);

        // Simulate mouse enter on the MouseRegion
        final mouseRegionFinder = find.ancestor(
          of: fileFinder,
          matching: find.byType(MouseRegion),
        );
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await gesture.moveTo(tester.getCenter(mouseRegionFinder.last));
        await tester.pump();

        // Now should have highlight color
        final hoveredContainer = tester.widget<Container>(containerFinder.last);
        expect(hoveredContainer.color, isNot(Colors.transparent));

        // Clean up gesture
        await gesture.removePointer();
      });

      // Tooltip tests removed - tooltips were removed for performance
    });

    group('PanelWrapper Integration', () {
      testWidgets('has title "Files"', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show the panel title
        expect(find.text('Files'), findsOneWidget);
      });

      testWidgets('has folder icon', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show the folder icon in the header
        expect(find.byIcon(Icons.folder), findsOneWidget);
      });

      testWidgets('renders with drag handle from provider', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // The drag handle icon should be present
        expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      });
    });

    group('Expand/Collapse Behavior (Task 2.3)', () {
      testWidgets('click folder expands it', (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Verify folder is collapsed (children not visible)
        expect(find.text('src'), findsOneWidget);
        expect(find.text('main.dart'), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);

        // Click on the folder name to expand
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('src'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Children should now be visible
        expect(find.text('main.dart'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      });

      testWidgets('click expanded folder collapses it', (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // First expand the folder
        state.toggleExpanded('/Users/test/my-project/src');
        await tester.pump();

        // Verify folder is expanded
        expect(find.text('main.dart'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);

        // Click on the folder name to collapse
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('src'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Children should no longer be visible
        expect(find.text('main.dart'), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      });

      testWidgets('children appear when folder is expanded', (tester) async {
        // Set up nested directory structure with multiple children
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/lib');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/lib/app.dart',
          'class App {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/lib/main.dart',
          'void main() {}',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/lib/utils.dart',
          'class Utils {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Initially no children visible
        expect(find.text('app.dart'), findsNothing);
        expect(find.text('main.dart'), findsNothing);
        expect(find.text('utils.dart'), findsNothing);

        // Expand the folder
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('lib'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // All children should now be visible
        expect(find.text('app.dart'), findsOneWidget);
        expect(find.text('main.dart'), findsOneWidget);
        expect(find.text('utils.dart'), findsOneWidget);
      });

      testWidgets(
        'children disappear when folder is collapsed',
        (tester) async {
        // Set up nested directory structure with multiple children
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/file1.dart',
          'content1',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/file2.dart',
          'content2',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Expand the folder first
        state.toggleExpanded('/Users/test/my-project/src');
        await tester.pump();

        // Verify children are visible
        expect(find.text('file1.dart'), findsOneWidget);
        expect(find.text('file2.dart'), findsOneWidget);

        // Collapse the folder by clicking
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('src'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Children should disappear
        expect(find.text('file1.dart'), findsNothing);
        expect(find.text('file2.dart'), findsNothing);
      });

      testWidgets(
        'icon changes from chevron_right to expand_more on expand',
        (tester) async {
          // Set up directory with children
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/folder');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/folder/file.dart',
            'content',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Initially collapsed - should show chevron_right
          expect(find.byIcon(Icons.chevron_right), findsOneWidget);
          expect(find.byIcon(Icons.expand_more), findsNothing);

          // Expand the folder
          // Must pump past kDoubleTapTimeout (300ms) for single tap to register
          await tester.tap(find.text('folder'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Now should show expand_more
          expect(find.byIcon(Icons.expand_more), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right), findsNothing);
        },
      );

      testWidgets(
        'icon changes from expand_more to chevron_right on collapse',
        (tester) async {
          // Set up directory with children
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/folder');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/folder/file.dart',
            'content',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Expand the folder first
          state.toggleExpanded('/Users/test/my-project/folder');
          await tester.pump();

          // Should show expand_more
          expect(find.byIcon(Icons.expand_more), findsOneWidget);
          expect(find.byIcon(Icons.chevron_right), findsNothing);

          // Collapse the folder
          // Must pump past kDoubleTapTimeout (300ms) for single tap to register
          await tester.tap(find.text('folder'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Now should show chevron_right
          expect(find.byIcon(Icons.chevron_right), findsOneWidget);
          expect(find.byIcon(Icons.expand_more), findsNothing);
        },
      );

      testWidgets(
        'state updated in FileManagerState on expand',
        (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Initially the src node should be collapsed (expanded state tracked separately)
        expect(state.isExpanded('/Users/test/my-project/src'), isFalse);

        // Click to expand
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('src'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Now the src node should be expanded in state
        expect(state.isExpanded('/Users/test/my-project/src'), isTrue);
      });

      testWidgets(
        'state updated in FileManagerState on collapse',
        (tester) async {
          // Set up nested directory structure
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/src');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/src/main.dart',
            'void main() {}',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // First expand via state
          state.toggleExpanded('/Users/test/my-project/src');
          await tester.pump();

          // Verify expanded in state (tracked separately from tree nodes)
          expect(state.isExpanded('/Users/test/my-project/src'), isTrue);

          // Click to collapse
          // Must pump past kDoubleTapTimeout (300ms) for single tap to register
          await tester.tap(find.text('src'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Now the src node should be collapsed in state
          expect(state.isExpanded('/Users/test/my-project/src'), isFalse);
        },
      );

      testWidgets(
        'single-click on directory toggles expand immediately',
        (tester) async {
        // Set up nested directory structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/src');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/src/main.dart',
          'void main() {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Verify folder is collapsed
        expect(find.text('main.dart'), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);

        // Single tap to expand (no delay for double-tap detection)
        await tester.tap(find.text('src'));
        await tester.pump();

        // Children should now be visible immediately
        expect(find.text('main.dart'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
      });

      testWidgets(
        'clicking on chevron icon also toggles expand',
        (tester) async {
          // Set up nested directory structure
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/src');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/src/main.dart',
            'void main() {}',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Verify folder is collapsed
          expect(find.text('main.dart'), findsNothing);

          // Click on the chevron icon to expand
          // Parent GestureDetector has onDoubleTap, so still need to wait
          await tester.tap(find.byIcon(Icons.chevron_right));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Children should now be visible
          expect(find.text('main.dart'), findsOneWidget);
          expect(find.byIcon(Icons.expand_more), findsOneWidget);

          // Click on the expand_more icon to collapse
          await tester.tap(find.byIcon(Icons.expand_more));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Children should no longer be visible
          expect(find.text('main.dart'), findsNothing);
          expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        },
      );

      testWidgets(
        'nested directories can be expanded independently',
        (tester) async {
          // Set up deeply nested directory structure
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addDirectory('/Users/test/my-project/level1');
          fakeFileSystem.addDirectory('/Users/test/my-project/level1/level2');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/level1/level2/deep.dart',
            'class Deep {}',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Only level1 visible initially
          expect(find.text('level1'), findsOneWidget);
          expect(find.text('level2'), findsNothing);
          expect(find.text('deep.dart'), findsNothing);

          // Expand level1
          // Must pump past kDoubleTapTimeout (300ms) for single tap to register
          await tester.tap(find.text('level1'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // level2 should be visible but its child not
          expect(find.text('level1'), findsOneWidget);
          expect(find.text('level2'), findsOneWidget);
          expect(find.text('deep.dart'), findsNothing);

          // Expand level2
          await tester.tap(find.text('level2'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Now all should be visible
          expect(find.text('level1'), findsOneWidget);
          expect(find.text('level2'), findsOneWidget);
          expect(find.text('deep.dart'), findsOneWidget);

          // Collapse level1 - level2 and deep.dart should disappear
          await tester.tap(find.text('level1'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          expect(find.text('level1'), findsOneWidget);
          expect(find.text('level2'), findsNothing);
          expect(find.text('deep.dart'), findsNothing);
        },
      );

      testWidgets('folder icon changes when expanded', (tester) async {
        // Set up directory with children
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addDirectory('/Users/test/my-project/folder');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/folder/file.dart',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Initially should show closed folder icon
        // Note: PanelWrapper header also has a folder icon, so we check
        // that we have at least one of each type
        expect(find.byIcon(Icons.folder), findsWidgets);
        expect(find.byIcon(Icons.folder_open), findsNothing);

        // Expand the folder
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('folder'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // Now should show open folder icon
        expect(find.byIcon(Icons.folder_open), findsOneWidget);
      });
    });

    group('File Selection (Task 2.4)', () {
      testWidgets('click file selects it', (tester) async {
        // Set up files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file1.dart',
          'content1',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file2.dart',
          'content2',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Initially no file selected
        expect(state.selectedFilePath, isNull);

        // Click on file1
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('file1.dart'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // file1 should be selected in state
        expect(state.selectedFilePath, '/Users/test/my-project/file1.dart');
      });

      testWidgets('selection highlighting appears', (tester) async {
        // Set up files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/test.dart',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Find the container before selection
        final fileFinder = find.text('test.dart');
        final containerFinder = find.ancestor(
          of: fileFinder,
          matching: find.byType(Container),
        );
        final initialContainer = tester.widget<Container>(
          containerFinder.last,
        );
        expect(initialContainer.color, Colors.transparent);

        // Click to select
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(fileFinder);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        // Container should now have selection color (not transparent)
        final selectedContainer = tester.widget<Container>(
          containerFinder.last,
        );
        expect(selectedContainer.color, isNot(Colors.transparent));
      });

      testWidgets('previous selection cleared', (tester) async {
        // Set up multiple files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file1.dart',
          'content1',
        );
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/file2.dart',
          'content2',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Select file1
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('file1.dart'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        expect(state.selectedFilePath, '/Users/test/my-project/file1.dart');

        // Find file1's container - should be highlighted
        final file1Finder = find.text('file1.dart');
        final file1ContainerFinder = find.ancestor(
          of: file1Finder,
          matching: find.byType(Container),
        );
        final file1Container = tester.widget<Container>(
          file1ContainerFinder.last,
        );
        expect(file1Container.color, isNot(Colors.transparent));

        // Now select file2
        await tester.tap(find.text('file2.dart'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        // file2 should be selected now
        expect(state.selectedFilePath, '/Users/test/my-project/file2.dart');

        // file1 should no longer be highlighted (transparent background)
        final file1ContainerAfter = tester.widget<Container>(
          file1ContainerFinder.last,
        );
        expect(file1ContainerAfter.color, Colors.transparent);

        // file2 should be highlighted
        final file2Finder = find.text('file2.dart');
        final file2ContainerFinder = find.ancestor(
          of: file2Finder,
          matching: find.byType(Container),
        );
        final file2Container = tester.widget<Container>(
          file2ContainerFinder.last,
        );
        expect(file2Container.color, isNot(Colors.transparent));
      });

      testWidgets('selection persists on tree rebuild', (tester) async {
        // Set up files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/main.dart',
          'void main() {}',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Select the file
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('main.dart'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        expect(state.selectedFilePath, '/Users/test/my-project/main.dart');

        // Rebuild the tree by refreshing
        await state.refreshFileTree();
        await safePumpAndSettle(tester);

        // Selection should persist after rebuild
        expect(state.selectedFilePath, '/Users/test/my-project/main.dart');

        // Visual highlighting should still be present
        final fileFinder = find.text('main.dart');
        final containerFinder = find.ancestor(
          of: fileFinder,
          matching: find.byType(Container),
        );
        final container = tester.widget<Container>(containerFinder.last);
        expect(container.color, isNot(Colors.transparent));
      });

      testWidgets('state updated in FileManagerState', (tester) async {
        // Set up files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/config.yaml',
          'key: value',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Verify initial state
        expect(state.selectedFilePath, isNull);
        expect(state.fileContent, isNull);

        // Click to select
        // Must pump past kDoubleTapTimeout (300ms) for single tap to register
        await tester.tap(find.text('config.yaml'));
        await tester.pump(const Duration(milliseconds: 350));
        await safePumpAndSettle(tester);

        // State should be updated with selected file path
        expect(
          state.selectedFilePath,
          '/Users/test/my-project/config.yaml',
        );
        // File content should be loading or loaded
        expect(state.fileContent, isNotNull);
      });

      testWidgets('double-click on file selects it', (tester) async {
        // Set up files
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/README.md',
          '# Project',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Initially no file selected
        expect(state.selectedFilePath, isNull);

        // Double-tap on the file
        await tester.tap(find.text('README.md'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('README.md'));
        await safePumpAndSettle(tester);

        // File should be selected
        expect(state.selectedFilePath, '/Users/test/my-project/README.md');

        // Highlighting should appear
        final fileFinder = find.text('README.md');
        final containerFinder = find.ancestor(
          of: fileFinder,
          matching: find.byType(Container),
        );
        final container = tester.widget<Container>(containerFinder.last);
        expect(container.color, isNot(Colors.transparent));
      });
    });

    group('Loading States and Refresh Button (Task 2.5)', () {
      testWidgets('refresh button triggers refresh', (tester) async {
        // Set up fake file system with initial structure
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/initial.dart',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select worktree and load initial tree
        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Verify initial file is visible
        expect(find.text('initial.dart'), findsOneWidget);

        // Add a new file to the fake file system
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/new.dart',
          'new content',
        );

        // Find and click the refresh button by looking for IconButton with tooltip
        final iconButtonFinder = find.ancestor(
          of: find.byTooltip('Refresh file tree'),
          matching: find.byType(IconButton),
        );
        expect(iconButtonFinder, findsOneWidget);

        await tester.tap(iconButtonFinder);
        await safePumpAndSettle(tester);

        // After refresh, new file should be visible
        expect(find.text('new.dart'), findsOneWidget);
        expect(find.text('initial.dart'), findsOneWidget);
      });

      testWidgets('empty state displays correctly', (tester) async {
        // Set up an empty directory
        fakeFileSystem.addDirectory('/Users/test/my-project');

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select worktree and load empty tree
        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Should show empty state message
        expect(find.text('No files found'), findsOneWidget);
        expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);

        // Should NOT show other states
        expect(find.text('No worktree selected'), findsNothing);
        expect(find.text('Loading file tree...'), findsNothing);
        expect(find.byType(ListView), findsNothing);
      });

      testWidgets(
        'loading state blocks interaction (button disabled)',
        (tester) async {
          // Set up fake file system
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/test.dart',
            'content',
          );

          // Use testable state to control loading state
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Select worktree first
          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Manually set loading state
          state.setLoadingTree(true);
          await tester.pump();

          // Find the refresh button by looking for the IconButton with tooltip
          final iconButtonFinder = find.ancestor(
            of: find.byTooltip('Refresh file tree'),
            matching: find.byType(IconButton),
          );
          expect(iconButtonFinder, findsOneWidget);

          // Verify button is disabled (onPressed is null)
          final iconButton = tester.widget<IconButton>(
            iconButtonFinder,
          );
          expect(iconButton.onPressed, isNull);

          // Verify button shows spinner instead of refresh icon
          expect(find.byType(CircularProgressIndicator), findsWidgets);
          expect(
            find.descendant(
              of: iconButtonFinder,
              matching: find.byIcon(Icons.refresh),
            ),
            findsNothing,
          );
        },
      );

      testWidgets(
        'refresh button enabled when not loading',
        (tester) async {
          // Set up fake file system
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/file.dart',
            'content',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Select worktree and wait for load to complete
          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Find the refresh button by looking for the IconButton with tooltip
          final iconButtonFinder = find.ancestor(
            of: find.byTooltip('Refresh file tree'),
            matching: find.byType(IconButton),
          );
          expect(iconButtonFinder, findsOneWidget);

          // Verify button is enabled (onPressed is not null)
          final iconButton = tester.widget<IconButton>(
            iconButtonFinder,
          );
          expect(iconButton.onPressed, isNotNull);

          // Verify button shows refresh icon
          expect(
            find.descendant(
              of: iconButtonFinder,
              matching: find.byIcon(Icons.refresh),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('empty tree after directory with files', (tester) async {
        // Set up directory with files initially
        fakeFileSystem.addDirectory('/Users/test/my-project');
        fakeFileSystem.addTextFile(
          '/Users/test/my-project/temp.dart',
          'content',
        );

        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select worktree and load tree
        state.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Should show file tree
        expect(find.text('temp.dart'), findsOneWidget);

        // Clear the file system and refresh
        fakeFileSystem.clear();
        fakeFileSystem.addDirectory('/Users/test/my-project');

        await state.refreshFileTree();
        await safePumpAndSettle(tester);

        // Should now show empty state
        expect(find.text('No files found'), findsOneWidget);
        expect(find.text('temp.dart'), findsNothing);
      });
    });

    group('State Transitions', () {
      testWidgets(
        'transitions from no selection to tree after worktree selected',
        (tester) async {
          // Set up fake file system with directory
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/file.txt',
            'content',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Initially shows no selection
          expect(find.text('No worktree selected'), findsOneWidget);

          // Select worktree and wait for load to complete
          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Now shows file tree with the file
          expect(find.byType(ListView), findsOneWidget);
          expect(find.text('file.txt'), findsOneWidget);
        },
      );

      testWidgets(
        'transitions from tree to no selection when worktree cleared',
        (tester) async {
          // Set up fake file system with directory
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/test.dart',
            'void main() {}',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Select worktree and wait for load
          state.selectWorktree(project.primaryWorktree);
          await safePumpAndSettle(tester);

          // Should show tree with file
          expect(find.byType(ListView), findsOneWidget);
          expect(find.text('test.dart'), findsOneWidget);

          // Clear selection
          state.clearSelection();
          await tester.pump();

          // Should show no selection
          expect(find.text('No worktree selected'), findsOneWidget);
        },
      );
    });
  });
}

/// Helper function to find a node by path in the file tree.
///
/// Recursively searches through the tree to find a node with the given path.
/// Returns null if not found.
FileTreeNode? _findNodeByPath(FileTreeNode node, String targetPath) {
  if (node.path == targetPath) {
    return node;
  }

  for (final child in node.children) {
    final found = _findNodeByPath(child, targetPath);
    if (found != null) {
      return found;
    }
  }

  return null;
}
