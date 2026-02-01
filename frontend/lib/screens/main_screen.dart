import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../panels/panels.dart';
import '../services/backend_service.dart';
import '../widgets/keyboard_focus_manager.dart';
import '../widgets/navigation_rail.dart';
import '../widgets/status_bar.dart';
import 'file_manager_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = SplitLayoutController(
      rootNode: _buildInitialLayout(),
      onBeforeReplace: _handleBeforeReplace,
    );
    // Enable drag-and-drop (editMode is a setter, not constructor param)
    _controller.editMode = true;

    // Listen for backend errors after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupBackendErrorListener();
    });
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

  @override
  void dispose() {
    // Remove listener before dispose
    try {
      context.read<BackendService>().removeListener(_onBackendChanged);
    } catch (_) {
      // Context may not be valid during dispose
    }
    _controller.dispose();
    super.dispose();
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

  /// Build the initial panel layout tree.
  SplitNode _buildInitialLayout() {
    return SplitNode.branch(
      id: 'root',
      axis: SplitAxis.horizontal,
      children: [
        // Left sidebar: Worktrees + Information + Chats + Agents + Actions stacked
        SplitNode.branch(
          id: 'sidebar',
          axis: SplitAxis.vertical,
          flex: 1.0,
          children: [
            // Worktrees panel (top)
            SplitNode.leaf(
              id: 'worktrees',
              flex: 1.0,
              widgetBuilder: (context) => const WorktreePanel(),
            ),
            // Information panel (between worktrees and chats)
            SplitNode.leaf(
              id: 'information',
              flex: 1.0,
              widgetBuilder: (context) => const InformationPanel(),
            ),
            // Chats panel (middle)
            SplitNode.leaf(
              id: 'chats',
              flex: 1.0,
              widgetBuilder: (context) => const ChatsPanel(),
            ),
            // Agents panel (bottom)
            SplitNode.leaf(
              id: 'agents',
              flex: 1.0,
              widgetBuilder: (context) => const AgentsPanel(),
            ),
            // Actions panel (bottom)
            SplitNode.leaf(
              id: 'actions',
              flex: 0.5,
              widgetBuilder: (context) => const ActionsPanel(),
            ),
          ],
        ),
        // Right panels: Content area and terminal output
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
              flex: 1.0,
              widgetBuilder: (context) => const TerminalOutputPanel(),
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

    return Scaffold(
      body: KeyboardFocusManager(
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
                      setState(() => _selectedNavIndex = index);
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
                          config: EditableMultiSplitViewConfig(
                            dividerThickness: 6.0,
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
