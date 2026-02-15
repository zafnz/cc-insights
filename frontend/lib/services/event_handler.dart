import 'dart:developer' as developer;

import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        BackendProvider,
        InsightsEvent,
        ToolInvocationEvent,
        ToolCompletionEvent,
        TextEvent,
        UserInputEvent,
        TurnCompleteEvent,
        UsageUpdateEvent,
        RateLimitUpdateEvent,
        SessionInitEvent,
        ConfigOptionsEvent,
        AvailableCommandsEvent,
        SessionModeEvent,
        SessionStatusEvent,
        ContextCompactionEvent,
        SubagentSpawnEvent,
        SubagentCompleteEvent,
        StreamDeltaEvent,
        PermissionRequestEvent,
        ReasoningEffort,
        ToolKind,
        TextKind,
        SessionStatus,
        CompactionTrigger,
        StreamDeltaKind;

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/codex_pricing.dart';
import '../models/output_entry.dart';
import '../models/ticket.dart';
import '../state/rate_limit_state.dart';
import '../state/ticket_board_state.dart';
import 'log_service.dart';
import 'streaming_processor.dart';
import 'ticket_event_bridge.dart';

part 'event_handler_lifecycle.dart';
part 'event_handler_subagents.dart';

/// Base class with shared state for event handling.
///
/// Contains the event routing switch, conversation resolution, tool/text
/// event processing, and cleanup methods. Session lifecycle and subagent
/// management are in part file mixins.
class _EventHandlerBase {
  /// Tool pairing: callId → entry (for updating with result later).
  final Map<String, ToolUseOutputEntry> _toolCallIndex = {};

  /// Agent routing: parentCallId (SDK agent ID) → conversationId.
  final Map<String, String> _agentIdToConversationId = {};

  /// Maps new Task callId → original agent's sdkAgentId (for resumed agents).
  final Map<String, String> _toolUseIdToAgentId = {};

  /// Tracks whether assistant output was added during the current turn.
  final Map<String, bool> _hasAssistantOutputThisTurn = {};

  /// Tracks whether we're expecting a context summary message.
  final Map<String, bool> _expectingContextSummary = {};

  /// Rate limit state for displaying rate limit information.
  final RateLimitState? rateLimitState;

  /// Bridge for ticket status transitions based on chat events.
  final TicketEventBridge _ticketBridge;

  /// Streaming delta processor with its own state machine.
  late final StreamingProcessor _streaming;

  _EventHandlerBase({
    this.rateLimitState,
    TicketBoardState? ticketBoard,
  }) : _ticketBridge = TicketEventBridge(ticketBoard: ticketBoard) {
    _streaming = StreamingProcessor(
      toolCallIndex: _toolCallIndex,
      activeStreamingEntries: _activeStreamingEntries,
      resolveConversationId: _resolveConversationId,
    );
  }

  /// Streaming entries shared between StreamingProcessor and finalization
  /// in _handleText/_handleToolInvocation.
  final Map<String, List<OutputEntry>> _activeStreamingEntries = {};

  /// The current ticket board state, if any.
  TicketBoardState? get ticketBoard => _ticketBridge.ticketBoard;

  set ticketBoard(TicketBoardState? value) =>
      _ticketBridge.ticketBoard = value;

  /// The ticket event bridge for external callers (e.g. ChatState).
  TicketEventBridge get ticketBridge => _ticketBridge;

  /// Resolves a parentCallId to a conversation ID.
  String _resolveConversationId(ChatState chat, String? parentCallId) {
    if (parentCallId == null) {
      return chat.data.primaryConversation.id;
    }
    return _agentIdToConversationId[parentCallId] ??
        chat.data.primaryConversation.id;
  }
}

