import 'package:flutter/foundation.dart';

import '../models/output_entry.dart';

/// Context window state information.
///
/// Tracks the current token usage within a chat's context window.
/// All fields are immutable.
@immutable
class ContextInfo {
  /// Number of tokens currently in the context window.
  final int currentTokens;

  /// Maximum token capacity of the context window.
  final int maxTokens;

  /// Creates a [ContextInfo] instance.
  const ContextInfo({
    required this.currentTokens,
    required this.maxTokens,
  });

  /// Creates a [ContextInfo] with default values.
  const ContextInfo.empty()
      : currentTokens = 0,
        maxTokens = 200000;

  /// Creates a copy with the given fields replaced.
  ContextInfo copyWith({
    int? currentTokens,
    int? maxTokens,
  }) {
    return ContextInfo(
      currentTokens: currentTokens ?? this.currentTokens,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  /// Serializes this [ContextInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'currentTokens': currentTokens,
      'maxTokens': maxTokens,
    };
  }

  /// Deserializes a [ContextInfo] from a JSON map.
  factory ContextInfo.fromJson(Map<String, dynamic> json) {
    return ContextInfo(
      currentTokens: json['currentTokens'] as int? ?? 0,
      maxTokens: json['maxTokens'] as int? ?? 200000,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ContextInfo &&
        other.currentTokens == currentTokens &&
        other.maxTokens == maxTokens;
  }

  @override
  int get hashCode => Object.hash(currentTokens, maxTokens);

  @override
  String toString() {
    return 'ContextInfo(currentTokens: $currentTokens, maxTokens: $maxTokens)';
  }
}

/// Metadata for a chat stored in `<chatId>.meta.json`.
///
/// Contains model settings, timestamps, context state, and cumulative usage.
/// All fields are immutable.
@immutable
class ChatMeta {
  /// The model identifier (backend-specific).
  final String model;

  /// Backend type identifier (e.g., "direct", "codex", "nodejs").
  final String backendType;

  /// Whether this chat has started at least once.
  ///
  /// Used to lock the backend selector after the first session starts.
  final bool hasStarted;

  /// The permission mode API name (e.g., "default", "acceptEdits").
  final String permissionMode;

  /// When this chat was created.
  final DateTime createdAt;

  /// When this chat was last active.
  final DateTime lastActiveAt;

  /// Current context window state.
  final ContextInfo context;

  /// Cumulative token usage and cost for this chat.
  final UsageInfo usage;

  /// Per-model usage breakdown for this chat.
  ///
  /// Provides detailed usage statistics for each model used (e.g., Opus, Haiku).
  final List<ModelUsageInfo> modelUsage;

  /// Creates a [ChatMeta] instance.
  const ChatMeta({
    required this.model,
    required this.backendType,
    required this.hasStarted,
    required this.permissionMode,
    required this.createdAt,
    required this.lastActiveAt,
    required this.context,
    required this.usage,
    this.modelUsage = const [],
  });

  /// Creates a [ChatMeta] with default values for a new chat.
  factory ChatMeta.create({
    String model = 'opus',
    String permissionMode = 'default',
    String backendType = 'direct',
    bool hasStarted = false,
  }) {
    final now = DateTime.now();
    return ChatMeta(
      model: model,
      backendType: backendType,
      hasStarted: hasStarted,
      permissionMode: permissionMode,
      createdAt: now,
      lastActiveAt: now,
      context: const ContextInfo.empty(),
      usage: const UsageInfo.zero(),
      modelUsage: const [],
    );
  }

  /// Creates a copy with the given fields replaced.
  ChatMeta copyWith({
    String? model,
    String? backendType,
    bool? hasStarted,
    String? permissionMode,
    DateTime? createdAt,
    DateTime? lastActiveAt,
    ContextInfo? context,
    UsageInfo? usage,
    List<ModelUsageInfo>? modelUsage,
  }) {
    return ChatMeta(
      model: model ?? this.model,
      backendType: backendType ?? this.backendType,
      hasStarted: hasStarted ?? this.hasStarted,
      permissionMode: permissionMode ?? this.permissionMode,
      createdAt: createdAt ?? this.createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      context: context ?? this.context,
      usage: usage ?? this.usage,
      modelUsage: modelUsage ?? this.modelUsage,
    );
  }

