import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/ask_ai_service.dart';
import '../services/backend_service.dart';
import '../services/file_system_service.dart';
import '../services/git_service.dart';
import '../services/persistence_service.dart';
import '../services/project_restore_service.dart';
import '../services/runtime_config.dart';
import '../services/sdk_message_handler.dart';
import '../services/worktree_watcher_service.dart';
import '../state/selection_state.dart';
import '../widgets/base_selector_dialog.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/commit_dialog.dart';
import '../widgets/conflict_resolution_dialog.dart';
import '../widgets/create_pr_dialog.dart';
import 'panel_wrapper.dart';

/// Keys for testing InformationPanel widgets.
class InformationPanelKeys {
  InformationPanelKeys._();

  static const commitButton = Key('info_panel_commit');
  static const changeBaseButton = Key('info_panel_change_base');
  static const rebaseOntoBaseButton = Key('info_panel_rebase_onto_base');
  static const mergeBaseButton = Key('info_panel_merge_base');
  static const mergeBranchIntoMainButton =
      Key('info_panel_merge_branch_into_main');
  static const pushButton = Key('info_panel_push');
  static const pullRebaseButton = Key('info_panel_pull_rebase');
  static const createPrButton = Key('info_panel_create_pr');
  static const baseSection = Key('info_panel_base_section');
  static const upstreamSection = Key('info_panel_upstream_section');
}

/// Information panel - shows git branch/status info for the selected worktree.
class InformationPanel extends StatelessWidget {
  const InformationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    // Show branch name in header, or fallback to "Information"
    final title = worktree?.data.branch ?? 'Information';

    return PanelWrapper(
      title: title,
      icon: Icons.call_split,
      child: const _InformationContent(),
    );
  }
}

class _InformationContent extends StatelessWidget {
  const _InformationContent();

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    if (worktree == null) {
      return const _NoWorktreeSelected();
    }

    return ListenableBuilder(
      listenable: worktree,
      builder: (context, _) => _WorktreeInfo(
        worktree: worktree,
        onStatusChanged: () {
          // Force an immediate refresh of the git status
          try {
            final watcher =
                context.read<WorktreeWatcherService>();
            watcher.forceRefresh(worktree);
          } catch (_) {
            // Provider not available (e.g., in tests)
          }
        },
      ),
    );
  }
}

class _NoWorktreeSelected extends StatelessWidget {
  const _NoWorktreeSelected();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Select a worktree to view information',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WorktreeInfo extends StatelessWidget {
  const _WorktreeInfo({
    required this.worktree,
    required this.onStatusChanged,
  });

  final WorktreeState worktree;
  final VoidCallback onStatusChanged;

  WorktreeData get data => worktree.data;
  String get worktreeRoot => data.worktreeRoot;

  Future<void> _showCommitDialog(BuildContext context) async {
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final fileSystemService = context.read<FileSystemService>();

    final committed = await showCommitDialog(
      context: context,
      worktreePath: worktreeRoot,
      gitService: gitService,
      askAiService: askAiService,
      fileSystemService: fileSystemService,
    );

    if (committed) {
      onStatusChanged();
    }
  }

  Future<void> _handleUpdateFromBase(
    BuildContext context,
    MergeOperationType operation,
  ) async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();
    final baseRef = data.baseRef ?? 'main';

    if (!context.mounted) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: baseRef,
      operation: operation,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final mainWorktreePath =
          project.primaryWorktree.data.worktreeRoot;

