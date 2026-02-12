import 'dart:async';
import 'dart:io';

import 'log_service.dart';

/// Result of a git status check for a worktree.
class GitStatus {
  /// Number of files with unstaged changes (modified, deleted).
  final int unstaged;

  /// Number of files staged for commit.
  final int staged;

  /// Number of untracked files.
  final int untracked;

  /// Number of distinct tracked files with any change (staged and/or
  /// unstaged). Each file is counted once even if it has both staged
  /// and unstaged modifications.
  final int changedEntries;

  /// Number of commits ahead of upstream.
  final int ahead;

  /// Number of commits behind upstream.
  final int behind;

  /// Whether there are unresolved merge conflicts.
  final bool hasConflicts;

  const GitStatus({
    this.unstaged = 0,
    this.staged = 0,
    this.untracked = 0,
    this.changedEntries = 0,
    this.ahead = 0,
    this.behind = 0,
    this.hasConflicts = false,
  });

  /// Total uncommitted files (changed tracked entries + untracked).
  int get uncommittedFiles => changedEntries + untracked;

  @override
  String toString() =>
      'GitStatus(unstaged: $unstaged, staged: $staged, untracked: $untracked, '
      'changedEntries: $changedEntries, ahead: $ahead, behind: $behind, '
      'hasConflicts: $hasConflicts)';
}

/// Information about a discovered worktree.
class WorktreeInfo {
  /// Absolute path to the worktree root.
  final String path;

  /// Whether this is the primary (main) worktree.
  final bool isPrimary;

  /// Current branch name, or null if in detached HEAD state.
  final String? branch;

  /// Whether this worktree is prunable (directory no longer exists on disk).
  final bool isPrunable;

  const WorktreeInfo({
    required this.path,
    required this.isPrimary,
    this.branch,
    this.isPrunable = false,
  });

  @override
  String toString() =>
      'WorktreeInfo(path: $path, isPrimary: $isPrimary, branch: $branch'
      '${isPrunable ? ', prunable' : ''})';
}

/// Status of a file in git.
enum GitFileStatus {
  added,
  modified,
  deleted,
  renamed,
  copied,
  untracked,
}

/// Represents a changed file in git status.
class GitFileChange {
  /// Path to the file relative to the worktree root.
  final String path;

  /// Status of the file.
  final GitFileStatus status;

  /// Whether the file is staged for commit.
  final bool isStaged;

  const GitFileChange({
    required this.path,
    required this.status,
    required this.isStaged,
  });

  @override
  String toString() => 'GitFileChange($path, $status, staged: $isStaged)';
}

/// Type of merge operation.
enum MergeOperationType { merge, rebase }

/// Result of a merge or rebase operation.
class MergeResult {
  /// Whether the operation resulted in conflicts.
  final bool hasConflicts;

  /// The type of operation performed.
  final MergeOperationType operation;

  /// Error message if the operation failed for a non-conflict reason.
  final String? error;

  const MergeResult({
    required this.hasConflicts,
    required this.operation,
    this.error,
  });
}

/// Exception thrown when a git operation fails.
class GitException implements Exception {
  final String message;
  final String? command;
  final int? exitCode;
  final String? stderr;

  const GitException(
    this.message, {
    this.command,
    this.exitCode,
    this.stderr,
  });

  @override
  String toString() {
    final buffer = StringBuffer('GitException: $message');
    if (command != null) buffer.write(' (command: $command)');
    if (exitCode != null) buffer.write(' (exit: $exitCode)');
    if (stderr != null && stderr!.isNotEmpty) buffer.write('\n$stderr');
    return buffer.toString();
  }
}

/// Abstract interface for git operations.
///
/// Use [RealGitService] for production and [FakeGitService] for testing.
abstract class GitService {
  /// Default timeout for git operations.
  static const defaultTimeout = Duration(seconds: 10);

  /// Gets the git version string.
  ///
  /// Returns the version string (e.g., "2.39.0") or throws [GitException].
  Future<String> getVersion();

  /// Gets the current branch name for a worktree.
  ///
  /// Returns null if in detached HEAD state.
  /// Throws [GitException] if [path] is not a git repository.
  Future<String?> getCurrentBranch(String path);

  /// Gets the git status for a worktree.
  ///
  /// Throws [GitException] if [path] is not a git repository.
  Future<GitStatus> getStatus(String path);

  /// Discovers all worktrees for a repository.
  ///
  /// [repoRoot] should be the path to the primary worktree (where .git lives).
  /// Returns a list of [WorktreeInfo] including the primary and all linked worktrees.
  /// Throws [GitException] if [repoRoot] is not a git repository.
  Future<List<WorktreeInfo>> discoverWorktrees(String repoRoot);

  /// Checks if a path is inside a git repository.
  ///
  /// Returns the repository root path if found, or null if not a git repo.
  Future<String?> findRepoRoot(String path);

  /// Lists all local branches in the repository.
  ///
  /// Returns a list of branch names (e.g., ["main", "develop", "feature/x"]).
  /// Throws [GitException] if [repoRoot] is not a git repository.
  Future<List<String>> listBranches(String repoRoot);

  /// Checks if a branch exists in the repository.
  ///
  /// Returns true if the branch exists, false otherwise.
  /// Throws [GitException] if [repoRoot] is not a git repository.
  Future<bool> branchExists(String repoRoot, String branchName);

