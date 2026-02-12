import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/setting_definition.dart';

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

  /// Setting values overridden via CLI flags or environment variables.
  ///
  /// Keys are setting keys (e.g. 'logging.filePath'), values are coerced
  /// to the correct type. These overrides take precedence over config.json
  /// but are never persisted to disk.
  final Map<String, dynamic> _cliOverrides = {};

  /// Warnings generated during CLI override parsing (e.g. invalid values).
  final List<String> _cliWarnings = [];

  /// Returns an unmodifiable view of CLI overrides.
  Map<String, dynamic> get cliOverrides => Map.unmodifiable(_cliOverrides);

  /// Returns warnings from CLI override parsing. Empty if all overrides valid.
  List<String> get cliWarnings => List.unmodifiable(_cliWarnings);

  /// Whether the given setting key is overridden via CLI or environment variable.
  bool isOverridden(String key) => _cliOverrides.containsKey(key);

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

  /// Whether to archive chats instead of deleting them on close.
  bool _archiveChats = false;

  /// Whether to delete the local branch when deleting a worktree.
  bool _deleteBranchWithWorktree = true;

  /// Whether to show cost/token usage on linked worktree status lines.
  bool _showWorktreeCost = true;

  /// Whether agents can access ticket tools (create_ticket MCP tool).
  bool _agentTicketToolsEnabled = true;

  /// Default model for new chats (composite value, e.g. 'last_used',
  /// 'claude:opus', 'codex:gpt-5.2').
  String _defaultModel = 'last_used';

  /// Default backend for new chats.
  BackendType _defaultBackend = BackendType.directCli;

  /// Default permission mode for new chats.
  String _defaultPermissionMode = 'default';

  /// Whether to stream partial messages as they're generated.
  bool _streamOfThought = true;

  /// Whether to enable debug SDK logging.
  bool _debugSdkLogging = false;

  /// Whether to exclude streaming delta messages from the trace log.
  bool _traceExcludeDeltas = true;

  /// Path to the SDK trace log file.
  String _traceLogPath = '~/ccinsights.trace.jsonl';

  /// Path to the application log file.
  String _loggingFilePath = '~/ccinsights.app.jsonl';

  /// Minimum log level for file output.
  String _loggingMinimumLevel = 'debug';

  /// Which markdown rendering backend to use.
  MarkdownBackend _markdownBackend = MarkdownBackend.flutterMarkdownPlus;

  /// Custom path to the Claude CLI executable (empty = use PATH lookup).
  String _claudeCliPath = '';

  /// Custom path to the Codex CLI executable (empty = use PATH lookup).
  String _codexCliPath = '';

  /// Whether the Codex CLI is available on this system.
  bool _codexAvailable = true;

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
  /// - `--<setting.key>=<value>`: Override a setting (e.g. `--logging.filePath=~/app.log`)
  /// - Positional arg 0: working directory (defaults to current directory)
  ///
  /// The [settingDefinitions] parameter provides known setting keys and their
  /// types for CLI override parsing and type coercion.
  ///
  /// Environment variables with the pattern `CCI_<CATEGORY>_<KEY>` (e.g.
  /// `CCI_LOGGING_FILEPATH`) are also checked. CLI flags take precedence
  /// over environment variables.
  static void initialize(
    List<String> args, {
    List<SettingDefinition> settingDefinitions = const [],
  }) {
    if (_instance._initialized) {
      return;
    }

    _instance._initialized = true;

    // Build a lookup map from setting key to definition for CLI parsing.
    final defsByKey = <String, SettingDefinition>{};
    for (final def in settingDefinitions) {
      defsByKey[def.key] = def;
    }

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
      } else if (arg.startsWith('--') && arg.contains('=')) {
        // Setting override: --key=value
        final eqIdx = arg.indexOf('=');
        final key = arg.substring(2, eqIdx);
        final rawValue = arg.substring(eqIdx + 1);
        final def = defsByKey[key];
        if (def != null) {
          final warning = _validateValue(rawValue, def);
          if (warning != null) {
            _instance._cliWarnings.add(warning);
          } else {
            _instance._cliOverrides[key] = _coerceValue(rawValue, def.type);
          }
        }
      } else if (!arg.startsWith('-')) {
        positionalArgs.add(arg);
      }
    }

    // Check environment variables for settings not already overridden by CLI.
    for (final def in settingDefinitions) {
      if (_instance._cliOverrides.containsKey(def.key)) continue;
      final envKey = _settingKeyToEnvVar(def.key);
      final envVal = Platform.environment[envKey];
      if (envVal != null) {
        final warning = _validateValue(envVal, def);
        if (warning != null) {
          _instance._cliWarnings.add(warning);
        } else {
          _instance._cliOverrides[def.key] = _coerceValue(envVal, def.type);
        }
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

  /// Coerces a raw string value to the appropriate type for a setting.
  static dynamic _coerceValue(String raw, SettingType type) {
    return switch (type) {
      SettingType.toggle => raw.toLowerCase() == 'true' || raw == '1',
      SettingType.number => int.tryParse(raw) ?? 0,
      SettingType.colorPicker => int.tryParse(raw) ?? 0,
      SettingType.dropdown || SettingType.text => raw,
    };
  }

  /// Validates a raw CLI/env value against a setting definition.
  ///
  /// Returns a human-readable warning string if invalid, or null if valid.
  static String? _validateValue(String raw, SettingDefinition def) {
    switch (def.type) {
      case SettingType.dropdown:
        final validValues = def.options?.map((o) => o.value).toList() ?? [];
        if (!validValues.contains(raw)) {
          return '--${def.key} has invalid value "$raw"'
              ' (valid: ${validValues.join(", ")})';
        }
      case SettingType.number:
        final parsed = int.tryParse(raw);
        if (parsed == null) {
          return '--${def.key} has invalid value "$raw" (expected a number)';
        }
      case SettingType.toggle:
        final lower = raw.toLowerCase();
        if (lower != 'true' && lower != 'false' && raw != '1' && raw != '0') {
          return '--${def.key} has invalid value "$raw"'
              ' (expected true/false/1/0)';
        }
      case SettingType.text:
      case SettingType.colorPicker:
        break; // No validation needed
    }
    return null;
  }

  /// Converts a setting key to an environment variable name.
  ///
  /// E.g. `logging.filePath` -> `CCI_LOGGING_FILEPATH`.
  static String _settingKeyToEnvVar(String key) {
    return 'CCI_${key.replaceAll('.', '_').toUpperCase()}'.replaceAll(' ', '_');
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

  /// Whether to archive chats instead of deleting them on close.
  bool get archiveChats => _archiveChats;

  set archiveChats(bool value) {
    if (_archiveChats != value) {
      _archiveChats = value;
      notifyListeners();
    }
  }

  /// Whether to delete the local branch when deleting a worktree.
  bool get deleteBranchWithWorktree => _deleteBranchWithWorktree;

  set deleteBranchWithWorktree(bool value) {
    if (_deleteBranchWithWorktree != value) {
      _deleteBranchWithWorktree = value;
      notifyListeners();
    }
  }

  bool get showWorktreeCost => _showWorktreeCost;

  set showWorktreeCost(bool value) {
    if (_showWorktreeCost != value) {
      _showWorktreeCost = value;
      notifyListeners();
    }
  }

  /// Whether agents can access ticket tools.
  bool get agentTicketToolsEnabled => _agentTicketToolsEnabled;

  set agentTicketToolsEnabled(bool value) {
    if (_agentTicketToolsEnabled != value) {
      _agentTicketToolsEnabled = value;
      notifyListeners();
    }
  }

  /// Default model for new chats (composite value).
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

  /// Whether to exclude streaming delta messages from the trace log.
  bool get traceExcludeDeltas => _traceExcludeDeltas;

  set traceExcludeDeltas(bool value) {
    if (_traceExcludeDeltas != value) {
      _traceExcludeDeltas = value;
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

  /// Custom path to the Claude CLI executable.
  ///
  /// Empty string means use default PATH lookup.
  String get claudeCliPath => _claudeCliPath;

  set claudeCliPath(String value) {
    if (_claudeCliPath != value) {
      _claudeCliPath = value;
      notifyListeners();
    }
  }

  /// Custom path to the Codex CLI executable.
  ///
  /// Empty string means use default PATH lookup.
  String get codexCliPath => _codexCliPath;

  set codexCliPath(String value) {
    if (_codexCliPath != value) {
      _codexCliPath = value;
      notifyListeners();
    }
  }

  /// Whether the Codex CLI is available on this system.
  bool get codexAvailable => _codexAvailable;

  set codexAvailable(bool value) {
    if (_codexAvailable != value) {
      _codexAvailable = value;
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
    _instance._cliOverrides.clear();
    _instance._cliWarnings.clear();
    _instance._bashToolSummary = BashToolSummary.description;
    _instance._toolSummaryRelativeFilePaths = true;
    _instance._monoFontFamily = 'JetBrains Mono';
    _instance._showRawMessages = true;
    _instance._showTimestamps = false;
    _instance._timestampIdleThreshold = 5;
    _instance._aiAssistanceModel = 'opus';
    _instance._aiChatLabelModel = 'haiku';
    _instance._desktopNotifications = true;
    _instance._archiveChats = false;
    _instance._deleteBranchWithWorktree = true;
    _instance._showWorktreeCost = true;
    _instance._defaultModel = 'last_used';
    _instance._defaultBackend = BackendType.directCli;
    _instance._defaultPermissionMode = 'default';
    _instance._streamOfThought = true;
    _instance._debugSdkLogging = false;
    _instance._traceExcludeDeltas = true;
    _instance._traceLogPath = '~/ccinsights.trace.jsonl';
    _instance._loggingFilePath = '~/ccinsights.app.jsonl';
    _instance._loggingMinimumLevel = 'debug';
    _instance._markdownBackend = MarkdownBackend.flutterMarkdownPlus;
    _instance._claudeCliPath = '';
    _instance._codexCliPath = '';
    _instance._codexAvailable = true;
    _instance._agentTicketToolsEnabled = true;
  }
}
