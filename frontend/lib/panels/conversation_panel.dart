import 'dart:async';
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
import '../services/event_handler.dart';
import '../services/internal_tools_service.dart';
import '../state/selection_state.dart';
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

  /// Cache the last permission request for animation-out.
  /// This ensures we can still render the widget while animating out.
  sdk.PermissionRequest? _cachedPermission;
  bool _permissionWasAtBottom = false;

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
      final hasStreamingEntry = conversation?.entries.any((e) =>
              (e is TextOutputEntry && e.isStreaming) ||
              (e is ToolUseOutputEntry && e.isStreaming)) ??
          false;
      if (hasStreamingEntry && _isAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scrollController.hasClients) {
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
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
    final currentPermission = chat?.pendingPermission;
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
    final shouldShowPermissionWidget = _cachedPermission != null &&
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
          builder: (context, _) => ConversationHeader(
            conversation: conversation,
            chat: chat,
          ),
        ),
        // Subagent status header (only for subagent conversations)
        if (!isPrimary)
          SubagentStatusHeader(
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
                  chat: chat,
                  showWorkingIndicator: isPrimary && isWorking,
                  isCompacting: isCompacting,
                ),
        ),
        // Bottom area: either permission widget or message input
        if (isPrimary)
          shouldShowPermissionWidget
              ? _buildPermissionWidget(chat)
              : MessageInput(
                  key: ValueKey('input-${chat.data.id}'),
                  initialText: chat.draftText,
                  onTextChanged: (text) => chat.draftText = text,
                  onSubmit: (text, images, displayFormat) =>
                      _handleSubmit(context, text, images, displayFormat),
                  isWorking: isWorking,
                  onInterrupt:
                      isWorking ? () => _handleInterrupt(chat) : null,
                ),
      ],
    );
  }

  /// Build the permission widget with slide-up animation.
  Widget _buildPermissionWidget(ChatState chat) {
    // Use cached permission to ensure we have a valid request during animation
    final permission = _cachedPermission;
    if (permission == null) {
      return const SizedBox.shrink();
    }

    // Determine which widget to show based on tool name
    final isAskUserQuestion = permission.toolName == 'AskUserQuestion';

    final isExitPlanMode = permission.toolName == 'ExitPlanMode';

    Widget dialogWidget;
    if (isAskUserQuestion) {
      dialogWidget = AskUserQuestionDialog(
        request: permission,
        onSubmit: (answers) {
          // Submit answers through the permission system
          chat.allowPermission(
            updatedInput: {'answers': answers},
          );
        },
        onCancel: () => chat.denyPermission('User cancelled the question'),
      );
    } else {
      final selection = context.read<SelectionState>();
      // Derive provider from chat's backend type
      final provider = chat.model.backend == sdk.BackendType.codex
          ? sdk.BackendProvider.codex
          : sdk.BackendProvider.claude;
      dialogWidget = PermissionDialog(
        request: permission,
        projectDir: selection.selectedChat?.data.worktreeRoot,
        onAllow: ({
          Map<String, dynamic>? updatedInput,
          List<dynamic>? updatedPermissions,
        }) {
          chat.allowPermission(
            updatedInput: updatedInput,
            updatedPermissions: updatedPermissions,
          );
        },
        onDeny: (message, {bool interrupt = false}) =>
            chat.denyPermission(message, interrupt: interrupt),
        onClearContextAndAcceptEdits: isExitPlanMode
            ? (planText) => _handleClearContextPlanApproval(chat, planText)
            : null,
        provider: provider,
      );
    }

    return SizeTransition(
      sizeFactor: _permissionAnimation,
      axisAlignment: 1.0, // Align to bottom (slide up from bottom)
      child: dialogWidget,
    );
  }

  /// Handles Option 1: Clear context + Accept edits.
  ///
  /// 1. Allows the ExitPlanMode permission (so CLI gets a response)
  /// 2. Resets the session (clears context)
  /// 3. Switches to acceptEdits mode
  /// 4. Starts a new session with the plan text as the prompt
  Future<void> _handleClearContextPlanApproval(
    ChatState chat,
    String planText,
  ) async {
    // 1. Allow the ExitPlanMode permission first
    chat.allowPermission(
      updatedPermissions: [
        {
          'type': 'setMode',
          'mode': 'acceptEdits',
          'destination': 'session',
        },
      ],
    );

    // 2. Reset session (clears context, stops session)
    await chat.resetSession();

    // 3. Switch to acceptEdits mode for the new session
    chat.setPermissionMode(PermissionMode.acceptEdits);

    // 4. Start new session with plan as prompt
    if (!mounted) return;
    final backend = context.read<BackendService>();
    final eventHandler = context.read<EventHandler>();
    final internalTools = context.read<InternalToolsService>();

    final prompt =
        'The user has approved your plan and wants you to execute it '
        'with a clear context. Here is the approved plan:\n\n'
        '$planText\n\n'
        'Begin implementation.';

    chat.addEntry(UserInputEntry(
      timestamp: DateTime.now(),
      text: '[Plan approved - clear context + accept edits]',
    ));

    try {
      await chat.startSession(
        backend: backend,
        eventHandler: eventHandler,
        prompt: prompt,
        internalToolsService: internalTools,
      );
    } catch (e) {
      chat.addEntry(TextOutputEntry(
        timestamp: DateTime.now(),
        text: 'Failed to start session: $e',
        contentType: 'error',
      ));
    }
  }

  Widget _buildEntryList(
    ConversationData conversation, {
    required ChatState? chat,
    bool showWorkingIndicator = false,
    bool isCompacting = false,
  }) {
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
      controller: _scrollController,
      listController: _listController,
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Working indicator is at the end (bottom visually)
        if (showIndicator && index == entries.length) {
          final agentName =
              chat?.model.backend == sdk.BackendType.codex
                  ? 'Codex'
                  : 'Claude';
          return WorkingIndicator(
            agentName: agentName,
            isCompacting: isCompacting,
            stopwatch: chat?.workingStopwatch,
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
    DisplayFormat displayFormat,
  ) async {
    if (text.trim().isEmpty && images.isEmpty) return;

    final selection = context.read<SelectionState>();
    final chat = selection.selectedChat;
    if (chat == null) return;

    // Handle /clear command - reset session without sending to SDK
    if (text.trim() == '/clear') {
      chat.draftText = '';
      await chat.resetSession();
      return;
    }

    // Clear the draft text since it's being submitted
    chat.draftText = '';

    final backend = context.read<BackendService>();
    final eventHandler = context.read<EventHandler>();
    final internalTools = context.read<InternalToolsService>();

    if (!chat.hasActiveSession) {
      // First message - start a new session with the prompt
      // Add user input entry first
      chat.addEntry(UserInputEntry(
        timestamp: DateTime.now(),
        text: text,
        images: images,
        displayFormat: displayFormat,
      ));

      // Generate a better title for the chat if it's new (fire-and-forget)
      if (chat.isAutoGeneratedName) {
        eventHandler.generateChatTitle(chat, text);
      }

      try {
        await chat.startSession(
          backend: backend,
          eventHandler: eventHandler,
          prompt: text,
          images: images,
          internalToolsService: internalTools,
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
        await chat.sendMessage(
          text,
          images: images,
          displayFormat: displayFormat,
        );
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
  final int topVisibleIndex;  // Index of the first visible item
  final double offsetInItem;  // Pixel offset within that item
  final bool wasAtBottom;

  _ScrollPosition({
    required this.topVisibleIndex,
    required this.offsetInItem,
    required this.wasAtBottom,
  });
}
