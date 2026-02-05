import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/foundation.dart';

import '../services/git_service.dart';
import '../services/runtime_config.dart';
import 'chat.dart';
import 'chat_model.dart';

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

  /// The type of conflict operation in progress (merge or rebase), or null
  /// if no conflict is in progress.
  final MergeOperationType? conflictOperation;

  /// The upstream branch name (e.g., "origin/main"), or null if none.
  final String? upstreamBranch;

  /// Number of commits this branch has that are not in the base branch.
  final int commitsAheadOfMain;

  /// Number of commits the base branch has that are not in this branch.
  final int commitsBehindMain;

  /// Whether the base comparison target is a remote ref (e.g. origin/main)
  /// rather than a local ref (e.g. main).
  ///
  /// When true, the UI shows a globe icon; when false, a house icon.
  final bool isRemoteBase;

  /// The exact ref name used for the base comparison (e.g. "main" or
  /// "origin/main"). Used in tooltips to show the comparison target.
  final String? baseRef;

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
    this.conflictOperation,
    this.upstreamBranch,
    this.commitsAheadOfMain = 0,
    this.commitsBehindMain = 0,
    this.isRemoteBase = false,
    this.baseRef,
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
    MergeOperationType? conflictOperation,
    bool clearConflictOperation = false,
    String? upstreamBranch,
    bool clearUpstreamBranch = false,
    int? commitsAheadOfMain,
    int? commitsBehindMain,
    bool? isRemoteBase,
    String? baseRef,
    bool clearBaseRef = false,
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
      conflictOperation: clearConflictOperation
          ? null
          : (conflictOperation ?? this.conflictOperation),
      upstreamBranch:
          clearUpstreamBranch ? null : (upstreamBranch ?? this.upstreamBranch),
      commitsAheadOfMain: commitsAheadOfMain ?? this.commitsAheadOfMain,
      commitsBehindMain: commitsBehindMain ?? this.commitsBehindMain,
      isRemoteBase: isRemoteBase ?? this.isRemoteBase,
      baseRef: clearBaseRef ? null : (baseRef ?? this.baseRef),
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
        other.hasMergeConflict == hasMergeConflict &&
        other.conflictOperation == conflictOperation &&
        other.upstreamBranch == upstreamBranch &&
        other.commitsAheadOfMain == commitsAheadOfMain &&
        other.commitsBehindMain == commitsBehindMain &&
        other.isRemoteBase == isRemoteBase &&
        other.baseRef == baseRef;
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
      conflictOperation,
      upstreamBranch,
      commitsAheadOfMain,
      commitsBehindMain,
      isRemoteBase,
      baseRef,
    );
  }

  @override
  String toString() {
    return 'WorktreeData(worktreeRoot: $worktreeRoot, isPrimary: $isPrimary, '
        'branch: $branch, uncommittedFiles: $uncommittedFiles, '
        'stagedFiles: $stagedFiles, commitsAhead: $commitsAhead, '
        'commitsBehind: $commitsBehind, hasMergeConflict: $hasMergeConflict, '
        'conflictOperation: $conflictOperation, '
        'upstreamBranch: $upstreamBranch, '
        'commitsAheadOfMain: $commitsAheadOfMain, '
        'commitsBehindMain: $commitsBehindMain, '
        'isRemoteBase: $isRemoteBase, '
        'baseRef: $baseRef)';
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

  /// Tag names assigned to this worktree.
  List<String> _tags;

  /// Per-worktree base branch override.
  ///
  /// When set, overrides the project-level `defaultBase` for merge
  /// comparisons. Null means "use the project default".
  String? _baseOverride;

  /// Draft text typed in the welcome screen before any chat is created.
  ///
  /// Preserved when switching between worktrees so users don't lose their
  /// in-progress messages on worktrees that don't have a chat yet.
  String _welcomeDraftText = '';

  /// Model selected in the welcome screen before any chat is created.
  ///
  /// Initialized from [RuntimeConfig.instance.defaultModel].
  ChatModel _welcomeModel = ChatModelCatalog.defaultForBackend(
    RuntimeConfig.instance.defaultBackend,
    RuntimeConfig.instance.defaultModel,
  );

  /// Permission mode selected in the welcome screen before chat creation.
  ///
  /// Initialized from [RuntimeConfig.instance.defaultPermissionMode].
  PermissionMode _welcomePermissionMode = PermissionMode.fromApiName(
    RuntimeConfig.instance.defaultPermissionMode,
  );

  /// Reasoning effort selected in the welcome screen before chat creation.
  ///
  /// Null means use the model's default reasoning effort.
  sdk.ReasoningEffort? _welcomeReasoningEffort;

  /// Creates a [WorktreeState] with the given initial data.
  ///
  /// [chats] defaults to an empty list if not provided.
  /// [tags] defaults to an empty list if not provided.
  /// [baseOverride] is the per-worktree base branch override (null = use
  /// project default).
  WorktreeState(
    this._data, {
    List<ChatState>? chats,
    List<String>? tags,
    String? baseOverride,
  }) : _chats = chats ?? [],
       _tags = tags ?? [],
       _baseOverride = baseOverride,
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

  /// Draft text for the welcome screen (before any chat is created).
  String get welcomeDraftText => _welcomeDraftText;
  set welcomeDraftText(String value) => _welcomeDraftText = value;

  /// Model selection for the welcome screen.
  ChatModel get welcomeModel => _welcomeModel;
  set welcomeModel(ChatModel value) {
    if (_welcomeModel == value) return;
    _welcomeModel = value;
    notifyListeners();
  }

  /// Permission mode selection for the welcome screen.
  PermissionMode get welcomePermissionMode => _welcomePermissionMode;
  set welcomePermissionMode(PermissionMode value) {
    if (_welcomePermissionMode == value) return;
    _welcomePermissionMode = value;
    notifyListeners();
  }

  /// Reasoning effort selection for the welcome screen.
  sdk.ReasoningEffort? get welcomeReasoningEffort => _welcomeReasoningEffort;
  set welcomeReasoningEffort(sdk.ReasoningEffort? value) {
    if (_welcomeReasoningEffort == value) return;
    _welcomeReasoningEffort = value;
    notifyListeners();
  }

  /// The tag names assigned to this worktree.
  List<String> get tags => List.unmodifiable(_tags);

  /// Replaces all assigned tags.
  void setTags(List<String> tags) {
    _tags = List.of(tags);
    notifyListeners();
  }

  /// Toggles a tag: adds it if missing, removes it if present.
  void toggleTag(String tagName) {
    if (_tags.contains(tagName)) {
      _tags.remove(tagName);
    } else {
      _tags.add(tagName);
    }
    notifyListeners();
  }

  /// The per-worktree base branch override, or null to use project default.
  String? get baseOverride => _baseOverride;

  /// Sets the per-worktree base branch override.
  ///
  /// Pass null to clear the override and revert to the project default.
  /// Does not notify listeners if the value hasn't changed.
  void setBaseOverride(String? value) {
    if (_baseOverride == value) return;
    _baseOverride = value;
    notifyListeners();
  }

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
