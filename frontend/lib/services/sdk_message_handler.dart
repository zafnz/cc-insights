import 'dart:async';
import 'dart:developer' as developer;

import 'package:agent_sdk_core/agent_sdk_core.dart' show BackendProvider, ToolKind;
import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/output_entry.dart';
import 'ask_ai_service.dart';
import 'log_service.dart';
import 'runtime_config.dart';

/// Handles SDK messages and routes them to the correct conversation.
///
/// This class is responsible for:
/// - Parsing incoming SDK messages and creating appropriate OutputEntry objects
/// - Tool use → tool result pairing via [_toolUseIdToEntry]
/// - Conversation routing via parentToolUseId → [_agentIdToConversationId]
/// - Agent lifecycle management (Task tool spawning)
/// - Streaming: processing stream_event messages into live-updating entries
///   with throttled UI notifications
///
/// The handler is stateless with respect to [ChatState] - the chat is passed
/// to [handleMessage] rather than stored. Internal tracking maps are keyed
/// by toolUseId/agentId which are unique across sessions.
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

  /// Tracks whether assistant output was added during the current turn,
  /// per chat.
  ///
  /// Used to determine whether to display result messages - if no assistant
  /// output was added (e.g., for an unrecognized slash command), the result
  /// message should be shown to the user.
  final Map<String, bool> _hasAssistantOutputThisTurn = {};

  /// Tracks whether we're expecting a context summary message, per chat.
  ///
  /// Set to true after receiving a compact_boundary message. The next user
  /// message will be treated as the context summary and displayed as a
  /// [ContextSummaryEntry].
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
  /// This persists for the lifetime of the SdkMessageHandler instance.
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
  /// Used by [_handleAssistantMessage] to finalize instead of duplicate.
  final Map<String, List<OutputEntry>> _activeStreamingEntries = {};

  /// Throttle timer for batching UI updates during streaming.
  Timer? _notifyTimer;

  /// Whether any deltas arrived since the last timer tick.
  bool _hasPendingNotify = false;

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
        _handleStreamEvent(chat, rawMessage);
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
        // Status update (e.g., compacting in progress, permission mode change)
        final status = msg['status'] as String?;
        if (status == 'compacting') {
          chat.setCompacting(true);
        } else {
          // status: null means compacting finished
          chat.setCompacting(false);
        }

        // Sync permission mode when the CLI reports it (e.g., entering plan mode)
        final permMode = msg['permissionMode'] as String?;
        if (permMode != null) {
          chat.setPermissionMode(PermissionMode.fromApiName(permMode));
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
        _expectingContextSummary[chat.data.id] = true;

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

    // Check if we have streaming entries to finalize for this conversation.
    // When streaming is active, entries are created during content_block_start
    // events. The final assistant message should finalize those entries
    // rather than creating duplicates.
    final streamingEntries = _activeStreamingEntries.remove(conversationId);
    if (streamingEntries != null && streamingEntries.isNotEmpty) {
      _finalizeStreamingEntries(
          chat, msg, streamingEntries, content, model, errorType,
          parentToolUseId);
      return;
    }

    // Non-streaming path: create entries as before
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
            _hasAssistantOutputThisTurn[chat.data.id] = true;
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
            _hasAssistantOutputThisTurn[chat.data.id] = true;
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
            toolKind: ToolKind.fromToolName(toolName),
            provider: BackendProvider.claude,
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

  /// Finalizes streaming entries with authoritative data from the
  /// complete assistant message.
  void _finalizeStreamingEntries(
    ChatState chat,
    Map<String, dynamic> msg,
    List<OutputEntry> streamingEntries,
    List<dynamic> content,
    String? model,
    String? errorType,
    String? parentToolUseId,
  ) {
    int streamIdx = 0;

    for (final block in content) {
      final blockMap = block as Map<String, dynamic>;
      final blockType = blockMap['type'] as String?;

      switch (blockType) {
        case 'text':
          if (streamIdx < streamingEntries.length &&
              streamingEntries[streamIdx] is TextOutputEntry) {
            final entry = streamingEntries[streamIdx] as TextOutputEntry;
            entry.text = blockMap['text'] as String? ?? '';
            entry.isStreaming = false;
            entry.addRawMessage(msg);
            // Persist now that we have final content
            chat.persistStreamingEntry(entry);
            streamIdx++;
          }
          if (parentToolUseId == null) {
            _hasAssistantOutputThisTurn[chat.data.id] = true;
          }

        case 'thinking':
          if (streamIdx < streamingEntries.length &&
              streamingEntries[streamIdx] is TextOutputEntry) {
            final entry = streamingEntries[streamIdx] as TextOutputEntry;
            entry.text = blockMap['thinking'] as String? ?? '';
            entry.isStreaming = false;
            entry.addRawMessage(msg);
            chat.persistStreamingEntry(entry);
            streamIdx++;
          }
          if (parentToolUseId == null) {
            _hasAssistantOutputThisTurn[chat.data.id] = true;
          }

        case 'tool_use':
          final toolUseId = blockMap['id'] as String? ?? '';
          final toolName = blockMap['name'] as String? ?? '';
          final inputRaw = blockMap['input'];
          final toolInput = inputRaw is Map<String, dynamic>
              ? inputRaw
              : <String, dynamic>{};

          if (streamIdx < streamingEntries.length &&
              streamingEntries[streamIdx] is ToolUseOutputEntry) {
            final entry =
                streamingEntries[streamIdx] as ToolUseOutputEntry;
            // Update with final parsed input
            entry.toolInput
              ..clear()
              ..addAll(Map<String, dynamic>.from(toolInput));
            entry.isStreaming = false;
            entry.addRawMessage(msg);
            chat.persistStreamingEntry(entry);

            // Task tool detection now that full input is available
            if (toolName == 'Task') {
              developer.log(
                'Task tool detected (finalized): '
                'toolUseId: $toolUseId',
                name: 'SdkMessageHandler',
              );
              _handleTaskToolSpawn(chat, toolUseId, entry);
            }
            streamIdx++;
          } else {
            // No matching streaming entry - create normally
            developer.log(
              'Tool use detected: $toolName (id: $toolUseId)',
              name: 'SdkMessageHandler',
            );
            final entry = ToolUseOutputEntry(
              timestamp: DateTime.now(),
              toolName: toolName,
              toolKind: ToolKind.fromToolName(toolName),
              provider: BackendProvider.claude,
              toolUseId: toolUseId,
              toolInput: Map<String, dynamic>.from(toolInput),
              model: model,
            );
            entry.addRawMessage(msg);
            _toolUseIdToEntry[toolUseId] = entry;
            final conversationId =
                _resolveConversationId(chat, parentToolUseId);
            chat.addOutputEntry(conversationId, entry);

            if (toolName == 'Task') {
              _handleTaskToolSpawn(chat, toolUseId, entry);
            }
          }
      }
    }

    chat.notifyListeners();
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
    final chatId = chat.data.id;
    if (isSynthetic ||
        ((_expectingContextSummary[chatId] ?? false) && !isReplay)) {
      // Reset the flag
      _expectingContextSummary[chatId] = false;

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

    // Handle local command output (e.g., /cost, /compact).
    // These arrive as user messages with isReplay: true and text content
    // wrapped in <local-command-stdout> tags.
    // Skip replay messages that follow a compact_boundary — the
    // AutoCompactionEntry already shows the compaction notification.
    if (isReplay) {
      if (!(_expectingContextSummary[chatId] ?? false)) {
        final localCmdRegex = RegExp(
          r'<local-command-stdout>([\s\S]*?)</local-command-stdout>',
        );
        for (final block in content) {
          if (block is! Map<String, dynamic>) continue;
          if (block['type'] != 'text') continue;
          final text = block['text'] as String? ?? '';
          final match = localCmdRegex.firstMatch(text);
          if (match != null) {
            final output = match.group(1)?.trim() ?? '';
            if (output.isNotEmpty) {
              chat.addEntry(SystemNotificationEntry(
                timestamp: DateTime.now(),
                message: output,
              ));
            }
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

    LogService.instance.debug('Task', 'Task tool created: type=${agentType ?? "unknown"} description=${taskDescription ?? "none"}');

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

    LogService.instance.debug('Task', 'Task tool finished: status=${resultStatus ?? "unknown"} isError=$isError');

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
      final chatId = chat.data.id;
      final result = msg['result'] as String?;
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
    }
  }

  void _handleStreamEvent(ChatState chat, Map<String, dynamic> msg) {
    final event = msg['event'] as Map<String, dynamic>? ?? {};
    final eventType = event['type'] as String? ?? '';
    final parentToolUseId = msg['parent_tool_use_id'] as String?;

    switch (eventType) {
      case 'message_start':
        _onMessageStart(chat, parentToolUseId);

      case 'content_block_start':
        final index = event['index'] as int? ?? 0;
        final contentBlock =
            event['content_block'] as Map<String, dynamic>? ?? {};
        _onContentBlockStart(chat, index, contentBlock);

      case 'content_block_delta':
        final index = event['index'] as int? ?? 0;
        final delta = event['delta'] as Map<String, dynamic>? ?? {};
        _onContentBlockDelta(chat, index, delta);

      case 'content_block_stop':
        final index = event['index'] as int? ?? 0;
        _onContentBlockStop(index);

      case 'message_delta':
        // Contains stop_reason and usage - not needed for streaming UI
        break;

      case 'message_stop':
        _onMessageStop(chat);

      default:
        break;
    }
  }

  void _onMessageStart(ChatState chat, String? parentToolUseId) {
    _streamingConversationId =
        _resolveConversationId(chat, parentToolUseId);
    _streamingChat = chat;
    _streamingBlocks.clear();
  }

  void _onContentBlockStart(
    ChatState chat,
    int index,
    Map<String, dynamic> contentBlock,
  ) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    final blockType = contentBlock['type'] as String? ?? '';

    OutputEntry? entry;
    switch (blockType) {
      case 'text':
        entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: '',
          contentType: 'text',
          isStreaming: true,
        );

      case 'thinking':
        entry = TextOutputEntry(
          timestamp: DateTime.now(),
          text: '',
          contentType: 'thinking',
          isStreaming: true,
        );

      case 'tool_use':
        final toolUseId = contentBlock['id'] as String? ?? '';
        final toolName = contentBlock['name'] as String? ?? '';
        entry = ToolUseOutputEntry(
          timestamp: DateTime.now(),
          toolName: toolName,
          toolKind: ToolKind.fromToolName(toolName),
          provider: BackendProvider.claude,
          toolUseId: toolUseId,
          toolInput: <String, dynamic>{},
          isStreaming: true,
        );
        // Register for tool result pairing
        _toolUseIdToEntry[toolUseId] = entry as ToolUseOutputEntry;

      default:
        return;
    }

    _streamingBlocks[(convId, index)] = entry;
    chat.addOutputEntry(convId, entry);
    _activeStreamingEntries
        .putIfAbsent(convId, () => [])
        .add(entry);
  }

  void _onContentBlockDelta(
    ChatState chat,
    int index,
    Map<String, dynamic> delta,
  ) {
    final convId = _streamingConversationId;
    if (convId == null) return;

    final entry = _streamingBlocks[(convId, index)];
    if (entry == null) return;

    final deltaType = delta['type'] as String? ?? '';
    switch (deltaType) {
      case 'text_delta':
        if (entry is TextOutputEntry) {
          entry.appendDelta(delta['text'] as String? ?? '');
        }

      case 'thinking_delta':
        if (entry is TextOutputEntry) {
          entry.appendDelta(delta['thinking'] as String? ?? '');
        }

      case 'input_json_delta':
        if (entry is ToolUseOutputEntry) {
          entry.appendInputDelta(
              delta['partial_json'] as String? ?? '');
        }

      case 'signature_delta':
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
