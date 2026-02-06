import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How to summarize bash tool usage in the UI.
enum BashToolSummary {
  /// Show the command that was executed.
  command,

  /// Show a description of what the command does.
  description,
}

/// Which markdown rendering backend to use.
enum MarkdownBackend {
  /// Use flutter_markdown_plus package.
  flutterMarkdownPlus,

  /// Use gpt_markdown package.
  gptMarkdown,
}

/// Runtime configuration for the application.
///
/// Provides configurable options that can be changed at runtime.
/// Uses a singleton pattern for global access.
///
/// Initialize with command line arguments before using:
/// ```dart
/// RuntimeConfig.initialize(args);
/// ```
class RuntimeConfig extends ChangeNotifier {
  RuntimeConfig._();

  static final RuntimeConfig _instance = RuntimeConfig._();

  /// Global singleton instance.
  static RuntimeConfig get instance => _instance;

  /// Whether the config has been initialized with command line args.
  bool _initialized = false;

  /// Whether to use mock data (--mock flag).
  bool _useMockData = false;

  /// Whether the app was launched from CLI (has TERM env var and no
  /// FORCE_WELCOME).
  ///
  /// When true, the app skips the welcome screen and goes directly to
  /// the main view.
  bool _launchedFromCli = false;

  /// The working directory (primary worktree root).
  ///
  /// This is the path to a git repository passed as the first positional
  /// argument, or the current working directory if not provided.
  String _workingDirectory = Directory.current.path;

  /// The config directory override (--config-dir flag).
  ///
  /// When set, overrides the default ~/.ccinsights directory for storing
  /// application data. Used primarily for test isolation.
  String? _configDir;

  /// How bash tool usage should be summarized in the UI.
  BashToolSummary _bashToolSummary = BashToolSummary.description;

  /// Whether to use relative file paths in tool summaries.
  bool _toolSummaryRelativeFilePaths = true;

  /// The font family to use for monospace text.
  String _monoFontFamily = 'JetBrains Mono';

  /// Whether to show raw JSON debug icons on messages.
  bool _showRawMessages = true;

  /// Whether to show timestamps on messages.
  bool _showTimestamps = false;

  /// Minutes of inactivity before showing a timestamp.
  /// Set to 0 to show on every message.
  int _timestampIdleThreshold = 5;

  /// Model for AI assistance tasks (commit messages, conflict resolution).
  /// Values: 'haiku', 'sonnet', 'opus', 'disabled'.
  String _aiAssistanceModel = 'opus';

  /// Model for AI chat label generation.
  /// Values: 'haiku', 'sonnet', 'opus', 'disabled'.
  String _aiChatLabelModel = 'haiku';

  /// Whether desktop notifications are enabled.
  bool _desktopNotifications = true;

  /// Default Claude model for new chats.
  String _defaultModel = 'opus';

  /// Default backend for new chats.
  BackendType _defaultBackend = BackendType.directCli;

  /// Default permission mode for new chats.
  String _defaultPermissionMode = 'default';

  /// Whether to stream partial messages as they're generated.
  bool _streamOfThought = true;

  /// Whether to enable debug SDK logging.
  bool _debugSdkLogging = false;

  /// Path to the SDK trace log file.
  String _traceLogPath = '~/ccinsights.trace.jsonl';

  /// Path to the application log file.
  String _loggingFilePath = '~/ccinsights.app.jsonl';

  /// Minimum log level for file output.
  String _loggingMinimumLevel = 'debug';

  /// Which markdown rendering backend to use.
  MarkdownBackend _markdownBackend = MarkdownBackend.flutterMarkdownPlus;

  /// The working directory for this session.
  String get workingDirectory => _workingDirectory;

  /// The config directory override.
  ///
  /// Returns null if no override was specified via --config-dir.
  String? get configDir => _configDir;

  /// Whether to use mock data (set via --mock flag).
  bool get useMockData => _useMockData;

  /// Whether the app was launched from CLI (TERM env var is set and
  /// FORCE_WELCOME is not set).
  ///
  /// When launched from CLI, the app skips the welcome screen and goes
  /// directly to the main view with the working directory.
  bool get launchedFromCli => _launchedFromCli;

  /// Whether to show the welcome screen.
  ///
  /// Returns false if launched from CLI (unless FORCE_WELCOME=1 is set).
  bool get showWelcome => !_launchedFromCli;