      await _openConflictManagerChat(
        context,
        branch: data.branch,
        mainBranch: baseRef,
        worktreePath: worktreeRoot,
        mainWorktreePath: mainWorktreePath,
        operation: operation,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleMergeIntoMain(BuildContext context) async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    // Detect main branch
    String? mainBranch;
    try {
      mainBranch =
          await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to detect main branch: $e')),
      );
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect main branch')),
      );
      return;
    }

    if (!context.mounted) return;

    // Merge the current branch into main, running in the primary
    // worktree directory (since we can't checkout main in a worktree
    // where another branch is checked out).
    final primaryWorktreePath =
        project.primaryWorktree.data.worktreeRoot;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: primaryWorktreePath,
      branch: mainBranch,
      mainBranch: data.branch,
      operation: MergeOperationType.merge,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      await _openConflictManagerChat(
        context,
        branch: mainBranch,
        mainBranch: data.branch,
        worktreePath: primaryWorktreePath,
        mainWorktreePath: primaryWorktreePath,
        operation: MergeOperationType.merge,
      );
    }

    onStatusChanged();
  }

  Future<void> _handlePush(
    BuildContext context, {
    bool setUpstream = false,
  }) async {
    final gitService = context.read<GitService>();
    try {
      await gitService.push(worktreeRoot, setUpstream: setUpstream);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Push failed: $e')),
      );
      return;
    }
    onStatusChanged();
  }

  Future<void> _handlePullRebase(BuildContext context) async {
    final gitService = context.read<GitService>();
    final project = context.read<ProjectState>();

    try {
      await gitService.fetch(worktreeRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fetch failed: $e')),
      );
      return;
    }

    if (!context.mounted) return;

    final upstream = data.upstreamBranch;
    if (upstream == null) return;

    final result = await showConflictResolutionDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: upstream,
      operation: MergeOperationType.rebase,
      gitService: gitService,
    );

    if (!context.mounted) return;

    if (result == ConflictResolutionResult.resolveWithClaude) {
      final mainWorktreePath =
          project.primaryWorktree.data.worktreeRoot;

      await _openConflictManagerChat(
        context,
        branch: data.branch,
        mainBranch: upstream,
        worktreePath: worktreeRoot,
        mainWorktreePath: mainWorktreePath,
        operation: MergeOperationType.rebase,
      );
    }

    onStatusChanged();
  }

  Future<void> _handleCreatePr(BuildContext context) async {
    final gitService = context.read<GitService>();
    final askAiService = context.read<AskAiService>();
    final project = context.read<ProjectState>();

    // Check gh is installed
    final ghInstalled = await gitService.isGhInstalled();
    if (!ghInstalled) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GitHub CLI (gh) is not installed. '
            'Install it from https://cli.github.com',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    // Detect main branch
    String? mainBranch;
    try {
      mainBranch =
          await gitService.getMainBranch(project.data.repoRoot);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to detect main branch: $e')),
      );
      return;
    }

    if (mainBranch == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect main branch')),
      );
      return;
    }

    if (!context.mounted) return;

    final created = await showCreatePrDialog(
      context: context,
      worktreePath: worktreeRoot,
      branch: data.branch,
      mainBranch: mainBranch,
      gitService: gitService,
      askAiService: askAiService,
    );

    if (created) {
      onStatusChanged();
    }
  }

  Future<void> _handleChangeBase(BuildContext context) async {
    final previousValue = worktree.baseOverride;
    final result = await showBaseSelectorDialog(
      context,
      currentBaseOverride: previousValue,
    );

    if (!context.mounted) return;

    // Both cancel and "project default" return null. Only apply if
    // the result differs from the previous value.
    if (result == previousValue) return;

    worktree.setBaseOverride(result);

    try {
      final project = context.read<ProjectState>();
      final persistence = context.read<PersistenceService>();
      persistence.updateWorktreeBaseOverride(
        projectRoot: project.data.repoRoot,
        worktreePath: worktreeRoot,
        baseOverride: result,
      );
    } catch (_) {
      // PersistenceService may not be available in tests
    }

    onStatusChanged();
  }

  Future<void> _openConflictManagerChat(
    BuildContext context, {
    required String branch,
    required String mainBranch,
    required String worktreePath,
    required String mainWorktreePath,
    required MergeOperationType operation,
  }) async {
    final selection = context.read<SelectionState>();
    final project = context.read<ProjectState>();
    final backend = context.read<BackendService>();
    final messageHandler = context.read<SdkMessageHandler>();
    final restoreService = context.read<ProjectRestoreService>();
    final wt = selection.selectedWorktree;
    if (wt == null) return;

    final operationName =
        operation == MergeOperationType.rebase ? 'rebasing' : 'merging';

    // Build the preamble (sent to Claude but NOT shown in UI)
    final preamble = 'The user is $operationName this child branch '
        '($branch) onto its parent ($mainBranch), and has '
        'encountered a number of merge conflicts. You are to resolve '
        'the conflicts where the solution is obvious go ahead. If '
        'the conflict is not obvious or you may break something STOP '
        'and advise the user.\n'
        'Rules:\n'
        '- Do NOT use origin, only local.\n'
        '- This branch is $branch: $worktreePath\n'
        '- Parent is $mainBranch: $mainWorktreePath\n'
        '- Do NOT do destructive edits\n'
        '- Always ask the user if it is a complicated conflict '
        'resolution.\n\n'
        'Now analyse the conflict and begin work resolving it.';

    // Create the chat
    final chatName = 'Conflict: $operationName $branch '
        'onto $mainBranch';
    final chatData = ChatData.create(
      name: chatName,
      worktreeRoot: worktreePath,
      isAutoGeneratedName: false,
    );
    final chat = ChatState(chatData);

    // Set the model to the AI assistance model
    final aiModel = RuntimeConfig.instance.aiAssistanceModel;
    if (aiModel != 'disabled') {
      final backend = RuntimeConfig.instance.defaultBackend;
      chat.setModel(
        ChatModelCatalog.defaultForBackend(backend, aiModel),
      );
    }

    // Add to worktree and select it
    wt.addChat(chat, select: true);
    selection.selectChat(chat);

    // Persist the new chat (fire-and-forget)
    restoreService
        .addChatToWorktree(
          project.data.repoRoot,
          wt.data.worktreeRoot,
          chat,
        )
        .catchError((error) {
      developer.log(
        'Failed to persist conflict chat: $error',
        name: 'InformationPanel',
        level: 900,
      );
    });

    // Start the session with the preamble as the prompt.
    // We do NOT add a UserInputEntry so the preamble is invisible.
    try {
      await chat.startSession(
        backend: backend,
        messageHandler: messageHandler,
        prompt: preamble,
      );
    } catch (e) {
      chat.addEntry(TextOutputEntry(
        timestamp: DateTime.now(),
        text: 'Failed to start conflict resolution session: $e',
        contentType: 'error',
      ));
    }
  }

  Future<void> _handleAbortConflict(BuildContext context) async {
    final gitService = context.read<GitService>();
    final operation = data.conflictOperation;
    try {
      if (operation == MergeOperationType.rebase) {
        await gitService.rebaseAbort(worktreeRoot);
      } else {
        await gitService.mergeAbort(worktreeRoot);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to abort: $e')),
      );
    }
    onStatusChanged();
  }

  Future<void> _handleContinueConflict(
    BuildContext context,
  ) async {
    final gitService = context.read<GitService>();
    final operation = data.conflictOperation;
    try {
      if (operation == MergeOperationType.rebase) {
        await gitService.rebaseContinue(worktreeRoot);
      } else {
        await gitService.mergeContinue(worktreeRoot);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to continue: $e')),
      );
    }
    onStatusChanged();
  }

  Future<void> _handleAskClaudeConflict(
    BuildContext context,
  ) async {
    final project = context.read<ProjectState>();
    final mainBranch = await context
        .read<GitService>()
        .getMainBranch(project.data.repoRoot);
    if (!context.mounted) return;

    final operation =
        data.conflictOperation ?? MergeOperationType.merge;
    final mainWorktreePath =
        project.primaryWorktree.data.worktreeRoot;

    await _openConflictManagerChat(
      context,
      branch: data.branch,
      mainBranch: mainBranch ?? 'main',
      worktreePath: worktreeRoot,
      mainWorktreePath: mainWorktreePath,
      operation: operation,
    );
  }

  // -- Enable/disable logic --

  bool get _canUpdateFromBase =>
      data.commitsBehindMain > 0 && !data.isPrimary;

  bool get _canMergeIntoMain =>
      data.commitsAheadOfMain > 0 &&
      data.commitsBehindMain == 0 &&
      !data.isPrimary;

  bool get _canPush =>
      data.upstreamBranch != null && data.commitsAhead > 0;

  bool get _canPullRebase =>
      data.upstreamBranch != null && data.commitsBehind > 0;

  bool get _canCreatePr =>
      data.commitsAheadOfMain > 0 &&
      data.upstreamBranch != null &&
      !data.isPrimary;

  @override
  Widget build(BuildContext context) {
    final baseRef = data.baseRef ?? 'main';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A. Working Tree section
          _SectionLabel(label: 'Working tree'),
          const SizedBox(height: 4),
          _StatusCounts(data: data),
          const SizedBox(height: 8),
          _CompactButton(
            key: InformationPanelKeys.commitButton,
            onPressed: data.uncommittedFiles > 0 ||
                    data.stagedFiles > 0
                ? () => _showCommitDialog(context)
                : null,
            label: 'Stage and commit all',
            icon: Icons.check_circle_outline,
            tooltip: data.uncommittedFiles == 0 &&
                    data.stagedFiles == 0
                ? 'No uncommitted files'
                : null,
          ),

          // B. Base section (non-primary only)
          if (!data.isPrimary) ...[
            const SizedBox(height: 16),
            _BaseSection(
              key: InformationPanelKeys.baseSection,
              data: data,
              baseRef: baseRef,
              onChangeBase: () => _handleChangeBase(context),
            ),
          ],

          // C. Upstream section (non-primary only)
          if (!data.isPrimary) ...[
            const SizedBox(height: 16),
            _UpstreamSection(
              key: InformationPanelKeys.upstreamSection,
              data: data,
            ),
          ],

          const SizedBox(height: 16),

          // D/E. Actions or Conflict section
          if (data.hasMergeConflict ||
              data.conflictOperation != null) ...[
            _ConflictInProgress(
              data: data,
              onAbort: () => _handleAbortConflict(context),
              onAskClaude: () =>
                  _handleAskClaudeConflict(context),
              onContinue: () =>
                  _handleContinueConflict(context),
            ),
          ] else if (!data.isPrimary) ...[
            _ActionsSection(
              data: data,
              baseRef: baseRef,
              canUpdateFromBase: _canUpdateFromBase,
              canMergeIntoMain: _canMergeIntoMain,
              canPush: _canPush,
              canPullRebase: _canPullRebase,
              canCreatePr: _canCreatePr,
              onRebaseOntoBase: () => _handleUpdateFromBase(
                context,
                MergeOperationType.rebase,
              ),
              onMergeBase: () => _handleUpdateFromBase(
                context,
                MergeOperationType.merge,
              ),
              onMergeIntoMain: () =>
                  _handleMergeIntoMain(context),
              onPush: () => _handlePush(
                context,
                setUpstream:
                    data.upstreamBranch == null,
              ),
              onPullRebase: () =>
                  _handlePullRebase(context),
              onCreatePr: () => _handleCreatePr(context),
            ),
          ],
        ],
      ),
    );
  }
}

