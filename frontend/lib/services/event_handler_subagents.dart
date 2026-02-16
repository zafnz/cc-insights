part of 'event_handler.dart';

/// Subagent lifecycle management (spawn, complete, routing).
mixin _SubagentMixin on _EventHandlerBase {
  void _handleSubagentSpawn(
    Chat chat,
    SubagentSpawnEvent event,
    SessionEventPipeline pipeline,
  ) {
    // Check if this is a resume of an existing agent
    if (event.isResume && event.resumeAgentId != null) {
      final existingAgent = chat.agents.findAgentByResumeId(
        event.resumeAgentId!,
      );
      if (existingAgent != null) {
        developer.log(
          'Resuming existing agent: resumeId=${event.resumeAgentId} -> '
          'conversationId=${existingAgent.conversationId}',
          name: 'EventHandler',
        );

        chat.agents.updateAgent(AgentStatus.working, existingAgent.sdkAgentId);
        pipeline.agentIdToConversationId[event.callId] =
            existingAgent.conversationId;
        pipeline.toolUseIdToAgentId[event.callId] = existingAgent.sdkAgentId;
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

    chat.conversations.addSubagentConversation(
      event.callId,
      event.agentType,
      event.description,
    );

    final agent = chat.agents.activeAgents[event.callId];
    if (agent != null) {
      pipeline.agentIdToConversationId[event.callId] = agent.conversationId;
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

  void _handleSubagentComplete(
    Chat chat,
    SubagentCompleteEvent event,
    SessionEventPipeline pipeline,
  ) {
    final agentId = pipeline.toolUseIdToAgentId[event.callId] ?? event.callId;

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

    chat.agents.updateAgent(
      agentStatus,
      agentId,
      result: event.summary,
      resumeId: event.agentId,
    );
  }
}