  /// Initialize runtime config from command line arguments.
  ///
  /// Should be called once at app startup, before [runApp].
  ///
  /// Args format:
  /// - `--mock`: Use mock data instead of real backend
  /// - `--config-dir <path>`: Override the default ~/.ccinsights directory
  /// - Positional arg 0: working directory (defaults to current directory)
  static void initialize(List<String> args) {
    if (_instance._initialized) {
      return;
    }

    _instance._initialized = true;

    // Detect if launched from CLI by checking TERM env var
    // FORCE_WELCOME=1 overrides this to show welcome screen
    final hasTerm = Platform.environment.containsKey('TERM');
    final forceWelcome = Platform.environment['FORCE_WELCOME'] == '1';
    _instance._launchedFromCli = hasTerm && !forceWelcome;

    // Parse flags and collect positional args
    final positionalArgs = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--mock') {
        _instance._useMockData = true;
      } else if (arg == '--config-dir') {
        // Next arg should be the config directory path
        if (i + 1 < args.length) {
          _instance._configDir = args[i + 1];
          i++; // Skip the next arg since we consumed it
        }
      } else if (!arg.startsWith('-')) {
        positionalArgs.add(arg);
      }
    }

    // First positional argument is the working directory
    if (positionalArgs.isNotEmpty) {
      var path = positionalArgs[0];

      // Expand tilde to home directory
      if (path.startsWith('~/')) {
        final home = Platform.environment['HOME'];
        if (home != null) {
          path = home + path.substring(1);
        }
      } else if (path == '~') {
        final home = Platform.environment['HOME'];
        if (home != null) {
          path = home;
        }
      }

      // Resolve relative paths to absolute and canonicalize
      // (this resolves '..' and removes trailing slashes)
      final dir = Directory(path);
      if (dir.isAbsolute) {
        _instance._workingDirectory = p.canonicalize(path);
      } else {
        _instance._workingDirectory = p.canonicalize(dir.absolute.path);
      }
    }
  }

  /// Verify the working directory is a valid git repository.
  ///
  /// Returns true if the working directory contains a `.git` directory.
  bool get isValidGitRepo {
    final gitDir = Directory('$_workingDirectory/.git');
    return gitDir.existsSync();
  }

  /// Get the project name from the working directory.
  ///
  /// Returns the basename of the working directory path.
  String get projectName {
    return _workingDirectory.split(Platform.pathSeparator).last;
  }

  /// How bash tool usage should be summarized in the UI.
  BashToolSummary get bashToolSummary => _bashToolSummary;

  set bashToolSummary(BashToolSummary value) {
    if (_bashToolSummary != value) {
      _bashToolSummary = value;
      notifyListeners();
    }
  }

  /// Whether to use relative file paths in tool summaries.
  bool get toolSummaryRelativeFilePaths => _toolSummaryRelativeFilePaths;

  set toolSummaryRelativeFilePaths(bool value) {
    if (_toolSummaryRelativeFilePaths != value) {
      _toolSummaryRelativeFilePaths = value;
      notifyListeners();
    }
  }

  /// The font family to use for monospace text.
  String get monoFontFamily => _monoFontFamily;

  set monoFontFamily(String value) {
    if (_monoFontFamily != value) {
      _monoFontFamily = value;
      notifyListeners();
    }
  }

  /// Whether to show raw JSON debug icons on messages.
  bool get showRawMessages => _showRawMessages;

  set showRawMessages(bool value) {
    if (_showRawMessages != value) {
      _showRawMessages = value;
      notifyListeners();
    }
  }

  /// Whether to show timestamps on messages.
  bool get showTimestamps => _showTimestamps;

  set showTimestamps(bool value) {
    if (_showTimestamps != value) {
      _showTimestamps = value;
      notifyListeners();
    }
  }

  /// Minutes of inactivity before showing a timestamp.
  int get timestampIdleThreshold => _timestampIdleThreshold;

  set timestampIdleThreshold(int value) {
    if (_timestampIdleThreshold != value) {
      _timestampIdleThreshold = value;
      notifyListeners();
    }
  }

  /// Model for AI assistance tasks (commit messages, conflict resolution).
  String get aiAssistanceModel => _aiAssistanceModel;

  set aiAssistanceModel(String value) {
    if (_aiAssistanceModel != value) {
      _aiAssistanceModel = value;
      notifyListeners();
    }
  }

  /// Whether AI assistance is enabled.
  bool get aiAssistanceEnabled => _aiAssistanceModel != 'disabled';

  /// Model for AI chat label generation.
  String get aiChatLabelModel => _aiChatLabelModel;

  set aiChatLabelModel(String value) {
    if (_aiChatLabelModel != value) {
      _aiChatLabelModel = value;
      notifyListeners();
    }
  }

  /// Whether AI chat labels are enabled.
  bool get aiChatLabelsEnabled => _aiChatLabelModel != 'disabled';



  /// Whether desktop notifications are enabled.
  bool get desktopNotifications => _desktopNotifications;

  set desktopNotifications(bool value) {
    if (_desktopNotifications != value) {
      _desktopNotifications = value;
      notifyListeners();
    }
  }

  /// Default Claude model for new chats.
  String get defaultModel => _defaultModel;

  set defaultModel(String value) {
    if (_defaultModel != value) {
      _defaultModel = value;
      notifyListeners();
    }
  }

  /// Default backend for new chats.
  BackendType get defaultBackend => _defaultBackend;

  set defaultBackend(BackendType value) {
    if (_defaultBackend != value) {
      _defaultBackend = value;
      notifyListeners();
    }
  }

  /// Default permission mode for new chats.
  String get defaultPermissionMode => _defaultPermissionMode;

  set defaultPermissionMode(String value) {
    if (_defaultPermissionMode != value) {
      _defaultPermissionMode = value;
      notifyListeners();
    }
  }

  /// Whether to stream partial messages as they're generated.
  bool get streamOfThought => _streamOfThought;

  set streamOfThought(bool value) {
    if (_streamOfThought != value) {
      _streamOfThought = value;
      notifyListeners();
    }
  }

  /// Whether to enable debug SDK logging.
  bool get debugSdkLogging => _debugSdkLogging;

  set debugSdkLogging(bool value) {
    if (_debugSdkLogging != value) {
      _debugSdkLogging = value;
      notifyListeners();
    }
  }

  /// Path to the SDK trace log file.
  String get traceLogPath => _traceLogPath;

  set traceLogPath(String value) {
    if (_traceLogPath != value) {
      _traceLogPath = value;
      notifyListeners();
    }
  }

  /// Path to the application log file.
  String get loggingFilePath => _loggingFilePath;

  set loggingFilePath(String value) {
    if (_loggingFilePath != value) {
      _loggingFilePath = value;
      notifyListeners();
    }
  }

  /// Minimum log level for file output.
  String get loggingMinimumLevel => _loggingMinimumLevel;

  set loggingMinimumLevel(String value) {
    if (_loggingMinimumLevel != value) {
      _loggingMinimumLevel = value;
      notifyListeners();
    }
  }

  /// Which markdown rendering backend to use.
  MarkdownBackend get markdownBackend => _markdownBackend;

  set markdownBackend(MarkdownBackend value) {
    if (_markdownBackend != value) {
      _markdownBackend = value;
      notifyListeners();
    }
  }

  /// Updates the working directory.
  ///
  /// This is called when the user selects a project from the welcome screen.
  void setWorkingDirectory(String path) {
    // Canonicalize the path
    final dir = Directory(path);
    if (dir.isAbsolute) {
      _workingDirectory = p.canonicalize(path);
    } else {
      _workingDirectory = p.canonicalize(dir.absolute.path);
    }
    notifyListeners();
  }

  /// Resets the RuntimeConfig to its uninitialized state.
  ///
  /// This is intended for use in tests only. It allows tests to
  /// reinitialize the config with different arguments.
  @visibleForTesting
  static void resetForTesting() {
    _instance._initialized = false;
    _instance._useMockData = false;
    _instance._launchedFromCli = false;
    _instance._workingDirectory = Directory.current.path;
    _instance._configDir = null;
    _instance._bashToolSummary = BashToolSummary.description;
    _instance._toolSummaryRelativeFilePaths = true;
    _instance._monoFontFamily = 'JetBrains Mono';
    _instance._showRawMessages = true;
    _instance._showTimestamps = false;
    _instance._timestampIdleThreshold = 5;
    _instance._aiAssistanceModel = 'opus';
    _instance._aiChatLabelModel = 'haiku';
    _instance._desktopNotifications = true;
    _instance._defaultModel = 'opus';
    _instance._defaultBackend = BackendType.directCli;
    _instance._defaultPermissionMode = 'default';
    _instance._streamOfThought = true;
    _instance._debugSdkLogging = false;
    _instance._traceLogPath = '~/ccinsights.trace.jsonl';
    _instance._loggingFilePath = '~/ccinsights.app.jsonl';
    _instance._loggingMinimumLevel = 'debug';
    _instance._markdownBackend = MarkdownBackend.flutterMarkdownPlus;
  }
}
