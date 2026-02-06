import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/information_panel.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/widgets/base_selector_dialog.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  const repoRoot = '/repo';
  const primaryPath = '/repo';
  const linkedPath = '/repo-wt/feature';

  late FakeGitService gitService;

  setUp(() {
    gitService = FakeGitService();
  });

  /// Builds a test widget tree with the InformationPanel and the
  /// required providers. The [worktreeData] controls the displayed state.
  Widget buildTestWidget({
    required WorktreeData worktreeData,
    WorktreeState? worktreeState,
    String? base,
  }) {
    final primaryWorktreeData = const WorktreeData(
      worktreeRoot: primaryPath,
      isPrimary: true,
      branch: 'main',
    );
    final primaryWorktree = WorktreeState(primaryWorktreeData);

    final wt = worktreeState ??
        WorktreeState(
          worktreeData,
          base: base,
        );

    final project = ProjectState(
      const ProjectData(name: 'test', repoRoot: repoRoot),
      primaryWorktree,
      linkedWorktrees:
          worktreeData.isPrimary ? [] : [wt],
      selectedWorktree:
          worktreeData.isPrimary ? primaryWorktree : wt,
      autoValidate: false,
      watchFilesystem: false,
    );

    final selection = SelectionState(project);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ProjectState>.value(value: project),
        ChangeNotifierProxyProvider<ProjectState, SelectionState>(
          create: (_) => selection,
          update: (_, __, previous) => previous!,
        ),
        Provider<GitService>.value(value: gitService),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: InformationPanel(),
          ),
        ),
      ),
    );
  }

  group('Working Tree section', () {
    testWidgets('shows status counts', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        worktreeData: const WorktreeData(
          worktreeRoot: linkedPath,
          isPrimary: false,
          branch: 'feature',
          uncommittedFiles: 3,
          stagedFiles: 1,
          commitsAhead: 5,
        ),
      ));
      await safePumpAndSettle(tester);

      check(
        find.textContaining('3 / 1 / 5').evaluate(),
      ).isNotEmpty();
    });

    testWidgets(
      'commit button disabled when no changes',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            uncommittedFiles: 0,
            stagedFiles: 0,
          ),
        ));
        await safePumpAndSettle(tester);

        final button = find.byKey(InformationPanelKeys.commitButton);
        check(button.evaluate()).isNotEmpty();

        // Verify the InkWell's onTap is null (disabled)
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: button,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNull();
      },
    );
  });

  group('Base section', () {
    testWidgets('hidden for primary worktree', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        worktreeData: const WorktreeData(
          worktreeRoot: primaryPath,
          isPrimary: true,
          branch: 'main',
        ),
      ));
      await safePumpAndSettle(tester);

      check(
        find.byKey(InformationPanelKeys.baseSection).evaluate(),
      ).isEmpty();
    });

    testWidgets('shows local base with house emoji and local label',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        worktreeData: const WorktreeData(
          worktreeRoot: linkedPath,
          isPrimary: false,
          branch: 'feature',
          baseRef: 'main',
          isRemoteBase: false,
          commitsAheadOfMain: 2,
          commitsBehindMain: 1,
        ),
      ));
      await safePumpAndSettle(tester);

      // Base section visible
      check(
        find.byKey(InformationPanelKeys.baseSection).evaluate(),
      ).isNotEmpty();

      // House emoji for local base
      check(find.text('🏠').evaluate()).isNotEmpty();

      // Combined "local main" text (now using same font)
      check(find.text('local main').evaluate()).isNotEmpty();

      // Ahead/behind indicators (rendered via RichText)
      final richTexts = find.byType(RichText).evaluate();
      final richTextStrings = richTexts
          .map((e) => (e.widget as RichText).text.toPlainText())
          .toList();
      check(richTextStrings).any((it) => it.contains('+2'));
      check(richTextStrings).any((it) => it.contains('-1'));
    });

    testWidgets(
      'shows remote base with globe emoji (no "remote" prefix)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
          ),
        ));
        await safePumpAndSettle(tester);

        // Globe emoji for remote base
        check(find.text('🌐').evaluate()).isNotEmpty();

        // Just "origin/main" (no "remote" prefix since origin/ implies remote)
        check(find.text('origin/main').evaluate()).isNotEmpty();
      },
    );

    testWidgets('Change... button opens BaseSelectorDialog',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        worktreeData: const WorktreeData(
          worktreeRoot: linkedPath,
          isPrimary: false,
          branch: 'feature',
          baseRef: 'main',
          isRemoteBase: false,
        ),
      ));
      await safePumpAndSettle(tester);

      // Tap the Change... button
      await tester
          .tap(find.byKey(InformationPanelKeys.changeBaseButton));
      await tester.pump();

      // The BaseSelectorDialog should be shown
      check(
        find.byKey(BaseSelectorDialogKeys.dialog).evaluate(),
      ).isNotEmpty();
    });
  });

  group('Upstream section', () {
    testWidgets('hidden for primary worktree', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        worktreeData: const WorktreeData(
          worktreeRoot: primaryPath,
          isPrimary: true,
          branch: 'main',
        ),
      ));
      await safePumpAndSettle(tester);

      check(
        find.byKey(InformationPanelKeys.upstreamSection).evaluate(),
      ).isEmpty();
    });

    testWidgets(
      'shows not published when no upstream',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
          ),
        ));
        await safePumpAndSettle(tester);

        check(
          find.text('(not published)').evaluate(),
        ).isNotEmpty();
        check(
          find.byIcon(Icons.cloud_off).evaluate(),
        ).isNotEmpty();
      },
    );

    testWidgets(
      'shows upstream branch when published',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAhead: 3,
            commitsBehind: 2,
          ),
        ));
        await safePumpAndSettle(tester);

        check(
          find.text('origin/feature').evaluate(),
        ).isNotEmpty();
        check(find.byIcon(Icons.cloud).evaluate()).isNotEmpty();
      },
    );
  });

  group('Actions - local base', () {
    testWidgets(
      'shows correct buttons for local base state',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            commitsAheadOfMain: 2,
            commitsBehindMain: 1,
          ),
        ));
        await safePumpAndSettle(tester);

        // Rebase and merge buttons visible
        check(
          find
              .byKey(InformationPanelKeys.rebaseOntoBaseButton)
              .evaluate(),
        ).isNotEmpty();
        check(
          find
              .byKey(InformationPanelKeys.mergeBaseButton)
              .evaluate(),
        ).isNotEmpty();

        // Merge branch into main button visible
        check(
          find
              .byKey(
                  InformationPanelKeys.mergeBranchIntoMainButton)
              .evaluate(),
        ).isNotEmpty();

        // Push, Pull/Rebase, Create PR not visible
        check(
          find.byKey(InformationPanelKeys.pushButton).evaluate(),
        ).isEmpty();
        check(
          find
              .byKey(InformationPanelKeys.pullRebaseButton)
              .evaluate(),
        ).isEmpty();
        check(
          find
              .byKey(InformationPanelKeys.createPrButton)
              .evaluate(),
        ).isEmpty();
      },
    );

    testWidgets(
      'merge into main disabled when behind',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            commitsAheadOfMain: 2,
            commitsBehindMain: 1,
          ),
        ));
        await safePumpAndSettle(tester);

        final button = find.byKey(
          InformationPanelKeys.mergeBranchIntoMainButton,
        );
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: button,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNull();
      },
    );

    testWidgets(
      'merge into main enabled when ahead and not behind',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            commitsAheadOfMain: 2,
            commitsBehindMain: 0,
          ),
        ));
        await safePumpAndSettle(tester);

        final button = find.byKey(
          InformationPanelKeys.mergeBranchIntoMainButton,
        );
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: button,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNotNull();
      },
    );
  });

  group('Actions - remote base, no upstream', () {
    testWidgets(
      'shows push and disabled create PR',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            // No upstream
            commitsAheadOfMain: 3,
            commitsBehindMain: 0,
          ),
        ));
        await safePumpAndSettle(tester);

        // Push button present and enabled (publish is always enabled)
        final pushButton =
            find.byKey(InformationPanelKeys.pushButton);
        check(pushButton.evaluate()).isNotEmpty();
        final pushInkWell = tester.widget<InkWell>(
          find.descendant(
            of: pushButton,
            matching: find.byType(InkWell),
          ),
        );
        check(pushInkWell.onTap).isNotNull();

        // Create PR button present but disabled
        final prButton =
            find.byKey(InformationPanelKeys.createPrButton);
        check(prButton.evaluate()).isNotEmpty();
        final prInkWell = tester.widget<InkWell>(
          find.descendant(
            of: prButton,
            matching: find.byType(InkWell),
          ),
        );
        check(prInkWell.onTap).isNull();

        // Merge branch into main not visible
        check(
          find
              .byKey(
                  InformationPanelKeys.mergeBranchIntoMainButton)
              .evaluate(),
        ).isEmpty();

        // Pull/Rebase not visible
        check(
          find
              .byKey(InformationPanelKeys.pullRebaseButton)
              .evaluate(),
        ).isEmpty();
      },
    );
  });

  group('Actions - remote base, has upstream', () {
    testWidgets(
      'shows push, pull/rebase, and create PR',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAhead: 2,
            commitsBehind: 1,
            commitsAheadOfMain: 5,
          ),
        ));
        await safePumpAndSettle(tester);

        // Push button present
        check(
          find.byKey(InformationPanelKeys.pushButton).evaluate(),
        ).isNotEmpty();

        // Pull/Rebase button present
        check(
          find
              .byKey(InformationPanelKeys.pullRebaseButton)
              .evaluate(),
        ).isNotEmpty();

        // Create PR button present
        check(
          find
              .byKey(InformationPanelKeys.createPrButton)
              .evaluate(),
        ).isNotEmpty();

        // Merge branch into main not visible
        check(
          find
              .byKey(
                  InformationPanelKeys.mergeBranchIntoMainButton)
              .evaluate(),
        ).isEmpty();
      },
    );

    testWidgets(
      'push disabled when nothing ahead of upstream',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAhead: 0,
            commitsBehind: 1,
            commitsAheadOfMain: 5,
          ),
        ));
        await safePumpAndSettle(tester);

        final pushButton =
            find.byKey(InformationPanelKeys.pushButton);
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: pushButton,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNull();
      },
    );

    testWidgets(
      'pull/rebase disabled when not behind upstream',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAhead: 2,
            commitsBehind: 0,
            commitsAheadOfMain: 5,
          ),
        ));
        await safePumpAndSettle(tester);

        final pullButton =
            find.byKey(InformationPanelKeys.pullRebaseButton);
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: pullButton,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNull();
      },
    );

    testWidgets(
      'create PR disabled when no commits ahead of main',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAheadOfMain: 0,
          ),
        ));
        await safePumpAndSettle(tester);

        final prButton =
            find.byKey(InformationPanelKeys.createPrButton);
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: prButton,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNull();
      },
    );

    testWidgets(
      'create PR enabled when ahead of main and has upstream',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'origin/main',
            isRemoteBase: true,
            upstreamBranch: 'origin/feature',
            commitsAheadOfMain: 3,
          ),
        ));
        await safePumpAndSettle(tester);

        final prButton =
            find.byKey(InformationPanelKeys.createPrButton);
        final inkWell = tester.widget<InkWell>(
          find.descendant(
            of: prButton,
            matching: find.byType(InkWell),
          ),
        );
        check(inkWell.onTap).isNotNull();
      },
    );
  });

  group('Rebase/Merge enable/disable', () {
    testWidgets(
      'rebase and merge disabled when not behind main',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            commitsBehindMain: 0,
          ),
        ));
        await safePumpAndSettle(tester);

        final rebaseButton =
            find.byKey(InformationPanelKeys.rebaseOntoBaseButton);
        final rebaseInkWell = tester.widget<InkWell>(
          find.descendant(
            of: rebaseButton,
            matching: find.byType(InkWell),
          ),
        );
        check(rebaseInkWell.onTap).isNull();

        final mergeButton =
            find.byKey(InformationPanelKeys.mergeBaseButton);
        final mergeInkWell = tester.widget<InkWell>(
          find.descendant(
            of: mergeButton,
            matching: find.byType(InkWell),
          ),
        );
        check(mergeInkWell.onTap).isNull();
      },
    );

    testWidgets(
      'rebase and merge enabled when behind main',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            commitsBehindMain: 3,
          ),
        ));
        await safePumpAndSettle(tester);

        final rebaseButton =
            find.byKey(InformationPanelKeys.rebaseOntoBaseButton);
        final rebaseInkWell = tester.widget<InkWell>(
          find.descendant(
            of: rebaseButton,
            matching: find.byType(InkWell),
          ),
        );
        check(rebaseInkWell.onTap).isNotNull();

        final mergeButton =
            find.byKey(InformationPanelKeys.mergeBaseButton);
        final mergeInkWell = tester.widget<InkWell>(
          find.descendant(
            of: mergeButton,
            matching: find.byType(InkWell),
          ),
        );
        check(mergeInkWell.onTap).isNotNull();
      },
    );
  });

  group('Conflict section', () {
    testWidgets(
      'shows conflict banner instead of actions',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: linkedPath,
            isPrimary: false,
            branch: 'feature',
            baseRef: 'main',
            isRemoteBase: false,
            hasMergeConflict: true,
            conflictOperation: MergeOperationType.rebase,
          ),
        ));
        await safePumpAndSettle(tester);

        // Conflict banner is shown
        check(
          find.textContaining('Rebase conflict').evaluate(),
        ).isNotEmpty();

        // Action buttons are NOT shown
        check(
          find
              .byKey(InformationPanelKeys.rebaseOntoBaseButton)
              .evaluate(),
        ).isEmpty();
      },
    );
  });

  group('No worktree selected', () {
    testWidgets('shows placeholder message', (tester) async {
      final primaryWorktreeData = const WorktreeData(
        worktreeRoot: primaryPath,
        isPrimary: true,
        branch: 'main',
      );
      final primaryWorktree =
          WorktreeState(primaryWorktreeData);

      final project = ProjectState(
        const ProjectData(name: 'test', repoRoot: repoRoot),
        primaryWorktree,
        selectedWorktree: null,
        autoValidate: false,
        watchFilesystem: false,
      );
      final selection = SelectionState(project);

      // Deselect the worktree
      project.selectWorktree(null);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProjectState>.value(
              value: project,
            ),
            ChangeNotifierProxyProvider<ProjectState,
                SelectionState>(
              create: (_) => selection,
              update: (_, __, previous) => previous!,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 800,
                child: InformationPanel(),
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      check(
        find
            .text('Select a worktree to view information')
            .evaluate(),
      ).isNotEmpty();
    });
  });

  group('Primary worktree', () {
    testWidgets(
      'shows only working tree section for primary',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          worktreeData: const WorktreeData(
            worktreeRoot: primaryPath,
            isPrimary: true,
            branch: 'main',
            uncommittedFiles: 2,
          ),
        ));
        await safePumpAndSettle(tester);

        // Working tree section visible (status counts shown, no label)
        check(find.textContaining('Uncommitted').evaluate()).isNotEmpty();

        // Base and upstream sections not visible
        check(
          find.byKey(InformationPanelKeys.baseSection).evaluate(),
        ).isEmpty();
        check(
          find
              .byKey(InformationPanelKeys.upstreamSection)
              .evaluate(),
        ).isEmpty();

        // Action buttons not visible
        check(
          find
              .byKey(InformationPanelKeys.rebaseOntoBaseButton)
              .evaluate(),
        ).isEmpty();
      },
    );
  });
}
