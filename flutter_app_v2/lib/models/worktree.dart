import 'package:flutter/foundation.dart';

import 'chat.dart';

/// Immutable data representing a git worktree.
///
/// A worktree is a git working tree with files. It has an immutable path
/// ([worktreeRoot]) and mutable state like the current branch and git status.
/// The primary worktree is at the repository root where `.git` lives.
/// Linked worktrees are created via `git worktree add`.
///
/// Use [copyWith] to create modified copies with updated mutable fields.
@immutable
class WorktreeData {
  /// The filesystem path to this worktree. Immutable once created.
  final String worktreeRoot;

  /// Whether this is the primary worktree (at the repository root).
  ///
  /// A project has exactly one primary worktree where the common `.git`
  /// directory lives. All other worktrees are linked worktrees.
  final bool isPrimary;

  /// The current git branch checked out in this worktree.
  ///
  /// This can change via `git checkout` or other git operations.
  /// Branches must be unique across worktrees in the same repository.
  final String branch;

  /// Number of uncommitted files (modified, added, deleted but not staged).
  final int uncommittedFiles;

  /// Number of files staged for commit.
  final int stagedFiles;

  /// Number of commits ahead of the remote tracking branch.
  final int commitsAhead;

  /// Number of commits behind the remote tracking branch.
  final int commitsBehind;

  /// Whether this worktree has unresolved merge conflicts.
  final bool hasMergeConflict;

  /// Creates a new [WorktreeData] instance.
  const WorktreeData({
    required this.worktreeRoot,
    required this.isPrimary,
    required this.branch,
    this.uncommittedFiles = 0,
    this.stagedFiles = 0,
    this.commitsAhead = 0,
    this.commitsBehind = 0,
    this.hasMergeConflict = false,
  });

  /// Creates a copy with the given mutable fields replaced.
  ///
  /// [worktreeRoot] and [isPrimary] are immutable and cannot be changed.
  WorktreeData copyWith({
    String? branch,
    int? uncommittedFiles,
    int? stagedFiles,
    int? commitsAhead,
    int? commitsBehind,
    bool? hasMergeConflict,
  }) {
    return WorktreeData(
      worktreeRoot: worktreeRoot,
      isPrimary: isPrimary,
      branch: branch ?? this.branch,
      uncommittedFiles: uncommittedFiles ?? this.uncommittedFiles,
      stagedFiles: stagedFiles ?? this.stagedFiles,
      commitsAhead: commitsAhead ?? this.commitsAhead,
      commitsBehind: commitsBehind ?? this.commitsBehind,
      hasMergeConflict: hasMergeConflict ?? this.hasMergeConflict,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorktreeData &&
        other.worktreeRoot == worktreeRoot &&
        other.isPrimary == isPrimary &&
        other.branch == branch &&
        other.uncommittedFiles == uncommittedFiles &&
        other.stagedFiles == stagedFiles &&
        other.commitsAhead == commitsAhead &&
        other.commitsBehind == commitsBehind &&
        other.hasMergeConflict == hasMergeConflict;
  }

  @override
  int get hashCode {
    return Object.hash(
      worktreeRoot,
      isPrimary,
      branch,
      uncommittedFiles,
      stagedFiles,
      commitsAhead,
      commitsBehind,
      hasMergeConflict,
    );
  }

  @override
  String toString() {
    return 'WorktreeData(worktreeRoot: $worktreeRoot, isPrimary: $isPrimary, '
        'branch: $branch, uncommittedFiles: $uncommittedFiles, '
        'stagedFiles: $stagedFiles, commitsAhead: $commitsAhead, '
        'commitsBehind: $commitsBehind, hasMergeConflict: $hasMergeConflict)';
  }
}

/// Mutable state holder for a worktree, extending [ChangeNotifier].
///
/// Holds a [WorktreeData] instance and manages the list of chats within this
/// worktree. The worktree remembers which chat was last selected, allowing
/// users to switch worktrees and return to their previous context.
///
/// Call [notifyListeners] after mutations to update the UI.
class WorktreeState extends ChangeNotifier {
  WorktreeData _data;

  final List<ChatState> _chats;
  ChatState? _selectedChat;

  /// Creates a [WorktreeState] with the given initial data.
  ///
  /// [chats] defaults to an empty list if not provided.
  WorktreeState(this._data, {List<ChatState>? chats})
    : _chats = chats ?? [],
      _selectedChat = null;

  /// The immutable data for this worktree.
  WorktreeData get data => _data;

  /// The list of chats in this worktree.
  ///
  /// Returns an unmodifiable view of the chats list.
  List<ChatState> get chats => List.unmodifiable(_chats);

  /// The currently selected chat in this worktree, if any.
  ///
  /// When switching worktrees, the selection is preserved so users can
  /// return to their previous context.
  ChatState? get selectedChat => _selectedChat;

  /// Replaces the entire [WorktreeData] with a new instance.
  ///
  /// Use this when you need to update multiple fields at once.
  void updateData(WorktreeData newData) {
    _data = newData;
    notifyListeners();
  }

  /// Updates just the branch name.
  ///
  /// This is a convenience method for a common operation.
  void updateBranch(String branch) {
    _data = _data.copyWith(branch: branch);
    notifyListeners();
  }

  /// Updates the git status fields.
  ///
  /// All parameters are optional; only provided values will be updated.
  void updateGitStatus({
    int? uncommittedFiles,
    int? stagedFiles,
    int? commitsAhead,
    int? commitsBehind,
    bool? hasMergeConflict,
  }) {
    _data = _data.copyWith(
      uncommittedFiles: uncommittedFiles,
      stagedFiles: stagedFiles,
      commitsAhead: commitsAhead,
      commitsBehind: commitsBehind,
      hasMergeConflict: hasMergeConflict,
    );
    notifyListeners();
  }

  /// Sets the selected chat.
  ///
  /// The [chat] should be one of the chats in [chats], or null to deselect.
  void selectChat(ChatState? chat) {
    _selectedChat = chat;
    notifyListeners();
  }

  /// Adds a chat to this worktree.
  ///
  /// Optionally selects the newly added chat if [select] is true.
  void addChat(ChatState chat, {bool select = false}) {
    _chats.add(chat);
    if (select) {
      _selectedChat = chat;
    }
    notifyListeners();
  }

  /// Removes a chat from this worktree.
  ///
  /// If the removed chat was selected, the selection is cleared.
  /// The removed chat is disposed to clean up its resources.
  void removeChat(ChatState chat) {
    _chats.remove(chat);
    if (_selectedChat == chat) {
      _selectedChat = null;
    }
    chat.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    // Dispose all ChatState instances before clearing.
    for (final chat in _chats) {
      chat.dispose();
    }
    _chats.clear();
    _selectedChat = null;
    super.dispose();
  }
}