/// Handles InsightsEvent objects and routes them to the correct conversation.
///
/// Responsibilities:
/// - Processing typed InsightsEvent objects and creating appropriate OutputEntry objects
/// - Tool use → tool result pairing via [_toolCallIndex]
/// - Conversation routing via parentCallId → [_agentIdToConversationId]
///
/// Extracted concerns:
/// - Streaming delta processing → [StreamingProcessor]
/// - Chat title generation → ChatTitleService
/// - Ticket status transitions → [TicketEventBridge]
class EventHandler extends _EventHandlerBase
    with _LifecycleMixin, _SubagentMixin {
  EventHandler({
    super.rateLimitState,
    super.ticketBoard,
  });

  /// Handle an incoming InsightsEvent.
  void handleEvent(ChatState chat, InsightsEvent event) {
    switch (event) {
      case final ToolInvocationEvent e:
        _handleToolInvocation(chat, e);
      case final ToolCompletionEvent e:
        _handleToolCompletion(chat, e);
      case final TextEvent e:
        _handleText(chat, e);
      case final UserInputEvent e:
        _handleUserInput(chat, e);
      case final TurnCompleteEvent e:
        _handleTurnComplete(chat, e);
      case final SessionInitEvent e:
        _handleSessionInit(chat, e);
      case final ConfigOptionsEvent e:
        _handleConfigOptions(chat, e);
      case final AvailableCommandsEvent e:
        _handleAvailableCommands(chat, e);
      case final SessionModeEvent e:
        _handleSessionMode(chat, e);
      case final SessionStatusEvent e:
        _handleSessionStatus(chat, e);
      case final ContextCompactionEvent e:
        _handleCompaction(chat, e);
      case final SubagentSpawnEvent e:
        _handleSubagentSpawn(chat, e);
      case final SubagentCompleteEvent e:
        _handleSubagentComplete(chat, e);
      case final StreamDeltaEvent e:
        _streaming.handleDelta(chat, e);
      case final UsageUpdateEvent e:
        _handleUsageUpdate(chat, e);
      case PermissionRequestEvent e:
        _ticketBridge.onPermissionRequest(chat);
      case final RateLimitUpdateEvent e:
        rateLimitState?.update(e);
    }
  }

  // -- Tool event processing --

  void _handleToolInvocation(ChatState chat, ToolInvocationEvent event) {
    final conversationId = _resolveConversationId(chat, event.parentCallId);

    // Check for streaming entries to finalize
    final streamingEntries = _activeStreamingEntries[conversationId];
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      for (final entry in streamingEntries) {
        if (entry is ToolUseOutputEntry && entry.toolUseId == event.callId) {
          entry.toolInput
            ..clear()
            ..addAll(Map<String, dynamic>.from(event.input));
          entry.isStreaming = false;
          entry.addRawMessage(event.raw ?? {});
          chat.persistStreamingEntry(entry);
          chat.notifyListeners();
          return;
        }
      }
    }

    final entry = ToolUseOutputEntry(
      timestamp: DateTime.now(),
      toolName: event.toolName,
      toolKind: event.kind,
      provider: event.provider,
      toolUseId: event.callId,
      toolInput: Map<String, dynamic>.from(event.input),
      model: event.model,
    );

    entry.addRawMessage(event.raw ?? {});
    _toolCallIndex[event.callId] = entry;
    chat.addOutputEntry(conversationId, entry);
  }

  void _handleToolCompletion(ChatState chat, ToolCompletionEvent event) {
    final entry = _toolCallIndex[event.callId];

    if (entry != null) {
      entry.updateResult(event.output, event.isError);
      entry.addRawMessage(event.raw ?? {});
      chat.persistToolResult(event.callId, event.output, event.isError);
      chat.notifyListeners();
    }

    if (event.callId.isNotEmpty) {
      chat.removePendingPermissionByToolUseId(event.callId);
    }
  }

  // -- Text & message processing --

  void _handleText(ChatState chat, TextEvent event) {
    final chatId = chat.data.id;

    // Check if this is a context summary (after compaction).
    final isSynthetic = event.extensions?['claude.isSynthetic'] == true;
    if ((_expectingContextSummary[chatId] ?? false) && isSynthetic) {
      _expectingContextSummary[chatId] = false;
      if (event.text.isNotEmpty) {
        chat.addEntry(ContextSummaryEntry(
          timestamp: DateTime.now(),
          summary: event.text,
        ));
      }
      return;
    }

    final conversationId = _resolveConversationId(chat, event.parentCallId);

    // Check for streaming entries to finalize
    final streamingEntries = _activeStreamingEntries.remove(conversationId);
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      for (final entry in streamingEntries) {
        if (entry is TextOutputEntry) {
          entry.text = event.text;
          entry.isStreaming = false;
          entry.addRawMessage(event.raw ?? {});
          chat.persistStreamingEntry(entry);
          chat.notifyListeners();
          return;
        }
      }
    }

    final String contentType;
    String? errorType;

    switch (event.kind) {
      case TextKind.thinking:
        contentType = 'thinking';
      case TextKind.error:
        contentType = 'text';
        errorType = 'error';
      case TextKind.text:
      case TextKind.plan:
        contentType = 'text';
    }

    final entry = TextOutputEntry(
      timestamp: DateTime.now(),
      text: event.text,
      contentType: contentType,
      errorType: errorType,
    );

    entry.addRawMessage(event.raw ?? {});
    chat.addOutputEntry(conversationId, entry);

    if (event.parentCallId == null) {
      _hasAssistantOutputThisTurn[chat.data.id] = true;
    }
  }

  void _handleUserInput(ChatState chat, UserInputEvent event) {
    final chatId = chat.data.id;

    if (event.isSynthetic ||
        (_expectingContextSummary[chatId] ?? false)) {
      _expectingContextSummary[chatId] = false;

      if (event.text.isNotEmpty) {
        chat.addEntry(ContextSummaryEntry(
          timestamp: DateTime.now(),
          summary: event.text,
        ));
      }
      return;
    }

    final isReplay = event.extensions?['isReplay'] == true;
    if (isReplay) {
      final localCmdRegex = RegExp(
        r'<local-command-stdout>([\s\S]*?)</local-command-stdout>',
      );
      final match = localCmdRegex.firstMatch(event.text);
      if (match != null) {
        final output = match.group(1)?.trim() ?? '';
        if (output.isNotEmpty) {
          chat.addEntry(SystemNotificationEntry(
            timestamp: DateTime.now(),
            message: output,
          ));
        }
      }
      return;
    }
  }

  // -- Delegation to extracted classes --

  /// Notifies the event handler that a permission response was sent.
  ///
  /// Delegates to [TicketEventBridge] to transition linked tickets back
  /// to active from needsInput.
  void handlePermissionResponse(ChatState chat) {
    _ticketBridge.onPermissionResponse(chat);
  }

  /// Clears in-flight streaming state.
  void clearStreamingState() {
    _streaming.clearStreamingState();
  }

  // -- Cleanup --

  /// Removes tracking state associated with a specific chat.
  void clearChat(
    String chatId, {
    required Set<String> agentIds,
    required Set<String> conversationIds,
  }) {
    // Chat-keyed maps
    _hasAssistantOutputThisTurn.remove(chatId);
    _expectingContextSummary.remove(chatId);

    // Agent-keyed maps
    for (final agentId in agentIds) {
      _agentIdToConversationId.remove(agentId);
    }
    _toolUseIdToAgentId.removeWhere((_, agentId) => agentIds.contains(agentId));

    // Streaming
    _streaming.clearConversations(conversationIds);
  }

  /// Clears all internal state.
  void clear() {
    _toolCallIndex.clear();
    _agentIdToConversationId.clear();
    _toolUseIdToAgentId.clear();
    _hasAssistantOutputThisTurn.clear();
    _expectingContextSummary.clear();
    _activeStreamingEntries.clear();
    _streaming.clear();
  }

  /// Disposes of resources.
  void dispose() {
    clear();
  }
}
