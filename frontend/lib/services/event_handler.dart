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
import '../state/rate_limit_state.dart';
import '../state/ticket_board_state.dart';
import 'log_service.dart';
import 'session_event_pipeline.dart';
import 'ticket_event_bridge.dart';

part 'event_handler_lifecycle.dart';
part 'event_handler_subagents.dart';

/// Base class with shared state for event handling.
///
/// Contains the event routing switch, conversation resolution, tool/text
/// event processing, and cleanup methods. Session lifecycle and subagent
/// management are in part file mixins.
class _EventHandlerBase {
  /// Rate limit state for displaying rate limit information.
  final RateLimitState? rateLimitState;

  /// Bridge for ticket status transitions based on chat events.
  final TicketEventBridge _ticketBridge;

  /// Active per-session pipelines keyed by chat ID.
  final Map<String, SessionEventPipeline> _pipelines = {};

  _EventHandlerBase({this.rateLimitState, TicketRepository? ticketBoard})
    : _ticketBridge = TicketEventBridge(ticketBoard: ticketBoard);

  /// The current ticket board state, if any.
  TicketRepository? get ticketBoard => _ticketBridge.ticketBoard;

  set ticketBoard(TicketRepository? value) => _ticketBridge.ticketBoard = value;

  /// The ticket event bridge for external callers (e.g. Chat).
  TicketEventBridge get ticketBridge => _ticketBridge;

  SessionEventPipeline _pipelineFor(Chat chat) {
    return _pipelines.putIfAbsent(
      chat.data.id,
      () => SessionEventPipeline(chatId: chat.data.id),
    );
  }

  /// Starts a fresh per-session pipeline for the chat.
  void beginSession(String chatId) {
    _pipelines.remove(chatId)?.dispose();
    _pipelines[chatId] = SessionEventPipeline(chatId: chatId);
  }

  /// Disposes the per-session pipeline for the chat.
  void endSession(String chatId) {
    _pipelines.remove(chatId)?.dispose();
  }
}