  /// Creates a new worktree at the specified path.
  ///
  /// If [newBranch] is true, creates a new branch with the given name.
  /// If [newBranch] is false, checks out an existing branch.
  ///
  /// Throws [GitException] on failure.
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
    String? base,
  });

  /// Gets the upstream branch for the current branch.
  ///
  /// Returns the upstream branch name (e.g., "origin/main") or null if none.
  Future<String?> getUpstream(String path);

  /// Compares two branches and returns ahead/behind counts.
  ///
  /// Returns a record with (ahead, behind) counts where:
  /// - ahead = commits in [branch] not in [targetBranch]
  /// - behind = commits in [targetBranch] not in [branch]
  ///
  /// Returns null if comparison fails (e.g., branches don't exist).
  Future<({int ahead, int behind})?> getBranchComparison(
    String path,
    String branch,
    String targetBranch,
  );

  /// Detects the main branch for the repository.
  ///
  /// Checks for "main", then "master", then returns the first branch found.
  /// Returns null if no branches exist.
  Future<String?> getMainBranch(String repoRoot);

  /// Gets the remote main branch tracking ref for the repository.
  ///
  /// Tries `refs/remotes/origin/HEAD` first, then falls back to checking
  /// for `origin/main`, then `origin/master`.
  /// Returns the remote tracking ref name (e.g. "origin/main") or null
  /// if no remote main branch can be determined.
  Future<String?> getRemoteMainBranch(String repoRoot);

  /// Gets a list of all changed files (staged, unstaged, untracked).
  ///
  /// Returns a list of [GitFileChange] with file paths and statuses.
  /// Throws [GitException] if [path] is not a git repository.
  Future<List<GitFileChange>> getChangedFiles(String path);

  /// Gets the content of a file at a specific git ref (e.g., "HEAD").
  ///
  /// Runs `git show <ref>:<filePath>` to retrieve the file content.
  /// Returns null if the file doesn't exist at that ref.
  /// [worktreePath] is the working directory.
  /// [filePath] is relative to the worktree root.
  Future<String?> getFileAtRef(
    String worktreePath,
    String filePath,
    String ref,
  );

  /// Stages all changes in the worktree (git add -A).
  ///
  /// Throws [GitException] on failure.
  Future<void> stageAll(String path);

  /// Creates a commit with the given message.
  ///
  /// Throws [GitException] if commit fails (e.g., nothing to commit).
  Future<void> commit(String path, String message);

  /// Resets the index (unstages all files).
  ///
  /// Used to restore state on error. Does not modify working tree files.
  /// Throws [GitException] on failure.
  Future<void> resetIndex(String path);

  /// Stashes all uncommitted changes.
  ///
  /// Saves both staged and unstaged changes to the stash.
  /// Throws [GitException] on failure.
  Future<void> stash(String path);

  /// Fetches updates from the remote.
  ///
  /// Throws [GitException] on failure.
  Future<void> fetch(String path);

  /// Fetches updates from a specific remote.
  ///
  /// Throws [GitException] on failure.
  Future<void> fetchRemote(String path, String remote);

  /// Checks if a branch has been merged into the target branch.
  ///
  /// Uses `git merge-base --is-ancestor` to determine if [branch] is an
  /// ancestor of [targetBranch]. Returns true if [branch] is fully merged
  /// into [targetBranch], false otherwise.
  ///
  /// [path] is the working directory for the git command.
  Future<bool> isBranchMerged(String path, String branch, String targetBranch);

  /// Removes a worktree.
  ///
  /// If [force] is true, uses `git worktree remove --force` which will
  /// remove the worktree even if it has uncommitted changes.
  ///
  /// Throws [GitException] on failure.
  Future<void> removeWorktree({
    required String repoRoot,
    required String worktreePath,
    bool force = false,
  });

  /// Deletes a local branch.
  ///
  /// Uses `git branch -d` for safe delete (only works if merged) or
  /// `git branch -D` for force delete.
  ///
  /// Throws [GitException] on failure.
  Future<void> deleteBranch({
    required String repoRoot,
    required String branchName,
    bool force = false,
  });

  /// Gets commits on [branch] that aren't on [targetBranch] by patch-id.
  ///
  /// Uses `git cherry -v targetBranch branch` to find commits whose changes
  /// are not yet on the target branch. This handles squash merges where
  /// commit SHAs differ but the changes are the same.
  ///
  /// Returns a list of commit messages for commits NOT on target.
  /// Empty list means all commits are on target (or branch has no new commits).
  Future<List<String>> getUnmergedCommits(
    String path,
    String branch,
    String targetBranch,
  );

  /// Gets commits on current branch that aren't on [targetBranch].
  ///
  /// Uses `git log targetBranch..HEAD --oneline` to list commits.
  /// Returns a list of (sha, message) pairs.
  Future<List<({String sha, String message})>> getCommitsAhead(
    String path,
    String targetBranch,
  );

  /// Checks if merging [targetBranch] into the current branch would
  /// produce conflicts, without actually performing the merge.
  ///
  /// Performs `git merge --no-commit --no-ff targetBranch` then
  /// aborts via `git merge --abort` to restore the original state.
  /// Returns true if the dry-run detected conflicts.
  Future<bool> wouldMergeConflict(String path, String targetBranch);

  /// Merges [targetBranch] into the current branch.
  ///
  /// Returns a [MergeResult] indicating success or conflicts.
  /// If conflicts occur, the working tree is left in a conflicted state
  /// for the user or Claude to resolve.
  Future<MergeResult> merge(String path, String targetBranch);

  /// Rebases the current branch onto [targetBranch].
  ///
  /// Returns a [MergeResult] indicating success or conflicts.
  /// If conflicts occur, the rebase is paused for the user or Claude
  /// to resolve.
  Future<MergeResult> rebase(String path, String targetBranch);

  /// Pulls from the remote (git pull).
  ///
  /// Returns a [MergeResult] with [MergeOperationType.merge] indicating
  /// success or conflicts. If conflicts occur, the working tree is left
  /// in a conflicted state for the user or Claude to resolve.
  Future<MergeResult> pull(String path);

  /// Pulls from the remote with rebase (git pull --rebase).
  ///
  /// Returns a [MergeResult] with [MergeOperationType.rebase] indicating
  /// success or conflicts. If conflicts occur, the rebase is paused for
  /// the user or Claude to resolve.
  Future<MergeResult> pullRebase(String path);

  /// Aborts a merge in progress.
  ///
  /// Throws [GitException] on failure.
  Future<void> mergeAbort(String path);

  /// Aborts a rebase in progress.
  ///
  /// Throws [GitException] on failure.
  Future<void> rebaseAbort(String path);

  /// Continues a merge in progress (after conflicts have been resolved).
  ///
  /// Throws [GitException] on failure.
  Future<void> mergeContinue(String path);

  /// Continues a rebase in progress (after conflicts have been resolved).
  ///
  /// Throws [GitException] on failure.
  Future<void> rebaseContinue(String path);

  /// Detects which type of conflict operation is in progress.
  ///
  /// Returns [MergeOperationType.merge] if a merge is in progress,
  /// [MergeOperationType.rebase] if a rebase is in progress, or null
  /// if no operation is in progress.
  Future<MergeOperationType?> getConflictOperation(String path);

  /// Analyzes a directory to determine its git repository status.
  ///
  /// Returns a [DirectoryGitInfo] containing:
  /// - Whether the directory is inside a git repository
  /// - The repository root (primary worktree)
  /// - Whether the directory is a linked worktree
  /// - Whether the directory is at the top of its worktree
  ///
  /// Uses `git rev-parse --git-dir --git-common-dir --show-toplevel --show-prefix`
  /// to determine the relationship between the directory and any git repo.
  Future<DirectoryGitInfo> analyzeDirectory(String path);

  /// Checks if the GitHub CLI (`gh`) is installed and available.
  ///
  /// Returns true if `gh --version` runs successfully.
  Future<bool> isGhInstalled();

  /// Pushes the current branch to the remote.
  ///
  /// If [setUpstream] is true, uses `git push -u origin <branch>`.
  /// Otherwise uses plain `git push`.
  /// Throws [GitException] on failure.
  Future<void> push(String path, {bool setUpstream = false});

  /// Creates a pull request using the GitHub CLI (`gh`).
  ///
  /// Requires `gh` to be installed and authenticated.
  /// [path] is the working directory.
  /// [title] is the PR title.
  /// [body] is the PR description/body.
  /// If [draft] is true, creates a draft PR.
  ///
  /// Returns the URL of the created pull request.
  /// Throws [GitException] if `gh` is not installed or the command fails.
  Future<String> createPullRequest({
    required String path,
    required String title,
    required String body,
    bool draft = false,
  });

  /// Prunes stale worktree entries whose directories no longer exist on disk.
  ///
  /// Runs `git worktree prune` to clean up the worktree list.
  /// Throws [GitException] on failure.
  Future<void> pruneWorktrees(String repoRoot);
}