// -- Section widgets --

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Text(
      label,
      style: textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StatusCounts extends StatelessWidget {
  const _StatusCounts({required this.data});

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Tooltip(
      message: 'Uncommitted: ${data.uncommittedFiles} files\n'
          'Staged: ${data.stagedFiles} files\n'
          'Commits ahead of upstream: ${data.commitsAhead}',
      child: Text(
        'Uncommitted / Staged / Commits:  '
        '${data.uncommittedFiles} / ${data.stagedFiles} / '
        '${data.commitsAhead}',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _BaseSection extends StatelessWidget {
  const _BaseSection({
    super.key,
    required this.data,
    required this.baseRef,
    required this.onChangeBase,
  });

  final WorktreeData data;
  final String baseRef;
  final VoidCallback onChangeBase;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Use house emoji for local, globe icon for remote
    final isLocal = !data.isRemoteBase;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Base'),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            // Use row layout if wide enough, otherwise stack
            final isWide = constraints.maxWidth > 220;
            if (isWide) {
              return Row(
                children: [
                  Text(
                    isLocal ? '🏠' : '🌐',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isLocal ? 'local' : 'remote',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      baseRef,
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  InsightsOutlinedButton(
                    key: InformationPanelKeys.changeBaseButton,
                    onPressed: onChangeBase,
                    child: const Text('Change...'),
                  ),
                ],
              );
            }
            // Narrow layout: stack vertically
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isLocal ? '🏠' : '🌐',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLocal ? 'local' : 'remote',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        baseRef,
                        style: textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: InsightsOutlinedButton(
                    key: InformationPanelKeys.changeBaseButton,
                    onPressed: onChangeBase,
                    child: const Text('Change...'),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 4),
        _AheadBehindIndicator(
          ahead: data.commitsAheadOfMain,
          behind: data.commitsBehindMain,
          aheadPrefix: '+',
          behindPrefix: '-',
        ),
      ],
    );
  }
}

class _UpstreamSection extends StatelessWidget {
  const _UpstreamSection({
    super.key,
    required this.data,
  });

  final WorktreeData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'Upstream'),
        const SizedBox(height: 4),
        if (data.upstreamBranch == null)
          Row(
            children: [
              Icon(
                Icons.cloud_off,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '(not published)',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              Icon(
                Icons.cloud,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.upstreamBranch!,
                  style: textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _AheadBehindIndicator(
            ahead: data.commitsAhead,
            behind: data.commitsBehind,
          ),
        ],
      ],
    );
  }
}

class _AheadBehindIndicator extends StatelessWidget {
  const _AheadBehindIndicator({
    required this.ahead,
    required this.behind,
    this.aheadPrefix = '\u{2191}',
    this.behindPrefix = '\u{2193}',
  });

  final int ahead;
  final int behind;
  final String aheadPrefix;
  final String behindPrefix;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (ahead == 0 && behind == 0) {
      return Text(
        'Up to date',
        style: textTheme.bodySmall?.copyWith(
          color: Colors.green,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: textTheme.bodySmall,
        children: [
          if (ahead > 0)
            TextSpan(
              text: '$aheadPrefix$ahead',
              style: const TextStyle(color: Colors.green),
            ),
          if (ahead > 0 && behind > 0)
            const TextSpan(text: '  '),
          if (behind > 0)
            TextSpan(
              text: '$behindPrefix$behind',
              style: const TextStyle(color: Colors.orange),
            ),
        ],
      ),
    );
  }
}

class _ActionsSection extends StatelessWidget {
  const _ActionsSection({
    required this.data,
    required this.baseRef,
    required this.canUpdateFromBase,
    required this.canMergeIntoMain,
    required this.canPush,
    required this.canPullRebase,
    required this.canCreatePr,
    required this.onRebaseOntoBase,
    required this.onMergeBase,
    required this.onMergeIntoMain,
    required this.onPush,
    required this.onPullRebase,
    required this.onCreatePr,
  });

  final WorktreeData data;
  final String baseRef;
  final bool canUpdateFromBase;
  final bool canMergeIntoMain;
  final bool canPush;
  final bool canPullRebase;
  final bool canCreatePr;
  final VoidCallback onRebaseOntoBase;
  final VoidCallback onMergeBase;
  final VoidCallback onMergeIntoMain;
  final VoidCallback onPush;
  final VoidCallback onPullRebase;
  final VoidCallback onCreatePr;

  bool get _isLocalBase => !data.isRemoteBase;
  bool get _hasUpstream => data.upstreamBranch != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Rebase onto base
        _CompactButton(
          key: InformationPanelKeys.rebaseOntoBaseButton,
          onPressed: canUpdateFromBase ? onRebaseOntoBase : null,
          label: 'Rebase onto $baseRef',
          icon: Icons.low_priority,
          tooltip: canUpdateFromBase
              ? null
              : 'Already up-to-date with $baseRef',
        ),
        const SizedBox(height: 6),
        // Merge base into branch
        _CompactButton(
          key: InformationPanelKeys.mergeBaseButton,
          onPressed: canUpdateFromBase ? onMergeBase : null,
          label: 'Merge $baseRef into branch',
          icon: Icons.merge,
          tooltip: canUpdateFromBase
              ? null
              : 'Already up-to-date with $baseRef',
        ),
        const SizedBox(height: 8),

        // State-specific actions
        if (_isLocalBase) ...[
          _CompactButton(
            key: InformationPanelKeys.mergeBranchIntoMainButton,
            onPressed:
                canMergeIntoMain ? onMergeIntoMain : null,
            label: 'Merge branch \u{2192} $baseRef',
            icon: Icons.merge,
            tooltip: _mergeIntoMainTooltip,
          ),
        ] else if (!_hasUpstream) ...[
          _CompactButton(
            key: InformationPanelKeys.pushButton,
            onPressed: onPush,
            label: 'Push to origin/${data.branch}...',
            icon: Icons.cloud_upload,
          ),
          const SizedBox(height: 8),
          _CompactButton(
            key: InformationPanelKeys.createPrButton,
            onPressed: null,
            label: 'Create PR',
            icon: Icons.open_in_new,
            tooltip: 'Push required before creating PR',
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  key: InformationPanelKeys.pushButton,
                  onPressed: canPush ? onPush : null,
                  label: 'Push',
                  icon: Icons.cloud_upload,
                  tooltip: canPush
                      ? null
                      : 'Nothing to push',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  key: InformationPanelKeys.pullRebaseButton,
                  onPressed:
                      canPullRebase ? onPullRebase : null,
                  label: 'Pull / Rebase',
                  icon: Icons.cloud_download,
                  tooltip: canPullRebase
                      ? null
                      : 'Already up-to-date with upstream',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _CompactButton(
            key: InformationPanelKeys.createPrButton,
            onPressed: canCreatePr ? onCreatePr : null,
            label: 'Create PR',
            icon: Icons.open_in_new,
            tooltip: _createPrTooltip,
          ),
        ],
      ],
    );
  }

  String? get _mergeIntoMainTooltip {
    if (data.commitsAheadOfMain == 0) return 'No commits to merge';
    if (data.commitsBehindMain > 0) {
      return 'Update this branch with the latest from $baseRef '
          'before merging it back in';
    }
    return null;
  }

  String? get _createPrTooltip {
    if (data.commitsAheadOfMain == 0) return 'No commits to push';
    return null;
  }
}

