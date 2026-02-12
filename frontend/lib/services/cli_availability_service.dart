import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Service that checks whether CLI executables (claude, codex, acp) are available.
///
/// Call [checkAll] after settings are loaded so that custom paths from
/// user preferences are taken into account.
class CliAvailabilityService extends ChangeNotifier {
  bool _claudeAvailable = false;
  bool _codexAvailable = false;
  bool _acpAvailable = false;
  bool _checked = false;

  /// Whether the Claude CLI was found.
  bool get claudeAvailable => _claudeAvailable;

  /// Whether the Codex CLI was found.
  bool get codexAvailable => _codexAvailable;

  /// Whether the ACP agent executable was found.
  bool get acpAvailable => _acpAvailable;

  /// Whether the initial check has completed.
  bool get checked => _checked;

  /// Checks both CLIs for availability.
  ///
  /// [claudePath], [codexPath], and [acpPath] are custom paths from settings.
  /// Pass an empty string to use the default PATH lookup.
  Future<void> checkAll({
    String claudePath = '',
    String codexPath = '',
    String acpPath = '',
  }) async {
    _claudeAvailable = await _checkExecutable('claude', claudePath);
    _codexAvailable = await _checkExecutable('codex', codexPath);
    _acpAvailable = await _checkExecutable('acp', acpPath);
    _checked = true;
    notifyListeners();

    developer.log(
      'CLI availability: claude=$_claudeAvailable, codex=$_codexAvailable, acp=$_acpAvailable',
      name: 'CliAvailabilityService',
    );
  }

  /// Checks whether a single CLI executable is available.
  ///
  /// If [customPath] is non-empty, verifies that specific file exists and is
  /// runnable. Otherwise falls back to the CLAUDE_CODE_PATH env var (for
  /// claude only) and then `which`.
  Future<bool> _checkExecutable(String name, String customPath) async {
    // 1. If a custom path is configured, check that file directly.
    if (customPath.isNotEmpty) {
      final resolvedPath = await _resolveCustomPath(name, customPath);
      final found = await _verifyExecutable(resolvedPath);
      developer.log(
        '$name CLI ${found ? 'found' : 'not found'} at custom path: $resolvedPath',
        name: 'CliAvailabilityService',
      );
      return found;
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
          return true;
        }
        developer.log(
          '$name CLI not found at CLAUDE_CODE_PATH: $envPath',
          name: 'CliAvailabilityService',
        );
      }
    }

    // 3. Fall back to `which` to search PATH.
    final found = await _whichExists(name);
    developer.log(
      '$name CLI ${found ? 'found' : 'not found'} via PATH lookup',
      name: 'CliAvailabilityService',
    );
    return found;
  }

  /// Runs `which <name>` and returns true if it exits with code 0.
  Future<bool> _whichExists(String name) async {
    try {
      final result = await Process.run('which', [name])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
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
