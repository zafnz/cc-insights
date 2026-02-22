import 'chat.dart';

/// Reason why a managed worker agent became ready.
enum AgentReadyReason {
  turnComplete('turn_complete'),
  error('error'),
  stopped('stopped'),
  permissionNeeded('permission_needed');

  const AgentReadyReason(this.wireValue);

  final String wireValue;
}

/// Completion status reported by orchestration tools.
enum AgentCompletionStatus {
  unknown('unknown'),
  complete('complete'),
  incomplete('incomplete');

  const AgentCompletionStatus(this.wireValue);

  final String wireValue;
}

/// Runtime metadata for a worker agent managed by an orchestrator chat.
class ManagedAgent {
  const ManagedAgent({required this.id, required this.chat, this.ticketId});

  /// Stable orchestrator-scoped agent ID.
  final String id;

  /// Backing worker chat.
  final Chat chat;

  /// Optional linked ticket ID.
  final int? ticketId;

  Map<String, dynamic> toSnapshot() {
    return {
      'id': id,
      'chatId': chat.id,
      if (ticketId != null) 'ticketId': ticketId,
    };
  }
}
