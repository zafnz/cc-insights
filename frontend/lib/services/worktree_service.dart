import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/project.dart';
import '../models/project_config.dart';
import '../models/worktree.dart';
import 'git_service.dart';
import 'log_service.dart';
import 'persistence_models.dart' as persistence;
import 'persistence_service.dart';
import 'project_config_service.dart';
import 'script_execution_service.dart';

/// Calculates the default worktree root directory for a project.
///
/// Checks for existing directories in this order:
/// 1. `{parent}/.{projectName}-wt/`
/// 2. `{parent}/.{projectName}-worktrees/`
/// 3. `{parent}/{projectName}-wt/`
/// 4. `{parent}/{projectName}-worktrees/`
///
/// If none exist, returns `{parent}/.{projectName}-wt` as the default.
///
/// For example, if [projectRoot] is `/my/project/folder/my-app`:
/// - Returns `/my/project/folder/.my-app-wt` if it exists
/// - Or `/my/project/folder/.my-app-worktrees` if it exists
/// - Or `/my/project/folder/my-app-wt` if it exists
/// - Or `/my/project/folder/my-app-worktrees` if it exists
/// - Otherwise returns `/my/project/folder/.my-app-wt` as default
Future<String> calculateDefaultWorktreeRoot(String projectRoot) async {
  final parentDir = path.dirname(projectRoot);
  final projectName = path.basename(projectRoot);

  // List of candidates in priority order
  final candidates = [
    path.join(parentDir, '.$projectName-wt'),
    path.join(parentDir, '.$projectName-worktrees'),
    path.join(parentDir, '$projectName-wt'),
    path.join(parentDir, '$projectName-worktrees'),
  ];

  // Check each candidate in order
  for (final candidate in candidates) {
    if (await Directory(candidate).exists()) {
      return candidate;
    }
  }

  // Default to first candidate if none exist
  return candidates.first;
}

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

/// Exception thrown when the user tries to create a worktree with a branch
/// name that already exists in git but is not currently checked out in any
/// worktree. This signals the UI to offer a recovery prompt.
class WorktreeBranchExistsException extends WorktreeCreationException {
  /// The sanitized branch name that already exists.
  final String branchName;

  WorktreeBranchExistsException(this.branchName)
      : super(
          'A branch named "$branchName" already exists.',
        );
}

/// Service for creating and managing git worktrees.
///
/// Encapsulates validation, creation, and persistence logic for worktrees.
/// Accepts optional [GitService] and [PersistenceService] for testability.
class WorktreeService {
  final GitService _gitService;
  final PersistenceService _persistenceService;
  final ProjectConfigService _configService;
  final ScriptExecutionService? _scriptService;

