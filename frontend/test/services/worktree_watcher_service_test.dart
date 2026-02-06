import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/worktree_watcher_service.dart';
import 'package:checks/checks.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../fakes/fake_project_config_service.dart';

void main() {
  late FakeGitService gitService;
  late FakeProjectConfigService configService;
  late ProjectState project;
  late WorktreeState primaryWorktree;

  const repoRoot = '/fake/repo';

  setUp(() {
    gitService = FakeGitService();
    gitService.statuses[repoRoot] = const GitStatus();
    gitService.mainBranches[repoRoot] = 'main';

    configService = FakeProjectConfigService();

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
          configService: configService,
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
          configService: configService,
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
          configService: configService,
        );
        async.flushMicrotasks();

        // Remove the linked worktree.
        project.removeLinkedWorktree(linked);
        async.flushMicrotasks();
        final callsAfterRemove = gitService.getStatusCalls;

        // Advance 2min — only primary should poll, not linked.
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        // The linked worktree's timer should be cancelled.
        // We should see only primary polls, not linked. The primary
        // gets polled twice at 2min: once from its periodic timer and
        // once from the fetch timer's forceRefreshAll.
        final pollsSinceRemove =
            gitService.getStatusCalls - callsAfterRemove;
        expect(pollsSinceRemove, 2);

        service.dispose();
      });
    });
  });

  group('common git directory watcher', () {
    test('git dir change triggers refresh of all worktrees', () {
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
          configService: configService,
        );
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        // Simulate a git dir change.
        service.onGitDirChanged();
        async.flushMicrotasks();

        // Should poll both worktrees (primary + linked).
        expect(gitService.getStatusCalls, initialCalls + 2);

        service.dispose();
      });
    });

    test('git dir changes are throttled at 5-second interval', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        // First change triggers immediately.
        service.onGitDirChanged();
        async.flushMicrotasks();
        final afterFirst = gitService.getStatusCalls;
        expect(afterFirst, greaterThan(initialCalls));

        // Second change within 5s is throttled.
        service.onGitDirChanged();
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, afterFirst);

        // After 5 seconds, the pending poll fires.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, greaterThan(afterFirst));

        service.dispose();
      });
    });

    test('git dir change after dispose is ignored', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );
        async.flushMicrotasks();
        final callsBeforeDispose = gitService.getStatusCalls;

        service.dispose();

        // Should not throw or trigger any polls.
        service.onGitDirChanged();
        async.flushMicrotasks();
        expect(gitService.getStatusCalls, callsBeforeDispose);
      });
    });

    test('forceRefreshAll polls all worktrees', () {
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
          configService: configService,
        );
        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        service.forceRefreshAll();
        async.flushMicrotasks();

        expect(gitService.getStatusCalls, initialCalls + 2);

        service.dispose();
      });
    });
  });

  group('periodic polling', () {
    test('polls git status every 2 minutes', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(initialCalls),
        );

        final afterFirst = gitService.getStatusCalls;
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThan(afterFirst),
        );

        service.dispose();
      });
    });

    test('does not poll before 2 minutes', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        async.elapse(const Duration(seconds: 119));
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
          configService: configService,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;

        service.dispose();

        async.elapse(const Duration(minutes: 2));
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
          configService: configService,
        );

        async.flushMicrotasks();
        final initialCalls = gitService.getStatusCalls;
        // Should have polled both worktrees.
        expect(initialCalls, greaterThanOrEqualTo(2));

        // After 2min, both should poll again.
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        expect(
          gitService.getStatusCalls,
          greaterThanOrEqualTo(initialCalls + 2),
        );

        service.dispose();
      });
    });
  });

  group('periodic fetch', () {
    test('periodic fetch is not started when enablePeriodicPolling '
        'is false', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final initialFetchCalls = gitService.fetchCalls.length;

        // Advance past the fetch interval.
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();

        // No fetch should have been triggered.
        check(gitService.fetchCalls.length).equals(initialFetchCalls);

        service.dispose();
      });
    });

    test('periodic fetch fires at 2-minute intervals', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );
        async.flushMicrotasks();
        final initialFetchCalls = gitService.fetchCalls.length;

        // Before 2 minutes: no fetch yet.
        async.elapse(const Duration(seconds: 119));
        async.flushMicrotasks();
        check(gitService.fetchCalls.length).equals(initialFetchCalls);

        // At 2 minutes: fetch fires.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        check(gitService.fetchCalls.length)
            .equals(initialFetchCalls + 1);

        // At 4 minutes: second fetch fires.
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
        check(gitService.fetchCalls.length)
            .equals(initialFetchCalls + 2);

        service.dispose();
      });
    });

    test('fetchOrigin calls gitService.fetch with repo root path',
        () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final initialFetchCalls = gitService.fetchCalls.length;

        service.fetchOrigin();
        async.flushMicrotasks();

        check(gitService.fetchCalls.length)
            .equals(initialFetchCalls + 1);
        check(gitService.fetchCalls.last).equals(repoRoot);

        service.dispose();
      });
    });

    test('fetchOrigin triggers forceRefreshAll after fetch', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final initialStatusCalls = gitService.getStatusCalls;

        service.fetchOrigin();
        async.flushMicrotasks();

        // forceRefreshAll polls all worktrees (1 primary).
        check(gitService.getStatusCalls)
            .isGreaterThan(initialStatusCalls);

        service.dispose();
      });
    });

    test('fetchOrigin refreshes all worktrees including linked', () {
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
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final initialStatusCalls = gitService.getStatusCalls;

        service.fetchOrigin();
        async.flushMicrotasks();

        // Should poll both worktrees (primary + linked).
        check(gitService.getStatusCalls)
            .equals(initialStatusCalls + 2);

        service.dispose();
      });
    });

    test('fetch failure does not crash the service', () {
      fakeAsync((async) {
        gitService.fetchError = const GitException(
          'Network timeout',
          command: 'git fetch',
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final initialStatusCalls = gitService.getStatusCalls;

        // Should not throw.
        service.fetchOrigin();
        async.flushMicrotasks();

        // Fetch was attempted.
        check(gitService.fetchCalls).isNotEmpty();

        // forceRefreshAll still runs after a failed fetch.
        check(gitService.getStatusCalls)
            .isGreaterThan(initialStatusCalls);

        service.dispose();
      });
    });

    test('fetch timer is cancelled on dispose', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
        );
        async.flushMicrotasks();
        final fetchCallsAtDispose = gitService.fetchCalls.length;

        service.dispose();

        // Advance past the fetch interval.
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();

        // No fetch should fire after dispose.
        check(gitService.fetchCalls.length)
            .equals(fetchCallsAtDispose);
      });
    });

    test('fetchOrigin sets lastFetchTime', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        check(service.lastFetchTime).isNull();

        service.fetchOrigin();
        async.flushMicrotasks();

        check(service.lastFetchTime).isNotNull();

        service.dispose();
      });
    });

    test('fetchOrigin after dispose is a no-op', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();
        final fetchCallsBeforeDispose = gitService.fetchCalls.length;

        service.dispose();

        service.fetchOrigin();
        async.flushMicrotasks();

        check(gitService.fetchCalls.length)
            .equals(fetchCallsBeforeDispose);
      });
    });
  });

  group('base ref resolution', () {
    late WorktreeState featureWorktree;

    setUp(() {
      const linkedPath = '/fake/linked';
      gitService.statuses[linkedPath] = const GitStatus();

      featureWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: linkedPath,
          isPrimary: false,
          branch: 'feature',
        ),
      );
      project.addWorktree(featureWorktree);
    });

    test('uses worktree base when set', () {
      fakeAsync((async) {
        featureWorktree.setBase('develop');

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('develop');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('worktree base with remote ref sets isRemoteBase', () {
      fakeAsync((async) {
        featureWorktree.setBase('origin/develop');

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('origin/develop');
          check(resolved.isRemoteBase).equals(true);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('worktree base with remotes/ prefix sets isRemoteBase',
        () {
      fakeAsync((async) {
        featureWorktree.setBase('remotes/origin/main');

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result =
            service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('remotes/origin/main');
          check(resolved.isRemoteBase).equals(true);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('falls back to project defaultBase when no worktree override',
        () {
      fakeAsync((async) {
        configService.configs[repoRoot] = const ProjectConfig(
          defaultBase: 'develop',
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('develop');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('project defaultBase with remote ref sets isRemoteBase', () {
      fakeAsync((async) {
        configService.configs[repoRoot] = const ProjectConfig(
          defaultBase: 'origin/main',
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('origin/main');
          check(resolved.isRemoteBase).equals(true);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('project defaultBase "auto" falls through to auto-detect', () {
      fakeAsync((async) {
        configService.configs[repoRoot] = const ProjectConfig(
          defaultBase: 'auto',
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          // Auto-detect should find local main (no upstream).
          check(resolved.baseRef).equals('main');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('worktree base takes priority over project defaultBase',
        () {
      fakeAsync((async) {
        featureWorktree.setBase('release/1.0');
        configService.configs[repoRoot] = const ProjectConfig(
          defaultBase: 'develop',
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('release/1.0');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('auto-detect uses remote main when upstream exists', () {
      fakeAsync((async) {
        gitService.remoteMainBranches[repoRoot] = 'origin/main';

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(
          featureWorktree,
          'origin/feature',
        );
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('origin/main');
          check(resolved.isRemoteBase).equals(true);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('auto-detect uses local main when no upstream', () {
      fakeAsync((async) {
        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result =
            service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('main');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test(
        'auto-detect falls back to local main when upstream exists '
        'but no remote main found', () {
      fakeAsync((async) {
        // upstream exists but no remote main branch configured
        gitService.remoteMainBranches.clear();

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result = service.resolveBaseRef(
          featureWorktree,
          'origin/feature',
        );
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('main');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('config load failure falls through to auto-detect', () {
      fakeAsync((async) {
        configService.shouldThrow = true;

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        final result =
            service.resolveBaseRef(featureWorktree, null);
        async.flushMicrotasks();

        result.then((resolved) {
          check(resolved.baseRef).equals('main');
          check(resolved.isRemoteBase).equals(false);
        });
        async.flushMicrotasks();

        service.dispose();
      });
    });

    test('poll updates worktree data with resolved base ref', () {
      fakeAsync((async) {
        featureWorktree.setBase('origin/develop');

        gitService.branchComparisons[
            '/fake/linked:feature:origin/develop'] = (
          ahead: 3,
          behind: 1,
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        // After initial poll, the worktree data should reflect
        // the override base ref.
        check(featureWorktree.data.baseRef)
            .equals('origin/develop');
        check(featureWorktree.data.isRemoteBase).equals(true);
        check(featureWorktree.data.commitsAheadOfMain).equals(3);
        check(featureWorktree.data.commitsBehindMain).equals(1);

        service.dispose();
      });
    });

    test('poll uses project default when no worktree override', () {
      fakeAsync((async) {
        configService.configs[repoRoot] = const ProjectConfig(
          defaultBase: 'develop',
        );

        gitService.branchComparisons[
            '/fake/linked:feature:develop'] = (
          ahead: 5,
          behind: 2,
        );

        final service = WorktreeWatcherService(
          gitService: gitService,
          project: project,
          configService: configService,
          enablePeriodicPolling: false,
        );
        async.flushMicrotasks();

        check(featureWorktree.data.baseRef).equals('develop');
        check(featureWorktree.data.isRemoteBase).equals(false);
        check(featureWorktree.data.commitsAheadOfMain).equals(5);
        check(featureWorktree.data.commitsBehindMain).equals(2);

        service.dispose();
      });
    });
  });
}
