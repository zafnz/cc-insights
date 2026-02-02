import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/output_entry.dart';
import 'ask_ai_service.dart';

/// Handles SDK messages and routes them to the correct conversation.
///
/// This class is responsible for:
/// - Parsing incoming SDK messages and creating appropriate OutputEntry objects
/// - Tool use → tool result pairing via [_toolUseIdToEntry]
/// - Conversation routing via parentToolUseId → [_agentIdToConversationId]
/// - Agent lifecycle management (Task tool spawning)
///
/// The handler is stateless with respect to [ChatState] - the chat is passed
/// to [handleMessage] rather than stored. Internal tracking maps are keyed
/// by toolUseId/agentId which are unique across sessions.
///
/// Future Phase 3 will add:
/// - Streaming state tracking for real-time text updates
/// - Throttled notifications for performance
class SdkMessageHandler {
  /// Tool pairing: toolUseId → entry (for updating with result later).
  final Map<String, ToolUseOutputEntry> _toolUseIdToEntry = {};

  /// Agent routing: parentToolUseId (SDK agent ID) → conversationId.
  final Map<String, String> _agentIdToConversationId = {};

  /// Maps new Task toolUseId → original agent's sdkAgentId (for resumed agents).
  ///
  /// When an agent is resumed with a new Task tool call, the new toolUseId
  /// needs to map back to the original agent's sdkAgentId so that results
  /// update the correct agent.
  final Map<String, String> _toolUseIdToAgentId = {};

  /// Tracks whether assistant output was added during the current turn.
  ///
  /// Used to determine whether to display result messages - if no assistant
  /// output was added (e.g., for an unrecognized slash command), the result
  /// message should be shown to the user.
  bool _hasAssistantOutputThisTurn = false;

  /// Tracks whether we're expecting a context summary message.
  ///
  /// Set to true after receiving a compact_boundary message. The next user
  /// message will be treated as the context summary and displayed as a
  /// [ContextSummaryEntry].
  bool _expectingContextSummary = false;

  /// AskAiService for generating chat titles.
  final AskAiService? _askAiService;

  /// Set of chat IDs that are currently having their title generated.
  ///
  /// Used to prevent duplicate concurrent title generation requests.
  final Set<String> _pendingTitleGenerations = {};

  /// Set of chat IDs that have already had title generation attempted.
  ///
  /// Once a chat ID is in this set, we won't attempt title generation again.
  /// This persists for the lifetime of the SdkMessageHandler instance.
  final Set<String> _titlesGenerated = {};

  // Phase 3: Streaming state (commented out for now)
  // final Map<String, Map<int, OutputEntry>> _streamingEntries = {};
  // Timer? _notifyTimer;

  /// Creates an [SdkMessageHandler].
  ///
  /// If [askAiService] is provided, it will be used to auto-generate chat
  /// titles after the first assistant response.
  SdkMessageHandler({AskAiService? askAiService}) : _askAiService = askAiService;

  /// Handle an incoming SDK message.
  ///
  /// The [chat] is the ChatState to route messages to.
  /// The [rawMessage] should be the payload from an `sdk.message` protocol
  /// message, containing the SDK message type and content.
  void handleMessage(ChatState chat, Map<String, dynamic> rawMessage) {
    final type = rawMessage['type'] as String?;

    switch (type) {
      case 'system':
        _handleSystemMessage(chat, rawMessage);
      case 'assistant':
        _handleAssistantMessage(chat, rawMessage);
      case 'user':
        _handleUserMessage(chat, rawMessage);
      case 'result':
        _handleResultMessage(chat, rawMessage);
      case 'stream_event':
        _handleStreamEvent(rawMessage);
      default:
        _handleUnknownMessage(chat, rawMessage, type ?? 'null');
    }
  }

  /// Resolves a parentToolUseId to a conversation ID.
  ///
  /// Returns the primary conversation ID if [parentToolUseId] is null,
  /// otherwise looks up the conversation for that agent.
  String _resolveConversationId(ChatState chat, String? parentToolUseId) {
    if (parentToolUseId == null) {
      return chat.data.primaryConversation.id;
    }
    return _agentIdToConversationId[parentToolUseId] ??
        chat.data.primaryConversation.id;
  }

