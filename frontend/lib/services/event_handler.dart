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
        UsageUpdateEvent,
        SessionInitEvent,
        SessionStatusEvent,
        ContextCompactionEvent,
        SubagentSpawnEvent,
        SubagentCompleteEvent,
        StreamDeltaEvent,
        PermissionRequestEvent,
        ToolKind,
        TextKind,
        SessionStatus,
        CompactionTrigger,
        StreamDeltaKind;

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/codex_pricing.dart';
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
      case UsageUpdateEvent e:
        _handleUsageUpdate(chat, e);
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

  // Task 4c methods
  void _handleText(ChatState chat, TextEvent event) {
    final conversationId = _resolveConversationId(chat, event.parentCallId);

    // Check for streaming entries to finalize: when a non-streaming event arrives
    // and there are active streaming entries for that conversation, finalize the
    // first matching text entry.
    final streamingEntries = _activeStreamingEntries.remove(conversationId);
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      // Find the first TextOutputEntry to finalize
      for (final entry in streamingEntries) {
        if (entry is TextOutputEntry) {
          // Finalize with authoritative text
          entry.text = event.text;
          entry.isStreaming = false;
          entry.addRawMessage(event.raw ?? {});
          chat.persistStreamingEntry(entry);
          chat.notifyListeners();
          return;
        }
      }
    }

    // Non-streaming path: create entry
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

    // Mark that we have assistant output for this turn (main agent only)
    if (event.parentCallId == null) {
      _hasAssistantOutputThisTurn[chat.data.id] = true;
    }
  }

  void _handleUserInput(ChatState chat, UserInputEvent event) {
    final chatId = chat.data.id;

    // Check if this is a context summary message (after compaction)
    // The SDK may send this with isSynthetic=true, or we track it via
    // _expectingContextSummary flag after receiving compact_boundary
    if (event.isSynthetic ||
        (_expectingContextSummary[chatId] ?? false)) {
      // Reset the flag
      _expectingContextSummary[chatId] = false;

      // Extract the text content and display as a context summary entry
      if (event.text.isNotEmpty) {
        chat.addEntry(ContextSummaryEntry(
          timestamp: DateTime.now(),
          summary: event.text,
        ));
      }
      return;
    }

    // Handle local command output (e.g., /cost, /compact).
    // These arrive as user messages with isReplay: true and text content
    // wrapped in <local-command-stdout> tags.
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

    // Normal user input - no-op (user input entries are added by ChatState.sendMessage)
  }

  void _handleSessionInit(ChatState chat, SessionInitEvent event) {
    // No-op - system initialization is handled elsewhere
  }

  void _handleSessionStatus(ChatState chat, SessionStatusEvent event) {
    // Update compacting state
    if (event.status == SessionStatus.compacting) {
      chat.setCompacting(true);
    } else {
      chat.setCompacting(false);
    }

    // Sync permission mode when the CLI reports it (e.g., entering plan mode)
    final permMode = event.extensions?['permissionMode'] as String?;
    if (permMode != null) {
      chat.setPermissionMode(PermissionMode.fromApiName(permMode));
    }
  }

  void _handleCompaction(ChatState chat, ContextCompactionEvent event) {
    // Check for context_cleared trigger
    if (event.trigger == CompactionTrigger.cleared) {
      chat.addEntry(ContextClearedEntry(timestamp: DateTime.now()));
      chat.resetContext();
      return;
    }

    // Create AutoCompactionEntry
    final message = event.preTokens != null
        ? 'Was ${_formatTokens(event.preTokens!)} tokens'
        : null;
    final isManual = event.trigger == CompactionTrigger.manual;

    chat.addEntry(AutoCompactionEntry(
      timestamp: DateTime.now(),
      message: message,
      isManual: isManual,
    ));

    // Handle summary
    if (event.summary != null) {
      // Summary provided immediately - create entry
      chat.addEntry(ContextSummaryEntry(
        timestamp: DateTime.now(),
        summary: event.summary!,
      ));
    } else {
      // Summary will arrive in the next user message
      _expectingContextSummary[chat.data.id] = true;
    }
  }

  void _handleTurnComplete(ChatState chat, TurnCompleteEvent event) {
    // Determine if main agent or subagent
    final parentCallId = event.extensions?['parent_tool_use_id'] as String?;

    // Extract usage
    UsageInfo? usageInfo;
    if (event.usage != null) {
      final u = event.usage!;
      usageInfo = UsageInfo(
        inputTokens: u.inputTokens,
        outputTokens: u.outputTokens,
        cacheReadTokens: u.cacheReadTokens ?? 0,
        cacheCreationTokens: u.cacheCreationTokens ?? 0,
        costUsd: event.costUsd ?? 0.0,
      );
    }

    // Extract per-model usage breakdown
    List<ModelUsageInfo>? modelUsageList;
    int? contextWindow;
    if (event.modelUsage != null && event.modelUsage!.isNotEmpty) {
      modelUsageList = event.modelUsage!.entries.map((entry) {
        final data = entry.value;
        return ModelUsageInfo(
          modelName: entry.key,
          inputTokens: data.inputTokens,
          outputTokens: data.outputTokens,
          cacheReadTokens: data.cacheReadTokens ?? 0,
          cacheCreationTokens: data.cacheCreationTokens ?? 0,
          costUsd: data.costUsd ?? 0.0,
          contextWindow: data.contextWindow ?? 200000,
        );
      }).toList();

      // Get context window from first model (they should all be the same)
      if (modelUsageList.isNotEmpty) {
        contextWindow = modelUsageList.first.contextWindow;
      }
    }

    // Calculate cost from pricing table for Codex (which doesn't report cost)
    double totalCostUsd = event.costUsd ?? 0.0;
    if (totalCostUsd == 0.0 &&
        event.provider == BackendProvider.codex &&
        modelUsageList != null) {
      modelUsageList = modelUsageList.map((m) {
        final pricing = lookupCodexPricing(m.modelName);
        if (pricing == null) return m;
        final cost = pricing.calculateCost(
          inputTokens: m.inputTokens,
          cachedInputTokens: m.cacheReadTokens,
          outputTokens: m.outputTokens,
        );
        return ModelUsageInfo(
          modelName: m.modelName,
          inputTokens: m.inputTokens,
          outputTokens: m.outputTokens,
          cacheReadTokens: m.cacheReadTokens,
          cacheCreationTokens: m.cacheCreationTokens,
          costUsd: cost,
          contextWindow: m.contextWindow,
        );
      }).toList();
      totalCostUsd = modelUsageList.fold(0.0, (sum, m) => sum + m.costUsd);
      if (usageInfo != null && totalCostUsd > 0.0) {
        usageInfo = usageInfo.copyWith(costUsd: totalCostUsd);
      }
    }

    if (parentCallId == null) {
      // Main agent result
      if (usageInfo != null) {
        chat.updateCumulativeUsage(
          usage: usageInfo,
          totalCostUsd: totalCostUsd,
          modelUsage: modelUsageList,
          contextWindow: contextWindow,
        );
      }

      // Update context tracker with the last step's per-API-call usage.
      // The result message's `usage` is cumulative across all steps in a turn,
      // which inflates the context count. Instead, we use `lastStepUsage`
      // from extensions — the usage from the final assistant message, which
      // reflects the actual context window size.
      final lastStepUsage =
          event.extensions?['lastStepUsage'] as Map<String, dynamic>?;
      if (lastStepUsage != null) {
        chat.updateContextFromUsage(lastStepUsage);
      }

      chat.setWorking(false);

      // Handle no-output result: if no assistant output was added during this
      // turn and there's a result message, display it as a system notification
      // (e.g., "Unknown skill: clear")
      final chatId = chat.data.id;
      final result = event.result;
      if (!(_hasAssistantOutputThisTurn[chatId] ?? false) &&
          result != null &&
          result.isNotEmpty) {
        chat.addEntry(SystemNotificationEntry(
          timestamp: DateTime.now(),
          message: result,
        ));
      }

      // Reset the flag for the next turn
      _hasAssistantOutputThisTurn[chatId] = false;
    } else {
      // Subagent result - determine agent status from subtype
      final AgentStatus status;
      final subtype = event.subtype;

      if (subtype == 'success') {
        status = AgentStatus.completed;
      } else if (subtype == 'error_max_turns' ||
          subtype == 'error_tool' ||
          subtype == 'error_api' ||
          subtype == 'error_budget') {
        status = AgentStatus.error;
      } else {
        status = AgentStatus.completed;
      }

      chat.updateAgent(status, parentCallId);
    }
  }

  // Intermediate usage update — fires after each API call (step) during a turn.
  void _handleUsageUpdate(ChatState chat, UsageUpdateEvent event) {
    // Accumulate output tokens from ALL events (main + subagent) so the
    // token counter reflects total work done during the turn.
    final outputTokens =
        (event.stepUsage['output_tokens'] as num?)?.toInt() ?? 0;
    chat.addInTurnOutputTokens(outputTokens);

    // Only update context tracker for main agent events — subagents have
    // independent context windows that don't reflect the main agent's state.
    final parentCallId = event.extensions?['parent_tool_use_id'] as String?;
    if (parentCallId != null) return;

    // Update context tracker with per-step usage (reflects actual context size).
    chat.updateContextFromUsage(event.stepUsage);
  }

  // Task 4d: Streaming delta handling
  void _handleStreamDelta(ChatState chat, StreamDeltaEvent event) {
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

  void _onMessageStart(ChatState chat, String? parentCallId) {
    _streamingConversationId = _resolveConversationId(chat, parentCallId);
    _streamingChat = chat;
    _streamingBlocks.clear();
  }

  void _onContentBlockStart(
    ChatState chat,
    int index,
    StreamDeltaEvent event,
  ) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    OutputEntry? entry;

    // Determine block type from event fields
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
    chat.addOutputEntry(convId, entry);
    _activeStreamingEntries.putIfAbsent(convId, () => []).add(entry);
  }

  void _onContentBlockDelta(
    ChatState chat,
    int index,
    StreamDeltaEvent event,
  ) {
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

  void _onMessageStop(ChatState chat) {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (_hasPendingNotify) {
      _hasPendingNotify = false;
      chat.notifyListeners();
    }

    _streamingBlocks.clear();
    _streamingConversationId = null;
    _streamingChat = null;
  }

  void _scheduleNotify() {
    _hasPendingNotify = true;
    _notifyTimer ??= Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        if (_hasPendingNotify && _streamingChat != null) {
          _hasPendingNotify = false;
          _streamingChat!.notifyListeners();
        }
      },
    );
  }

  /// Clears in-flight streaming state.
  ///
  /// Marks any streaming entries as finalized and flushes pending
  /// notifications. Call this when a session is interrupted.
  void clearStreamingState() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _hasPendingNotify = false;

    // Finalize any in-flight streaming entries
    for (final entry in _streamingBlocks.values) {
      if (entry is TextOutputEntry) {
        entry.isStreaming = false;
      } else if (entry is ToolUseOutputEntry) {
        entry.isStreaming = false;
      }
    }

    if (_streamingChat != null) {
      _streamingChat!.notifyListeners();
    }

    _streamingBlocks.clear();
    _activeStreamingEntries.clear();
    _streamingConversationId = null;
    _streamingChat = null;
  }

  // Task 4e: Subagent routing + title generation
  void _handleSubagentSpawn(ChatState chat, SubagentSpawnEvent event) {
    // Check if this is a resume of an existing agent
    if (event.isResume && event.resumeAgentId != null) {
      final existingAgent = chat.findAgentByResumeId(event.resumeAgentId!);
      if (existingAgent != null) {
        developer.log(
          'Resuming existing agent: resumeId=${event.resumeAgentId} -> '
          'conversationId=${existingAgent.conversationId}',
          name: 'EventHandler',
        );

        // Update the agent status back to working
        chat.updateAgent(AgentStatus.working, existingAgent.sdkAgentId);

        // Map this new callId to the existing conversation
        _agentIdToConversationId[event.callId] = existingAgent.conversationId;

        // Also map the new callId to the existing agent for result routing
        _toolUseIdToAgentId[event.callId] = existingAgent.sdkAgentId;

        return;
      } else {
        developer.log(
          'Resume requested but agent not found: resumeId=${event.resumeAgentId}',
          name: 'EventHandler',
          level: 900, // Warning
        );
        // Fall through to create a new agent
      }
    }

    developer.log(
      'Creating subagent: type=${event.agentType ?? "null"}, '
      'description=${event.description?.substring(0, event.description!.length > 50 ? 50 : event.description!.length) ?? "null"}...',
      name: 'EventHandler',
    );

    // Log warning if expected fields are missing
    if (event.agentType == null) {
      developer.log(
        'SubagentSpawnEvent missing agentType field',
        name: 'EventHandler',
      );
    }
    if (event.description == null) {
      developer.log(
        'SubagentSpawnEvent missing description field',
        name: 'EventHandler',
      );
    }

    LogService.instance.debug(
      'Task',
      'Task tool created: type=${event.agentType ?? "unknown"} '
      'description=${event.description ?? "none"}',
    );

    // Create subagent conversation and agent
    chat.addSubagentConversation(event.callId, event.agentType, event.description);

    // Map this callId to the new conversation for routing
    final agent = chat.activeAgents[event.callId];
    if (agent != null) {
      _agentIdToConversationId[event.callId] = agent.conversationId;
      developer.log(
        'Subagent created: callId=${event.callId} -> '
        'conversationId=${agent.conversationId}',
        name: 'EventHandler',
      );
    } else {
      developer.log(
        'ERROR: Failed to create agent for callId=${event.callId}',
        name: 'EventHandler',
        level: 1000, // Error level
      );
    }
  }

  void _handleSubagentComplete(ChatState chat, SubagentCompleteEvent event) {
    // Look up correct agent ID: for resumed agents, use the mapped ID
    final agentId = _toolUseIdToAgentId[event.callId] ?? event.callId;

    // Determine agent status from event status
    final AgentStatus agentStatus;
    if (event.status == 'completed') {
      agentStatus = AgentStatus.completed;
    } else if (event.status == 'error' ||
        event.status == 'error_max_turns' ||
        event.status == 'error_tool' ||
        event.status == 'error_api' ||
        event.status == 'error_budget') {
      agentStatus = AgentStatus.error;
    } else {
      // Unknown status - treat as completed
      agentStatus = AgentStatus.completed;
    }

    developer.log(
      'Subagent complete: callId=${event.callId}, agentId=$agentId, '
      'status=${event.status}, agentStatus=${agentStatus.name}',
      name: 'EventHandler',
    );

    LogService.instance.debug(
      'Task',
      'Task tool finished: status=${event.status ?? "unknown"}',
    );

    // Update the agent status and store the resumeId for future resume operations
    chat.updateAgent(
      agentStatus,
      agentId,
      result: event.summary,
      resumeId: event.agentId,
    );
  }

  /// Generates an AI-powered title for a chat based on the user's message.
  ///
  /// Call this when creating a new chat and sending the first message.
  /// The title generation is fire-and-forget - failures are logged but don't
  /// affect the user experience.
  ///
  /// The method is idempotent - it tracks which chats have had title generation
  /// attempted and won't generate twice for the same chat.
  ///
  /// Parameters:
  /// - [chat]: The chat to generate a title for
  /// - [userMessage]: The user's message to base the title on
  void generateChatTitle(ChatState chat, String userMessage) {
    // Fire and forget - don't await
    _generateChatTitleAsync(chat, userMessage);
  }

  Future<void> _generateChatTitleAsync(
    ChatState chat,
    String userMessage,
  ) async {
    // Skip if no AskAiService available
    if (_askAiService == null) return;

    // Skip if AI chat labels are disabled
    final config = RuntimeConfig.instance;
    if (!config.aiChatLabelsEnabled) return;

    // Skip if we've already generated (or attempted to generate) a title for this chat
    if (_titlesGenerated.contains(chat.data.id)) return;

    // Skip if currently generating a title for this chat
    if (_pendingTitleGenerations.contains(chat.data.id)) return;

    if (userMessage.isEmpty) return;

    // Get the working directory
    final workingDirectory = chat.data.worktreeRoot;
    if (workingDirectory == null) return;

    // Mark as generated (even before we start, to prevent duplicate attempts)
    _titlesGenerated.add(chat.data.id);

    // Mark as pending (prevents duplicate concurrent requests)
    _pendingTitleGenerations.add(chat.data.id);

    try {
      final prompt = '''Read the following and produce a short 3-5 word statement succiciently summing up what the request is. It should be concise, do not worry about grammer.
Your reply should be between ==== marks. eg:
=====
Automatic Chat Summary
=====

User's message:
$userMessage''';

      final result = await _askAiService!.ask(
        prompt: prompt,
        workingDirectory: workingDirectory,
        model: config.aiChatLabelModel,
        allowedTools: [], // No tools needed for title generation
        maxTurns: 1, // Single turn only - no tool use
        timeoutSeconds: 30,
      );

      if (result != null && !result.isError && result.result.isNotEmpty) {
        // Extract the title from between ==== marks
        final rawResult = result.result;
        final titleMatch = RegExp(r'=+\s*\n(.+?)\n\s*=+', dotAll: true)
            .firstMatch(rawResult);

        String title;
        if (titleMatch != null) {
          title = titleMatch.group(1)?.trim() ?? rawResult.trim();
        } else {
          // Fallback: use the raw result if no ==== marks found
          title = rawResult.trim();
        }

        // Clean up the title - remove any remaining markers and limit length
        title = title
            .replaceAll(RegExp(r'^=+'), '')
            .replaceAll(RegExp(r'=+$'), '')
            .trim();
        if (title.length > 50) {
          title = '${title.substring(0, 47)}...';
        }

        if (title.isNotEmpty) {
          chat.rename(title);
        }
      }
    } catch (e) {
      // Title generation is fire-and-forget - log but don't propagate errors
      developer.log(
        'Failed to generate chat title: $e',
        name: 'EventHandler',
        level: 900,
      );
    } finally {
      _pendingTitleGenerations.remove(chat.data.id);
    }
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
