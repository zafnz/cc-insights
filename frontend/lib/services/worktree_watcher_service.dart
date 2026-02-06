import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/project.dart';
import '../models/worktree.dart';
import 'git_service.dart';
import 'project_config_service.dart';

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

  /// Throttle interval for the common .git directory watcher.
  ///
  /// Shorter than per-worktree polling because git dir changes
  /// are higher signal (commit, push, fetch).
  static const gitDirPollInterval = Duration(seconds: 5);

  /// Interval for periodic `git fetch origin` to keep remote refs
  /// up to date. All worktrees share the same `.git` directory, so
  /// a single fetch at the project repo root is sufficient.
  static const fetchInterval = Duration(minutes: 2);

  final GitService _gitService;
  final ProjectState _project;
  final ProjectConfigService _configService;
  final bool _enablePeriodicPolling;
  bool _disposed = false;

  /// Active watchers keyed by worktree root path.
  final Map<String, _WorktreeWatcher> _watchers = {};

  /// Watcher for the common .git directory.
  StreamSubscription<FileSystemEvent>? _gitDirWatcherSubscription;

  /// Throttle state for the common git dir watcher.
  Timer? _gitDirPollTimer;
  DateTime? _gitDirLastPollTime;
  bool _gitDirPollPending = false;

  /// Timer for periodic `git fetch origin`.
  Timer? _fetchTimer;

  /// Timestamp of the last completed fetch.
  DateTime? _lastFetchTime;

  /// Creates a [WorktreeWatcherService] that automatically watches
  /// all worktrees in [project].
  ///
  /// Set [enablePeriodicPolling] to false to disable background
  /// timers (useful in tests to avoid interfering with
  /// pumpAndSettle).
  WorktreeWatcherService({
    required GitService gitService,
    required ProjectState project,
    required ProjectConfigService configService,
    bool enablePeriodicPolling = true,
  })  : _gitService = gitService,
        _project = project,
        _configService = configService,
        _enablePeriodicPolling = enablePeriodicPolling {
    _project.addListener(_syncWatchers);
    _syncWatchers();
    _startGitDirWatcher();
    _startPeriodicFetch();
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
  ///
  /// Events from the `.git` directory are skipped here — they are
  /// handled by the dedicated common git dir watcher instead.
  void _handleFileSystemEvent(
    _WorktreeWatcher watcher,
    FileSystemEvent event,
  ) {
    final path = event.path;
    if (path.contains('/.git/') || path.endsWith('/.git')) return;
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

      // Resolve the base ref using the override chain:
      // 1. Per-worktree base
      // 2. Project config defaultBase
      // 3. Auto-detect (remote main if upstream, else local main)
      final resolved = await _resolveBaseRef(worktree, upstream);
      final baseRef = resolved.baseRef;
      final isRemoteBase = resolved.isRemoteBase;

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

  // -----------------------------------------------------------------
  // Base ref resolution
  // -----------------------------------------------------------------

  /// Resolves the base ref for comparing a worktree's branch.
  ///
  /// Resolution chain (first non-null/non-auto wins):
  /// 1. Per-worktree [WorktreeState.base]
  /// 2. Project config [ProjectConfig.defaultBase]
  /// 3. Auto-detect: remote main (if upstream exists) or local main
  ///
  /// Returns a record with the resolved [baseRef] and whether it
  /// [isRemoteBase] (a remote tracking ref like "origin/main").
  @visibleForTesting
  Future<({String? baseRef, bool isRemoteBase})> resolveBaseRef(
    WorktreeState worktree,
    String? upstream,
  ) => _resolveBaseRef(worktree, upstream);

  Future<({String? baseRef, bool isRemoteBase})> _resolveBaseRef(
    WorktreeState worktree,
    String? upstream,
  ) async {
    final repoRoot = _project.data.repoRoot;

    // 1. Per-worktree base takes highest priority.
    final base = worktree.base;
    if (base != null && base.isNotEmpty) {
      return (
        baseRef: base,
        isRemoteBase: _isRemoteRef(base),
      );
    }

    // 2. Project-level default base from config.
    try {
      final config = await _configService.loadConfig(repoRoot);
      final defaultBase = config.defaultBase;
      if (defaultBase != null &&
          defaultBase.isNotEmpty &&
          defaultBase != 'auto') {
        return (
          baseRef: defaultBase,
          isRemoteBase: _isRemoteRef(defaultBase),
        );
      }
    } catch (_) {
      // Config load failed; fall through to auto-detect.
    }

    // 3. Auto-detect: remote main if upstream exists, else local main.
    return _autoDetectBaseRef(upstream, repoRoot);
  }

  /// Auto-detects the base ref using upstream information.
  ///
  /// If the worktree has an upstream, tries the remote main branch
  /// first. Falls back to local main if no remote main is found.
  Future<({String? baseRef, bool isRemoteBase})> _autoDetectBaseRef(
    String? upstream,
    String repoRoot,
  ) async {
    if (upstream != null) {
      final remoteMain = await _gitService.getRemoteMainBranch(
        repoRoot,
      );
      if (remoteMain != null) {
        return (baseRef: remoteMain, isRemoteBase: true);
      }
    }

    final localMain = await _gitService.getMainBranch(repoRoot);
    return (baseRef: localMain, isRemoteBase: false);
  }

  /// Whether a ref string refers to a remote tracking branch.
  static bool _isRemoteRef(String ref) =>
      ref.startsWith('origin/') || ref.startsWith('remotes/');

  // -----------------------------------------------------------------
  // Common .git directory watcher
  // -----------------------------------------------------------------

  /// Starts watching the common .git directory for changes.
  ///
  /// The common .git directory is shared between all worktrees.
  /// Changes here (commits, pushes, fetches, branch operations)
  /// affect all worktrees. When a change is detected, all
  /// worktrees are refreshed via [forceRefreshAll].
  ///
  /// For linked worktrees, the `.git` path is a file pointing to the
  /// worktree-specific git dir. We resolve the common git dir using
  /// `git rev-parse --git-common-dir`.
  void _startGitDirWatcher() {
    if (_disposed) return;
    // Start async resolution without blocking constructor.
    _resolveAndWatchGitDir();
  }

  /// Resolves the common .git directory path and starts watching it.
  Future<void> _resolveAndWatchGitDir() async {
    if (_disposed) return;

    final gitPath = '${_project.data.repoRoot}/.git';
    String? commonGitDir;

    try {
      final fileType = FileSystemEntity.typeSync(gitPath);
      if (fileType == FileSystemEntityType.directory) {
        // Primary worktree: .git is the common directory.
        commonGitDir = gitPath;
      } else if (fileType == FileSystemEntityType.file) {
        // Linked worktree: .git is a file. Use git to find common dir.
        commonGitDir = await _getGitCommonDir(_project.data.repoRoot);
      }
    } catch (_) {
      // Failed to determine git dir type.
    }

    if (_disposed) return;
    if (commonGitDir == null) return;

    try {
      final dir = Directory(commonGitDir);
      if (!dir.existsSync()) return;

      _gitDirWatcherSubscription = dir
          .watch(recursive: true)
          .listen(
            (_) => _onGitDirChanged(),
            onError: (_) {},
          );
    } catch (_) {
      // Failed to start watcher (e.g., in tests or bare repos).
    }
  }

  /// Gets the common .git directory path using git rev-parse.
  Future<String?> _getGitCommonDir(String workingDir) async {
    try {
      final result = await Process.run(
        'git',
        ['rev-parse', '--git-common-dir'],
        workingDirectory: workingDir,
      );
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        // Path may be relative; resolve against working directory.
        if (path.startsWith('/')) {
          return path;
        }
        return Directory(workingDir).uri.resolve(path).toFilePath();
      }
    } catch (_) {
      // Git command failed.
    }
    return null;
  }

  /// Called when a change is detected in the common .git directory.
  ///
  /// Schedules a throttled refresh of all worktrees.
  void _onGitDirChanged() {
    if (_disposed) return;
    if (_gitDirPollPending) return;

    final now = DateTime.now();
    final lastPoll = _gitDirLastPollTime;

    if (lastPoll == null) {
      _refreshAllFromGitDir();
    } else {
      final elapsed = now.difference(lastPoll);
      if (elapsed >= gitDirPollInterval) {
        _refreshAllFromGitDir();
      } else {
        final remaining = gitDirPollInterval - elapsed;
        _gitDirPollPending = true;
        _gitDirPollTimer?.cancel();
        _gitDirPollTimer = Timer(remaining, () {
          _gitDirPollPending = false;
          _refreshAllFromGitDir();
        });
      }
    }
  }

  /// Refreshes all worktrees in response to a common git dir change.
  void _refreshAllFromGitDir() {
    if (_disposed) return;
    _gitDirLastPollTime = DateTime.now();
    forceRefreshAll();
  }

  /// Simulates a git directory change for testing.
  ///
  /// Triggers the same throttled refresh-all logic that a real
  /// filesystem event in the .git directory would trigger.
  @visibleForTesting
  void onGitDirChanged() => _onGitDirChanged();

  // -----------------------------------------------------------------
  // Periodic git fetch
  // -----------------------------------------------------------------

  /// Starts the periodic `git fetch origin` timer.
  ///
  /// Disabled when [_enablePeriodicPolling] is false (tests).
  void _startPeriodicFetch() {
    if (!_enablePeriodicPolling) return;
    _fetchTimer = Timer.periodic(fetchInterval, (_) => _fetchOrigin());
  }

  /// Runs `git fetch` against the project repo root and refreshes
  /// all worktrees afterwards.
  ///
  /// Network failures are non-fatal and silently ignored — status
  /// polls will continue with stale remote refs until the next
  /// successful fetch.
  Future<void> _fetchOrigin() async {
    if (_disposed) return;
    _lastFetchTime = DateTime.now();
    try {
      await _gitService.fetch(_project.data.repoRoot);
    } catch (_) {
      // Network failures are non-fatal.
    }
    if (!_disposed) {
      await forceRefreshAll();
    }
  }

  /// Triggers a fetch for testing purposes.
  @visibleForTesting
  Future<void> fetchOrigin() => _fetchOrigin();

  /// The timestamp of the last completed fetch, for testing.
  @visibleForTesting
  DateTime? get lastFetchTime => _lastFetchTime;

  // -----------------------------------------------------------------

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

    // Cancel periodic fetch timer.
    _fetchTimer?.cancel();
    _fetchTimer = null;

    // Cancel common git dir watcher.
    _gitDirWatcherSubscription?.cancel();
    _gitDirWatcherSubscription = null;
    _gitDirPollTimer?.cancel();
    _gitDirPollTimer = null;

    for (final w in _watchers.values) {
      w.cancel();
    }
    _watchers.clear();
    super.dispose();
  }
}