  void _handleSystemMessage(ChatState chat, Map<String, dynamic> msg) {
    final subtype = msg['subtype'] as String?;

    switch (subtype) {
      case 'init':
        // Session initialized - could extract model, tools, etc.
        break;

      case 'status':
        // Status update (e.g., compacting in progress)
        final status = msg['status'] as String?;
        if (status == 'compacting') {
          chat.setCompacting(true);
        } else {
          // status: null means compacting finished
          chat.setCompacting(false);
        }

      case 'compact_boundary':
        // Context was compacted - show notification
        // SDK uses snake_case: compact_metadata, pre_tokens
        // Note: The summary comes in a subsequent user message
        final compactMetadata =
            msg['compact_metadata'] as Map<String, dynamic>? ?? {};
        final trigger = compactMetadata['trigger'] as String? ?? 'auto';
        final preTokens = compactMetadata['pre_tokens'] as int?;
        final isManual = trigger == 'manual';

        // Show compaction notification for both auto and manual compaction
        final message = preTokens != null
            ? 'Was ${_formatTokens(preTokens)} tokens'
            : null;
        chat.addEntry(AutoCompactionEntry(
          timestamp: DateTime.now(),
          message: message,
          isManual: isManual,
        ));

        // The next user message will contain the context summary
        _expectingContextSummary = true;

      case 'context_cleared':
        // Context was cleared (e.g., /clear command)
        chat.addEntry(ContextClearedEntry(timestamp: DateTime.now()));
        chat.resetContext();

      default:
        // Unknown system message subtype - log and display it
        if (subtype != null) {
          developer.log(
            'Unknown system message subtype: $subtype',
            name: 'SdkMessageHandler',
          );
          chat.addEntry(UnknownMessageEntry(
            timestamp: DateTime.now(),
            messageType: 'system:$subtype',
            rawMessage: msg,
          ));
        }
    }
  }

  /// Formats token count with K suffix for readability.
  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  void _handleAssistantMessage(ChatState chat, Map<String, dynamic> msg) {
    final parentToolUseId = msg['parent_tool_use_id'] as String?;
    final conversationId = _resolveConversationId(chat, parentToolUseId);
    final message = msg['message'] as Map<String, dynamic>? ?? {};
    final content = message['content'] as List<dynamic>? ?? [];
    final model = message['model'] as String?;
    final errorType = msg['error'] as String?;

    // Update context tracking from main agent assistant messages only.
    // Subagent messages have their own context which could be confusing
    // to display (especially if using a different model like Haiku).
    final usage = message['usage'] as Map<String, dynamic>?;
    if (usage != null && parentToolUseId == null) {
      chat.updateContextFromUsage(usage);
    }

    for (final block in content) {
      final blockMap = block as Map<String, dynamic>;
      final blockType = blockMap['type'] as String?;

      switch (blockType) {
        case 'text':
          final textEntry = TextOutputEntry(
            timestamp: DateTime.now(),
            text: blockMap['text'] as String? ?? '',
            contentType: 'text',
            errorType: errorType,
          );
          textEntry.addRawMessage(msg);
          chat.addOutputEntry(conversationId, textEntry);
          // Mark that we have assistant output for this turn (main agent only)
          if (parentToolUseId == null) {
            _hasAssistantOutputThisTurn = true;
          }

        case 'thinking':
          final thinkingEntry = TextOutputEntry(
            timestamp: DateTime.now(),
            text: blockMap['thinking'] as String? ?? '',
            contentType: 'thinking',
          );
          thinkingEntry.addRawMessage(msg);
          chat.addOutputEntry(conversationId, thinkingEntry);
          // Mark that we have assistant output for this turn (main agent only)
          if (parentToolUseId == null) {
            _hasAssistantOutputThisTurn = true;
          }

        case 'tool_use':
          final toolUseId = blockMap['id'] as String? ?? '';
          final toolName = blockMap['name'] as String? ?? '';
          final inputRaw = blockMap['input'];
          final toolInput = inputRaw is Map<String, dynamic>
              ? inputRaw
              : <String, dynamic>{};

          developer.log(
            'Tool use detected: $toolName (id: $toolUseId)',
            name: 'SdkMessageHandler',
          );

          final entry = ToolUseOutputEntry(
            timestamp: DateTime.now(),
            toolName: toolName,
            toolUseId: toolUseId,
            toolInput: Map<String, dynamic>.from(toolInput),
            model: model,
          );

          // Add raw message for debugging
          entry.addRawMessage(msg);

          // Track for pairing with tool_result
          _toolUseIdToEntry[toolUseId] = entry;
          chat.addOutputEntry(conversationId, entry);

          // Check for Task tool (spawns subagent)
          if (toolName == 'Task') {
            developer.log(
              'Task tool detected! Creating subagent for toolUseId: $toolUseId',
              name: 'SdkMessageHandler',
            );
            _handleTaskToolSpawn(chat, toolUseId, entry);
          }
      }
    }
  }

