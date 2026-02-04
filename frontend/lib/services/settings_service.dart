import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/setting_definition.dart';
import '../models/worktree_tag.dart';
import 'persistence_service.dart';
import 'runtime_config.dart';

/// Service for loading, saving, and managing application settings.
///
/// Settings are defined as generic [SettingDefinition] objects grouped
/// into [SettingCategory] instances. Values are persisted to
/// `~/.ccinsights/config.json` and synced to [RuntimeConfig] for
/// live UI updates.
class SettingsService extends ChangeNotifier {
  SettingsService({String? configPath})
      : _configPath = configPath ??
            '${PersistenceService.baseDir}/config.json';

  final String _configPath;

  /// Current setting values. Keys match [SettingDefinition.key].
  final Map<String, dynamic> _values = {};

  /// Whether the initial load has completed.
  bool _loaded = false;

  /// Whether settings have been loaded from disk.
  bool get loaded => _loaded;

  // ---------------------------------------------------------------------------
  // Setting Categories
  // ---------------------------------------------------------------------------

  /// Key for the available tags list in settings.
  static const tagsKey = 'tags.available';

  /// All setting categories and their definitions.
  static const List<SettingCategory> categories = [
    _appearanceCategory,
    _behaviorCategory,
    _tagsCategory,
    _sessionCategory,
    _developerCategory,
  ];

  static const _tagsCategory = SettingCategory(
    id: 'tags',
    label: 'Tags',
    description: 'Manage worktree tags and their colors',
    icon: Icons.label_outlined,
    settings: [],
  );

  static const _appearanceCategory = SettingCategory(
    id: 'appearance',
    label: 'Appearance',
    description: 'Customize how CC Insights looks and displays information',
    icon: Icons.palette_outlined,
    settings: [
      SettingDefinition(
        key: 'appearance.themeMode',
        title: 'Theme Mode',
        description:
            'Choose between light, dark, or system-default '
            'appearance.',
        type: SettingType.dropdown,
        defaultValue: 'system',
        options: [
          SettingOption(value: 'light', label: 'Light'),
          SettingOption(value: 'dark', label: 'Dark'),
          SettingOption(value: 'system', label: 'System'),
        ],
      ),
      SettingDefinition(
        key: 'appearance.seedColor',
        title: 'Accent Color',
        description:
            'The seed color used to generate the application '
            'color scheme. Choose a preset or enter a custom '
            'hex value.',
        type: SettingType.colorPicker,
        // Colors.deepPurple.value
        defaultValue: 0xFF673AB7,
      ),
      SettingDefinition(
        key: 'appearance.bashToolSummary',
        title: 'Bash Tool Summary',
        description:
            'How to display bash commands in the conversation. '
            '`Description` shows a human-readable summary of what '
            'the command does. `Command` shows the actual command text.',
        type: SettingType.dropdown,
        defaultValue: 'description',
        options: [
          SettingOption(value: 'description', label: 'Description'),
          SettingOption(value: 'command', label: 'Command'),
        ],
      ),
      SettingDefinition(
        key: 'appearance.relativeFilePaths',
        title: 'Relative File Paths',
        description:
            'Show file paths relative to the project directory instead '
            'of absolute paths. Makes tool output more compact and '
            'readable when working within a project.',
        type: SettingType.toggle,
        defaultValue: true,
      ),
      SettingDefinition(
        key: 'appearance.showTimestamps',
        title: 'Show Timestamps',
        description:
            'Display timestamps next to messages in the conversation '
            'view. Helps track timing during long debugging sessions.',
        type: SettingType.toggle,
        defaultValue: false,
      ),
      SettingDefinition(
        key: 'appearance.timestampIdleThreshold',
        title: 'Timestamp Idle Threshold',
        description:
            'Only show timestamps after this many minutes of '
            'inactivity. Set to `0` to show timestamps on every '
            'message regardless of timing.',
        type: SettingType.number,
        defaultValue: 5,
        min: 0,
        max: 60,
      ),
    ],
  );