  /// Creates a [WorktreeService] with optional dependency injection.
  ///
  /// If not provided, uses [RealGitService] and [PersistenceService].
  /// The [scriptService] is optional and used for running lifecycle hooks.
  WorktreeService({
    GitService? gitService,
    PersistenceService? persistenceService,
    ProjectConfigService? configService,
    ScriptExecutionService? scriptService,
  })  : _gitService = gitService ?? const RealGitService(),
        _persistenceService = persistenceService ?? PersistenceService(),
        _configService = configService ?? ProjectConfigService(),
        _scriptService = scriptService;

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
    String? base,
  }) async {
    final repoRoot = project.data.repoRoot;

    LogService.instance.notice('Worktree', 'Creating workspace: branch=$branch root=$worktreeRoot${base != null ? ' base=$base' : ''}');

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

    // 3b. If branch exists but is not a worktree, signal for recovery prompt
    if (branchExists) {
      throw WorktreeBranchExistsException(sanitizedBranch);
    }

    // 4. Construct the full worktree path
    final worktreePath = path.join(worktreeRoot, 'cci', sanitizedBranch);

    // 5. Ensure parent directory exists
    final parentDir = Directory(path.dirname(worktreePath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 6. Run pre-create hook if configured
    final config = await _configService.loadConfig(repoRoot);
    final preCreateHook = config.getHook('worktree-pre-create');
    if (preCreateHook != null && preCreateHook.isNotEmpty) {
      LogService.instance.notice('Worktree', 'Running hook: worktree-pre-create');
      final exitCode = await _runHook(
        hookName: 'worktree-pre-create',
        command: preCreateHook,
        workingDirectory: repoRoot,
      );
      if (exitCode != 0) {
        throw WorktreeCreationException(
          'Pre-create hook failed with exit code $exitCode',
          suggestions: [
            'Check the hook script for errors',
            'Review the terminal output for details',
          ],
        );
      }
    }

    // 7. If base is a remote ref (e.g. origin/main), fetch the remote first
    if (base != null && base.contains('/')) {
      final remote = base.split('/').first;
      try {
        await _gitService.fetchRemote(repoRoot, remote);
      } on GitException {
        // Fetch failure is non-fatal — the base ref may still be available locally
      }
    }

    // 8. Create the git worktree
    try {
      await _gitService.createWorktree(
        repoRoot: repoRoot,
        worktreePath: worktreePath,
        branch: sanitizedBranch,
        newBranch: !branchExists,
        base: base,
      );
    } on GitException catch (e) {
      throw WorktreeCreationException(
        'Failed to create worktree: ${e.message}',
        suggestions: _suggestionsForGitError(e),
      );
    }

    // 9. Run post-create hook if configured
    final postCreateHook = config.getHook('worktree-post-create');
    if (postCreateHook != null && postCreateHook.isNotEmpty) {
      LogService.instance.notice('Worktree', 'Running hook: worktree-post-create');
      // Run in the new worktree directory
      final exitCode = await _runHook(
        hookName: 'worktree-post-create',
        command: postCreateHook,
        workingDirectory: worktreePath,
      );
      if (exitCode != 0) {
        developer.log(
          'Post-create hook failed with exit code $exitCode, continuing anyway',
          name: 'WorktreeService',
        );
        // Don't fail worktree creation for post-create hook failures
      }
    }

    // 10. Get git status for the new worktree
    final status = await _gitService.getStatus(worktreePath);

    // 11. Determine the base for this worktree.
    // Use the explicitly provided base, falling back to the project default.
    var effectiveBase = base;
    if (effectiveBase == null) {
      final defaultBase = config.defaultBase;
      if (defaultBase != null && defaultBase.isNotEmpty && defaultBase != 'auto') {
        effectiveBase = defaultBase;
      }
    }

    // 12. Create WorktreeData and WorktreeState
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
    final worktreeState = WorktreeState(worktreeData, base: effectiveBase);

    // 13. Persist to projects.json
    await _persistWorktree(project, worktreeState, base: effectiveBase);

    // 14. Return WorktreeState
    LogService.instance.info('Worktree', 'Workspace created: branch=$sanitizedBranch path=$worktreePath');
    return worktreeState;
  }

  /// Recovers a worktree from an existing branch.
  ///
  /// This is called after the user confirms they want to recover a branch
  /// that already exists in git. It creates a worktree using the existing
  /// branch, skipping the branch-exists check that [createWorktree] performs.
  ///
  /// The [branch] should already be sanitized (as returned by
  /// [WorktreeBranchExistsException.branchName]).
  Future<WorktreeState> recoverWorktree({
    required ProjectState project,
    required String branch,
    required String worktreeRoot,
  }) async {
    final repoRoot = project.data.repoRoot;

    LogService.instance.notice('Worktree', 'Recovering workspace: branch=$branch root=$worktreeRoot');

    // 1. Construct the full worktree path
    final worktreePath = path.join(worktreeRoot, 'cci', branch);

    // 2. Ensure parent directory exists
    final parentDir = Directory(path.dirname(worktreePath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 3. Run pre-create hook if configured
    final config = await _configService.loadConfig(repoRoot);
    final preCreateHook = config.getHook('worktree-pre-create');
    if (preCreateHook != null && preCreateHook.isNotEmpty) {
      LogService.instance.notice('Worktree', 'Running hook: worktree-pre-create');
      final exitCode = await _runHook(
        hookName: 'worktree-pre-create',
        command: preCreateHook,
        workingDirectory: repoRoot,
      );
      if (exitCode != 0) {
        throw WorktreeCreationException(
          'Pre-create hook failed with exit code $exitCode',
          suggestions: [
            'Check the hook script for errors',
            'Review the terminal output for details',
          ],
        );
      }
    }

    // 4. Create the git worktree using the existing branch
    try {
      await _gitService.createWorktree(
        repoRoot: repoRoot,
        worktreePath: worktreePath,
        branch: branch,
        newBranch: false, // Branch already exists
      );
    } on GitException catch (e) {
      throw WorktreeCreationException(
        'Failed to create worktree: ${e.message}',
        suggestions: _suggestionsForGitError(e),
      );
    }

    // 5. Run post-create hook if configured
    final postCreateHook = config.getHook('worktree-post-create');
    if (postCreateHook != null && postCreateHook.isNotEmpty) {
      LogService.instance.notice('Worktree', 'Running hook: worktree-post-create');
      final exitCode = await _runHook(
        hookName: 'worktree-post-create',
        command: postCreateHook,
        workingDirectory: worktreePath,
      );
      if (exitCode != 0) {
        developer.log(
          'Post-create hook failed with exit code $exitCode, continuing anyway',
          name: 'WorktreeService',
        );
      }
    }

    // 6. Get git status for the new worktree
    final status = await _gitService.getStatus(worktreePath);

    // 7. Determine the base for this worktree.
    String? effectiveBase;
    final defaultBase = config.defaultBase;
    if (defaultBase != null && defaultBase.isNotEmpty && defaultBase != 'auto') {
      effectiveBase = defaultBase;
    }

    // 8. Create WorktreeData and WorktreeState
    final worktreeData = WorktreeData(
      worktreeRoot: worktreePath,
      isPrimary: false,
      branch: branch,
      uncommittedFiles: status.uncommittedFiles,
      stagedFiles: status.staged,
      commitsAhead: status.ahead,
      commitsBehind: status.behind,
      hasMergeConflict: status.hasConflicts,
    );
    final worktreeState = WorktreeState(worktreeData, base: effectiveBase);

    // 9. Persist to projects.json
    await _persistWorktree(project, worktreeState, base: effectiveBase);

    // 10. Return WorktreeState
    LogService.instance.info('Worktree', 'Workspace recovered: branch=$branch path=$worktreePath');
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

  /// Runs a lifecycle hook script and returns the exit code.
  ///
  /// If a [ScriptExecutionService] is available, uses it to show output
  /// in the terminal panel. Otherwise, runs the script directly.
  Future<int> _runHook({
    required String hookName,
    required String command,
    required String workingDirectory,
  }) async {
    developer.log(
      'Running hook "$hookName": $command in $workingDirectory',
      name: 'WorktreeService',
    );

    if (_scriptService != null) {
      // Use script service to show output in terminal panel
      return await _scriptService.runScriptSync(
        name: hookName,
        command: command,
        workingDirectory: workingDirectory,
      );
    } else {
      // Run directly without UI
      final result = await Process.run(
        '/bin/sh',
        ['-c', command],
        workingDirectory: workingDirectory,
      );
      return result.exitCode;
    }
  }

  /// Persists a new worktree to projects.json.
  ///
  /// The [base] captures the project's default base at creation time,
  /// ensuring the worktree's base doesn't change when the project default
  /// changes later.
  Future<void> _persistWorktree(
    ProjectState project,
    WorktreeState worktree, {
    String? base,
  }) async {
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
      base: base,
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
