import 'package:flutter/foundation.dart';

/// Whether the author is a human user or an AI agent.
enum AuthorType {
  /// A human user.
  user,

  /// An AI agent.
  agent;

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes an [AuthorType] from a JSON string.
  static AuthorType fromJson(String json) {
    return AuthorType.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid AuthorType: $json'),
    );
  }
}

/// The type of activity event recorded on a ticket timeline.
enum ActivityEventType {
  /// A tag was added to the ticket.
  tagAdded,

  /// A tag was removed from the ticket.
  tagRemoved,

  /// A worktree was linked to the ticket.
  worktreeLinked,

  /// A worktree was unlinked from the ticket.
  worktreeUnlinked,

  /// A chat was linked to the ticket.
  chatLinked,

  /// A chat was unlinked from the ticket.
  chatUnlinked,

  /// A dependency was added to the ticket.
  dependencyAdded,

  /// A dependency was removed from the ticket.
  dependencyRemoved,

  /// The ticket was closed.
  closed,

  /// The ticket was reopened.
  reopened,

  /// The ticket title was edited.
  titleEdited,

  /// The ticket body was edited.
  bodyEdited;

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes an [ActivityEventType] from a JSON string.
  static ActivityEventType fromJson(String json) {
    return ActivityEventType.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid ActivityEventType: $json'),
    );
  }
}

/// A chronological activity event recorded on a ticket timeline.
///
/// Every mutation to a ticket generates an activity event. Events are stored
/// chronologically and displayed on the timeline between comments.
@immutable
class ActivityEvent {
  /// Unique identifier (uuid).
  final String id;

  /// The type of activity that occurred.
  final ActivityEventType type;

  /// Who performed the action (e.g. "zaf", "agent auth-refactor").
  final String actor;

  /// Whether the actor is a user or agent.
  final AuthorType actorType;

  /// When the event occurred.
  final DateTime timestamp;

  /// Type-specific payload data.
  final Map<String, dynamic> data;

  /// Creates an [ActivityEvent] instance.
  const ActivityEvent({
    required this.id,
    required this.type,
    required this.actor,
    required this.actorType,
    required this.timestamp,
    this.data = const {},
  });

