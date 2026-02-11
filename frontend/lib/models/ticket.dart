import 'package:flutter/foundation.dart';

/// The current status of a ticket.
enum TicketStatus {
  /// Ticket is being drafted and is not yet ready for work.
  draft,

  /// Ticket is ready to be started.
  ready,

  /// Ticket is actively being worked on.
  active,

  /// Ticket is blocked by dependencies or external factors.
  blocked,

  /// Ticket needs user input or clarification.
  needsInput,

  /// Ticket is in review/testing.
  inReview,

  /// Ticket work is completed.
  completed,

  /// Ticket work was cancelled.
  cancelled,

  /// Ticket has been split into subtasks.
  split;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case draft:
        return 'Draft';
      case ready:
        return 'Ready';
      case active:
        return 'Active';
      case blocked:
        return 'Blocked';
      case needsInput:
        return 'Needs Input';
      case inReview:
        return 'In Review';
      case completed:
        return 'Completed';
      case cancelled:
        return 'Cancelled';
      case split:
        return 'Split';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketStatus] from a JSON string.
  static TicketStatus fromJson(String json) {
    return TicketStatus.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketStatus: $json'),
    );
  }
}

/// The kind/type of work for a ticket.
enum TicketKind {
  /// New feature implementation.
  feature,

  /// Bug fix.
  bugfix,

  /// Research or investigation.
  research,

  /// Split from another ticket.
  split,

  /// Question or clarification request.
  question,

  /// Test implementation or updates.
  test,

  /// Documentation work.
  docs,

  /// General maintenance or chores.
  chore;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case feature:
        return 'Feature';
      case bugfix:
        return 'Bug Fix';
      case research:
        return 'Research';
      case split:
        return 'Split';
      case question:
        return 'Question';
      case test:
        return 'Test';
      case docs:
        return 'Docs';
      case chore:
        return 'Chore';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketKind] from a JSON string.
  static TicketKind fromJson(String json) {
    return TicketKind.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketKind: $json'),
    );
  }
}

/// The priority level of a ticket.
enum TicketPriority {
  /// Low priority.
  low,

  /// Medium priority.
  medium,

  /// High priority.
  high,

  /// Critical priority.
  critical;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case low:
        return 'Low';
      case medium:
        return 'Medium';
      case high:
        return 'High';
      case critical:
        return 'Critical';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketPriority] from a JSON string.
  static TicketPriority fromJson(String json) {
    return TicketPriority.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketPriority: $json'),
    );
  }
}

/// The estimated effort/size of a ticket.
enum TicketEffort {
  /// Small effort (hours).
  small,

  /// Medium effort (days).
  medium,

  /// Large effort (weeks).
  large;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case small:
        return 'Small';
      case medium:
        return 'Medium';
      case large:
        return 'Large';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketEffort] from a JSON string.
  static TicketEffort fromJson(String json) {
    return TicketEffort.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketEffort: $json'),
    );
  }
}

/// The view mode for displaying tickets.
enum TicketViewMode {
  /// Display tickets as a list.
  list,

  /// Display tickets as a dependency graph.
  graph;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case list:
        return 'List';
      case graph:
        return 'Graph';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketViewMode] from a JSON string.
  static TicketViewMode fromJson(String json) {
    return TicketViewMode.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketViewMode: $json'),
    );
  }
}

/// The grouping method for ticket lists.
enum TicketGroupBy {
  /// Group by category.
  category,

  /// Group by status.
  status,

  /// Group by kind.
  kind,

  /// Group by priority.
  priority;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case category:
        return 'Category';
      case status:
        return 'Status';
      case kind:
        return 'Kind';
      case priority:
        return 'Priority';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketGroupBy] from a JSON string.
  static TicketGroupBy fromJson(String json) {
    return TicketGroupBy.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketGroupBy: $json'),
    );
  }
}

/// A worktree linked to a ticket.
@immutable
class LinkedWorktree {
  /// The absolute path to the worktree root directory.
  final String worktreeRoot;

  /// The branch name associated with this worktree (if any).
  final String? branch;

  /// Creates a [LinkedWorktree] instance.
  const LinkedWorktree({
    required this.worktreeRoot,
    this.branch,
  });

