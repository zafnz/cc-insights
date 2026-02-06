import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/screens/file_manager_screen.dart';
import 'package:cc_insights_v2/screens/main_screen.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/log_service.dart';
import 'package:cc_insights_v2/services/menu_action_service.dart';
import 'package:cc_insights_v2/services/project_config_service.dart';
import 'package:cc_insights_v2/services/script_execution_service.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:cc_insights_v2/services/worktree_watcher_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:cc_insights_v2/widgets/dialog_observer.dart';
import 'package:cc_insights_v2/widgets/navigation_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

/// Integration tests for Phase 5: Navigation Integration.
///
/// Covers:
/// - Task 5.2: Navigation and Screen Switching
/// - Task 5.3: Provider Integration
/// - Task 5.4: State Isolation
void main() {
  group('Navigation Integration (Phase 5)', () {
    final resources = TestResources();
    late ProjectState project;
    late SelectionState selectionState;
    late FileManagerState fileManagerState;
    late FakeFileSystemService fakeFileSystem;
    late MockBackendService mockBackend;
    late GitService gitService;
    late WorktreeWatcherService worktreeWatcher;
    late ScriptExecutionService scriptService;
    late DialogObserver dialogObserver;
    late MenuActionService menuActionService;
    late FakeCliAvailabilityService fakeCliAvailability;

    /// Creates a project with primary and linked worktrees for testing.
    ProjectState createProject() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/Users/test/my-project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      final linkedWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/Users/test/my-project-linked',
          isPrimary: false,
          branch: 'feature',
        ),
      );

      final proj = ProjectState(
        const ProjectData(
          name: 'My Project',
          repoRoot: '/Users/test/my-project',
        ),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );

      proj.addWorktree(linkedWorktree);
      return proj;
    }

    /// Creates the full app with all providers.
    Widget createApp() {
      return MultiProvider(
        providers: [
          Provider<DialogObserver>.value(value: dialogObserver),
          ChangeNotifierProvider<LogService>.value(
            value: LogService.instance,
          ),
          ChangeNotifierProvider<BackendService>.value(
            value: mockBackend,
          ),
          Provider<GitService>.value(
            value: gitService,
          ),
          Provider<FileSystemService>.value(
            value: fakeFileSystem,
          ),
          ChangeNotifierProvider<ProjectState>.value(
            value: project,
          ),
          ChangeNotifierProvider<SelectionState>.value(
            value: selectionState,
          ),
          ChangeNotifierProvider<FileManagerState>.value(
            value: fileManagerState,
          ),
          ChangeNotifierProvider<WorktreeWatcherService>.value(
            value: worktreeWatcher,
          ),
          Provider<ProjectConfigService>(
            create: (_) => ProjectConfigService(),
          ),
          ChangeNotifierProvider<ScriptExecutionService>.value(
            value: scriptService,
          ),
          ChangeNotifierProvider<SettingsService>.value(
            value: SettingsService(),
          ),
          ChangeNotifierProvider<MenuActionService>.value(
            value: menuActionService,
          ),
          ChangeNotifierProvider<CliAvailabilityService>.value(
            value: fakeCliAvailability,
          ),
        ],
        child: const MaterialApp(
          home: MainScreen(),
        ),
      );
    }

    setUp(() {
      project = createProject();
      fakeFileSystem = FakeFileSystemService();
      mockBackend = MockBackendService();
      mockBackend.start();
      gitService = FakeGitService();
      scriptService = ScriptExecutionService();
      worktreeWatcher = WorktreeWatcherService(
        gitService: gitService,
        project: project,
        configService: ProjectConfigService(),
        enablePeriodicPolling: false,
      );

      selectionState = resources.track(SelectionState(project));
      fileManagerState = resources.track(
        FileManagerState(project, fakeFileSystem, selectionState),
      );
      dialogObserver = DialogObserver();
      menuActionService = MenuActionService();
      fakeCliAvailability = FakeCliAvailabilityService();

      // Set up fake file system
      fakeFileSystem.addDirectory('/Users/test/my-project');
      fakeFileSystem.addDirectory('/Users/test/my-project/src');
      fakeFileSystem.addTextFile(
        '/Users/test/my-project/src/main.dart',
        'void main() {}',
      );
      fakeFileSystem.addDirectory('/Users/test/my-project-linked');
      fakeFileSystem.addTextFile(
        '/Users/test/my-project-linked/feature.txt',
        'feature content',
      );
    });

    tearDown(() async {
      worktreeWatcher.dispose();
      scriptService.dispose();
      await resources.disposeAll();
    });

    group('Navigation and Screen Switching (Task 5.2)', () {
      testWidgets(
        'switch from main to file manager',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Initially on main screen (index 0)
          expect(find.byType(MainScreen), findsOneWidget);
          expect(find.byType(FileManagerScreen), findsNothing);

          // Navigation rail should show main view selected
          final navRail = tester.widget<AppNavigationRail>(
            find.byType(AppNavigationRail),
          );
          expect(navRail.selectedIndex, 0);

          // Click file manager button
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Should now be on file manager screen
          expect(find.byType(FileManagerScreen), findsOneWidget);
        },
      );

      testWidgets(
        'switch from file manager to main',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Go to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);
          expect(find.byType(FileManagerScreen), findsOneWidget);

          // Click main view button
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Should be back on main screen
          // MainScreen is always in the widget tree, but file manager
          // should not be visible
          final indexedStack = tester.widget<IndexedStack>(
            find.byType(IndexedStack),
          );
          expect(indexedStack.index, 0);
        },
      );

      testWidgets(
        'state persists across switches',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // On main screen, select a worktree
          // Find worktree in main screen's worktree panel
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          expect(selectionState.selectedWorktree?.data.branch, 'main');

          // Switch to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Switch back to main
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Main screen selection should still be 'main'
          expect(selectionState.selectedWorktree?.data.branch, 'main');
        },
      );

      testWidgets(
        'navigation rail updates selection',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Initially selected index 0
          var navRail = tester.widget<AppNavigationRail>(
            find.byType(AppNavigationRail),
          );
          expect(navRail.selectedIndex, 0);

          // Click file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Selected index should be 1
          navRail = tester.widget<AppNavigationRail>(
            find.byType(AppNavigationRail),
          );
          expect(navRail.selectedIndex, 1);

          // Click main view
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Selected index back to 0
          navRail = tester.widget<AppNavigationRail>(
            find.byType(AppNavigationRail),
          );
          expect(navRail.selectedIndex, 0);
        },
      );

      testWidgets(
        'both screens render correctly',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Main screen should have its panels
          expect(find.text('Worktrees'), findsWidgets);

          // Switch to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // File manager should have its panels
          expect(find.text('Files'), findsOneWidget);
          expect(find.text('File Viewer'), findsOneWidget);

          // Switch back
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Main screen panels should be visible again
          expect(find.text('Worktrees'), findsWidgets);
        },
      );

      testWidgets(
        'IndexedStack keeps both screens in memory',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Find IndexedStack
          final stackFinder = find.byType(IndexedStack);
          expect(stackFinder, findsOneWidget);

          final stack = tester.widget<IndexedStack>(stackFinder);
          expect(stack.children.length, 4);
          expect(stack.index, 0); // Initially showing main screen
        },
      );

      testWidgets(
        'rapid screen switching works correctly',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Switch back and forth rapidly
          for (int i = 0; i < 3; i++) {
            await tester.tap(find.byTooltip('File Manager'));
            await tester.pump();
            await tester.pump();

            await tester.tap(find.byTooltip('Main View'));
            await tester.pump();
            await tester.pump();
          }

          await safePumpAndSettle(tester);

          // Should end up on main screen with no errors
          final stack = tester.widget<IndexedStack>(
            find.byType(IndexedStack),
          );
          expect(stack.index, 0);
        },
      );
    });

    group('Provider Integration (Task 5.3)', () {
      testWidgets(
        'FileManagerState accessible via Provider',
        (tester) async {
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
                ChangeNotifierProvider<FileManagerState>.value(
                  value: fileManagerState,
                ),
              ],
              child: MaterialApp(
                home: Scaffold(body: testWidget),
              ),
            ),
          );
          await safePumpAndSettle(tester);

          // FileManagerState should be accessible
          expect(
            capturedContext.read<FileManagerState>(),
            same(fileManagerState),
          );
        },
      );

      testWidgets(
        'FileSystemService accessible via Provider',
        (tester) async {
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
                Provider<FileSystemService>.value(
                  value: fakeFileSystem,
                ),
              ],
              child: MaterialApp(
                home: Scaffold(body: testWidget),
              ),
            ),
          );
          await safePumpAndSettle(tester);

          // FileSystemService should be accessible
          expect(
            capturedContext.read<FileSystemService>(),
            same(fakeFileSystem),
          );
        },
      );

      testWidgets(
        'dependencies resolved correctly in full app',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Navigate to file manager to ensure it builds
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // If we got here without errors, providers are working
          expect(find.byType(FileManagerScreen), findsOneWidget);
        },
      );

      testWidgets(
        'all required providers available in MainScreen',
        (tester) async {
          late BuildContext capturedContext;

          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Use a builder to capture context from inside the screen
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider<DialogObserver>.value(value: dialogObserver),
                ChangeNotifierProvider<LogService>.value(
                  value: LogService.instance,
                ),
                ChangeNotifierProvider<BackendService>.value(
                  value: mockBackend,
                ),
                Provider<GitService>.value(
                  value: gitService,
                ),
                Provider<FileSystemService>.value(
                  value: fakeFileSystem,
                ),
                ChangeNotifierProvider<ProjectState>.value(
                  value: project,
                ),
                ChangeNotifierProvider<SelectionState>.value(
                  value: selectionState,
                ),
                ChangeNotifierProvider<FileManagerState>.value(
                  value: fileManagerState,
                ),
                ChangeNotifierProvider<WorktreeWatcherService>.value(
                  value: worktreeWatcher,
                ),
                Provider<ProjectConfigService>(
                  create: (_) => ProjectConfigService(),
                ),
                ChangeNotifierProvider<ScriptExecutionService>.value(
                  value: scriptService,
                ),
                ChangeNotifierProvider<SettingsService>.value(
                  value: SettingsService(),
                ),
                ChangeNotifierProvider<MenuActionService>.value(
                  value: menuActionService,
                ),
                ChangeNotifierProvider<CliAvailabilityService>.value(
                  value: fakeCliAvailability,
                ),
              ],
              child: MaterialApp(
                home: Builder(
                  builder: (context) {
                    capturedContext = context;
                    return const MainScreen();
                  },
                ),
              ),
            ),
          );
          await safePumpAndSettle(tester);

          // All providers should be accessible
          expect(
            capturedContext.read<BackendService>(),
            same(mockBackend),
          );
          expect(
            capturedContext.read<ProjectState>(),
            same(project),
          );
          expect(
            capturedContext.read<SelectionState>(),
            same(selectionState),
          );
          expect(
            capturedContext.read<FileManagerState>(),
            same(fileManagerState),
          );
          expect(
            capturedContext.read<FileSystemService>(),
            same(fakeFileSystem),
          );
        },
      );
    });

    group('State Synchronization (Task 5.4)', () {
      // Note: FileManagerState now synchronizes with SelectionState.
      // When a worktree is selected in SelectionState, FileManagerState
      // automatically picks it up and vice versa.

      testWidgets(
        'SelectionState and FileManagerState are synchronized',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // On main screen, select worktree 'main'
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          // Both states should have the same selection (synchronized)
          expect(selectionState.selectedWorktree?.data.branch, 'main');
          expect(fileManagerState.selectedWorktree?.data.branch, 'main');

          // Switch to file manager and select 'feature'
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // Both states should now have 'feature' selected (synchronized)
          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'feature',
          );
          expect(selectionState.selectedWorktree?.data.branch, 'feature');
        },
      );

      testWidgets(
        'selecting worktree in main screen updates file manager',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // On main screen, select 'main'
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          // Both should be synchronized
          expect(selectionState.selectedWorktree?.data.branch, 'main');
          expect(fileManagerState.selectedWorktree?.data.branch, 'main');

          // Select different worktree on main screen
          await tester.tap(find.text('feature').first);
          await safePumpAndSettle(tester);

          // Both should update together
          expect(selectionState.selectedWorktree?.data.branch, 'feature');
          expect(fileManagerState.selectedWorktree?.data.branch, 'feature');
        },
      );

      testWidgets(
        'selecting worktree in file manager updates main screen',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // On main screen, select 'main'
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          expect(selectionState.selectedWorktree?.data.branch, 'main');

          // Switch to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Select 'feature' in file manager
          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // Both should be synchronized to 'feature'
          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'feature',
          );
          expect(selectionState.selectedWorktree?.data.branch, 'feature');

          // Switch back to main screen
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Main screen should also show 'feature'
          expect(selectionState.selectedWorktree?.data.branch, 'feature');
        },
      );

      testWidgets(
        'worktree selection persists across screen switches',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // On main screen, select 'main'
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          // Switch to file manager and select 'feature'
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // Both states should have 'feature' selected
          expect(selectionState.selectedWorktree?.data.branch, 'feature');
          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'feature',
          );

          // Switch back and forth - selection should persist
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);
          expect(selectionState.selectedWorktree?.data.branch, 'feature');

          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);
          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'feature',
          );
        },
      );

      testWidgets(
        'file selection in file manager independent from main screen',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Go to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          // Expand src directory
          await tester.tap(find.text('src'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          // Select main.dart file
          await tester.tap(find.text('main.dart'));
          await tester.pump(const Duration(milliseconds: 350));
          await safePumpAndSettle(tester);

          expect(
            fileManagerState.selectedFilePath,
            '/Users/test/my-project/src/main.dart',
          );

          // Switch to main screen
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          // Main screen's file selection should be null
          expect(selectionState.selectedFilePath, isNull);

          // Switch back to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // File selection should persist
          expect(
            fileManagerState.selectedFilePath,
            '/Users/test/my-project/src/main.dart',
          );
        },
      );

      testWidgets(
        'synchronized state maintained during rapid switching',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Select worktree
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // Rapidly switch screens
          for (int i = 0; i < 5; i++) {
            await tester.tap(find.byTooltip('Main View'));
            await tester.pump();
            await tester.pump();

            await tester.tap(find.byTooltip('File Manager'));
            await tester.pump();
            await tester.pump();
          }

          await safePumpAndSettle(tester);

          // Both states should have the same selection (synchronized)
          expect(selectionState.selectedWorktree?.data.branch, 'feature');
          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'feature',
          );
        },
      );

      testWidgets(
        'clearing selection in one state does not affect the other',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Set up selections in both states
          await tester.tap(find.text('main').first);
          await safePumpAndSettle(tester);

          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          await tester.tap(find.text('feature'));
          await safePumpAndSettle(tester);

          // Clear file manager selection by selecting a different worktree
          await tester.tap(find.text('main'));
          await safePumpAndSettle(tester);

          expect(
            fileManagerState.selectedWorktree?.data.branch,
            'main',
          );

          // Switch to main screen - selection should still be 'main'
          await tester.tap(find.byTooltip('Main View'));
          await safePumpAndSettle(tester);

          expect(selectionState.selectedWorktree?.data.branch, 'main');
        },
      );
    });

    group('Cross-Screen Integration', () {
      testWidgets(
        'project state shared between both screens',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Both screens should see the same project
          final mainScreenProject = selectionState.project;
          expect(mainScreenProject, same(project));

          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // File manager should also see the same project
          expect(fileManagerState.project, same(project));
          expect(fileManagerState.project, same(mainScreenProject));
        },
      );

      testWidgets(
        'adding worktree visible in both screens',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Add a new worktree to the project
          final newWorktree = WorktreeState(
            const WorktreeData(
              worktreeRoot: '/Users/test/my-project-new',
              isPrimary: false,
              branch: 'new-feature',
            ),
          );
          project.addWorktree(newWorktree);

          // Set up file system for new worktree
          fakeFileSystem.addDirectory('/Users/test/my-project-new');

          await safePumpAndSettle(tester);

          // New worktree should appear in main screen
          expect(find.text('new-feature'), findsWidgets);

          // Switch to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // New worktree should also appear in file manager
          expect(find.text('new-feature'), findsWidgets);
        },
      );

      testWidgets(
        'navigation rail visible in both screens',
        (tester) async {
          await tester.pumpWidget(createApp());
          await safePumpAndSettle(tester);

          // Navigation rail should be present on main screen
          expect(find.byType(AppNavigationRail), findsOneWidget);

          // Switch to file manager
          await tester.tap(find.byTooltip('File Manager'));
          await safePumpAndSettle(tester);

          // Navigation rail should still be present
          expect(find.byType(AppNavigationRail), findsOneWidget);
        },
      );
    });
  });
}