  static const _behaviorCategory = SettingCategory(
    id: 'behavior',
    label: 'Behavior',
    description: 'Control how CC Insights behaves during sessions',
    icon: Icons.tune_outlined,
    settings: [
      SettingDefinition(
        key: 'behavior.aiAssistanceModel',
        title: 'AI Assistance Model',
        description:
            'Which model to use for automated tasks such as '
            'commit message generation and merge conflict '
            'resolution. Set to `Disabled` to turn off AI '
            'assistance entirely.',
        type: SettingType.dropdown,
        defaultValue: 'haiku',
        options: [
          SettingOption(value: 'haiku', label: 'Haiku'),
          SettingOption(value: 'sonnet', label: 'Sonnet'),
          SettingOption(value: 'opus', label: 'Opus'),
          SettingOption(value: 'disabled', label: 'Disabled'),
        ],
      ),
      SettingDefinition(
        key: 'behavior.aiChatLabelModel',
        title: 'AI Chat Labels',
        description:
            'Which model to use when auto-generating chat '
            'labels from the first message. Set to `Disabled` '
            'to use sequential names like `Chat #1` instead.',
        type: SettingType.dropdown,
        defaultValue: 'haiku',
        options: [
          SettingOption(value: 'haiku', label: 'Haiku'),
          SettingOption(value: 'sonnet', label: 'Sonnet'),
          SettingOption(value: 'opus', label: 'Opus'),
          SettingOption(value: 'disabled', label: 'Disabled'),
        ],
      ),
      SettingDefinition(
        key: 'behavior.desktopNotifications',
        title: 'Desktop Notifications',
        description:
            'Show desktop notifications when a chat completes or '
            'requires attention while the app is in the background.',
        type: SettingType.toggle,
        defaultValue: true,
      ),
    ],
  );

  static const _sessionCategory = SettingCategory(
    id: 'session',
    label: 'Session',
    description: 'Default settings for new chat sessions',
    icon: Icons.chat_outlined,
    settings: [
      SettingDefinition(
        key: 'session.defaultModel',
        title: 'Default Model',
        description:
            'The Claude model to use for new chat sessions. '
            '`Opus` is the most capable, `Sonnet` balances speed '
            'and capability, `Haiku` is the fastest.',
        type: SettingType.dropdown,
        defaultValue: 'opus',
        options: [
          SettingOption(value: 'haiku', label: 'Haiku'),
          SettingOption(value: 'sonnet', label: 'Sonnet'),
          SettingOption(value: 'opus', label: 'Opus'),
        ],
      ),
      SettingDefinition(
        key: 'session.defaultPermissionMode',
        title: 'Default Permission Mode',
        description:
            'The permission mode for new chat sessions. `Default` '
            'requires approval for most operations. `Accept Edits` '
            'auto-approves file changes. `Plan` restricts tool '
            'access. `Bypass` approves everything.',
        type: SettingType.dropdown,
        defaultValue: 'default',
        options: [
          SettingOption(value: 'default', label: 'Default'),
          SettingOption(value: 'acceptEdits', label: 'Accept Edits'),
          SettingOption(value: 'plan', label: 'Plan'),
          SettingOption(value: 'bypassPermissions', label: 'Bypass'),
        ],
      ),
    ],
  );

  static const _developerCategory = SettingCategory(
    id: 'developer',
    label: 'Developer',
    description: 'Debugging and developer tools',
    icon: Icons.code_outlined,
    settings: [
      SettingDefinition(
        key: 'developer.showRawMessages',
        title: 'Show Raw Messages',
        description:
            'Show debug icons on messages that allow viewing the '
            'raw JSON data. Useful for debugging SDK communication.',
        type: SettingType.toggle,
        defaultValue: true,
      ),
      SettingDefinition(
        key: 'developer.debugSdkLogging',
        title: 'Debug SDK Logging',
        description:
            'Enable verbose SDK logging to '
            '`~/ccinsights.debug.jsonl`. Captures all messages '
            'between the app and the Claude CLI.',
        type: SettingType.toggle,
        defaultValue: false,
      ),
    ],
  );

  // ---------------------------------------------------------------------------
  // Value access
  // ---------------------------------------------------------------------------

  /// Gets a setting value, falling back to its default.
  T getValue<T>(String key) {
    if (_values.containsKey(key)) {
      final value = _values[key];
      if (value is T) return value;
    }
    final def = findDefinition(key);
    if (def != null) return def.defaultValue as T;
    throw ArgumentError('Unknown setting key: $key');
  }

