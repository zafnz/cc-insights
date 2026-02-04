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

/// Reactive holder for theme settings.
///
/// Values are managed by [SettingsService] and synced here
/// so that [MaterialApp] can rebuild when the theme changes.
/// This class does not persist anything itself.
class ThemeState extends ChangeNotifier {
  ThemeState({
    Color seedColor = const Color(0xFF673AB7), // deepPurple
    ThemeMode themeMode = ThemeMode.system,
    Color? inputTextColor,
  })  : _seedColor = seedColor,
        _themeMode = themeMode,
        _inputTextColor = inputTextColor;

  Color _seedColor;
  ThemeMode _themeMode;
  Color? _inputTextColor;

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;

  /// Custom color for user input message bubbles.
  /// When null, falls back to [ColorScheme.primary].
  Color? get inputTextColor => _inputTextColor;


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
  }

  void setInputTextColor(Color? color) {
    if (_inputTextColor?.value == color?.value) return;
    _inputTextColor = color;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  /// Parses a theme mode string to [ThemeMode].
  static ThemeMode parseThemeMode(String? s) {
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