  /// Serializes this [LinkedWorktree] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'worktreeRoot': worktreeRoot,
      if (branch != null) 'branch': branch,
    };
  }

  /// Deserializes a [LinkedWorktree] from a JSON map.
  factory LinkedWorktree.fromJson(Map<String, dynamic> json) {
    return LinkedWorktree(
      worktreeRoot: json['worktreeRoot'] as String? ?? '',
      branch: json['branch'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LinkedWorktree &&
        other.worktreeRoot == worktreeRoot &&
        other.branch == branch;
  }

  @override
  int get hashCode => Object.hash(worktreeRoot, branch);

  @override
  String toString() {
    return 'LinkedWorktree(worktreeRoot: $worktreeRoot, branch: $branch)';
  }
}

/// A chat linked to a ticket.
@immutable
class LinkedChat {
  /// The unique identifier of the chat.
  final String chatId;

  /// The name of the chat.
  final String chatName;

  /// The absolute path to the worktree containing this chat.
  final String worktreeRoot;

  /// Creates a [LinkedChat] instance.
  const LinkedChat({
    required this.chatId,
    required this.chatName,
    required this.worktreeRoot,
  });

  /// Serializes this [LinkedChat] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'chatName': chatName,
      'worktreeRoot': worktreeRoot,
    };
  }

  /// Deserializes a [LinkedChat] from a JSON map.
  factory LinkedChat.fromJson(Map<String, dynamic> json) {
    return LinkedChat(
      chatId: json['chatId'] as String? ?? '',
      chatName: json['chatName'] as String? ?? '',
      worktreeRoot: json['worktreeRoot'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LinkedChat &&
        other.chatId == chatId &&
        other.chatName == chatName &&
        other.worktreeRoot == worktreeRoot;
  }

  @override
  int get hashCode => Object.hash(chatId, chatName, worktreeRoot);

  @override
  String toString() {
    return 'LinkedChat(chatId: $chatId, chatName: $chatName, '
        'worktreeRoot: $worktreeRoot)';
  }
}

/// Cost and performance statistics for a ticket.
@immutable
class TicketCostStats {
  /// Total tokens consumed across all chats.
  final int totalTokens;

  /// Total cost in USD across all chats.
  final double totalCost;

  /// Total time Claude spent working (milliseconds).
  final int agentTimeMs;

  /// Total time spent waiting for user input (milliseconds).
  final int waitingTimeMs;

  /// Creates a [TicketCostStats] instance.
  const TicketCostStats({
    required this.totalTokens,
    required this.totalCost,
    required this.agentTimeMs,
    required this.waitingTimeMs,
  });

  /// Serializes this [TicketCostStats] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'totalTokens': totalTokens,
      'totalCost': totalCost,
      'agentTimeMs': agentTimeMs,
      'waitingTimeMs': waitingTimeMs,
    };
  }

  /// Deserializes a [TicketCostStats] from a JSON map.
  factory TicketCostStats.fromJson(Map<String, dynamic> json) {
    return TicketCostStats(
      totalTokens: json['totalTokens'] as int? ?? 0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
      agentTimeMs: json['agentTimeMs'] as int? ?? 0,
      waitingTimeMs: json['waitingTimeMs'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketCostStats &&
        other.totalTokens == totalTokens &&
        other.totalCost == totalCost &&
        other.agentTimeMs == agentTimeMs &&
        other.waitingTimeMs == waitingTimeMs;
  }

  @override
  int get hashCode => Object.hash(
        totalTokens,
        totalCost,
        agentTimeMs,
        waitingTimeMs,
      );

  @override
  String toString() {
    return 'TicketCostStats(totalTokens: $totalTokens, totalCost: $totalCost, '
        'agentTimeMs: $agentTimeMs, waitingTimeMs: $waitingTimeMs)';
  }
}

/// A project management ticket.
///
/// Represents a unit of work that can be tracked through completion. Tickets
/// can have dependencies, linked worktrees/chats, and accumulated cost metrics.
@immutable
class TicketData {
  /// Unique numeric identifier for this ticket.
  final int id;

  /// Short title describing the ticket.
  final String title;

  /// Detailed description of the ticket work.
  final String description;

  /// Current status of the ticket.
  final TicketStatus status;

  /// Kind/type of work this ticket represents.
  final TicketKind kind;

  /// Priority level of this ticket.
  final TicketPriority priority;

  /// Estimated effort/size of this ticket.
  final TicketEffort effort;

  /// Optional category for grouping tickets.
  final String? category;

  /// Tags for flexible categorization.
  final Set<String> tags;

  /// IDs of tickets this ticket depends on.
  final List<int> dependsOn;

  /// Worktrees linked to this ticket.
  final List<LinkedWorktree> linkedWorktrees;

  /// Chats linked to this ticket.
  final List<LinkedChat> linkedChats;

  /// ID of the conversation that created this ticket (if any).
  final String? sourceConversationId;

  /// Accumulated cost and performance statistics (if any).
  final TicketCostStats? costStats;

  /// When this ticket was created.
  final DateTime createdAt;

  /// When this ticket was last updated.
  final DateTime updatedAt;

  /// Creates a [TicketData] instance.
  const TicketData({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.kind,
    required this.priority,
    required this.effort,
    this.category,
    this.tags = const {},
    this.dependsOn = const [],
    this.linkedWorktrees = const [],
    this.linkedChats = const [],
    this.sourceConversationId,
    this.costStats,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Formatted display ID (e.g., "TKT-001").
  String get displayId => 'TKT-${id.toString().padLeft(3, '0')}';

  /// Whether this ticket is in a terminal state.
  bool get isTerminal => status == TicketStatus.completed ||
      status == TicketStatus.cancelled ||
      status == TicketStatus.split;

  /// Creates a copy with the given fields replaced.
  TicketData copyWith({
    int? id,
    String? title,
    String? description,
    TicketStatus? status,
    TicketKind? kind,
    TicketPriority? priority,
    TicketEffort? effort,
    String? category,
    bool clearCategory = false,
    Set<String>? tags,
    List<int>? dependsOn,
    List<LinkedWorktree>? linkedWorktrees,
    List<LinkedChat>? linkedChats,
    String? sourceConversationId,
    bool clearSourceConversationId = false,
    TicketCostStats? costStats,
    bool clearCostStats = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TicketData(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      kind: kind ?? this.kind,
      priority: priority ?? this.priority,
      effort: effort ?? this.effort,
      category: clearCategory ? null : (category ?? this.category),
      tags: tags ?? this.tags,
      dependsOn: dependsOn ?? this.dependsOn,
      linkedWorktrees: linkedWorktrees ?? this.linkedWorktrees,
      linkedChats: linkedChats ?? this.linkedChats,
      sourceConversationId: clearSourceConversationId
          ? null
          : (sourceConversationId ?? this.sourceConversationId),
      costStats: clearCostStats ? null : (costStats ?? this.costStats),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Serializes this [TicketData] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'status': status.jsonValue,
      'kind': kind.jsonValue,
      'priority': priority.jsonValue,
      'effort': effort.jsonValue,
      if (category != null) 'category': category,
      if (tags.isNotEmpty) 'tags': tags.toList(),
      if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
      if (linkedWorktrees.isNotEmpty)
        'linkedWorktrees': linkedWorktrees.map((w) => w.toJson()).toList(),
      if (linkedChats.isNotEmpty)
        'linkedChats': linkedChats.map((c) => c.toJson()).toList(),
      if (sourceConversationId != null)
        'sourceConversationId': sourceConversationId,
      if (costStats != null) 'costStats': costStats!.toJson(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Deserializes a [TicketData] from a JSON map.
  factory TicketData.fromJson(Map<String, dynamic> json) {
    final tagsList = json['tags'] as List<dynamic>? ?? [];
    final dependsOnList = json['dependsOn'] as List<dynamic>? ?? [];
    final linkedWorktreesList =
        json['linkedWorktrees'] as List<dynamic>? ?? [];
    final linkedChatsList = json['linkedChats'] as List<dynamic>? ?? [];
    final costStatsJson = json['costStats'] as Map<String, dynamic>?;

    final now = DateTime.now();

    return TicketData(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: TicketStatus.fromJson(json['status'] as String? ?? 'draft'),
      kind: TicketKind.fromJson(json['kind'] as String? ?? 'feature'),
      priority:
          TicketPriority.fromJson(json['priority'] as String? ?? 'medium'),
      effort: TicketEffort.fromJson(json['effort'] as String? ?? 'medium'),
      category: json['category'] as String?,
      tags: Set<String>.from(tagsList.map((e) => e.toString())),
      dependsOn: dependsOnList.map((e) => e as int).toList(),
      linkedWorktrees: linkedWorktreesList
          .map((w) => LinkedWorktree.fromJson(w as Map<String, dynamic>))
          .toList(),
      linkedChats: linkedChatsList
          .map((c) => LinkedChat.fromJson(c as Map<String, dynamic>))
          .toList(),
      sourceConversationId: json['sourceConversationId'] as String?,
      costStats:
          costStatsJson != null ? TicketCostStats.fromJson(costStatsJson) : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : now,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : now,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketData &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.status == status &&
        other.kind == kind &&
        other.priority == priority &&
        other.effort == effort &&
        other.category == category &&
        setEquals(other.tags, tags) &&
        listEquals(other.dependsOn, dependsOn) &&
        listEquals(other.linkedWorktrees, linkedWorktrees) &&
        listEquals(other.linkedChats, linkedChats) &&
        other.sourceConversationId == sourceConversationId &&
        other.costStats == costStats &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      description,
      status,
      kind,
      priority,
      effort,
      category,
      Object.hashAll(tags),
      Object.hashAll(dependsOn),
      Object.hashAll(linkedWorktrees),
      Object.hashAll(linkedChats),
      sourceConversationId,
      costStats,
      createdAt,
      updatedAt,
    );
  }

  @override
  String toString() {
    return 'TicketData(id: $id, title: $title, status: $status, '
        'kind: $kind, priority: $priority, effort: $effort)';
  }
}

/// A proposal for a ticket, typically from an agent bulk-creation workflow.
///
/// Proposals are staging objects that get converted into [TicketData] with
/// status [TicketStatus.draft] during bulk review. Dependencies are expressed
/// as indices into the proposal array rather than ticket IDs, since IDs are
/// not yet assigned.
@immutable
class TicketProposal {
  /// Short title describing the proposed ticket.
  final String title;

  /// Detailed description of the proposed work.
  final String description;

  /// Kind/type of work this ticket represents.
  final TicketKind kind;

  /// Priority level of this ticket.
  final TicketPriority priority;

  /// Estimated effort/size of this ticket.
  final TicketEffort effort;

  /// Optional category for grouping.
  final String? category;

  /// Tags for flexible categorization.
  final Set<String> tags;

  /// Indices into the proposal array for dependencies.
  ///
  /// These are converted to actual ticket IDs when the proposals are created.
  /// Out-of-range indices are silently dropped.
  final List<int> dependsOnIndices;

  /// Creates a [TicketProposal] instance.
  const TicketProposal({
    required this.title,
    this.description = '',
    this.kind = TicketKind.feature,
    this.priority = TicketPriority.medium,
    this.effort = TicketEffort.medium,
    this.category,
    this.tags = const {},
    this.dependsOnIndices = const [],
  });

  /// Deserializes a [TicketProposal] from a JSON map.
  factory TicketProposal.fromJson(Map<String, dynamic> json) {
    final tagsList = json['tags'] as List<dynamic>? ?? [];
    final depsList = json['dependsOnIndices'] as List<dynamic>? ?? [];

    return TicketProposal(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      kind: TicketKind.fromJson(json['kind'] as String? ?? 'feature'),
      priority: TicketPriority.fromJson(json['priority'] as String? ?? 'medium'),
      effort: TicketEffort.fromJson(json['effort'] as String? ?? 'medium'),
      category: json['category'] as String?,
      tags: Set<String>.from(tagsList.map((e) => e.toString())),
      dependsOnIndices: depsList.map((e) => e as int).toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketProposal &&
        other.title == title &&
        other.description == description &&
        other.kind == kind &&
        other.priority == priority &&
        other.effort == effort &&
        other.category == category &&
        setEquals(other.tags, tags) &&
        listEquals(other.dependsOnIndices, dependsOnIndices);
  }

  @override
  int get hashCode => Object.hash(
        title,
        description,
        kind,
        priority,
        effort,
        category,
        Object.hashAll(tags),
        Object.hashAll(dependsOnIndices),
      );

  @override
  String toString() {
    return 'TicketProposal(title: $title, kind: $kind, '
        'priority: $priority, effort: $effort)';
  }
}