/// Result of analyzing a directory's git repository status.
class DirectoryGitInfo {
  /// The path that was analyzed.
  final String analyzedPath;

  /// Whether the path is inside a git repository.
  final bool isInGitRepo;

  /// The root of the current worktree (where `git status` operates).
  /// Null if not in a git repo.
  final String? worktreeRoot;

  /// The root of the primary worktree (where .git directory lives).
  /// For primary worktrees, this equals [worktreeRoot].
  /// For linked worktrees, this is the parent repository root.
  /// Null if not in a git repo.
  final String? repoRoot;

  /// Whether this is a linked worktree (not the primary).
  final bool isLinkedWorktree;

  /// Whether the analyzed path is at the worktree root.
  /// False if inside a subdirectory of the worktree.
  final bool isAtWorktreeRoot;

  /// The path prefix within the worktree (empty string if at root).
  final String prefix;

  const DirectoryGitInfo({
    required this.analyzedPath,
    required this.isInGitRepo,
    this.worktreeRoot,
    this.repoRoot,
    required this.isLinkedWorktree,
    required this.isAtWorktreeRoot,
    this.prefix = '',
  });

  /// Convenient check: is this the ideal case (primary worktree at root)?
  bool get isPrimaryWorktreeRoot =>
      isInGitRepo && !isLinkedWorktree && isAtWorktreeRoot;

  @override
  String toString() => 'DirectoryGitInfo('
      'analyzedPath: $analyzedPath, '
      'isInGitRepo: $isInGitRepo, '
      'worktreeRoot: $worktreeRoot, '
      'repoRoot: $repoRoot, '
      'isLinkedWorktree: $isLinkedWorktree, '
      'isAtWorktreeRoot: $isAtWorktreeRoot, '
      'prefix: $prefix)';
}

/// Real implementation of [GitService] that spawns git processes.
class RealGitService implements GitService {
  final Duration timeout;

  const RealGitService({this.timeout = GitService.defaultTimeout});

  /// Runs a git command and returns stdout.
  ///
  /// Throws [GitException] on non-zero exit, timeout, or process failure.
  Future<String> _runGit(
    List<String> args, {
    String? workingDirectory,
  }) async {
    final command = 'git ${args.join(' ')}';
    LogService.instance.trace('Git', command, meta: {'cwd': workingDirectory ?? '.'});
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
      ).timeout(timeout);

      if (result.exitCode != 0) {
        throw GitException(
          'Git command failed',
          command: command,
          exitCode: result.exitCode,
          stderr: result.stderr as String,
        );
      }

