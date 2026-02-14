import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/agent_config.dart';

/// Service that checks whether CLI executables are available per-agent.
///
/// Call [checkAgents] after settings are loaded so that custom paths from
/// user preferences are taken into account.
class CliAvailabilityService extends ChangeNotifier {
  /// Per-agent availability keyed by agent ID.
  Map<String, bool> _agentAvailability = {};

  /// Per-agent resolved CLI paths keyed by agent ID.
  ///
  /// Populated during [checkAgents]. Contains the actual path to the
  /// executable when found (whether via custom path, env var, or PATH lookup).
  Map<String, String> _agentResolvedPaths = {};

  /// Whether at least one claude-driver agent is available.
  ///
  /// Used by [CliRequiredScreen] to gate app startup.
  bool _claudeAvailable = false;

  /// Whether the initial check has completed.
  bool _checked = false;

  /// Whether a specific agent's CLI is available.
  bool isAgentAvailable(String agentId) =>
      _agentAvailability[agentId] ?? false;

  /// Returns the resolved CLI path for an agent, or null if not found.
  String? resolvedPathForAgent(String agentId) =>
      _agentResolvedPaths[agentId];

  /// Unmodifiable view of per-agent availability.
  Map<String, bool> get agentAvailability =>
      Map.unmodifiable(_agentAvailability);

  /// Whether at least one claude-driver agent is available.
  bool get claudeAvailable => _claudeAvailable;

  /// Whether the initial check has completed.
  bool get checked => _checked;

  /// Checks CLI availability for each agent in the list.
  ///
  /// Each agent's [AgentConfig.driver] is used as the executable name
  /// and [AgentConfig.cliPath] as the custom path override.
  Future<void> checkAgents(List<AgentConfig> agents) async {
    final results = <String, bool>{};
    final paths = <String, String>{};
    for (final agent in agents) {
      final (found, resolvedPath) =
          await _checkExecutable(agent.driver, agent.cliPath);
      results[agent.id] = found;
      if (found && resolvedPath != null) {
        paths[agent.id] = resolvedPath;
      }
    }
    _agentAvailability = results;
    _agentResolvedPaths = paths;
    // Claude is available if ANY claude-driver agent resolves.
    _claudeAvailable = agents
        .where((a) => a.driver == 'claude')
        .any((a) => results[a.id] == true);
    _checked = true;
    notifyListeners();

    developer.log(
      'CLI availability: ${results.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
      name: 'CliAvailabilityService',
    );
  }

  /// Quick check for Claude CLI availability only.
  ///
  /// Used by [CliRequiredScreen] before the full agent list is relevant.
  Future<void> checkClaude({String customPath = ''}) async {
    final (found, _) = await _checkExecutable('claude', customPath);
    _claudeAvailable = found;
    _checked = true;
    notifyListeners();
  }

  /// Checks whether a single CLI executable is available.
  ///
  /// Returns a tuple of (available, resolvedPath). The resolved path is the
  /// actual path to the executable when found.
  ///
  /// If [customPath] is non-empty, verifies that specific file exists and is
  /// runnable. Otherwise falls back to the CLAUDE_CODE_PATH env var (for
  /// claude only) and then `which`.
  Future<(bool, String?)> _checkExecutable(
      String name, String customPath) async {
    // 1. If a custom path is configured, check that file directly.
    if (customPath.isNotEmpty) {
      final resolvedPath = await _resolveCustomPath(name, customPath);
      final found = await _verifyExecutable(resolvedPath);
      developer.log(
        '$name CLI ${found ? 'found' : 'not found'} at custom path: $resolvedPath',
        name: 'CliAvailabilityService',
      );
      return (found, found ? resolvedPath : null);
    }

    // 2. For claude, check the CLAUDE_CODE_PATH environment variable.
    if (name == 'claude') {
      final envPath = Platform.environment['CLAUDE_CODE_PATH'];
      if (envPath != null && envPath.isNotEmpty) {
        if (await _verifyExecutable(envPath)) {
          developer.log(
            '$name CLI found via CLAUDE_CODE_PATH: $envPath',
            name: 'CliAvailabilityService',
          );
          return (true, envPath);
        }
        developer.log(
          '$name CLI not found at CLAUDE_CODE_PATH: $envPath',
          name: 'CliAvailabilityService',
        );
      }
    }

    // 3. Fall back to `which` to search PATH.
    final whichPath = await _whichPath(name);
    final found = whichPath != null;
    developer.log(
      '$name CLI ${found ? 'found' : 'not found'} via PATH lookup${found ? ': $whichPath' : ''}',
      name: 'CliAvailabilityService',
    );
    return (found, whichPath);
  }

  /// Runs `which <name>` and returns the resolved path, or null if not found.
  Future<String?> _whichPath(String name) async {
    try {
      final result = await Process.run('which', [name])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        return path.isNotEmpty ? path : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Verifies that [path] exists on disk and is executable.
  Future<bool> _verifyExecutable(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return false;
      // Check executable bit via `test -x`
      final result = await Process.run('test', ['-x', path])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<String> _resolveCustomPath(String name, String customPath) async {
    final trimmed = customPath.trim();
    if (trimmed.isEmpty) return trimmed;

    final expanded = _expandTilde(trimmed);
    final file = File(expanded);
    if (await file.exists()) {
      return expanded;
    }

    final dir = Directory(expanded);
    if (await dir.exists()) {
      final candidate = p.join(expanded, name);
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    return expanded;
  }

  String _expandTilde(String path) {
    if (!path.startsWith('~')) return path;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return path;
    if (path == '~') return home;
    if (path.startsWith('~/')) {
      return home + path.substring(1);
    }
    return path;
  }
}
