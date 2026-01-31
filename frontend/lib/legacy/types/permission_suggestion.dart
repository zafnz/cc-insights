/// A permission rule within a suggestion (for addRules/replaceRules/removeRules).
class PermissionRule {
  const PermissionRule({
    required this.toolName,
    this.ruleContent,
  });

  final String toolName;
  final String? ruleContent;

  /// Display label for UI, e.g. "Bash(flutter test:*)" or just "Read".
  String get displayLabel =>
      ruleContent != null ? '$toolName($ruleContent)' : toolName;

  factory PermissionRule.fromJson(Map<String, dynamic> json) {
    return PermissionRule(
      toolName: json['toolName'] as String? ?? '',
      ruleContent: json['ruleContent'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        if (ruleContent != null) 'ruleContent': ruleContent,
      };
}

/// A permission suggestion from the SDK.
///
/// When the SDK's canUseTool callback is invoked, it may include suggestions
/// for permission rules the user could add to auto-approve similar requests.
///
/// Supports multiple types:
/// - `addRules` / `replaceRules` / `removeRules`: uses `rules` array
/// - `addDirectories` / `removeDirectories`: uses `directories` array
/// - `setMode`: uses `mode` field
class PermissionSuggestion {
  const PermissionSuggestion({
    required this.type,
    this.rules,
    this.directories,
    this.mode,
    this.behavior,
    required this.destination,
    required this.rawJson,
  });

  /// The type of update: 'addRules', 'replaceRules', 'removeRules',
  /// 'addDirectories', 'removeDirectories', 'setMode'.
  final String type;

  /// The permission rules (for addRules/replaceRules/removeRules).
  final List<PermissionRule>? rules;

  /// The directories (for addDirectories/removeDirectories).
  final List<String>? directories;

  /// The mode (for setMode).
  final String? mode;

  /// The behavior: 'allow', 'deny', or 'ask' (only for rule types).
  final String? behavior;

  /// Where to save: 'localSettings', 'projectSettings', 'userSettings', 'session'.
  final String destination;

  /// Original JSON for passthrough to SDK.
  final Map<String, dynamic> rawJson;

  /// Human-readable display label for the UI.
  String get displayLabel {
    switch (type) {
      case 'addRules':
      case 'replaceRules':
        if (rules != null && rules!.isNotEmpty) {
          return rules!.map((r) => r.displayLabel).join(', ');
        }
        return 'permission rules';
      case 'removeRules':
        if (rules != null && rules!.isNotEmpty) {
          return 'remove ${rules!.map((r) => r.displayLabel).join(', ')}';
        }
        return 'remove rules';
      case 'addDirectories':
        if (directories != null && directories!.isNotEmpty) {
          // Show short paths for readability
          final paths = directories!.map((d) {
            // Shorten home directory
            if (d.startsWith('/Users/')) {
              final parts = d.split('/');
              if (parts.length > 2) {
                final subPath = parts.sublist(3).join('/');
                return subPath.isEmpty ? '~/' : '~/$subPath';
              }
            }
            return d;
          }).join(', ');
          return paths;
        }
        return 'directory access';
      case 'removeDirectories':
        if (directories != null && directories!.isNotEmpty) {
          return 'remove directory access';
        }
        return 'remove directories';
      case 'setMode':
        return 'set mode to ${mode ?? 'default'}';
      default:
        return type;
    }
  }

  factory PermissionSuggestion.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'addRules';

    // Parse rules if present
    List<PermissionRule>? rules;
    final rulesJson = json['rules'] as List<dynamic>?;
    if (rulesJson != null) {
      rules = rulesJson
          .whereType<Map<String, dynamic>>()
          .map((r) => PermissionRule.fromJson(r))
          .toList();
    }

    // Parse directories if present
    List<String>? directories;
    final dirsJson = json['directories'] as List<dynamic>?;
    if (dirsJson != null) {
      directories = dirsJson.whereType<String>().toList();
    }

    return PermissionSuggestion(
      type: type,
      rules: rules,
      directories: directories,
      mode: json['mode'] as String?,
      behavior: json['behavior'] as String?,
      destination: json['destination'] as String? ?? 'localSettings',
      rawJson: json,
    );
  }

  /// Create a copy with a different destination.
  PermissionSuggestion withDestination(String newDestination) {
    return PermissionSuggestion(
      type: type,
      rules: rules,
      directories: directories,
      mode: mode,
      behavior: behavior,
      destination: newDestination,
      rawJson: {...rawJson, 'destination': newDestination},
    );
  }

  /// Create a copy with a different behavior.
  PermissionSuggestion withBehavior(String newBehavior) {
    return PermissionSuggestion(
      type: type,
      rules: rules,
      directories: directories,
      mode: mode,
      behavior: newBehavior,
      destination: destination,
      rawJson: {...rawJson, 'behavior': newBehavior},
    );
  }

  /// Convert to JSON for sending back to SDK.
  /// Uses the original rawJson but with possibly updated behavior and destination.
  Map<String, dynamic> toJson() => {
        ...rawJson,
        if (behavior != null) 'behavior': behavior,
        'destination': destination,
      };
}

/// Destination options for permission rules.
enum PermissionDestination {
  localSettings('localSettings', 'Local Settings'),
  projectSettings('projectSettings', 'Project Settings'),
  userSettings('userSettings', 'User Settings'),
  session('session', 'This Session Only');

  const PermissionDestination(this.value, this.displayName);

  final String value;
  final String displayName;

  static PermissionDestination fromValue(String value) {
    return PermissionDestination.values.firstWhere(
      (d) => d.value == value,
      orElse: () => PermissionDestination.localSettings,
    );
  }
}
