import 'package:flutter/foundation.dart';

/// Actions that can be triggered from the application menu.
enum MenuAction {
  // View actions
  showWorkspace,
  showFileManager,
  showSettings,
  showProjectSettings,

  // Worktree actions
  newWorktree,
  newChat,

  // Actions submenu
  actionTest,
  actionRun,

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
class MenuActionService extends ChangeNotifier {
  MenuAction? _lastAction;

  /// The last action that was triggered.
  /// Listeners should check this when notified and clear it after handling.
  MenuAction? get lastAction => _lastAction;

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
