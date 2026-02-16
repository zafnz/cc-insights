import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/output_entry.dart';
import '../services/backend_service.dart';
import '../services/chat_session_service.dart';
import '../state/selection_state.dart';
import '../config/design_tokens.dart';
import '../widgets/ask_user_question_dialog.dart';
import '../widgets/message_input.dart';
import '../widgets/output_entries.dart';
import '../widgets/permission_dialog.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'conversation_header.dart';
import 'welcome_card.dart';

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

  /// The Chat we're currently listening to.
  Chat? _listeningToChat;
  ChatConversationState? _listeningToConversations;
  ChatPermissionState? _listeningToPermissions;
  ChatSessionState? _listeningToSession;

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

  /// Cache the last permission request for animation-out.
  /// This ensures we can still render the widget while animating out.
  sdk.PermissionRequest? _cachedPermission;
  bool _permissionWasAtBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _permissionAnimController = AnimationController(
      duration: AnimDurations.standard,
      vsync: this,
    );
    _permissionAnimation = CurvedAnimation(
      parent: _permissionAnimController,
      curve: Curves.easeOut,
    );
    // Handle permission animation lifecycle
    _permissionAnimController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        final shouldScrollToBottom = _permissionWasAtBottom;
        _permissionWasAtBottom = false;
        // Clear cached permission when animation completes reverse
        setState(() {
          _cachedPermission = null;
        });
        if (shouldScrollToBottom) {
          _scheduleScrollToBottom();
        }
      } else if (status == AnimationStatus.completed) {
        // Permission widget fully visible - if user was at bottom, scroll there
        // This handles the case where the animation changed the list height
        // Use post-frame callback to ensure layout is fully settled
        if (_isAtBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
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
    // Consider "at bottom" if within a dynamic threshold of the end.
    // For very short lists, keep the threshold small so "top" isn't
    // incorrectly treated as "bottom".
    final atBottom = _isNearBottom(position);

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

  /// Returns true if the scroll position is close enough to the bottom
  /// to be treated as "at bottom" for auto-scroll purposes.
  bool _isNearBottom(ScrollPosition position) {
    final maxExtent = position.maxScrollExtent;
    if (maxExtent <= 0) {
      return true;
    }

    final threshold = math.min(50.0, maxExtent * 0.2);
    return position.pixels >= maxExtent - threshold;
  }

  /// Scrolls to the bottom of the list with animation.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AnimDurations.fast,
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
    final wasAtBottom = _isNearBottom(position);

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
          // ignore: invalid_use_of_visible_for_testing_member
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
    _listeningToConversations?.removeListener(_onChatChanged);
    _listeningToPermissions?.removeListener(_onChatChanged);
    _listeningToSession?.removeListener(_onChatChanged);
    super.dispose();
  }

  /// Called when the Chat changes (entries added, etc.)
  void _onChatChanged() {
    if (!mounted) return;

    // Check if new entries were added
    final conversation = _listeningToChat?.conversations.selectedConversation;
    final currentCount = conversation?.entries.length ?? 0;
    final newEntriesAdded = currentCount > _lastEntryCount;

    // Check scroll position directly when new entries are added
    // The scroll listener may not have fired yet, so we recompute here
    if (newEntriesAdded && _scrollController.hasClients) {
      final position = _scrollController.position;
      final wasAtBottom = _isNearBottom(position);

      // Capture current scroll position BEFORE setState
      // SuperListView may adjust scroll position when items are added
      final savedPixels = position.pixels;

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
      } else {
        // User was scrolled up - preserve their exact position
        // Use nested postFrameCallbacks to ensure correction happens after
        // SuperListView's own layout adjustments
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final currentPixels = _scrollController.position.pixels;
              if ((currentPixels - savedPixels).abs() > 1.0) {
                developer.log(
                  'Correcting scroll: was $savedPixels, became $currentPixels, restoring to $savedPixels',
                  name: 'ConversationPanel',
                );
                _scrollController.jumpTo(savedPixels);
              }
            }
          });
        });
      }
    } else if (newEntriesAdded && !_scrollController.hasClients) {
      // No clients yet (first build), schedule scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } else if (!newEntriesAdded && _scrollController.hasClients) {
      // No new entries, but content may have changed (streaming deltas).
      // If user is at bottom and any entry is streaming, keep scrolled down.
      final hasStreamingEntry =
          conversation?.entries.any(
            (e) =>
                (e is TextOutputEntry && e.isStreaming) ||
                (e is ToolUseOutputEntry && e.isStreaming),
          ) ??
          false;
      if (hasStreamingEntry && _isAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    }

    _lastEntryCount = currentCount;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    context.watch<BackendService>();
    final selection = context.watch<SelectionState>();
    final chat = selection.selectedChat;

    // Listen to conversation, permission, and session state changes for UI updates.
    if (chat != _listeningToChat) {
      _listeningToConversations?.removeListener(_onChatChanged);
      _listeningToPermissions?.removeListener(_onChatChanged);
      _listeningToSession?.removeListener(_onChatChanged);
      _listeningToChat = chat;
      _listeningToConversations = chat?.conversations;
      _listeningToPermissions = chat?.permissions;
      _listeningToSession = chat?.session;
      _listeningToConversations?.addListener(_onChatChanged);
      _listeningToPermissions?.addListener(_onChatChanged);
      _listeningToSession?.addListener(_onChatChanged);
    }

    final conversation = chat?.conversations.selectedConversation;

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
      if (conversation != null &&
          _savedScrollPositions.containsKey(conversation.id)) {
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
    final currentPermission = chat?.permissions.pendingPermission;
    final showPermission = currentPermission != null;

    // Update cache and animate
    if (showPermission) {
      if (_cachedPermission == null) {
        _permissionWasAtBottom = _isAtBottom;
      }
      _cachedPermission = currentPermission;
      if (!_permissionAnimController.isCompleted) {
        _permissionAnimController.forward();
      }
    } else if (_cachedPermission != null) {
      // Permission was cleared, animate out
      _permissionAnimController.reverse();
    }

    // Determine if we should show the permission widget
    // Show if we have a cached permission AND either:
    // - animation is animating forward (including value=0 at start)
    // - animation value > 0 (during animation or completed)
    final shouldShowPermissionWidget =
        _cachedPermission != null &&
        (_permissionAnimController.status == AnimationStatus.forward ||
            _permissionAnimController.status == AnimationStatus.completed ||
            _permissionAnimController.value > 0);

    // Check if Claude is working (for spinner display)
    final isWorking = chat?.session.isWorking ?? false;
    final isCompacting = chat?.session.isCompacting ?? false;

    // Find the agent for this subagent conversation (if any)
    final Agent? agent = !isPrimary && chat != null
        ? chat.agents.activeAgents.values.cast<Agent?>().firstWhere(
            (a) => a?.conversationId == conversation.id,
            orElse: () => null,
          )
        : null;

    return Column(
      children: [
        // Conversation header - wrapped in ListenableBuilder to rebuild on chat changes
        ListenableBuilder(
          listenable: Listenable.merge([
            chat!.settings,
            chat.metrics,
            chat.session,
            chat.agents,
            chat.conversations,
          ]),
          builder: (context, _) =>
              ConversationHeader(conversation: conversation, chat: chat),
        ),
        // Subagent status header (only for subagent conversations)
        if (!isPrimary)
          SubagentStatusHeader(conversation: conversation, agent: agent),
        // Output entries list
        Expanded(
          child: conversation.entries.isEmpty && !isWorking
              ? _ConversationPlaceholder(
                  message: isPrimary
                      ? 'No messages yet. Start a conversation!'
                      : 'No output from this subagent yet.',
                )
              : _EntryList(
                  conversation: conversation,
                  chat: chat,
                  scrollController: _scrollController,
                  listController: _listController,
                  showWorkingIndicator: isPrimary && isWorking,
                  isCompacting: isCompacting,
                ),
        ),
        // Bottom area: agent-removed banner, permission widget, or message input
        if (isPrimary && chat.agents.agentRemoved)
          _AgentRemovedBanner(message: chat.agents.missingAgentMessage)
        else if (isPrimary)
          shouldShowPermissionWidget
              ? _PermissionSection(
                  chat: chat,
                  permission: _cachedPermission,
                  animation: _permissionAnimation,
                  onClearContextPlanApproval: (chat, planText) => context
                      .read<ChatSessionService>()
                      .approvePlanWithClearContext(chat, planText),
                )
              : MessageInput(
                  key: ValueKey('input-${chat.data.id}'),
                  initialText: chat.viewState.draftText,
                  onTextChanged: (text) => chat.viewState.draftText = text,
                  onSubmit: (text, images, displayFormat) =>
                      context.read<ChatSessionService>().submitMessage(
                        chat,
                        text: text,
                        images: images,
                        displayFormat: displayFormat,
                      ),
                  isWorking: isWorking,
                  onInterrupt: isWorking
                      ? () => context.read<ChatSessionService>().interrupt(chat)
                      : null,
                ),
      ],
    );
  }
}

