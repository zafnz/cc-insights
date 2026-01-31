import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../acp/acp_client_wrapper.dart';
import '../acp/pending_permission.dart';
import '../acp/session_update_handler.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../services/agent_registry.dart';
import '../services/agent_service.dart';
import '../services/project_restore_service.dart';
import '../state/selection_state.dart';
import '../widgets/acp_permission_dialog.dart';
import '../widgets/context_indicator.dart';
import '../widgets/cost_indicator.dart';
import '../widgets/message_input.dart';
import '../widgets/output_entries.dart';

/// A conversation panel with smart scroll behavior.
///
/// Key behaviors:
/// - Uses a normal (non-reversed) ListView for stable scroll position
/// - Auto-scrolls to bottom when new content arrives IF user is already at bottom
/// - When user scrolls up, content stays in place as new messages arrive
/// - This prevents the jarring "content shift" when reading older messages
class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final ListController _listController = ListController();

  /// Saved scroll positions indexed by conversation ID
  final Map<String, _ScrollPosition> _savedScrollPositions = {};

  /// The ChatState we're currently listening to.
  ChatState? _listeningToChat;

  /// Track which conversation we're viewing to detect conversation changes.
  String? _previousConversationId;

  /// Whether the user is currently at the bottom of the scroll view.
  /// When true, new content will trigger auto-scroll to bottom.
  bool _isAtBottom = true;

  /// The number of entries last time we checked, used to detect new entries.
  int _lastEntryCount = 0;

  /// Animation controller for permission widget slide-up.
  late final AnimationController _permissionAnimController;
  late final Animation<double> _permissionAnimation;

  /// Cache the last ACP permission request for animation-out.
  /// This ensures we can still render the widget while animating out.
  PendingPermission? _cachedAcpPermission;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _permissionAnimController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _permissionAnimation = CurvedAnimation(
      parent: _permissionAnimController,
      curve: Curves.easeOut,
    );
    // Handle permission animation lifecycle
    _permissionAnimController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        // Clear cached permission when animation completes reverse
        setState(() {
          _cachedAcpPermission = null;
        });
      } else if (status == AnimationStatus.completed) {
        // Permission widget fully visible - if user was at bottom, scroll there
        // This handles the case where the animation changed the list height
        // Use post-frame callback to ensure layout is fully settled
        if (_isAtBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }
    });
    // Also handle animation value changes to keep scroll at bottom during animation
    _permissionAnimController.addListener(_onPermissionAnimationChanged);
  }

  /// Called when the permission animation value changes.
  /// Keeps scroll at bottom during animation if user was at bottom.
  void _onPermissionAnimationChanged() {
    // Only act if animating forward (permission appearing) and user was at bottom
    if (_permissionAnimController.status == AnimationStatus.forward &&
        _isAtBottom &&
        _scrollController.hasClients) {
      // Jump to bottom immediately to keep content pinned during animation
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  /// Called when scroll position changes.
  /// Tracks whether user is at the bottom for auto-scroll behavior.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // Consider "at bottom" if within 50 pixels of the end
    final atBottom = position.pixels >= position.maxScrollExtent - 50;

    if (_isAtBottom != atBottom) {
      developer.log(
        'Scroll: _isAtBottom changed from $_isAtBottom to $atBottom '
        '(pixels=${position.pixels.toStringAsFixed(0)}, '
        'max=${position.maxScrollExtent.toStringAsFixed(0)})',
        name: 'ConversationPanel',
      );
    }
    _isAtBottom = atBottom;
  }

  /// Scrolls to the bottom of the list with animation.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  /// Schedules a scroll to bottom after layout is complete.
  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// Saves the current scroll position for the given conversation ID.
  void _saveScrollPosition(String conversationId) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final currentPixels = position.pixels;
    final wasAtBottom = currentPixels >= position.maxScrollExtent - 50;

    // Calculate which item is at the top of the viewport
    // Use the list controller to get the first visible item
    int topIndex = 0;
    double offsetInItem = 0.0;

    if (_listController.isAttached) {
      final visibleRange = _listController.visibleRange;

      if (visibleRange != null) {
        final (firstItem, _) = visibleRange;
        if (firstItem >= 0) {
          topIndex = firstItem;
          // Calculate offset within the item using getOffsetToReveal
          // This gives us the scroll offset to align this item at the top
          final itemOffset = _listController.getOffsetToReveal(
            topIndex,
            0.0, // alignment 0.0 = top of viewport
          );
          offsetInItem = currentPixels - itemOffset;
        }
      }
    }

    _savedScrollPositions[conversationId] = _ScrollPosition(
      topVisibleIndex: topIndex,
      offsetInItem: offsetInItem,
      wasAtBottom: wasAtBottom,
    );

    developer.log(
      'Saved scroll position for conversation $conversationId: '
      'topIndex=$topIndex, offsetInItem=${offsetInItem.toStringAsFixed(1)}, '
      'currentPixels=${currentPixels.toStringAsFixed(1)}, '
      'wasAtBottom=$wasAtBottom',
      name: 'ConversationPanel',
    );
  }

  /// Schedules restoration of a saved scroll position after layout.
  void _scheduleScrollRestore(String conversationId) {
    final saved = _savedScrollPositions[conversationId];
    if (saved == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      try {
        if (saved.wasAtBottom) {
          // User was at bottom - scroll to bottom
          _scrollToBottom();
        } else {
          // Jump to the saved item index first
          _listController.jumpToItem(
            index: saved.topVisibleIndex,
            scrollController: _scrollController,
            alignment: 0.0, // Align to top of viewport
          );

          // Then fine-tune with the offset within that item
          // Schedule this as a separate frame callback to let layout settle
          if (saved.offsetInItem != 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              final currentPixels = _scrollController.position.pixels;
              final targetPixels = currentPixels + saved.offsetInItem;
              // Clamp to valid scroll range
              final position = _scrollController.position;
              final clampedPixels = targetPixels.clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              );
              _scrollController.jumpTo(clampedPixels);
            });
          }
        }

        developer.log(
          'Restored scroll position for conversation $conversationId: '
          'index=${saved.topVisibleIndex}, offset=${saved.offsetInItem.toStringAsFixed(1)}',
          name: 'ConversationPanel',
        );
      } catch (e) {
        // If restoration fails (e.g., index out of range), just scroll to bottom
        developer.log(
          'Failed to restore scroll position for $conversationId: $e - scrolling to bottom',
          name: 'ConversationPanel',
          error: e,
        );
        _scrollToBottom();
        // Clear the invalid saved position
        _savedScrollPositions.remove(conversationId);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _permissionAnimController.removeListener(_onPermissionAnimationChanged);
    _permissionAnimController.dispose();
    _scrollController.dispose();
    _listController.dispose();
    _listeningToChat?.removeListener(_onChatChanged);
    super.dispose();
  }

  /// Called when the ChatState changes (entries added, etc.)
  void _onChatChanged() {
    if (!mounted) return;

    // Check if new entries were added
    final conversation = _listeningToChat?.selectedConversation;
    final currentCount = conversation?.entries.length ?? 0;
    final newEntriesAdded = currentCount > _lastEntryCount;

    // Check scroll position directly when new entries are added
    // The scroll listener may not have fired yet, so we recompute here
    if (newEntriesAdded && _scrollController.hasClients) {
      final position = _scrollController.position;
      final wasAtBottom = position.pixels >= position.maxScrollExtent - 50;

      developer.log(
        'New entry: wasAtBottom=$wasAtBottom, '
        'pixels=${position.pixels.toStringAsFixed(0)}, '
        'maxExtent=${position.maxScrollExtent.toStringAsFixed(0)}',
        name: 'ConversationPanel',
      );

      if (wasAtBottom) {
        // User was at bottom - schedule scroll to bottom after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } else if (newEntriesAdded && !_scrollController.hasClients) {
      // No clients yet (first build), schedule scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }

    _lastEntryCount = currentCount;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();
    final chat = selection.selectedChat;

    // Listen to ChatState changes for entry updates
    if (chat != _listeningToChat) {
      _listeningToChat?.removeListener(_onChatChanged);
      _listeningToChat = chat;
      chat?.addListener(_onChatChanged);
    }

    final conversation = chat?.selectedConversation;

    // Handle conversation switching - save old position and restore new
    if (conversation?.id != _previousConversationId) {
      // Save old conversation's scroll position (if any)
      if (_previousConversationId != null && _scrollController.hasClients) {
        _saveScrollPosition(_previousConversationId!);
      }

      _previousConversationId = conversation?.id;
      _lastEntryCount = conversation?.entries.length ?? 0;
      _isAtBottom = true;

      // Restore saved position (if any), otherwise scroll to bottom
      if (conversation != null && _savedScrollPositions.containsKey(conversation.id)) {
        _scheduleScrollRestore(conversation.id);
      } else {
        _scheduleScrollToBottom();
      }
    }

    if (conversation == null) {
      // Show welcome card when no chat is selected
      return const WelcomeCard();
    }

    final isPrimary = conversation.isPrimary;

    // Check for pending ACP permission
    final currentAcpPermission = chat?.pendingAcpPermission;

    // Update cache and animate
    if (currentAcpPermission != null) {
      _cachedAcpPermission = currentAcpPermission;
      if (!_permissionAnimController.isCompleted) {
        _permissionAnimController.forward();
      }
    } else if (_cachedAcpPermission != null) {
      // Permission was cleared, animate out
      _permissionAnimController.reverse();
    }

    // Determine if we should show the permission widget
    // Show if we have a cached permission AND either:
    // - animation is animating forward (including value=0 at start)
    // - animation value > 0 (during animation or completed)
    final shouldShowPermissionWidget = _cachedAcpPermission != null &&
        (_permissionAnimController.status == AnimationStatus.forward ||
            _permissionAnimController.status == AnimationStatus.completed ||
            _permissionAnimController.value > 0);

    // Check if Claude is working (for spinner display)
    final isWorking = chat?.isWorking ?? false;
    final isCompacting = chat?.isCompacting ?? false;

    // Find the agent for this subagent conversation (if any)
    final Agent? agent = !isPrimary && chat != null
        ? chat.activeAgents.values.cast<Agent?>().firstWhere(
              (a) => a?.conversationId == conversation.id,
              orElse: () => null,
            )
        : null;

    return Column(
      children: [
        // Conversation header - wrapped in ListenableBuilder to rebuild on chat changes
        ListenableBuilder(
          listenable: chat!,
          builder: (context, _) => _ConversationHeader(
            conversation: conversation,
            chat: chat,
          ),
        ),
        // Subagent status header (only for subagent conversations)
        if (!isPrimary)
          _SubagentStatusHeader(
            conversation: conversation,
            agent: agent,
          ),
        // Output entries list
        Expanded(
          child: conversation.entries.isEmpty && !isWorking
              ? _ConversationPlaceholder(
                  message: isPrimary
                      ? 'No messages yet. Start a conversation!'
                      : 'No output from this subagent yet.',
                )
              : _buildEntryList(
                  conversation,
                  showWorkingIndicator: isPrimary && isWorking,
                  isCompacting: isCompacting,
                ),
        ),
        // Bottom area: either permission widget or message input
        if (isPrimary)
          shouldShowPermissionWidget
              ? _buildPermissionWidget(chat!)
              : MessageInput(
                  onSubmit: (text, images) =>
                      _handleSubmit(context, text, images),
                  isWorking: isWorking,
                  onInterrupt: isWorking ? () => _handleInterrupt(chat!) : null,
                ),
      ],
    );
  }

  /// Build the permission widget with slide-up animation.
  Widget _buildPermissionWidget(ChatState chat) {
    final acpPermission = _cachedAcpPermission;
    if (acpPermission == null) {
      // No permission to show
      return const SizedBox.shrink();
    }

    return SizeTransition(
      sizeFactor: _permissionAnimation,
      axisAlignment: 1.0, // Align to bottom (slide up from bottom)
      child: AcpPermissionDialog(
        permission: acpPermission,
        onAllow: (optionId) => chat.allowAcpPermission(optionId),
        onCancel: () => chat.cancelAcpPermission(),
      ),
    );
  }

  Widget _buildEntryList(
    ConversationData conversation, {
    bool showWorkingIndicator = false,
    bool isCompacting = false,
  }) {
    final entries = conversation.entries;
    final selection = context.read<SelectionState>();
    final projectDir = selection.selectedChat?.data.worktreeRoot;
    final isSubagent = !conversation.isPrimary;

    // Add 1 to item count for the working indicator when active
    final itemCount = entries.length + (showWorkingIndicator ? 1 : 0);

    return SuperListView.builder(
      controller: _scrollController,
      listController: _listController,
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Working indicator is at the end (bottom visually)
        if (showWorkingIndicator && index == entries.length) {
          return WorkingIndicator(isCompacting: isCompacting);
        }

        // Normal chronological order: index 0 = oldest, index n-1 = newest
        final entry = entries[index];
        return OutputEntryWidget(
          entry: entry,
          projectDir: projectDir,
          isSubagent: isSubagent,
        );
      },
    );
  }

  /// Handles interrupt button press - stops the current session.
  Future<void> _handleInterrupt(ChatState chat) async {
    try {
      await chat.interrupt();
    } catch (e) {
      developer.log(
        'Failed to interrupt session: $e',
        name: 'ConversationPanel',
        error: e,
      );
    }
  }

  Future<void> _handleSubmit(
    BuildContext context,
    String text,
    List<AttachedImage> images,
  ) async {
    if (text.trim().isEmpty && images.isEmpty) return;

    final selection = context.read<SelectionState>();
    final chat = selection.selectedChat;
    if (chat == null) return;

    final agentService = context.read<AgentService>();

    if (!chat.hasActiveSession) {
      // First message - start a new ACP session with the prompt
      // Check if agent is connected before trying to start session
      if (!agentService.isConnected) {
        _showNotConnectedDialog(context, agentService);
        return;
      }

      // Create a session update handler for this chat
      final updateHandler = _createUpdateHandler(chat);

      try {
        await chat.startAcpSession(
          agentService: agentService,
          updateHandler: updateHandler,
          prompt: text,
          images: images,
        );
      } catch (e) {
        // Show error in conversation
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Failed to start session: $e',
          contentType: 'error',
        ));
      }
    } else {
      // Subsequent message - send to existing session
      try {
        await chat.sendMessage(text, images: images);
      } catch (e) {
        // Show error in conversation
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: 'Failed to send message: $e',
          contentType: 'error',
        ));
      }
    }
  }

  /// Creates a SessionUpdateHandler that routes updates to the chat.
  SessionUpdateHandler _createUpdateHandler(ChatState chat) {
    return SessionUpdateHandler(
      onAgentMessage: (text) {
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: text,
          contentType: 'assistant',
        ));
      },
      onThinkingMessage: (text) {
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: text,
          contentType: 'thinking',
        ));
      },
      onToolCall: (info) {
        chat.addEntry(ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: info.title,
          toolInput: info.rawInput ?? {},
          toolUseId: info.toolCallId,
        ));
      },
      onToolCallUpdate: (info) {
        // Tool call updates could be used to update the tool result
        // For now, we'll add a tool result entry when status is complete
        if (info.status?.name == 'complete' && info.rawOutput != null) {
          chat.addEntry(ToolResultEntry(
            timestamp: DateTime.now(),
            toolUseId: info.toolCallId,
            result: info.rawOutput,
            isError: false,
          ));
        }
      },
    );
  }
}