      return result.stdout as String;
    } on TimeoutException {
      throw GitException('Git command timed out after $timeout',
          command: command);
    } on ProcessException catch (e) {
      throw GitException(
        'Failed to run git: ${e.message}',
        command: command,
      );
    }
  }

  @override
  Future<String> getVersion() async {
    final output = await _runGit(['--version']);
    // Parse "git version 2.39.0" -> "2.39.0"
    final match = RegExp(r'git version (\S+)').firstMatch(output);
    if (match == null) {
      throw GitException('Could not parse git version from: $output');
    }
    return match.group(1)!;
  }

  @override
  Future<String?> getCurrentBranch(String path) async {
    try {
      final output = await _runGit(
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: path,
      );
      final branch = output.trim();
      // "HEAD" means detached HEAD state
      return branch == 'HEAD' ? null : branch;
    } on GitException {
      rethrow;
    }
  }

  @override
  Future<GitStatus> getStatus(String path) async {
    // Use porcelain v2 for machine-readable output
    final output = await _runGit(
      ['status', '--porcelain=v2', '--branch'],
      workingDirectory: path,
    );

    return GitStatusParser.parse(output);
  }

  @override
  Future<List<WorktreeInfo>> discoverWorktrees(String repoRoot) async {
    final output = await _runGit(
      ['worktree', 'list', '--porcelain'],
      workingDirectory: repoRoot,
    );

    return GitWorktreeParser.parse(output, repoRoot);
  }

  @override
  Future<String?> findRepoRoot(String path) async {
    try {
      final output = await _runGit(
        ['rev-parse', '--show-toplevel'],
        workingDirectory: path,
      );
      return output.trim();
    } on GitException {
      return null;
    }
  }

  @override
  Future<List<String>> listBranches(String repoRoot) async {
    final output = await _runGit(
      ['branch', '--format=%(refname:short)'],
      workingDirectory: repoRoot,
    );
    return output.split('\n').where((b) => b.isNotEmpty).toList();
  }

  @override
  Future<bool> branchExists(String repoRoot, String branchName) async {
    try {
      await _runGit(
        ['rev-parse', '--verify', 'refs/heads/$branchName'],
        workingDirectory: repoRoot,
      );
      return true;
    } on GitException {
      return false;
    }
  }

  @override
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
    String? base,
  }) async {
    // Use -c branch.autoSetupMerge=simple to prevent git from automatically
    // setting the upstream to the base ref (e.g. origin/main) when creating
    // a new branch from a remote tracking branch. Without this, `git push`
    // fails because the upstream name doesn't match the local branch name.
    final args = ['-c', 'branch.autoSetupMerge=simple', 'worktree', 'add'];
    if (newBranch) {
      args.addAll(['-b', branch, worktreePath]);
      if (base != null) {
        args.add(base);
      }
    } else {
      args.addAll([worktreePath, branch]);
    }
    await _runGit(args, workingDirectory: repoRoot);
  }

  @override
  Future<String?> getUpstream(String path) async {
    try {
      final output = await _runGit(
        ['rev-parse', '--abbrev-ref', '@{upstream}'],
        workingDirectory: path,
      );
      final upstream = output.trim();
      return upstream.isEmpty ? null : upstream;
    } on GitException {
      // No upstream configured
      return null;
    }
  }

  @override
  Future<({int ahead, int behind})?> getBranchComparison(
    String path,
    String branch,
    String targetBranch,
  ) async {
    try {
      final output = await _runGit(
        ['rev-list', '--left-right', '--count', '$branch...$targetBranch'],
        workingDirectory: path,
      );
      // Output format: "3\t2" (ahead\tbehind)
      final parts = output.trim().split('\t');
      if (parts.length == 2) {
        return (
          ahead: int.tryParse(parts[0]) ?? 0,
          behind: int.tryParse(parts[1]) ?? 0,
        );
      }
      return null;
    } on GitException {
      return null;
    }
  }

  @override
  Future<String?> getMainBranch(String repoRoot) async {
    // First try to get the default branch from origin
    try {
      final output = await _runGit(
        ['symbolic-ref', 'refs/remotes/origin/HEAD'],
        workingDirectory: repoRoot,
      );
      // Output: refs/remotes/origin/main
      final ref = output.trim();
      if (ref.startsWith('refs/remotes/origin/')) {
        return ref.substring('refs/remotes/origin/'.length);
      }
    } on GitException {
      // Fall through to manual detection
    }

    // Check for common main branch names
    final branches = await listBranches(repoRoot);
    if (branches.contains('main')) return 'main';
    if (branches.contains('master')) return 'master';
    return branches.isNotEmpty ? branches.first : null;
  }

  @override
  Future<String?> getRemoteMainBranch(String repoRoot) async {
    // Try symbolic-ref first (most reliable)
    try {
      final output = await _runGit(
        ['symbolic-ref', 'refs/remotes/origin/HEAD'],
        workingDirectory: repoRoot,
      );
      final ref = output.trim();
      // Output: refs/remotes/origin/main → return "origin/main"
      if (ref.startsWith('refs/remotes/')) {
        return ref.substring('refs/remotes/'.length);
      }
    } on GitException {
      // Fall through
    }

    // Try origin/main
    try {
      await _runGit(
        ['rev-parse', '--verify', 'refs/remotes/origin/main'],
        workingDirectory: repoRoot,
      );
      return 'origin/main';
    } on GitException {
      // Fall through
    }

    // Try origin/master
    try {
      await _runGit(
        ['rev-parse', '--verify', 'refs/remotes/origin/master'],
        workingDirectory: repoRoot,
      );
      return 'origin/master';
    } on GitException {
      return null;
    }
  }

  @override
  Future<List<GitFileChange>> getChangedFiles(String path) async {
    final output = await _runGit(
      ['status', '--porcelain=v2'],
      workingDirectory: path,
    );
    return GitChangedFilesParser.parse(output);
  }

  @override
  Future<String?> getFileAtRef(
    String worktreePath,
    String filePath,
    String ref,
  ) async {
    try {
      final output = await _runGit(
        ['show', '$ref:$filePath'],
        workingDirectory: worktreePath,
      );
      return output;
    } on GitException {
      return null;
    }
  }

  @override
  Future<void> stageAll(String path) async {
    await _runGit(['add', '-A'], workingDirectory: path);
  }

  @override
  Future<void> commit(String path, String message) async {
    // Use -m for the commit message
    // For multiline messages, git handles newlines in the string properly
    await _runGit(['commit', '-m', message], workingDirectory: path);
  }

  @override
  Future<void> resetIndex(String path) async {
    await _runGit(['reset', 'HEAD'], workingDirectory: path);
  }

  @override
  Future<void> stash(String path) async {
    await _runGit(['stash'], workingDirectory: path);
  }

  @override
  Future<void> fetch(String path) async {
    await _runGit(['fetch'], workingDirectory: path);
  }

  @override
  Future<void> fetchRemote(String path, String remote) async {
    await _runGit(['fetch', remote], workingDirectory: path);
  }

  @override
  Future<bool> isBranchMerged(
    String path,
    String branch,
    String targetBranch,
  ) async {
    try {
      // git merge-base --is-ancestor returns 0 if branch is ancestor of target
      await _runGit(
        ['merge-base', '--is-ancestor', branch, targetBranch],
        workingDirectory: path,
      );
      return true;
    } on GitException catch (e) {
      // Exit code 1 means branch is NOT an ancestor (not merged)
      if (e.exitCode == 1) {
        return false;
      }
      // Other errors should be rethrown
      rethrow;
    }
  }

  @override
  Future<void> removeWorktree({
    required String repoRoot,
    required String worktreePath,
    bool force = false,
  }) async {
    final args = ['worktree', 'remove'];
    if (force) {
      args.add('--force');
    }
    args.add(worktreePath);
    await _runGit(args, workingDirectory: repoRoot);
  }

  @override
  Future<void> deleteBranch({
    required String repoRoot,
    required String branchName,
    bool force = false,
  }) async {
    final args = ['branch', force ? '-D' : '-d', branchName];
    await _runGit(args, workingDirectory: repoRoot);
  }

  @override
  Future<List<String>> getUnmergedCommits(
    String path,
    String branch,
    String targetBranch,
  ) async {
    try {
      // git cherry -v marks commits with '-' if already on target, '+' if not
      final output = await _runGit(
        ['cherry', '-v', targetBranch, branch],
        workingDirectory: path,
      );

      final unmerged = <String>[];
      for (final line in output.split('\n')) {
        if (line.isEmpty) continue;
        // Format: "+ sha message" or "- sha message"
        if (line.startsWith('+ ')) {
          // This commit is NOT on target branch
          // Extract message (skip "+ sha ")
          final parts = line.substring(2).split(' ');
          if (parts.length > 1) {
            unmerged.add(parts.sublist(1).join(' '));
          }
        }
        // Lines starting with "- " are already on target, skip them
      }
      return unmerged;
    } on GitException {
      // If cherry fails, return empty (assume merged)
      return [];
    }
  }

  @override
  Future<List<({String sha, String message})>> getCommitsAhead(
    String path,
    String targetBranch,
  ) async {
    try {
      final output = await _runGit(
        ['log', '$targetBranch..HEAD', '--oneline'],
        workingDirectory: path,
      );

      final commits = <({String sha, String message})>[];
      for (final line in output.split('\n')) {
        if (line.isEmpty) continue;
        // Format: "sha message"
        final spaceIndex = line.indexOf(' ');
        if (spaceIndex > 0) {
          commits.add((
            sha: line.substring(0, spaceIndex),
            message: line.substring(spaceIndex + 1),
          ));
        }
      }
      return commits;
    } on GitException {
      return [];
    }
  }

  /// Longer timeout for merge/rebase operations on large repos.
  static const _mergeTimeout = Duration(seconds: 30);

  @override
  Future<bool> wouldMergeConflict(
    String path,
    String targetBranch,
  ) async {
    try {
      await _runGit(
        ['merge', '--no-commit', '--no-ff', targetBranch],
        workingDirectory: path,
      );
      // Merge succeeded without conflicts - abort to restore state
      try {
        await _runGit(['merge', '--abort'], workingDirectory: path);
      } catch (_) {
        // If abort fails, the merge was clean so reset instead
        await _runGit(['reset', '--merge'], workingDirectory: path);
      }
      return false;
    } on GitException catch (e) {
      // Merge failed - conflicts detected. Abort to restore state.
      try {
        await _runGit(['merge', '--abort'], workingDirectory: path);
      } catch (_) {
        // Abort may also fail if in a weird state, ignore
      }
      if (e.exitCode == 1 ||
          (e.stderr?.contains('CONFLICT') ?? false) ||
          (e.stderr?.contains('Automatic merge failed') ?? false)) {
        return true;
      }
      rethrow;
    }
  }

  @override
  Future<MergeResult> merge(String path, String targetBranch) async {
    try {
      await Process.run(
        'git',
        ['merge', targetBranch],
        workingDirectory: path,
      ).timeout(_mergeTimeout);
      // Check if there are conflicts by looking at status
      final status = await getStatus(path);
      if (status.hasConflicts) {
        return const MergeResult(
          hasConflicts: true,
          operation: MergeOperationType.merge,
        );
      }
      return const MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
      );
    } on TimeoutException {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
        error: 'Merge timed out after $_mergeTimeout',
      );
    } on ProcessException catch (e) {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
        error: 'Failed to run git: ${e.message}',
      );
    }
  }

  @override
  Future<MergeResult> rebase(String path, String targetBranch) async {
    try {
      final result = await Process.run(
        'git',
        ['rebase', targetBranch],
        workingDirectory: path,
      ).timeout(_mergeTimeout);

      if (result.exitCode != 0) {
        final stderr = result.stderr as String;
        if (stderr.contains('CONFLICT') ||
            stderr.contains('could not apply')) {
          return const MergeResult(
            hasConflicts: true,
            operation: MergeOperationType.rebase,
          );
        }
        return MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.rebase,
          error: stderr.isNotEmpty ? stderr : 'Rebase failed',
        );
      }
      return const MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
      );
    } on TimeoutException {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
        error: 'Rebase timed out after $_mergeTimeout',
      );
    } on ProcessException catch (e) {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
        error: 'Failed to run git: ${e.message}',
      );
    }
  }

  @override
  Future<MergeResult> pull(String path) async {
    try {
      await Process.run(
        'git',
        ['pull'],
        workingDirectory: path,
      ).timeout(_mergeTimeout);
      // Check if there are conflicts by looking at status
      final status = await getStatus(path);
      if (status.hasConflicts) {
        return const MergeResult(
          hasConflicts: true,
          operation: MergeOperationType.merge,
        );
      }
      return const MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
      );
    } on TimeoutException {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
        error: 'Pull timed out after $_mergeTimeout',
      );
    } on ProcessException catch (e) {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.merge,
        error: 'Failed to run git: ${e.message}',
      );
    }
  }

  @override
  Future<MergeResult> pullRebase(String path) async {
    try {
      final result = await Process.run(
        'git',
        ['pull', '--rebase'],
        workingDirectory: path,
      ).timeout(_mergeTimeout);

      if (result.exitCode != 0) {
        final stderr = result.stderr as String;
        if (stderr.contains('CONFLICT') ||
            stderr.contains('could not apply')) {
          return const MergeResult(
            hasConflicts: true,
            operation: MergeOperationType.rebase,
          );
        }
        return MergeResult(
          hasConflicts: false,
          operation: MergeOperationType.rebase,
          error: stderr.isNotEmpty ? stderr : 'Pull rebase failed',
        );
      }
      return const MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
      );
    } on TimeoutException {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
        error: 'Pull rebase timed out after $_mergeTimeout',
      );
    } on ProcessException catch (e) {
      return MergeResult(
        hasConflicts: false,
        operation: MergeOperationType.rebase,
        error: 'Failed to run git: ${e.message}',
      );
    }
  }

  @override
  Future<void> mergeAbort(String path) async {
    await _runGit(['merge', '--abort'], workingDirectory: path);
  }

  @override
  Future<void> rebaseAbort(String path) async {
    await _runGit(['rebase', '--abort'], workingDirectory: path);
  }

  @override
  Future<void> mergeContinue(String path) async {
    await _runGit(
      ['-c', 'core.editor=true', 'merge', '--continue'],
      workingDirectory: path,
    );
  }

  @override
  Future<void> rebaseContinue(String path) async {
    await _runGit(
      ['-c', 'core.editor=true', 'rebase', '--continue'],
      workingDirectory: path,
    );
  }

  @override
  Future<MergeOperationType?> getConflictOperation(
    String path,
  ) async {
    // Check for rebase first (more specific).
    // git rebase uses .git/rebase-merge or .git/rebase-apply.
    try {
      final gitDir = await _runGit(
        ['rev-parse', '--git-dir'],
        workingDirectory: path,
      );
      final dir = gitDir.trim();
      final rebaseMerge = Directory('$dir/rebase-merge');
      final rebaseApply = Directory('$dir/rebase-apply');
      if (rebaseMerge.existsSync() || rebaseApply.existsSync()) {
        return MergeOperationType.rebase;
      }
      final mergeHead = File('$dir/MERGE_HEAD');
      if (mergeHead.existsSync()) {
        return MergeOperationType.merge;
      }
    } catch (_) {
      // If we can't determine, return null.
    }
    return null;
  }

  @override
  Future<DirectoryGitInfo> analyzeDirectory(String path) async {
    const log = 'GitAnalyze';
    LogService.instance.info(log, 'Analyzing directory: $path');
    try {
      // Run git rev-parse with multiple queries in one call
      // This gives us: git-dir, git-common-dir, toplevel, and prefix
      final output = await _runGit(
        [
          'rev-parse',
          '--git-dir',
          '--git-common-dir',
          '--show-toplevel',
          '--show-prefix',
        ],
        workingDirectory: path,
      );

      final lines = output.split('\n');
      // Output format:
      // line 0: git-dir (e.g., ".git" or "/path/to/repo/.git/worktrees/branch")
      // line 1: git-common-dir (e.g., ".git" or "/path/to/repo/.git")
      // line 2: toplevel (e.g., "/path/to/worktree")
      // line 3: prefix (e.g., "" or "subdir/")

      final gitDir = lines.isNotEmpty ? lines[0].trim() : '';
      final gitCommonDir = lines.length > 1 ? lines[1].trim() : '';
      final toplevel = lines.length > 2 ? lines[2].trim() : '';
      final prefix = lines.length > 3 ? lines[3].trim() : '';

      LogService.instance.trace(log, 'git rev-parse output', meta: {
        'git-dir': gitDir,
        'git-common-dir': gitCommonDir,
        'toplevel': toplevel,
        'prefix': prefix,
        'line_count': lines.length,
      });

      // Determine if this is a linked worktree by checking if git-dir contains /worktrees/
      // For primary worktree: git-dir is ".git" or "/path/to/.git"
      // For linked worktree: git-dir is "/path/to/.git/worktrees/name"
      // Note: We can't just compare gitDir to gitCommonDir because git-common-dir
      // may be a relative path (e.g., "../../.git") when run from a subdirectory.
      final isLinked = gitDir.contains('/.git/worktrees/');

      // The repo root is the parent of the git-common-dir
      // We need to resolve git-common-dir to an absolute path
      String repoRoot;
      if (gitCommonDir == '.git') {
        repoRoot = toplevel;
      } else {
        // git-common-dir is an absolute path like "/path/to/repo/.git"
        // Strip the "/.git" suffix to get the repo root
        if (gitCommonDir.endsWith('/.git')) {
          repoRoot = gitCommonDir.substring(0, gitCommonDir.length - 5);
        } else {
          repoRoot = gitCommonDir;
        }
      }

      final result = DirectoryGitInfo(
        analyzedPath: path,
        isInGitRepo: true,
        worktreeRoot: toplevel,
        repoRoot: repoRoot,
        isLinkedWorktree: isLinked,
        isAtWorktreeRoot: prefix.isEmpty,
        prefix: prefix,
      );

      LogService.instance.info(log, 'Directory analysis complete', meta: {
        'isInGitRepo': true,
        'isLinkedWorktree': isLinked,
        'isAtWorktreeRoot': prefix.isEmpty,
        'isPrimaryWorktreeRoot': result.isPrimaryWorktreeRoot,
        'worktreeRoot': toplevel,
        'repoRoot': repoRoot,
      });

      return result;
    } on GitException catch (e) {
      // Not a git repository
      LogService.instance.warn(log, 'Not a git repository: $path', meta: {
        'error': e.message,
        'command': e.command,
        'exitCode': e.exitCode,
        'stderr': e.stderr,
      });
      return DirectoryGitInfo(
        analyzedPath: path,
        isInGitRepo: false,
        isLinkedWorktree: false,
        isAtWorktreeRoot: false,
      );
    }
  }

  /// Longer timeout for network operations (push, PR creation).
  static const _networkTimeout = Duration(seconds: 30);

  @override
  Future<bool> isGhInstalled() async {
    try {
      final result = await Process.run('gh', ['--version'])
          .timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<void> push(String path, {bool setUpstream = false}) async {
    final List<String> args;
    if (setUpstream) {
      final branch = await getCurrentBranch(path);
      if (branch == null) {
        throw const GitException('Cannot push: detached HEAD');
      }
      args = ['push', '-u', 'origin', branch];
    } else {
      // Check if the upstream branch name matches the local branch.
      // If not (e.g. local branch "feat-x" tracking "origin/main" from
      // worktree creation), plain `git push` fails. Fix by pushing with
      // -u to set the correct upstream.
      final branch = await getCurrentBranch(path);
      final upstream = await getUpstream(path);
      if (branch != null &&
          upstream != null &&
          !upstream.endsWith('/$branch')) {
        args = ['push', '-u', 'origin', branch];
      } else {
        args = ['push'];
      }
    }

    final command = 'git ${args.join(' ')}';
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: path,
      ).timeout(_networkTimeout);

      if (result.exitCode != 0) {
        throw GitException(
          'Push failed',
          command: command,
          exitCode: result.exitCode,
          stderr: result.stderr as String,
        );
      }
    } on TimeoutException {
      throw GitException(
        'Push timed out after $_networkTimeout',
        command: command,
      );
    } on ProcessException catch (e) {
      throw GitException(
        'Failed to run git: ${e.message}',
        command: command,
      );
    }
  }

  @override
  Future<String> createPullRequest({
    required String path,
    required String title,
    required String body,
    bool draft = false,
  }) async {
    final args = ['pr', 'create', '--title', title, '--body', body];
    if (draft) args.add('--draft');

    try {
      final result = await Process.run(
        'gh',
        args,
        workingDirectory: path,
      ).timeout(_networkTimeout);

      if (result.exitCode != 0) {
        throw GitException(
          'Failed to create pull request',
          command: 'gh ${args.join(' ')}',
          exitCode: result.exitCode,
          stderr: result.stderr as String,
        );
      }

      return (result.stdout as String).trim();
    } on TimeoutException {
      throw const GitException(
        'Pull request creation timed out',
        command: 'gh pr create',
      );
    } on ProcessException catch (e) {
      throw GitException(
        'GitHub CLI (gh) is not available: ${e.message}',
        command: 'gh pr create',
      );
    }
  }

  @override
  Future<void> pruneWorktrees(String repoRoot) async {
    await _runGit(['worktree', 'prune'], workingDirectory: repoRoot);
  }
}

