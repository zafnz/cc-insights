import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/setting_definition.dart';
import '../models/worktree_tag.dart';
import '../services/settings_service.dart';
import '../state/theme_state.dart';

/// Settings screen with sidebar navigation and generic setting renderers.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _selectedCategoryId = SettingsService.categories.first.id;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Row(
          children: [
            _SettingsSidebar(
              categories: SettingsService.categories,
              selectedCategoryId: _selectedCategoryId,
              onCategorySelected: (id) {
                setState(() => _selectedCategoryId = id);
              },
              onResetToDefaults: () => _confirmReset(context, settings),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
            ),
            Expanded(
              child: _SettingsContent(
                category: SettingsService.categories.firstWhere(
                  (c) => c.id == _selectedCategoryId,
                ),
                settings: settings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context, SettingsService settings) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text(
          'This will reset all settings to their default values. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              settings.resetToDefaults();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar
// -----------------------------------------------------------------------------

class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.onResetToDefaults,
  });

  final List<SettingCategory> categories;
  final String selectedCategoryId;
  final ValueChanged<String> onCategorySelected;
  final VoidCallback onResetToDefaults;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              'Settings',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          // Category list
          for (final category in categories)
            _CategoryTile(
              category: category,
              isSelected: category.id == selectedCategoryId,
              onTap: () => onCategorySelected(category.id),
            ),
          const Spacer(),
          // Footer
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onResetToDefaults,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  side: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('Reset to Defaults'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final SettingCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: isSelected ? colorScheme.primary : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                category.icon,
                size: 16,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Text(
                category.label,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Content area
// -----------------------------------------------------------------------------

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.category,
    required this.settings,
  });

  final SettingCategory category;
  final SettingsService settings;

  void _handleSettingChanged(
    BuildContext context,
    SettingsService settings,
    SettingDefinition definition,
    dynamic value,
  ) {
    if (definition.key == 'session.defaultPermissionMode' &&
        value == 'bypassPermissions') {
      _showBypassWarning(context, settings, definition.key);
      return;
    }
    settings.setValue(definition.key, value);
  }

  static void _showBypassWarning(
    BuildContext context,
    SettingsService settings,
    String key,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
          size: 48,
        ),
        title: const Text('Enable Bypass Mode?'),
        content: const SizedBox(
          width: 400,
          child: Text(
            'Bypass mode approves all tool operations without asking '
            'for permission. This means Claude can read, write, and '
            'delete files, execute arbitrary commands, and access '
            'the network without any confirmation.\n\n'
            'This is dangerous and should only be used in isolated '
            'environments where you fully trust the operations '
            'being performed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              settings.setValue(key, 'bypassPermissions');
            },
            child: const Text('Enable Bypass'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Custom renderer for tags category.
    if (category.id == 'tags') {
      return _TagsSettingsContent(settings: settings);
    }


    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        // Category header
        Text(
          category.label,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          category.description,
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        // Setting rows
        for (var i = 0; i < category.settings.length; i++) ...[
          _SettingRow(
            definition: category.settings[i],
            value: settings.getValue(category.settings[i].key),
            onChanged: (value) {
              _handleSettingChanged(
                context,
                settings,
                category.settings[i],
                value,
              );
            },
          ),
          if (i < category.settings.length - 1)
            Divider(
              height: 48,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Generic setting row
// -----------------------------------------------------------------------------

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.definition,
    required this.value,
    required this.onChanged,
  });

  final SettingDefinition definition;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Color picker uses a stacked layout (title + description
    // above, picker below) because it needs more width.
    if (definition.type == SettingType.colorPicker) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              definition.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            _DescriptionText(definition.description),
            const SizedBox(height: 12),
            _buildInput(context),
          ],
        ),
      );
    }


    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: title + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                _DescriptionText(definition.description),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right: input widget
          _buildInput(context),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return switch (definition.type) {
      SettingType.toggle => _buildToggle(context),
      SettingType.dropdown => _buildDropdown(context),
      SettingType.number => _NumberInput(
          value: (value as num).toInt(),
          min: definition.min ?? 0,
          max: definition.max ?? 999,
          onChanged: onChanged,
        ),
      SettingType.colorPicker => _ColorPickerInput(
          value: (value as num).toInt(),
          onChanged: onChanged,
          allowDefault: definition.defaultValue == 0,
        ),
      SettingType.text => _TextInput(
          value: value as String,
          placeholder: definition.placeholder,
          onChanged: onChanged,
        ),
    };
  }

  Widget _buildToggle(BuildContext context) {
    return Transform.scale(
      scale: 0.75,
      child: Switch(
        value: value as bool,
        onChanged: (v) => onChanged(v),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = definition.options ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value as String,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          items: options
              .map(
                (opt) => DropdownMenuItem<String>(
                  value: opt.value,
                  child: Text(opt.label),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Description text with inline `code` spans
// -----------------------------------------------------------------------------

class _DescriptionText extends StatelessWidget {
  const _DescriptionText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
        children: _parseInlineCode(context),
      ),
    );
  }

  List<InlineSpan> _parseInlineCode(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final codePattern = RegExp(r'`([^`]+)`');
    var lastEnd = 0;

    for (final match in codePattern.allMatches(text)) {
      // Text before the code span
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      // Code span
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(1)!,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }

    // Remaining text after last code span
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans;
  }
}

// -----------------------------------------------------------------------------
// Number input
// -----------------------------------------------------------------------------

class _NumberInput extends StatefulWidget {
  const _NumberInput({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_NumberInput> createState() => _NumberInputState();
}

class _NumberInputState extends State<_NumberInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_NumberInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final parsed = int.tryParse(text);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _controller.text = clamped.toString();
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 80,
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colorScheme.primary),
          ),
        ),
        onSubmitted: _submit,
        onTapOutside: (_) => _submit(_controller.text),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------

class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.value,
    this.placeholder,
    required this.onChanged,
  });

  final String value;
  final String? placeholder;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 280,
      child: TextField(
        controller: _controller,
        style: TextStyle(
          fontSize: 13,
          fontFamily: 'JetBrains Mono',
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.placeholder,
          hintStyle: TextStyle(
            fontSize: 13,
            fontFamily: 'JetBrains Mono',
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: colorScheme.primary),
          ),
        ),
        onSubmitted: _submit,
        onTapOutside: (_) => _submit(_controller.text),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Color picker input
