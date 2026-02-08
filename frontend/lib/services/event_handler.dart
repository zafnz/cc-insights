import 'dart:async';
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
        SessionInitEvent,
        SessionStatusEvent,
        ContextCompactionEvent,
        SubagentSpawnEvent,
        SubagentCompleteEvent,
        StreamDeltaEvent,
        PermissionRequestEvent,
        ToolKind,
        TextKind,
        ToolCallStatus,
        SessionStatus,
        CompactionTrigger,
        StreamDeltaKind,
        TokenUsage,
        ModelTokenUsage;
import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/output_entry.dart';
import 'ask_ai_service.dart';
import 'log_service.dart';
import 'runtime_config.dart';

/// Handles InsightsEvent objects and routes them to the correct conversation.
///
/// This class is responsible for:
/// - Processing typed InsightsEvent objects and creating appropriate OutputEntry objects
/// - Tool use → tool result pairing via [_toolCallIndex]
/// - Conversation routing via parentCallId → [_agentIdToConversationId]
/// - Agent lifecycle management (subagent spawning)
/// - Streaming: processing StreamDeltaEvent objects into live-updating entries
///   with throttled UI notifications
///
/// The handler is stateless with respect to [ChatState] - the chat is passed
/// to [handleEvent] rather than stored. Internal tracking maps are keyed
/// by callId/agentId which are unique across sessions.
class EventHandler {
  /// Tool pairing: callId → entry (for updating with result later).
  final Map<String, ToolUseOutputEntry> _toolCallIndex = {};

  /// Agent routing: parentCallId (SDK agent ID) → conversationId.
  final Map<String, String> _agentIdToConversationId = {};

  /// Maps new Task callId → original agent's sdkAgentId (for resumed agents).
  ///
  /// When an agent is resumed with a new Task tool call, the new callId
  /// needs to map back to the original agent's sdkAgentId so that results
  /// update the correct agent.
  final Map<String, String> _toolUseIdToAgentId = {};

  /// Tracks whether assistant output was added during the current turn,
  /// per chat.
  ///
  /// Used to determine whether to display result messages - if no assistant
  /// output was added (e.g., for an unrecognized slash command), the result
  /// message should be shown to the user.
  final Map<String, bool> _hasAssistantOutputThisTurn = {};

  /// Tracks whether we're expecting a context summary message, per chat.
  ///
  /// Set to true after receiving a ContextCompactionEvent without a summary.
  /// The next user message will be treated as the context summary and displayed
  /// as a [ContextSummaryEntry].
  final Map<String, bool> _expectingContextSummary = {};

  /// AskAiService for generating chat titles.
  final AskAiService? _askAiService;

  /// Set of chat IDs that are currently having their title generated.
  ///
  /// Used to prevent duplicate concurrent title generation requests.
  final Set<String> _pendingTitleGenerations = {};

  /// Set of chat IDs that have already had title generation attempted.
  ///
  /// Once a chat ID is in this set, we won't attempt title generation again.
  /// This persists for the lifetime of the EventHandler instance.
  final Set<String> _titlesGenerated = {};

  // Streaming state

  /// Tracks streaming entries by (conversationId, contentBlockIndex).
  /// Reset on each new message_start.
  final Map<(String, int), OutputEntry> _streamingBlocks = {};

  /// The conversation ID for the currently streaming message.
  String? _streamingConversationId;

  /// Chat reference for the current streaming session.
  ChatState? _streamingChat;

  /// Entries created during streaming for each conversation.
  /// Used by [_handleText] and [_handleToolInvocation] to finalize instead of duplicate.
  final Map<String, List<OutputEntry>> _activeStreamingEntries = {};

  /// Throttle timer for batching UI updates during streaming.
  Timer? _notifyTimer;

  /// Whether any deltas arrived since the last timer tick.
  bool _hasPendingNotify = false;

  /// Creates an [EventHandler].
  ///
  /// If [askAiService] is provided, it will be used to auto-generate chat
  /// titles after the first assistant response.
  EventHandler({AskAiService? askAiService}) : _askAiService = askAiService;

  /// Handle an incoming InsightsEvent.
  ///
  /// The [chat] is the ChatState to route events to.
  /// The [event] is the typed event object from the protocol.
  void handleEvent(ChatState chat, InsightsEvent event) {
    switch (event) {
      case ToolInvocationEvent e:
        _handleToolInvocation(chat, e);
      case ToolCompletionEvent e:
        _handleToolCompletion(chat, e);
      case TextEvent e:
        _handleText(chat, e);
      case UserInputEvent e:
        _handleUserInput(chat, e);
      case TurnCompleteEvent e:
        _handleTurnComplete(chat, e);
      case SessionInitEvent e:
        _handleSessionInit(chat, e);
      case SessionStatusEvent e:
        _handleSessionStatus(chat, e);
      case ContextCompactionEvent e:
        _handleCompaction(chat, e);
      case SubagentSpawnEvent e:
        _handleSubagentSpawn(chat, e);
      case SubagentCompleteEvent e:
        _handleSubagentComplete(chat, e);
      case StreamDeltaEvent e:
        _handleStreamDelta(chat, e);
      case PermissionRequestEvent _:
        break; // Handled via permission stream
    }
  }