class _ConflictInProgress extends StatelessWidget {
  const _ConflictInProgress({
    required this.data,
    required this.onAbort,
    required this.onAskClaude,
    required this.onContinue,
  });

  final WorktreeData data;
  final VoidCallback onAbort;
  final VoidCallback onAskClaude;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final operationLabel =
        data.conflictOperation == MergeOperationType.rebase
            ? 'Rebase'
            : 'Merge';

    // Conflicts resolved but operation still pending.
    final resolved = !data.hasMergeConflict &&
        data.conflictOperation != null;

    final Color bannerColor;
    final IconData bannerIcon;
    final String bannerText;
    if (resolved) {
      bannerColor = Colors.green.shade700;
      bannerIcon = Icons.check_circle_outline;
      bannerText = 'Conflicts resolved \u{2014} ready to continue';
    } else {
      bannerColor = Colors.orange.shade700;
      bannerIcon = Icons.warning_amber;
      bannerText = '$operationLabel conflict in progress';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: bannerColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: bannerColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Icon(bannerIcon, size: 14, color: bannerColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  bannerText,
                  style: textTheme.labelSmall?.copyWith(
                    color: bannerColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (resolved)
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  onPressed: onContinue,
                  label: 'Continue',
                  icon: Icons.play_arrow,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _CompactButton(
                  onPressed: onAbort,
                  label: 'Abort',
                  icon: Icons.cancel_outlined,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CompactButton(
                  onPressed: onAskClaude,
                  label: 'Ask Claude',
                  icon: Icons.auto_fix_high,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Compact button styled for desktop UI - smaller padding and text.
class _CompactButton extends StatelessWidget {
  const _CompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEnabled = onPressed != null;

    final contentColor = isEnabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);
    final borderColor = isEnabled
        ? colorScheme.outline
        : colorScheme.outlineVariant.withValues(alpha: 0.3);

    Widget button = Opacity(
      opacity: isEnabled ? 1.0 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 12, color: contentColor),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: contentColor,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}
