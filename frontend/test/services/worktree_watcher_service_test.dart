import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/worktree_watcher_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';

void main() {
  late FakeGitService gitService;
  late ProjectState project;
  late WorktreeState worktree;

  const worktreePath = '/fake/repo';
  const repoRoot = '/fake/repo';

  setUp(() {
    gitService = FakeGitService();
    gitService.statuses[worktreePath] = const GitStatus();
    gitService.mainBranches[repoRoot] = 'main';

    project = ProjectState(
      const ProjectData(name: 'test', repoRoot: repoRoot),
      WorktreeState(
        const WorktreeData(
          worktreeRoot: repoRoot,
          isPrimary: true,
          branch: 'main',
        ),
      ),
      autoValidate: false,
      watchFilesystem: false,
    );

    worktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: worktreePath,
        isPrimary: false,
        branch: 'feature',
      ),
    );
  });

  tearDown(() {
    project.dispose();
    worktree.dispose();
  });

  group('periodic polling', () {
    test('polls git status every 30 seconds', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        service.watchWorktree(worktree);

        // The initial poll from watchWorktree
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;
        expect(initialCalls, greaterThan(0));

        // Advance 30 seconds - should trigger periodic poll
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(initialCalls),
        );

        // Advance another 30 seconds - should trigger again
        final afterFirst = gitService.getStatusCalls;
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(afterFirst),
        );

        service.dispose();
      });
    });

    test('does not poll before 30 seconds', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        service.watchWorktree(worktree);
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        // Advance 29 seconds - should NOT trigger periodic poll
        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, equals(initialCalls));

        service.dispose();
      });
    });

    test('stops periodic polling when stopWatching is called', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        service.watchWorktree(worktree);
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        service.stopWatching();

        // Advance 30 seconds - should NOT poll
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, equals(initialCalls));

        service.dispose();
      });
    });

    test('stops periodic polling on dispose', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        service.watchWorktree(worktree);
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        service.dispose();

        // Advance 30 seconds - should NOT poll
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, equals(initialCalls));
      });
    });

    test('restarts periodic polling when switching worktrees', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        final worktree2 = WorktreeState(
          const WorktreeData(
            worktreeRoot: '/fake/repo2',
            isPrimary: false,
            branch: 'other',
          ),
        );
        gitService.statuses['/fake/repo2'] = const GitStatus();

        service.watchWorktree(worktree);
        async.flushMicrotasks();

        // Switch to different worktree at 15s mark
        async.elapse(const Duration(seconds: 15));
        service.watchWorktree(worktree2);
        async.flushMicrotasks();
        final callsAfterSwitch = gitService.getStatusCalls;

        // At 30s from start (15s after switch) - should NOT have fired
        // the old 30s timer
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, equals(callsAfterSwitch));

        // At 45s from start (30s after switch) - should fire new timer
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(callsAfterSwitch),
        );

        worktree2.dispose();
        service.dispose();
      });
    });
  });
}
