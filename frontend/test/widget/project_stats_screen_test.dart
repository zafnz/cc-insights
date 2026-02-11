import 'dart:io';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/models/output_entry.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/timing_stats.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/screens/project_stats_screen.dart';
import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:cc_insights_v2/services/log_service.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';
import 'package:claude_sdk/claude_sdk.dart' show BackendType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late PersistenceService persistence;
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
    tempDir = await Directory.systemTemp.createTemp('project_stats_screen_test_');
    persistence = PersistenceService();
    PersistenceService.setBaseDir(tempDir.path);

    RuntimeConfig.resetForTesting();
    RuntimeConfig.initialize([]);
  });

  tearDown(() async {
    LogService.instance.clearBuffer();
    await cleanupConfig();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ProjectState createMockProject({
    String name = 'Test Project',
    List<_ChatStats>? primaryChats,
  }) {
    final primaryWorktree = WorktreeState(
      WorktreeData(
        worktreeRoot: tempDir.path,
        branch: 'main',
        isPrimary: true,
      ),
    );

    if (primaryChats != null) {
      for (final chatStats in primaryChats) {
        final chatData = ChatData.create(
          name: chatStats.chatName,
          worktreeRoot: tempDir.path,
        );
        final chat = ChatState(chatData);

        // Inject model usage and timing data into the ChatState
        chat.restoreFromMeta(
          const ContextInfo(currentTokens: 0, maxTokens: 200000),
          const UsageInfo.zero(),
          modelUsage: chatStats.modelUsage,
          timing: chatStats.timing,
        );

        // Set the backend type so backendLabel returns correctly
        final backendType = chatStats.backend == 'codex'
            ? BackendType.codex
            : BackendType.directCli;
        chat.setModel(ChatModelCatalog.defaultForBackend(backendType, null));

        primaryWorktree.addChat(chat);
      }
    }

    final project = ProjectState(
      ProjectData(name: name, repoRoot: tempDir.path),
      primaryWorktree,
      autoValidate: false,
      watchFilesystem: false,
    );

    // Clear LogService buffer to cancel the periodic timer created by
    // WorktreeState.addChat() logging. Without this, the fake async zone
    // detects a pending timer and fails the test.
    LogService.instance.clearBuffer();

    return project;
  }

  Widget createTestApp(ProjectState project) {
    final selectionState = SelectionState(project);

    return MultiProvider(
      providers: [
        Provider<PersistenceService>.value(value: persistence),
        ChangeNotifierProvider<SelectionState>.value(value: selectionState),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ProjectStatsScreen()),
      ),
    );
  }

  /// Pumps the widget and allows real async I/O (file system access in
  /// StatsService.buildProjectStats) to complete before returning.
  ///
  /// Also sets a large surface size to accommodate table layouts.
  Future<void> pumpWidgetWithRealAsync(
    WidgetTester tester,
    Widget widget,
  ) async {
    // Set a large enough surface to avoid overflow errors in tables
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      // Give time for StatsService.buildProjectStats to finish file I/O
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // Rebuild the UI with the loaded data
    await tester.pump();
  }

  group('ProjectStatsScreen', () {
    group('Project Overview', () {
      testWidgets('shows project name in header', (tester) async {
        final project = createMockProject(name: 'My Project');
        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        expect(find.text('My Project'), findsOneWidget);
        expect(find.text('Project Stats'), findsOneWidget);
      });

      testWidgets('shows KPI summary cards with formatted values',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 1000000,
                  outputTokens: 500000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 10.50,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 3600000, // 1 hour
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Chat count
        expect(find.text('1'), findsWidgets);
      });

      testWidgets('shows worktree rows with names and stats', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 5.00,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 60000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        expect(find.text('WORKTREES'), findsOneWidget);
        // The worktree name is the basename of the temp directory
        expect(find.textContaining(tempDir.path), findsOneWidget);
      });

      testWidgets('shows cost for codex-only worktrees', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Codex Chat',
              worktree: 'main',
              backend: 'codex',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'o3',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 1.50,
                  contextWindow: 192000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 60000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: false,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Cost should show the estimated value (not a dash)
        expect(find.text('\$1.50'), findsWidgets);
      });

      testWidgets('tapping worktree row transitions to worktree detail',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 5.00,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 60000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Find and tap the chevron icon
        final chevron = find.byIcon(Icons.chevron_right);
        expect(chevron, findsWidgets);
        await tester.tap(chevron.first);
        await safePumpAndSettle(tester);

        // Should now show worktree detail with back button
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.text('Worktree Stats'), findsOneWidget);
      });
    });

    group('Worktree Detail View', () {
      testWidgets('worktree detail shows back button', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 5.00,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 60000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      });

      testWidgets('tapping back returns to project overview', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 5.00,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 60000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Tap back button
        await tester.tap(find.byIcon(Icons.arrow_back));
        await safePumpAndSettle(tester);

        // Should be back on project overview
        expect(find.text('Project Stats'), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsNothing);
      });

      testWidgets('worktree detail shows scoped KPI cards', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000, // 2 minutes
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Check KPI values (cost appears in KPI card, model legend, and table)
        expect(find.textContaining('\$3.25'), findsWidgets);
        expect(find.text('150K'), findsWidgets); // 100K + 50K
      });

      testWidgets('worktree detail shows timing grid', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Chat 1',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000, // 2 minutes
                userResponseMs: 30000, // 30 seconds
                claudeWorkCount: 2,
                userResponseCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.text('TIMING'), findsOneWidget);
        expect(find.text('Agent Working'), findsOneWidget);
        expect(find.text('User Response'), findsOneWidget);
      });

      testWidgets('worktree detail shows chat rows with correct badges',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Active Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.text('CHATS'), findsOneWidget);
        expect(find.text('Active Chat'), findsOneWidget);
        expect(find.text('active'), findsOneWidget);
      });

      testWidgets('tapping chat row transitions to chat detail',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Tap chat row
        final chevrons = find.byIcon(Icons.chevron_right);
        await tester.tap(chevrons.first);
        await safePumpAndSettle(tester);

        // Should now show chat detail
        expect(find.text('Chat Stats'), findsOneWidget);
        expect(find.text('My Chat'), findsOneWidget);
      });
    });

    group('Chat Detail View', () {
      testWidgets('chat detail shows back button returning to worktree',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Should have back button
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);

        // Tap back
        await tester.tap(find.byIcon(Icons.arrow_back));
        await safePumpAndSettle(tester);

        // Should be back at worktree detail
        expect(find.text('Worktree Stats'), findsOneWidget);
      });

      testWidgets('chat detail shows per-model usage table', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 25000,
                  cacheCreationTokens: 10000,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
                const ModelUsageInfo(
                  modelName: 'claude-haiku-4-5-20251001',
                  inputTokens: 20000,
                  outputTokens: 10000,
                  cacheReadTokens: 5000,
                  cacheCreationTokens: 2000,
                  costUsd: 0.50,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.text('MODEL USAGE'), findsOneWidget);
        expect(find.text('Sonnet 4.5'), findsOneWidget);
        expect(find.text('Haiku 4.5'), findsOneWidget);
      });

      testWidgets('chat detail shows timing grid with correct values',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000, // 2 minutes
                userResponseMs: 30000, // 30 seconds
                claudeWorkCount: 5,
                userResponseCount: 3,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.text('TIMING'), findsOneWidget);
        expect(find.text('Work Cycles'), findsOneWidget);
        expect(find.text('User Prompts'), findsOneWidget);
        expect(find.text('5'), findsOneWidget); // Work cycles count
        expect(find.text('3'), findsOneWidget); // User prompts count
      });

      testWidgets('chat detail shows metadata table', (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-sonnet-4-5-20250929',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 3.25,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        expect(find.text('DETAILS'), findsOneWidget);
        expect(find.text('Backend'), findsOneWidget);
        expect(find.text('Worktree'), findsOneWidget);
        expect(find.text('Status'), findsOneWidget);
        expect(find.text('Context Window'), findsOneWidget);
      });

      testWidgets('codex chat shows cost in KPI and model table',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'Codex Chat',
              worktree: 'main',
              backend: 'codex',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'o3',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 2.50,
                  contextWindow: 192000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: false,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Cost should show the estimated value (not a dash)
        expect(find.text('\$2.50'), findsWidgets);
      });

      testWidgets('chat detail shows correct model display names',
          (tester) async {
        final project = createMockProject(
          primaryChats: [
            _ChatStats(
              chatName: 'My Chat',
              worktree: 'main',
              backend: 'claude',
              modelUsage: [
                const ModelUsageInfo(
                  modelName: 'claude-opus-4-6-20260104',
                  inputTokens: 100000,
                  outputTokens: 50000,
                  cacheReadTokens: 0,
                  cacheCreationTokens: 0,
                  costUsd: 10.00,
                  contextWindow: 200000,
                ),
              ],
              timing: const TimingStats(
                claudeWorkingMs: 120000,
                claudeWorkCount: 1,
              ),
              timestamp: DateTime.now().toUtc().toIso8601String(),
              isActive: true,
            ),
          ],
        );

        await pumpWidgetWithRealAsync(tester, createTestApp(project));

        // Navigate to worktree detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Navigate to chat detail
        await tester.tap(find.byIcon(Icons.chevron_right).first);
        await safePumpAndSettle(tester);

        // Should show formatted model name
        expect(find.text('Opus 4.6'), findsOneWidget);
      });
    });

    group('Loading and Error States', () {
      testWidgets('shows loading indicator while data loads', (tester) async {
        final project = createMockProject();

        await tester.pumpWidget(createTestApp(project));
        // Don't wait for settle - check loading state
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });
  });
}

/// Helper type for creating mock chat stats
class _ChatStats {
  final String chatName;
  final String worktree;
  final String backend;
  final List<ModelUsageInfo> modelUsage;
  final TimingStats timing;
  final String timestamp;
  final bool isActive;

  const _ChatStats({
    required this.chatName,
    required this.worktree,
    required this.backend,
    required this.modelUsage,
    required this.timing,
    required this.timestamp,
    required this.isActive,
  });
}
