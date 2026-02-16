part of 'package:cc_insights_v2/models/chat.dart';

class ChatAgentState extends ChangeNotifier {
  ChatAgentState._(this._chat);

  final _ChatCore _chat;

  Map<String, Agent> get activeAgents => _chat.activeAgents;
  String? get agentId => _chat.agentId;
  set agentId(String? value) => _chat.agentId = value;
  bool get agentRemoved => _chat.agentRemoved;
  String? get missingAgentMessage => _chat.missingAgentMessage;
  String get agentName => _chat.agentName;
  String get backendLabel => _chat.backendLabel;

  void markAgentMissing(String message) => _chat.markAgentMissing(message);

  Future<void> terminateForAgentRemoval() => _chat.terminateForAgentRemoval();

  void updateAgent(
    AgentStatus status,
    String sdkAgentId, {
    String? result,
    String? resumeId,
  }) {
    _chat.updateAgent(status, sdkAgentId, result: result, resumeId: resumeId);
  }

  Agent? findAgentByResumeId(String resumeId) {
    return _chat.findAgentByResumeId(resumeId);
  }

  void createWorkingAgent({
    required String sdkAgentId,
    required String conversationId,
  }) {
    _chat._activeAgents[sdkAgentId] = Agent.working(
      sdkAgentId: sdkAgentId,
      conversationId: conversationId,
    );
    notifyListeners();
  }

  void clearAll() {
    if (_chat._activeAgents.isEmpty) return;
    _chat._activeAgents.clear();
    notifyListeners();
  }
}
