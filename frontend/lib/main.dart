import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'models/output_entry.dart';
import 'models/project.dart';
import 'models/worktree.dart';
import 'screens/main_screen.dart';
import 'screens/replay_demo_screen.dart';
import 'services/ask_ai_service.dart';
import 'services/backend_service.dart';
import 'services/git_service.dart';
import 'services/persistence_service.dart';
import 'services/project_restore_service.dart';
import 'services/runtime_config.dart';
import 'services/sdk_message_handler.dart';
import 'services/worktree_watcher_service.dart';
import 'state/selection_state.dart';
import 'testing/mock_backend.dart';
import 'testing/mock_data.dart';

/// Global flag to force mock data usage in tests.
///
/// Set this to true before running integration tests that need mock data.
bool useMockData = false;

void main(List<String> args) {
  // Initialize runtime config from command line arguments.
  // First positional arg is the working directory.
  debugPrint('main() args: $args');
  RuntimeConfig.initialize(args);
  debugPrint('RuntimeConfig.useMockData: ${RuntimeConfig.instance.useMockData}');

  runApp(const CCInsightsApp());
}

/// Creates a ProjectState synchronously for mock data.
///
/// Used when [useMockData] is true or in test environments.
ProjectState _createMockProject() {
  return MockDataFactory.createMockProject();
}

/// Creates a ProjectState synchronously as a fallback.
///
/// Used when we need a project immediately but can't use async restore.
ProjectState _createFallbackProject() {
  final config = RuntimeConfig.instance;
  final workingDir = config.workingDirectory;
  final projectName = config.projectName;

  // Create the primary worktree from the working directory.
  final primaryWorktree = WorktreeState(
    WorktreeData(
      worktreeRoot: workingDir,
      isPrimary: true,
      branch: 'main', // TODO: Get actual branch from git
    ),
  );

  // Create the project with just the primary worktree.
  return ProjectState(
    ProjectData(name: projectName, repoRoot: workingDir),
    primaryWorktree,
  );
}

/// Determines if mock data should be used.
///
/// Returns true if either:
/// - The [useMockData] global flag is set (for tests)
/// - The `--mock` command-line flag was passed
bool _shouldUseMockData() {
  return useMockData || RuntimeConfig.instance.useMockData;
}

/// CC-Insights V2 - Desktop application for monitoring Claude Code agents.
class CCInsightsApp extends StatefulWidget {
  /// Optional BackendService instance for dependency injection in tests.
  final BackendService? backendService;

  /// Optional SdkMessageHandler instance for dependency injection in tests.
  final SdkMessageHandler? messageHandler;

  const CCInsightsApp({
    super.key,
    this.backendService,
    this.messageHandler,
  });

  @override
  State<CCInsightsApp> createState() => _CCInsightsAppState();
}

