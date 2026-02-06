import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/conversation.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/backend_service.dart';
import '../services/project_restore_service.dart';
import '../services/runtime_config.dart';
import '../services/sdk_message_handler.dart';
import '../state/selection_state.dart';
import '../widgets/ask_user_question_dialog.dart';
import '../widgets/context_indicator.dart';
import '../widgets/cost_indicator.dart';
import '../widgets/message_input.dart';
import '../widgets/output_entries.dart';
import '../widgets/permission_dialog.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

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
                  chat: chat,
                  showWorkingIndicator: isPrimary && isWorking,
                  isCompacting: isCompacting,
                ),
        ),
        // Bottom area: either permission widget or message input
        if (isPrimary)
          shouldShowPermissionWidget
              ? _buildPermissionWidget(chat!)
              : MessageInput(
                  key: ValueKey('input-${chat!.data.id}'),
                  initialText: chat.draftText,
                  onTextChanged: (text) => chat.draftText = text,
                  onSubmit: (text, images) =>
                      _handleSubmit(context, text, images),
                  isWorking: isWorking,
                  onInterrupt: isWorking ? () => _handleInterrupt(chat) : null,
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
      );
    } else {
      final selection = context.read<SelectionState>();
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
        onDeny: (message) => chat.denyPermission(message),
      );
    }

    return SizeTransition(
      sizeFactor: _permissionAnimation,
      axisAlignment: 1.0, // Align to bottom (slide up from bottom)
      child: dialogWidget,
    );
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
            startTime: chat?.workingStartTime,
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
    final messageHandler = context.read<SdkMessageHandler>();

    if (!chat.hasActiveSession) {
      // First message - start a new session with the prompt
      // Add user input entry first
      chat.addEntry(UserInputEntry(
        timestamp: DateTime.now(),
        text: text,
        images: images,
      ));

      // Generate a better title for the chat if it's new (fire-and-forget)
      if (chat.isAutoGeneratedName) {
        messageHandler.generateChatTitle(chat, text);
      }

      try {
        await chat.startSession(
          backend: backend,
          messageHandler: messageHandler,
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
    final backendService = context.watch<BackendService>();

    final isSubagent = !conversation.isPrimary;

    // Don't show the toolbar for subagent conversations (title is in panel header)
    if (isSubagent) {
      return const SizedBox.shrink();
    }

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
          final isBackendLocked = chat.hasStarted;

          return Row(
            children: [
              // Left side: agent, model, and permission dropdowns
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CompactDropdown(
                        value: _agentLabel(chat.model.backend),
                        items: _agentItems,
                        tooltip: 'Agent',
                        isEnabled: !isBackendLocked,
                        onChanged: (value) {
                          unawaited(
                            _handleAgentChange(context, chat, value),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final models = ChatModelCatalog.forBackend(
                            chat.model.backend,
                          );
                          final selected = models.firstWhere(
                            (m) => m.id == chat.model.id,
                            orElse: () => chat.model,
                          );
                          final isModelLoading =
                              chat.model.backend == sdk.BackendType.codex &&
                              backendService.isModelListLoadingFor(
                                chat.model.backend,
                              );
                          return _CompactDropdown(
                            value: selected.label,
                            items: models.map((m) => m.label).toList(),
                            isLoading: isModelLoading,
                            tooltip: 'Model',
                            onChanged: (value) {
                              final model = models.firstWhere(
                                (m) => m.label == value,
                                orElse: () => selected,
                              );
                              chat.setModel(model);
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _CompactDropdown(
                        value: chat.permissionMode.label,
                        items: PermissionMode.values
                            .map((m) => m.label)
                            .toList(),
                        tooltip: 'Permissions',
                        onChanged: (value) {
                          final mode = PermissionMode.values.firstWhere(
                            (m) => m.label == value,
                            orElse: () => PermissionMode.defaultMode,
                          );
                          chat.setPermissionMode(mode);
                        },
                      ),
                      // Reasoning effort dropdown (Codex only)
                      if (chat.model.backend == sdk.BackendType.codex) ...[
                        const SizedBox(width: 8),
                        _CompactDropdown(
                          value: chat.reasoningEffort?.label ?? 'Default',
                          items: _reasoningEffortItems,
                          tooltip: 'Reasoning',
                          onChanged: (value) {
                            final effort = _reasoningEffortFromLabel(value);
                            chat.setReasoningEffort(effort);
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
                  timingStats: chat.timingStats,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static const List<String> _agentItems = ['Claude', 'Codex'];

  /// Labels for reasoning effort dropdown.
  /// 'Default' means null (use model's default).
  static const List<String> _reasoningEffortItems = [
    'Default',
    'None',
    'Minimal',
    'Low',
    'Medium',
    'High',
    'Extra High',
  ];

  String _agentLabel(sdk.BackendType backend) {
    return backend == sdk.BackendType.codex ? 'Codex' : 'Claude';
  }

  sdk.BackendType _backendFromAgent(String value) {
    return value == 'Codex' ? sdk.BackendType.codex : sdk.BackendType.directCli;
  }

  /// Converts a dropdown label to a ReasoningEffort value.
  /// Returns null for 'Default'.
  sdk.ReasoningEffort? _reasoningEffortFromLabel(String label) {
    return switch (label) {
      'Default' => null,
      'None' => sdk.ReasoningEffort.none,
      'Minimal' => sdk.ReasoningEffort.minimal,
      'Low' => sdk.ReasoningEffort.low,
      'Medium' => sdk.ReasoningEffort.medium,
      'High' => sdk.ReasoningEffort.high,
      'Extra High' => sdk.ReasoningEffort.xhigh,
      _ => null,
    };
  }

  Future<void> _handleAgentChange(
    BuildContext context,
    ChatState chat,
    String value,
  ) async {
    final backendType = _backendFromAgent(value);
    if (backendType == chat.model.backend) return;

    if (chat.hasActiveSession) {
      _showBackendSwitchError(
        context,
        'End the active session before switching agents.',
      );
      return;
    }

    if (chat.hasStarted) {
      _showBackendSwitchError(
        context,
        'Backend is locked once a chat has started.',
      );
      return;
    }

    final backendService = context.read<BackendService>();
    await backendService.start(type: backendType);
    final error = backendService.errorFor(backendType);
    if (error != null) {
      _showBackendSwitchError(context, error);
      return;
    }

    final model = ChatModelCatalog.defaultForBackend(backendType, null);
    chat.setModel(model);
  }

  void _showBackendSwitchError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
    this.isLoading = false,
    this.tooltip,
    this.isEnabled = true,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final bool isLoading;
  final String? tooltip;
  final bool isEnabled;

  @override
  State<_CompactDropdown> createState() => _CompactDropdownState();
}

class _CompactDropdownState extends State<_CompactDropdown> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = widget.isEnabled;
    final isHovered = isEnabled && _isHovered;
    final textColor =
        isEnabled ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final iconColor = isEnabled
        ? colorScheme.onSurface.withOpacity(0.7)
        : colorScheme.onSurfaceVariant.withOpacity(0.7);

    return PopupMenuButton<String>(
      initialValue: widget.value,
      enabled: isEnabled,
      onSelected: isEnabled ? widget.onChanged : null,
      tooltip: widget.tooltip ?? '',
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
            cursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
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
        cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: isEnabled
            ? (_) => setState(() => _isHovered = true)
            : null,
        onExit: isEnabled ? (_) => setState(() => _isHovered = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isEnabled
                ? (isHovered
                    ? colorScheme.primary.withOpacity(0.1)
                    : colorScheme.surfaceContainerHigh)
                : colorScheme.surfaceContainerHigh.withOpacity(0.6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.isLoading) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: iconColor,
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
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final backendService = context.watch<BackendService>();
    final worktree = selection.selectedWorktree;
    final defaultModel = ChatModelCatalog.defaultForBackend(
      RuntimeConfig.instance.defaultBackend,
      RuntimeConfig.instance.defaultModel,
    );
    final defaultPermissionMode = PermissionMode.fromApiName(
      RuntimeConfig.instance.defaultPermissionMode,
    );

    Widget buildHeader() {
      final model = worktree?.welcomeModel ?? defaultModel;
      final isModelLoading =
          model.backend == sdk.BackendType.codex &&
          backendService.isModelListLoadingFor(model.backend);
      return _WelcomeHeader(
        model: model,
        permissionMode: worktree?.welcomePermissionMode ?? defaultPermissionMode,
        reasoningEffort: worktree?.welcomeReasoningEffort,
        isModelLoading: isModelLoading,
        onAgentChanged: (backendType) async {
          final backendService = context.read<BackendService>();
          await backendService.start(type: backendType);
          final error = backendService.errorFor(backendType);
          if (error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
            return;
          }

          final model = ChatModelCatalog.defaultForBackend(backendType, null);
          worktree?.welcomeModel = model;
        },
        onModelChanged: (model) => worktree?.welcomeModel = model,
        onPermissionChanged: (mode) =>
            worktree?.welcomePermissionMode = mode,
        onReasoningChanged: (effort) =>
            worktree?.welcomeReasoningEffort = effort,
      );
    }

    return Column(
      children: [
        // Header with model/permission selectors
        if (worktree == null)
          buildHeader()
        else
          ListenableBuilder(
            listenable: worktree,
            builder: (context, _) => buildHeader(),
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
        // Use worktree path in key so each worktree gets its own input
        MessageInput(
          key: ValueKey(
            'input-welcome-${worktree?.data.worktreeRoot ?? 'none'}',
          ),
          initialText: worktree?.welcomeDraftText ?? '',
          onTextChanged: (text) => worktree?.welcomeDraftText = text,
          onSubmit: (text, images) =>
              _createChatAndSendMessage(context, worktree, text, images),
        ),
      ],
    );
  }

  /// Creates a new chat, selects it, and sends the first message.
  static Future<void> _createChatAndSendMessage(
    BuildContext context,
    WorktreeState? worktree,
    String text,
    List<AttachedImage> images,
  ) async {
    if (text.trim().isEmpty && images.isEmpty) return;

    final selection = context.read<SelectionState>();
    if (worktree == null) return;

    final project = context.read<ProjectState>();
    final backend = context.read<BackendService>();
    final messageHandler = context.read<SdkMessageHandler>();
    final restoreService = context.read<ProjectRestoreService>();

    // Determine the chat name based on AI label setting
    final aiLabelsEnabled = RuntimeConfig.instance.aiChatLabelsEnabled;
    final String chatName;
    final bool isAutoGenerated;
    if (aiLabelsEnabled) {
      // Use message-based name as placeholder for AI-generated title
      chatName = _generateChatName(text);
      isAutoGenerated = true;
    } else {
      // Use sequential "Chat #N" naming
      chatName = 'Chat #${worktree.chats.length + 1}';
      isAutoGenerated = false;
    }

    // Create a new chat in the worktree
    final chat = ChatState.create(
      name: chatName,
      worktreeRoot: worktree.data.worktreeRoot,
      isAutoGeneratedName: isAutoGenerated,
    );

    // Apply the selected model, permission mode, and reasoning effort
    // from the worktree's welcome screen state
    chat.setModel(worktree.welcomeModel);
    chat.setPermissionMode(worktree.welcomePermissionMode);
    chat.setReasoningEffort(worktree.welcomeReasoningEffort);

    // Clear the welcome draft since it's being submitted as a chat
    worktree.welcomeDraftText = '';

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

    // Add the user's message
    final userEntry = UserInputEntry(
      timestamp: DateTime.now(),
      text: text,
      images: images,
    );
    chat.addEntry(userEntry);

    // Generate a better title for the chat (fire-and-forget)
    messageHandler.generateChatTitle(chat, text);

    // Start session with the first message (including images if attached)
    try {
      await chat.startSession(
        backend: backend,
        messageHandler: messageHandler,
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

  /// Generates a chat name from the first message.
  static String _generateChatName(String message) {
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
    required this.reasoningEffort,
    required this.onModelChanged,
    required this.onPermissionChanged,
    required this.onAgentChanged,
    required this.onReasoningChanged,
    required this.isModelLoading,
  });

  final ChatModel model;
  final PermissionMode permissionMode;
  final sdk.ReasoningEffort? reasoningEffort;
  final ValueChanged<ChatModel> onModelChanged;
  final ValueChanged<PermissionMode> onPermissionChanged;
  final ValueChanged<sdk.BackendType> onAgentChanged;
  final ValueChanged<sdk.ReasoningEffort?> onReasoningChanged;
  final bool isModelLoading;

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
                    value: _agentLabel(model.backend),
                    items: _agentItems,
                    tooltip: 'Agent',
                    onChanged: (value) {
                      onAgentChanged(_backendFromAgent(value));
                    },
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final models = ChatModelCatalog.forBackend(model.backend);
                      final selected = models.firstWhere(
                        (m) => m.id == model.id,
                        orElse: () => model,
                      );
                      return _CompactDropdown(
                        value: selected.label,
                        items: models.map((m) => m.label).toList(),
                        isLoading: isModelLoading,
                        tooltip: 'Model',
                        onChanged: (value) {
                          final next = models.firstWhere(
                            (m) => m.label == value,
                            orElse: () => selected,
                          );
                          onModelChanged(next);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _CompactDropdown(
                    value: permissionMode.label,
                    items: PermissionMode.values.map((m) => m.label).toList(),
                    tooltip: 'Permissions',
                    onChanged: (value) {
                      final selected = PermissionMode.values.firstWhere(
                        (m) => m.label == value,
                        orElse: () => PermissionMode.defaultMode,
                      );
                      onPermissionChanged(selected);
                    },
                  ),
                  // Reasoning effort dropdown (Codex only)
                  if (model.backend == sdk.BackendType.codex) ...[
                    const SizedBox(width: 8),
                    _CompactDropdown(
                      value: reasoningEffort?.label ?? 'Default',
                      items: _reasoningEffortItems,
                      tooltip: 'Reasoning',
                      onChanged: (value) {
                        final effort = _reasoningEffortFromLabel(value);
                        onReasoningChanged(effort);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Right side: empty for new chat (no usage data yet)
        ],
      ),
    );
  }

  static const List<String> _agentItems = ['Claude', 'Codex'];

  static const List<String> _reasoningEffortItems = [
    'Default',
    'None',
    'Minimal',
    'Low',
    'Medium',
    'High',
    'Extra High',
  ];

  String _agentLabel(sdk.BackendType backend) {
    return backend == sdk.BackendType.codex ? 'Codex' : 'Claude';
  }

  sdk.BackendType _backendFromAgent(String value) {
    return value == 'Codex' ? sdk.BackendType.codex : sdk.BackendType.directCli;
  }

  sdk.ReasoningEffort? _reasoningEffortFromLabel(String label) {
    return switch (label) {
      'Default' => null,
      'None' => sdk.ReasoningEffort.none,
      'Minimal' => sdk.ReasoningEffort.minimal,
      'Low' => sdk.ReasoningEffort.low,
      'Medium' => sdk.ReasoningEffort.medium,
      'High' => sdk.ReasoningEffort.high,
      'Extra High' => sdk.ReasoningEffort.xhigh,
      _ => null,
    };
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
