import 'package:flutter/foundation.dart';

import 'output_entry.dart';

/// Persistent log of messages and output for a conversation.
///
/// A conversation survives session lifecycle and contains the complete history
/// of messages, tool uses, and other output entries. Each chat has a primary
/// conversation and zero or more subagent conversations.
///
/// Primary conversations (where [label] is null) allow user input, while
/// subagent conversations are read-only and display output from SDK subagents.
///
/// This is an immutable data class. Use [copyWith] to create modified copies.
@immutable
class ConversationData {
  /// Unique identifier for this conversation.
  final String id;

  /// Label for subagent conversations (e.g., "Explore", "Plan").
  ///
  /// Null for primary conversations.
  final String? label;

  /// Task description for subagent conversations.
  ///
  /// Describes what the subagent was asked to do. Null for primary
  /// conversations.
  final String? taskDescription;

  /// The conversation log entries in chronological order.
  ///
  /// Contains [TextOutputEntry], [ToolUseOutputEntry], [UserInputEntry],
  /// and other [OutputEntry] subclasses.
  final List<OutputEntry> entries;

  /// Cumulative token usage and cost for this conversation.
  final UsageInfo totalUsage;

  /// Creates a [ConversationData] instance.
  const ConversationData({
    required this.id,
    this.label,
    this.taskDescription,
    required this.entries,
    required this.totalUsage,
  });

  /// Creates an empty primary conversation with the given ID.
  const ConversationData.primary({required this.id})
    : label = null,
      taskDescription = null,
      entries = const [],
      totalUsage = const UsageInfo.zero();

  /// Creates a new subagent conversation with the given label and task.
  const ConversationData.subagent({
    required this.id,
    required String this.label,
    this.taskDescription,
  }) : entries = const [],
       totalUsage = const UsageInfo.zero();

  /// Whether this is a primary conversation.
  ///
  /// Primary conversations allow user input. Subagent conversations
  /// (where [label] is not null) are read-only.
  bool get isPrimary => label == null;

  /// Creates a copy with the given fields replaced.
  ConversationData copyWith({
    String? id,
    String? label,
    String? taskDescription,
    List<OutputEntry>? entries,
    UsageInfo? totalUsage,
  }) {
    return ConversationData(
      id: id ?? this.id,
      label: label ?? this.label,
      taskDescription: taskDescription ?? this.taskDescription,
      entries: entries ?? this.entries,
      totalUsage: totalUsage ?? this.totalUsage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationData &&
        other.id == id &&
        other.label == label &&
        other.taskDescription == taskDescription &&
        listEquals(other.entries, entries) &&
        other.totalUsage == totalUsage;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      label,
      taskDescription,
      Object.hashAll(entries),
      totalUsage,
    );
  }

  @override
  String toString() {
    return 'ConversationData(id: $id, label: $label, '
        'taskDescription: $taskDescription, entries: ${entries.length}, '
        'totalUsage: $totalUsage)';
  }
}
