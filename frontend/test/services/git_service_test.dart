import 'dart:io';

import 'package:cc_insights_v2/services/git_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';

void main() {
  // ===========================================================================
  // PARSING TESTS - Pure functions, no I/O
  // ===========================================================================

  group('GitStatusParser', () {
    test('parses empty status (clean working tree)', () {
      const output = '''
# branch.oid abc123
# branch.head main
# branch.upstream origin/main
# branch.ab +0 -0
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 0);
      expect(status.unstaged, 0);
      expect(status.untracked, 0);
      expect(status.ahead, 0);
      expect(status.behind, 0);
      expect(status.hasConflicts, false);
    });

    test('parses ahead/behind counts', () {
      const output = '''
# branch.oid abc123
# branch.head feature
# branch.upstream origin/feature
# branch.ab +5 -3
''';
      final status = GitStatusParser.parse(output);

      expect(status.ahead, 5);
      expect(status.behind, 3);
    });

    test('parses staged files', () {
      // 1 = ordinary changed entry, XY where X is staged status
      // M. = modified and staged, not modified in worktree
      // A. = added (new file), staged
      const output = '''
# branch.ab +0 -0
1 M. N... 100644 100644 100644 abc123 def456 lib/main.dart
1 A. N... 000000 100644 100644 000000 abc123 lib/new_file.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 2);
      expect(status.unstaged, 0);
    });

    test('parses unstaged files', () {
      // .M = not staged, modified in worktree
      // .D = not staged, deleted in worktree
      const output = '''
# branch.ab +0 -0
1 .M N... 100644 100644 100644 abc123 abc123 lib/modified.dart
1 .D N... 100644 100644 000000 abc123 abc123 lib/deleted.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 0);
      expect(status.unstaged, 2);
    });

    test('parses mixed staged and unstaged', () {
      // MM = staged AND also modified in worktree
      const output = '''
# branch.ab +0 -0
1 MM N... 100644 100644 100644 abc123 def456 lib/both.dart
1 M. N... 100644 100644 100644 abc123 def456 lib/staged_only.dart
1 .M N... 100644 100644 100644 abc123 abc123 lib/unstaged_only.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 2); // MM and M.
      expect(status.unstaged, 2); // MM and .M
    });

    test('parses untracked files', () {
      const output = '''
# branch.ab +0 -0
? lib/new_untracked.dart
? test/another_untracked.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.untracked, 2);
      expect(status.uncommittedFiles, 2); // unstaged + untracked
    });

    test('parses merge conflicts', () {
      // u = unmerged entry
      const output = '''
# branch.ab +1 -2
u UU N... 100644 100644 100644 100644 abc123 def456 ghi789 lib/conflicted.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.hasConflicts, true);
    });

    test('parses renamed files', () {
      // 2 = rename entry
      const output = '''
# branch.ab +0 -0
2 R. N... 100644 100644 100644 abc123 def456 R100 lib/old.dart\tlib/new.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 1);
      expect(status.unstaged, 0);
    });

    test('ignores ignored files', () {
      const output = '''
# branch.ab +0 -0
! build/output.txt
! .dart_tool/package_config.json
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 0);
      expect(status.unstaged, 0);
      expect(status.untracked, 0);
    });

    test('handles complex real-world output', () {
      const output = '''
# branch.oid 1234567890abcdef
# branch.head feature-branch
# branch.upstream origin/feature-branch
# branch.ab +3 -1
1 M. N... 100644 100644 100644 abc123 def456 lib/main.dart
1 A. N... 000000 100644 100644 000000 abc123 lib/new_service.dart
1 .M N... 100644 100644 100644 abc123 abc123 lib/utils.dart
? lib/temp.dart
? test/temp_test.dart
''';
      final status = GitStatusParser.parse(output);

      expect(status.staged, 2); // M. and A.
      expect(status.unstaged, 1); // .M
      expect(status.untracked, 2); // two ? entries
      expect(status.uncommittedFiles, 5); // 3 changed + 2 untracked
      expect(status.ahead, 3);
      expect(status.behind, 1);
      expect(status.hasConflicts, false);
    });
  });

  group('GitWorktreeParser', () {
    test('parses single worktree (primary only)', () {
      const output = '''
worktree /tmp/cc-insights/myrepo
HEAD abc123def456
branch refs/heads/main

''';
      final worktrees =
          GitWorktreeParser.parse(output, '/tmp/cc-insights/myrepo');

      expect(worktrees.length, 1);
      expect(worktrees[0].path, '/tmp/cc-insights/myrepo');
      expect(worktrees[0].isPrimary, true);
      expect(worktrees[0].branch, 'main');
    });

    test('parses multiple worktrees', () {
      const output = '''
worktree /tmp/cc-insights/myrepo
HEAD abc123
branch refs/heads/main

worktree /tmp/cc-insights/myrepo-wt/feature
HEAD def456
branch refs/heads/feature-branch

worktree /tmp/cc-insights/myrepo-wt/bugfix
HEAD ghi789
branch refs/heads/bugfix-123

''';
      final worktrees =
          GitWorktreeParser.parse(output, '/tmp/cc-insights/myrepo');

      expect(worktrees.length, 3);

      expect(worktrees[0].path, '/tmp/cc-insights/myrepo');
      expect(worktrees[0].isPrimary, true);
      expect(worktrees[0].branch, 'main');

      expect(worktrees[1].path, '/tmp/cc-insights/myrepo-wt/feature');
      expect(worktrees[1].isPrimary, false);
      expect(worktrees[1].branch, 'feature-branch');

      expect(worktrees[2].path, '/tmp/cc-insights/myrepo-wt/bugfix');
      expect(worktrees[2].isPrimary, false);
      expect(worktrees[2].branch, 'bugfix-123');
    });

    test('handles detached HEAD', () {
      const output = '''
worktree /tmp/cc-insights/myrepo
HEAD abc123
detached

''';
      final worktrees =
          GitWorktreeParser.parse(output, '/tmp/cc-insights/myrepo');

      expect(worktrees.length, 1);
      expect(worktrees[0].branch, null);
    });

    test('handles trailing slash in primary path', () {
      const output = '''
worktree /tmp/cc-insights/myrepo
HEAD abc123
branch refs/heads/main

''';
      // Primary path has trailing slash
      final worktrees =
          GitWorktreeParser.parse(output, '/tmp/cc-insights/myrepo/');

      expect(worktrees[0].isPrimary, true);
    });

    test('handles output without trailing newline', () {
      const output = '''
worktree /tmp/cc-insights/myrepo
HEAD abc123
branch refs/heads/main''';

      final worktrees =
          GitWorktreeParser.parse(output, '/tmp/cc-insights/myrepo');

      expect(worktrees.length, 1);
      expect(worktrees[0].branch, 'main');
    });
  });

  // ===========================================================================
  // FAKE SERVICE TESTS - Fast, reliable, no I/O
  // ===========================================================================

  group('FakeGitService', () {
    late FakeGitService gitService;

    setUp(() {
      gitService = FakeGitService();
    });

    test('returns configured version', () async {
      gitService.version = '2.45.0';

      final version = await gitService.getVersion();

      expect(version, '2.45.0');
      expect(gitService.getVersionCalls, 1);
    });

    test('returns configured branch', () async {
      gitService.branches['/my/repo'] = 'feature-x';

      final branch = await gitService.getCurrentBranch('/my/repo');

      expect(branch, 'feature-x');
      expect(gitService.getCurrentBranchCalls, 1);
    });

    test('returns null for detached HEAD', () async {
      gitService.branches['/my/repo'] = null;

      final branch = await gitService.getCurrentBranch('/my/repo');

      expect(branch, null);
    });

    test('throws for unknown path', () async {
      expect(
        () => gitService.getCurrentBranch('/unknown/path'),
        throwsA(isA<GitException>()),
      );
    });

    test('returns configured status', () async {
      gitService.statuses['/my/repo'] = const GitStatus(
        staged: 2,
        unstaged: 3,
        untracked: 1,
        changedEntries: 4,
        ahead: 5,
        behind: 2,
        hasConflicts: true,
      );

      final status = await gitService.getStatus('/my/repo');

      expect(status.staged, 2);
      expect(status.unstaged, 3);
      expect(status.untracked, 1);
      expect(status.uncommittedFiles, 5); // 4 changed + 1 untracked
      expect(status.ahead, 5);
      expect(status.behind, 2);
      expect(status.hasConflicts, true);
    });

    test('setupSimpleRepo configures everything', () async {
      gitService.setupSimpleRepo('/my/repo', branch: 'develop');

      expect(await gitService.findRepoRoot('/my/repo'), '/my/repo');
      expect(await gitService.getCurrentBranch('/my/repo'), 'develop');

      final status = await gitService.getStatus('/my/repo');
      expect(status.staged, 0);

      final wts = await gitService.discoverWorktrees('/my/repo');
      expect(wts.length, 1);
      expect(wts[0].isPrimary, true);
      expect(wts[0].branch, 'develop');
    });

    test('setupRepo configures multiple worktrees', () async {
      gitService.setupRepo('/primary', [
        const WorktreeInfo(path: '/primary', isPrimary: true, branch: 'main'),
        const WorktreeInfo(
            path: '/wt/feature', isPrimary: false, branch: 'feature'),
      ]);

      final wts = await gitService.discoverWorktrees('/primary');
      expect(wts.length, 2);

      expect(await gitService.getCurrentBranch('/primary'), 'main');
      expect(await gitService.getCurrentBranch('/wt/feature'), 'feature');
    });

    test('throwOnAll causes all methods to throw', () async {
      gitService.throwOnAll =
          const GitException('Simulated failure', exitCode: 1);

      expect(() => gitService.getVersion(), throwsA(isA<GitException>()));
      expect(
          () => gitService.getCurrentBranch('/x'), throwsA(isA<GitException>()));
      expect(() => gitService.getStatus('/x'), throwsA(isA<GitException>()));
    });

    test('reset clears all state', () async {
      gitService.version = '1.0.0';
      gitService.branches['/x'] = 'y';
      gitService.getVersionCalls = 5;

      gitService.reset();

      expect(gitService.version, '2.39.0');
      expect(gitService.branches, isEmpty);
      expect(gitService.getVersionCalls, 0);
    });

    test('stash tracks calls', () async {
      await gitService.stash('/my/repo');

      expect(gitService.stashCalls, ['/my/repo']);
    });

    test('stash throws configured error', () async {
      gitService.stashError =
          const GitException('Stash failed', exitCode: 1);

      expect(
        () => gitService.stash('/my/repo'),
        throwsA(isA<GitException>()),
      );
    });

    test('fetch tracks calls', () async {
      await gitService.fetch('/my/repo');

      expect(gitService.fetchCalls, ['/my/repo']);
    });

    test('fetch throws configured error', () async {
      gitService.fetchError =
          const GitException('Fetch failed', exitCode: 1);

      expect(
        () => gitService.fetch('/my/repo'),
        throwsA(isA<GitException>()),
      );
    });

    test('isBranchMerged returns configured value', () async {
      gitService.branchMerged['/repo:feature:main'] = true;

      final result = await gitService.isBranchMerged('/repo', 'feature', 'main');

      expect(result, true);
    });

    test('isBranchMerged returns false when not merged', () async {
      gitService.branchMerged['/repo:feature:main'] = false;

      final result = await gitService.isBranchMerged('/repo', 'feature', 'main');

      expect(result, false);
    });

    test('isBranchMerged defaults to true', () async {
      // No configuration - should default to true
      final result = await gitService.isBranchMerged('/repo', 'feature', 'main');

      expect(result, true);
    });

    test('removeWorktree tracks calls', () async {
      await gitService.removeWorktree(
        repoRoot: '/repo',
        worktreePath: '/repo/worktree',
        force: false,
      );

      expect(gitService.removeWorktreeCalls.length, 1);
      expect(gitService.removeWorktreeCalls.first.repoRoot, '/repo');
      expect(gitService.removeWorktreeCalls.first.worktreePath, '/repo/worktree');
      expect(gitService.removeWorktreeCalls.first.force, false);
    });

    test('removeWorktree with force flag', () async {
      await gitService.removeWorktree(
        repoRoot: '/repo',
        worktreePath: '/repo/worktree',
        force: true,
      );

      expect(gitService.removeWorktreeCalls.first.force, true);
    });

    test('removeWorktree throws configured error', () async {
      gitService.removeWorktreeError =
          const GitException('Remove failed', exitCode: 1);

      expect(
        () => gitService.removeWorktree(
          repoRoot: '/repo',
          worktreePath: '/repo/worktree',
        ),
        throwsA(isA<GitException>()),
      );
    });

    test('removeWorktree only throws on non-force when configured', () async {
      gitService.removeWorktreeError =
          const GitException('Contains modified files', exitCode: 1);
      gitService.removeWorktreeOnlyThrowOnNonForce = true;

      // Non-force should throw
      expect(
        () => gitService.removeWorktree(
          repoRoot: '/repo',
          worktreePath: '/repo/worktree',
          force: false,
        ),
        throwsA(isA<GitException>()),
      );

      // Force should succeed
      await gitService.removeWorktree(
        repoRoot: '/repo',
        worktreePath: '/repo/worktree',
        force: true,
      );

      expect(gitService.removeWorktreeCalls.length, 2);
    });
  });

  // ===========================================================================
  // REAL SERVICE TESTS - Actual git process spawning
  // ===========================================================================

  group('RealGitService', () {
    late RealGitService gitService;
    late String testRepoPath;

    setUpAll(() async {
      gitService = const RealGitService(timeout: Duration(seconds: 5));

      // Use the current project as a real git repo for testing
      // This assumes tests are run from within a git repository
      final result =
          await Process.run('git', ['rev-parse', '--show-toplevel']);
      if (result.exitCode != 0) {
        fail('Tests must be run from within a git repository');
      }
      testRepoPath = (result.stdout as String).trim();
    });

    test('getVersion returns valid version', () async {
      final version = await gitService.getVersion();

      expect(version, isNotEmpty);
      // Version should be in format X.Y.Z or similar
      expect(RegExp(r'^\d+\.\d+').hasMatch(version), true,
          reason: 'Version "$version" should start with X.Y');

      // Major version should be at least 2
      final major = int.parse(version.split('.').first);
      expect(major, greaterThanOrEqualTo(2));
    });

    test('getCurrentBranch returns branch name', () async {
      final branch = await gitService.getCurrentBranch(testRepoPath);

      // Could be null if detached HEAD, but if not null should be non-empty
      if (branch != null) {
        expect(branch, isNotEmpty);
        expect(branch, isNot('HEAD'));
      }
    });

    test('getStatus returns valid status', () async {
      try {
        final status = await gitService.getStatus(testRepoPath);

        // All counts should be non-negative
        expect(status.staged, greaterThanOrEqualTo(0));
        expect(status.unstaged, greaterThanOrEqualTo(0));
        expect(status.untracked, greaterThanOrEqualTo(0));
        expect(status.ahead, greaterThanOrEqualTo(0));
        expect(status.behind, greaterThanOrEqualTo(0));
      } on GitException catch (e) {
        // Skip test if submodule symlink issue in worktrees
        if (e.stderr?.contains('symbolic link') ?? false) {
          markTestSkipped('Skipping: submodule symlink issue in worktree');
          return;
        }
        rethrow;
      }
    });

    test('discoverWorktrees finds at least primary', () async {
      final worktrees = await gitService.discoverWorktrees(testRepoPath);

      expect(worktrees, isNotEmpty);

      // Should have exactly one primary
      final primaries = worktrees.where((w) => w.isPrimary).toList();
      expect(primaries.length, 1,
          reason: 'Should have exactly one primary worktree');
      expect(primaries.first.path, testRepoPath);
    });

    test('findRepoRoot returns path for valid repo', () async {
      final root = await gitService.findRepoRoot(testRepoPath);

      expect(root, testRepoPath);
    });

    test('findRepoRoot returns null for non-repo', () async {
      final root = await gitService.findRepoRoot('/tmp');

      expect(root, null);
    });

    test('throws GitException for invalid path', () async {
      expect(
        () => gitService.getCurrentBranch('/nonexistent/path/xyz'),
        throwsA(isA<GitException>()),
      );
    });

    test('completes within timeout', () async {
      final stopwatch = Stopwatch()..start();

      await gitService.getVersion();
      await gitService.getCurrentBranch(testRepoPath);
      try {
        await gitService.getStatus(testRepoPath);
      } on GitException catch (e) {
        // Skip test if submodule symlink issue in worktrees
        if (e.stderr?.contains('symbolic link') ?? false) {
          markTestSkipped('Skipping: submodule symlink issue in worktree');
          return;
        }
        rethrow;
      }

      stopwatch.stop();

      // All three operations should complete well under the 5s timeout
      expect(stopwatch.elapsedMilliseconds, lessThan(3000),
          reason: 'Git operations should be fast');
    });
  });
}