  /// Serializes this [ActivityEvent] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.jsonValue,
      'actor': actor,
      'actorType': actorType.jsonValue,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (data.isNotEmpty) 'data': data,
    };
  }

  /// Deserializes an [ActivityEvent] from a JSON map.
  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    final dataMap = json['data'] as Map<String, dynamic>? ?? {};

    return ActivityEvent(
      id: json['id'] as String? ?? '',
      type: ActivityEventType.fromJson(json['type'] as String? ?? 'closed'),
      actor: json['actor'] as String? ?? '',
      actorType: AuthorType.fromJson(json['actorType'] as String? ?? 'user'),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      data: dataMap,
    );
  }

  /// Creates a copy with the given fields replaced.
  ActivityEvent copyWith({
    String? id,
    ActivityEventType? type,
    String? actor,
    AuthorType? actorType,
    DateTime? timestamp,
    Map<String, dynamic>? data,
  }) {
    return ActivityEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      actorType: actorType ?? this.actorType,
      timestamp: timestamp ?? this.timestamp,
      data: data ?? this.data,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ActivityEvent &&
        other.id == id &&
        other.type == type &&
        other.actor == actor &&
        other.actorType == actorType &&
        other.timestamp == timestamp &&
        mapEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        actor,
        actorType,
        timestamp,
        Object.hashAll(data.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() {
    return 'ActivityEvent(id: $id, type: $type, actor: $actor, '
        'actorType: $actorType)';
  }
}

/// An image attached to a ticket body or comment.
@immutable
class TicketImage {
  /// Unique identifier (uuid).
  final String id;

  /// Original file name.
  final String fileName;

  /// Path relative to the project data directory.
  final String relativePath;

  /// MIME type (e.g. "image/png").
  final String mimeType;

  /// When the image was attached.
  final DateTime createdAt;

  /// Creates a [TicketImage] instance.
  const TicketImage({
    required this.id,
    required this.fileName,
    required this.relativePath,
    required this.mimeType,
    required this.createdAt,
  });

  /// Serializes this [TicketImage] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'relativePath': relativePath,
      'mimeType': mimeType,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  /// Deserializes a [TicketImage] from a JSON map.
  factory TicketImage.fromJson(Map<String, dynamic> json) {
    return TicketImage(
      id: json['id'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      relativePath: json['relativePath'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketImage &&
        other.id == id &&
        other.fileName == fileName &&
        other.relativePath == relativePath &&
        other.mimeType == mimeType &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, fileName, relativePath, mimeType, createdAt);

  @override
  String toString() {
    return 'TicketImage(id: $id, fileName: $fileName, '
        'relativePath: $relativePath, mimeType: $mimeType)';
  }
}

/// A comment entry attached to a ticket.
///
/// Comments support rich text (markdown) and image attachments. Each comment
/// has proper author attribution indicating whether it came from a user or
/// an AI agent.
@immutable
class TicketComment {
  /// Unique identifier (uuid).
  final String id;

  /// Markdown content of the comment.
  final String text;

  /// Who wrote this comment (e.g. "zaf", "agent auth-refactor").
  final String author;

  /// Whether the author is a user or agent.
  final AuthorType authorType;

  /// Images attached to this comment.
  final List<TicketImage> images;

  /// When this comment was created.
  final DateTime createdAt;

  /// When this comment was last edited (null if never edited).
  final DateTime? updatedAt;

  /// Creates a [TicketComment] instance.
  const TicketComment({
    required this.id,
    required this.text,
    required this.author,
    required this.authorType,
    this.images = const [],
    required this.createdAt,
    this.updatedAt,
  });

  /// Serializes this [TicketComment] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'author': author,
      'authorType': authorType.jsonValue,
      if (images.isNotEmpty)
        'images': images.map((i) => i.toJson()).toList(),
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (updatedAt != null)
        'updatedAt': updatedAt!.toUtc().toIso8601String(),
    };
  }

  /// Deserializes a [TicketComment] from a JSON map.
  factory TicketComment.fromJson(Map<String, dynamic> json) {
    final imagesList = json['images'] as List<dynamic>? ?? [];

    return TicketComment(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      author: json['author'] as String? ?? '',
      authorType: AuthorType.fromJson(
        json['authorType'] as String? ?? 'user',
      ),
      images: imagesList
          .map((i) => TicketImage.fromJson(i as Map<String, dynamic>))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// Creates a copy with the given fields replaced.
  TicketComment copyWith({
    String? id,
    String? text,
    String? author,
    AuthorType? authorType,
    List<TicketImage>? images,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return TicketComment(
      id: id ?? this.id,
      text: text ?? this.text,
      author: author ?? this.author,
      authorType: authorType ?? this.authorType,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketComment &&
        other.id == id &&
        other.text == text &&
        other.author == author &&
        other.authorType == authorType &&
        listEquals(other.images, images) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        text,
        author,
        authorType,
        Object.hashAll(images),
        createdAt,
        updatedAt,
      );

  @override
  String toString() {
    return 'TicketComment(id: $id, author: $author, '
        'authorType: $authorType)';
  }
}

/// A tag definition in the project-level tag registry.
///
/// Tags are free-form strings used for categorization. The registry stores
/// known tags for autocomplete suggestions and optional colour overrides.
@immutable
class TagDefinition {
  /// The tag text (always lowercase).
  final String name;

  /// Optional hex colour override (e.g. "#ef5350").
  final String? color;

  /// Creates a [TagDefinition] instance.
  ///
  /// The [name] is normalized to lowercase.
  TagDefinition({required String name, this.color})
      : name = name.toLowerCase();

  /// Serializes this [TagDefinition] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (color != null) 'color': color,
    };
  }

  /// Deserializes a [TagDefinition] from a JSON map.
  factory TagDefinition.fromJson(Map<String, dynamic> json) {
    return TagDefinition(
      name: json['name'] as String? ?? '',
      color: json['color'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TagDefinition &&
        other.name == name &&
        other.color == color;
  }

  @override
  int get hashCode => Object.hash(name, color);

  @override
  String toString() {
    return 'TagDefinition(name: $name, color: $color)';
  }
}

/// The sort order for ticket lists.
enum TicketSortOrder {
  /// Sort by creation date, newest first.
  newest,

  /// Sort by creation date, oldest first.
  oldest,

  /// Sort by last update date, most recent first.
  recentlyUpdated;

  /// User-friendly display label.
  String get label {
    switch (this) {
      case newest:
        return 'Newest';
      case oldest:
        return 'Oldest';
      case recentlyUpdated:
        return 'Recently updated';
    }
  }

  /// JSON serialization value.
  String get jsonValue => name;

  /// Deserializes a [TicketSortOrder] from a JSON string.
  static TicketSortOrder fromJson(String json) {
    return TicketSortOrder.values.firstWhere(
      (e) => e.name == json,
      orElse: () => throw ArgumentError('Invalid TicketSortOrder: $json'),
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

/// A worktree linked to a ticket.
@immutable
class LinkedWorktree {
  /// The absolute path to the worktree root directory.
  final String worktreeRoot;

  /// The branch name associated with this worktree (if any).
  final String? branch;

  /// Creates a [LinkedWorktree] instance.
  const LinkedWorktree({required this.worktreeRoot, this.branch});

  /// Serializes this [LinkedWorktree] to a JSON map.
  Map<String, dynamic> toJson() {
    return {'worktreeRoot': worktreeRoot, if (branch != null) 'branch': branch};
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

/// A project management ticket following a GitHub Issues-style model.
///
/// Tickets use an Open/Closed status model with free-form tags for
/// categorization, a comment thread with activity timeline, and support
/// for image attachments and author attribution.
@immutable
class TicketData {
  /// Unique numeric identifier for this ticket.
  final int id;

  /// Short title describing the ticket.
  final String title;

  /// Markdown body content (was 'description' in V1).
  final String body;

  /// Who created this ticket (e.g. "zaf", "agent auth-refactor").
  final String author;

  /// Whether the ticket is open (true) or closed (false).
  final bool isOpen;

  /// Free-form tags for categorization (always lowercase).
  final Set<String> tags;

  /// IDs of tickets this ticket depends on.
  final List<int> dependsOn;

  /// Worktrees linked to this ticket.
  final List<LinkedWorktree> linkedWorktrees;

  /// Chats linked to this ticket.
  final List<LinkedChat> linkedChats;

  /// Comment thread for this ticket.
  final List<TicketComment> comments;

  /// Chronological activity timeline.
  final List<ActivityEvent> activityLog;

  /// Images attached to the ticket body.
  final List<TicketImage> bodyImages;

  /// ID of the conversation that created this ticket (if any).
  final String? sourceConversationId;

  /// When this ticket was created.
  final DateTime createdAt;

  /// When this ticket was last updated.
  final DateTime updatedAt;

  /// When this ticket was closed (null if open).
  final DateTime? closedAt;

  /// Creates a [TicketData] instance.
  ///
  /// Tags are normalized to lowercase on construction.
  TicketData({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    this.isOpen = true,
    Set<String> tags = const {},
    this.dependsOn = const [],
    this.linkedWorktrees = const [],
    this.linkedChats = const [],
    this.comments = const [],
    this.activityLog = const [],
    this.bodyImages = const [],
    this.sourceConversationId,
    required this.createdAt,
    required this.updatedAt,
    this.closedAt,
  }) : tags = {for (final t in tags) t.toLowerCase()};

  /// Formatted display ID (e.g., "#1").
  String get displayId => '#$id';

  /// Creates a copy with the given fields replaced.
  TicketData copyWith({
    int? id,
    String? title,
    String? body,
    String? author,
    bool? isOpen,
    Set<String>? tags,
    List<int>? dependsOn,
    List<LinkedWorktree>? linkedWorktrees,
    List<LinkedChat>? linkedChats,
    List<TicketComment>? comments,
    List<ActivityEvent>? activityLog,
    List<TicketImage>? bodyImages,
    String? sourceConversationId,
    bool clearSourceConversationId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? closedAt,
    bool clearClosedAt = false,
  }) {
    return TicketData(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      author: author ?? this.author,
      isOpen: isOpen ?? this.isOpen,
      tags: tags ?? this.tags,
      dependsOn: dependsOn ?? this.dependsOn,
      linkedWorktrees: linkedWorktrees ?? this.linkedWorktrees,
      linkedChats: linkedChats ?? this.linkedChats,
      comments: comments ?? this.comments,
      activityLog: activityLog ?? this.activityLog,
      bodyImages: bodyImages ?? this.bodyImages,
      sourceConversationId: clearSourceConversationId
          ? null
          : (sourceConversationId ?? this.sourceConversationId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
    );
  }

  /// Serializes this [TicketData] to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'author': author,
      'isOpen': isOpen,
      if (tags.isNotEmpty) 'tags': tags.toList(),
      if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
      if (linkedWorktrees.isNotEmpty)
        'linkedWorktrees': linkedWorktrees.map((w) => w.toJson()).toList(),
      if (linkedChats.isNotEmpty)
        'linkedChats': linkedChats.map((c) => c.toJson()).toList(),
      if (comments.isNotEmpty)
        'comments': comments.map((c) => c.toJson()).toList(),
      if (activityLog.isNotEmpty)
        'activityLog': activityLog.map((e) => e.toJson()).toList(),
      if (bodyImages.isNotEmpty)
        'bodyImages': bodyImages.map((i) => i.toJson()).toList(),
      if (sourceConversationId != null)
        'sourceConversationId': sourceConversationId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      if (closedAt != null) 'closedAt': closedAt!.toUtc().toIso8601String(),
    };
  }

  /// Deserializes a [TicketData] from a JSON map.
  factory TicketData.fromJson(Map<String, dynamic> json) {
    final tagsList = json['tags'] as List<dynamic>? ?? [];
    final dependsOnList = json['dependsOn'] as List<dynamic>? ?? [];
    final linkedWorktreesList = json['linkedWorktrees'] as List<dynamic>? ?? [];
    final linkedChatsList = json['linkedChats'] as List<dynamic>? ?? [];
    final commentsList = json['comments'] as List<dynamic>? ?? [];
    final activityLogList = json['activityLog'] as List<dynamic>? ?? [];
    final bodyImagesList = json['bodyImages'] as List<dynamic>? ?? [];

    final now = DateTime.now();

    return TicketData(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      author: json['author'] as String? ?? '',
      isOpen: json['isOpen'] as bool? ?? true,
      tags: Set<String>.from(tagsList.map((e) => e.toString())),
      dependsOn: dependsOnList.map((e) => e as int).toList(),
      linkedWorktrees: linkedWorktreesList
          .map((w) => LinkedWorktree.fromJson(w as Map<String, dynamic>))
          .toList(),
      linkedChats: linkedChatsList
          .map((c) => LinkedChat.fromJson(c as Map<String, dynamic>))
          .toList(),
      comments: commentsList
          .map((c) => TicketComment.fromJson(c as Map<String, dynamic>))
          .toList(),
      activityLog: activityLogList
          .map((e) => ActivityEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      bodyImages: bodyImagesList
          .map((i) => TicketImage.fromJson(i as Map<String, dynamic>))
          .toList(),
      sourceConversationId: json['sourceConversationId'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : now,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : now,
      closedAt: json['closedAt'] != null
          ? DateTime.parse(json['closedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TicketData &&
        other.id == id &&
        other.title == title &&
        other.body == body &&
        other.author == author &&
        other.isOpen == isOpen &&
        setEquals(other.tags, tags) &&
        listEquals(other.dependsOn, dependsOn) &&
        listEquals(other.linkedWorktrees, linkedWorktrees) &&
        listEquals(other.linkedChats, linkedChats) &&
        listEquals(other.comments, comments) &&
        listEquals(other.activityLog, activityLog) &&
        listEquals(other.bodyImages, bodyImages) &&
        other.sourceConversationId == sourceConversationId &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.closedAt == closedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      body,
      author,
      isOpen,
      Object.hashAll(tags),
      Object.hashAll(dependsOn),
      Object.hashAll(linkedWorktrees),
      Object.hashAll(linkedChats),
      Object.hashAll(comments),
      Object.hashAll(activityLog),
      Object.hashAll(bodyImages),
      sourceConversationId,
      createdAt,
      updatedAt,
      closedAt,
    );
  }

  @override
  String toString() {
    return 'TicketData(id: $id, title: $title, isOpen: $isOpen, '
        'author: $author)';
  }
}

/// A proposal for creating a ticket (used by bulk proposal workflow).
///
/// In V2, kind/priority/effort/category from the agent are converted to tags.
@immutable
class TicketProposal {
  /// Short title describing the ticket.
  final String title;

  /// Markdown body content.
  final String body;

  /// Free-form tags for categorization.
  final Set<String> tags;

  /// Indices of other proposals in the same batch that this ticket depends on.
  final List<int> dependsOnIndices;

  /// Creates a [TicketProposal] instance.
  const TicketProposal({
    required this.title,
    this.body = '',
    this.tags = const {},
    this.dependsOnIndices = const [],
  });

  /// Deserializes a [TicketProposal] from a JSON map.
  ///
  /// Converts V1 fields (kind, priority, effort, category) to tags.
  factory TicketProposal.fromJson(Map<String, dynamic> json) {
    final tags = <String>{};

    // Collect explicit tags
    final tagsList = json['tags'] as List<dynamic>?;
    if (tagsList != null) {
      tags.addAll(tagsList.map((e) => e.toString().toLowerCase()));
    }

    // Convert V1 enum fields to tags
    final kind = json['kind'] as String?;
    if (kind != null && kind.isNotEmpty) tags.add(kind.toLowerCase());

    final priority = json['priority'] as String?;
    if (priority != null && priority.isNotEmpty) tags.add(priority.toLowerCase());

    final effort = json['effort'] as String?;
    if (effort != null && effort.isNotEmpty) tags.add(effort.toLowerCase());

    final category = json['category'] as String?;
    if (category != null && category.isNotEmpty) tags.add(category.toLowerCase());

    return TicketProposal(
      title: json['title'] as String? ?? '',
      body: json['description'] as String? ?? json['body'] as String? ?? '',
      tags: tags,
      dependsOnIndices:
          ((json['dependsOnIndices'] as List<dynamic>?) ??
                  (json['depends_on_indices'] as List<dynamic>?) ??
                  [])
              .map((e) => (e as num).toInt())
              .toList(),
    );
  }
}
