import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// An immutable tag definition with a name and color.
///
/// Tags are defined globally in user settings and assigned to worktrees
/// by name. Each tag has a unique name and a color stored as an int
/// for JSON serialization.
@immutable
class WorktreeTag {
  /// The display name of this tag (e.g., "ready", "testing").
  final String name;

  /// The color stored as an ARGB int value.
  final int colorValue;

  /// Creates a [WorktreeTag] with the given [name] and [colorValue].
  const WorktreeTag({
    required this.name,
    required this.colorValue,
  });

  /// The resolved [Color] from [colorValue].
  Color get color => Color(colorValue);

  /// Creates a copy with the given fields replaced.
  WorktreeTag copyWith({
    String? name,
    int? colorValue,
  }) {
    return WorktreeTag(
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  /// Serializes this tag to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'color': colorValue,
    };
  }

  /// Deserializes a tag from a JSON map.
  factory WorktreeTag.fromJson(Map<String, dynamic> json) {
    return WorktreeTag(
      name: json['name'] as String,
      colorValue: json['color'] as int,
    );
  }

  /// The default set of tags provided on first use.
  static const List<WorktreeTag> defaults = [
    WorktreeTag(name: 'ready', colorValue: 0xFF4CAF50),
    WorktreeTag(name: 'testing', colorValue: 0xFFFF9800),
    WorktreeTag(name: 'mergable', colorValue: 0xFF2196F3),
    WorktreeTag(name: 'in-review', colorValue: 0xFF9C27B0),
    WorktreeTag(name: 'feedback', colorValue: 0xFF00BCD4),
    WorktreeTag(name: 'merged', colorValue: 0xFF607D8B),
    WorktreeTag(name: 'done', colorValue: 0xFF9E9E9E),
  ];

  /// Preset colors available when creating or editing tags.
  static const List<int> presetColors = [
    0xFF4CAF50, // green
    0xFFFF9800, // orange
    0xFF2196F3, // blue
    0xFF9C27B0, // purple
    0xFF00BCD4, // cyan
    0xFF607D8B, // blue-grey
    0xFFFFEB3B, // yellow
    0xFF795548, // brown
    0xFFE91E63, // pink
    0xFFFF5722, // deep orange
    0xFF3F51B5, // indigo
    0xFF9E9E9E, // grey
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorktreeTag &&
        other.name == name &&
        other.colorValue == colorValue;
  }

  @override
  int get hashCode => Object.hash(name, colorValue);

  @override
  String toString() => 'WorktreeTag(name: $name, color: $colorValue)';
}