  /// Resolves a parentCallId to a conversation ID.
  ///
  /// Returns the primary conversation ID if [parentCallId] is null,
  /// otherwise looks up the conversation for that agent.
  String _resolveConversationId(ChatState chat, String? parentCallId) {
    if (parentCallId == null) {
      return chat.data.primaryConversation.id;
    }
    return _agentIdToConversationId[parentCallId] ??
        chat.data.primaryConversation.id;
  }

  void _handleToolInvocation(ChatState chat, ToolInvocationEvent event) {
    final conversationId = _resolveConversationId(chat, event.parentCallId);

    // Check for streaming entries to finalize
    final streamingEntries = _activeStreamingEntries[conversationId];
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      // Find the first matching tool entry
      for (final entry in streamingEntries) {
        if (entry is ToolUseOutputEntry && entry.toolUseId == event.callId) {
          // Finalize the streaming entry
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

    // Non-streaming path: create entry
    final entry = ToolUseOutputEntry(
      timestamp: DateTime.now(),
      toolName: event.toolName,
      toolKind: event.kind,
      provider: event.provider,
      toolUseId: event.callId,
      toolInput: Map<String, dynamic>.from(event.input),
      model: event.model,
    );

    // Add raw message for debugging
    entry.addRawMessage(event.raw ?? {});

    // Track for pairing with tool_result
    _toolCallIndex[event.callId] = entry;
    chat.addOutputEntry(conversationId, entry);
  }

  void _handleToolCompletion(ChatState chat, ToolCompletionEvent event) {
    final entry = _toolCallIndex[event.callId];

    if (entry != null) {
      // Update the entry in place
      entry.updateResult(event.output, event.isError);

      // Add the result message to raw messages for debugging
      entry.addRawMessage(event.raw ?? {});

      // Persist the tool result to the JSONL file
      chat.persistToolResult(event.callId, event.output, event.isError);

      // Entry already in the list - just notify listeners
      chat.notifyListeners();
    }

    // Clear any pending permission request for this specific tool.
    // This handles the timeout case: when the SDK times out waiting for
    // permission, it sends a tool result (denied), and we should dismiss
    // the stale permission widget.
    if (event.callId.isNotEmpty) {
      chat.removePendingPermissionByToolUseId(event.callId);
    }
  }

  /// Formats token count with K suffix for readability.
  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  // Stub methods for 4c
  void _handleText(ChatState chat, TextEvent event) {
    // TODO: Implement in Task 4c
  }

  void _handleUserInput(ChatState chat, UserInputEvent event) {
    // TODO: Implement in Task 4c
  }

  void _handleSessionInit(ChatState chat, SessionInitEvent event) {
    // TODO: Implement in Task 4c
  }

  void _handleSessionStatus(ChatState chat, SessionStatusEvent event) {
    // TODO: Implement in Task 4c
  }

  void _handleCompaction(ChatState chat, ContextCompactionEvent event) {
    // TODO: Implement in Task 4c
  }

  void _handleTurnComplete(ChatState chat, TurnCompleteEvent event) {
    // TODO: Implement in Task 4c
  }

  // Stub methods for 4d
  void _handleStreamDelta(ChatState chat, StreamDeltaEvent event) {
    // TODO: Implement in Task 4d
  }

  // Stub methods for 4e
  void _handleSubagentSpawn(ChatState chat, SubagentSpawnEvent event) {
    // TODO: Implement in Task 4e
  }

  void _handleSubagentComplete(ChatState chat, SubagentCompleteEvent event) {
    // TODO: Implement in Task 4e
  }

  /// Clears all internal state.
  ///
  /// Call this when the session ends or is cleared.
  void clear() {
    _toolCallIndex.clear();
    _agentIdToConversationId.clear();
    _toolUseIdToAgentId.clear();
    _hasAssistantOutputThisTurn.clear();
    _expectingContextSummary.clear();
    _pendingTitleGenerations.clear();
    _titlesGenerated.clear();
    _streamingBlocks.clear();
    _activeStreamingEntries.clear();
    _streamingConversationId = null;
    _streamingChat = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _hasPendingNotify = false;
  }

  /// Disposes of resources.
  void dispose() {
    clear();
  }
}
