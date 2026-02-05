import 'dart:async';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'models/output_entry.dart';
import 'models/project.dart';
import 'models/worktree.dart';
import 'screens/main_screen.dart';
import 'screens/replay_demo_screen.dart';
import 'screens/welcome_screen.dart';
import 'widgets/directory_validation_dialog.dart';
import 'services/ask_ai_service.dart';
import 'services/log_service.dart';
import 'services/backend_service.dart';
import 'services/file_system_service.dart';
import 'services/git_service.dart';
import 'services/notification_service.dart';
import 'services/persistence_service.dart';
import 'services/project_restore_service.dart';
import 'services/runtime_config.dart';
import 'services/project_config_service.dart';
import 'services/settings_service.dart';
import 'services/script_execution_service.dart';
import 'services/sdk_message_handler.dart';
import 'services/worktree_watcher_service.dart';
import 'state/file_manager_state.dart';
import 'state/selection_state.dart';
import 'state/theme_state.dart';
import 'testing/mock_backend.dart';
import 'testing/mock_data.dart';
import 'widgets/dialog_observer.dart';

/// Global flag to force mock data usage in tests.
///
/// Set this to true before running integration tests that need mock data.
bool useMockData = false;

/// The original debugPrintSynchronously function, saved before we override it.
final DebugPrintCallback _originalDebugPrint = debugPrintSynchronously;

/// Custom debugPrint that logs to LogService while also printing to stdout.
///
/// This replaces Flutter's default debugPrint to capture debug output in the
/// centralized logging system while preserving the standard console output.
void _loggingDebugPrint(String? message, {int? wrapWidth}) {
  // Always forward to stdout (original behavior)
  _originalDebugPrint(message, wrapWidth: wrapWidth);

  // Also log to LogService if message is not null/empty
  if (message != null && message.isNotEmpty) {
    LogService.instance.debug('Flutter', 'print', message);
  }
}

