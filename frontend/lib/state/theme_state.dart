import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';

/// Preset seed colors available in the theme selector.
enum ThemePresetColor {
  deepPurple('Deep Purple', Colors.deepPurple),
  blue('Blue', Colors.blue),
  teal('Teal', Colors.teal),
  green('Green', Colors.green),
  orange('Orange', Colors.orange),
  red('Red', Colors.red),
  indigo('Indigo', Colors.indigo),
  slate('Slate', Color(0xFF607D8B));

  const ThemePresetColor(this.label, this.color);
  final String label;
  final Color color;
}

/// Manages the application's theme settings.
///
/// Owns the seed color and theme mode, persists them to
/// `~/.ccinsights/theme.json`, and notifies listeners on
/// change.
class ThemeState extends ChangeNotifier {
  ThemeState({
    Color seedColor = const Color(0xFF673AB7), // deepPurple
    ThemeMode themeMode = ThemeMode.system,
  })  : _seedColor = seedColor,
        _themeMode = themeMode;

  Color _seedColor;
  ThemeMode _themeMode;

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  /// The preset matching the current seed color, or null if
  /// using a custom color.
  ThemePresetColor? get activePreset {
    for (final preset in ThemePresetColor.values) {
      if (preset.color.value == _seedColor.value) return preset;
    }
    return null;
  }

  void setSeedColor(Color color) {
    if (_seedColor.value == color.value) return;
    _seedColor = color;
    notifyListeners();
    _persist();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    _persist();
  }

  /// Apply loaded settings without re-persisting.
  ///
  /// Used during startup to apply values read from disk
  /// without triggering a redundant write.
  void applyLoaded(Color seedColor, ThemeMode themeMode) {
    _seedColor = seedColor;
    _themeMode = themeMode;
    notifyListeners();
  }

  // -- Persistence --

  static String get _settingsPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.ccinsights/theme.json';
  }

  /// Loads theme settings from disk. Returns a new
  /// [ThemeState] with the persisted values, or defaults.
  static Future<ThemeState> load() async {
    final file = File(_settingsPath);
    if (!await file.exists()) return ThemeState();
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final colorValue = json['seedColor'] as int?;
      final modeStr = json['themeMode'] as String?;
      return ThemeState(
        seedColor: colorValue != null
            ? Color(colorValue)
            : const Color(0xFF673AB7),
        themeMode: _parseThemeMode(modeStr),
      );
    } catch (e) {
      developer.log(
        'Failed to load theme settings: $e',
        name: 'ThemeState',
      );
      return ThemeState();
    }
  }

  Future<void> _persist() async {
    try {
      final dir = Directory(
        File(_settingsPath).parent.path,
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final json = jsonEncode({
        'seedColor': _seedColor.value,
        'themeMode': _themeMode.name,
      });
      await File(_settingsPath).writeAsString(json);
    } catch (e) {
      developer.log(
        'Failed to persist theme settings: $e',
        name: 'ThemeState',
      );
    }
  }

  static ThemeMode _parseThemeMode(String? s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