  /// Sets a setting value, persists, and syncs to RuntimeConfig.
  Future<void> setValue(String key, dynamic value) async {
    _values[key] = value;
    _syncToRuntimeConfig(key, value);
    notifyListeners();
    await _save();
  }

  /// Resets all settings to their defaults.
  Future<void> resetToDefaults() async {
    _values.clear();
    _syncAllToRuntimeConfig();
    notifyListeners();
    await _save();
  }

  // ---------------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------------

  /// Returns the list of available worktree tags.
  ///
  /// Falls back to [WorktreeTag.defaults] if no tags are configured.
  List<WorktreeTag> get availableTags {
    final raw = _values[tagsKey];
    if (raw is List) {
      try {
        return raw
            .map(
              (e) => WorktreeTag.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      } catch (_) {
        return List.of(WorktreeTag.defaults);
      }
    }
    return List.of(WorktreeTag.defaults);
  }

  /// Replaces the entire list of available tags.
  Future<void> setAvailableTags(List<WorktreeTag> tags) async {
    _values[tagsKey] = tags.map((t) => t.toJson()).toList();
    notifyListeners();
    await _save();
  }

  /// Adds a new tag to the available list.
  Future<void> addTag(WorktreeTag tag) async {
    final tags = availableTags;
    tags.add(tag);
    await setAvailableTags(tags);
  }

  /// Removes a tag by name from the available list.
  Future<void> removeTag(String name) async {
    final tags = availableTags;
    tags.removeWhere((t) => t.name == name);
    await setAvailableTags(tags);
  }

  /// Updates a tag identified by [oldName] with a new [tag].
  Future<void> updateTag(String oldName, WorktreeTag tag) async {
    final tags = availableTags;
    final index = tags.indexWhere((t) => t.name == oldName);
    if (index >= 0) {
      tags[index] = tag;
      await setAvailableTags(tags);
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Loads settings from disk. Should be called once at startup.
  Future<void> load() async {
    final file = File(_configPath);

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          _values.addAll(json);
        }
      } catch (e) {
        developer.log(
          'Failed to load settings: $e',
          name: 'SettingsService',
          error: e,
        );
      }
    }

    _loaded = true;
    _syncAllToRuntimeConfig();
    notifyListeners();
  }

  /// Saves current values to disk.
  Future<void> _save() async {
    try {
      final file = File(_configPath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_values));
    } catch (e) {
      developer.log(
        'Failed to save settings: $e',
        name: 'SettingsService',
        error: e,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RuntimeConfig sync
  // ---------------------------------------------------------------------------

  /// Syncs a single setting value to RuntimeConfig.
  void _syncToRuntimeConfig(String key, dynamic value) {
    final config = RuntimeConfig.instance;
    switch (key) {
      case 'appearance.bashToolSummary':
        config.bashToolSummary = value == 'command'
            ? BashToolSummary.command
            : BashToolSummary.description;
      case 'appearance.relativeFilePaths':
        config.toolSummaryRelativeFilePaths = value as bool;
      case 'appearance.showTimestamps':
        config.showTimestamps = value as bool;
      case 'appearance.timestampIdleThreshold':
        config.timestampIdleThreshold = (value as num).toInt();
      case 'behavior.aiAssistanceModel':
        config.aiAssistanceModel = value as String;
      case 'behavior.aiChatLabelModel':
        config.aiChatLabelModel = value as String;
      case 'behavior.desktopNotifications':
        config.desktopNotifications = value as bool;
      case 'session.defaultModel':
        config.defaultModel = value as String;
      case 'session.defaultPermissionMode':
        config.defaultPermissionMode = value as String;
      case 'developer.showRawMessages':
        config.showRawMessages = value as bool;
      case 'developer.debugSdkLogging':
        config.debugSdkLogging = value as bool;
    }
  }

  /// Syncs all settings to RuntimeConfig using current or default values.
  void _syncAllToRuntimeConfig() {
    for (final category in categories) {
      for (final setting in category.settings) {
        final value = _values.containsKey(setting.key)
            ? _values[setting.key]
            : setting.defaultValue;
        _syncToRuntimeConfig(setting.key, value);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Finds a setting definition by key across all categories.
  static SettingDefinition? findDefinition(String key) {
    for (final category in categories) {
      for (final setting in category.settings) {
        if (setting.key == key) return setting;
      }
    }
    return null;
  }
}
