import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:acp_sdk/acp_sdk.dart' show AcpBackend;
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:codex_sdk/codex_sdk.dart' show CodexBackend;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'models/output_entry.dart';
import 'models/project.dart';
import 'models/worktree.dart';
import 'screens/main_screen.dart';
import 'screens/replay_demo_screen.dart';
import 'screens/welcome_screen.dart';
import 'widgets/app_menu_bar.dart';
import 'widgets/directory_validation_dialog.dart';
import 'screens/cli_required_screen.dart';
import 'services/ask_ai_service.dart';
import 'services/cli_availability_service.dart';
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
import 'services/window_layout_service.dart';
import 'services/script_execution_service.dart';
import 'services/codex_pricing_service.dart';
import 'services/event_handler.dart';
import 'services/internal_tools_service.dart';
import 'services/worktree_watcher_service.dart';
import 'services/menu_action_service.dart';
import 'state/file_manager_state.dart';
import 'state/selection_state.dart';
import 'state/theme_state.dart';
import 'state/rate_limit_state.dart';
import 'state/ticket_board_state.dart';
import 'testing/mock_backend.dart';
import 'testing/mock_data.dart';
import 'widgets/dialog_observer.dart';

/// Global flag to force mock data usage in tests.
///
/// Set this to true before running integration tests that need mock data.
bool useMockData = false;

/// The original debugPrintSynchronously function, saved before we override it.
const DebugPrintCallback _originalDebugPrint = debugPrintSynchronously;

/// Custom debugPrint that logs to LogService while also printing to stdout.
///
/// This replaces Flutter's default debugPrint to capture debug output in the
/// centralized logging system while preserving the standard console output.
void _loggingDebugPrint(String? message, {int? wrapWidth}) {
  // Always forward to stdout (original behavior)
  _originalDebugPrint(message, wrapWidth: wrapWidth);

  // Also log to LogService if message is not null/empty
  if (message != null && message.isNotEmpty) {
    LogService.instance.debug('Flutter', message);
  }
}

void main(List<String> args) async {
  // Ensure Flutter bindings are initialized before any async work
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window_manager for cross-platform window control
  await windowManager.ensureInitialized();

  // Override debugPrint to also log to LogService while preserving stdout output
  debugPrint = _loggingDebugPrint;

  // Disable Google Fonts runtime HTTP fetching. JetBrains Mono is bundled
  // in assets/fonts/ so no network request is needed.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Catch unhandled async exceptions (streams, futures, isolates) and route
  // them through LogService so they appear in the log viewer and can trigger
  // a UI snackbar.
  PlatformDispatcher.instance.onError = (error, stack) {
    LogService.instance.logUnhandledException(error, stack);
    return true; // handled — don't terminate the app
  };

  // Initialize runtime config from command line arguments.
  // First positional arg is the working directory.
  // Pass setting definitions so CLI overrides can be parsed and type-coerced.
  debugPrint('main() args: $args');
  RuntimeConfig.initialize(
    args,
    settingDefinitions: SettingsService.allDefinitions,
  );
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

  /// Optional EventHandler instance for dependency injection in tests.
  final EventHandler? eventHandler;

  const CCInsightsApp({
    super.key,
    this.backendService,
    this.eventHandler,
  });

  @override
  State<CCInsightsApp> createState() => _CCInsightsAppState();
}

