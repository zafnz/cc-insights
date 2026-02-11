import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/foundation.dart';

import '../services/git_service.dart';
import '../services/log_service.dart';
import '../services/runtime_config.dart';
import 'chat.dart';
import 'chat_model.dart';
import 'output_entry.dart';

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

  /// Per-worktree base branch for merge comparisons.
  ///
  /// When set, used for merge/diff operations. Null means "use the project
  /// default". New worktrees inherit the project's defaultBase at creation.
  String? _base;

  /// Whether this worktree is hidden from the default view.
  bool _hidden;

  /// Accumulated cost and token data from closed chats, grouped by backend.
  ///
  /// When a chat is removed via [removeChat], its usage data is captured here
  /// so that the worktree panel can display total costs including closed chats.
  /// Key is the backend label ('claude' or 'codex').
  final Map<String, _ClosedChatUsage> _closedChatUsage = {};

  /// Draft text typed in the welcome screen before any chat is created.
  ///
  /// Preserved when switching between worktrees so users don't lose their
  /// in-progress messages on worktrees that don't have a chat yet.
  String welcomeDraftText = '';

  /// Model explicitly chosen by the user in the welcome screen, or `null`
  /// when the user hasn't overridden the global default yet.
  ChatModel? _welcomeModelOverride;

  /// Backend-specific security configuration for the welcome screen.
  ///
  /// Initialized based on [RuntimeConfig.instance.defaultBackend]:
  /// - Codex: CodexSecurityConfig with workspaceWrite + onRequest
  /// - Claude: ClaudeSecurityConfig with default permission mode
  late sdk.SecurityConfig _welcomeSecurityConfig;

  /// Reasoning effort selected in the welcome screen before chat creation.
  ///
  /// Null means use the model's default reasoning effort.
  sdk.ReasoningEffort? _welcomeReasoningEffort;

  /// Creates a [WorktreeState] with the given initial data.
  ///
  /// [chats] defaults to an empty list if not provided.
  /// [tags] defaults to an empty list if not provided.
  /// [base] is the per-worktree base branch (null = use project default).
  WorktreeState(
    this._data, {
    List<ChatState>? chats,
    List<String>? tags,
    String? base,
    bool hidden = false,
  }) : _chats = chats ?? [],
       _tags = tags ?? [],
       _base = base,
       _hidden = hidden,
       _selectedChat = null {
    // Initialize welcome security config based on default backend
    final defaultBackend = RuntimeConfig.instance.defaultBackend;
    if (defaultBackend == sdk.BackendType.codex) {
      _welcomeSecurityConfig = const sdk.CodexSecurityConfig(
        sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
        approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
      );
    } else {
      _welcomeSecurityConfig = sdk.ClaudeSecurityConfig(
        permissionMode: sdk.PermissionMode.fromString(
          RuntimeConfig.instance.defaultPermissionMode,
        ),
      );
    }
  }

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
  /// Public field for direct access from UI.

  /// Model selection for the welcome screen.
  ///
  /// Returns the user's explicit override if set, otherwise resolves
  /// the global default from [RuntimeConfig].
  ChatModel get welcomeModel =>
      _welcomeModelOverride ??
      ChatModelCatalog.defaultFromComposite(
        RuntimeConfig.instance.defaultModel,
        fallbackBackend: RuntimeConfig.instance.defaultBackend,
      );
  set welcomeModel(ChatModel value) {
    if (_welcomeModelOverride == value) return;

    // If backend changed, update security config to match new backend
    final backendChanged = value.backend != welcomeModel.backend;
    if (backendChanged) {
      if (value.backend == sdk.BackendType.codex) {
        _welcomeSecurityConfig = const sdk.CodexSecurityConfig(
          sandboxMode: sdk.CodexSandboxMode.workspaceWrite,
          approvalPolicy: sdk.CodexApprovalPolicy.onRequest,
        );
      } else {
        _welcomeSecurityConfig = sdk.ClaudeSecurityConfig(
          permissionMode: sdk.PermissionMode.fromString(
            RuntimeConfig.instance.defaultPermissionMode,
          ),
        );
      }
    }

    _welcomeModelOverride = value;
    notifyListeners();
  }

  /// Security configuration for the welcome screen.
  ///
  /// Backend-specific: CodexSecurityConfig for Codex, ClaudeSecurityConfig for Claude.
  sdk.SecurityConfig get welcomeSecurityConfig => _welcomeSecurityConfig;
  set welcomeSecurityConfig(sdk.SecurityConfig value) {
    if (_welcomeSecurityConfig == value) return;
    _welcomeSecurityConfig = value;
    notifyListeners();
  }

  /// Permission mode selection for the welcome screen.
  ///
  /// Derived from [welcomeSecurityConfig] for backward compatibility.
  /// Returns default mode if the security config is not a ClaudeSecurityConfig.
  PermissionMode get welcomePermissionMode {
    if (_welcomeSecurityConfig case sdk.ClaudeSecurityConfig(:final permissionMode)) {
      // Convert sdk.PermissionMode to PermissionMode
      return PermissionMode.fromApiName(permissionMode.value);
    }
    return PermissionMode.defaultMode;
  }

  set welcomePermissionMode(PermissionMode value) {
    // Only update if current config is Claude
    if (_welcomeSecurityConfig is sdk.ClaudeSecurityConfig) {
      final sdkMode = sdk.PermissionMode.fromString(value.apiName);
      _welcomeSecurityConfig = sdk.ClaudeSecurityConfig(permissionMode: sdkMode);
      notifyListeners();
    }
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

  /// Whether this worktree is hidden from the default view.
  bool get hidden => _hidden;

  /// Sets the hidden state of this worktree.
  void setHidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    notifyListeners();
  }

  /// The per-worktree base branch, or null to use project default.
  String? get base => _base;

  /// Sets the per-worktree base branch.
  ///
  /// Pass null to clear and revert to the project default.
  /// Does not notify listeners if the value hasn't changed.
  void setBase(String? value) {
    if (_base == value) return;
    _base = value;
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
    LogService.instance.notice('Chat', 'Chat created: "${chat.data.name}" in ${_data.branch}');
    _chats.add(chat);
    if (select) {
      _selectedChat = chat;
    }
    notifyListeners();
  }

  /// Removes a chat from this worktree.
  ///
  /// Before disposing, captures the chat's cost/token data into
  /// [_closedChatUsage] so worktree-level aggregation remains accurate.
  /// If the removed chat was selected, the selection is cleared.
  void removeChat(ChatState chat) {
    // Capture cost data before disposing
    final usage = chat.cumulativeUsage;
    if (usage.totalTokens > 0 || usage.costUsd > 0) {
      final backend = chat.backendLabel;
      final existing = _closedChatUsage[backend];
      if (existing != null) {
        _closedChatUsage[backend] = _ClosedChatUsage(
          totalTokens: existing.totalTokens + usage.totalTokens,
          costUsd: existing.costUsd + usage.costUsd,
        );
      } else {
        _closedChatUsage[backend] = _ClosedChatUsage(
          totalTokens: usage.totalTokens,
          costUsd: usage.costUsd,
        );
      }
    }

    _chats.remove(chat);
    if (_selectedChat == chat) {
      _selectedChat = null;
    }
    chat.dispose();
    notifyListeners();
  }

  /// Returns aggregated cost and token totals per backend, combining
  /// active chats and closed chats.
  ///
  /// Returns a map of backend label ('claude' or 'codex') to
  /// (totalTokens, costUsd).
  Map<String, ({int totalTokens, double costUsd})> get costPerBackend {
    final result = <String, ({int totalTokens, double costUsd})>{};

    // Start with closed chat data
    for (final entry in _closedChatUsage.entries) {
      result[entry.key] = (
        totalTokens: entry.value.totalTokens,
        costUsd: entry.value.costUsd,
      );
    }

    // Add active chat data (skip chats with no usage)
    for (final chat in _chats) {
      final usage = chat.cumulativeUsage;
      if (usage.totalTokens == 0 && usage.costUsd == 0) continue;
      final backend = chat.backendLabel;
      final existing = result[backend];
      if (existing != null) {
        result[backend] = (
          totalTokens: existing.totalTokens + usage.totalTokens,
          costUsd: existing.costUsd + usage.costUsd,
        );
      } else {
        result[backend] = (
          totalTokens: usage.totalTokens,
          costUsd: usage.costUsd,
        );
      }
    }

    return result;
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

/// Accumulated cost/token data from a closed chat.
class _ClosedChatUsage {
  final int totalTokens;
  final double costUsd;

  const _ClosedChatUsage({
    required this.totalTokens,
    required this.costUsd,
  });
}