/// Shows a dialog prompting the user to connect to an agent.
///
/// Displays available agents and allows the user to select and connect.
/// If agents are available, it also offers to auto-connect to the first one.
void _showNotConnectedDialog(BuildContext context, AgentService agentService) {
  final registry = context.read<AgentRegistry>();
  final agents = registry.agents;

  debugPrint('[ConnectDialog] Showing dialog. Agents available: '
      '${agents.map((a) => a.name).join(", ")}');

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ConnectAgentDialog(
        agents: agents,
        agentService: agentService,
      );
    },
  );
}

/// Stateful dialog for connecting to an agent.
///
/// Handles the async connection flow with loading state and error handling.
class _ConnectAgentDialog extends StatefulWidget {
  const _ConnectAgentDialog({
    required this.agents,
    required this.agentService,
  });

  final List<AgentConfig> agents;
  final AgentService agentService;

  @override
  State<_ConnectAgentDialog> createState() => _ConnectAgentDialogState();
}

class _ConnectAgentDialogState extends State<_ConnectAgentDialog> {
  bool _isConnecting = false;
  String? _error;

  Future<void> _connect(AgentConfig agent) async {
    debugPrint('[ConnectDialog] Connect button pressed for: ${agent.name}');
    debugPrint('[ConnectDialog] Agent config: command=${agent.command}, '
        'args=${agent.args}');

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      debugPrint('[ConnectDialog] Calling agentService.connect()...');
      await widget.agentService.connect(agent);
      debugPrint('[ConnectDialog] Connection successful!');

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      debugPrint('[ConnectDialog] Connection failed: $e');
      debugPrint('[ConnectDialog] Stack trace: $stackTrace');

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final agents = widget.agents;

    return AlertDialog(
      title: const Text('No Agent Connected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You need to connect to an agent before sending messages.',
          ),
          if (agents.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'No agents are available. Please ensure an ACP-compatible '
              'agent (like Claude Code) is installed and configured.',
              style: TextStyle(
                color: colorScheme.error,
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Text(
              'Available agents: ${agents.map((a) => a.name).join(", ")}',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              'Error: $_error',
              style: TextStyle(color: colorScheme.error),
            ),
          ],
          if (_isConnecting) ...[
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Connecting...'),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (agents.isNotEmpty)
          FilledButton(
            onPressed: _isConnecting ? null : () => _connect(agents.first),
            child: Text('Connect to ${agents.first.name}'),
          ),
      ],
    );
  }
}

/// Header showing conversation context with model/permission selectors and usage.
///
/// Layout behavior:
/// - >= 700px: All elements visible (name, dropdowns, context, tokens)
/// - >= 500px: Context and tokens visible, dropdowns clip under them
/// - >= 350px: Only tokens visible
/// - < 350px: Only chat name visible
class _ConversationHeader extends StatelessWidget {
  const _ConversationHeader({
    required this.conversation,
    required this.chat,
  });

