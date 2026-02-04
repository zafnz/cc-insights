import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import 'git_service.dart';

/// Per-worktree watcher state.
///
/// Holds the filesystem subscription, throttle timer, periodic timer,
/// and last-poll timestamp for a single worktree.
class _WorktreeWatcher {
  final WorktreeState worktree;

  StreamSubscription<FileSystemEvent>? watcherSubscription;
  Timer? pollTimer;
  Timer? periodicTimer;
  DateTime? lastPollTime;
  bool pollPending = false;

  _WorktreeWatcher(this.worktree);

  /// Cancels all timers and subscriptions for this watcher.
  void cancel() {
    watcherSubscription?.cancel();
    watcherSubscription = null;
    pollTimer?.cancel();
    pollTimer = null;
    periodicTimer?.cancel();
    periodicTimer = null;
    pollPending = false;
  }
}

/// Service that watches all project worktrees for filesystem changes
/// and polls git status at a throttled interval.
///
/// Listens to [ProjectState] and automatically starts/stops watchers
/// as worktrees are added or removed. Each worktree gets its own
/// filesystem watcher and periodic polling timer.
class WorktreeWatcherService extends ChangeNotifier {
  /// Minimum interval between git status polls triggered by
  /// filesystem events.
  static const pollInterval = Duration(seconds: 10);

  /// Interval for periodic background polling (catches changes not
  /// visible to the filesystem watcher, e.g. `git fetch`).
  static const periodicInterval = Duration(minutes: 2);

  final GitService _gitService;
  final ProjectState _project;
  final bool _enablePeriodicPolling;
  bool _disposed = false;

  /// Active watchers keyed by worktree root path.
  final Map<String, _WorktreeWatcher> _watchers = {};

  /// Creates a [WorktreeWatcherService] that automatically watches
  /// all worktrees in [project].
  ///
  /// Set [enablePeriodicPolling] to false to disable background
  /// timers (useful in tests to avoid interfering with
  /// pumpAndSettle).
  WorktreeWatcherService({
    required GitService gitService,
    required ProjectState project,
    bool enablePeriodicPolling = true,
  })  : _gitService = gitService,
        _project = project,
        _enablePeriodicPolling = enablePeriodicPolling {
    _project.addListener(_syncWatchers);
    _syncWatchers();
  }

  /// Reconciles active watchers with the project's worktree list.
  ///
  /// Adds watchers for new worktrees and removes watchers for
  /// worktrees that no longer exist in the project.
  void _syncWatchers() {
    if (_disposed) return;

    final allWt = _project.allWorktrees;

    final desiredPaths = <String>{};
    for (final wt in allWt) {
      desiredPaths.add(wt.data.worktreeRoot);
    }

    // Remove watchers for worktrees no longer in the project.
    final currentPaths = _watchers.keys.toSet();
    final toRemove = currentPaths.difference(desiredPaths);
    for (final path in toRemove) {
      _watchers[path]?.cancel();
      _watchers.remove(path);
    }

    // Add watchers for new worktrees.
    for (final wt in _project.allWorktrees) {
      final path = wt.data.worktreeRoot;
      if (!_watchers.containsKey(path)) {
        _startWatching(wt);
      }
    }
  }

  /// Starts watching a single worktree.
  void _startWatching(WorktreeState worktree) {
    if (_disposed) return;

    final path = worktree.data.worktreeRoot;
    final watcher = _WorktreeWatcher(worktree);
    _watchers[path] = watcher;

    // Start filesystem watcher.
    _startFsWatcher(watcher);

    // Start periodic background polling.
    if (_enablePeriodicPolling) {
      watcher.periodicTimer = Timer.periodic(
        periodicInterval,
        (_) => _pollGitStatus(watcher),
      );
    }

    // Immediate initial poll.
    _pollGitStatus(watcher);
  }

  /// Starts a filesystem watcher for the given [watcher]'s path.
  void _startFsWatcher(_WorktreeWatcher watcher) {
    try {
      final dir = Directory(watcher.worktree.data.worktreeRoot);
      if (!dir.existsSync()) return;

      watcher.watcherSubscription = dir
          .watch(recursive: true)
          .listen(
            (event) => _handleFileSystemEvent(watcher, event),
            onError: (_) {},
          );
    } catch (_) {
      // Failed to start watcher (e.g., in tests).
    }
  }

