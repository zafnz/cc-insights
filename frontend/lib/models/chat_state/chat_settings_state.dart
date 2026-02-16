part of 'package:cc_insights_v2/models/chat.dart';

class ChatSettingsState extends ChangeNotifier {
  ChatSettingsState._(this._chat);

  final _ChatCore _chat;

  ChatModel get model => _chat.model;
  sdk.SecurityConfig get securityConfig => _chat.securityConfig;
  PermissionMode get permissionMode => _chat.permissionMode;
  sdk.ReasoningEffort? get reasoningEffort => _chat.reasoningEffort;
  List<Map<String, dynamic>>? get acpConfigOptions => _chat.acpConfigOptions;
  List<Map<String, dynamic>>? get acpAvailableCommands =>
      _chat.acpAvailableCommands;
  String? get acpCurrentModeId => _chat.acpCurrentModeId;
  List<Map<String, dynamic>>? get acpAvailableModes => _chat.acpAvailableModes;

  void setModel(ChatModel model) => _chat.setModel(model);

  void setPermissionMode(PermissionMode mode) => _chat.setPermissionMode(mode);

  void setSecurityConfig(
    sdk.SecurityConfig config, {
    bool notifyChange = true,
  }) {
    _chat.setSecurityConfig(config, notifyChange: notifyChange);
  }

  void setReasoningEffort(sdk.ReasoningEffort? effort) {
    _chat.setReasoningEffort(effort);
  }

  void syncModelFromServer(ChatModel model) => _chat.syncModelFromServer(model);

  void syncReasoningEffortFromServer(sdk.ReasoningEffort? effort) {
    _chat.syncReasoningEffortFromServer(effort);
  }

  void syncFromTransport(sdk.EventTransport transport) {
    _chat._syncServerReportedValues(transport);
  }

  void setAcpConfigOptions(List<Map<String, dynamic>> options) {
    _chat.setAcpConfigOptions(options);
  }

  void setAcpConfigOption({required String configId, required dynamic value}) {
    _chat.setAcpConfigOption(configId: configId, value: value);
  }

  void setAcpAvailableCommands(List<Map<String, dynamic>> commands) {
    _chat.setAcpAvailableCommands(commands);
  }

  void setAcpSessionMode({
    required String currentModeId,
    List<Map<String, dynamic>>? availableModes,
  }) {
    _chat.setAcpSessionMode(
      currentModeId: currentModeId,
      availableModes: availableModes,
    );
  }

  void setAcpMode(String modeId) => _chat.setAcpMode(modeId);

  void clearAcpMetadata() {
    _chat._clearAcpSessionMetadata();
    notifyListeners();
  }

  void syncPermissionModeFromResponse(
    String? toolName,
    List<dynamic>? updatedPermissions,
  ) {
    _chat._syncPermissionModeFromResponse(toolName, updatedPermissions);
    notifyListeners();
  }
}
