import 'package:flutter/foundation.dart';

import 'user_action.dart';

/// Configuration for project-specific actions stored in .ccinsights/config.json.
///
/// This configuration lives at the project root (not per-worktree) and contains:
/// - Lifecycle hooks (worktree-pre-create, worktree-post-create, etc.)
/// - User-defined action buttons (Test, Run, etc.)
/// - Default base branch for merge/diff operations
@immutable
class ProjectConfig {
  /// Lifecycle hooks that run during worktree operations.
  ///
  /// Supported keys:
  /// - `worktree-pre-create`: Runs before git worktree add
  /// - `worktree-post-create`: Runs after worktree is created
  /// - `worktree-pre-remove`: Runs before worktree removal
  /// - `worktree-post-remove`: Runs after worktree removal
  final Map<String, String> actions;

  /// User-defined action buttons shown in the ActionsPanel.
  ///
  /// - If null: show default actions (Test, Run)
  /// - If empty list: show no actions
  /// - If populated: show only these actions, in list order
  final List<UserAction>? userActions;

  /// Default base branch/ref for merge and diff operations.
  ///
  /// Can be "main", "origin/main", "auto", or a custom ref.
  /// If null, the application auto-detects the base branch.
  final String? defaultBase;

  /// Default user actions shown when no config exists or userActions is null.
  static const List<UserAction> defaultUserActions = [
    CommandAction(name: 'Test', command: './test.sh'),
    CommandAction(name: 'Run', command: './run.sh'),
  ];

  const ProjectConfig({
    this.actions = const {},
    this.userActions,
    this.defaultBase,
  });

  /// Creates an empty config (used as default when no file exists).
  const ProjectConfig.empty()
    : actions = const {},
      userActions = null,
      defaultBase = null;

  /// Returns the effective user actions to display.
  ///
  /// - Returns [defaultUserActions] if [userActions] is null
  /// - Returns the actual [userActions] list otherwise (may be empty)
  List<UserAction> get effectiveUserActions =>
      userActions ?? defaultUserActions;

  /// Whether this config has any lifecycle hooks defined.
  bool get hasLifecycleHooks => actions.isNotEmpty;

  /// Gets a specific lifecycle hook command, or null if not defined.
  String? getHook(String hookName) => actions[hookName];

  /// Creates a copy with updated fields.
  ProjectConfig copyWith({
    Map<String, String>? actions,
    List<UserAction>? userActions,
    bool clearUserActions = false,
    String? defaultBase,
    bool clearDefaultBase = false,
  }) {
    return ProjectConfig(
      actions: actions ?? this.actions,
      userActions: clearUserActions ? null : (userActions ?? this.userActions),
      defaultBase: clearDefaultBase ? null : (defaultBase ?? this.defaultBase),
    );
  }

  /// Creates a config from JSON.
  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'];
    final userActionsJson = json['user-actions'];
    final defaultBaseJson = json['default-base'];

    List<UserAction>? parsedUserActions;
    if (userActionsJson is Map) {
      parsedUserActions = userActionsJson.entries
          .where((entry) => entry.key is String)
          .map((entry) => UserAction.fromJson(entry.key as String, entry.value))
          .toList();
    }

    return ProjectConfig(
      actions: actionsJson is Map
          ? Map<String, String>.from(actionsJson)
          : const {},
      userActions: parsedUserActions,
      defaultBase: defaultBaseJson is String ? defaultBaseJson : null,
    );
  }

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() {
    return {
      if (actions.isNotEmpty) 'actions': actions,
      if (userActions != null)
        'user-actions': {
          for (final action in userActions!) action.name: action.toJsonValue(),
        },
      if (defaultBase != null) 'default-base': defaultBase,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectConfig &&
        mapEquals(other.actions, actions) &&
        listEquals(other.userActions, userActions) &&
        other.defaultBase == defaultBase;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(actions.entries),
    userActions != null ? Object.hashAll(userActions!) : null,
    defaultBase,
  );

  @override
  String toString() =>
      'ProjectConfig(actions: $actions, userActions: $userActions, '
      'defaultBase: $defaultBase)';
}
