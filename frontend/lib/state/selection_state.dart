import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/persistence_service.dart';
import '../services/project_restore_service.dart';

/// Mode for the main content panel.
enum ContentPanelMode {
  /// Normal conversation view
  conversation,

  /// Create worktree form
  createWorktree,

  /// Project settings (per-project configuration)
  projectSettings,
}

/// Provides a unified view of the current selection state.
///
/// This class is a convenience accessor that delegates to the entity hierarchy.
/// Each level in the hierarchy (project, worktree, chat) remembers its own
/// selection, allowing switching contexts while preserving previous selections.
///
/// For example, switching from worktree A to B, then back to A, restores your
/// previous chat/conversation selection in A.
///
/// Panels use this class to get the current context without directly accessing
/// the hierarchy. This allows the selection logic to change without modifying
/// panel implementations.
///
/// File selection is managed separately as it does not belong to the entity
/// hierarchy.
class SelectionState extends ChangeNotifier {
  final ProjectState _project;

  /// Service for lazy-loading chat history.
  final ProjectRestoreService _restoreService;

  /// The currently selected file path, if any.
  ///
  /// File selection is separate from the entity hierarchy (project/worktree/
  /// chat/conversation) and can be set independently.
  String? _selectedFilePath;

  /// The current mode for the main content panel.
  ContentPanelMode _contentPanelMode = ContentPanelMode.conversation;

  /// Creates a [SelectionState] for the given project.
  ///
  /// The project is required and cannot be changed after creation.
  /// An optional [restoreService] can be provided for testing; if not provided,
  /// a default instance is created.
  SelectionState(this._project, {ProjectRestoreService? restoreService})
    : _restoreService = restoreService ?? ProjectRestoreService();

  /// The project this selection state is for.
  ProjectState get project => _project;

  /// The currently selected worktree, if any.
  ///
  /// Delegates to [ProjectState.selectedWorktree].
  WorktreeState? get selectedWorktree => _project.selectedWorktree;

  /// The currently selected chat, if any.
  ///
  /// Follows the hierarchy: returns the selected chat within the selected
  /// worktree. Returns null if no worktree is selected or if the selected
  /// worktree has no selected chat.
  ChatState? get selectedChat => selectedWorktree?.selectedChat;

  /// The currently selected conversation, if any.
  ///
  /// Follows the hierarchy: returns the selected conversation within the
  /// selected chat. Returns null if no chat is selected.
  ConversationData? get selectedConversation =>
      selectedChat?.selectedConversation;

  /// The currently selected file path, if any.
  String? get selectedFilePath => _selectedFilePath;

  /// The current mode for the main content panel.
  ContentPanelMode get contentPanelMode => _contentPanelMode;

  /// Selects a worktree within the project.
  ///
  /// The worktree's previous chat/conversation selection is restored. Panels
  /// will update to show the new worktree's context.
  ///
  /// If the project settings panel is currently shown, it will be closed and
  /// the conversation panel will be shown instead.
  void selectWorktree(WorktreeState worktree) {
    // Mark the previously selected chat as no longer viewed
    final previousChat = selectedChat;
    previousChat?.markAsNotViewed();

    _project.selectWorktree(worktree);

    // Mark the newly selected worktree's chat as viewed (if any)
    final newChat = worktree.selectedChat;
    newChat?.markAsViewed();

    // Close project settings panel if it's open
    if (_contentPanelMode == ContentPanelMode.projectSettings) {
      _contentPanelMode = ContentPanelMode.conversation;
    }

    notifyListeners();
  }

  /// Selects a chat within the currently selected worktree.
  ///
  /// Does nothing if no worktree is selected. Resets the conversation
  /// selection to the primary conversation.
  ///
  /// If the chat's history has not been loaded yet, triggers lazy-loading
  /// in the background. The chat is shown immediately (possibly empty), and
  /// entries appear when loading completes via [notifyListeners].
  void selectChat(ChatState chat) {
    // Mark the previously selected chat as no longer viewed
    final previousChat = selectedChat;
    if (previousChat != null && previousChat != chat) {
      previousChat.markAsNotViewed();
    }

    selectedWorktree?.selectChat(chat);
    // Reset to primary conversation when selecting a chat
    chat.resetToMainConversation();
    // Mark the newly selected chat as viewed (clears unread count)
    chat.markAsViewed();
    notifyListeners();

    // Lazy-load chat history if not already loaded
    _loadChatHistoryIfNeeded(chat);
  }

