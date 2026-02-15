part of 'event_handler.dart';

/// Subagent lifecycle management (spawn, complete, routing).
mixin _SubagentMixin on _EventHandlerBase {
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

        chat.updateAgent(AgentStatus.working, existingAgent.sdkAgentId);
        _agentIdToConversationId[event.callId] = existingAgent.conversationId;
        _toolUseIdToAgentId[event.callId] = existingAgent.sdkAgentId;
        return;
      } else {
        developer.log(
          'Resume requested but agent not found: resumeId=${event.resumeAgentId}',
          name: 'EventHandler',
          level: 900,
        );
      }
    }

    final descPreview = event.description != null
        ? (event.description!.length > 50
            ? '${event.description!.substring(0, 50)}...'
            : event.description!)
        : 'null';
    developer.log(
      'Creating subagent: type=${event.agentType ?? "null"}, '
      'description=$descPreview',
      name: 'EventHandler',
    );

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

    chat.addSubagentConversation(event.callId, event.agentType, event.description);

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
        level: 1000,
      );
    }
  }

  void _handleSubagentComplete(ChatState chat, SubagentCompleteEvent event) {
    final agentId = _toolUseIdToAgentId[event.callId] ?? event.callId;

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

    chat.updateAgent(
      agentStatus,
      agentId,
      result: event.summary,
      resumeId: event.agentId,
    );
  }
}