  /// Handles a filesystem event by scheduling a throttled poll.
  void _handleFileSystemEvent(
    _WorktreeWatcher watcher,
    FileSystemEvent event,
  ) {
    _schedulePoll(watcher);
  }

  /// Schedules a git status poll, respecting the throttle interval.
  void _schedulePoll(_WorktreeWatcher watcher) {
    if (_disposed) return;
    if (watcher.pollPending) return;

    final now = DateTime.now();
    final lastPoll = watcher.lastPollTime;

    if (lastPoll == null) {
      _pollGitStatus(watcher);
    } else {
      final elapsed = now.difference(lastPoll);
      if (elapsed >= pollInterval) {
        _pollGitStatus(watcher);
      } else {
        final remaining = pollInterval - elapsed;
        watcher.pollPending = true;
        watcher.pollTimer?.cancel();
        watcher.pollTimer = Timer(remaining, () {
          watcher.pollPending = false;
          _pollGitStatus(watcher);
        });
      }
    }
  }

  /// Polls git status and updates the worktree state.
  Future<void> _pollGitStatus(_WorktreeWatcher watcher) async {
    if (_disposed) return;

    final worktree = watcher.worktree;
    watcher.lastPollTime = DateTime.now();

    try {
      final path = worktree.data.worktreeRoot;

      final status = await _gitService.getStatus(path);
      final upstream = await _gitService.getUpstream(path);

      // Determine base comparison target per branch:
      // - If branch has upstream → use remote main (origin/main)
      // - Otherwise → use local main
      String? baseRef;
      var isRemoteBase = false;

      if (upstream != null) {
        final remoteMain = await _gitService.getRemoteMainBranch(
          _project.data.repoRoot,
        );
        if (remoteMain != null) {
          baseRef = remoteMain;
          isRemoteBase = true;
        }
      }

      // Fallback to local main if no remote base was found
      if (baseRef == null) {
        final localMain = await _gitService.getMainBranch(
          _project.data.repoRoot,
        );
        if (localMain != null) {
          baseRef = localMain;
        }
      }

      ({int ahead, int behind})? baseComparison;
      if (baseRef != null &&
          worktree.data.branch != baseRef) {
        baseComparison = await _gitService.getBranchComparison(
          path,
          worktree.data.branch,
          baseRef,
        );
      }

      if (_disposed) return;

      // Only update if still watching this worktree.
      if (!_watchers.containsKey(path)) return;

      // Detect conflict operation type. Check whenever there are
      // conflicts OR a previous operation was in progress, so we
      // can detect the "resolved but not yet continued" state.
      final hadOperation =
          worktree.data.conflictOperation != null;
      MergeOperationType? conflictOp;
      if (status.hasConflicts || hadOperation) {
        conflictOp =
            await _gitService.getConflictOperation(path);
      }

      if (_disposed) return;
      if (!_watchers.containsKey(path)) return;


      worktree.updateData(worktree.data.copyWith(
        uncommittedFiles: status.uncommittedFiles,
        stagedFiles: status.staged,
        commitsAhead: status.ahead,
        commitsBehind: status.behind,
        hasMergeConflict: status.hasConflicts,
        conflictOperation: conflictOp,
        clearConflictOperation: conflictOp == null,
        upstreamBranch: upstream,
        clearUpstreamBranch: upstream == null,
        commitsAheadOfMain: baseComparison?.ahead ?? 0,
        commitsBehindMain: baseComparison?.behind ?? 0,
        isRemoteBase: isRemoteBase,
        baseRef: baseRef,
        clearBaseRef: baseRef == null,
      ));
    } catch (_) {
      // Git poll failed — will retry on next interval.
    }
  }

  /// Forces an immediate git status poll for [worktree].
  Future<void> forceRefresh(WorktreeState worktree) async {
    final watcher = _watchers[worktree.data.worktreeRoot];
    if (watcher == null) return;
    watcher.pollTimer?.cancel();
    watcher.pollPending = false;
    await _pollGitStatus(watcher);
  }

  /// Forces an immediate git status poll for all watched worktrees.
  Future<void> forceRefreshAll() async {
    await Future.wait(
      _watchers.values.map((w) {
        w.pollTimer?.cancel();
        w.pollPending = false;
        return _pollGitStatus(w);
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _project.removeListener(_syncWatchers);
    for (final w in _watchers.values) {
      w.cancel();
    }
    _watchers.clear();
    super.dispose();
  }
}
