import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../acp/acp_client_wrapper.dart';

/// Registry of available ACP agents.
///
/// This service discovers installed agents on the system and manages
/// custom agent configurations. It extends [ChangeNotifier] for
/// Provider integration, notifying listeners when the agent list changes.
///
/// The registry supports two types of agents:
/// - **Discovered agents**: Automatically found on the system (e.g., claude-code-acp,
///   gemini, codex). These cannot be removed, only refreshed via [discover].
/// - **Custom agents**: Manually configured by the user. These can be added
///   and removed programmatically.
///
/// Example usage:
/// ```dart
/// final registry = AgentRegistry();
///
/// // Discover installed agents
/// await registry.discover();
///
/// // List all available agents
/// for (final agent in registry.agents) {
///   print('${agent.name}: ${agent.command}');
/// }
///
/// // Add a custom agent
/// registry.addCustomAgent(AgentConfig(
///   id: 'my-agent',
///   name: 'My Custom Agent',
///   command: '/path/to/agent',
/// ));
///
/// // Get a specific agent by ID
/// final claude = registry.getAgent('claude-code');
/// ```
///
/// The [configDir] parameter specifies where to persist custom agent
/// configurations. If not provided, defaults to `~/.cc-insights/`.
class AgentRegistry extends ChangeNotifier {
  /// Creates an agent registry.
  ///
  /// The optional [configDir] specifies the directory where agent
  /// configurations are persisted. Defaults to `~/.cc-insights/` if
  /// not provided.
  AgentRegistry({String? configDir}) : _configDir = configDir;

  final String? _configDir;
  final List<AgentConfig> _discoveredAgents = [];
  final List<AgentConfig> _customAgents = [];
  bool _hasDiscovered = false;

  /// Default configuration directory path.
  ///
  /// Returns `~/.cc-insights/` where `~` is the user's home directory.
  /// Uses the `HOME` environment variable to determine the home directory.
  static String get defaultConfigDir {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.cc-insights';
  }

  /// Gets the path to the agents configuration file.
  ///
  /// Returns `<configDir>/agents.json` where `<configDir>` is either
  /// the directory passed to the constructor or [defaultConfigDir].
  String get _configFilePath {
    final dir = _configDir ?? defaultConfigDir;
    return '$dir/agents.json';
  }

  /// All available agents (discovered + custom).
  ///
  /// Returns an unmodifiable list combining agents discovered on
  /// the system with custom agents added via [addCustomAgent].
  /// Discovered agents appear first, followed by custom agents.
  List<AgentConfig> get agents =>
      List.unmodifiable([..._discoveredAgents, ..._customAgents]);

  /// Whether agent discovery has been run.
  ///
  /// Returns `true` after [discover] has completed at least once,
  /// regardless of whether any agents were found.
  bool get hasDiscovered => _hasDiscovered;