/// Displays the list of output entries for a conversation.
class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.conversation,
    required this.chat,
    required this.scrollController,
    required this.listController,
    this.showWorkingIndicator = false,
    this.isCompacting = false,
  });

  final ConversationData conversation;
  final Chat? chat;
  final ScrollController scrollController;
  final ListController listController;
  final bool showWorkingIndicator;
  final bool isCompacting;

  @override
  Widget build(BuildContext context) {
    final entries = conversation.entries;
    final selection = context.read<SelectionState>();
    final projectDir = selection.selectedChat?.data.worktreeRoot;
    final isSubagent = !conversation.isPrimary;

    // Hide the working indicator when the last entry is streaming text,
    // since the streaming cursor already indicates Claude is working.
    final lastEntry = entries.isNotEmpty ? entries.last : null;
    final lastEntryIsStreaming =
        lastEntry is TextOutputEntry && lastEntry.isStreaming;
    final showIndicator = showWorkingIndicator && !lastEntryIsStreaming;

    final itemCount = entries.length + (showIndicator ? 1 : 0);

    return SuperListView.builder(
      controller: scrollController,
      listController: listController,
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Working indicator is at the end (bottom visually)
        if (showIndicator && index == entries.length) {
          final agentName = switch (chat?.settings.model.backend) {
            sdk.BackendType.codex => 'Codex',
            sdk.BackendType.acp => 'ACP',
            _ => 'Claude',
          };
          return WorkingIndicator(
            agentName: agentName,
            isCompacting: isCompacting,
            stopwatch: chat?.session.workingStopwatch,
          );
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
}

/// Builds the permission widget with slide-up animation.
class _PermissionSection extends StatelessWidget {
  const _PermissionSection({
    required this.chat,
    required this.permission,
    required this.animation,
    required this.onClearContextPlanApproval,
  });

  final Chat chat;
  final sdk.PermissionRequest? permission;
  final Animation<double> animation;
  final Future<void> Function(Chat, String) onClearContextPlanApproval;

  @override
  Widget build(BuildContext context) {
    if (permission == null) {
      return const SizedBox.shrink();
    }

    final perm = permission!;
    final isAskUserQuestion = perm.toolName == 'AskUserQuestion';
    final isExitPlanMode = perm.toolName == 'ExitPlanMode';
    final sessionService = context.read<ChatSessionService>();

    Widget dialogWidget;
    if (isAskUserQuestion) {
      dialogWidget = AskUserQuestionDialog(
        request: perm,
        onSubmit: (answers) {
          sessionService.allowPermission(chat, updatedInput: {'answers': answers});
        },
        onCancel: () =>
            sessionService.denyPermission(chat, 'User cancelled the question'),
      );
    } else {
      final selection = context.read<SelectionState>();
      final backendProvider = switch (chat.settings.model.backend) {
        sdk.BackendType.codex => sdk.BackendProvider.codex,
        sdk.BackendType.acp => sdk.BackendProvider.acp,
        sdk.BackendType.directCli => sdk.BackendProvider.claude,
      };
      dialogWidget = PermissionDialog(
        request: perm,
        projectDir: selection.selectedChat?.data.worktreeRoot,
        onAllow:
            ({
              Map<String, dynamic>? updatedInput,
              List<dynamic>? updatedPermissions,
            }) {
              sessionService.allowPermission(
                chat,
                updatedInput: updatedInput,
                updatedPermissions: updatedPermissions,
              );
            },
        onDeny: (message, {bool interrupt = false}) => sessionService
            .denyPermission(chat, message, interrupt: interrupt),
        onClearContextAndAcceptEdits: isExitPlanMode
            ? (planText) => onClearContextPlanApproval(chat, planText)
            : null,
        provider: backendProvider,
      );
    }

    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 1.0, // Align to bottom (slide up from bottom)
      child: dialogWidget,
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

/// Represents a saved scroll position in a conversation list.
class _ScrollPosition {
  final int topVisibleIndex; // Index of the first visible item
  final double offsetInItem; // Pixel offset within that item
  final bool wasAtBottom;

  _ScrollPosition({
    required this.topVisibleIndex,
    required this.offsetInItem,
    required this.wasAtBottom,
  });
}

/// Banner shown when a chat's agent has been removed from the registry.
///
/// Replaces the message input to indicate that no new messages can be sent,
/// while the chat history remains visible.
class _AgentRemovedBanner extends StatelessWidget {
  const _AgentRemovedBanner({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: 16, color: colorScheme.error),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message ??
                  'Agent removed \u2014 this chat can no longer send messages',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