  void _handleUserMessage(ChatState chat, Map<String, dynamic> msg) {
    final message = msg['message'] as Map<String, dynamic>? ?? {};
    final rawContent = message['content'];

    // Content can be either a String or a List of content blocks
    final List<dynamic> content;
    if (rawContent is String) {
      // Simple string content - wrap in a text block for uniform handling
      content = [
        {'type': 'text', 'text': rawContent}
      ];
    } else if (rawContent is List) {
      content = rawContent;
    } else {
      content = [];
    }

    // Check if this is a context summary message (after compaction)
    // The SDK may send this with isSynthetic=true, or we track it via
    // _expectingContextSummary flag after receiving compact_boundary
    final isSynthetic = msg['isSynthetic'] as bool? ?? false;
    final isReplay = msg['isReplay'] as bool? ?? false;
    if (isSynthetic || (_expectingContextSummary && !isReplay)) {
      // Reset the flag
      _expectingContextSummary = false;

      // Extract the text content and display as a context summary entry
      for (final block in content) {
        if (block is! Map<String, dynamic>) continue;
        final blockType = block['type'] as String?;
        if (blockType == 'text') {
          final text = block['text'] as String? ?? '';
          if (text.isNotEmpty) {
            chat.addEntry(ContextSummaryEntry(
              timestamp: DateTime.now(),
              summary: text,
            ));
          }
        }
      }
      return;
    }

    for (final block in content) {
      if (block is! Map<String, dynamic>) continue;
      final blockType = block['type'] as String?;

      if (blockType == 'tool_result') {
        final toolUseId = block['tool_use_id'] as String? ?? '';
        final entry = _toolUseIdToEntry[toolUseId];

        if (entry != null) {
          // Get structured result if available (richer data for display)
          final toolUseResult = msg['tool_use_result'];
          final isError = block['is_error'] == true;
          final resultData = toolUseResult ?? block['content'];

          // Update the entry in place
          entry.updateResult(resultData, isError);

          // Add the result message to raw messages for debugging
          entry.addRawMessage(msg);

          // Persist the tool result to the JSONL file
          chat.persistToolResult(toolUseId, resultData, isError);

          // Check if this is a Task tool result (subagent completion)
          if (entry.toolName == 'Task' && toolUseResult is Map) {
            // For resumed agents, look up the original agent's sdkAgentId
            final agentId = _toolUseIdToAgentId[toolUseId] ?? toolUseId;
            _handleTaskToolResult(chat, agentId, toolUseResult, isError);
          }

          // Entry already in the list - just notify listeners
          chat.notifyListeners();
        }

        // Clear any pending permission request for this specific tool.
        // This handles the timeout case: when the SDK times out waiting for
        // permission, it sends a tool result (denied), and we should dismiss
        // the stale permission widget.
        //
        // This is safe for parallel tool calls because we match by toolUseId,
        // so only the specific tool's permission is cleared, not others.
        if (toolUseId.isNotEmpty) {
          chat.removePendingPermissionByToolUseId(toolUseId);
        }
      }
    }
  }

