import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Service that checks whether CLI executables (claude, codex) are available.
///
/// Call [checkAll] after settings are loaded so that custom paths from
/// user preferences are taken into account.
class CliAvailabilityService extends ChangeNotifier {
  bool _claudeAvailable = false;
  bool _codexAvailable = false;
  bool _checked = false;

  /// Whether the Claude CLI was found.
  bool get claudeAvailable => _claudeAvailable;

  /// Whether the Codex CLI was found.
  bool get codexAvailable => _codexAvailable;

  /// Whether the initial check has completed.
  bool get checked => _checked;

  /// Checks both CLIs for availability.
  ///
  /// [claudePath] and [codexPath] are custom paths from settings.
  /// Pass an empty string to use the default PATH lookup.
  Future<void> checkAll({
    String claudePath = '',
    String codexPath = '',
  }) async {
    _claudeAvailable = await _checkExecutable('claude', claudePath);
    _codexAvailable = await _checkExecutable('codex', codexPath);
    _checked = true;
    notifyListeners();

    developer.log(
      'CLI availability: claude=$_claudeAvailable, codex=$_codexAvailable',
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
      return _verifyExecutable(customPath);
    }

    // 2. For claude, check the CLAUDE_CODE_PATH environment variable.
    if (name == 'claude') {
      final envPath = Platform.environment['CLAUDE_CODE_PATH'];
      if (envPath != null && envPath.isNotEmpty) {
        if (await _verifyExecutable(envPath)) return true;
      }
    }

    // 3. Fall back to `which` to search PATH.
    return _whichExists(name);
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
}
