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
  late WorktreeState primaryWorktree;

  const repoRoot = '/fake/repo';

  setUp(() {
    gitService = FakeGitService();
    gitService.statuses[repoRoot] = const GitStatus();
    gitService.mainBranches[repoRoot] = 'main';

    primaryWorktree = WorktreeState(
      const WorktreeData(
        worktreeRoot: repoRoot,
        isPrimary: true,
        branch: 'main',
      ),
    );

    project = ProjectState(
      const ProjectData(name: 'test', repoRoot: repoRoot),
      primaryWorktree,
      autoValidate: false,
      watchFilesystem: false,
    );
  });

  tearDown(() {
    project.dispose();
  });

  group('automatic syncing', () {
    test('polls all worktrees on construction', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        // Flush the initial poll for the primary worktree.
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, greaterThan(0));

        service.dispose();
      });
    });

    test('starts polling when worktree added to project', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        // Add a linked worktree.
        const linkedPath = '/fake/linked';
        gitService.statuses[linkedPath] = const GitStatus();
        final linked = WorktreeState(
          const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
          ),
        );
        project.addWorktree(linked);

        // The sync triggers an immediate poll for the new wt.
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(initialCalls),
        );

        service.dispose();
      });
    });

    test('stops polling when worktree removed from project', () {
      fakeAsync((async) {
        // Start with a linked worktree.
        const linkedPath = '/fake/linked';
        gitService.statuses[linkedPath] = const GitStatus();
        final linked = WorktreeState(
          const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
          ),
        );
        project.addWorktree(linked);

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );
        async.flushMicrotasks();

        // Remove the linked worktree.
        project.removeLinkedWorktree(linked);
        async.flushMicrotasks();
        final callsAfterRemove = gitService.getStatusCalls;

        // Advance 30s — only primary should poll, not linked.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        // The linked worktree's timer should be cancelled.
        // We should see exactly one poll (primary), not two.
        final pollsSinceRemove =
            gitService.getStatusCalls - callsAfterRemove;
        // Primary polls once at 30s.
        expect(pollsSinceRemove, 1);

        service.dispose();
      });
    });
  });

  group('periodic polling', () {
    test('polls git status every 30 seconds', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(initialCalls),
        );

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

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        async.elapse(const Duration(seconds: 29));
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

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        service.dispose();

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, equals(initialCalls));
      });
    });

    test('polls multiple worktrees independently', () {
      fakeAsync((async) {
        const linkedPath = '/fake/linked';
        gitService.statuses[linkedPath] = const GitStatus();
        final linked = WorktreeState(
          const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
          ),
        );
        project.addWorktree(linked);

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;
        // Should have polled both worktrees.
        expect(initialCalls, greaterThanOrEqualTo(2));

        // After 30s, both should poll again.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThanOrEqualTo(initialCalls + 2),
        );

        service.dispose();
      });
    });
  });
}
