import 'dart:async';

import 'package:claude_sdk/claude_sdk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/chat_model.dart';
import '../models/setting_definition.dart';
import '../models/worktree_tag.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../services/internal_tools_service.dart';
import '../services/runtime_config.dart';
import '../services/settings_service.dart';
import '../state/ticket_board_state.dart';
import '../state/theme_state.dart';
import '../widgets/insights_widgets.dart';

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
              child: InsightsOutlinedButton(
                onPressed: onResetToDefaults,
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
              Expanded(
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
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
    BackendService backendService,
    SettingDefinition definition,
    dynamic value,
  ) {
    if (definition.key == 'session.defaultPermissionMode' &&
        value == 'bypassPermissions') {
      _showBypassWarning(context, settings, definition.key);
      return;
    }

    if (definition.key == 'session.defaultModel') {
      unawaited(settings.setValue(definition.key, value));
      final parsed =
          ChatModelCatalog.parseCompositeModel(value as String);
      if (parsed != null) {
        unawaited(backendService.start(type: parsed.$1));
      }
      return;
    }

    if (definition.key == 'session.claudeCliPath' ||
        definition.key == 'session.codexCliPath' ||
        definition.key == 'session.acpCliPath') {
      unawaited(settings.setValue(definition.key, value));
      // Re-validate CLI availability with new paths
      final cliAvailability = context.read<CliAvailabilityService>();
      unawaited(
        cliAvailability
            .checkAll(
              claudePath: definition.key == 'session.claudeCliPath'
                  ? value as String
                  : RuntimeConfig.instance.claudeCliPath,
              codexPath: definition.key == 'session.codexCliPath'
                  ? value as String
                  : RuntimeConfig.instance.codexCliPath,
              acpPath: definition.key == 'session.acpCliPath'
                  ? value as String
                  : RuntimeConfig.instance.acpCliPath,
            )
            .then((_) {
          RuntimeConfig.instance.codexAvailable =
              cliAvailability.codexAvailable;
          RuntimeConfig.instance.acpAvailable =
              cliAvailability.acpAvailable;
        }),
      );
      return;
    }

    if (definition.key == 'projectMgmt.agentTicketTools') {
      unawaited(settings.setValue(definition.key, value));
      final tools = context.read<InternalToolsService>();
      if (value == true) {
        tools.registerTicketTools(context.read<TicketBoardState>());
      } else {
        tools.unregisterTicketTools();
      }
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
    final backendService = context.watch<BackendService>();

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
          _buildSettingRow(
            context,
            settings,
            backendService,
            category.settings[i],
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

  Widget _buildSettingRow(
    BuildContext context,
    SettingsService settings,
    BackendService backendService,
    SettingDefinition definition,
  ) {
    var effectiveDefinition = definition;
    var value = settings.getEffectiveValue(definition.key);
    var isLoading = false;
    final isOverridden = settings.isOverridden(definition.key);

    // CLI path settings get a file picker button
    if (definition.key == 'session.claudeCliPath' ||
        definition.key == 'session.codexCliPath' ||
        definition.key == 'session.acpCliPath') {
      var cliDefinition = definition;
      if (definition.key == 'session.codexCliPath') {
        final cliAvailability = context.watch<CliAvailabilityService>();
        if (!cliAvailability.codexAvailable) {
          cliDefinition = SettingDefinition(
            key: definition.key,
            title: definition.title,
            description: definition.description,
            type: definition.type,
            defaultValue: definition.defaultValue,
            placeholder: definition.placeholder,
            errorText: 'Codex CLI could not be found.',
          );
        }
      } else if (definition.key == 'session.acpCliPath') {
        final cliAvailability = context.watch<CliAvailabilityService>();
        if (!cliAvailability.acpAvailable) {
          cliDefinition = SettingDefinition(
            key: definition.key,
            title: definition.title,
            description: definition.description,
            type: definition.type,
            defaultValue: definition.defaultValue,
            placeholder: definition.placeholder,
            errorText: 'ACP agent could not be found.',
          );
        }
      }
      return _CliPathSettingRow(
        definition: cliDefinition,
        value: value as String,
        isOverridden: isOverridden,
        onChanged: (value) {
          _handleSettingChanged(
            context,
            settings,
            backendService,
            definition,
            value,
          );
        },
      );
    }

    if (definition.key == 'session.defaultModel') {
      isLoading = backendService.isModelListLoadingFor(BackendType.codex);
      final options = ChatModelCatalog.allModelOptions();

      final currentValue = value as String;
      value = _ensureDropdownValue(currentValue, options);

      effectiveDefinition = SettingDefinition(
        key: definition.key,
        title: definition.title,
        description: definition.description,
        type: definition.type,
        defaultValue: definition.defaultValue,
        options: options,
        min: definition.min,
        max: definition.max,
        placeholder: definition.placeholder,
      );
    }

    return _SettingRow(
      definition: effectiveDefinition,
      value: value,
      isLoading: isLoading,
      isOverridden: isOverridden,
      onChanged: (value) {
        _handleSettingChanged(
          context,
          settings,
          backendService,
          definition,
          value,
        );
      },
    );
  }

  static String _ensureDropdownValue(
    String value,
    List<SettingOption> options,
  ) {
    for (final option in options) {
      if (option.value == value) {
        return value;
      }
    }
    if (options.isEmpty) {
      return value;
    }
    return options.first.value;
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
    this.isLoading = false,
    this.isOverridden = false,
  });

  final SettingDefinition definition;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool isLoading;
  final bool isOverridden;

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
            InsightsDescriptionText(definition.description),
            if (isOverridden) _buildOverrideIndicator(context),
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
                InsightsDescriptionText(definition.description),
                if (definition.errorText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    definition.errorText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (isOverridden) _buildOverrideIndicator(context),
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

  Widget _buildOverrideIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'Overridden via CLI',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return switch (definition.type) {
      SettingType.toggle => _buildToggle(context),
      SettingType.dropdown => _buildDropdown(context, isLoading),
      SettingType.number => InsightsNumberField(
          value: (value as num).toInt(),
          min: definition.min ?? 0,
          max: definition.max ?? 999,
          onChanged: isOverridden ? null : (v) => onChanged(v),
        ),
      SettingType.colorPicker => isOverridden
          ? _buildDisabledColorPreview(context)
          : _ColorPickerInput(
              value: (value as num).toInt(),
              onChanged: onChanged,
              allowDefault: definition.defaultValue == 0,
            ),
      SettingType.text => _TextSettingInput(
          value: value as String,
          placeholder: definition.placeholder,
          enabled: !isOverridden,
          onChanged: onChanged,
        ),
    };
  }

  Widget _buildToggle(BuildContext context) {
    return Transform.scale(
      scale: 0.75,
      child: Switch(
        value: value as bool,
        onChanged: isOverridden ? null : (v) => onChanged(v),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = definition.options ?? [];

    final dropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOverridden
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest,
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
            color: isOverridden
                ? colorScheme.onSurface.withValues(alpha: 0.5)
                : colorScheme.onSurface,
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
          onChanged: isOverridden
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      ),
    );

    if (!isLoading) return dropdown;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dropdown,
        const SizedBox(width: 8),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildDisabledColorPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colorValue = (value as num).toInt();
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colorValue == 0 ? null : Color(colorValue),
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: colorValue == 0
          ? Icon(Icons.auto_awesome, size: 14, color: colorScheme.onSurfaceVariant)
          : null,
    );
  }
}

// ---------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------

class _TextSettingInput extends StatefulWidget {
  const _TextSettingInput({
    required this.value,
    this.placeholder,
    this.enabled = true,
    required this.onChanged,
  });

  final String value;
  final String? placeholder;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_TextSettingInput> createState() => _TextSettingInputState();
}

class _TextSettingInputState extends State<_TextSettingInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextSettingInput oldWidget) {
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
    return SizedBox(
      width: 280,
      child: InsightsTextField(
        controller: _controller,
        hintText: widget.placeholder,
        monospace: true,
        enabled: widget.enabled,
        onSubmitted: widget.enabled ? _submit : null,
        onTapOutside: widget.enabled ? (_) => _submit(_controller.text) : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// CLI path setting row (text input + file picker button)
// ---------------------------------------------------------------------

class _CliPathSettingRow extends StatefulWidget {
  const _CliPathSettingRow({
    required this.definition,
    required this.value,
    required this.onChanged,
    this.isOverridden = false,
  });

  final SettingDefinition definition;
  final String value;
  final ValueChanged<dynamic> onChanged;
  final bool isOverridden;

  @override
  State<_CliPathSettingRow> createState() => _CliPathSettingRowState();
}

class _CliPathSettingRowState extends State<_CliPathSettingRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CliPathSettingRow oldWidget) {
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CLI executable',
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        _controller.text = path;
        _submit(path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);
    final enabled = !widget.isOverridden;

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
                  widget.definition.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                InsightsDescriptionText(widget.definition.description),
                if (widget.definition.errorText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.definition.errorText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (widget.isOverridden)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: colorScheme.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Overridden via CLI',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right: text input + file picker icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _controller,
                  enabled: enabled,
                  style: mono,
                  decoration: InputDecoration(
                    hintText: widget.definition.placeholder,
                    hintStyle: mono.copyWith(
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: enabled ? _submit : null,
                  onTapOutside: enabled
                      ? (_) => _submit(_controller.text)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18),
                tooltip: 'Browse...',
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: enabled ? _pickFile : null,
              ),
            ],
          ),
        ],
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
      widget.onChanged(_previewColor!.toARGB32());
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
                    preset.color.toARGB32() == widget.value,
                onTap: () {
                  widget.onChanged(preset.color.toARGB32());
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
        .every((p) => p.color.toARGB32() != color.toARGB32());
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
                      child: InsightsTextField(
                        controller: _newTagController,
                        hintText: 'New tag name...',
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: InsightsTonalButton(
                      onPressed: _addTag,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
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
