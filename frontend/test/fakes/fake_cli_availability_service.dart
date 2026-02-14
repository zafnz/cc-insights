import 'package:cc_insights_v2/models/agent_config.dart';
import 'package:flutter/foundation.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';

/// A fake [CliAvailabilityService] for testing.
///
/// Defaults to all agents available. Use [agentAvailability] setter or
/// [claudeAvailable] setter to configure different availability states.
class FakeCliAvailabilityService extends ChangeNotifier
    implements CliAvailabilityService {
  bool _claudeAvailable = true;
  Map<String, bool> _agentAvailability = {};
  bool _checked = true;
  int checkAgentsCalls = 0;
  int checkClaudeCalls = 0;

  @override
  bool get claudeAvailable => _claudeAvailable;

  @override
  bool get checked => _checked;

  @override
  bool isAgentAvailable(String agentId) =>
      _agentAvailability[agentId] ?? true;

  @override
  Map<String, bool> get agentAvailability =>
      Map.unmodifiable(_agentAvailability);

  @override
  String? resolvedPathForAgent(String agentId) => null;

  set claudeAvailable(bool value) {
    _claudeAvailable = value;
    notifyListeners();
  }

  set agentAvailability(Map<String, bool> value) {
    _agentAvailability = Map.of(value);
    notifyListeners();
  }

  set checked(bool value) {
    _checked = value;
    notifyListeners();
  }

  @override
  Future<void> checkAgents(List<AgentConfig> agents) async {
    checkAgentsCalls++;
  }

  @override
  Future<void> checkClaude({String customPath = ''}) async {
    checkClaudeCalls++;
  }
}
