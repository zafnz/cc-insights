import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

/// Handles ACP session updates and converts them to chat-friendly format.
///
/// This class processes incoming [SessionUpdate] messages from the ACP agent
/// and provides callbacks for different update types. It acts as a bridge
/// between the raw ACP protocol updates and the UI layer, routing updates
/// to appropriate conversations and handling special cases like subagent
/// spawning.
///
/// The handler uses callbacks rather than streams to allow synchronous
/// processing of updates. This enables the caller (typically ChatState)
/// to update its internal state immediately as updates arrive.
///
/// Key features:
/// - **Update routing**: Routes tool calls to the correct conversation
/// - **Subagent detection**: Identifies Task tool calls that spawn subagents
/// - **Tool call tracking**: Maps tool call IDs to conversations for routing
///
/// Example usage:
/// ```dart
/// final handler = SessionUpdateHandler(
///   onAgentMessage: (text) => conversation.addText(text),
///   onToolCall: (info) => conversation.addToolCall(info),
///   onToolCallUpdate: (info) => conversation.updateToolCall(info),
/// );
///
/// // Subscribe to session updates
/// session.updates.listen((update) => handler.handleUpdate(update));
/// ```
class SessionUpdateHandler {
  /// Creates a new session update handler.
  ///
  /// All callbacks are optional. If a callback is not provided, the
  /// corresponding update type will be ignored.
  SessionUpdateHandler({
    this.onAgentMessage,
    this.onThinkingMessage,
    this.onToolCall,
    this.onToolCallUpdate,
    this.onPlan,
    this.onModeChange,
    this.onUserMessage,
    this.onCommands,
  });

  /// Called when the agent sends a text message.
  ///
  /// The [text] parameter contains the text content. Note that messages
  /// may arrive in chunks, so the same logical message may trigger
  /// multiple callbacks.
  final void Function(String text)? onAgentMessage;

  /// Called when the agent sends thinking/reasoning content.
  ///
  /// Thinking content represents the agent's internal reasoning process.
  /// Like regular messages, this may arrive in chunks.
  final void Function(String text)? onThinkingMessage;

  /// Called when a new tool call starts.
  ///
  /// The [info] parameter contains details about the tool call, including
  /// its ID, title, status, raw input, and whether it's a Task tool that
  /// spawns a subagent.
  final void Function(ToolCallInfo info)? onToolCall;

  /// Called when a tool call status updates.
  ///
  /// The [info] parameter contains the updated status and any content
  /// produced by the tool call.
  final void Function(ToolCallUpdateInfo info)? onToolCallUpdate;

  /// Called when the agent updates its task plan.
  ///
  /// The [entries] parameter contains the current plan entries with their
  /// status and priority information.
  final void Function(List<PlanEntry> entries)? onPlan;

  /// Called when the session mode changes.
  ///
  /// The [modeId] parameter contains the ID of the new mode (e.g., 'code',
  /// 'architect', 'ask').
  final void Function(String modeId)? onModeChange;

  /// Called when a user message is replayed.
  ///
  /// This typically happens during session resume, when the agent replays
  /// the conversation history.
  final void Function(String text)? onUserMessage;

  /// Called when the available slash commands update.
  ///
  /// The [commands] parameter contains the list of available commands
  /// that can be invoked by the user.
  final void Function(List<AvailableCommand> commands)? onCommands;

  /// Maps tool call IDs to conversation IDs for subagent routing.
  ///
  /// When a Task tool spawns a subagent, the tool call ID is mapped to
  /// a new conversation. Subsequent updates for that subagent's tool calls
  /// can be routed to the correct conversation.
  final Map<String, String> _toolCallToConversation = {};

  /// Handles an incoming session update.
  ///
  /// This method dispatches the update to the appropriate handler based
  /// on its type. Unknown update types are logged but otherwise ignored.
  void handleUpdate(SessionUpdate update) {
    switch (update) {
      case AgentMessageChunkSessionUpdate(:final content):
        _handleAgentMessage(content);
      case AgentThoughtChunkSessionUpdate(:final content):
        _handleThinking(content);
      case ToolCallSessionUpdate():
        _handleToolCall(update);
      case ToolCallUpdateSessionUpdate():
        _handleToolCallUpdate(update);
      case PlanSessionUpdate(:final entries):
        _handlePlan(entries);
      case CurrentModeUpdateSessionUpdate(:final currentModeId):
        _handleModeChange(currentModeId);
      case UserMessageChunkSessionUpdate(:final content):
        _handleUserMessage(content);
      case AvailableCommandsUpdateSessionUpdate(:final availableCommands):
        _handleCommands(availableCommands);
      case UnknownSessionUpdate(:final rawJson):
        debugPrint('Unknown session update: $rawJson');
    }
  }

  /// Handles an agent message update.
  ///
  /// Extracts text from the content block and forwards it to the callback.
  void _handleAgentMessage(ContentBlock content) {
    if (content is TextContentBlock) {
      onAgentMessage?.call(content.text);
    }
  }

  /// Handles a thinking/reasoning update.
  ///
  /// Extracts text from the content block and forwards it to the callback.
  void _handleThinking(ContentBlock content) {
    if (content is TextContentBlock) {
      onThinkingMessage?.call(content.text);
    }
  }

  /// Handles a new tool call.
  ///
  /// Creates a [ToolCallInfo] from the update and forwards it to the callback.
  void _handleToolCall(ToolCallSessionUpdate update) {
    final info = ToolCallInfo(
      toolCallId: update.toolCallId,
      title: update.title,
      status: update.status ?? ToolCallStatus.pending,
      kind: update.kind,
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
      content: update.content,
      locations: update.locations,
      isTaskTool: _isTaskTool(update),
    );
    onToolCall?.call(info);
  }

