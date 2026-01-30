import 'package:flutter/foundation.dart';

/// The current status of an SDK agent.
///
/// Agents transition through these states during their lifecycle:
/// - [working]: Actively processing a request
/// - [waitingTool]: Waiting for tool permission approval
/// - [waitingUser]: Waiting for user input or clarification
/// - [completed]: Finished successfully with a result
/// - [error]: Terminated due to an error
enum AgentStatus {
  /// Agent is actively working on a task.
  working,

  /// Agent is waiting for tool permission approval.
  waitingTool,

  /// Agent is waiting for user input or clarification.
  waitingUser,

  /// Agent has completed its task successfully.
  completed,

  /// Agent terminated due to an error.
  error,
}

/// A runtime SDK entity that exists only while a session is active.
///
/// Agents are created when the SDK spawns agents (either the main agent
/// or subagents via the Task tool). Each agent links to a [ConversationData]
/// for persistent output storage.
///
/// When a session ends or is cleared:
/// - Agents are discarded (they are ephemeral)
/// - Conversations persist with their output history
///
/// When a session resumes (future feature):
/// - New agents are created
/// - They link to existing conversations
///
/// This is an immutable data class. Use [copyWith] to create modified copies.
@immutable
class Agent {
  /// The SDK's internal agent ID (tool_use_id of the Task tool).
  ///
  /// This ID is the tool_use_id from the Task tool call and is used as the
  /// key in [ChatState.activeAgents].
  final String sdkAgentId;

  /// The ID of the conversation this agent writes output to.
  ///
  /// Links the ephemeral agent to its persistent conversation log.
  final String conversationId;

  /// The current status of this agent.
  final AgentStatus status;

  /// The result message when the agent completes.
  ///
  /// Only populated when [status] is [AgentStatus.completed] or
  /// [AgentStatus.error].
  final String? result;

  /// The SDK's short agent ID used for resuming.
  ///
  /// This is returned in the Task tool result as `agentId` (e.g., "adba350")
  /// and can be used with the `resume` parameter to continue this agent's work.
  /// May be null until the agent completes its first task.
  final String? resumeId;

  /// Creates an [Agent] instance.
  const Agent({
    required this.sdkAgentId,
    required this.conversationId,
    required this.status,
    this.result,
    this.resumeId,
  });

  /// Creates a new working agent linked to a conversation.
  const Agent.working({required this.sdkAgentId, required this.conversationId})
    : status = AgentStatus.working,
      result = null,
      resumeId = null;

  /// Whether this agent is in a terminal state (completed or error).
  bool get isTerminal =>
      status == AgentStatus.completed || status == AgentStatus.error;

  /// Whether this agent is waiting for user action.
  bool get isWaiting =>
      status == AgentStatus.waitingTool || status == AgentStatus.waitingUser;

  /// Creates a copy with the given fields replaced.
  Agent copyWith({
    String? sdkAgentId,
    String? conversationId,
    AgentStatus? status,
    String? result,
    String? resumeId,
  }) {
    return Agent(
      sdkAgentId: sdkAgentId ?? this.sdkAgentId,
      conversationId: conversationId ?? this.conversationId,
      status: status ?? this.status,
      result: result ?? this.result,
      resumeId: resumeId ?? this.resumeId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Agent &&
        other.sdkAgentId == sdkAgentId &&
        other.conversationId == conversationId &&
        other.status == status &&
        other.result == result &&
        other.resumeId == resumeId;
  }

  @override
  int get hashCode {
    return Object.hash(sdkAgentId, conversationId, status, result, resumeId);
  }

  @override
  String toString() {
    return 'Agent(sdkAgentId: $sdkAgentId, conversationId: $conversationId, '
        'status: $status, result: $result, resumeId: $resumeId)';
  }
}