  /// Serializes this [ChatMeta] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'backendType': backendType,
      'hasStarted': hasStarted,
      'permissionMode': permissionMode,
      'createdAt': createdAt.toIso8601String(),
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'context': context.toJson(),
      'usage': {
        'inputTokens': usage.inputTokens,
        'outputTokens': usage.outputTokens,
        'cacheReadTokens': usage.cacheReadTokens,
        'cacheCreationTokens': usage.cacheCreationTokens,
        'costUsd': usage.costUsd,
      },
      'modelUsage': modelUsage
          .map((m) => {
                'modelName': m.modelName,
                'inputTokens': m.inputTokens,
                'outputTokens': m.outputTokens,
                'cacheReadTokens': m.cacheReadTokens,
                'cacheCreationTokens': m.cacheCreationTokens,
                'costUsd': m.costUsd,
                'contextWindow': m.contextWindow,
              })
          .toList(),
    };
  }

  /// Deserializes a [ChatMeta] from a JSON map.
  factory ChatMeta.fromJson(Map<String, dynamic> json) {
    final usageJson = json['usage'] as Map<String, dynamic>? ?? {};
    final modelUsageJson = json['modelUsage'] as List<dynamic>? ?? [];

    return ChatMeta(
      model: json['model'] as String? ?? 'opus',
      backendType: json['backendType'] as String? ?? 'direct',
      hasStarted: json['hasStarted'] as bool? ?? false,
      permissionMode: json['permissionMode'] as String? ?? 'default',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      lastActiveAt: json['lastActiveAt'] != null
          ? DateTime.parse(json['lastActiveAt'] as String)
          : DateTime.now(),
      context: json['context'] != null
          ? ContextInfo.fromJson(json['context'] as Map<String, dynamic>)
          : const ContextInfo.empty(),
      usage: UsageInfo(
        inputTokens: usageJson['inputTokens'] as int? ?? 0,
        outputTokens: usageJson['outputTokens'] as int? ?? 0,
        cacheReadTokens: usageJson['cacheReadTokens'] as int? ?? 0,
        cacheCreationTokens: usageJson['cacheCreationTokens'] as int? ?? 0,
        costUsd: (usageJson['costUsd'] as num?)?.toDouble() ?? 0.0,
      ),
      modelUsage: modelUsageJson
          .map((m) {
            final map = m as Map<String, dynamic>;
            return ModelUsageInfo(
              modelName: map['modelName'] as String? ?? '',
              inputTokens: map['inputTokens'] as int? ?? 0,
              outputTokens: map['outputTokens'] as int? ?? 0,
              cacheReadTokens: map['cacheReadTokens'] as int? ?? 0,
              cacheCreationTokens: map['cacheCreationTokens'] as int? ?? 0,
              costUsd: (map['costUsd'] as num?)?.toDouble() ?? 0.0,
              contextWindow: map['contextWindow'] as int? ?? 200000,
            );
          })
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMeta &&
        other.model == model &&
        other.backendType == backendType &&
        other.hasStarted == hasStarted &&
        other.permissionMode == permissionMode &&
        other.createdAt == createdAt &&
        other.lastActiveAt == lastActiveAt &&
        other.context == context &&
        other.usage == usage &&
        listEquals(other.modelUsage, modelUsage);
  }

  @override
  int get hashCode {
    return Object.hash(
      model,
      backendType,
      hasStarted,
      permissionMode,
      createdAt,
      lastActiveAt,
      context,
      usage,
      Object.hashAll(modelUsage),
    );
  }

  @override
  String toString() {
    return 'ChatMeta(model: $model, backendType: $backendType, '
        'hasStarted: $hasStarted, permissionMode: $permissionMode, '
        'createdAt: $createdAt, lastActiveAt: $lastActiveAt)';
  }
}

/// A reference to a chat stored in `projects.json`.
///
/// Contains minimal information needed to identify and resume a chat.
/// All fields are immutable.
@immutable
class ChatReference {
  /// User-visible name for this chat.
  final String name;