void main(List<String> args) async {
  // Ensure Flutter bindings are initialized before any async work
  WidgetsFlutterBinding.ensureInitialized();

  // Override debugPrint to also log to LogService while preserving stdout output
  debugPrint = _loggingDebugPrint;

  // Initialize runtime config from command line arguments.
  // First positional arg is the working directory.
  debugPrint('main() args: $args');
  RuntimeConfig.initialize(args);
  debugPrint(
    'RuntimeConfig.useMockData: ${RuntimeConfig.instance.useMockData}',
  );

  // Set the config directory if specified via --config-dir
  final configDir = RuntimeConfig.instance.configDir;
  if (configDir != null) {
    debugPrint('Using config directory: $configDir');
    PersistenceService.setBaseDir(configDir);
  }

  // Initialize the notification service for desktop notifications
  await NotificationService.instance.initialize();

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

  const CCInsightsApp({super.key, this.backendService, this.messageHandler});

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

  /// The settings service for application preferences.
  SettingsService? _settingsService;

  /// The persistence service for storing project/chat data.
  PersistenceService? _persistenceService;

  /// Dialog observer for tracking open dialogs.
  /// Used to suspend keyboard interception while dialogs are open.
  final DialogObserver _dialogObserver = DialogObserver();

  /// Theme state for dynamic theme switching.
  ThemeState? _themeState;

  /// Future for project restoration.
  Future<ProjectState>? _projectFuture;

  /// Cached project for mock mode (synchronous path).
  ProjectState? _mockProject;

  /// The project state - cached for app lifecycle callbacks.
  ProjectState? _project;

  /// Whether a project has been selected (either from CLI or welcome screen).
  bool _projectSelected = false;

  /// Whether we need to validate the directory before loading.
  /// Set to true when launched from CLI with a potentially problematic directory.
  bool _needsValidation = false;

  /// The git info for the directory being validated.
  DirectoryGitInfo? _pendingValidationInfo;

  /// Subscription to forward SdkLogger entries to LogService.
  StreamSubscription<sdk.LogEntry>? _sdkLogSubscription;

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

    // Initialize application logging
    _initializeLogging();

    // Enable SDK debug logging to file
    _initializeSdkLogging();

    // Forward SDK logs to the central LogService
    _sdkLogSubscription = sdk.SdkLogger.instance.logs.listen(_forwardSdkLog);

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
    }

    // Create the project restore service for persistence operations
    _restoreService = ProjectRestoreService();

    // Create the persistence service for storing project/chat data
    _persistenceService = PersistenceService();

    // Create and load the settings service (fire-and-forget load)
    _settingsService = SettingsService();
    _settingsService!.load().then((_) {
      if (!shouldUseMock && widget.backendService == null) {
        _backend?.start(type: RuntimeConfig.instance.defaultBackend);
      }
    });

    // Create the AskAI service for one-shot AI queries
    _askAiService = AskAiService();

    // Create theme state and sync from settings service
    _themeState = ThemeState();
    _themeState!.addListener(_onThemeChanged);
    _settingsService!.addListener(_syncThemeFromSettings);

    // Listen for changes to debug SDK logging setting
    RuntimeConfig.instance.addListener(_onRuntimeConfigChanged);

    // Create or use injected SdkMessageHandler
    // Pass askAiService for auto-generating chat titles
    _handler =
        widget.messageHandler ?? SdkMessageHandler(askAiService: _askAiService);

    // Initialize project (sync for mock, async for CLI launch)
    // If showing welcome screen, defer project loading until user selects one
    if (shouldUseMock) {
      _mockProject = _createMockProject();
      _projectSelected = true;
    } else if (RuntimeConfig.instance.launchedFromCli) {
      // Launched from CLI - need to validate the directory first
      _needsValidation = true;
      _validateDirectory(RuntimeConfig.instance.workingDirectory);
    }
    // Otherwise, show welcome screen and wait for user to select a project
  }

  /// Rebuilds the widget tree when theme settings change.
  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  /// Syncs theme values from [SettingsService] to [ThemeState].
  void _syncThemeFromSettings() {
    if (_settingsService == null || _themeState == null) return;
    final colorValue = _settingsService!
        .getValue<int>('appearance.seedColor');
    _themeState!.setSeedColor(Color(colorValue));
    final modeStr = _settingsService!
        .getValue<String>('appearance.themeMode');
    _themeState!.setThemeMode(
      ThemeState.parseThemeMode(modeStr),
    );
    final inputColorValue = _settingsService!
        .getValue<int>('appearance.inputTextColor');
    _themeState!.setInputTextColor(
      inputColorValue == 0 ? null : Color(inputColorValue),
    );
  }

  /// Handles changes to RuntimeConfig (like debug SDK logging).
  void _onRuntimeConfigChanged() {
    // Handle SDK debug logging setting
    final shouldLog = RuntimeConfig.instance.debugSdkLogging;
    final home = Platform.environment['HOME'] ?? '/tmp';
    final logPath = '$home/ccinsights.debug.jsonl';

    sdk.SdkLogger.instance.debugEnabled = shouldLog;
    if (shouldLog) {
      sdk.SdkLogger.instance.enableFileLogging(logPath);
    } else {
      sdk.SdkLogger.instance.disableFileLogging();
    }

    // Handle application logging settings
    _updateLoggingConfig();
  }

  /// Updates LogService configuration from RuntimeConfig.
  void _updateLoggingConfig() {
    final config = RuntimeConfig.instance;
    final logPath = _expandPath(config.loggingFilePath);

    // Update minimum level
    LogService.instance.minimumLevel = _parseLogLevel(config.loggingMinimumLevel);

    // Update file logging
    if (logPath.isEmpty) {
      LogService.instance.disableFileLogging();
    } else {
      LogService.instance.enableFileLogging(logPath);
    }
  }

  /// Parses a log level string to LogLevel enum.
  LogLevel _parseLogLevel(String level) {
    return switch (level) {
      'debug' => LogLevel.debug,
      'info' => LogLevel.info,
      'notice' => LogLevel.notice,
      'warn' => LogLevel.warn,
      'error' => LogLevel.error,
      _ => LogLevel.debug,
    };
  }

  /// Expands ~ to home directory in a path.
  String _expandPath(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return home + path.substring(1);
      }
    } else if (path == '~') {
      return Platform.environment['HOME'] ?? path;
    }
    return path;
  }

  /// Forwards an SDK log entry to the central LogService.
  void _forwardSdkLog(sdk.LogEntry entry) {
    // Map SDK log level to app log level
    final level = switch (entry.level) {
      sdk.LogLevel.debug => LogLevel.debug,
      sdk.LogLevel.info => LogLevel.info,
      sdk.LogLevel.warning => LogLevel.warn,
      sdk.LogLevel.error => LogLevel.error,
    };

    // Determine the type based on direction
    final type = switch (entry.direction) {
      sdk.LogDirection.stdin => 'send',
      sdk.LogDirection.stdout => 'recv',
      sdk.LogDirection.stderr => 'stderr',
      sdk.LogDirection.internal => 'internal',
      null => 'message',
    };

    // Build the message payload
    final message = <String, dynamic>{};
    if (entry.data != null) {
      message.addAll(entry.data!);
    } else if (entry.text != null) {
      message['text'] = entry.text;
    } else {
      message['text'] = entry.message;
    }

    // Add direction if present
    if (entry.direction != null) {
      message['direction'] = entry.direction!.name;
    }

    LogService.instance.log(
      service: 'ClaudeSDK',
      level: level,
      type: type,
      message: message,
      // TODO: Add worktree when we can associate sessions with worktrees
    );
  }


  /// Initialize application logging with settings from RuntimeConfig.
  void _initializeLogging() {
    final config = RuntimeConfig.instance;
    final logPath = _expandPath(config.loggingFilePath);

    // Set minimum level
    LogService.instance.minimumLevel = _parseLogLevel(config.loggingMinimumLevel);

    // Enable file logging if path is set
    if (logPath.isNotEmpty) {
      LogService.instance.enableFileLogging(logPath);
    }

    LogService.instance.info('App', 'startup', 'CC Insights starting up');
  }

  /// Validates the directory and determines if we need to show a prompt.
  Future<void> _validateDirectory(String path) async {
    final gitService = const RealGitService();
    final gitInfo = await gitService.analyzeDirectory(path);

    if (!mounted) return;

    // Check if the directory is ideal (primary worktree at root)
    if (gitInfo.isPrimaryWorktreeRoot) {
      // Ideal case - proceed directly
      setState(() {
        _needsValidation = false;
        _projectSelected = true;
        _projectFuture = _restoreProject();
      });
    } else {
      // Need to show validation dialog
      setState(() {
        _pendingValidationInfo = gitInfo;
      });
    }
  }

  /// Initialize SDK debug logging to write all messages to a file.
  void _initializeSdkLogging() {
    // Get home directory path
    final home = Platform.environment['HOME'] ?? '/tmp';
    final logPath = '$home/ccinsights.debug.jsonl';

    // Enable debug mode and file logging based on RuntimeConfig
    final shouldLog = RuntimeConfig.instance.debugSdkLogging;
    sdk.SdkLogger.instance.debugEnabled = shouldLog;
    if (shouldLog) {
      sdk.SdkLogger.instance.enableFileLogging(logPath);
    }
  }

  /// Handles app termination by writing session quit markers.
  Future<void> _handleAppTermination() async {
    if (_project == null) return;

    debugPrint('App terminating - writing session quit markers');

    // Collect all quit marker writes
    final writes = <Future<void>>[];
    final persistence = _persistenceService ?? PersistenceService();

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
              persistence.appendChatEntry(chat.projectId!, chat.data.id, entry),
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
    _sdkLogSubscription?.cancel();
    _themeState?.removeListener(_onThemeChanged);
    _settingsService?.removeListener(_syncThemeFromSettings);
    RuntimeConfig.instance.removeListener(_onRuntimeConfigChanged);
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
    }

    // Show validation dialog if we have pending validation
    if (_needsValidation && _pendingValidationInfo != null) {
      return _buildValidationScreen();
    }

    // Show welcome screen if not launched from CLI and no project selected
    if (!_projectSelected) {
      return _buildWelcomeApp();
    }

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

  /// Handles project selection from the welcome screen.
  void _onProjectSelected(String projectPath) {
    // Update the RuntimeConfig with the selected directory
    RuntimeConfig.instance.setWorkingDirectory(projectPath);

    // Start loading the project
    setState(() {
      _projectSelected = true;
      _projectFuture = _restoreProject();
    });
  }

  /// Builds the welcome screen app (before a project is selected).
  Widget _buildWelcomeApp() {
    return MaterialApp(
      title: 'CC Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeState?.themeMode ?? ThemeMode.system,
      home: WelcomeScreen(
        onProjectSelected: _onProjectSelected,
      ),
    );
  }

  /// Builds the validation screen that shows the directory validation message.
  Widget _buildValidationScreen() {
    return MaterialApp(
      title: 'CC Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeState?.themeMode ?? ThemeMode.system,
      home: DirectoryValidationScreen(
        gitInfo: _pendingValidationInfo!,
        onResult: _handleValidationResult,
      ),
    );
  }

  /// Handles the result of the directory validation dialog.
  void _handleValidationResult(DirectoryValidationResult result) {
    switch (result) {
      case DirectoryValidationResult.openPrimary:
        // User chose to open the primary/repo root
        final targetPath = _pendingValidationInfo!.isLinkedWorktree
            ? _pendingValidationInfo!.repoRoot
            : _pendingValidationInfo!.worktreeRoot;

        if (targetPath != null) {
          RuntimeConfig.instance.setWorkingDirectory(targetPath);
          setState(() {
            _needsValidation = false;
            _pendingValidationInfo = null;
            _projectSelected = true;
            _projectFuture = _restoreProject();
          });
        }
        break;

      case DirectoryValidationResult.chooseDifferent:
        // User wants to choose a different folder - show welcome screen
        setState(() {
          _needsValidation = false;
          _pendingValidationInfo = null;
          _projectSelected = false;
        });
        break;

      case DirectoryValidationResult.openAnyway:
        // User chose to proceed with the current directory
        setState(() {
          _needsValidation = false;
          _pendingValidationInfo = null;
          _projectSelected = true;
          _projectFuture = _restoreProject();
        });
        break;

      case DirectoryValidationResult.cancelled:
        // User cancelled - show welcome screen
        setState(() {
          _needsValidation = false;
          _pendingValidationInfo = null;
          _projectSelected = false;
        });
        break;
    }
  }

  /// Builds the loading screen shown while restoring project.
  Widget _buildLoadingScreen() {
    return MaterialApp(
      title: 'CC Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeState?.themeMode ?? ThemeMode.system,
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
        // File system service for file tree and content (stateless)
        Provider<FileSystemService>.value(value: const RealFileSystemService()),
        // AskAI service for one-shot AI queries
        Provider<AskAiService>.value(value: _askAiService!),
        // Persistence service for storing project/chat data
        Provider<PersistenceService>.value(
            value: _persistenceService ?? PersistenceService()),
        // Settings service for application preferences
        ChangeNotifierProvider<SettingsService>.value(
          value: _settingsService!,
        ),
        // Project state
        ChangeNotifierProvider<ProjectState>.value(value: project),
        // Selection state depends on project
        ChangeNotifierProxyProvider<ProjectState, SelectionState>(
          create: (context) => SelectionState(context.read<ProjectState>()),
          update: (context, project, previous) =>
              previous ?? SelectionState(project),
        ),
        // File manager state depends on project, file system service, and
        // selection state (for synchronized worktree selection)
        ChangeNotifierProxyProvider3<
          ProjectState,
          FileSystemService,
          SelectionState,
          FileManagerState
        >(
          create: (context) => FileManagerState(
            context.read<ProjectState>(),
            context.read<FileSystemService>(),
            context.read<SelectionState>(),
          ),
          update: (context, project, fileService, selectionState, previous) =>
              previous ?? FileManagerState(project, fileService, selectionState),
        ),
        // Worktree watcher service for monitoring git status changes.
        // Self-contained: listens to ProjectState and watches all
        // worktrees automatically. Eager (lazy: false) so it starts
        // polling immediately, not when first read by a widget.
        ChangeNotifierProvider<WorktreeWatcherService>(
          lazy: false,
          create: (context) => WorktreeWatcherService(
            gitService: context.read<GitService>(),
            project: context.read<ProjectState>(),
          ),
        ),
        // Project config service for reading/writing .ccinsights/config.json
        Provider<ProjectConfigService>(
          create: (_) => ProjectConfigService(),
        ),
        // Script execution service for running user actions
        ChangeNotifierProvider<ScriptExecutionService>(
          create: (_) => ScriptExecutionService(),
        ),
        // Theme state for dynamic theme switching
        ChangeNotifierProvider<ThemeState>.value(
          value: _themeState!,
        ),
        // Dialog observer for keyboard focus management
        Provider<DialogObserver>.value(value: _dialogObserver),
      ],
      child: _NotificationNavigationListener(
        child: MaterialApp(
          title: 'CC Insights',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: _themeState?.themeMode ?? ThemeMode.system,
          navigatorObservers: [_dialogObserver],
          home: const MainScreen(),
          routes: {'/replay': (context) => const ReplayDemoScreen()},
        ),
      ),
    );
  }

  /// Build a compact desktop-appropriate theme.
  ///
  /// The primary background ([ColorScheme.surface]) is
  /// desaturated to near-white/near-black so the app
  /// feels neutral. Other surface variants keep their
  /// normal Material 3 tonal relationships.
  ThemeData _buildTheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: _themeState?.seedColor ?? Colors.deepPurple,
      brightness: brightness,
    );

    // Blend the main scaffold background toward
    // pure white/black so it stays fairly neutral.
    final neutral = brightness == Brightness.light
        ? Colors.white
        : Colors.black;
    final colorScheme = base.copyWith(
      surface: Color.lerp(base.surface, neutral, 0.50),
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

/// Listens for notification click events and navigates to the relevant
/// worktree and chat.
///
/// Must be placed inside the [MultiProvider] so it can access
/// [ProjectState] and [SelectionState] via [Provider].
class _NotificationNavigationListener extends StatefulWidget {
  final Widget child;

  const _NotificationNavigationListener({required this.child});

  @override
  State<_NotificationNavigationListener> createState() =>
      _NotificationNavigationListenerState();
}

class _NotificationNavigationListenerState
    extends State<_NotificationNavigationListener> {
  StreamSubscription<NotificationNavigationEvent>? _subscription;

  static const _windowChannel =
      MethodChannel('com.nickclifford.ccinsights/window');

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.instance.navigationEvents.listen(
      _handleNavigationEvent,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleNavigationEvent(NotificationNavigationEvent event) {
    if (!mounted) return;

    final project = context.read<ProjectState>();
    final selection = context.read<SelectionState>();

    // Find the worktree matching the event's worktreeRoot
    final worktree = project.allWorktrees.where(
      (w) => w.data.worktreeRoot == event.worktreeRoot,
    ).firstOrNull;
    if (worktree == null) return;

    // Find the chat matching the event's chatId
    final chat = worktree.chats.where(
      (c) => c.data.id == event.chatId,
    ).firstOrNull;
    if (chat == null) return;

    // Navigate to the worktree and chat
    selection.selectWorktree(worktree);
    selection.selectChat(chat);

    // Bring the app window to front
    _bringWindowToFront();
  }

  Future<void> _bringWindowToFront() async {
    try {
      await _windowChannel.invokeMethod('bringToFront');
    } catch (_) {
      // Platform channel not available - ignore
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
