part of 'package:cc_insights_v2/models/chat.dart';

class ChatConversationState extends ChangeNotifier {
  ChatConversationState._(this._chat);

  final _ChatCore _chat;

  ChatData get data => _chat.data;
  String? get selectedConversationId => _chat._selectedConversationId;
  ConversationData get selectedConversation => _chat.selectedConversation;
  bool get isInputEnabled => _chat.isInputEnabled;
  ConversationData get primaryConversation => _chat.data.primaryConversation;
  Map<String, ConversationData> get subagentConversations =>
      Map.unmodifiable(_chat.data.subagentConversations);
  bool get hasLoadedHistory => _chat.hasLoadedHistory;

  void selectConversation(String? conversationId) {
    _chat.selectConversation(conversationId);
  }

  void resetToMainConversation() => _chat.resetToMainConversation();

  void addEntry(OutputEntry entry) => _chat.addEntry(entry);

  void addOutputEntry(String conversationId, OutputEntry entry) {
    _chat.addOutputEntry(conversationId, entry);
  }

  void addSubagentConversation(
    String sdkAgentId,
    String? label,
    String? taskDescription,
  ) {
    final conversationId = _chat.addSubagentConversation(
      label,
      taskDescription,
    );
    _chat.agents.createWorkingAgent(
      sdkAgentId: sdkAgentId,
      conversationId: conversationId,
    );
  }

  void clearEntries() => _chat.clearEntries();

  void loadEntriesFromPersistence(List<OutputEntry> entries) {
    _chat.loadEntriesFromPersistence(entries);
  }

  void markHistoryAsLoaded() => _chat.markHistoryAsLoaded();

  void rename(String newName) => _chat.rename(newName);

  /// Notifies listeners for in-place entry mutations.
  void notifyMutation() => notifyListeners();
}