// =============================================================================
// PARSERS - Pure functions for parsing git output
// =============================================================================

/// Parses `git status --porcelain=v2 --branch` output.
class GitStatusParser {
  /// Parses porcelain v2 status output into [GitStatus].
  static GitStatus parse(String output) {
    int staged = 0;
    int unstaged = 0;
    int untracked = 0;
    int changedEntries = 0;
    int ahead = 0;
    int behind = 0;
    bool hasConflicts = false;

    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;

      // Branch tracking info: # branch.ab +3 -2
      if (line.startsWith('# branch.ab ')) {
        final match = RegExp(r'\+(\d+) -(\d+)').firstMatch(line);
        if (match != null) {
          ahead = int.parse(match.group(1)!);
          behind = int.parse(match.group(2)!);
        }
        continue;
      }

      // Skip other header lines
      if (line.startsWith('#')) continue;

      // Untracked files: ? path
      if (line.startsWith('?')) {
        untracked++;
        continue;
      }

      // Ignored files: ! path
      if (line.startsWith('!')) continue;

      // Changed entries: 1 XY ... or 2 XY ... (renames)
      if (line.startsWith('1 ') || line.startsWith('2 ')) {
        changedEntries++;
        final xy = line.substring(2, 4);
        final x = xy[0]; // staged status
        final y = xy[1]; // unstaged status

        if (x != '.') staged++;
        if (y != '.') unstaged++;
        continue;
      }

      // Unmerged entries: u XY ...
      if (line.startsWith('u ')) {
        hasConflicts = true;
        continue;
      }
    }

