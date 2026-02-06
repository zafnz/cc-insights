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
    fileAtRefContents.clear();
    remoteMainBranches.clear();
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
    String? base,
  }) async {
    await _maybeDelay();
    _maybeThrow();
    // No-op by default
  }

  /// Map of path -> upstream branch for [getUpstream].
  final Map<String, String?> upstreams = {};

  /// Map of (path, branch, targetBranch) -> comparison for [getBranchComparison].
  final Map<String, ({int ahead, int behind})?> branchComparisons = {};

  /// Map of repo root -> main branch for [getMainBranch].
  final Map<String, String?> mainBranches = {};

  @override
  Future<String?> getUpstream(String path) async {
    await _maybeDelay();
    _maybeThrow();
    return upstreams[path];
  }

  @override
  Future<({int ahead, int behind})?> getBranchComparison(
    String path,
    String branch,
    String targetBranch,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    final key = '$path:$branch:$targetBranch';
    return branchComparisons[key];
  }

  @override
  Future<String?> getMainBranch(String repoRoot) async {
    await _maybeDelay();
    _maybeThrow();
    return mainBranches[repoRoot] ?? 'main';
  }

  /// Map of repo root -> remote main branch for [getRemoteMainBranch].
  final Map<String, String?> remoteMainBranches = {};

  @override
  Future<String?> getRemoteMainBranch(String repoRoot) async {
    await _maybeDelay();
    _maybeThrow();
    return remoteMainBranches[repoRoot];
  }

  /// Map of path -> changed files for [getChangedFiles].
  final Map<String, List<GitFileChange>> changedFiles = {};

  /// Tracks calls to [stageAll].
  final List<String> stageAllCalls = [];

  /// Tracks calls to [commit] with (path, message).
  final List<(String, String)> commitCalls = [];

  /// Tracks calls to [resetIndex].
  final List<String> resetIndexCalls = [];

  /// If set, [commit] will throw this exception.
  GitException? commitError;

  /// If set, [stageAll] will throw this exception.
  GitException? stageAllError;

  @override
  Future<List<GitFileChange>> getChangedFiles(String path) async {
    await _maybeDelay();
    _maybeThrow();
    return changedFiles[path] ?? [];
  }

  /// Map of (worktreePath:filePath:ref) -> content for [getFileAtRef].
  final Map<String, String?> fileAtRefContents = {};

  @override
  Future<String?> getFileAtRef(
    String worktreePath,
    String filePath,
    String ref,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    final key = '$worktreePath:$filePath:$ref';
    return fileAtRefContents[key];
  }

  @override
  Future<void> stageAll(String path) async {
    stageAllCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
    if (stageAllError != null) {
      throw stageAllError!;
    }
  }

  @override
  Future<void> commit(String path, String message) async {
    commitCalls.add((path, message));
    await _maybeDelay();
    _maybeThrow();
    if (commitError != null) {
      throw commitError!;
    }
  }

  @override
  Future<void> resetIndex(String path) async {
    resetIndexCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
  }

  /// Tracks calls to [stash].
  final List<String> stashCalls = [];

  /// If set, [stash] will throw this exception.
  GitException? stashError;

  @override
  Future<void> stash(String path) async {
    stashCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
    if (stashError != null) {
      throw stashError!;
    }
  }

  /// Tracks calls to [fetch].
  final List<String> fetchCalls = [];

  /// If set, [fetch] will throw this exception.
  GitException? fetchError;

  @override
  Future<void> fetch(String path) async {
    fetchCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
    if (fetchError != null) {
      throw fetchError!;
    }
  }

  /// Tracks calls to [fetchRemote].
  final List<(String path, String remote)> fetchRemoteCalls = [];

  @override
  Future<void> fetchRemote(String path, String remote) async {
    fetchRemoteCalls.add((path, remote));
    await _maybeDelay();
    _maybeThrow();
  }

  /// Map of (path, branch, targetBranch) -> isMerged for [isBranchMerged].
  final Map<String, bool> branchMerged = {};

  /// If set, [isBranchMerged] will throw this exception.
  GitException? isBranchMergedError;

  @override
  Future<bool> isBranchMerged(
    String path,
    String branch,
    String targetBranch,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    if (isBranchMergedError != null) {
      throw isBranchMergedError!;
    }
    final key = '$path:$branch:$targetBranch';
    return branchMerged[key] ?? true; // Default to merged
  }

  /// Tracks calls to [removeWorktree] with (repoRoot, worktreePath, force).
  final List<({String repoRoot, String worktreePath, bool force})>
      removeWorktreeCalls = [];

  /// If set, [removeWorktree] will throw this exception.
  GitException? removeWorktreeError;

  /// If true, [removeWorktree] will only throw on first call (non-force).
  bool removeWorktreeOnlyThrowOnNonForce = false;

  @override
  Future<void> removeWorktree({
    required String repoRoot,
    required String worktreePath,
    bool force = false,
  }) async {
    removeWorktreeCalls.add((
      repoRoot: repoRoot,
      worktreePath: worktreePath,
      force: force,
    ));
    await _maybeDelay();
    _maybeThrow();
    if (removeWorktreeError != null) {
      if (removeWorktreeOnlyThrowOnNonForce && force) {
        return; // Force succeeds
      }
      throw removeWorktreeError!;
    }
  }

  /// Map of (path, branch, targetBranch) -> unmerged commits for [getUnmergedCommits].
  final Map<String, List<String>> unmergedCommits = {};

  @override
  Future<List<String>> getUnmergedCommits(
    String path,
    String branch,
    String targetBranch,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    final key = '$path:$branch:$targetBranch';
    return unmergedCommits[key] ?? [];
  }

  /// Map of (path, targetBranch) -> commits ahead for [getCommitsAhead].
  final Map<String, List<({String sha, String message})>> commitsAhead = {};

  @override
  Future<List<({String sha, String message})>> getCommitsAhead(
    String path,
    String targetBranch,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    final key = '$path:$targetBranch';
    return commitsAhead[key] ?? [];
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

  // =========================================================================
  // Merge/Rebase operations
  // =========================================================================

  /// Result for [wouldMergeConflict]. Key is path.
  final Map<String, bool> wouldConflict = {};

  /// Result for [wouldRebaseConflict]. Key is path.
  final Map<String, bool> wouldRebaseConflicts = {};

  /// Result for [merge]. Key is path.
  final Map<String, MergeResult> mergeResults = {};

  /// Result for [rebase]. Key is path.
  final Map<String, MergeResult> rebaseResults = {};

  /// Result for [pull]. Key is path.
  final Map<String, MergeResult> pullResults = {};

  /// Result for [pullRebase]. Key is path.
  final Map<String, MergeResult> pullRebaseResults = {};

  /// Tracks calls to [pull].
  final List<String> pullCalls = [];

  /// Tracks calls to [pullRebase].
  final List<String> pullRebaseCalls = [];

  /// If set, [pull] will throw this exception.
  GitException? pullError;

  /// If set, [pullRebase] will throw this exception.
  GitException? pullRebaseError;

  @override
  Future<MergeResult> pull(String path) async {
    pullCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
    if (pullError != null) throw pullError!;
    return pullResults[path] ??
        const MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.merge,
        );
  }

  @override
  Future<MergeResult> pullRebase(String path) async {
    pullRebaseCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
    if (pullRebaseError != null) throw pullRebaseError!;
    return pullRebaseResults[path] ??
        const MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.rebase,
        );
  }

  /// Tracks calls to [mergeAbort].
  final List<String> mergeAbortCalls = [];

  /// Tracks calls to [rebaseAbort].
  final List<String> rebaseAbortCalls = [];

  /// Tracks calls to [merge] with (path, targetBranch).
  final List<(String, String)> mergeCalls = [];

  /// Tracks calls to [rebase] with (path, targetBranch).
  final List<(String, String)> rebaseCalls = [];

  /// If set, [merge] will throw this exception.
  GitException? mergeError;

  /// If set, [rebase] will throw this exception.
  GitException? rebaseError;

  @override
  Future<bool> wouldMergeConflict(String path, String targetBranch) async {
    await _maybeDelay();
    _maybeThrow();
    return wouldConflict[path] ?? false;
  }

  @override
  Future<bool> wouldRebaseConflict(
    String path,
    String targetBranch,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    return wouldRebaseConflicts[path] ?? false;
  }

  @override
  Future<MergeResult> merge(String path, String targetBranch) async {
    mergeCalls.add((path, targetBranch));
    await _maybeDelay();
    _maybeThrow();
    if (mergeError != null) throw mergeError!;
    return mergeResults[path] ??
        const MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.merge,
        );
  }

  @override
  Future<MergeResult> rebase(String path, String targetBranch) async {
    rebaseCalls.add((path, targetBranch));
    await _maybeDelay();
    _maybeThrow();
    if (rebaseError != null) throw rebaseError!;
    return rebaseResults[path] ??
        const MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.rebase,
        );
  }

  @override
  Future<void> mergeAbort(String path) async {
    mergeAbortCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
  }

  @override
  Future<void> rebaseAbort(String path) async {
    rebaseAbortCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
  }

  /// Calls to [mergeContinue].
  final List<String> mergeContinueCalls = [];

  /// Calls to [rebaseContinue].
  final List<String> rebaseContinueCalls = [];

  @override
  Future<void> mergeContinue(String path) async {
    mergeContinueCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
  }

  @override
  Future<void> rebaseContinue(String path) async {
    rebaseContinueCalls.add(path);
    await _maybeDelay();
    _maybeThrow();
  }

  /// Map of path -> conflict operation type for [getConflictOperation].
  final Map<String, MergeOperationType> conflictOperations = {};

  @override
  Future<MergeOperationType?> getConflictOperation(
    String path,
  ) async {
    await _maybeDelay();
    _maybeThrow();
    return conflictOperations[path];
  }

  /// Map of path -> directory git info for [analyzeDirectory].
  final Map<String, DirectoryGitInfo> directoryInfos = {};

  @override
  Future<DirectoryGitInfo> analyzeDirectory(String path) async {
    await _maybeDelay();
    _maybeThrow();

    if (directoryInfos.containsKey(path)) {
      return directoryInfos[path]!;
    }

    // Default: not a git repo
    return DirectoryGitInfo(
      analyzedPath: path,
      isInGitRepo: false,
      isLinkedWorktree: false,
      isAtWorktreeRoot: false,
    );
  }

  // =========================================================================
  // Push & Pull Request operations
  // =========================================================================

  /// Whether [isGhInstalled] returns true.
  bool ghInstalled = true;

  @override
  Future<bool> isGhInstalled() async {
    await _maybeDelay();
    return ghInstalled;
  }

  /// Tracks calls to [push] with (path, setUpstream).
  final List<({String path, bool setUpstream})> pushCalls = [];

  /// If set, [push] will throw this exception.
  GitException? pushError;

  @override
  Future<void> push(String path, {bool setUpstream = false}) async {
    pushCalls.add((path: path, setUpstream: setUpstream));
    await _maybeDelay();
    _maybeThrow();
    if (pushError != null) throw pushError!;
  }

  /// Tracks calls to [createPullRequest].
  final List<({String path, String title, String body, bool draft})>
      createPullRequestCalls = [];

  /// The URL to return from [createPullRequest].
  String createPullRequestResult =
      'https://github.com/owner/repo/pull/1';

  /// If set, [createPullRequest] will throw this exception.
  GitException? createPullRequestError;

  @override
  Future<String> createPullRequest({
    required String path,
    required String title,
    required String body,
    bool draft = false,
  }) async {
    createPullRequestCalls.add((
      path: path,
      title: title,
      body: body,
      draft: draft,
    ));
    await _maybeDelay();
    _maybeThrow();
    if (createPullRequestError != null) {
      throw createPullRequestError!;
    }
    return createPullRequestResult;
  }
}
