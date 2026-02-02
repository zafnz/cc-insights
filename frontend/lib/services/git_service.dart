import 'dart:async';
import 'dart:io';

/// Result of a git status check for a worktree.
class GitStatus {
  /// Number of files with unstaged changes (modified, deleted).
  final int unstaged;

  /// Number of files staged for commit.
  final int staged;

  /// Number of untracked files.
  final int untracked;

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
    this.ahead = 0,
    this.behind = 0,
    this.hasConflicts = false,
  });

  /// Total uncommitted files (unstaged + untracked).
  int get uncommittedFiles => unstaged + untracked;

  @override
  String toString() =>
      'GitStatus(unstaged: $unstaged, staged: $staged, untracked: $untracked, '
      'ahead: $ahead, behind: $behind, hasConflicts: $hasConflicts)';
}

/// Information about a discovered worktree.
class WorktreeInfo {
  /// Absolute path to the worktree root.
  final String path;

  /// Whether this is the primary (main) worktree.
  final bool isPrimary;

  /// Current branch name, or null if in detached HEAD state.
  final String? branch;

  const WorktreeInfo({
    required this.path,
    required this.isPrimary,
    this.branch,
  });

  @override
  String toString() =>
      'WorktreeInfo(path: $path, isPrimary: $isPrimary, branch: $branch)';
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

  /// Gets a list of all changed files (staged, unstaged, untracked).
  ///
  /// Returns a list of [GitFileChange] with file paths and statuses.
  /// Throws [GitException] if [path] is not a git repository.
  Future<List<GitFileChange>> getChangedFiles(String path);

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
  }) async {
    final args = ['worktree', 'add'];
    if (newBranch) {
      args.addAll(['-b', branch, worktreePath]);
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
  Future<List<GitFileChange>> getChangedFiles(String path) async {
    final output = await _runGit(
      ['status', '--porcelain=v2'],
      workingDirectory: path,
    );
    return GitChangedFilesParser.parse(output);
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
  static List<WorktreeInfo> parse(String output, String primaryPath) {
    final worktrees = <WorktreeInfo>[];
    String? currentPath;
    String? currentBranch;

    for (final line in output.split('\n')) {
      if (line.isEmpty) {
        // End of worktree entry
        if (currentPath != null) {
          worktrees.add(WorktreeInfo(
            path: currentPath,
            isPrimary: _pathsEqual(currentPath, primaryPath),
            branch: currentBranch,
          ));
        }
        currentPath = null;
        currentBranch = null;
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
      }
    }

    // Handle last entry if output doesn't end with blank line
    if (currentPath != null) {
      worktrees.add(WorktreeInfo(
        path: currentPath,
        isPrimary: _pathsEqual(currentPath, primaryPath),
        branch: currentBranch,
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