  /// Handles a tool call status update.
  ///
  /// Creates a [ToolCallUpdateInfo] from the update and forwards it.
  void _handleToolCallUpdate(ToolCallUpdateSessionUpdate update) {
    final info = ToolCallUpdateInfo(
      toolCallId: update.toolCallId,
      status: update.status,
      title: update.title,
      kind: update.kind,
      rawInput: update.rawInput,
      rawOutput: update.rawOutput,
      content: update.content,
      locations: update.locations,
    );
    onToolCallUpdate?.call(info);
  }

  /// Handles a plan update.
  void _handlePlan(List<PlanEntry> entries) {
    onPlan?.call(entries);
  }

  /// Handles a mode change update.
  void _handleModeChange(String currentModeId) {
    onModeChange?.call(currentModeId);
  }

  /// Handles a user message update.
  ///
  /// Extracts text from the content block and forwards it to the callback.
  void _handleUserMessage(ContentBlock content) {
    if (content is TextContentBlock) {
      onUserMessage?.call(content.text);
    }
  }

  /// Handles an available commands update.
  void _handleCommands(List<AvailableCommand> availableCommands) {
    onCommands?.call(availableCommands);
  }

  /// Determines if a tool call is a Task tool (subagent spawn).
  ///
  /// Task tools are special tools that spawn subagents to handle
  /// subtasks. They're identified by:
  /// - Tool title containing 'task' or 'agent'
  /// - Raw input containing a 'subagent_type' field
  bool _isTaskTool(ToolCallSessionUpdate update) {
    final title = update.title.toLowerCase();
    return title.contains('task') ||
        title.contains('agent') ||
        (update.rawInput?['subagent_type'] != null);
  }

  /// Registers a mapping from a tool call ID to a conversation ID.
  ///
  /// This is used to track which conversation a subagent's output should
  /// be routed to. Call this when spawning a subagent conversation.
  void registerToolCallConversation(String toolCallId, String conversationId) {
    _toolCallToConversation[toolCallId] = conversationId;
  }

  /// Gets the conversation ID for a tool call, if one has been registered.
  ///
  /// Returns `null` if the tool call hasn't been mapped to a conversation.
  String? getConversationForToolCall(String toolCallId) {
    return _toolCallToConversation[toolCallId];
  }

  /// Removes the conversation mapping for a tool call.
  ///
  /// Call this when a subagent completes and its conversation is no longer
  /// needed for routing.
  void unregisterToolCallConversation(String toolCallId) {
    _toolCallToConversation.remove(toolCallId);
  }

  /// Clears all tool call to conversation mappings.
  ///
  /// Useful when resetting state or disposing of the handler.
  void clearConversationMappings() {
    _toolCallToConversation.clear();
  }
}

/// Information about a new tool call.
///
/// This class wraps the relevant fields from [ToolCallSessionUpdate]
/// in a more convenient format for the UI layer.
class ToolCallInfo {
  /// Creates a tool call info object.
  const ToolCallInfo({
    required this.toolCallId,
    required this.title,
    required this.status,
    this.kind,
    this.rawInput,
    this.rawOutput,
    this.content,
    this.locations,
    this.isTaskTool = false,
  });

  /// The unique identifier for this tool call.
  final String toolCallId;

  /// The human-readable title/name of the tool.
  final String title;

  /// The current execution status of the tool call.
  final ToolCallStatus status;

  /// The category of tool (read, edit, execute, etc.).
  final ToolKind? kind;

  /// The raw input parameters passed to the tool.
  final Map<String, dynamic>? rawInput;

  /// The raw output from the tool execution.
  final Map<String, dynamic>? rawOutput;

  /// Structured content produced by the tool call.
  ///
  /// May include text content, diffs, terminal output references, etc.
  final List<ToolCallContent>? content;

  /// File locations being accessed or modified by the tool.
  final List<ToolCallLocation>? locations;

  /// Whether this tool call is a Task tool that spawns a subagent.
  final bool isTaskTool;

  @override
  String toString() => 'ToolCallInfo(id: $toolCallId, title: $title, '
      'status: $status, isTaskTool: $isTaskTool)';
}

/// Information about a tool call status update.
///
/// This class wraps the relevant fields from [ToolCallUpdateSessionUpdate].
/// Unlike [ToolCallInfo], all fields except [toolCallId] are optional since
/// updates only include changed fields.
class ToolCallUpdateInfo {
  /// Creates a tool call update info object.
  const ToolCallUpdateInfo({
    required this.toolCallId,
    this.status,
    this.title,
    this.kind,
    this.rawInput,
    this.rawOutput,
    this.content,
    this.locations,
  });

  /// The unique identifier for the tool call being updated.
  final String toolCallId;

  /// The updated execution status, if changed.
  final ToolCallStatus? status;

  /// The updated title, if changed.
  final String? title;

  /// The updated tool kind, if changed.
  final ToolKind? kind;

  /// The updated raw input, if changed.
  final Map<String, dynamic>? rawInput;

  /// The updated raw output, if changed.
  final Map<String, dynamic>? rawOutput;

  /// Updated structured content from the tool call.
  final List<ToolCallContent>? content;

  /// Updated file locations being accessed or modified.
  final List<ToolCallLocation>? locations;

  @override
  String toString() => 'ToolCallUpdateInfo(id: $toolCallId, '
      'status: $status, hasContent: ${content != null})';
}
