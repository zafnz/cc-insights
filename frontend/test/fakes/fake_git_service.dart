import 'package:cc_insights_v2/services/git_service.dart';

/// Fake implementation of [GitService] for testing.
///
/// Configure responses before running tests:
/// ```dart
/// final gitService = FakeGitService();
/// gitService.version = '2.39.0';
/// gitService.branches['/path/to/repo'] = 'main';
/// gitService.statuses['/path/to/repo'] = GitStatus(staged: 2, unstaged: 1);
/// ```
class FakeGitService implements GitService {
  /// The version to return from [getVersion].
  String version = '2.39.0';

  /// Map of path -> branch name for [getCurrentBranch].
  /// If path not found, throws [GitException].
  /// If value is null, simulates detached HEAD.
  final Map<String, String?> branches = {};

  /// Map of path -> status for [getStatus].
  /// If path not found, throws [GitException].
  final Map<String, GitStatus> statuses = {};

  /// Map of repo root -> worktree list for [discoverWorktrees].
  /// If path not found, throws [GitException].
  final Map<String, List<WorktreeInfo>> worktrees = {};

  /// Map of path -> repo root for [findRepoRoot].
  /// If path not found, returns null.
  final Map<String, String> repoRoots = {};

  /// If set, all methods will throw this exception.
  GitException? throwOnAll;

  /// Delay to add to all operations (simulates slow git).
  Duration? simulatedDelay;

  /// Call counts for verification.
  int getVersionCalls = 0;
  int getCurrentBranchCalls = 0;
  int getStatusCalls = 0;
  int discoverWorktreesCalls = 0;
  int findRepoRootCalls = 0;

  /// Resets all state to defaults.
  void reset() {
    version = '2.39.0';
    branches.clear();
    statuses.clear();
    worktrees.clear();
    repoRoots.clear();
    throwOnAll = null;
    simulatedDelay = null;
    getVersionCalls = 0;
    getCurrentBranchCalls = 0;
    getStatusCalls = 0;
    discoverWorktreesCalls = 0;
    findRepoRootCalls = 0;
  }

  Future<void> _maybeDelay() async {
    if (simulatedDelay != null) {
      await Future.delayed(simulatedDelay!);
    }
  }

  void _maybeThrow() {
    if (throwOnAll != null) {
      throw throwOnAll!;
    }
  }

  @override
  Future<String> getVersion() async {
    getVersionCalls++;
    await _maybeDelay();
    _maybeThrow();
    return version;
  }

  @override
  Future<String?> getCurrentBranch(String path) async {
    getCurrentBranchCalls++;
    await _maybeDelay();
    _maybeThrow();

    if (!branches.containsKey(path)) {
      throw GitException(
        'Not a git repository',
        command: 'git rev-parse --abbrev-ref HEAD',
        exitCode: 128,
      );
    }

    return branches[path];
  }

  @override
  Future<GitStatus> getStatus(String path) async {
    getStatusCalls++;
    await _maybeDelay();
    _maybeThrow();

    if (!statuses.containsKey(path)) {
      throw GitException(
        'Not a git repository',
        command: 'git status --porcelain=v2 --branch',
        exitCode: 128,
      );
    }

    return statuses[path]!;
  }

  @override
  Future<List<WorktreeInfo>> discoverWorktrees(String repoRoot) async {
    discoverWorktreesCalls++;
    await _maybeDelay();
    _maybeThrow();

    if (!worktrees.containsKey(repoRoot)) {
      throw GitException(
        'Not a git repository',
        command: 'git worktree list --porcelain',
        exitCode: 128,
      );
    }

    return worktrees[repoRoot]!;
  }

  @override
  Future<String?> findRepoRoot(String path) async {
    findRepoRootCalls++;
    await _maybeDelay();
    _maybeThrow();

    return repoRoots[path];
  }

  @override
  Future<List<String>> listBranches(String repoRoot) async {
    await _maybeDelay();
    _maybeThrow();
    // Return empty list by default
    return [];
  }

  @override
  Future<bool> branchExists(String repoRoot, String branchName) async {
    await _maybeDelay();
    _maybeThrow();
    // Return false by default
    return false;
  }

  @override
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
  }) async {
    await _maybeDelay();
    _maybeThrow();
    // No-op by default
  }

  // =========================================================================
  // Convenience methods for test setup
  // =========================================================================

  /// Sets up a simple repository with one primary worktree.
  void setupSimpleRepo(String path, {String branch = 'main'}) {
    repoRoots[path] = path;
    branches[path] = branch;
    statuses[path] = const GitStatus();
    worktrees[path] = [
      WorktreeInfo(path: path, isPrimary: true, branch: branch),
    ];
  }

  /// Sets up a repository with the given worktrees.
  void setupRepo(String primaryPath, List<WorktreeInfo> wts) {
    repoRoots[primaryPath] = primaryPath;
    worktrees[primaryPath] = wts;

    for (final wt in wts) {
      repoRoots[wt.path] = primaryPath;
      branches[wt.path] = wt.branch;
      statuses[wt.path] = const GitStatus();
    }
  }
}
