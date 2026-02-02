import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// How to summarize bash tool usage in the UI.
enum BashToolSummary {
  /// Show the command that was executed.
  command,

  /// Show a description of what the command does.
  description,
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

  /// How bash tool usage should be summarized in the UI.
  BashToolSummary _bashToolSummary = BashToolSummary.description;

  /// Whether to use relative file paths in tool summaries.
  bool _toolSummaryRelativeFilePaths = true;

  /// The font family to use for monospace text.
  String _monoFontFamily = 'JetBrains Mono';

  /// Whether to show raw JSON debug icons on messages.
  bool _showRawMessages = true;

  /// The working directory for this session.
  String get workingDirectory => _workingDirectory;

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
    for (final arg in args) {
      if (arg == '--mock') {
        _instance._useMockData = true;
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
}