class _CCInsightsAppState extends State<CCInsightsApp>
    with WidgetsBindingObserver {
  /// The backend service instance - created once in initState.
  BackendService? _backend;

  /// The SDK message handler - created once in initState.
  SdkMessageHandler? _handler;

  /// The project restore service - shared for persistence operations.
  ProjectRestoreService? _restoreService;

  /// The AskAI service for one-shot AI queries.
  AskAiService? _askAiService;

  /// Future for project restoration.
  Future<ProjectState>? _projectFuture;

  /// Cached project for mock mode (synchronous path).
  ProjectState? _mockProject;

  /// The project state - cached for app lifecycle callbacks.
  ProjectState? _project;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app is detached (terminating), write session quit markers
    if (state == AppLifecycleState.detached) {
      // Note: We cannot await in didChangeAppLifecycleState, but we fire
      // off the async operation. The OS should give us enough time to complete.
      _handleAppTermination();
    }
  }

  /// Initialize services once on first build.
  ///
  /// This runs in initState so services are created only once,
  /// not on every hot reload.
  void _initializeServices() {
    final shouldUseMock = _shouldUseMockData();

    // Create or use injected BackendService
    if (widget.backendService != null) {
      _backend = widget.backendService;
    } else if (shouldUseMock) {
      // Use MockBackendService for mock mode
      final mockBackend = MockBackendService();
      mockBackend.nextSessionConfig = const MockResponseConfig(
        autoReply: true,
        replyText: 'Mock response to: {message}',
      );
      mockBackend.start();
      _backend = mockBackend;
    } else {
      _backend = BackendService();
      _backend!.start();
    }

    // Create or use injected SdkMessageHandler
    _handler = widget.messageHandler ?? SdkMessageHandler();

    // Create the project restore service for persistence operations
    _restoreService = ProjectRestoreService();

    // Create the AskAI service for one-shot AI queries
    _askAiService = AskAiService();

    // Initialize project (sync for mock, async for real)
    if (shouldUseMock) {
      _mockProject = _createMockProject();
    } else {
      _projectFuture = _restoreProject();
    }
  }

  /// Handles app termination by writing session quit markers.
  Future<void> _handleAppTermination() async {
    if (_project == null) return;

    debugPrint('App terminating - writing session quit markers');

    // Collect all quit marker writes
    final writes = <Future<void>>[];
    final persistence = PersistenceService();

    // Iterate through all worktrees and their chats
    for (final worktree in _project!.allWorktrees) {
      for (final chat in worktree.chats) {
        // Write quit marker if chat has a session ID (indicating it was active)
        // We check lastSessionId instead of hasActiveSession because the session
        // object may already be disposed during app termination
        if (chat.lastSessionId != null) {
          debugPrint(
            'Writing quit marker for chat ${chat.data.id} '
            '(session: ${chat.lastSessionId}) in '
            'worktree ${worktree.data.worktreeRoot}',
          );

          final entry = SessionMarkerEntry(
            timestamp: DateTime.now(),
            markerType: SessionMarkerType.quit,
          );

          // Add to UI immediately (synchronous)
          chat.addEntry(entry);

          // But also explicitly persist (async) - collect the future
          if (chat.projectId != null) {
            writes.add(
              persistence.appendChatEntry(
                chat.projectId!,
                chat.data.id,
                entry,
              ),
            );
          }
        }
      }
    }

    // Wait for all writes to complete before returning
    if (writes.isNotEmpty) {
      try {
        await Future.wait(writes);
        debugPrint('All quit markers persisted successfully');
      } catch (e) {
        debugPrint('Error persisting quit markers: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Only dispose services we created, not injected ones
    if (widget.backendService == null) {
      _backend?.dispose();
    }
    if (widget.messageHandler == null) {
      _handler?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use mock data if explicitly requested or in test environment
    final shouldUseMock = useMockData || _shouldUseMockData();

    if (shouldUseMock) {
      // Synchronous path for mock data
      _project = _mockProject!;
      return _buildApp(_project!);
    } else {
      // Async path for restoring from persistence
      return FutureBuilder<ProjectState>(
        future: _projectFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingScreen();
          }

          if (snapshot.hasError) {
            debugPrint('Error restoring project: ${snapshot.error}');
            // Fall back to creating a new project synchronously
            _project = _createFallbackProject();
            return _buildApp(_project!);
          }

          _project = snapshot.data ?? _createFallbackProject();
          return _buildApp(_project!);
        },
      );
    }
  }

  /// Restores the project from persistence.
  Future<ProjectState> _restoreProject() async {
    final config = RuntimeConfig.instance;
    final (project, isNew) = await _restoreService!.restoreOrCreateProject(
      config.workingDirectory,
    );

    if (isNew) {
      debugPrint('Created new project: ${project.data.name}');
    } else {
      debugPrint('Restored project: ${project.data.name}');
    }

    return project;
  }

  /// Builds the loading screen shown while restoring project.
  Widget _buildLoadingScreen() {
    return MaterialApp(
      title: 'CC Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading project...'),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the main app with the given project.
  Widget _buildApp(ProjectState project) {
    return MultiProvider(
      providers: [
        // Backend service for spawning SDK sessions
        ChangeNotifierProvider<BackendService>.value(value: _backend!),
        // SDK message handler (stateless - shared across all chats)
        Provider<SdkMessageHandler>.value(value: _handler!),
        // Project restore service for persistence operations
        Provider<ProjectRestoreService>.value(value: _restoreService!),
        // Git service for git operations (stateless)
        Provider<GitService>.value(value: const RealGitService()),
        // AskAI service for one-shot AI queries
        Provider<AskAiService>.value(value: _askAiService!),
        // Project state
        ChangeNotifierProvider<ProjectState>.value(value: project),
        // Selection state depends on project
        ChangeNotifierProxyProvider<ProjectState, SelectionState>(
          create: (context) => SelectionState(context.read<ProjectState>()),
          update: (context, project, previous) =>
              previous ?? SelectionState(project),
        ),
        // Worktree watcher service for monitoring git status changes
        ChangeNotifierProxyProvider2<GitService, ProjectState,
            WorktreeWatcherService>(
          create: (context) => WorktreeWatcherService(
            gitService: context.read<GitService>(),
            project: context.read<ProjectState>(),
          ),
          update: (context, gitService, project, previous) =>
              previous ??
              WorktreeWatcherService(
                gitService: gitService,
                project: project,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'CC Insights',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const MainScreen(),
        routes: {
          '/replay': (context) => const ReplayDemoScreen(),
        },
      ),
    );
  }

  /// Build a compact desktop-appropriate theme.
  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      // Compact text theme for desktop
      textTheme: TextTheme(
        // Panel headers
        titleSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: brightness == Brightness.dark
              ? Colors.white70
              : Colors.black54,
        ),
        // List item primary text
        bodyMedium: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.normal,
        ),
        // List item secondary text (monospace for paths)
        bodySmall: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.normal,
        ),
        // Status indicators
        labelSmall: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}
