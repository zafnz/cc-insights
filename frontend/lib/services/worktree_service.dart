import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/project.dart';
import '../models/worktree.dart';
import 'git_service.dart';
import 'persistence_models.dart' as persistence;
import 'persistence_service.dart';

/// Exception thrown when worktree creation fails.
///
/// Contains a user-friendly message and optional actionable suggestions.
class WorktreeCreationException implements Exception {
  /// The error message describing what went wrong.
  final String message;

  /// Actionable suggestions to help resolve the issue.
  final List<String> suggestions;

  WorktreeCreationException(this.message, {this.suggestions = const []});

  @override
  String toString() => message;
}

/// Service for creating and managing git worktrees.
///
/// Encapsulates validation, creation, and persistence logic for worktrees.
/// Accepts optional [GitService] and [PersistenceService] for testability.
class WorktreeService {
  final GitService _gitService;
  final PersistenceService _persistenceService;

  /// Creates a [WorktreeService] with optional dependency injection.
  ///
  /// If not provided, uses [RealGitService] and [PersistenceService].
  WorktreeService({
    GitService? gitService,
    PersistenceService? persistenceService,
  })  : _gitService = gitService ?? const RealGitService(),
        _persistenceService = persistenceService ?? PersistenceService();

  /// Creates a new worktree and persists it.
  ///
  /// Returns the created [WorktreeState] on success.
  /// Throws [WorktreeCreationException] on failure with actionable message.
  ///
  /// Parameters:
  /// - [project]: The project to add the worktree to.
  /// - [branch]: The branch name (will be sanitized).
  /// - [worktreeRoot]: The parent directory for the worktree.
  ///
  /// The full worktree path will be: `{worktreeRoot}/cci/{sanitizedBranch}`
  Future<WorktreeState> createWorktree({
    required ProjectState project,
    required String branch,
    required String worktreeRoot,
  }) async {
    final repoRoot = project.data.repoRoot;

    // 1. Validate worktree root is outside project repo
    if (_isPathInsideRepo(worktreeRoot, repoRoot)) {
      throw WorktreeCreationException(
        'Worktree directory cannot be inside the project repository.',
        suggestions: ['Choose a location outside of $repoRoot'],
      );
    }

    // 2. Sanitize branch name
    final sanitizedBranch = _sanitizeBranchName(branch);
    if (sanitizedBranch.isEmpty) {
      throw WorktreeCreationException(
        'Invalid branch name. Please enter a valid branch name.',
      );
    }

    // 3. Check if branch exists and if it's already a worktree
    final branchExists = await _gitService.branchExists(
      repoRoot,
      sanitizedBranch,
    );
    final worktrees = await _gitService.discoverWorktrees(repoRoot);

    // Find if branch is already a worktree
    WorktreeInfo? existingWorktree;
    for (final wt in worktrees) {
      if (wt.branch == sanitizedBranch) {
        existingWorktree = wt;
        break;
      }
    }

    if (existingWorktree != null) {
      throw WorktreeCreationException(
        'Branch "$sanitizedBranch" is already a worktree at: '
        '${existingWorktree.path}',
        suggestions: [
          'Select the existing worktree from the sidebar',
          'Choose a different branch name',
        ],
      );
    }

    // 4. Construct the full worktree path
    final worktreePath = path.join(worktreeRoot, 'cci', sanitizedBranch);

    // 5. Ensure parent directory exists
    final parentDir = Directory(path.dirname(worktreePath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 6. Create the git worktree
    try {
      await _gitService.createWorktree(
        repoRoot: repoRoot,
        worktreePath: worktreePath,
        branch: sanitizedBranch,
        newBranch: !branchExists,
      );
    } on GitException catch (e) {
      throw WorktreeCreationException(
        'Failed to create worktree: ${e.message}',
        suggestions: _suggestionsForGitError(e),
      );
    }

    // 7. Get git status for the new worktree
    final status = await _gitService.getStatus(worktreePath);

    // 8. Create WorktreeData and WorktreeState
    final worktreeData = WorktreeData(
      worktreeRoot: worktreePath,
      isPrimary: false,
      branch: sanitizedBranch,
      uncommittedFiles: status.uncommittedFiles,
      stagedFiles: status.staged,
      commitsAhead: status.ahead,
      commitsBehind: status.behind,
      hasMergeConflict: status.hasConflicts,
    );
    final worktreeState = WorktreeState(worktreeData);

    // 9. Persist to projects.json
    await _persistWorktree(project, worktreeState);

    // 10. Return WorktreeState
    return worktreeState;
  }

  /// Sanitizes a branch name for git.
  ///
  /// - Trims whitespace
  /// - Replaces spaces with hyphens
  /// - Removes invalid characters (keeps word chars, hyphens, slashes)
  /// - Removes leading/trailing hyphens
  /// - Collapses consecutive dots and slashes
  String _sanitizeBranchName(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'\s+'), '-') // spaces -> hyphens
        .replaceAll(RegExp(r'[^\w\-/]'), '') // remove invalid chars
        .replaceAll(RegExp(r'^-+|-+$'), '') // trim leading/trailing hyphens
        .replaceAll(RegExp(r'\.\.+'), '.') // collapse consecutive dots
        .replaceAll(RegExp(r'//+'), '/'); // collapse consecutive slashes
  }