  /// Loads custom agents from the configuration file.
  ///
  /// Reads the `agents.json` file from the config directory and
  /// populates [customAgents]. If the file doesn't exist or cannot
  /// be read, the custom agents list remains empty.
  ///
  /// This should typically be called during app initialization,
  /// before or after [discover].
  ///
  /// Example:
  /// ```dart
  /// final registry = AgentRegistry();
  /// await registry.load();  // Load saved custom agents
  /// await registry.discover();  // Discover system agents
  /// ```
  Future<void> load() async {
    try {
      final file = File(_configFilePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final json = jsonDecode(content) as List<dynamic>;

      _customAgents.clear();
      for (final item in json) {
        _customAgents.add(AgentConfig.fromJson(item as Map<String, dynamic>));
      }
      notifyListeners();
    } catch (e) {
      // Log error but don't fail - start with empty list
      debugPrint('Failed to load agents config: $e');
    }
  }

  /// Saves custom agents to the configuration file.
  ///
  /// Writes the current [customAgents] list to `agents.json` in the
  /// config directory. Creates the directory if it doesn't exist.
  ///
  /// This is automatically called when agents are added or removed
  /// via [addCustomAgent] and [removeAgent]. You typically don't need
  /// to call this directly.
  ///
  /// Errors are logged but not thrown to avoid disrupting the app.
  Future<void> save() async {
    try {
      final dir = Directory(_configDir ?? defaultConfigDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File(_configFilePath);
      final json = _customAgents.map((a) => a.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('Failed to save agents config: $e');
    }
  }

  /// The configuration directory path, if set.
  ///
  /// This is used for persisting custom agent configurations.
  /// Returns `null` if no config directory was specified.
  String? get configDir => _configDir;

  /// Discovered agents only (excludes custom agents).
  ///
  /// Useful for UI that needs to show system-installed vs.
  /// user-configured agents separately.
  List<AgentConfig> get discoveredAgents =>
      List.unmodifiable(_discoveredAgents);

  /// Custom agents only (excludes discovered agents).
  ///
  /// Useful for UI that needs to show system-installed vs.
  /// user-configured agents separately.
  List<AgentConfig> get customAgents => List.unmodifiable(_customAgents);

  /// Discovers installed agents on the system.
  ///
  /// This method checks for common ACP-compatible agents:
  /// - **Claude Code**: The `claude-code-acp` command
  /// - **Gemini CLI**: The `gemini` command with `--acp` flag
  /// - **Codex CLI**: The `codex` command
  ///
  /// Discovery clears any previously discovered agents and runs
  /// fresh detection. Custom agents are preserved.
  ///
  /// After discovery completes, [hasDiscovered] is `true` and
  /// listeners are notified.
  ///
  /// Example:
  /// ```dart
  /// final registry = AgentRegistry();
  /// await registry.discover();
  ///
  /// if (registry.agents.isEmpty) {
  ///   print('No ACP agents found. Install claude-code-acp or another agent.');
  /// }
  /// ```
  Future<void> discover() async {
    _discoveredAgents.clear();

    // Check for Claude Code ACP
    final claudeCode = await _discoverClaudeCode();
    if (claudeCode != null) _discoveredAgents.add(claudeCode);

    // Check for Gemini CLI
    final gemini = await _discoverGemini();
    if (gemini != null) _discoveredAgents.add(gemini);

    // Check for Codex CLI
    final codex = await _discoverCodex();
    if (codex != null) _discoveredAgents.add(codex);

    _hasDiscovered = true;
    notifyListeners();
  }

  /// Adds a custom agent configuration.
  ///
  /// Custom agents are user-defined configurations that persist
  /// alongside discovered agents. Use this for agents that can't
  /// be auto-discovered or require custom arguments/environment.
  ///
  /// The [config] must have a unique [AgentConfig.id]. If an agent
  /// with the same ID already exists (discovered or custom), it
  /// will not be duplicated.
  ///
  /// The agent configuration is automatically saved to disk after
  /// adding. Notifies listeners after adding.
  ///
  /// Example:
  /// ```dart
  /// registry.addCustomAgent(AgentConfig(
  ///   id: 'my-llm-agent',
  ///   name: 'My LLM Agent',
  ///   command: '/usr/local/bin/my-agent',
  ///   args: ['--mode', 'chat'],
  ///   env: {'MY_API_KEY': 'xxx'},
  /// ));
  /// ```
  void addCustomAgent(AgentConfig config) {
    // Avoid duplicates
    if (getAgent(config.id) != null) {
      return;
    }
    _customAgents.add(config);
    notifyListeners();
    save(); // Auto-save after adding
  }

  /// Removes an agent by ID.
  ///
  /// Only custom agents can be removed. Discovered agents are
  /// managed by [discover] and cannot be individually removed.
  ///
  /// Returns silently if the agent is not found or is a discovered agent.
  ///
  /// The agent configuration is automatically saved to disk after
  /// removal. Notifies listeners after removal.
  ///
  /// Example:
  /// ```dart
  /// registry.removeAgent('my-custom-agent');
  /// ```
  void removeAgent(String id) {
    final lengthBefore = _customAgents.length;
    _customAgents.removeWhere((a) => a.id == id);
    if (_customAgents.length < lengthBefore) {
      notifyListeners();
      save(); // Auto-save after removing
    }
  }

  /// Gets an agent by ID.
  ///
  /// Searches both discovered and custom agents for a matching ID.
  ///
  /// Returns `null` if no agent with the given [id] is found.
  ///
  /// Example:
  /// ```dart
  /// final agent = registry.getAgent('claude-code');
  /// if (agent != null) {
  ///   print('Found: ${agent.name}');
  /// }
  /// ```
  AgentConfig? getAgent(String id) {
    return agents.where((a) => a.id == id).firstOrNull;
  }

  /// Checks if an agent with the given [id] exists.
  ///
  /// Returns `true` if a discovered or custom agent has this ID.
  bool hasAgent(String id) => getAgent(id) != null;

  // Discovery methods

  /// Discovers the Claude Code ACP agent.
  ///
  /// Checks for the `claude` command first (the standard Claude Code CLI),
  /// then falls back to `claude-code-acp` (explicit ACP adapter).
  ///
  /// Uses the system's `which` command to locate the executable in PATH.
  /// The agent is configured with no arguments and relies on the
  /// `ANTHROPIC_API_KEY` environment variable being set.
  ///
  /// Returns an [AgentConfig] if found, `null` otherwise.
  Future<AgentConfig?> _discoverClaudeCode() async {
    try {
      // Check if 'claude' is installed (standard Claude Code CLI)
      var result = await Process.run('which', ['claude']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        return AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: path,
          args: const [],
          env: const {}, // Uses ANTHROPIC_API_KEY from environment
        );
      }

      // Try alternate name 'claude-code-acp' (explicit ACP adapter)
      result = await Process.run('which', ['claude-code-acp']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        return AgentConfig(
          id: 'claude-code',
          name: 'Claude Code',
          command: path,
          args: const [],
          env: const {},
        );
      }
    } catch (e) {
      // Ignore errors - agent not found or 'which' not available
    }
    return null;
  }

  /// Discovers the Gemini CLI agent.
  ///
  /// Checks for the `gemini` command in the system PATH.
  /// The agent is configured with the `--acp` flag to enable ACP mode.
  ///
  /// Uses the system's `which` command to locate the executable.
  /// The agent relies on the `GOOGLE_API_KEY` environment variable
  /// being set for authentication.
  ///
  /// Returns an [AgentConfig] if found, `null` otherwise.
  Future<AgentConfig?> _discoverGemini() async {
    try {
      final result = await Process.run('which', ['gemini']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        return AgentConfig(
          id: 'gemini-cli',
          name: 'Gemini CLI',
          command: path,
          args: const ['--acp'], // Gemini may require --acp flag
          env: const {},
        );
      }
    } catch (e) {
      // Ignore errors - agent not found or 'which' not available
    }
    return null;
  }

  /// Discovers the Codex CLI agent.
  ///
  /// Checks for the `codex` command in the system PATH.
  /// This is the OpenAI Codex CLI tool.
  ///
  /// Uses the system's `which` command to locate the executable.
  /// The agent relies on the `OPENAI_API_KEY` environment variable
  /// being set for authentication.
  ///
  /// Returns an [AgentConfig] if found, `null` otherwise.
  Future<AgentConfig?> _discoverCodex() async {
    try {
      final result = await Process.run('which', ['codex']);
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        return AgentConfig(
          id: 'codex-cli',
          name: 'Codex CLI',
          command: path,
          args: const [],
          env: const {},
        );
      }
    } catch (e) {
      // Ignore errors - agent not found or 'which' not available
    }
    return null;
  }
}
