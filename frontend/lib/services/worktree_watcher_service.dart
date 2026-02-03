import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import 'git_service.dart';

/// Service that watches a worktree's filesystem for changes and polls git
/// status at a throttled interval.
///
/// Uses Dart's built-in [Directory.watch] to monitor the worktree directory
/// for file changes. When changes are detected, the service waits for the
/// throttle interval before polling git status, ensuring we don't poll more
/// than once every [pollInterval].
class WorktreeWatcherService extends ChangeNotifier {
  /// Minimum interval between git status polls triggered by filesystem events.
  static const pollInterval = Duration(seconds: 10);

  /// Interval for periodic background polling (catches changes not visible
  /// to the filesystem watcher, e.g. `git fetch`).
  static const periodicInterval = Duration(seconds: 30);

  final GitService _gitService;
  final ProjectState _project;
  final bool _enablePeriodicPolling;

  WorktreeState? _currentWorktree;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  Timer? _pollTimer;
  Timer? _periodicTimer;
  DateTime? _lastPollTime;
  bool _pollPending = false;
  bool _disposed = false;

  /// Creates a [WorktreeWatcherService] with the given dependencies.
  ///
  /// Set [enablePeriodicPolling] to false to disable the background timer
  /// (useful in tests to avoid interfering with pumpAndSettle).
  WorktreeWatcherService({
    required GitService gitService,
    required ProjectState project,
    bool enablePeriodicPolling = true,
  })  : _gitService = gitService,
        _project = project,
        _enablePeriodicPolling = enablePeriodicPolling;

  /// The worktree currently being watched.
  WorktreeState? get currentWorktree => _currentWorktree;

  /// Starts watching the given worktree for filesystem changes.
  ///
  /// Stops any existing watcher before starting a new one. Also triggers
  /// an immediate git status poll.
  void watchWorktree(WorktreeState worktree) {
    if (_disposed) return;

    // Don't restart if already watching this worktree
    if (_currentWorktree == worktree) return;

    stopWatching();
    _currentWorktree = worktree;

    // Start filesystem watcher
    _startWatcher(worktree.data.worktreeRoot);

    // Start periodic background polling
    if (_enablePeriodicPolling) {
      _startPeriodicPolling();
    }

    // Trigger immediate poll
    _pollGitStatus();
  }

  /// Stops watching the current worktree.
  void stopWatching() {
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _currentWorktree = null;
    _pollPending = false;
  }

  /// Starts a repeating timer that polls git status every [periodicInterval].
  ///
  /// This catches changes that don't trigger filesystem events, such as
  /// `git fetch` updating remote tracking refs inside `.git/`.
  void _startPeriodicPolling() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(periodicInterval, (_) {
      _pollGitStatus();
    });
  }

  /// Starts the filesystem watcher for the given path.
  void _startWatcher(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) {
        // Directory doesn't exist (e.g., in tests) - silently skip
        return;
      }

      // Watch recursively for all file changes
      _watcherSubscription = dir.watch(recursive: true).listen(
        _handleFileSystemEvent,
        onError: (_) {
          // Watcher errors are expected in tests - silently ignore
        },
      );
    } catch (_) {
      // Failed to start watcher (e.g., in tests) - silently ignore
    }
  }

  /// Handles a filesystem event by scheduling a throttled poll.
  void _handleFileSystemEvent(FileSystemEvent event) {
    // Ignore .git directory internal changes (too noisy)
    if (event.path.contains('/.git/')) return;

    _schedulePoll();
  }

  /// Schedules a git status poll, respecting the throttle interval.
  void _schedulePoll() {
    if (_disposed || _currentWorktree == null) return;

    // If a poll is already pending, don't schedule another
    if (_pollPending) return;

    final now = DateTime.now();
    final lastPoll = _lastPollTime;

    if (lastPoll == null) {
      // First poll - execute immediately
      _pollGitStatus();
    } else {
      final elapsed = now.difference(lastPoll);
      if (elapsed >= pollInterval) {
        // Enough time has passed - poll immediately
        _pollGitStatus();
      } else {
        // Schedule a poll after the remaining interval
        final remaining = pollInterval - elapsed;
        _pollPending = true;
        _pollTimer?.cancel();
        _pollTimer = Timer(remaining, () {
          _pollPending = false;
          _pollGitStatus();
        });
      }
    }
  }

  /// Polls git status and updates the worktree state.
  Future<void> _pollGitStatus() async {
    if (_disposed) return;

    final worktree = _currentWorktree;
    if (worktree == null) return;

    _lastPollTime = DateTime.now();

    try {
      final path = worktree.data.worktreeRoot;

      // Fetch basic git status
      final status = await _gitService.getStatus(path);

      // Fetch upstream branch
      final upstream = await _gitService.getUpstream(path);

      // Fetch comparison to main branch
      final mainBranch = await _gitService.getMainBranch(_project.data.repoRoot);
      ({int ahead, int behind})? mainComparison;
      if (mainBranch != null && worktree.data.branch != mainBranch) {
        mainComparison = await _gitService.getBranchComparison(
          path,
          worktree.data.branch,
          mainBranch,
        );
      }

      // Update worktree data if still watching the same worktree
      if (!_disposed && _currentWorktree == worktree) {
        worktree.updateData(worktree.data.copyWith(
          uncommittedFiles: status.uncommittedFiles,
          stagedFiles: status.staged,
          commitsAhead: status.ahead,
          commitsBehind: status.behind,
          hasMergeConflict: status.hasConflicts,
          upstreamBranch: upstream,
          clearUpstreamBranch: upstream == null,
          commitsAheadOfMain: mainComparison?.ahead ?? 0,
          commitsBehindMain: mainComparison?.behind ?? 0,
        ));

        // Notify listeners that status has been updated
        notifyListeners();
      }
    } catch (_) {
      // Git status poll failed (e.g., in tests) - silently ignore
    }
  }

  /// Forces an immediate git status poll, ignoring the throttle interval.
  ///
  /// Useful for when the user explicitly requests a refresh.
  Future<void> forceRefresh() async {
    _pollTimer?.cancel();
    _pollPending = false;
    await _pollGitStatus();
  }

  @override
  void dispose() {
    _disposed = true;
    stopWatching();
    super.dispose();
  }
}
