import 'package:flutter/foundation.dart';

/// Actions that can be triggered from the application menu.
enum MenuAction {
  // View actions
  showWorkspace,
  showFileManager,
  showSettings,
  showLogs,
  showProjectSettings,

  // Worktree actions
  newWorktree,
  newChat,

  // Actions submenu
  actionTest,
  actionRun,

  // Panels
  toggleMergeChatsAgents,

  // Git submenu
  gitStageCommit,
  gitRebase,
  gitMerge,
  gitMergeIntoMain,
  gitPush,
  gitPull,
  gitCreatePR,
}

/// Service for broadcasting menu actions to listeners.
///
/// This allows the app menu bar (which doesn't have access to the widget tree)
/// to communicate with MainScreen (which needs to respond to navigation actions).
///
/// Also tracks panel merge state so the menu bar can show the correct
/// labels (e.g., "Merge Chats & Agents" vs "Split Chats & Agents").
class MenuActionService extends ChangeNotifier {
  MenuAction? _lastAction;

  /// Whether the chats and agents panels are currently merged.
  bool _agentsMergedIntoChats = false;

  /// The last action that was triggered.
  /// Listeners should check this when notified and clear it after handling.
  MenuAction? get lastAction => _lastAction;

  /// Whether the chats and agents panels are currently merged.
  bool get agentsMergedIntoChats => _agentsMergedIntoChats;

  /// Updates the merge state. Called by MainScreen when merge state changes.
  set agentsMergedIntoChats(bool value) {
    if (_agentsMergedIntoChats != value) {
      _agentsMergedIntoChats = value;
      notifyListeners();
    }
  }

  /// Triggers a menu action and notifies listeners.
  void triggerAction(MenuAction action) {
    _lastAction = action;
    notifyListeners();
  }

  /// Clears the last action. Call this after handling the action.
  void clearAction() {
    _lastAction = null;
  }
}