  /// Loads chat history from persistence if not already loaded.
  ///
  /// This runs asynchronously and does not block the UI. When loading
  /// completes, the chat's entries are populated and [notifyListeners]
  /// is called to update the UI.
  Future<void> _loadChatHistoryIfNeeded(ChatState chat) async {
    if (chat.hasLoadedHistory) {
      developer.log(
        'Chat history already loaded: ${chat.data.name}',
        name: 'SelectionState',
      );
      return;
    }

    final projectId = PersistenceService.generateProjectId(
      _project.data.repoRoot,
    );

    developer.log(
      'Lazy-loading history for chat: ${chat.data.name} (projectId: $projectId)',
      name: 'SelectionState',
    );

    try {
      final entryCount = await _restoreService.loadChatHistory(chat, projectId);
      developer.log(
        'Loaded $entryCount entries for chat: ${chat.data.name}',
        name: 'SelectionState',
      );
      // No need to call notifyListeners here - ChatState.loadEntriesFromPersistence
      // already calls notifyListeners, which triggers UI updates
    } catch (e) {
      developer.log(
        'Failed to load chat history: ${chat.data.name}',
        name: 'SelectionState',
        error: e,
      );
      // Don't rethrow - lazy loading failures shouldn't crash the UI
    }
  }

  /// Selects a conversation within the currently selected chat.
  ///
  /// Does nothing if no chat is selected. For primary conversations, pass the
  /// conversation data directly; the chat will determine whether to use null
  /// (for primary) or the conversation ID (for subagents).
  void selectConversation(ConversationData conversation) {
    selectedChat?.selectConversation(
      conversation.isPrimary ? null : conversation.id,
    );
    notifyListeners();
  }

  /// Selects a file to view.
  ///
  /// Pass a file path to select a file, or null to clear the selection.
  /// File selection is independent of the entity hierarchy.
  void selectFile(String? path) {
    if (_selectedFilePath != path) {
      _selectedFilePath = path;
      notifyListeners();
    }
  }

  /// Clears the current file selection.
  ///
  /// Convenience method equivalent to `selectFile(null)`.
  void clearFileSelection() {
    selectFile(null);
  }

  /// Closes a chat, removing it from persistence and the worktree.
  ///
  /// This method:
  /// 1. Stops any active SDK session
  /// 2. Deletes the chat files from disk
  /// 3. Removes the chat from projects.json
  /// 4. Removes the chat from the worktree state
  /// 5. Notifies listeners to update the UI
  ///
  /// Does nothing if the chat's worktree is not currently selected.
  Future<void> closeChat(
    ChatState chat,
    ProjectRestoreService restoreService,
  ) async {
    final worktree = selectedWorktree;
    if (worktree == null) return;

    // Perform the close operation (deletes files and updates projects.json)
    await restoreService.closeChat(
      _project.data.repoRoot,
      worktree.data.worktreeRoot,
      chat,
    );

    // Remove from the worktree state (this also calls dispose())
    worktree.removeChat(chat);

    // Notify listeners so UI rebuilds
    notifyListeners();
  }

  /// Creates a new chat in the currently selected worktree.
  ///
  /// This method:
  /// 1. Creates a new ChatState with the worktree's welcome screen settings
  /// 2. Persists the chat to projects.json
  /// 3. Adds the chat to the worktree state
  /// 4. Selects the new chat
  /// 5. Notifies listeners to update the UI
  ///
  /// Deselects the current chat, returning to the welcome/new-chat screen.
  ///
  /// Does nothing if no worktree is currently selected.
  void deselectChat() {
    final worktree = selectedWorktree;
    if (worktree == null) return;

    final previousChat = selectedChat;
    if (previousChat != null) {
      previousChat.markAsNotViewed();
    }

    worktree.selectChat(null);
    notifyListeners();
  }

  /// Shows the create worktree panel in the content area.
  void showCreateWorktreePanel() {
    _contentPanelMode = ContentPanelMode.createWorktree;
    notifyListeners();
  }

  /// Returns to the normal conversation panel view.
  void showConversationPanel() {
    _contentPanelMode = ContentPanelMode.conversation;
    notifyListeners();
  }

  /// Shows the project settings panel in the content area.
  void showProjectSettingsPanel() {
    _contentPanelMode = ContentPanelMode.projectSettings;
    notifyListeners();
  }
}
