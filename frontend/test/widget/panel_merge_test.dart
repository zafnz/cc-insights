import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/panels/panels.dart';
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
import 'package:cc_insights_v2/testing/mock_data.dart';
import 'package:cc_insights_v2/widgets/dialog_observer.dart';
import 'package:checks/checks.dart';
import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_cli_availability_service.dart';
import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  group('Panel Merge/Separate Tests', () {
    late ProjectState project;
    late SelectionState selection;
    late MockBackendService mockBackend;
    late ScriptExecutionService scriptService;
    late WorktreeWatcherService worktreeWatcher;
    late GitService gitService;
    late FakeFileSystemService fakeFileSystem;
    late FileManagerState fileManagerState;
    late DialogObserver dialogObserver;
    late MenuActionService menuActionService;
    late FakeCliAvailabilityService fakeCliAvailability;

    final resources = TestResources();

    Widget createTestApp() {
      return MultiProvider(
        providers: [
          Provider<DialogObserver>.value(value: dialogObserver),
          ChangeNotifierProvider<LogService>.value(value: LogService.instance),
          ChangeNotifierProvider<BackendService>.value(value: mockBackend),
          ChangeNotifierProvider<ProjectState>.value(value: project),
          ChangeNotifierProxyProvider<ProjectState, SelectionState>(
            create: (_) => selection,
            update: (_, __, previous) => previous!,
          ),
          Provider<GitService>.value(value: gitService),
          Provider<FileSystemService>.value(value: fakeFileSystem),
          ChangeNotifierProvider<WorktreeWatcherService>.value(
            value: worktreeWatcher,
          ),
          ChangeNotifierProvider<FileManagerState>.value(
            value: fileManagerState,
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
          home: const MainScreen(),
        ),
      );
    }

    setUp(() async {
      project = MockDataFactory.createMockProject();
      selection = SelectionState(project);
      mockBackend = MockBackendService();
      scriptService = ScriptExecutionService();
      gitService = FakeGitService();
      worktreeWatcher = WorktreeWatcherService(
        gitService: gitService,
        project: project,
        configService: ProjectConfigService(),
        enablePeriodicPolling: false,
      );
      fakeFileSystem = FakeFileSystemService();
      fileManagerState = resources.track(
        FileManagerState(project, fakeFileSystem, selection),
      );
      dialogObserver = DialogObserver();
      menuActionService = MenuActionService();
      fakeCliAvailability = FakeCliAvailabilityService();
      await mockBackend.start();
      fakeFileSystem = FakeFileSystemService();
      fileManagerState = resources.track(
        FileManagerState(project, fakeFileSystem, selection),
      );
    });

    Future<void> setLargeWindowSize(WidgetTester tester) async {
      // Set a larger window size to accommodate all panels
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
    }

    tearDown(() async {
      worktreeWatcher.dispose();
      mockBackend.dispose();
      scriptService.dispose();
      await resources.disposeAll();
    });

    group('Initial State', () {
      testWidgets('renders all panels in initial layout', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Verify all panels are visible
        expect(find.text('Worktrees'), findsOneWidget);
        expect(find.text('Chats'), findsOneWidget);
        expect(find.text('Agents'), findsOneWidget);
        expect(find.text('Conversation'), findsOneWidget);
      });

      testWidgets('renders navigation rail', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Verify navigation rail buttons exist (by their tooltips)
        expect(find.byTooltip('Main View'), findsOneWidget);
        expect(find.byTooltip('Settings'), findsOneWidget);
      });

      testWidgets('renders status bar with stats', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Verify status bar elements
        expect(find.text('Connected'), findsOneWidget);
        // Find worktree count - use findsWidgets since text may appear elsewhere
        expect(find.textContaining('worktrees'), findsWidgets);
        expect(find.textContaining('chats'), findsWidgets);
        expect(find.textContaining('Total \$'), findsOneWidget);
      });
    });

    group('Worktree Panel', () {
      testWidgets('displays worktrees from project state', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Verify worktree items are rendered
        final worktrees = project.allWorktrees;
        for (final wt in worktrees) {
          expect(find.text(wt.data.branch), findsWidgets);
        }
      });

      testWidgets('selecting worktree updates selection state', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        final linkedWorktree = project.linkedWorktrees.first;
        // Find and tap the linked worktree
        await tester.tap(find.text(linkedWorktree.data.branch).first);
        await safePumpAndSettle(tester);

        check(selection.selectedWorktree).equals(linkedWorktree);
      });
    });

    group('Chats Panel', () {
      testWidgets('displays chats when worktree is selected', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select primary worktree (it has chats)
        selection.selectWorktree(project.primaryWorktree);
        await safePumpAndSettle(tester);

        // Verify chats are displayed
        final chats = project.primaryWorktree.chats;
        if (chats.isNotEmpty) {
          expect(find.text(chats.first.data.name), findsWidgets);
        }
      });

      testWidgets('shows placeholder when no worktree selected', (tester) async {
        await setLargeWindowSize(tester);
        // Create project without initial selection
        project.selectWorktree(null);
        selection = SelectionState(project);

        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(find.text('Select a worktree to view chats'), findsOneWidget);
      });
    });

    group('Agents Panel', () {
      testWidgets('shows Chat as first entry when chat selected', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Select a chat with subagents
        final chat = project.primaryWorktree.chats.firstWhere(
          (c) => c.data.subagentConversations.isNotEmpty,
          orElse: () => project.primaryWorktree.chats.first,
        );
        selection.selectChat(chat);
        await safePumpAndSettle(tester);

        // Verify "Chat" appears as first entry in agents list
        // The Agents panel shows: Chat (primary), then subagents
        expect(find.text('Chat'), findsWidgets);
      });

      testWidgets('shows placeholder when no chat selected', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Ensure no chat is selected
        project.primaryWorktree.selectChat(null);
        await safePumpAndSettle(tester);

        expect(find.text('Select a chat to view agents'), findsOneWidget);
      });
    });

    group('Panel Drag Handles', () {
      testWidgets('drag handles are visible in panel headers', (tester) async {
        await setLargeWindowSize(tester);
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Each panel should have a drag indicator icon
        expect(find.byIcon(Icons.drag_indicator), findsWidgets);
      });
    });
  });

  group('ReplaceInterceptResult Enum', () {
    test('allow value exists', () {
      expect(ReplaceInterceptResult.allow, isNotNull);
    });

    test('cancel value exists', () {
      expect(ReplaceInterceptResult.cancel, isNotNull);
    });

    test('handled value exists', () {
      expect(ReplaceInterceptResult.handled, isNotNull);
    });
  });

  group('PanelWrapper Widget', () {
    testWidgets('renders with title and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DragHandleProvider(
              dragHandle: const Icon(Icons.drag_indicator),
              child: const PanelWrapper(
                title: 'Test Panel',
                icon: Icons.folder,
                child: Text('Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Panel'), findsOneWidget);
      expect(find.byIcon(Icons.folder), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('renders with context menu items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DragHandleProvider(
              dragHandle: const Icon(Icons.drag_indicator),
              child: PanelWrapper(
                title: 'Test Panel',
                icon: Icons.folder,
                contextMenuItems: [
                  PopupMenuItem<String>(
                    value: 'test',
                    child: const Text('Test Action'),
                  ),
                ],
                child: const Text('Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Test Panel'), findsOneWidget);
    });
  });

  group('ChatsAgentsPanel Widget', () {
    testWidgets('renders with title Chats', (tester) async {
      final project = MockDataFactory.createMockProject();
      final selection = SelectionState(project);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DragHandleProvider(
                dragHandle: const Icon(Icons.drag_indicator),
                child: ChatsAgentsPanel(
                  onSeparateAgents: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Title should be "Chats" (merged panel keeps the primary panel's name)
      expect(find.text('Chats'), findsOneWidget);
    });

    testWidgets('onSeparateAgents callback is invoked from context menu',
        (tester) async {
      var separateCalled = false;
      final project = MockDataFactory.createMockProject();
      final selection = SelectionState(project);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DragHandleProvider(
                dragHandle: const Icon(Icons.drag_indicator),
                child: ChatsAgentsPanel(
                  onSeparateAgents: () {
                    separateCalled = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find the header area and trigger context menu via secondary tap
      final headerFinder = find.text('Chats');
      expect(headerFinder, findsOneWidget);

      // Get the location of the header
      final headerCenter = tester.getCenter(headerFinder);

      // Perform a secondary tap (right-click)
      await tester.tapAt(headerCenter, buttons: kSecondaryMouseButton);
      await safePumpAndSettle(tester);

      // Context menu should appear with "Separate Agents" option
      expect(find.text('Separate Agents'), findsOneWidget);

      // Tap on "Separate Agents"
      await tester.tap(find.text('Separate Agents'));
      await safePumpAndSettle(tester);

      check(separateCalled).isTrue();
    });
  });

  group('WorktreesChatsAgentsPanel Widget', () {
    testWidgets('renders with title Worktrees', (tester) async {
      final project = MockDataFactory.createMockProject();
      final selection = SelectionState(project);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DragHandleProvider(
                dragHandle: const Icon(Icons.drag_indicator),
                child: WorktreesChatsAgentsPanel(
                  onSeparateChats: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Title should be "Worktrees"
      expect(find.text('Worktrees'), findsOneWidget);
    });

    testWidgets('displays worktrees with nested chats', (tester) async {
      final project = MockDataFactory.createMockProject();
      final selection = SelectionState(project);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DragHandleProvider(
                dragHandle: const Icon(Icons.drag_indicator),
                child: WorktreesChatsAgentsPanel(
                  onSeparateChats: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Verify worktree branches are displayed
      for (final wt in project.allWorktrees) {
        expect(find.text(wt.data.branch), findsWidgets);
      }
    });

    testWidgets('onSeparateChats callback is invoked from context menu',
        (tester) async {
      var separateCalled = false;
      final project = MockDataFactory.createMockProject();
      final selection = SelectionState(project);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(value: project),
            ChangeNotifierProvider<SelectionState>.value(value: selection),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DragHandleProvider(
                dragHandle: const Icon(Icons.drag_indicator),
                child: WorktreesChatsAgentsPanel(
                  onSeparateChats: () {
                    separateCalled = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Find the header and trigger context menu
      final headerFinder = find.text('Worktrees');
      expect(headerFinder, findsOneWidget);

      final headerCenter = tester.getCenter(headerFinder);
      await tester.tapAt(headerCenter, buttons: kSecondaryMouseButton);
      await safePumpAndSettle(tester);

      // Context menu should appear with "Separate Chats" option
      expect(find.text('Separate Chats'), findsOneWidget);

      await tester.tap(find.text('Separate Chats'));
      await safePumpAndSettle(tester);

      check(separateCalled).isTrue();
    });
  });
}
