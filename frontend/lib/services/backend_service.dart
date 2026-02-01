import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

/// Service for managing the Claude backend lifecycle.
///
/// This service handles spawning and disposing the Claude CLI backend process,
/// and provides session creation capabilities for chats.
///
/// The backend communicates directly with the Claude CLI using the stream-json
/// protocol. Requires the `claude` CLI to be installed and available in PATH,
/// or configured via the `CLAUDE_CODE_PATH` environment variable.
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
  AgentBackend? _backend;
  StreamSubscription<BackendError>? _errorSubscription;
  bool _isStarting = false;
  String? _error;

  /// Whether the backend is ready to accept session creation requests.
  bool get isReady => _backend != null && _error == null;

  /// Whether the backend is currently starting up.
  bool get isStarting => _isStarting;

  /// The current error message, if any.
  String? get error => _error;

  /// Starts the Claude CLI backend.
  ///
  /// This spawns a direct connection to the Claude CLI using the stream-json
  /// protocol. The CLI path can be configured via the `CLAUDE_CODE_PATH`
  /// environment variable, otherwise it defaults to `claude` in PATH.
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
      _backend = await BackendFactory.create(
        type: BackendType.directCli,
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
  /// - [content]: Optional content blocks (text + images) for the initial message.
  ///   If provided, this takes precedence over [prompt].
  ///
  /// Throws [StateError] if the backend is not started.
  Future<AgentSession> createSession({
    required String prompt,
    required String cwd,
    SessionOptions? options,
    List<ContentBlock>? content,
  }) async {
    if (_backend == null) {
      throw StateError('Backend not started. Call start() first.');
    }
    return _backend!.createSession(
      prompt: prompt,
      cwd: cwd,
      options: options,
      content: content,
    );
  }

  /// Disposes of the backend service and terminates the subprocess.
  ///
  /// This should be called when the app is shutting down to ensure
  /// the backend process is properly terminated.
  @override
  void dispose() {
    _errorSubscription?.cancel();
    _errorSubscription = null;
    _backend?.dispose();
    _backend = null;
    super.dispose();
  }
}
