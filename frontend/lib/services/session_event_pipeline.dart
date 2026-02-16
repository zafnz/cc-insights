import '../models/chat.dart';
import '../models/output_entry.dart';
import 'streaming_processor.dart';

/// Per-session event routing and streaming state for a single chat.
class SessionEventPipeline {
  SessionEventPipeline({required this.chatId}) {
    streaming = StreamingProcessor(
      toolCallIndex: toolCallIndex,
      activeStreamingEntries: activeStreamingEntries,
      resolveConversationId: resolveConversationId,
    );
  }

  final String chatId;

  /// Tool pairing: callId -> entry (for updating with result later).
  final Map<String, ToolUseOutputEntry> toolCallIndex = {};

  /// Agent routing: parentCallId (SDK agent ID) -> conversationId.
  final Map<String, String> agentIdToConversationId = {};

  /// Maps new Task callId -> original agent's sdkAgentId (for resumed agents).
  final Map<String, String> toolUseIdToAgentId = {};

  /// Tracks whether assistant output was added during the current turn.
  bool hasAssistantOutputThisTurn = false;

  /// Tracks whether we're expecting a context summary message.
  bool expectingContextSummary = false;

  /// Streaming entries shared between StreamingProcessor and finalization.
  final Map<String, List<OutputEntry>> activeStreamingEntries = {};

  late final StreamingProcessor streaming;

  /// Resolves a parentCallId to a conversation ID for this session.
  String resolveConversationId(Chat chat, String? parentCallId) {
    if (parentCallId == null) {
      return chat.data.primaryConversation.id;
    }
    return agentIdToConversationId[parentCallId] ??
        chat.data.primaryConversation.id;
  }

  void clearStreamingState() {
    streaming.clearStreamingState();
  }

  void dispose() {
    streaming.clear();
    toolCallIndex.clear();
    agentIdToConversationId.clear();
    toolUseIdToAgentId.clear();
    activeStreamingEntries.clear();
    hasAssistantOutputThisTurn = false;
    expectingContextSummary = false;
  }
}