class _CCInsightsAppState extends State<CCInsightsApp>
    with WidgetsBindingObserver {
  /// The backend service instance - created once in initState.
  BackendService? _backend;

  /// The event handler for typed InsightsEvent consumption.
  EventHandler? _eventHandler;

  /// The internal tools service for MCP tool registration.
  InternalToolsService? _internalToolsService;

  /// The project restore service - shared for persistence operations.
  ProjectRestoreService? _restoreService;

  /// The AskAI service for one-shot AI queries.
  AskAiService? _askAiService;

  /// The settings service for application preferences.
  SettingsService? _settingsService;

  /// The window/layout service for window geometry and panel layout.
  WindowLayoutService? _windowLayoutService;

  /// CLI availability service for checking claude/codex/acp existence.
  CliAvailabilityService? _cliAvailability;

  /// The persistence service for storing project/chat data.
  PersistenceService? _persistenceService;

  /// Dialog observer for tracking open dialogs.
  /// Used to suspend keyboard interception while dialogs are open.
  final DialogObserver _dialogObserver = DialogObserver();

  /// Theme state for dynamic theme switching.
  ThemeState? _themeState;

  /// Rate limit state for displaying rate limit information from Codex.
  final RateLimitState _rateLimitState = RateLimitState();

  /// Menu action service for broadcasting menu actions to MainScreen.
  final MenuActionService _menuActionService = MenuActionService();

  /// Navigator key for the MaterialApp, used to show dialogs from the
  /// platform menu bar (which sits above the navigator).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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

  /// Subscription forwarding SDK trace logs to LogService.
  StreamSubscription<sdk.LogEntry>? _sdkLogSubscription;

  /// Subscription forwarding backend-level rate limit events to UI state.
  StreamSubscription<sdk.RateLimitUpdateEvent>? _rateLimitSubscription;

  /// Debounce timer for saving window size after resize.
  Timer? _windowSizeDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _menuActionService.addListener(_onMenuServiceChanged);
    _initializeServices();
  }

  /// Rebuilds when menu service state changes (e.g., merge state for labels).
  void _onMenuServiceChanged() {
    if (mounted) setState(() {});
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

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _debounceSaveWindowSize();
  }

  /// Restores the saved window size on startup via window_manager.
  ///
  /// Called after window layout service has been loaded.
  Future<void> _restoreWindowSize() async {
    final saved = _windowLayoutService?.savedWindowSize;
    if (saved == null) return;

    try {
      await windowManager.setSize(Size(saved.width, saved.height));
    } catch (e) {
      debugPrint('Failed to restore window size: $e');
    }
  }

  /// Debounces window size saves - waits 5 seconds after the last resize.
  void _debounceSaveWindowSize() {
    _windowSizeDebounce?.cancel();
    _windowSizeDebounce = Timer(const Duration(seconds: 5), () {
      _saveCurrentWindowSize();
    });
  }

  /// Reads the current window size and saves it to window.json.
  Future<void> _saveCurrentWindowSize() async {
    try {
      final size = await windowManager.getSize();
      if (size.width > 0 && size.height > 0) {
        await _windowLayoutService?.saveWindowSize(size.width, size.height);
      }
    } catch (e) {
      debugPrint('Failed to save window size: $e');
    }
  }

  /// Initialize services once on first build.
  ///
  /// This runs in initState so services are created only once,
  /// not on every hot reload.
  void _initializeServices() {
    final shouldUseMock = _shouldUseMockData();

    // Register available backend factories
    sdk.ClaudeCliBackend.register();
    CodexBackend.register();
    AcpBackend.register();

    // Initialize application logging
    _initializeLogging();

    // Load Codex pricing (from disk cache, then fetch remote in background)
    CodexPricingService.instance.initialize();

    // Enable SDK debug logging to file
    _initializeSdkLogging();

    // Forward SDK log entries into the app LogService so they appear
    // in the log viewer. Only forward internal entries (trace, warnings, etc.)
    // — raw message payloads (stdin/stdout/stderr) stay in the trace file only.
    _sdkLogSubscription = sdk.SdkLogger.instance.logs.listen((entry) {
      if (entry.direction != sdk.LogDirection.internal) return;

      final source = entry.text != null ? 'CCI:${entry.text}' : 'SDK';
      final level = switch (entry.level) {
        sdk.LogLevel.debug => LogLevel.debug,
        sdk.LogLevel.info => LogLevel.info,
        sdk.LogLevel.warning => LogLevel.warn,
        sdk.LogLevel.error => LogLevel.error,
      };
      LogService.instance.log(
        source: source,
        level: level,
        message: entry.message,
      );
    });

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

    // Create CLI availability service
    _cliAvailability = CliAvailabilityService();

    // Create and load the settings service (fire-and-forget load)
    _settingsService = SettingsService();
    _windowLayoutService = WindowLayoutService();
    _settingsService!.load().then((_) async {
      // Load window/layout service, migrating from config.json if needed
      await _windowLayoutService!.load(
        migrationSource: _settingsService!.valuesSnapshot,
      );
      // Clean legacy keys from config.json after migration
      await _settingsService!.removeLegacyWindowLayoutKeys();

      // Check CLI availability after settings load (custom paths may be set)
      if (!shouldUseMock && widget.backendService == null) {
        final config = RuntimeConfig.instance;
        await _cliAvailability!.checkAgents(config.agents);

        if (_cliAvailability!.claudeAvailable) {
          _backend?.discoverModelsForAllAgents();
        }
      }
      _restoreWindowSize();
      if (mounted) setState(() {});
    });

    // Create the AskAI service for one-shot AI queries
    _askAiService = AskAiService();

    // Create theme state and sync from settings service
    _themeState = ThemeState();
    _themeState!.addListener(_onThemeChanged);
    _settingsService!.addListener(_syncThemeFromSettings);

    // Listen for changes to debug SDK logging setting
    RuntimeConfig.instance.addListener(_onRuntimeConfigChanged);

    // Create the internal tools service for MCP tool registration
    _internalToolsService = InternalToolsService();

    // Create or use injected EventHandler
    _eventHandler =
        widget.eventHandler ?? EventHandler(askAiService: _askAiService);
    _eventHandler!.rateLimitState = _rateLimitState;

    // Subscribe to backend-level rate limit events (independent of sessions).
    // This ensures rate limit data is captured even if no chat session is
    // actively listening when the notification arrives.
    _rateLimitSubscription = _backend!.rateLimits.listen(
      _rateLimitState.update,
    );

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
        .getEffectiveValue<int>('appearance.seedColor');
    _themeState!.setSeedColor(Color(colorValue));
    final modeStr = _settingsService!
        .getEffectiveValue<String>('appearance.themeMode');
    _themeState!.setThemeMode(
      ThemeState.parseThemeMode(modeStr),
    );
    final inputColorValue = _settingsService!
        .getEffectiveValue<int>('appearance.inputTextColor');
    _themeState!.setInputTextColor(
      inputColorValue == 0 ? null : Color(inputColorValue),
    );
  }

  /// Handles changes to RuntimeConfig (like debug SDK logging).
  void _onRuntimeConfigChanged() {
    // Handle SDK debug logging setting
    final shouldLog = RuntimeConfig.instance.debugSdkLogging;
    final logPath = _expandPath(RuntimeConfig.instance.traceLogPath);

    sdk.SdkLogger.instance.debugEnabled = shouldLog;
    sdk.SdkLogger.instance.excludeDeltas =
        RuntimeConfig.instance.traceExcludeDeltas;
    if (shouldLog && logPath.isNotEmpty) {
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
      'trace' => LogLevel.trace,
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

  /// Initialize application logging with settings from RuntimeConfig.
  void _initializeLogging() {
    final config = RuntimeConfig.instance;
    final logPath = _expandPath(config.loggingFilePath);

    // Set minimum level
    LogService.instance.minimumLevel = _parseLogLevel(config.loggingMinimumLevel);

    // Enable stdout logging if --stdout-log-level was specified
    final stdoutLevel = config.stdoutLogLevel;
    if (stdoutLevel != null) {
      LogService.instance.stdoutMinimumLevel = _parseLogLevel(stdoutLevel);
    }

    // Enable file logging if path is set
    if (logPath.isNotEmpty) {
      LogService.instance.enableFileLogging(logPath);
    }

    LogService.instance.info('App', 'CC Insights starting up');
  }

  /// Validates the directory and determines if we need to show a prompt.
  Future<void> _validateDirectory(String path) async {
    const gitService = RealGitService();
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
    final logPath = _expandPath(RuntimeConfig.instance.traceLogPath);

    // Enable debug mode and file logging based on RuntimeConfig
    final shouldLog = RuntimeConfig.instance.debugSdkLogging;
    sdk.SdkLogger.instance.debugEnabled = shouldLog;
    sdk.SdkLogger.instance.excludeDeltas =
        RuntimeConfig.instance.traceExcludeDeltas;
    if (shouldLog && logPath.isNotEmpty) {
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
    _windowSizeDebounce?.cancel();
    _sdkLogSubscription?.cancel();
    _rateLimitSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _menuActionService.removeListener(_onMenuServiceChanged);
    _themeState?.removeListener(_onThemeChanged);
    _settingsService?.removeListener(_syncThemeFromSettings);
    RuntimeConfig.instance.removeListener(_onRuntimeConfigChanged);
    // Only dispose services we created, not injected ones
    if (widget.backendService == null) {
      _backend?.dispose();
    }
    if (widget.eventHandler == null) {
      _eventHandler?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use mock data if explicitly requested or in test environment
    final shouldUseMock = useMockData || _shouldUseMockData();

    // Determine if we have a project (for menu item enable/disable state).
    // Use _projectSelected rather than _project != null because _project is
    // set inside _buildScreen's FutureBuilder (after this line runs), so it
    // would be null on the first frame even though the project is loaded.
    final hasProject = shouldUseMock || _projectSelected;

    // Single AppMenuBar at the root to avoid PlatformMenuBar lock conflicts
    // when transitioning between states (loading -> loaded)
    return AppMenuBar(
      callbacks: _createMenuCallbacks(),
      hasProject: hasProject,
      navigatorKey: _navigatorKey,
      child: _buildContent(shouldUseMock),
    );
  }

  /// Builds the appropriate content based on current state.
  ///
  /// Returns a single [MaterialApp] wrapping the content for the current
  /// screen state. Theme, navigator observers, debug banner, and routes
  /// are configured once here rather than per-screen.
  Widget _buildContent(bool shouldUseMock) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'CC Insights',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeState?.themeMode ?? ThemeMode.system,
      navigatorObservers: [_dialogObserver],
      routes: {'/replay': (context) => const ReplayDemoScreen()},
      home: _buildScreen(shouldUseMock),
    );
  }

  /// Returns the plain screen widget for the current app state.
  ///
  /// Unlike [_buildContent], this does NOT wrap in a [MaterialApp].
  Widget _buildScreen(bool shouldUseMock) {
    if (shouldUseMock) {
      // Synchronous path for mock data
      _project = _mockProject!;
      return _buildAppContent(_project!);
    }

    // After CLI check completes, show the required screen if claude is missing
    if (_cliAvailability != null &&
        _cliAvailability!.checked &&
        !_cliAvailability!.claudeAvailable) {
      return _buildCliRequiredContent();
    }

    // Show validation dialog if we have pending validation
    if (_needsValidation && _pendingValidationInfo != null) {
      return _buildValidationContent();
    }

    // Show welcome screen if not launched from CLI and no project selected
    if (!_projectSelected) {
      return _buildWelcomeContent();
    }

    // Async path for restoring from persistence
    return FutureBuilder<ProjectState>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingContent();
        }

        if (snapshot.hasError) {
          debugPrint('Error restoring project: ${snapshot.error}');
          // Fall back to creating a new project synchronously
          _project = _createFallbackProject();
          return _buildAppContent(_project!);
        }

        _project = snapshot.data ?? _createFallbackProject();
        return _buildAppContent(_project!);
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

  /// Builds the welcome screen content (before a project is selected).
  Widget _buildWelcomeContent() {
    return WelcomeScreen(
      onProjectSelected: _onProjectSelected,
    );
  }

  /// Builds the CLI required screen (Claude CLI not found).
  Widget _buildCliRequiredContent() {
    return CliRequiredScreen(
      cliAvailability: _cliAvailability!,
      settingsService: _settingsService!,
      onCliFound: () {
        // Start backends for all agents now that CLI is available
        if (widget.backendService == null) {
          _backend?.discoverModelsForAllAgents();
        }
        setState(() {});
      },
    );
  }

  /// Builds the validation screen content that shows the directory validation message.
  Widget _buildValidationContent() {
    return DirectoryValidationScreen(
      gitInfo: _pendingValidationInfo!,
      onResult: _handleValidationResult,
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

  // ========== Menu Action Handlers ==========

  /// Opens a folder picker and loads the selected project.
  Future<void> _handleOpenProject() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Project Folder',
    );

    if (result != null) {
      await _validateAndOpenProject(result);
    }
  }

  /// Validates a directory and opens it as a project.
  Future<void> _validateAndOpenProject(String path) async {
    const gitService = RealGitService();
    final gitInfo = await gitService.analyzeDirectory(path);

    if (!mounted) return;

    // Check if the directory is ideal (primary worktree at root)
    if (gitInfo.isPrimaryWorktreeRoot) {
      _onProjectSelected(path);
      return;
    }

    // For non-ideal directories, we need to show a validation dialog.
    // Store the info and let the validation screen handle it.
    setState(() {
      _needsValidation = true;
      _pendingValidationInfo = gitInfo;
    });
  }

  /// Closes the current project and returns to the welcome screen.
  void _handleCloseProject() {
    setState(() {
      _project = null;
      _projectSelected = false;
      _projectFuture = null;
    });
  }

  /// Creates the menu callbacks for the current state.
  MenuCallbacks _createMenuCallbacks() {
    return MenuCallbacks(
      // Project menu
      onOpenProject: _handleOpenProject,
      onProjectSettings: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.showProjectSettings)
          : null,
      onCloseProject: _projectSelected ? _handleCloseProject : null,

      // Worktree menu
      onNewWorktree: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.newWorktree)
          : null,
      onRestoreWorktree: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.restoreWorktree)
          : null,
      onDeleteWorktree: null, // Not wired up yet
      onNewChat: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.newChat)
          : null,

      // Actions submenu
      onActionTest: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.actionTest)
          : null,
      onActionRun: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.actionRun)
          : null,

      // Git submenu
      onGitStageCommit: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitStageCommit)
          : null,
      onGitRebase: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitRebase)
          : null,
      onGitMerge: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitMerge)
          : null,
      onGitMergeIntoMain: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitMergeIntoMain)
          : null,
      onGitPush: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitPush)
          : null,
      onGitPull: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitPull)
          : null,
      onGitCreatePR: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.gitCreatePR)
          : null,

      // View menu
      onShowWorkspace: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.showWorkspace)
          : null,
      onShowFileManager: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.showFileManager)
          : null,
      onShowSettings: () =>
          _menuActionService.triggerAction(MenuAction.showSettings),
      onShowLogs: () =>
          _menuActionService.triggerAction(MenuAction.showLogs),
      onShowStats: _projectSelected
          ? () => _menuActionService.triggerAction(MenuAction.showStats)
          : null,

      // Panels
      onToggleMergeChatsAgents: _projectSelected
          ? () => _menuActionService
              .triggerAction(MenuAction.toggleMergeChatsAgents)
          : null,
      agentsMergedIntoChats: _menuActionService.agentsMergedIntoChats,
    );
  }

  /// Builds the loading screen content shown while restoring project.
  Widget _buildLoadingContent() {
    return const Scaffold(
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
    );
  }

  /// Builds the main app content with the given project.
  Widget _buildAppContent(ProjectState project) {
    return MultiProvider(
      providers: [
        // Central logging service (singleton, rate-limited notifications)
        ChangeNotifierProvider<LogService>.value(value: LogService.instance),
        // CLI availability service for checking claude/codex/acp existence
        ChangeNotifierProvider<CliAvailabilityService>.value(
          value: _cliAvailability!,
        ),
        // Backend service for spawning SDK sessions
        ChangeNotifierProvider<BackendService>.value(value: _backend!),
        // Event handler for typed InsightsEvent consumption
        Provider<EventHandler>.value(value: _eventHandler!),
        // Internal tools service for MCP tool registration
        ChangeNotifierProvider<InternalToolsService>.value(
          value: _internalToolsService!,
        ),
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
        // Window/layout service for window geometry and panel layout
        ChangeNotifierProvider<WindowLayoutService>.value(
          value: _windowLayoutService!,
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
        // Project config service for reading/writing .ccinsights/config.json
        ChangeNotifierProvider<ProjectConfigService>(
          create: (_) => ProjectConfigService(),
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
            configService: context.read<ProjectConfigService>(),
          ),
        ),
        // Script execution service for running user actions
        ChangeNotifierProvider<ScriptExecutionService>(
          create: (_) => ScriptExecutionService(),
        ),
        // Theme state for dynamic theme switching
        ChangeNotifierProvider<ThemeState>.value(
          value: _themeState!,
        ),
        // Rate limit state for displaying Codex rate limits
        ChangeNotifierProvider<RateLimitState>.value(
          value: _rateLimitState,
        ),
        // Dialog observer for keyboard focus management
        Provider<DialogObserver>.value(value: _dialogObserver),
        // Menu action service for broadcasting menu actions to MainScreen
        ChangeNotifierProvider<MenuActionService>.value(
          value: _menuActionService,
        ),
        // Ticket board state for project management
        ChangeNotifierProxyProvider<ProjectState, TicketBoardState>(
          create: (context) {
            final projectState = context.read<ProjectState>();
            final projectId = PersistenceService.generateProjectId(
              projectState.data.repoRoot,
            );
            final ticketBoardState = TicketBoardState(
              projectId,
              persistence: context.read<PersistenceService>(),
            );
            // Wire up the event handler for ticket status transitions
            context.read<EventHandler>().ticketBoard = ticketBoardState;
            // Register internal MCP tools with the ticket board
            if (context.read<SettingsService>().getEffectiveValue<bool>(
              'projectMgmt.agentTicketTools',
            )) {
              context.read<InternalToolsService>().registerTicketTools(
                ticketBoardState,
              );
            }
            // Load tickets asynchronously (fire-and-forget)
            ticketBoardState.load();
            return ticketBoardState;
          },
          update: (context, project, previous) {
            if (previous != null) return previous;
            final projectId = PersistenceService.generateProjectId(
              project.data.repoRoot,
            );
            final ticketBoardState = TicketBoardState(
              projectId,
              persistence: context.read<PersistenceService>(),
            );
            // Wire up the event handler for ticket status transitions
            context.read<EventHandler>().ticketBoard = ticketBoardState;
            // Register internal MCP tools with the ticket board
            if (context.read<SettingsService>().getEffectiveValue<bool>(
              'projectMgmt.agentTicketTools',
            )) {
              context.read<InternalToolsService>().registerTicketTools(
                ticketBoardState,
              );
            }
            ticketBoardState.load();
            return ticketBoardState;
          },
        ),
      ],
      child: _NotificationNavigationListener(
        child: const MainScreen(),
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