// ---------------------------------------------------------------------

class _ColorPickerInput extends StatefulWidget {
  const _ColorPickerInput({
    required this.value,
    required this.onChanged,
    this.allowDefault = false,
  });

  final int value;
  final ValueChanged<dynamic> onChanged;

  /// When true, shows a "Default" swatch that sets the value
  /// to 0 (meaning "use the accent color").
  final bool allowDefault;

  @override
  State<_ColorPickerInput> createState() =>
      _ColorPickerInputState();
}

class _ColorPickerInputState extends State<_ColorPickerInput> {
  bool _showHexInput = false;
  late TextEditingController _hexController;
  Color? _previewColor;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _onHexChanged(String value) {
    final color = _parseHex(value);
    setState(() => _previewColor = color);
  }

  void _applyHex() {
    if (_previewColor != null) {
      widget.onChanged(_previewColor!.value);
      setState(() => _showHexInput = false);
    }
  }

  static Color? _parseHex(String input) {
    final hex = input.trim().replaceFirst('#', '');
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
    final currentColor = Color(widget.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.allowDefault)
              _DefaultColorSwatch(
                isSelected: widget.value == 0,
                onTap: () {
                  widget.onChanged(0);
                  setState(() => _showHexInput = false);
                },
              ),
            for (final preset in ThemePresetColor.values)
              _ColorSwatch(
                color: preset.color,
                tooltip: preset.label,
                isSelected:
                    widget.value != 0 &&
                    preset.color.value == widget.value,
                onTap: () {
                  widget.onChanged(preset.color.value);
                  setState(() => _showHexInput = false);
                },
              ),
            // Custom color button
            Tooltip(
              message: 'Custom color',
              child: InkWell(
                onTap: () => setState(
                  () => _showHexInput = !_showHexInput,
                ),
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
                    border: _isCustomColor(currentColor)
                        ? Border.all(
                            color: borderColor,
                            width: 2.5,
                          )
                        : Border.all(
                            color: borderColor
                                .withValues(alpha: 0.3),
                          ),
                  ),
                  child: _isCustomColor(currentColor)
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (_showHexInput) ...[
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
                  controller: _hexController,
                  decoration: const InputDecoration(
                    hintText: '#FF5722',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: _onHexChanged,
                  onSubmitted: (_) => _applyHex(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed:
                    _previewColor != null
                        ? _applyHex
                        : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool _isCustomColor(Color color) {
    if (widget.value == 0) return false;
    return ThemePresetColor.values
        .every((p) => p.color.value != color.value);
  }
}

// ---------------------------------------------------------------------
// Color swatch circle
// ---------------------------------------------------------------------

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
                ? Border.all(
                    color: borderColor,
                    width: 2.5,
                  )
                : Border.all(
                    color: borderColor
                        .withValues(alpha: 0.3),
                  ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// "Default" swatch (uses accent color)
// ---------------------------------------------------------------------

class _DefaultColorSwatch extends StatelessWidget {
  const _DefaultColorSwatch({
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outline;

    return Tooltip(
      message: 'Default (accent color)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: borderColor,
                    width: 2.5,
                  )
                : Border.all(
                    color: borderColor
                        .withValues(alpha: 0.3),
                  ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: colorScheme.onSurface,
                )
              : Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tags settings content
// -----------------------------------------------------------------------------

class _TagsSettingsContent extends StatefulWidget {
  const _TagsSettingsContent({required this.settings});

  final SettingsService settings;

  @override
  State<_TagsSettingsContent> createState() => _TagsSettingsContentState();
}

class _TagsSettingsContentState extends State<_TagsSettingsContent> {
  final _newTagController = TextEditingController();
  int _newTagColor = WorktreeTag.presetColors.first;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final name = _newTagController.text.trim().toLowerCase();
    if (name.isEmpty) return;

    final existing = widget.settings.availableTags;
    if (existing.any((t) => t.name == name)) return;

    widget.settings.addTag(WorktreeTag(name: name, colorValue: _newTagColor));
    _newTagController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tags = widget.settings.availableTags;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tags',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage worktree tags and their colors',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // Existing tags
              for (final tag in tags) ...[
                _TagRow(
                  tag: tag,
                  onColorChanged: (color) {
                    widget.settings.updateTag(
                      tag.name,
                      tag.copyWith(colorValue: color),
                    );
                  },
                  onDelete: () => widget.settings.removeTag(tag.name),
                ),
                const SizedBox(height: 8),
              ],
              if (tags.isNotEmpty)
                Divider(
                  height: 32,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              // Add new tag row
              Row(
                children: [
                  _ColorDot(
                    colorValue: _newTagColor,
                    size: 24,
                    onTap: () async {
                      final picked = await _showColorPicker(
                        context,
                        _newTagColor,
                      );
                      if (picked != null) {
                        setState(() => _newTagColor = picked);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _newTagController,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: 'New tag name...',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: FilledButton.tonalIcon(
                      onPressed: _addTag,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: FilledButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.onColorChanged,
    required this.onDelete,
  });

  final WorktreeTag tag;
  final ValueChanged<int> onColorChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _ColorDot(
          colorValue: tag.colorValue,
          size: 24,
          onTap: () async {
            final picked = await _showColorPicker(
              context,
              tag.colorValue,
            );
            if (picked != null) {
              onColorChanged(picked);
            }
          },
        ),
        const SizedBox(width: 12),
        // Tag pill preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tag.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tag.color.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 12,
              color: tag.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onDelete,
          icon: Icon(
            Icons.close,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          constraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          padding: EdgeInsets.zero,
          tooltip: 'Remove tag',
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.colorValue,
    required this.size,
    required this.onTap,
  });

  final int colorValue;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: 'Change color',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Color(colorValue),
            shape: BoxShape.circle,
            border: Border.all(
              color: Color(colorValue).withValues(alpha: 0.6),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a color picker popup and returns the chosen color, or null.
Future<int?> _showColorPicker(BuildContext context, int currentColor) async {
  final colorScheme = Theme.of(context).colorScheme;
  final renderBox = context.findRenderObject() as RenderBox?;
  if (renderBox == null) return null;

  final position = renderBox.localToGlobal(Offset.zero);

  return showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy + renderBox.size.height + 4,
      position.dx + 1,
      position.dy + renderBox.size.height + 5,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: colorScheme.primary.withValues(alpha: 0.5),
      ),
    ),
    color: colorScheme.surfaceContainerHigh,
    menuPadding: const EdgeInsets.all(8),
    items: [
      PopupMenuItem<int>(
        enabled: false,
        height: 0,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 160,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: WorktreeTag.presetColors.map((c) {
              final isSelected = c == currentColor;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Color(c).withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ],
  );
}
