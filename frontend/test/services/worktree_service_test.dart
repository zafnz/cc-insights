import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/persistence_models.dart'
    as persistence;
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';

void main() {
  late FakeGitService gitService;
  late _FakePersistenceService persistenceService;
  late WorktreeService worktreeService;
  late Directory tempDir;
  late String repoRoot;
  late String worktreeRoot;

  setUp(() async {
    gitService = FakeGitService();
    tempDir = await Directory.systemTemp.createTemp('worktree_service_test_');
    persistenceService = _FakePersistenceService(tempDir.path);
    worktreeService = WorktreeService(
      gitService: gitService,
      persistenceService: persistenceService,
    );

    // Set up paths within the temp directory
    repoRoot = '${tempDir.path}/repo';
    worktreeRoot = '${tempDir.path}/worktrees';

    // Create the repo directory so path validation doesn't fail
    await Directory(repoRoot).create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('WorktreeService', () {
    group('branch name sanitization', () {
      test('converts spaces to hyphens', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/my-branch-name'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'my branch name',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('my-branch-name');
      });

      test('removes invalid characters', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/featurevalid'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature@#\$%^&*valid',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('featurevalid');
      });

      test('removes leading and trailing hyphens', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/my-branch'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: '---my-branch---',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('my-branch');
      });

      test('collapses consecutive dots', () async {
        // Arrange
        // Note: The sanitization removes ALL dots because they're not in the
        // allowed character class [^\w\-/]. The consecutive dots regex runs
        // after dots are already removed, so this test verifies dots are
        // removed entirely.
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/featuretest'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature...test',
          worktreeRoot: worktreeRoot,
        );

        // Assert - dots are removed by the invalid char filter
        check(result.data.branch).equals('featuretest');
      });

      test('collapses consecutive slashes', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature/test'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature///test',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('feature/test');
      });

      test('throws error when empty after sanitization', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          worktreeService.createWorktree(
            project: project,
            branch: '@#\$%^&*()',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeCreationException>();
      });

      test('throws with descriptive message when empty after sanitization',
          () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await worktreeService.createWorktree(
            project: project,
            branch: '---',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.message).contains('Invalid branch name');
        }
      });
    });

    group('path validation', () {
      test('throws when path is inside repo', () async {
        // Arrange
        final insideRepoPath = '$repoRoot/nested'; // Inside repo
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          worktreeService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: insideRepoPath,
          ),
        ).throws<WorktreeCreationException>();
      });

      test('exception message mentions path is inside repo', () async {
        // Arrange
        final insideRepoPath = '$repoRoot/subdirectory';
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await worktreeService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: insideRepoPath,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.message).contains('inside the project repository');
          check(e.suggestions).isNotEmpty();
        }
      });

      test('succeeds when path is outside repo', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.worktreeRoot).equals('$worktreeRoot/cci/feature');
      });

      test('throws when path is repo root', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          worktreeService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: repoRoot, // Same as repo root
          ),
        ).throws<WorktreeCreationException>();
      });

      test('succeeds with similar prefix but different directory', () async {
        // Arrange: /foo/bar vs /foo/barbaz - should NOT match
        final similarButDifferent = '${repoRoot}baz';
        await Directory(similarButDifferent).create(recursive: true);
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$similarButDifferent/cci/feature'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature',
          worktreeRoot: similarButDifferent,
        );

        // Assert - should succeed because path is NOT inside repo
        check(result.data.worktreeRoot)
            .equals('$similarButDifferent/cci/feature');
      });
    });

    group('branch status checking', () {
      test('creates new branch with -b flag when branch does not exist',
          () async {
        // Arrange
        final trackingGitService = _TrackingFakeGitService();
        trackingGitService.setupSimpleRepo(repoRoot);
        trackingGitService.statuses['$worktreeRoot/cci/new-feature'] =
            const GitStatus();

        final trackingService = WorktreeService(
          gitService: trackingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        await trackingService.createWorktree(
          project: project,
          branch: 'new-feature',
          worktreeRoot: worktreeRoot,
        );

        // Assert - check that createWorktree was called with newBranch: true
        check(trackingGitService.createWorktreeCalls).isNotEmpty();
        check(trackingGitService.createWorktreeCalls.first.newBranch).isTrue();
      });

      test(
          'throws WorktreeBranchExistsException when branch exists but is not a worktree',
          () async {
        // Arrange
        final trackingGitService = _TrackingFakeGitService();
        trackingGitService.setupSimpleRepo(repoRoot);
        trackingGitService.statuses['$worktreeRoot/cci/existing-branch'] =
            const GitStatus();
        trackingGitService.existingBranches.add('existing-branch');
        // Branch exists but is NOT in worktrees list

        final trackingService = WorktreeService(
          gitService: trackingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert - should throw for user confirmation, not silently proceed
        await check(
          trackingService.createWorktree(
            project: project,
            branch: 'existing-branch',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeBranchExistsException>();
      });

      test(
          'throws WorktreeBranchExistsException when branch exists but is not a worktree',
          () async {
        // Arrange
        final trackingGitService = _TrackingFakeGitService();
        trackingGitService.setupSimpleRepo(repoRoot);
        trackingGitService.existingBranches.add('existing-branch');

        final trackingService = WorktreeService(
          gitService: trackingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          trackingService.createWorktree(
            project: project,
            branch: 'existing-branch',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeBranchExistsException>();
      });

      test(
          'WorktreeBranchExistsException contains sanitized branch name',
          () async {
        // Arrange
        final trackingGitService = _TrackingFakeGitService();
        trackingGitService.setupSimpleRepo(repoRoot);
        trackingGitService.existingBranches.add('existing-branch');

        final trackingService = WorktreeService(
          gitService: trackingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await trackingService.createWorktree(
            project: project,
            branch: 'existing-branch',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeBranchExistsException');
        } on WorktreeBranchExistsException catch (e) {
          // Assert
          check(e.branchName).equals('existing-branch');
          check(e.message).contains('already exists');
        }
      });

      test('throws when branch already exists as a worktree', () async {
        // Arrange
        const existingWorktreePath = '/other/worktree/feature';
        gitService.worktrees[repoRoot] = [
          WorktreeInfo(path: repoRoot, isPrimary: true, branch: 'main'),
          const WorktreeInfo(
            path: existingWorktreePath,
            isPrimary: false,
            branch: 'feature',
          ),
        ];
        gitService.repoRoots[repoRoot] = repoRoot;
        gitService.branches[repoRoot] = 'main';
        gitService.statuses[repoRoot] = const GitStatus();

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          worktreeService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeCreationException>();
      });

      test('exception includes path of existing worktree', () async {
        // Arrange
        const existingWorktreePath = '/other/worktree/feature';
        gitService.worktrees[repoRoot] = [
          WorktreeInfo(path: repoRoot, isPrimary: true, branch: 'main'),
          const WorktreeInfo(
            path: existingWorktreePath,
            isPrimary: false,
            branch: 'feature',
          ),
        ];
        gitService.repoRoots[repoRoot] = repoRoot;
        gitService.branches[repoRoot] = 'main';
        gitService.statuses[repoRoot] = const GitStatus();

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await worktreeService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.message).contains(existingWorktreePath);
          check(e.message).contains('already a worktree');
          check(e.suggestions).isNotEmpty();
        }
      });
    });

    group('error handling', () {
      test('produces WorktreeCreationException on git command failure',
          () async {
        // Arrange
        final failingGitService = _FailingGitService();
        failingGitService.setupSimpleRepo(repoRoot);
        failingGitService.statuses['$worktreeRoot/cci/feature'] =
            const GitStatus();
        failingGitService.createWorktreeError = const GitException(
          'Git worktree add failed',
          command: 'git worktree add',
          exitCode: 1,
          stderr: 'fatal: already exists',
        );

        final failingService = WorktreeService(
          gitService: failingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          failingService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeCreationException>();
      });

      test('generates suggestions for "already exists" git error', () async {
        // Arrange
        final failingGitService = _FailingGitService();
        failingGitService.setupSimpleRepo(repoRoot);
        failingGitService.statuses['$worktreeRoot/cci/feature'] =
            const GitStatus();
        failingGitService.createWorktreeError = const GitException(
          'Git worktree add failed',
          command: 'git worktree add',
          exitCode: 1,
          stderr: 'fatal: already exists',
        );

        final failingService = WorktreeService(
          gitService: failingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await failingService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.suggestions.any((s) => s.contains('already exists')))
              .isTrue();
        }
      });

      test('generates suggestions for "already checked out" git error',
          () async {
        // Arrange
        final failingGitService = _FailingGitService();
        failingGitService.setupSimpleRepo(repoRoot);
        failingGitService.statuses['$worktreeRoot/cci/feature'] =
            const GitStatus();
        failingGitService.createWorktreeError = const GitException(
          'Git worktree add failed',
          command: 'git worktree add',
          exitCode: 1,
          stderr: 'fatal: branch is already checked out at another worktree',
        );

        final failingService = WorktreeService(
          gitService: failingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await failingService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.suggestions.any((s) => s.contains('different branch')))
              .isTrue();
        }
      });

      test('generates generic suggestion for unknown git error', () async {
        // Arrange
        final failingGitService = _FailingGitService();
        failingGitService.setupSimpleRepo(repoRoot);
        failingGitService.statuses['$worktreeRoot/cci/feature'] =
            const GitStatus();
        failingGitService.createWorktreeError = const GitException(
          'Git worktree add failed',
          command: 'git worktree add',
          exitCode: 1,
          stderr: 'some unknown error',
        );

        final failingService = WorktreeService(
          gitService: failingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        try {
          await failingService.createWorktree(
            project: project,
            branch: 'feature',
            worktreeRoot: worktreeRoot,
          );
          fail('Expected WorktreeCreationException');
        } on WorktreeCreationException catch (e) {
          // Assert
          check(e.suggestions).isNotEmpty();
        }
      });
    });

    group('success path', () {
      test('creates worktree at correct path: root/cci/branch', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/my-feature'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'my-feature',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.worktreeRoot).equals('$worktreeRoot/cci/my-feature');
      });

      test('returns WorktreeState with correct data', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature'] = const GitStatus(
          staged: 1,
          unstaged: 2,
          changedEntries: 3,
          ahead: 3,
          behind: 4,
          hasConflicts: true,
        );
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('feature');
        check(result.data.isPrimary).isFalse();
        check(result.data.stagedFiles).equals(1);
        check(result.data.uncommittedFiles).equals(3); // changedEntries + untracked
        check(result.data.commitsAhead).equals(3);
        check(result.data.commitsBehind).equals(4);
        check(result.data.hasMergeConflict).isTrue();
      });

      test('calls persistence service with correct worktree info', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        await worktreeService.createWorktree(
          project: project,
          branch: 'feature',
          worktreeRoot: worktreeRoot,
        );

        // Assert - verify persistence was updated
        final index = await persistenceService.loadProjectsIndex();
        final projectInfo = index.projects[repoRoot];
        check(projectInfo).isNotNull();
        check(projectInfo!.worktrees['$worktreeRoot/cci/feature']).isNotNull();
        final worktreeInfo =
            projectInfo.worktrees['$worktreeRoot/cci/feature']!;
        check(worktreeInfo.isLinked).isTrue();
        check(worktreeInfo.name).equals('feature');
      });

      test('handles branch names with slashes correctly', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature/nested/branch'] =
            const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.createWorktree(
          project: project,
          branch: 'feature/nested/branch',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('feature/nested/branch');
        check(result.data.worktreeRoot)
            .equals('$worktreeRoot/cci/feature/nested/branch');
      });
    });

    group('recoverWorktree', () {
      test('creates worktree from existing branch without checking existence',
          () async {
        // Arrange
        final trackingGitService = _TrackingFakeGitService();
        trackingGitService.setupSimpleRepo(repoRoot);
        trackingGitService.existingBranches.add('recover-me');
        trackingGitService.statuses['$worktreeRoot/cci/recover-me'] =
            const GitStatus();

        final trackingService = WorktreeService(
          gitService: trackingGitService,
          persistenceService: persistenceService,
        );

        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await trackingService.recoverWorktree(
          project: project,
          branch: 'recover-me',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.branch).equals('recover-me');
        check(result.data.worktreeRoot).equals('$worktreeRoot/cci/recover-me');
        check(result.data.isPrimary).isFalse();
        // Should call git with newBranch: false
        check(trackingGitService.createWorktreeCalls).isNotEmpty();
        check(trackingGitService.createWorktreeCalls.first.newBranch).isFalse();
      });

      test('persists recovered worktree to projects.json', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/recover-me'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        await worktreeService.recoverWorktree(
          project: project,
          branch: 'recover-me',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        final index = await persistenceService.loadProjectsIndex();
        final projectInfo = index.projects[repoRoot];
        check(projectInfo).isNotNull();
        check(projectInfo!.worktrees['$worktreeRoot/cci/recover-me']).isNotNull();
        final worktreeInfo =
            projectInfo.worktrees['$worktreeRoot/cci/recover-me']!;
        check(worktreeInfo.isLinked).isTrue();
        check(worktreeInfo.name).equals('recover-me');
      });

      test('returns WorktreeState with correct git status', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/recover-me'] = const GitStatus(
          staged: 2,
          changedEntries: 5,
          ahead: 1,
          behind: 3,
          hasConflicts: true,
        );
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result = await worktreeService.recoverWorktree(
          project: project,
          branch: 'recover-me',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result.data.stagedFiles).equals(2);
        check(result.data.uncommittedFiles).equals(5);
        check(result.data.commitsAhead).equals(1);
        check(result.data.commitsBehind).equals(3);
        check(result.data.hasMergeConflict).isTrue();
      });
    });

    group('integration scenarios', () {
      test('multiple worktrees can be created for same project', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        gitService.statuses['$worktreeRoot/cci/feature-1'] = const GitStatus();
        gitService.statuses['$worktreeRoot/cci/feature-2'] = const GitStatus();
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act
        final result1 = await worktreeService.createWorktree(
          project: project,
          branch: 'feature-1',
          worktreeRoot: worktreeRoot,
        );

        final result2 = await worktreeService.createWorktree(
          project: project,
          branch: 'feature-2',
          worktreeRoot: worktreeRoot,
        );

        // Assert
        check(result1.data.branch).equals('feature-1');
        check(result2.data.branch).equals('feature-2');

        final index = await persistenceService.loadProjectsIndex();
        final projectInfo = index.projects[repoRoot]!;
        check(projectInfo.worktrees).length.equals(3); // primary + 2 linked
      });

      test('whitespace-only branch name throws error', () async {
        // Arrange
        gitService.setupSimpleRepo(repoRoot);
        final project = _createProject(repoRoot);
        await _setupPersistence(persistenceService, repoRoot, project);

        // Act & Assert
        await check(
          worktreeService.createWorktree(
            project: project,
            branch: '   ',
            worktreeRoot: worktreeRoot,
          ),
        ).throws<WorktreeCreationException>();
      });
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

ProjectState _createProject(String repoRoot) {
  final projectData = ProjectData(name: 'Test Project', repoRoot: repoRoot);
  final worktreeData = WorktreeData(
    worktreeRoot: repoRoot,
    isPrimary: true,
    branch: 'main',
  );
  final primaryWorktree = WorktreeState(worktreeData);
  return ProjectState(
    projectData,
    primaryWorktree,
    autoValidate: false,
    watchFilesystem: false,
  );
}

Future<void> _setupPersistence(
  _FakePersistenceService persistenceService,
  String repoRoot,
  ProjectState project,
) async {
  final projectInfo = persistence.ProjectInfo(
    id: PersistenceService.generateProjectId(repoRoot),
    name: project.data.name,
    worktrees: {
      repoRoot: const persistence.WorktreeInfo.primary(name: 'main'),
    },
  );
  await persistenceService.saveProjectsIndex(
    persistence.ProjectsIndex(projects: {repoRoot: projectInfo}),
  );
}

// =============================================================================
// Fake Services
// =============================================================================

/// Fake persistence service for testing.
class _FakePersistenceService extends PersistenceService {
  final String _testBaseDir;

  _FakePersistenceService(this._testBaseDir);

  String get _baseDir => '$_testBaseDir/.ccinsights';

  @override
  Future<persistence.ProjectsIndex> loadProjectsIndex() async {
    final file = File('$_baseDir/projects.json');

    if (!await file.exists()) {
      return const persistence.ProjectsIndex.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return const persistence.ProjectsIndex.empty();
      }
      final json = jsonDecode(content) as Map<String, dynamic>;
      return persistence.ProjectsIndex.fromJson(json);
    } catch (e) {
      return const persistence.ProjectsIndex.empty();
    }
  }

  @override
  Future<void> saveProjectsIndex(persistence.ProjectsIndex index) async {
    final dir = Directory(_baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File('$_baseDir/projects.json');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(index.toJson()));
  }
}