    return GitStatus(
      staged: staged,
      unstaged: unstaged,
      untracked: untracked,
      changedEntries: changedEntries,
      ahead: ahead,
      behind: behind,
      hasConflicts: hasConflicts,
    );
  }
}

/// Parses `git worktree list --porcelain` output.
class GitWorktreeParser {
  /// Parses porcelain worktree list output into [WorktreeInfo] list.
  ///
  /// [primaryPath] is used to determine which worktree is primary.
  /// Detects `prunable` lines to set [WorktreeInfo.isPrunable].
  static List<WorktreeInfo> parse(String output, String primaryPath) {
    final worktrees = <WorktreeInfo>[];
    String? currentPath;
    String? currentBranch;
    bool currentPrunable = false;

    for (final line in output.split('\n')) {
      if (line.isEmpty) {
        // End of worktree entry
        if (currentPath != null) {
          worktrees.add(WorktreeInfo(
            path: currentPath,
            isPrimary: _pathsEqual(currentPath, primaryPath),
            branch: currentBranch,
            isPrunable: currentPrunable,
          ));
        }
        currentPath = null;
        currentBranch = null;
        currentPrunable = false;
        continue;
      }

      if (line.startsWith('worktree ')) {
        currentPath = line.substring('worktree '.length);
      } else if (line.startsWith('branch ')) {
        // Format: branch refs/heads/main
        final ref = line.substring('branch '.length);
        if (ref.startsWith('refs/heads/')) {
          currentBranch = ref.substring('refs/heads/'.length);
        } else {
          currentBranch = ref;
        }
      } else if (line == 'detached') {
        currentBranch = null;
      } else if (line.startsWith('prunable ')) {
        currentPrunable = true;
      }
    }

    // Handle last entry if output doesn't end with blank line
    if (currentPath != null) {
      worktrees.add(WorktreeInfo(
        path: currentPath,
        isPrimary: _pathsEqual(currentPath, primaryPath),
        branch: currentBranch,
        isPrunable: currentPrunable,
      ));
    }

    return worktrees;
  }