/// Handles InsightsEvent objects and routes them to the correct conversation.
///
/// Responsibilities:
/// - Processing typed InsightsEvent objects and creating appropriate OutputEntry objects
/// - Tool use -> tool result pairing via session pipeline
/// - Conversation routing via parentCallId -> session pipeline mapping
///
/// Extracted concerns:
/// - Streaming delta processing -> [StreamingProcessor] via [SessionEventPipeline]
/// - Chat title generation -> ChatTitleService
/// - Ticket status transitions -> [TicketEventBridge]
class EventHandler extends _EventHandlerBase
    with _LifecycleMixin, _SubagentMixin {
  EventHandler({super.rateLimitState, super.ticketBoard});

  /// Handle an incoming InsightsEvent.
  void handleEvent(Chat chat, InsightsEvent event) {
    final pipeline = _pipelineFor(chat);

    switch (event) {
      case final ToolInvocationEvent e:
        _handleToolInvocation(chat, e, pipeline);
      case final ToolCompletionEvent e:
        _handleToolCompletion(chat, e, pipeline);
      case final TextEvent e:
        _handleText(chat, e, pipeline);
      case final UserInputEvent e:
        _handleUserInput(chat, e, pipeline);
      case final TurnCompleteEvent e:
        _handleTurnComplete(chat, e, pipeline);
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
        _handleCompaction(chat, e, pipeline);
      case final SubagentSpawnEvent e:
        _handleSubagentSpawn(chat, e, pipeline);
      case final SubagentCompleteEvent e:
        _handleSubagentComplete(chat, e, pipeline);
      case final StreamDeltaEvent e:
        pipeline.streaming.handleDelta(chat, e);
      case final UsageUpdateEvent e:
        _handleUsageUpdate(chat, e);
      case PermissionRequestEvent e:
        _ticketBridge.onPermissionRequest(chat);
      case final RateLimitUpdateEvent e:
        rateLimitState?.update(e);
    }
  }

  // -- Tool event processing --

  void _handleToolInvocation(
    Chat chat,
    ToolInvocationEvent event,
    SessionEventPipeline pipeline,
  ) {
    final conversationId = pipeline.resolveConversationId(
      chat,
      event.parentCallId,
    );

    // Check for streaming entries to finalize
    final streamingEntries = pipeline.activeStreamingEntries[conversationId];
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      for (final entry in streamingEntries) {
        if (entry is ToolUseOutputEntry && entry.toolUseId == event.callId) {
          entry.toolInput
            ..clear()
            ..addAll(Map<String, dynamic>.from(event.input));
          entry.isStreaming = false;
          entry.addRawMessage(event.raw ?? {});
          chat.persistence.persistStreamingEntry(entry);
          chat.conversations.notifyMutation();
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
    pipeline.toolCallIndex[event.callId] = entry;
    chat.conversations.addOutputEntry(conversationId, entry);
  }

  void _handleToolCompletion(
    Chat chat,
    ToolCompletionEvent event,
    SessionEventPipeline pipeline,
  ) {
    final entry = pipeline.toolCallIndex[event.callId];

    if (entry != null) {
      entry.updateResult(event.output, event.isError);
      entry.addRawMessage(event.raw ?? {});
      chat.persistence.persistToolResult(
        event.callId,
        event.output,
        event.isError,
      );
      chat.conversations.notifyMutation();
    }

    if (event.callId.isNotEmpty) {
      final before = chat.permissions.pendingPermissionCount;
      chat.permissions.removeByToolUseId(event.callId);
      if (chat.permissions.pendingPermissionCount != before) {
        chat.session.notifyPermissionQueueChanged();
      }
    }
  }

  // -- Text & message processing --

  void _handleText(Chat chat, TextEvent event, SessionEventPipeline pipeline) {
    // Check if this is a context summary (after compaction).
    final isSynthetic = event.extensions?['claude.isSynthetic'] == true;
    if (pipeline.expectingContextSummary && isSynthetic) {
      pipeline.expectingContextSummary = false;
      if (event.text.isNotEmpty) {
        chat.conversations.addEntry(
          ContextSummaryEntry(timestamp: DateTime.now(), summary: event.text),
        );
      }
      return;
    }

    final conversationId = pipeline.resolveConversationId(
      chat,
      event.parentCallId,
    );

    // Check for streaming entries to finalize
    final streamingEntries = pipeline.activeStreamingEntries.remove(
      conversationId,
    );
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      for (final entry in streamingEntries) {
        if (entry is TextOutputEntry) {
          entry.text = event.text;
          entry.isStreaming = false;
          entry.addRawMessage(event.raw ?? {});
          chat.persistence.persistStreamingEntry(entry);
          chat.conversations.notifyMutation();
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
    chat.conversations.addOutputEntry(conversationId, entry);

    if (event.parentCallId == null) {
      pipeline.hasAssistantOutputThisTurn = true;
    }
  }

  void _handleUserInput(
    Chat chat,
    UserInputEvent event,
    SessionEventPipeline pipeline,
  ) {
    if (event.isSynthetic || pipeline.expectingContextSummary) {
      pipeline.expectingContextSummary = false;

      if (event.text.isNotEmpty) {
        chat.conversations.addEntry(
          ContextSummaryEntry(timestamp: DateTime.now(), summary: event.text),
        );
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
          chat.conversations.addEntry(
            SystemNotificationEntry(timestamp: DateTime.now(), message: output),
          );
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
  void handlePermissionResponse(Chat chat) {
    _ticketBridge.onPermissionResponse(chat);
  }

  /// Clears in-flight streaming state for all active pipelines.
  void clearStreamingState() {
    for (final pipeline in _pipelines.values) {
      pipeline.clearStreamingState();
    }
  }

  // -- Cleanup --

  /// Removes tracking state associated with a specific chat.
  void clearChat(String chatId) {
    endSession(chatId);
  }

  /// Clears all internal state.
  void clear() {
    final pipelines = _pipelines.values.toList(growable: false);
    _pipelines.clear();
    for (final pipeline in pipelines) {
      pipeline.dispose();
    }
  }

  /// Disposes of resources.
  void dispose() {
    clear();
  }
}