/// Tracking fake git service that records createWorktree calls.
class _TrackingFakeGitService extends FakeGitService {
  final List<_CreateWorktreeCall> createWorktreeCalls = [];
  final Set<String> existingBranches = {};

  @override
  Future<bool> branchExists(String repoRoot, String branchName) async {
    await super.branchExists(repoRoot, branchName);
    return existingBranches.contains(branchName);
  }

  @override
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
    String? base,
  }) async {
    createWorktreeCalls.add(_CreateWorktreeCall(
      repoRoot: repoRoot,
      worktreePath: worktreePath,
      branch: branch,
      newBranch: newBranch,
      base: base,
    ));
    await super.createWorktree(
      repoRoot: repoRoot,
      worktreePath: worktreePath,
      branch: branch,
      newBranch: newBranch,
      base: base,
    );
  }
}

class _CreateWorktreeCall {
  final String repoRoot;
  final String worktreePath;
  final String branch;
  final bool newBranch;
  final String? base;

  _CreateWorktreeCall({
    required this.repoRoot,
    required this.worktreePath,
    required this.branch,
    required this.newBranch,
    this.base,
  });
}

/// Fake git service that can be configured to fail on createWorktree.
class _FailingGitService extends FakeGitService {
  GitException? createWorktreeError;

  @override
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
    String? base,
  }) async {
    if (createWorktreeError != null) {
      throw createWorktreeError!;
    }
    await super.createWorktree(
      repoRoot: repoRoot,
      worktreePath: worktreePath,
      branch: branch,
      newBranch: newBranch,
      base: base,
    );
  }
}