  /// Compare paths, normalizing trailing slashes.
  static bool _pathsEqual(String a, String b) {
    return a.replaceAll(RegExp(r'/$'), '') == b.replaceAll(RegExp(r'/$'), '');
  }
}

/// Parses `git status --porcelain=v2` output into [GitFileChange] list.
class GitChangedFilesParser {
  /// Parses porcelain v2 status output into a list of changed files.
  static List<GitFileChange> parse(String output) {
    final files = <GitFileChange>[];

    for (final line in output.split('\n')) {
      if (line.isEmpty) continue;

      // Skip header lines
      if (line.startsWith('#')) continue;

      // Untracked files: ? path
      if (line.startsWith('? ')) {
        final path = line.substring(2);
        files.add(GitFileChange(
          path: path,
          status: GitFileStatus.untracked,
          isStaged: false,
        ));
        continue;
      }

      // Ignored files: ! path - skip
      if (line.startsWith('!')) continue;

      // Changed entries: 1 XY sub mH mI mW hH hI path
      // Rename entries: 2 XY sub mH mI mW hH hI X<score> path\torigPath
      if (line.startsWith('1 ') || line.startsWith('2 ')) {
        final isRename = line.startsWith('2 ');
        final xy = line.substring(2, 4);
        final x = xy[0]; // staged status
        final y = xy[1]; // unstaged status

        // Extract path - it's the last field
        // For type 1: fields are space-separated, path is last
        // For type 2 (rename): path\torigPath at end
        String path;
        if (isRename) {
          // Format: 2 XY sub mH mI mW hH hI X<score> path\torigPath
          final tabIndex = line.indexOf('\t');
          if (tabIndex != -1) {
            // The new path is between last space before tab and tab
            final beforeTab = line.substring(0, tabIndex);
            final lastSpace = beforeTab.lastIndexOf(' ');
            path = beforeTab.substring(lastSpace + 1);
          } else {
            // Fallback: take everything after last space
            path = line.substring(line.lastIndexOf(' ') + 1);
          }
        } else {
          // Format: 1 XY sub mH mI mW hH hI path
          path = line.substring(line.lastIndexOf(' ') + 1);
        }

        // Determine status based on XY codes
        final status = _parseStatus(x, y, isRename);

        // A file can appear in both staged and unstaged if it has both types
        // of changes. We'll report the staged status if staged, else unstaged.
        if (x != '.') {
          files.add(GitFileChange(
            path: path,
            status: status,
            isStaged: true,
          ));
        }
        if (y != '.') {
          files.add(GitFileChange(
            path: path,
            status: _parseUnstagedStatus(y),
            isStaged: false,
          ));
        }
        continue;
      }

      // Unmerged entries: u XY sub m1 m2 m3 mW h1 h2 h3 path
      if (line.startsWith('u ')) {
        final path = line.substring(line.lastIndexOf(' ') + 1);
        files.add(GitFileChange(
          path: path,
          status: GitFileStatus.modified, // Conflict is a type of modification
          isStaged: false,
        ));
        continue;
      }
    }

    return files;
  }

  /// Parse staged status code to [GitFileStatus].
  static GitFileStatus _parseStatus(String x, String y, bool isRename) {
    if (isRename) return GitFileStatus.renamed;
    switch (x) {
      case 'A':
        return GitFileStatus.added;
      case 'M':
        return GitFileStatus.modified;
      case 'D':
        return GitFileStatus.deleted;
      case 'R':
        return GitFileStatus.renamed;
      case 'C':
        return GitFileStatus.copied;
      default:
        // Check unstaged status as fallback
        return _parseUnstagedStatus(y);
    }
  }

  /// Parse unstaged status code to [GitFileStatus].
  static GitFileStatus _parseUnstagedStatus(String y) {
    switch (y) {
      case 'M':
        return GitFileStatus.modified;
      case 'D':
        return GitFileStatus.deleted;
      case 'A':
        return GitFileStatus.added;
      default:
        return GitFileStatus.modified;
    }
  }
}
