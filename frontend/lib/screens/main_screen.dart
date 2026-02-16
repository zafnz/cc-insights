import 'dart:async';

import 'package:cc_insights_v2/services/log_service.dart';
import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../panels/panels.dart';
import '../services/backend_service.dart';
import '../services/git_service.dart';
import '../services/menu_action_service.dart';
import '../services/persistence_service.dart';
import '../services/project_restore_service.dart';
import '../services/runtime_config.dart';
import '../services/settings_service.dart';
import '../services/window_layout_service.dart';
import '../services/worktree_service.dart';
import '../state/selection_state.dart';
import '../state/bulk_proposal_state.dart';
import '../widgets/dialog_observer.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/restore_worktree_dialog.dart';
import '../widgets/keyboard_focus_manager.dart';
import '../widgets/navigation_rail.dart';
import '../widgets/status_bar.dart';
import 'file_manager_screen.dart';
import 'log_viewer_screen.dart';
import 'project_stats_screen.dart';
import 'settings_screen.dart';
import 'ticket_screen.dart';

/// Main screen using drag_split_layout for movable, resizable panels.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Key to access KeyboardFocusManagerState directly (it's a child widget,
  // so findAncestorStateOfType from this State's context can't find it).
  final _keyboardFocusManagerKey = GlobalKey<KeyboardFocusManagerState>();
  late SplitLayoutController _controller;

  // Track panel merge state
  // These flags track which panels are merged together:
  // - _agentsMergedIntoChats: agents are nested under chats
  bool _agentsMergedIntoChats = false;

  // Navigation rail selection
  // 0 = main view, 1 = file manager, others are panel toggles
  int _selectedNavIndex = 0;

  // Track last error shown to avoid duplicate snackbars
  String? _lastShownError;

  // Callback to resume keyboard interception when leaving settings
  VoidCallback? _resumeKeyboardInterception;

  // Subscription for unhandled async error notifications
  StreamSubscription<LogEntry>? _unhandledErrorSub;

  // Tracked listeners for safe disposal (avoids context.read in dispose)
  BackendService? _backendService;
  MenuActionService? _menuActionService;
  BulkProposalState? _bulkProposalState;

  // Debounce timer for saving panel layout after divider drag
  Timer? _layoutSaveDebounce;

  // Method channel for native menu actions
  static const _windowChannel = MethodChannel(
    'com.nickclifford.ccinsights/window',
  );

  @override
  void initState() {
    super.initState();
    _controller = SplitLayoutController(
      rootNode: _buildInitialLayout(),
      onBeforeReplace: _handleBeforeReplace,
    );
    // Enable drag-and-drop (editMode is a setter, not constructor param)
    _controller.editMode = true;

    // Listen for structural changes to save layout
    _controller.addListener(_onLayoutChanged);

    // Listen for native menu actions
    _windowChannel.setMethodCallHandler(_handleNativeMethodCall);

    // Listen for backend errors, menu actions, unhandled exceptions,
    // and ticket board state changes after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupBackendErrorListener();
      _setupMenuActionListener();
      _setupUnhandledErrorListener();
      _setupBulkProposalListener();
      _syncMergeStateToMenu();
      _showCliWarnings();
    });
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'openSettings') {
      _handleNavigationChange(2);
    }
  }

  void _setupBackendErrorListener() {
    final backend = context.read<BackendService>();
    _backendService = backend;
    backend.addListener(_onBackendChanged);

    // Check if there's already an error
    if (backend.error != null) {
      _handleBackendError(backend, backend.error!);
    }
  }

  void _onBackendChanged() {
    if (!mounted) return;
    final backend = context.read<BackendService>();
    if (backend.error != null && backend.error != _lastShownError) {
      _handleBackendError(backend, backend.error!);
    }
  }

  void _handleBackendError(BackendService backend, String error) {
    _lastShownError = error;

    // Log to console
    debugPrint('Backend error: $error');

    if (backend.isAgentError) {
      return;
    }

    _showBackendError(error);
  }

  void _showBackendError(String error) {
    // Show snackbar
    if (mounted) {
      showErrorSnackBar(context, 'Backend error: $error');
    }
  }

  void _setupUnhandledErrorListener() {
    _unhandledErrorSub = LogService.instance.unhandledErrors.listen((entry) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'App error: ${entry.message}  (see Log Viewer)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }

  void _showCliWarnings() {
    final warnings = RuntimeConfig.instance.cliWarnings;
    if (warnings.isEmpty || !mounted) return;
    for (final warning in warnings) {
      showErrorSnackBar(context, warning);
    }
  }

  void _setupBulkProposalListener() {
    final bulkProposal = context.read<BulkProposalState>();
    _bulkProposalState = bulkProposal;
    bulkProposal.addListener(_onBulkProposalChanged);
  }

  void _onBulkProposalChanged() {
    if (!mounted) return;
    final bulkProposal = context.read<BulkProposalState>();
    // Auto-navigate to ticket screen when bulk proposal is active
    if (bulkProposal.hasActiveProposal && _selectedNavIndex != 4) {
      _handleNavigationChange(4);
    }
  }

  void _setupMenuActionListener() {
    final menuService = context.read<MenuActionService>();
    _menuActionService = menuService;
    menuService.addListener(_onMenuAction);
  }

  void _onMenuAction() {
    if (!mounted) return;
    final menuService = context.read<MenuActionService>();
    final action = menuService.lastAction;
    if (action == null) return;

    // Clear the action immediately to prevent re-processing
    menuService.clearAction();

    switch (action) {
      // View actions
      case MenuAction.showWorkspace:
        _handleNavigationChange(0);
        break;
      case MenuAction.showFileManager:
        _handleNavigationChange(1);
        break;
      case MenuAction.showSettings:
        _handleNavigationChange(2);
        break;
      case MenuAction.showLogs:
        _handleNavigationChange(3);
        break;
      case MenuAction.showStats:
        _handleNavigationChange(5);
        break;
      case MenuAction.showProjectSettings:
        _handleNavigationChange(0);
        context.read<SelectionState>().showProjectSettingsPanel();
        break;

      // Worktree actions
      case MenuAction.newWorktree:
        _handleNavigationChange(0);
        context.read<SelectionState>().showCreateWorktreePanel();
        break;
      case MenuAction.restoreWorktree:
        _handleNavigationChange(0);
        _handleRestoreWorktree();
        break;
      case MenuAction.newChat:
        _handleNavigationChange(0);
        _handleNewChatShortcut();
        break;

      // Panels
      case MenuAction.toggleMergeChatsAgents:
        if (_agentsMergedIntoChats) {
          _separateAgentsFromChats();
        } else {
          _mergeAgentsIntoChats();
        }
        break;

      // Actions submenu - not wired up yet, just log for now
      case MenuAction.actionTest:
        debugPrint('Menu: Actions > Test (not implemented)');
        break;
      case MenuAction.actionRun:
        debugPrint('Menu: Actions > Run (not implemented)');
        break;

      // Git submenu - not wired up yet, just log for now
      case MenuAction.gitStageCommit:
        debugPrint('Menu: Git > Stage & Commit (not implemented)');
        break;
      case MenuAction.gitRebase:
        debugPrint('Menu: Git > Rebase (not implemented)');
        break;
      case MenuAction.gitMerge:
        debugPrint('Menu: Git > Merge (not implemented)');
        break;
      case MenuAction.gitMergeIntoMain:
        debugPrint('Menu: Git > Merge into Main (not implemented)');
        break;
      case MenuAction.gitPush:
        debugPrint('Menu: Git > Push (not implemented)');
        break;
      case MenuAction.gitPull:
        debugPrint('Menu: Git > Pull (not implemented)');
        break;
      case MenuAction.gitCreatePR:
        debugPrint('Menu: Git > Create PR (not implemented)');
        break;
    }
  }

  /// Handles Escape shortcut - interrupts the active chat session.
  void _handleEscapeShortcut() {
    final selection = context.read<SelectionState>();
    final chat = selection.selectedChat;
    if (chat != null && chat.isWorking) {
      chat.interrupt();
    }
  }

  /// Handles Cmd+N shortcut - shows the new chat / welcome screen.
  void _handleNewChatShortcut() {
    final selection = context.read<SelectionState>();
    if (selection.selectedWorktree == null) return;
    selection.deselectChat();
  }

  /// Handles Cmd+W shortcut - shows the create worktree panel.
  void _handleNewWorktreeShortcut() {
    final selection = context.read<SelectionState>();
    selection.showCreateWorktreePanel();
  }

  /// Handles the "Restore Worktree" menu action.
  ///
  /// Discovers untracked worktrees, shows the restore dialog, and either
  /// restores healthy worktrees or offers cleanup for prunable ones.
  Future<void> _handleRestoreWorktree() async {
    final project = context.read<ProjectState>();
    final gitService = context.read<GitService>();
    final repoRoot = project.data.repoRoot;

    try {
      // Discover all git worktrees
      final allWorktrees = await gitService.discoverWorktrees(repoRoot);

      // Find worktrees not tracked in the app
      final trackedPaths = project.allWorktrees
          .map((w) => w.data.worktreeRoot)
          .toSet();
      final untracked = allWorktrees
          .where((wt) => !wt.isPrimary && !trackedPaths.contains(wt.path))
          .toList();

      if (!mounted) return;

      // Show the restore dialog
      final selected = await showRestoreWorktreeDialog(
        context: context,
        restorableWorktrees: untracked,
      );

      if (selected == null || !mounted) return;

      // Check if the selected worktree is prunable
      if (selected.isPrunable) {
        await _handlePrunableWorktree(selected, repoRoot, gitService);
        return;
      }

      // Restore the healthy worktree
      await _restoreWorktreeAndRecoverChats(
        project: project,
        gitService: gitService,
        worktreePath: selected.path,
        branch: selected.branch ?? 'unknown',
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Failed to restore worktree: $e');
      }
    }
  }

  /// Shows a cleanup confirmation dialog for a prunable worktree.
  Future<void> _handlePrunableWorktree(
    WorktreeInfo worktree,
    String repoRoot,
    GitService gitService,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stale Worktree'),
        content: Text(
          'This worktree is listed as being at ${worktree.path}, '
          'but doesn\'t exist on disk. Cleanup to remove the stale '
          'entry and you can then try to restore by branch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cleanup'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await gitService.pruneWorktrees(repoRoot);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stale worktree entries cleaned up')),
          );
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, 'Failed to prune worktrees: $e');
        }
      }
    }
  }

  /// Restores a worktree and recovers any archived chats.
  Future<void> _restoreWorktreeAndRecoverChats({
    required ProjectState project,
    required GitService gitService,
    required String worktreePath,
    required String branch,
  }) async {
    final worktreeService = WorktreeService(gitService: gitService);

    final worktreeState = await worktreeService.restoreExistingWorktree(
      project: project,
      worktreePath: worktreePath,
      branch: branch,
    );

    // Add to project state
    project.addWorktree(worktreeState);

    // Recover archived chats
    final projectRoot = project.data.repoRoot;
    final projectId = PersistenceService.generateProjectId(projectRoot);
    if (!mounted) return;
    final persistenceService = context.read<PersistenceService>();
    final restoreService = ProjectRestoreService(persistence: persistenceService);

    final archivedChats = await persistenceService.getArchivedChats(
      projectRoot: projectRoot,
    );

    final suffix = '/cci/$branch';
    final matchingChats = archivedChats
        .where((chat) =>
            chat.originalWorktreePath.endsWith(suffix) ||
            chat.originalWorktreePath == worktreePath)
        .toList();

    for (final archivedRef in matchingChats) {
      final chatState = await restoreService.restoreArchivedChat(
        archivedRef,
        worktreeState.data.worktreeRoot,
        projectId,
        projectRoot,
      );
      worktreeState.addChat(chatState);
    }

    // Select the restored worktree
    if (mounted) {
      final selection = context.read<SelectionState>();
      selection.selectWorktree(worktreeState);
    }
  }

  /// Whether the given nav index needs keyboard interception suspended.
  ///
  /// Keyboard interception should only be active on the main workspace
  /// (index 0) where the message input lives. All other screens (file
  /// manager, settings, logs, stats, tickets) should not have keys grabbed.
  bool _needsKeyboardSuspension(int index) => index != 0;

  /// Handles navigation destination changes (nav rail).
  ///
  /// Suspends keyboard interception when entering screens with text input
  /// (settings, logs) and resumes when leaving.
  void _handleNavigationChange(int newIndex) {
    final oldIndex = _selectedNavIndex;
    final wasSuspended = _needsKeyboardSuspension(oldIndex);
    final needsSuspension = _needsKeyboardSuspension(newIndex);

    // When leaving the main view (index 0), unfocus everything so that
    // widgets hidden by IndexedStack (like the terminal) don't keep a
    // stale keyboard suspension. IndexedStack keeps children mounted,
    // so Focus.onFocusChange won't fire on its own.
    if (oldIndex == 0 && newIndex != 0) {
      FocusManager.instance.primaryFocus?.unfocus();
    }

    // Update the selected index first
    setState(() => _selectedNavIndex = newIndex);

    // Manage keyboard interception suspension after the next frame
    // to ensure the widget tree has been updated
    if (wasSuspended && !needsSuspension) {
      // Resume keyboard interception when leaving a suspended screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resumeKeyboardInterception?.call();
        _resumeKeyboardInterception = null;
      });
    } else if (!wasSuspended && needsSuspension) {
      // Suspend keyboard interception when entering a screen with text input
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final keyboardManager = _keyboardFocusManagerKey.currentState;
        _resumeKeyboardInterception = keyboardManager?.suspend();
      });
    }
  }

  @override
  void dispose() {
    _layoutSaveDebounce?.cancel();
    _unhandledErrorSub?.cancel();
    // Resume keyboard interception if suspended
    _resumeKeyboardInterception?.call();
    // Remove native menu handler
    _windowChannel.setMethodCallHandler(null);
    // Remove listeners before dispose (using stored references, not context)
    _controller.removeListener(_onLayoutChanged);
    _backendService?.removeListener(_onBackendChanged);
    _menuActionService?.removeListener(_onMenuAction);
    _bulkProposalState?.removeListener(_onBulkProposalChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Called when the layout controller notifies of changes.
  void _onLayoutChanged() {
    _debounceSaveLayout();
  }

  /// Schedules a debounced save of the current panel layout tree.
  void _debounceSaveLayout() {
    _layoutSaveDebounce?.cancel();
    _layoutSaveDebounce = Timer(const Duration(seconds: 5), () {
      _saveLayoutTree();
    });
  }

  /// Saves the current panel layout tree immediately.
  void _saveLayoutTree() {
    try {
      final windowLayout = context.read<WindowLayoutService>();
      final treeJson = _controller.rootNode.toJson();
      windowLayout.saveLayoutTree(treeJson);
    } catch (_) {
      // Provider not available (e.g. during dispose)
    }
  }

  /// Handle replace interception - merge panels instead of replacing.
  ReplaceInterceptResult _handleBeforeReplace(
    DragItemModel draggedItem,
    String targetNodeId,
    DropPreviewModel preview,
  ) {
    // Check for agents being dropped onto chats
    if (draggedItem.id == 'agents' && targetNodeId == 'chats') {
      _mergeAgentsIntoChats();
      return ReplaceInterceptResult.handled;
    }

    // Check for chats (or chats_agents) being dropped onto worktrees
    if ((draggedItem.id == 'chats' || draggedItem.id == 'chats_agents') &&
        targetNodeId == 'worktrees') {
      _mergeChatsIntoWorktrees();
      return ReplaceInterceptResult.handled;
    }

    // Cancel all other replaces - we don't want panels to replace each other
    return ReplaceInterceptResult.cancel;
  }

  /// Syncs the merge state to the MenuActionService so the menu bar
  /// can show the correct label ("Merge" vs "Split").
  void _syncMergeStateToMenu() {
    try {
      context.read<MenuActionService>().agentsMergedIntoChats =
          _agentsMergedIntoChats;
    } catch (_) {
      // Provider not available (e.g. during dispose or tests)
    }
  }

  /// Merge agents panel into chats panel.
  void _mergeAgentsIntoChats() {
    setState(() {
      _agentsMergedIntoChats = true;
    });
    _syncMergeStateToMenu();

    // Remove the agents panel from the layout
    final agentsPath = _controller.findPathById('agents');
    if (agentsPath != null) {
      _controller.removeNode(agentsPath);
    }

    // Replace chats panel with combined ChatsAgentsPanel
    final chatsPath = _controller.findPathById('chats');
    if (chatsPath != null) {
      final chatsNode = _controller.getNodeAtPath(chatsPath);
      _controller.updateRootNode(
        _controller.rootNode.replaceAtPath(
          chatsPath,
          SplitNode.leaf(
            id: 'chats_agents',
            flex: chatsNode?.flex ?? 1.0,
            widgetBuilder: (context) =>
                ChatsAgentsPanel(onSeparateAgents: _separateAgentsFromChats),
          ),
        ),
      );
    }
  }

  /// Merge chats panel into worktrees panel.
  void _mergeChatsIntoWorktrees() {
    setState(() {});

    // Determine if we're merging chats_agents or just chats
    final isChatsAgents = _controller.findPathById('chats_agents') != null;

    // Remove the chats (or chats_agents) panel from the layout
    final chatsPath =
        _controller.findPathById('chats') ??
        _controller.findPathById('chats_agents');
    if (chatsPath != null) {
      _controller.removeNode(chatsPath);
    }

    // Replace worktrees panel with the appropriate combined panel
    final worktreesPath = _controller.findPathById('worktrees');
    if (worktreesPath != null) {
      final worktreesNode = _controller.getNodeAtPath(worktreesPath);

      // Use WorktreesChatsAgentsPanel if agents are merged, else WorktreesChatsPanel
      final newPanelId = isChatsAgents
          ? 'worktrees_chats_agents'
          : 'worktrees_chats';
      final newWidget = isChatsAgents
          ? WorktreesChatsAgentsPanel(
              onSeparateChats: _separateChatsFromWorktrees,
            )
          : WorktreesChatsPanel(onSeparateChats: _separateChatsFromWorktrees);

      _controller.updateRootNode(
        _controller.rootNode.replaceAtPath(
          worktreesPath,
          SplitNode.leaf(
            id: newPanelId,
            flex: worktreesNode?.flex ?? 1.0,
            widgetBuilder: (context) => newWidget,
          ),
        ),
      );
    }
  }

  /// Separate agents back out from the chats panel.
  void _separateAgentsFromChats() {
    setState(() {
      _agentsMergedIntoChats = false;
    });
    _syncMergeStateToMenu();

    // Find the chats_agents panel
    final combinedPath = _controller.findPathById('chats_agents');
    if (combinedPath == null) return;

    final combinedNode = _controller.getNodeAtPath(combinedPath);
    final flex = combinedNode?.flex ?? 1.0;

    // Replace with a branch containing chats and agents
    _controller.updateRootNode(
      _controller.rootNode.replaceAtPath(
        combinedPath,
        SplitNode.branch(
          id: 'chats_agents_split',
          axis: SplitAxis.vertical,
          flex: flex,
          children: [
            SplitNode.leaf(
              id: 'chats',
              flex: 1.0,
              widgetBuilder: (context) => const ChatsPanel(),
            ),
            SplitNode.leaf(
              id: 'agents',
              flex: 1.0,
              widgetBuilder: (context) => const AgentsPanel(),
            ),
          ],
        ),
      ),
    );
  }

  /// Separate chats back out from the worktrees panel.
  void _separateChatsFromWorktrees() {
    setState(() {});

    // Find the combined panel (could be worktrees_chats or worktrees_chats_agents)
    final combinedPath =
        _controller.findPathById('worktrees_chats_agents') ??
        _controller.findPathById('worktrees_chats');
    if (combinedPath == null) return;

    final combinedNode = _controller.getNodeAtPath(combinedPath);
    final flex = combinedNode?.flex ?? 1.0;

    // Determine what to put back based on whether agents are merged
    final chatsWidget = _agentsMergedIntoChats
        ? SplitNode.leaf(
            id: 'chats_agents',
            flex: 1.0,
            widgetBuilder: (context) =>
                ChatsAgentsPanel(onSeparateAgents: _separateAgentsFromChats),
          )
        : SplitNode.leaf(
            id: 'chats',
            flex: 1.0,
            widgetBuilder: (context) => const ChatsPanel(),
          );

    // Replace with a branch containing worktrees and chats
    _controller.updateRootNode(
      _controller.rootNode.replaceAtPath(
        combinedPath,
        SplitNode.branch(
          id: 'worktrees_chats_split',
          axis: SplitAxis.vertical,
          flex: flex,
          children: [
            SplitNode.leaf(
              id: 'worktrees',
              flex: 1.0,
              widgetBuilder: (context) => const WorktreePanel(),
            ),
            chatsWidget,
          ],
        ),
      ),
    );
  }

  /// Resolves a panel ID to its widget builder.
  ///
  /// Returns null if the ID is not recognized, which causes
  /// [SplitNode.fromJson] to fail and fall back to the default layout.
  Widget Function(BuildContext)? _resolveWidgetBuilder(String id) {
    switch (id) {
      case 'worktrees':
        return (context) => const WorktreePanel();
      case 'information':
        return (context) => const InformationPanel();
      case 'actions':
        return (context) => const ActionsPanel();
      case 'content':
        return (context) => const ContentPanel();
      case 'terminal':
        return (context) => const TerminalOutputPanel();
      case 'chats':
        return (context) => const ChatsPanel();
      case 'agents':
        return (context) => const AgentsPanel();
      case 'chats_agents':
        _agentsMergedIntoChats = true;
        return (context) =>
            ChatsAgentsPanel(onSeparateAgents: _separateAgentsFromChats);
      case 'worktrees_chats':
        return (context) =>
            WorktreesChatsPanel(onSeparateChats: _separateChatsFromWorktrees);
      case 'worktrees_chats_agents':
        _agentsMergedIntoChats = true;
        return (context) => WorktreesChatsAgentsPanel(
              onSeparateChats: _separateChatsFromWorktrees,
            );
      default:
        return null;
    }
  }

  /// Build the initial panel layout tree.
  ///
  /// If a saved layout tree exists in settings, it is restored.
  /// Otherwise, the default layout is used.
  SplitNode _buildInitialLayout() {
    Map<String, dynamic>? savedTree;
    try {
      savedTree = context.read<WindowLayoutService>().savedLayoutTree;
    } catch (_) {
      // Provider not available (e.g. in tests without WindowLayoutService)
    }

    // Try to restore from saved tree
    if (savedTree != null) {
      final restored = SplitNode.fromJson(savedTree, _resolveWidgetBuilder);
      if (restored != null) {
        return restored;
      }
    }

    // Fall back to default layout
    return _buildDefaultLayout();
  }

  /// Builds the default panel layout tree.
  SplitNode _buildDefaultLayout() {
    return SplitNode.branch(
      id: 'root',
      axis: SplitAxis.horizontal,
      children: [
        // Left sidebar: Worktrees + Information + Actions stacked
        SplitNode.branch(
          id: 'left_sidebar',
          axis: SplitAxis.vertical,
          children: [
            // Worktrees panel (top)
            SplitNode.leaf(
              id: 'worktrees',
              widgetBuilder: (context) => const WorktreePanel(),
            ),
            // Information panel
            SplitNode.leaf(
              id: 'information',
              widgetBuilder: (context) => const InformationPanel(),
            ),
            // Actions panel (bottom)
            SplitNode.leaf(
              id: 'actions',
              flex: 0.5,
              widgetBuilder: (context) => const ActionsPanel(),
            ),
          ],
        ),
        // Center: Content area and terminal output
        SplitNode.branch(
          id: 'content_area',
          axis: SplitAxis.vertical,
          flex: 3.0,
          children: [
            // Main content area
            SplitNode.leaf(
              id: 'content',
              flex: 3.0,
              widgetBuilder: (context) => const ContentPanel(),
            ),
            // Terminal output panel (for script output)
            SplitNode.leaf(
              id: 'terminal',
              widgetBuilder: (context) => const TerminalOutputPanel(),
            ),
          ],
        ),
        // Right sidebar: Chats + Agents stacked
        SplitNode.branch(
          id: 'right_sidebar',
          axis: SplitAxis.vertical,
          children: [
            // Chats panel (top)
            SplitNode.leaf(
              id: 'chats',
              widgetBuilder: (context) => const ChatsPanel(),
            ),
            // Agents panel (bottom)
            SplitNode.leaf(
              id: 'agents',
              widgetBuilder: (context) => const AgentsPanel(),
            ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dialogObserver = context.read<DialogObserver>();

    return Scaffold(
      body: KeyboardFocusManager(
        key: _keyboardFocusManagerKey,
        dialogObserver: dialogObserver,
        onEscapePressed: _handleEscapeShortcut,
        onNewChatShortcut: _handleNewChatShortcut,
        onNewWorktreeShortcut: _handleNewWorktreeShortcut,
        child: Column(
          children: [
            // Main content area with nav rail
            Expanded(
              child: Row(
                children: [
                  // Navigation Rail
                  AppNavigationRail(
                    selectedIndex: _selectedNavIndex,
                    onDestinationSelected: (index) {
                      _handleNavigationChange(index);
                    },
                  ),
                  // Vertical divider
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  // Screen content - switches based on navigation
                  Expanded(
                    child: IndexedStack(
                      index: _selectedNavIndex,
                      children: [
                        // Index 0: Main screen with panel layout
                        _PanelLayout(
                          controller: _controller,
                          onDividerDragEnd: _debounceSaveLayout,
                        ),
                        // Index 1: File Manager screen
                        const FileManagerScreen(),
                        // Index 2: Settings screen
                        const SettingsScreen(),
                        // Index 3: Log viewer screen
                        const LogViewerScreen(),
                        // Index 4: Ticket screen
                        const TicketScreen(),
                        // Index 5: Project Stats screen
                        const ProjectStatsScreen(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Status bar (locked to bottom)
            StatusBar(showTicketStats: _selectedNavIndex == 4),
          ],
        ),
      ),
    );
  }
}

/// Panel layout with drag-and-drop split view configuration.
class _PanelLayout extends StatelessWidget {
  const _PanelLayout({
    required this.controller,
    required this.onDividerDragEnd,
  });

  final SplitLayoutController controller;
  final VoidCallback onDividerDragEnd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return EditableMultiSplitView(
      controller: controller,
      onDividerDragEnd: onDividerDragEnd,
      config: EditableMultiSplitViewConfig(
        dividerThickness: 1.0,
        dividerHandleBuffer: 3.0,
        paneConfig: DraggablePaneConfig(
          dragFeedbackOpacity: 0.8,
          dragFeedbackScale: 0.95,
          useLongPressOnMobile: true,
          previewStyle: DropPreviewStyle(
            splitColor: colorScheme.primary.withValues(alpha: 0.3),
            replaceColor: colorScheme.secondary.withValues(alpha: 0.3),
            borderWidth: 2.0,
            animationDuration: const Duration(milliseconds: 150),
          ),
          dragHandleBuilder: (context) => Icon(
            Icons.drag_indicator,
            size: 14,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
