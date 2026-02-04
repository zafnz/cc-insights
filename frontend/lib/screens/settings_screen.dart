import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/setting_definition.dart';
import '../services/settings_service.dart';

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

    return Row(
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
              settings.setValue(category.settings[i].key, value);
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
