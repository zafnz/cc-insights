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