  /// Unique identifier for this chat, used for file naming.
  final String chatId;

  /// SDK session ID for session resume, null if never connected or ended.
  final String? lastSessionId;

  /// Creates a [ChatReference] instance.
  const ChatReference({
    required this.name,
    required this.chatId,
    this.lastSessionId,
  });

  /// Creates a copy with the given fields replaced.
  ChatReference copyWith({
    String? name,
    String? chatId,
    String? lastSessionId,
  }) {
    return ChatReference(
      name: name ?? this.name,
      chatId: chatId ?? this.chatId,
      lastSessionId: lastSessionId ?? this.lastSessionId,
    );
  }

  /// Serializes this [ChatReference] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'chatId': chatId,
      'lastSessionId': lastSessionId,
    };
  }

  /// Deserializes a [ChatReference] from a JSON map.
  factory ChatReference.fromJson(Map<String, dynamic> json) {
    return ChatReference(
      name: json['name'] as String? ?? 'Untitled Chat',
      chatId: json['chatId'] as String,
      lastSessionId: json['lastSessionId'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatReference &&
        other.name == name &&
        other.chatId == chatId &&
        other.lastSessionId == lastSessionId;
  }

  @override
  int get hashCode => Object.hash(name, chatId, lastSessionId);

  @override
  String toString() {
    return 'ChatReference(name: $name, chatId: $chatId, '
        'lastSessionId: $lastSessionId)';
  }
}

/// Information about a worktree stored in `projects.json`.
///
/// Contains the worktree type, name, list of chats, and assigned tags.
/// All fields are immutable.
@immutable
class WorktreeInfo {
  /// The type of worktree: "primary" (repo root) or "linked" (git worktree).
  final String type;

  /// Human-readable name (defaults to branch or directory name).
  final String name;

  /// List of chats in this worktree.
  final List<ChatReference> chats;

  /// Tag names assigned to this worktree.
  final List<String> tags;

  /// Creates a [WorktreeInfo] instance.
  const WorktreeInfo({
    required this.type,
    required this.name,
    this.chats = const [],
    this.tags = const [],
  });

  /// Creates a primary worktree with the given name.
  const WorktreeInfo.primary({
    required this.name,
    this.chats = const [],
    this.tags = const [],
  }) : type = 'primary';

  /// Creates a linked worktree with the given name.
  const WorktreeInfo.linked({
    required this.name,
    this.chats = const [],
    this.tags = const [],
  }) : type = 'linked';

  /// Whether this is the primary worktree (repo root).
  bool get isPrimary => type == 'primary';

  /// Whether this is a linked worktree (git worktree).
  bool get isLinked => type == 'linked';

  /// Creates a copy with the given fields replaced.
  WorktreeInfo copyWith({
    String? type,
    String? name,
    List<ChatReference>? chats,
    List<String>? tags,
  }) {
    return WorktreeInfo(
      type: type ?? this.type,
      name: name ?? this.name,
      chats: chats ?? this.chats,
      tags: tags ?? this.tags,
    );
  }

  /// Serializes this [WorktreeInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'name': name,
      'chats': chats.map((c) => c.toJson()).toList(),
      'tags': tags,
    };
  }

  /// Deserializes a [WorktreeInfo] from a JSON map.
  factory WorktreeInfo.fromJson(Map<String, dynamic> json) {
    final chatsList = json['chats'] as List<dynamic>? ?? [];
    final tagsList = json['tags'] as List<dynamic>? ?? [];
    return WorktreeInfo(
      type: json['type'] as String? ?? 'primary',
      name: json['name'] as String? ?? 'main',
      chats: chatsList
          .map((c) => ChatReference.fromJson(c as Map<String, dynamic>))
          .toList(),
      tags: tagsList.cast<String>(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorktreeInfo &&
        other.type == type &&
        other.name == name &&
        listEquals(other.chats, chats) &&
        listEquals(other.tags, tags);
  }

  @override
  int get hashCode => Object.hash(
        type,
        name,
        Object.hashAll(chats),
        Object.hashAll(tags),
      );

  @override
  String toString() {
    return 'WorktreeInfo(type: $type, name: $name, '
        'chats: ${chats.length}, tags: $tags)';
  }
}

/// Information about a project stored in `projects.json`.
///
/// Contains the project ID, name, and map of worktrees.
/// All fields are immutable.
@immutable
class ProjectInfo {
  /// Stable project ID (hash of root path), used for storage directory.
  final String id;

  /// Human-readable name (defaults to directory name, user-editable).
  final String name;

  /// Map of worktree paths to worktree information.
  final Map<String, WorktreeInfo> worktrees;

  /// Default parent directory for new linked worktrees.
  ///
  /// If not set, defaults to `{project_parent_dir}/.{project_name}-wt`.
  /// For example, a project at `/Users/dev/my-app` would default to
  /// `/Users/dev/.my-app-wt`.
  final String? defaultWorktreeRoot;

  /// Creates a [ProjectInfo] instance.
  const ProjectInfo({
    required this.id,
    required this.name,
    this.worktrees = const {},
    this.defaultWorktreeRoot,
  });

  /// Creates a copy with the given fields replaced.
  ProjectInfo copyWith({
    String? id,
    String? name,
    Map<String, WorktreeInfo>? worktrees,
    String? defaultWorktreeRoot,
  }) {
    return ProjectInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      worktrees: worktrees ?? this.worktrees,
      defaultWorktreeRoot: defaultWorktreeRoot ?? this.defaultWorktreeRoot,
    );
  }

  /// Serializes this [ProjectInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'worktrees': worktrees.map((k, v) => MapEntry(k, v.toJson())),
      if (defaultWorktreeRoot != null)
        'defaultWorktreeRoot': defaultWorktreeRoot,
    };
  }

  /// Deserializes a [ProjectInfo] from a JSON map.
  factory ProjectInfo.fromJson(Map<String, dynamic> json) {
    final worktreesJson = json['worktrees'] as Map<String, dynamic>? ?? {};
    return ProjectInfo(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Project',
      worktrees: worktreesJson.map(
        (k, v) => MapEntry(k, WorktreeInfo.fromJson(v as Map<String, dynamic>)),
      ),
      defaultWorktreeRoot: json['defaultWorktreeRoot'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectInfo &&
        other.id == id &&
        other.name == name &&
        mapEquals(other.worktrees, worktrees) &&
        other.defaultWorktreeRoot == defaultWorktreeRoot;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        Object.hashAll(worktrees.entries),
        defaultWorktreeRoot,
      );

  @override
  String toString() {
    return 'ProjectInfo(id: $id, name: $name, worktrees: ${worktrees.length})';
  }
}

/// The root of the `projects.json` file.
///
/// Contains a map of all known projects indexed by their root path.
/// All fields are immutable.
@immutable
class ProjectsIndex {
  /// Map of project root paths to project information.
  final Map<String, ProjectInfo> projects;

  /// Creates a [ProjectsIndex] instance.
  const ProjectsIndex({
    this.projects = const {},
  });

  /// Creates an empty [ProjectsIndex].
  const ProjectsIndex.empty() : projects = const {};

  /// Creates a copy with the given fields replaced.
  ProjectsIndex copyWith({
    Map<String, ProjectInfo>? projects,
  }) {
    return ProjectsIndex(
      projects: projects ?? this.projects,
    );
  }

  /// Serializes this [ProjectsIndex] to a JSON map.
  ///
  /// The format matches the `projects.json` structure where the outer keys
  /// are project root paths and values are project info objects.
  Map<String, dynamic> toJson() {
    return projects.map((k, v) => MapEntry(k, v.toJson()));
  }

  /// Deserializes a [ProjectsIndex] from a JSON map.
  ///
  /// The JSON format has project root paths as keys and project info as values.
  factory ProjectsIndex.fromJson(Map<String, dynamic> json) {
    return ProjectsIndex(
      projects: json.map(
        (k, v) => MapEntry(k, ProjectInfo.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectsIndex && mapEquals(other.projects, projects);
  }

  @override
  int get hashCode => Object.hashAll(projects.entries);

  @override
  String toString() {
    return 'ProjectsIndex(projects: ${projects.length})';
  }
}
