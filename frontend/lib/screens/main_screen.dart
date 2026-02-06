import 'dart:async';

import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../panels/panels.dart';
import '../services/backend_service.dart';
import '../services/menu_action_service.dart';
import '../services/settings_service.dart';
import '../state/selection_state.dart';
import '../widgets/dialog_observer.dart';
import '../widgets/keyboard_focus_manager.dart';
import '../widgets/navigation_rail.dart';
import '../widgets/status_bar.dart';
import 'file_manager_screen.dart';
import 'settings_screen.dart';

/// Main screen using drag_split_layout for movable, resizable panels.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late SplitLayoutController _controller;

  // Track panel merge state
  // These flags track which panels are merged together:
  // - _agentsMergedIntoChats: agents are nested under chats
  // - _chatsMergedIntoWorktrees: chats (possibly with agents)
  //   are nested under worktrees
  bool _agentsMergedIntoChats = false;
  bool _chatsMergedIntoWorktrees = false;

  // Navigation rail selection
  // 0 = main view, 1 = file manager, others are panel toggles
  int _selectedNavIndex = 0;

  // Track last error shown to avoid duplicate snackbars
  String? _lastShownError;

  // Callback to resume keyboard interception when leaving settings
  VoidCallback? _resumeKeyboardInterception;

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

    // Listen for backend errors and menu actions after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupBackendErrorListener();
      _setupMenuActionListener();
    });
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'openSettings') {
      _handleNavigationChange(2);
    }
  }

  void _setupBackendErrorListener() {
    final backend = context.read<BackendService>();
    backend.addListener(_onBackendChanged);

    // Check if there's already an error
    if (backend.error != null) {
      _showBackendError(backend.error!);
    }
  }

  void _onBackendChanged() {
    if (!mounted) return;
    final backend = context.read<BackendService>();
    if (backend.error != null && backend.error != _lastShownError) {
      _showBackendError(backend.error!);
    }
  }

  void _showBackendError(String error) {
    _lastShownError = error;

    // Log to console
    debugPrint('Backend error: $error');

    // Show snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backend error: $error',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Theme.of(context).colorScheme.onError,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
    }
  }

  void _setupMenuActionListener() {
    final menuService = context.read<MenuActionService>();
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
      case MenuAction.showProjectSettings:
        _handleNavigationChange(0);
        context.read<SelectionState>().showProjectSettingsPanel();
        break;

      // Worktree actions
      case MenuAction.newWorktree:
        _handleNavigationChange(0);
        context.read<SelectionState>().showCreateWorktreePanel();
        break;
      case MenuAction.newChat:
        _handleNavigationChange(0);
        _handleNewChatShortcut();
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

  /// Whether the given nav index needs keyboard interception suspended.
  ///
  /// Settings screen has text fields that need direct keyboard input,
  /// so we suspend the global keyboard interception for it.
  bool _needsKeyboardSuspension(int index) => index == 2;

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
        final keyboardManager = KeyboardFocusManager.maybeOf(context);
        _resumeKeyboardInterception = keyboardManager?.suspend();
      });
    }
  }

  @override
  void dispose() {
    _layoutSaveDebounce?.cancel();
    // Resume keyboard interception if suspended
    _resumeKeyboardInterception?.call();
    // Remove native menu handler
    _windowChannel.setMethodCallHandler(null);
    // Remove listeners before dispose
    _controller.removeListener(_onLayoutChanged);
    try {
      context.read<BackendService>().removeListener(_onBackendChanged);
      context.read<MenuActionService>().removeListener(_onMenuAction);
    } catch (_) {
      // Context may not be valid during dispose
    }
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
      final settings = context.read<SettingsService>();
      final treeJson = _controller.rootNode.toJson();
      settings.saveLayoutTree(treeJson);
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

  /// Merge agents panel into chats panel.
  void _mergeAgentsIntoChats() {
    setState(() {
      _agentsMergedIntoChats = true;
    });

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
    setState(() {
      _chatsMergedIntoWorktrees = true;
    });

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
    setState(() {
      _chatsMergedIntoWorktrees = false;
    });

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
        _chatsMergedIntoWorktrees = true;
        return (context) =>
            WorktreesChatsPanel(onSeparateChats: _separateChatsFromWorktrees);
      case 'worktrees_chats_agents':
        _chatsMergedIntoWorktrees = true;
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
      savedTree = context.read<SettingsService>().savedLayoutTree;
    } catch (_) {
      // Provider not available (e.g. in tests without SettingsService)
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

  /// Handle panel toggle from nav rail.
  /// If panel is merged, split it out. Otherwise toggle visibility.
  void _togglePanel(String panelId) {
    switch (panelId) {
      case 'chats':
        if (_chatsMergedIntoWorktrees) {
          // Chats are merged into worktrees - split them out
          _separateChatsFromWorktrees();
        }
        break;
      case 'agents':
        if (_chatsMergedIntoWorktrees) {
          // Agents are hidden because chats (with agents) are in worktrees
          // First separate chats, then separate agents if needed
          _separateChatsFromWorktrees();
          if (_agentsMergedIntoChats) {
            _separateAgentsFromChats();
          }
        } else if (_agentsMergedIntoChats) {
          // Agents are merged into chats - split them out
          _separateAgentsFromChats();
        }
        break;
      default:
        // For other panels (worktrees, conversation), no action yet
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dialogObserver = context.read<DialogObserver>();

    return Scaffold(
      body: KeyboardFocusManager(
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
                    isChatsSeparate: !_chatsMergedIntoWorktrees,
                    isAgentsSeparate:
                        !_agentsMergedIntoChats && !_chatsMergedIntoWorktrees,
                    onDestinationSelected: (index) {
                      _handleNavigationChange(index);
                    },
                    onPanelToggle: _togglePanel,
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
                        EditableMultiSplitView(
                          controller: _controller,
                          onDividerDragEnd: _debounceSaveLayout,
                          config: EditableMultiSplitViewConfig(
                            dividerThickness: 1.0,
                            dividerHandleBuffer: 3.0,
                            paneConfig: DraggablePaneConfig(
                              dragFeedbackOpacity: 0.8,
                              dragFeedbackScale: 0.95,
                              useLongPressOnMobile: true,
                              previewStyle: DropPreviewStyle(
                                splitColor: colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
                                replaceColor: colorScheme.secondary.withValues(
                                  alpha: 0.3,
                                ),
                                borderWidth: 2.0,
                                animationDuration: const Duration(
                                  milliseconds: 150,
                                ),
                              ),
                              // Only the drag handle initiates dragging
                              dragHandleBuilder: (context) => Icon(
                                Icons.drag_indicator,
                                size: 14,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Index 1: File Manager screen
                        const FileManagerScreen(),
                        // Index 2: Settings screen
                        const SettingsScreen(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Status bar (locked to bottom)
            const StatusBar(),
          ],
        ),
      ),
    );
  }
}
