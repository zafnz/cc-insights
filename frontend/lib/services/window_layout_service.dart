import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'persistence_service.dart';

/// Service for persisting window geometry and panel layout state.
///
/// This data changes frequently (on every window resize or panel drag)
/// and is stored in a separate `window.json` file to avoid polluting
/// the user-facing `config.json` with automatic writes.
class WindowLayoutService extends ChangeNotifier {
  WindowLayoutService({String? configPath})
      : _configPath =
            configPath ?? '${PersistenceService.baseDir}/window.json';

  final String _configPath;

  final Map<String, dynamic> _values = {};

  bool _loaded = false;

  bool get loaded => _loaded;

  // ---------------------------------------------------------------------------
  // Window persistence
  // ---------------------------------------------------------------------------

  static const _windowWidthKey = 'window.width';
  static const _windowHeightKey = 'window.height';

  /// Returns the saved window size, or null if not saved.
  ({double width, double height})? get savedWindowSize {
    final w = _values[_windowWidthKey];
    final h = _values[_windowHeightKey];
    if (w is num && h is num && w > 0 && h > 0) {
      return (width: w.toDouble(), height: h.toDouble());
    }
    return null;
  }

  /// Saves the window dimensions to window.json.
  Future<void> saveWindowSize(double width, double height) async {
    _values[_windowWidthKey] = width;
    _values[_windowHeightKey] = height;
    await _save();
  }

  // ---------------------------------------------------------------------------
  // Panel layout persistence
  // ---------------------------------------------------------------------------

  static const _layoutTreeKey = 'layout.tree';

  /// Returns the saved layout tree JSON, or null if not saved.
  Map<String, dynamic>? get savedLayoutTree {
    final raw = _values[_layoutTreeKey];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return null;
  }

  /// Saves the layout tree JSON to window.json.
  Future<void> saveLayoutTree(Map<String, dynamic> treeJson) async {
    _values[_layoutTreeKey] = treeJson;
    await _save();
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Loads window/layout state from disk. Should be called once at startup.
  ///
  /// If [migrationSource] is provided and this service's own file does not
  /// yet exist, window/layout keys are migrated from [migrationSource] (the
  /// old config.json values map).
  Future<void> load({Map<String, dynamic>? migrationSource}) async {
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
          'Failed to load window layout: $e',
          name: 'WindowLayoutService',
          error: e,
        );
      }
    } else if (migrationSource != null) {
      await _migrateFromConfig(migrationSource);
    }

    _loaded = true;
    notifyListeners();
  }

  /// Migrates window/layout keys from the old config.json values.
  Future<void> _migrateFromConfig(Map<String, dynamic> source) async {
    const keysToMigrate = [
      'window.width',
      'window.height',
      'layout.tree',
    ];
    for (final key in keysToMigrate) {
      if (source.containsKey(key)) {
        _values[key] = source[key];
      }
    }
    if (_values.isNotEmpty) {
      await _save();
    }
  }

  /// Saves current values to disk.
  Future<void> _save() async {
    try {
      final file = File(_configPath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(_values));
    } catch (e) {
      developer.log(
        'Failed to save window layout: $e',
        name: 'WindowLayoutService',
        error: e,
      );
    }
  }
}