  final ConversationData conversation;
  final ChatState chat;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final chatName = chat.data.name;
    final isSubagent = !conversation.isPrimary;

    // Get connected agent info for primary conversations
    final agentService = context.watch<AgentService?>();
    final isConnected = agentService?.isConnected ?? false;
    final agentName = agentService?.currentAgent?.name;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final showContext = width >= 500;
          final showTokens = width >= 350;

          return Row(
            children: [
              // Left side: chat name and dropdowns (clips under right side)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSubagent
                            ? Icons.smart_toy_outlined
                            : Icons.chat_bubble_outline,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      // Chat/subagent name
                      Text(
                        isSubagent
                            ? conversation.label ?? 'Subagent'
                            : chatName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Connected agent badge (only for primary conversations)
                      if (!isSubagent && agentName != null) ...[
                        const SizedBox(width: 8),
                        _AgentBadge(
                          agentName: agentName,
                          isConnected: isConnected,
                        ),
                      ],
                      // Model and permission selectors
                      if (!isSubagent) ...[
                        const SizedBox(width: 12),
                        _CompactDropdown(
                          value: chat.model.label,
                          items:
                              ClaudeModel.values.map((m) => m.label).toList(),
                          onChanged: (value) {
                            final model = ClaudeModel.values.firstWhere(
                              (m) => m.label == value,
                              orElse: () => ClaudeModel.sonnet,
                            );
                            chat.setModel(model);
                          },
                        ),
                        const SizedBox(width: 8),
                        _CompactDropdown(
                          value: chat.permissionMode.label,
                          items: PermissionMode.values
                              .map((m) => m.label)
                              .toList(),
                          onChanged: (value) {
                            final mode = PermissionMode.values.firstWhere(
                              (m) => m.label == value,
                              orElse: () => PermissionMode.defaultMode,
                            );
                            chat.setPermissionMode(mode);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Right side: context indicator and token/cost
              if (showContext) ...[
                const SizedBox(width: 8),
                ContextIndicator(tracker: chat.contextTracker),
              ],
              if (showTokens) ...[
                const SizedBox(width: 8),
                CostIndicator(
                  usage: chat.cumulativeUsage,
                  modelUsage: chat.modelUsage,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Badge showing the connected ACP agent with status indicator.
class _AgentBadge extends StatelessWidget {
  const _AgentBadge({
    required this.agentName,
    required this.isConnected,
  });

  final String agentName;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final statusColor = isConnected ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Connection status dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          // Agent name
          Text(
            agentName,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Status header shown for subagent conversations.
///
/// Displays:
/// - Agent label/name
/// - Task description
/// - Current status (working, completed, error, etc.)
/// - Result summary when completed
class _SubagentStatusHeader extends StatelessWidget {
  const _SubagentStatusHeader({
    required this.conversation,
    required this.agent,
  });

  final ConversationData conversation;
  final Agent? agent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine status info
    final status = agent?.status;
    final (statusLabel, statusColor, statusIcon) = _getStatusInfo(
      status,
      colorScheme,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First row: status badge and task description
          Row(
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Task description
              if (conversation.taskDescription != null)
                Expanded(
                  child: Text(
                    conversation.taskDescription!,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          // Second row: result summary (if completed)
          if (agent?.result != null && agent!.result!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      agent!.result!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns status label, color, and icon based on agent status.
  (String, Color, IconData) _getStatusInfo(
    AgentStatus? status,
    ColorScheme colorScheme,
  ) {
    return switch (status) {
      AgentStatus.working => (
          'Working',
          colorScheme.primary,
          Icons.sync,
        ),
      AgentStatus.waitingTool => (
          'Waiting for permission',
          Colors.orange,
          Icons.hourglass_top,
        ),
      AgentStatus.waitingUser => (
          'Waiting for input',
          Colors.orange,
          Icons.question_mark,
        ),
      AgentStatus.completed => (
          'Completed',
          Colors.green,
          Icons.check_circle_outline,
        ),
      AgentStatus.error => (
          'Error',
          colorScheme.error,
          Icons.error_outline,
        ),
      null => (
          'Inactive',
          colorScheme.onSurfaceVariant,
          Icons.pause_circle_outline,
        ),
    };
  }
}

/// Compact dropdown using PopupMenuButton for styled menu.
class _CompactDropdown extends StatefulWidget {
  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  State<_CompactDropdown> createState() => _CompactDropdownState();
}

class _CompactDropdownState extends State<_CompactDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      initialValue: widget.value,
      onSelected: widget.onChanged,
      offset: const Offset(0, 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: colorScheme.primary.withOpacity(0.5),
          width: 1,
        ),
      ),
      color: colorScheme.surfaceContainerHigh,
      itemBuilder: (context) => widget.items.map((item) {
        final isSelected = item == widget.value;
        return PopupMenuItem<String>(
          value: item,
          height: 32,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              item,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
        );
      }).toList(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovered
                ? colorScheme.primary.withOpacity(0.1)
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shown when no conversation is selected or empty.
class _ConversationPlaceholder extends StatelessWidget {
  const _ConversationPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Welcome card shown when no chat is selected.
///
/// Displays project info and invites the user to start chatting.
/// Includes model/permission selectors and a message input box at the bottom
/// that creates a new chat and sends the first message.
class WelcomeCard extends StatefulWidget {
  const WelcomeCard({super.key});

  @override
  State<WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends State<WelcomeCard> {
  ClaudeModel _selectedModel = ClaudeModel.sonnet;
  PermissionMode _selectedPermission = PermissionMode.defaultMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final worktree = selection.selectedWorktree;

    return Column(
      children: [
        // Header with model/permission selectors
        _WelcomeHeader(
          model: _selectedModel,
          permissionMode: _selectedPermission,
          onModelChanged: (model) => setState(() => _selectedModel = model),
          onPermissionChanged: (mode) =>
              setState(() => _selectedPermission = mode),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Project icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.primaryContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Project name
                    Text(
                      project.data.name,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Worktree path
                    if (worktree != null)
                      Text(
                        worktree.data.worktreeRoot,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 24),
                    // Welcome message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Welcome to CC-Insights',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a new conversation by typing a message below, '
                            'or click "New Chat" in the sidebar to create a '
                            'chat.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Message input - creates a new chat on submit
        MessageInput(
          onSubmit: (text, images) =>
              _createChatAndSendMessage(context, text, images),
        ),
      ],
    );
  }

  /// Creates a new chat, selects it, and sends the first message.
  Future<void> _createChatAndSendMessage(
    BuildContext context,
    String text,
    List<AttachedImage> images,
  ) async {
    if (text.trim().isEmpty && images.isEmpty) return;

    final selection = context.read<SelectionState>();
    final worktree = selection.selectedWorktree;
    if (worktree == null) return;

    final project = context.read<ProjectState>();
    final agentService = context.read<AgentService>();
    final restoreService = context.read<ProjectRestoreService>();

    // Check if agent is connected before trying to start session
    if (!agentService.isConnected) {
      _showNotConnectedDialog(context, agentService);
      return;
    }

    // Generate a chat name from the first message (truncated)
    final chatName = _generateChatName(text);

    // Create a new chat in the worktree
    final chat = ChatState.create(
      name: chatName,
      worktreeRoot: worktree.data.worktreeRoot,
    );

    // Apply the selected model and permission mode
    chat.setModel(_selectedModel);
    chat.setPermissionMode(_selectedPermission);

    // Add the chat to the worktree and select it
    worktree.addChat(chat, select: true);
    selection.selectChat(chat);

    // Persist the new chat to projects.json (fire-and-forget with error logging)
    restoreService
        .addChatToWorktree(
          project.data.repoRoot,
          worktree.data.worktreeRoot,
          chat,
        )
        .catchError((error) {
      developer.log(
        'Failed to persist chat: $error',
        name: 'ConversationPanel',
        level: 900, // Warning level
      );
    });

    // Create a session update handler for this chat
    final updateHandler = _createUpdateHandler(chat);

    // Start ACP session with the first message (including images if attached)
    try {
      await chat.startAcpSession(
        agentService: agentService,
        updateHandler: updateHandler,
        prompt: text,
        images: images,
      );
    } catch (e) {
      // Show error in conversation
      chat.addEntry(TextOutputEntry(
        timestamp: DateTime.now(),
        text: 'Failed to start session: $e',
        contentType: 'error',
      ));
    }
  }

  /// Creates a SessionUpdateHandler that routes updates to the chat.
  SessionUpdateHandler _createUpdateHandler(ChatState chat) {
    return SessionUpdateHandler(
      onAgentMessage: (text) {
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: text,
          contentType: 'assistant',
        ));
      },
      onThinkingMessage: (text) {
        chat.addEntry(TextOutputEntry(
          timestamp: DateTime.now(),
          text: text,
          contentType: 'thinking',
        ));
      },
      onToolCall: (info) {
        chat.addEntry(ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: info.title,
          toolInput: info.rawInput ?? {},
          toolUseId: info.toolCallId,
        ));
      },
      onToolCallUpdate: (info) {
        // Tool call updates could be used to update the tool result
        // For now, we'll add a tool result entry when status is complete
        if (info.status?.name == 'complete' && info.rawOutput != null) {
          chat.addEntry(ToolResultEntry(
            timestamp: DateTime.now(),
            toolUseId: info.toolCallId,
            result: info.rawOutput,
            isError: false,
          ));
        }
      },
    );
  }

  /// Generates a chat name from the first message.
  String _generateChatName(String message) {
    // Take first 30 chars, truncate at word boundary if possible
    final trimmed = message.trim();
    if (trimmed.length <= 30) return trimmed;

    final truncated = trimmed.substring(0, 30);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > 15) {
      return '${truncated.substring(0, lastSpace)}...';
    }
    return '$truncated...';
  }
}

/// Header for the welcome card with model/permission selectors.
///
/// Similar layout to _ConversationHeader but for the welcome state.
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.model,
    required this.permissionMode,
    required this.onModelChanged,
    required this.onPermissionChanged,
  });

  final ClaudeModel model;
  final PermissionMode permissionMode;
  final ValueChanged<ClaudeModel> onModelChanged;
  final ValueChanged<PermissionMode> onPermissionChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // Left side: "New Chat" label and dropdowns
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_comment_outlined,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'New Chat',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CompactDropdown(
                    value: model.label,
                    items: ClaudeModel.values.map((m) => m.label).toList(),
                    onChanged: (value) {
                      final selected = ClaudeModel.values.firstWhere(
                        (m) => m.label == value,
                        orElse: () => ClaudeModel.sonnet,
                      );
                      onModelChanged(selected);
                    },
                  ),
                  const SizedBox(width: 8),
                  _CompactDropdown(
                    value: permissionMode.label,
                    items: PermissionMode.values.map((m) => m.label).toList(),
                    onChanged: (value) {
                      final selected = PermissionMode.values.firstWhere(
                        (m) => m.label == value,
                        orElse: () => PermissionMode.defaultMode,
                      );
                      onPermissionChanged(selected);
                    },
                  ),
                ],
              ),
            ),
          ),
          // Right side: empty for new chat (no usage data yet)
        ],
      ),
    );
  }
}

/// Represents a saved scroll position in a conversation list.
class _ScrollPosition {
  final int topVisibleIndex;  // Index of the first visible item
  final double offsetInItem;  // Pixel offset within that item
  final bool wasAtBottom;

  _ScrollPosition({
    required this.topVisibleIndex,
    required this.offsetInItem,
    required this.wasAtBottom,
  });
}