  void _handleTaskToolSpawn(
    ChatState chat,
    String toolUseId,
    ToolUseOutputEntry entry,
  ) {
    final input = entry.toolInput;

    developer.log(
      'Task tool spawn: input keys = ${input.keys.toList()}',
      name: 'SdkMessageHandler',
    );

    // Check if this is a resume of an existing agent
    final resumeId = input['resume'] as String?;
    if (resumeId != null) {
      final existingAgent = chat.findAgentByResumeId(resumeId);
      if (existingAgent != null) {
        developer.log(
          'Resuming existing agent: resumeId=$resumeId -> '
          'conversationId=${existingAgent.conversationId}',
          name: 'SdkMessageHandler',
        );

        // Update the agent status back to working
        chat.updateAgent(AgentStatus.working, existingAgent.sdkAgentId);

        // Map this new toolUseId to the existing conversation
        _agentIdToConversationId[toolUseId] = existingAgent.conversationId;

        // Also map the new toolUseId to the existing agent for result routing
        // We need to track this separately since activeAgents is keyed by original sdkAgentId
        _toolUseIdToAgentId[toolUseId] = existingAgent.sdkAgentId;

        return;
      } else {
        developer.log(
          'Resume requested but agent not found: resumeId=$resumeId',
          name: 'SdkMessageHandler',
          level: 900, // Warning
        );
        // Fall through to create a new agent
      }
    }

    // Extract agent type from Task tool input.
    // The SDK uses 'subagent_type' for the agent type (e.g., "general-purpose",
    // "Explore", "Plan"). Some older code may use 'name'.
    final agentType = input['subagent_type'] as String? ??
        input['name'] as String?;

    // Extract task description from 'description' field.
    // This is a short (3-5 word) summary of what the agent will do.
    // Fall back to 'task' for backwards compatibility.
    final taskDescription = input['description'] as String? ??
        input['task'] as String?;

    developer.log(
      'Creating subagent: type=${agentType ?? "null"}, description=${taskDescription?.substring(0, taskDescription.length > 50 ? 50 : taskDescription.length) ?? "null"}...',
      name: 'SdkMessageHandler',
    );

    // Log warning if expected fields are missing
    if (input['subagent_type'] == null && input['name'] == null) {
      developer.log(
        'Task tool missing subagent_type/name field. Input keys: ${input.keys.toList()}',
        name: 'SdkMessageHandler',
      );
    }
    if (input['description'] == null) {
      developer.log(
        'Task tool missing description field. Input keys: ${input.keys.toList()}',
        name: 'SdkMessageHandler',
      );
    }

    // Create subagent conversation and agent
    chat.addSubagentConversation(toolUseId, agentType, taskDescription);

    // Map this toolUseId to the new conversation for routing
    final agent = chat.activeAgents[toolUseId];
    if (agent != null) {
      _agentIdToConversationId[toolUseId] = agent.conversationId;
      developer.log(
        'Subagent created: toolUseId=$toolUseId -> conversationId=${agent.conversationId}',
        name: 'SdkMessageHandler',
      );
    } else {
      developer.log(
        'ERROR: Failed to create agent for toolUseId=$toolUseId',
        name: 'SdkMessageHandler',
        level: 1000, // Error level
      );
    }
  }

  /// Handles Task tool result (subagent completion).
  ///
  /// Updates the agent status based on the tool_use_result content.
  /// The result contains a 'status' field: 'completed', 'error', etc.
  /// Also extracts the SDK's `agentId` for future resume operations.
  void _handleTaskToolResult(
    ChatState chat,
    String toolUseId,
    Map<dynamic, dynamic> toolUseResult,
    bool isError,
  ) {
    final resultStatus = toolUseResult['status'] as String?;
    // Extract the SDK's agentId for resume support
    final resumeId = toolUseResult['agentId'] as String?;

    developer.log(
      'Task tool result: toolUseId=$toolUseId, status=$resultStatus, '
      'resumeId=$resumeId, isError=$isError',
      name: 'SdkMessageHandler',
    );

    // Determine agent status from result
    final AgentStatus agentStatus;
    if (isError) {
      agentStatus = AgentStatus.error;
    } else if (resultStatus == 'completed') {
      agentStatus = AgentStatus.completed;
    } else if (resultStatus == 'error' ||
        resultStatus == 'error_max_turns' ||
        resultStatus == 'error_tool' ||
        resultStatus == 'error_api' ||
        resultStatus == 'error_budget') {
      agentStatus = AgentStatus.error;
    } else {
      // Unknown status - treat as completed
      agentStatus = AgentStatus.completed;
    }

    // Extract result summary from content
    String? resultSummary;
    final content = toolUseResult['content'];
    if (content is List && content.isNotEmpty) {
      // Get first text content as summary
      for (final item in content) {
        if (item is Map && item['type'] == 'text') {
          resultSummary = item['text'] as String?;
          break;
        }
      }
    }

    // Update the agent status and store the resumeId for future resume operations
    chat.updateAgent(
      agentStatus,
      toolUseId,
      result: resultSummary,
      resumeId: resumeId,
    );
  }