  /// Checks if a path is inside a repository root.
  ///
  /// Normalizes both paths to absolute and checks if [worktreePath] starts
  /// with [repoRoot].
  bool _isPathInsideRepo(String worktreePath, String repoRoot) {
    final normalizedWorktree = path.normalize(path.absolute(worktreePath));
    final normalizedRepo = path.normalize(path.absolute(repoRoot));

    // Check if worktree path starts with repo root
    // Also ensure we're checking directory boundaries (not just string prefix)
    if (normalizedWorktree == normalizedRepo) {
      return true;
    }

    // Add trailing separator to avoid false positives like
    // /foo/bar matching /foo/barbaz
    final repoWithSep = normalizedRepo.endsWith(path.separator)
        ? normalizedRepo
        : '$normalizedRepo${path.separator}';

    return normalizedWorktree.startsWith(repoWithSep);
  }

  /// Returns actionable suggestions based on a git error.
  List<String> _suggestionsForGitError(GitException e) {
    final stderr = e.stderr?.toLowerCase() ?? '';

    if (stderr.contains('already exists')) {
      return [
        'The worktree directory already exists',
        'Choose a different branch name or delete the existing directory',
      ];
    }

    if (stderr.contains('is already checked out')) {
      return [
        'This branch is checked out in another worktree',
        'Use a different branch name',
      ];
    }

    if (stderr.contains('invalid reference')) {
      return [
        'The branch name is not valid',
        'Check the branch name and try again',
      ];
    }

    if (stderr.contains('permission denied')) {
      return [
        'Permission denied when creating worktree',
        'Check directory permissions',
      ];
    }

    return ['Check the git error message above for details'];
  }

  /// Persists a new worktree to projects.json.
  Future<void> _persistWorktree(
    ProjectState project,
    WorktreeState worktree,
  ) async {
    final index = await _persistenceService.loadProjectsIndex();
    final projectInfo = index.projects[project.data.repoRoot];

    if (projectInfo == null) {
      throw WorktreeCreationException(
        'Project not found in persistence. This is unexpected.',
      );
    }

    // Add the new worktree to the project
    final updatedWorktrees = Map<String, persistence.WorktreeInfo>.from(
      projectInfo.worktrees,
    );
    updatedWorktrees[worktree.data.worktreeRoot] = persistence.WorktreeInfo
        .linked(
      name: worktree.data.branch,
    );

    final updatedProjectInfo = projectInfo.copyWith(
      worktrees: updatedWorktrees,
    );
    final updatedProjects = Map<String, persistence.ProjectInfo>.from(
      index.projects,
    );
    updatedProjects[project.data.repoRoot] = updatedProjectInfo;

    await _persistenceService.saveProjectsIndex(
      index.copyWith(projects: updatedProjects),
    );
  }
}
