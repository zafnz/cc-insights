import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendProvider, StreamDeltaEvent, StreamDeltaKind, ToolKind;

import '../models/chat.dart';
import '../models/output_entry.dart';

/// Processes streaming delta events into live-updating output entries.
///
/// Manages the streaming state machine (message_start → block_start →
/// deltas → block_stop → message_stop) and throttles UI notifications
/// to avoid excessive rebuilds during rapid delta delivery.
///
/// Extracted from [EventHandler] — this is a self-contained subsystem with
/// its own state machine and throttling logic.
class StreamingProcessor {
  /// Shared with EventHandler for tool result pairing.
  final Map<String, ToolUseOutputEntry> _toolCallIndex;

  /// Shared with EventHandler for streaming → finalized entry handoff.
  final Map<String, List<OutputEntry>> activeStreamingEntries;

  /// Resolves a parentCallId to a conversation ID.
  final String Function(Chat, String?) _resolveConversationId;

  /// Tracks streaming entries by (conversationId, contentBlockIndex).
  final Map<(String, int), OutputEntry> _streamingBlocks = {};

  /// The conversation ID for the currently streaming message.
  String? _streamingConversationId;

  /// Chat reference for the current streaming session.
  Chat? _streamingChat;

  /// Throttle timer for batching UI updates during streaming.
  Timer? _notifyTimer;

  /// Whether any deltas arrived since the last timer tick.
  bool _hasPendingNotify = false;

  StreamingProcessor({
    required Map<String, ToolUseOutputEntry> toolCallIndex,
    required this.activeStreamingEntries,
    required String Function(Chat, String?) resolveConversationId,
  }) : _toolCallIndex = toolCallIndex,
       _resolveConversationId = resolveConversationId;

  /// Handle a streaming delta event.
  void handleDelta(Chat chat, StreamDeltaEvent event) {
    switch (event.kind) {
      case StreamDeltaKind.messageStart:
        _onMessageStart(chat, event.parentCallId);
      case StreamDeltaKind.blockStart:
        _onContentBlockStart(chat, event.blockIndex ?? 0, event);
      case StreamDeltaKind.text:
        _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
      case StreamDeltaKind.thinking:
        _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
      case StreamDeltaKind.toolInput:
        _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
      case StreamDeltaKind.blockStop:
        _onContentBlockStop(event.blockIndex ?? 0);
      case StreamDeltaKind.messageStop:
        _onMessageStop(chat);
    }
  }

  void _onMessageStart(Chat chat, String? parentCallId) {
    _streamingConversationId = _resolveConversationId(chat, parentCallId);
    _streamingChat = chat;
    _streamingBlocks.clear();
  }

  void _onContentBlockStart(Chat chat, int index, StreamDeltaEvent event) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    OutputEntry? entry;

    if (event.callId != null) {
      // tool_use block
      final toolName = event.extensions?['tool_name'] as String? ?? '';
      entry = ToolUseOutputEntry(
        timestamp: DateTime.now(),
        toolName: toolName,
        toolKind: ToolKind.fromToolName(toolName),
        provider: event.provider,
        toolUseId: event.callId!,
        toolInput: <String, dynamic>{},
        isStreaming: true,
      );
      // Register for tool result pairing
      _toolCallIndex[event.callId!] = entry as ToolUseOutputEntry;
    } else if (event.extensions?['block_type'] == 'thinking') {
      // thinking block
      entry = TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'thinking',
        isStreaming: true,
      );
    } else {
      // text block (default)
      entry = TextOutputEntry(
        timestamp: DateTime.now(),
        text: '',
        contentType: 'text',
        isStreaming: true,
      );
    }

    _streamingBlocks[(convId, index)] = entry;
    chat.conversations.addOutputEntry(convId, entry);
    activeStreamingEntries.putIfAbsent(convId, () => []).add(entry);
  }

  void _onContentBlockDelta(Chat chat, int index, StreamDeltaEvent event) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    final entry = _streamingBlocks[(convId, index)];
    if (entry == null) return;

    switch (event.kind) {
      case StreamDeltaKind.text:
      case StreamDeltaKind.thinking:
        if (entry is TextOutputEntry) {
          entry.appendDelta(event.textDelta ?? '');
        }
      case StreamDeltaKind.toolInput:
        if (entry is ToolUseOutputEntry) {
          entry.appendInputDelta(event.jsonDelta ?? '');
        }
      default:
        break;
    }

    _scheduleNotify();
  }

  void _onContentBlockStop(int index) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    final entry = _streamingBlocks[(convId, index)];
    if (entry is TextOutputEntry) {
      entry.isStreaming = false;
    } else if (entry is ToolUseOutputEntry) {
      entry.isStreaming = false;
    }
  }

  void _onMessageStop(Chat chat) {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (_hasPendingNotify) {
      _hasPendingNotify = false;
      chat.conversations.notifyMutation();
    }

    _streamingBlocks.clear();
    _streamingConversationId = null;
    _streamingChat = null;
  }

  void _scheduleNotify() {
    _hasPendingNotify = true;
    _notifyTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_hasPendingNotify && _streamingChat != null) {
        _hasPendingNotify = false;
        _streamingChat!.conversations.notifyMutation();
      }
    });
  }

  /// Clears in-flight streaming state.
  ///
  /// Marks any streaming entries as finalized and flushes pending
  /// notifications. Call this when a session is interrupted.
  void clearStreamingState() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _hasPendingNotify = false;

    for (final entry in _streamingBlocks.values) {
      if (entry is TextOutputEntry) {
        entry.isStreaming = false;
      } else if (entry is ToolUseOutputEntry) {
        entry.isStreaming = false;
      }
    }

    if (_streamingChat != null) {
      _streamingChat!.conversations.notifyMutation();
    }

    _streamingBlocks.clear();
    activeStreamingEntries.clear();
    _streamingConversationId = null;
    _streamingChat = null;
  }

  /// Removes streaming state for specific conversations.
  void clearConversations(Set<String> conversationIds) {
    _streamingBlocks.removeWhere((key, _) => conversationIds.contains(key.$1));
    activeStreamingEntries.removeWhere(
      (convId, _) => conversationIds.contains(convId),
    );

    if (conversationIds.contains(_streamingConversationId)) {
      _streamingConversationId = null;
      _streamingChat = null;
    }
  }

  /// Clears all internal state.
  void clear() {
    _streamingBlocks.clear();
    activeStreamingEntries.clear();
    _streamingConversationId = null;
    _streamingChat = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _hasPendingNotify = false;
  }
}
