import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/project_config.dart';
import '../models/user_action.dart';

/// Service for reading and writing project configuration files.
///
/// Configuration is stored at `{projectRoot}/.ccinsights/config.json`.
/// Extends [ChangeNotifier] so listeners (e.g. ActionsPanel) are notified
/// when the config is saved.
class ProjectConfigService extends ChangeNotifier {
  static const _configDir = '.ccinsights';
  static const _configFile = 'config.json';

  /// Returns the path to the config file for a given project root.
  String configPath(String projectRoot) =>
      '$projectRoot/$_configDir/$_configFile';

  /// Returns the path to the config directory for a given project root.
  String configDir(String projectRoot) => '$projectRoot/$_configDir';

  /// Loads the project configuration from disk.
  ///
  /// Returns [ProjectConfig.empty()] if the file doesn't exist or is invalid.
  Future<ProjectConfig> loadConfig(String projectRoot) async {
    final path = configPath(projectRoot);
    final file = File(path);

    if (!await file.exists()) {
      developer.log(
        'Config file does not exist: $path',
        name: 'ProjectConfigService',
      );
      return const ProjectConfig.empty();
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return const ProjectConfig.empty();
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      final config = ProjectConfig.fromJson(json);
      developer.log(
        'Loaded config from $path: $config',
        name: 'ProjectConfigService',
      );
      return config;
    } catch (e) {
      developer.log(
        'Failed to load config from $path: $e',
        name: 'ProjectConfigService',
        error: e,
      );
      return const ProjectConfig.empty();
    }
  }

  /// Saves the project configuration to disk.
  ///
  /// Creates the `.ccinsights` directory if it doesn't exist.
  Future<void> saveConfig(String projectRoot, ProjectConfig config) async {
    final dirPath = configDir(projectRoot);
    final filePath = configPath(projectRoot);

    try {
      // Create directory if needed
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        developer.log(
          'Created config directory: $dirPath',
          name: 'ProjectConfigService',
        );
      }

      // Write with pretty formatting
      const encoder = JsonEncoder.withIndent('  ');
      final content = encoder.convert(config.toJson());
      await File(filePath).writeAsString(content);

      developer.log('Saved config to $filePath', name: 'ProjectConfigService');

      notifyListeners();
    } catch (e) {
      developer.log(
        'Failed to save config to $filePath: $e',
        name: 'ProjectConfigService',
        error: e,
      );
      rethrow;
    }
  }

  /// Updates a single user action in the config.
  ///
  /// Loads the existing config, updates the action, and saves.
  Future<void> updateUserAction(String projectRoot, UserAction action) async {
    final config = await loadConfig(projectRoot);

    final newUserActions = List<UserAction>.from(
      config.userActions ?? const [],
    );
    final existingIndex = newUserActions.indexWhere(
      (existing) => existing.name == action.name,
    );
    if (existingIndex >= 0) {
      newUserActions[existingIndex] = action;
    } else {
      newUserActions.add(action);
    }

    final updatedConfig = config.copyWith(userActions: newUserActions);
    await saveConfig(projectRoot, updatedConfig);
  }

  /// Updates a lifecycle hook in the config.
  ///
  /// Loads the existing config, updates the hook, and saves.
  Future<void> updateAction(
    String projectRoot,
    String hookName,
    String command,
  ) async {
    final config = await loadConfig(projectRoot);

    final newActions = Map<String, String>.from(config.actions);
    newActions[hookName] = command;

    final updatedConfig = config.copyWith(actions: newActions);
    await saveConfig(projectRoot, updatedConfig);
  }

  /// Removes a user action from the config.
  Future<void> removeUserAction(String projectRoot, String actionName) async {
    final config = await loadConfig(projectRoot);

    if (config.userActions == null) return;

    final newUserActions = config.userActions!
        .where((action) => action.name != actionName)
        .toList();

    final updatedConfig = config.copyWith(userActions: newUserActions);
    await saveConfig(projectRoot, updatedConfig);
  }

  /// Updates the default base branch in the config.
  ///
  /// Pass null to clear the default base (revert to auto-detect).
  /// Loads the existing config, updates the field, and saves.
  Future<void> updateDefaultBase(String projectRoot, String? value) async {
    final config = await loadConfig(projectRoot);
    final updatedConfig = config.copyWith(
      defaultBase: value,
      clearDefaultBase: value == null,
    );
    await saveConfig(projectRoot, updatedConfig);
  }

  /// Checks if a config file exists for the given project.
  Future<bool> configExists(String projectRoot) async {
    return File(configPath(projectRoot)).exists();
  }
}
