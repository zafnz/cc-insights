import 'package:flutter/material.dart';

/// The type of input widget to render for a setting.
enum SettingType {
  /// Boolean toggle switch.
  toggle,

  /// Dropdown with predefined options.
  dropdown,

  /// Numeric input field.
  number,

  /// Color picker with presets and custom hex input.
  colorPicker,

  /// Text input field.
  text,
}

/// A single option in a dropdown setting.
@immutable
class SettingOption {
  /// The value stored when this option is selected.
  final String value;

  /// The display label shown in the dropdown.
  final String label;

  const SettingOption({required this.value, required this.label});
}

/// A self-describing setting definition.
///
/// The UI renders settings generically based on these definitions -
/// no per-setting widgets needed.
@immutable
class SettingDefinition {
  /// Unique key used for persistence (e.g., 'appearance.bashToolSummary').
  final String key;

  /// Display title (e.g., 'Bash Tool Summary').
  final String title;

  /// Description text. Supports inline `code` spans rendered in mono.
  final String description;

  /// Determines which widget renders this setting.
  final SettingType type;

  /// The default value. Type depends on [type]:
  /// - toggle: bool
  /// - dropdown: String (matching a SettingOption.value)
  /// - number: int
  final dynamic defaultValue;

  /// For dropdowns: the allowed values with display labels.
  final List<SettingOption>? options;

  /// For numbers: minimum allowed value.
  final int? min;

  /// For numbers: maximum allowed value.
  final int? max;

  /// For text: placeholder text shown when empty.
  final String? placeholder;

  const SettingDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.type,
    required this.defaultValue,
    this.options,
    this.min,
    this.max,
    this.placeholder,
  });
}

/// A group of settings displayed as a section in the settings screen.
@immutable
class SettingCategory {
  /// Unique identifier (e.g., 'appearance').
  final String id;

  /// Display label (e.g., 'Appearance').
  final String label;

  /// Subtitle shown below the category header.
  final String description;

  /// Icon shown in the sidebar.
  final IconData icon;

  /// The settings in this category.
  final List<SettingDefinition> settings;

  const SettingCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.settings,
  });
}
