import 'dart:async';
import 'dart:io';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Service for managing the Node.js backend subprocess lifecycle.
///
/// This service handles spawning and disposing the Claude backend process,
/// and provides session creation capabilities for chats.
///
/// Usage:
/// ```dart
/// final backendService = BackendService();
/// await backendService.start();
///
/// // Check if ready
/// if (backendService.isReady) {
///   final session = await backendService.createSession(
///     prompt: 'Hello',
///     cwd: '/path/to/project',
///   );
/// }
///
/// // Dispose when done
/// backendService.dispose();
/// ```
class BackendService extends ChangeNotifier {
  ClaudeBackend? _backend;
  StreamSubscription<BackendError>? _errorSubscription;
  bool _isStarting = false;
  String? _error;

  /// Whether the backend is ready to accept session creation requests.
  bool get isReady => _backend != null && _error == null;

  /// Whether the backend is currently starting up.
  bool get isStarting => _isStarting;

  /// The current error message, if any.
  String? get error => _error;

  /// Starts the Node.js backend subprocess.
  ///
  /// This method is idempotent - calling it while already started or starting
  /// will return immediately without doing anything.
  ///
  /// After calling this method, check [isReady] to verify the backend started
  /// successfully, or [error] to see what went wrong.
  Future<void> start() async {
    if (_backend != null || _isStarting) return;

    _isStarting = true;
    _error = null;
    notifyListeners();

    try {
      _backend = await ClaudeBackend.spawn(
        backendPath: _getBackendPath(),
      );

      // Monitor backend errors
      _errorSubscription = _backend!.errors.listen((error) {
        _error = error.toString();
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      _backend = null;
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }

  /// Creates a new Claude session.
  ///
  /// The backend must be started and ready before calling this method.
  ///
  /// Parameters:
  /// - [prompt]: The initial prompt to start the session with.
  /// - [cwd]: The working directory for the session (typically the worktree root).
  /// - [options]: Optional session configuration (model, permission mode, etc.).
  ///
  /// Throws [StateError] if the backend is not started.
  Future<ClaudeSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
  }) async {
    if (_backend == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    return _backend!.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
    );
  }

  /// Disposes of the backend service and terminates the subprocess.
  ///
  /// This should be called when the app is shutting down to ensure
  /// the Node.js process is properly terminated.
  @override
  void dispose() {
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _backend?.dispose();
    _backend = null;
    super.dispose();
  }

  /// Gets the path to the backend Node.js entry point.
  ///
  /// In development, this returns the path to the compiled JavaScript.
  /// In production, this would return the path to a bundled executable.
  String _getBackendPath() {
    // Get the directory where the app is running from
    final currentDir = Directory.current.path;

    // Check if we're in the flutter_app_v2 directory
    if (path.basename(currentDir) == 'flutter_app_v2') {
      // Development: relative to flutter_app_v2
      return path.join(currentDir, '..', 'backend-node', 'dist', 'index.js');
    }

    // Check if we're in the project root
    final backendPath =
        path.join(currentDir, 'backend-node', 'dist', 'index.js');
    if (File(backendPath).existsSync()) {
      return backendPath;
    }

    // macOS app bundle: look in Resources
    if (Platform.isMacOS) {
      final executablePath = Platform.resolvedExecutable;
      final appDir = path.dirname(path.dirname(executablePath));
      final resourcesPath =
          path.join(appDir, 'Resources', 'backend', 'index.js');
      if (File(resourcesPath).existsSync()) {
        return resourcesPath;
      }
    }

    // Fallback: assume we're in project root
    return path.join(currentDir, 'backend-node', 'dist', 'index.js');
  }
}
