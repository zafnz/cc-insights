import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/theme_state.dart';

/// Shows the application settings dialog.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const SettingsDialog(),
  );
}

/// Application settings dialog with theme color and
/// appearance mode controls.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Color',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in ThemePresetColor.values)
                  _ColorSwatch(
                    color: preset.color,
                    tooltip: preset.label,
                    isSelected:
                        themeState.activePreset == preset,
                    onTap: () =>
                        themeState.setSeedColor(preset.color),
                  ),
                _CustomColorSwatch(
                  isSelected: themeState.activePreset == null,
                  currentColor: themeState.seedColor,
                  onColorSelected: themeState.setSeedColor,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Appearance',
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 18),
                    label: Text('Light'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 18),
                    label: Text('Dark'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(
                      Icons.settings_suggest,
                      size: 18,
                    ),
                    label: Text('System'),
                  ),
                ],
                selected: {themeState.themeMode},
                onSelectionChanged: (modes) {
                  themeState.setThemeMode(modes.first);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A circular color swatch button.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        Theme.of(context).colorScheme.outline;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(color: borderColor, width: 2.5)
                : Border.all(
                    color: borderColor.withValues(alpha: 0.3),
                  ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: _contrastColor(color),
                )
              : null,
        ),
      ),
    );
  }

  /// Returns white or black depending on luminance.
  static Color _contrastColor(Color color) {
    return color.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
  }
}

/// A swatch that opens a hex color input for custom colors.
class _CustomColorSwatch extends StatefulWidget {
  const _CustomColorSwatch({
    required this.isSelected,
    required this.currentColor,
    required this.onColorSelected,
  });

  final bool isSelected;
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  @override
  State<_CustomColorSwatch> createState() =>
      _CustomColorSwatchState();
}

class _CustomColorSwatchState
    extends State<_CustomColorSwatch> {
  bool _showInput = false;
  late TextEditingController _controller;
  Color? _previewColor;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHexChanged(String value) {
    final color = _parseHex(value);
    setState(() => _previewColor = color);
  }

  void _applyColor() {
    if (_previewColor != null) {
      widget.onColorSelected(_previewColor!);
      setState(() => _showInput = false);
    }
  }

  static Color? _parseHex(String input) {
    var hex = input.trim().replaceFirst('#', '');
    if (hex.length == 6 &&
        RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        Theme.of(context).colorScheme.outline;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Custom color',
          child: InkWell(
            onTap: () =>
                setState(() => _showInput = !_showInput),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Colors.red,
                    Colors.orange,
                    Colors.yellow,
                    Colors.green,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ],
                ),
                border: widget.isSelected
                    ? Border.all(
                        color: borderColor,
                        width: 2.5,
                      )
                    : Border.all(
                        color: borderColor
                            .withValues(alpha: 0.3),
                      ),
              ),
              child: widget.isSelected
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
        if (_showInput) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_previewColor != null)
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _previewColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: borderColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: '#FF5722',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: _onHexChanged,
                  onSubmitted: (_) => _applyColor(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed:
                    _previewColor != null
                        ? _applyColor
                        : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  minimumSize: const Size(0, 36),
                  foregroundColor: colorScheme.primary,
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
