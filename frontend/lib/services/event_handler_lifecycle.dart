part of 'event_handler.dart';

/// Session lifecycle, configuration, compaction, and turn management.
mixin _LifecycleMixin on _EventHandlerBase {
  void _handleSessionInit(ChatState chat, SessionInitEvent event) {
    // Sync the server-reported model to the chat's model dropdown so the UI
    // shows the actual resolved model (e.g. "gpt-5.2-codex" instead of
    // "Default (server)").
    final serverModel = event.model;
    if (serverModel != null && serverModel.isNotEmpty) {
      final models = ChatModelCatalog.forBackend(chat.model.backend);
      final match = models.where((m) => m.id == serverModel).toList();
      if (match.isNotEmpty) {
        chat.syncModelFromServer(match.first);
      } else {
        // Model not in catalog — add it dynamically so the dropdown shows it
        final resolved = ChatModel(
          id: serverModel,
          label: serverModel,
          backend: chat.model.backend,
        );
        chat.syncModelFromServer(resolved);
      }
    }

    // Sync the server-reported reasoning effort to the chat so the dropdown
    // reflects what the server is actually using.
    final effort = ReasoningEffort.fromString(event.reasoningEffort);
    if (effort != null && effort != chat.reasoningEffort) {
      chat.syncReasoningEffortFromServer(effort);
    }
  }

  void _handleConfigOptions(ChatState chat, ConfigOptionsEvent event) {
    chat.setAcpConfigOptions(event.configOptions);
  }

  void _handleAvailableCommands(ChatState chat, AvailableCommandsEvent event) {
    chat.setAcpAvailableCommands(event.availableCommands);
  }

  void _handleSessionMode(ChatState chat, SessionModeEvent event) {
    chat.setAcpSessionMode(
      currentModeId: event.currentModeId,
      availableModes: event.availableModes,
    );
  }

  void _handleSessionStatus(ChatState chat, SessionStatusEvent event) {
    if (event.status == SessionStatus.compacting) {
      chat.setCompacting(true);
    } else {
      chat.setCompacting(false);
    }

    final permMode = event.extensions?['permissionMode'] as String?;
    if (permMode != null) {
      chat.setPermissionMode(PermissionMode.fromApiName(permMode));
    }
  }

  void _handleCompaction(ChatState chat, ContextCompactionEvent event) {
    if (event.trigger == CompactionTrigger.cleared) {
      chat.addEntry(ContextClearedEntry(timestamp: DateTime.now()));
      chat.resetContext();
      return;
    }

    final message = event.preTokens != null
        ? 'Was ${_formatTokens(event.preTokens!)} tokens'
        : null;
    final isManual = event.trigger == CompactionTrigger.manual;

    chat.addEntry(AutoCompactionEntry(
      timestamp: DateTime.now(),
      message: message,
      isManual: isManual,
    ));

    if (event.summary != null) {
      chat.addEntry(ContextSummaryEntry(
        timestamp: DateTime.now(),
        summary: event.summary!,
      ));
    } else {
      _expectingContextSummary[chat.data.id] = true;
    }
  }

  void _handleTurnComplete(ChatState chat, TurnCompleteEvent event) {
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

      final lastStepUsage =
          event.extensions?['lastStepUsage'] as Map<String, dynamic>?;
      if (lastStepUsage != null) {
        chat.updateContextFromUsage(lastStepUsage);
      }

      chat.setWorking(false);

      // Handle no-output result
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

      _hasAssistantOutputThisTurn[chatId] = false;

      // Ticket status transitions
      _ticketBridge.onTurnComplete(chat, event);
    } else {
      // Subagent result
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

  void _handleUsageUpdate(ChatState chat, UsageUpdateEvent event) {
    final outputTokens =
        (event.stepUsage['output_tokens'] as num?)?.toInt() ?? 0;
    chat.addInTurnOutputTokens(outputTokens);

    final parentCallId = event.extensions?['parent_tool_use_id'] as String?;
    if (parentCallId != null) return;

    chat.updateContextFromUsage(event.stepUsage);
  }

  /// Formats token count with K suffix for readability.
  String _formatTokens(int tokens) {
    if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }
}