  void _handleResultMessage(ChatState chat, Map<String, dynamic> msg) {
    final parentToolUseId = msg['parent_tool_use_id'] as String?;

    // Extract total cost
    final totalCostUsd =
        (msg['total_cost_usd'] as num?)?.toDouble() ?? 0.0;

    // Extract aggregate usage
    final usageData = msg['usage'] as Map<String, dynamic>?;
    final usage = usageData != null
        ? UsageInfo(
            inputTokens: usageData['input_tokens'] as int? ?? 0,
            outputTokens: usageData['output_tokens'] as int? ?? 0,
            cacheReadTokens:
                usageData['cache_read_input_tokens'] as int? ?? 0,
            cacheCreationTokens:
                usageData['cache_creation_input_tokens'] as int? ?? 0,
            costUsd: totalCostUsd,
          )
        : const UsageInfo.zero();

    // Extract per-model usage breakdown
    List<ModelUsageInfo>? modelUsage;
    int? contextWindow;
    final modelUsageData = msg['modelUsage'] as Map<String, dynamic>?;
    if (modelUsageData != null && modelUsageData.isNotEmpty) {
      modelUsage = modelUsageData.entries.map((entry) {
        final data = entry.value as Map<String, dynamic>;
        return ModelUsageInfo(
          modelName: entry.key,
          inputTokens: data['inputTokens'] as int? ?? 0,
          outputTokens: data['outputTokens'] as int? ?? 0,
          cacheReadTokens: data['cacheReadInputTokens'] as int? ?? 0,
          cacheCreationTokens: data['cacheCreationInputTokens'] as int? ?? 0,
          costUsd: (data['costUSD'] as num?)?.toDouble() ?? 0.0,
          contextWindow: data['contextWindow'] as int? ?? 200000,
        );
      }).toList();

      // Get context window from first model (they should all be the same)
      contextWindow = modelUsage.first.contextWindow;
    }

    // Check for agent completion
    final subtype = msg['subtype'] as String?;

    // Only update cumulative usage for main agent results (not subagents).
    // Subagent costs are already included in the parent's total_cost_usd.
    if (parentToolUseId == null) {
      chat.updateCumulativeUsage(
        usage: usage,
        totalCostUsd: totalCostUsd,
        modelUsage: modelUsage,
        contextWindow: contextWindow,
      );
    }

    if (parentToolUseId != null) {
      // This is a subagent result
      final status = switch (subtype) {
        'success' => AgentStatus.completed,
        'error_max_turns' ||
        'error_tool' ||
        'error_api' ||
        'error_budget' =>
          AgentStatus.error,
        _ => AgentStatus.completed,
      };

      chat.updateAgent(status, parentToolUseId);
    } else {
      // This is the main agent result - Claude is done working
      chat.setWorking(false);

      // If no assistant output was added during this turn and there's a result
      // message, display it as a system notification (e.g., "Unknown skill: clear")
      final result = msg['result'] as String?;
      if (!_hasAssistantOutputThisTurn &&
          result != null &&
          result.isNotEmpty) {
        chat.addEntry(SystemNotificationEntry(
          timestamp: DateTime.now(),
          message: result,
        ));
      }

      // Reset the flag for the next turn
      _hasAssistantOutputThisTurn = false;
    }
  }

  void _handleStreamEvent(Map<String, dynamic> msg) {
    // Phase 3: Streaming support
    // For now, ignore stream events - we get complete messages anyway
    // When streaming is enabled, this will create/update streaming entries
  }

  /// Handles unknown message types by displaying them for debugging.
  void _handleUnknownMessage(
    ChatState chat,
    Map<String, dynamic> msg,
    String messageType,
  ) {
    developer.log(
      'Unknown SDK message type: $messageType',
      name: 'SdkMessageHandler',
    );
    chat.addEntry(UnknownMessageEntry(
      timestamp: DateTime.now(),
      messageType: messageType,
      rawMessage: msg,
    ));
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

  Future<void> _generateChatTitleAsync(ChatState chat, String userMessage) async {
    // Skip if no AskAiService available
    if (_askAiService == null) return;

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
        model: 'haiku',
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
        title = title.replaceAll(RegExp(r'^=+'), '').replaceAll(RegExp(r'=+$'), '').trim();
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
        name: 'SdkMessageHandler',
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
    _toolUseIdToEntry.clear();
    _agentIdToConversationId.clear();
    _toolUseIdToAgentId.clear();
    _hasAssistantOutputThisTurn = false;
    _expectingContextSummary = false;
    _pendingTitleGenerations.clear();
    _titlesGenerated.clear();
  }

  /// Disposes of resources.
  void dispose() {
    clear();
    // Phase 3: _notifyTimer?.cancel();
  }
}
