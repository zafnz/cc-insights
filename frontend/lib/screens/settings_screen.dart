import 'dart:async';

import 'package:agent_sdk_core/agent_sdk_core.dart'
    show
        CodexApprovalPolicy,
        CodexSandboxMode,
        CodexSecurityCapabilities,
        CodexSecurityConfig;
import 'package:claude_sdk/claude_sdk.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_config.dart';
import '../models/chat_model.dart';
import '../models/project.dart';
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
import '../widgets/security_config_group.dart';

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
    if (definition.key == 'session.defaultModel') {
      unawaited(settings.setValue(definition.key, value));
      final parsed =
          ChatModelCatalog.parseCompositeModel(value as String);
      if (parsed != null) {
        unawaited(backendService.startAgent(settings.defaultAgentId));
      }
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



  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final backendService = context.watch<BackendService>();

    // Custom renderer for tags category.
    if (category.id == 'tags') {
      return _TagsSettingsContent(settings: settings);
    }

    // Custom renderer for agents category.
    if (category.id == 'agents') {
      return _AgentsSettingsContent(settings: settings);
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

// -----------------------------------------------------------------------------
// Agents settings content
// -----------------------------------------------------------------------------

class _AgentsSettingsContent extends StatefulWidget {
  const _AgentsSettingsContent({required this.settings});

  final SettingsService settings;

  @override
  State<_AgentsSettingsContent> createState() => _AgentsSettingsContentState();
}

class _AgentsSettingsContentState extends State<_AgentsSettingsContent> {
  String? _selectedAgentId;

  late TextEditingController _nameController;
  late TextEditingController _cliPathController;
  late TextEditingController _cliArgsController;
  late TextEditingController _environmentController;
  String _driver = 'claude';
  String _defaultModel = 'default';
  String _defaultPermissions = 'default';
  String _codexSandboxMode = 'workspace-write';
  String _codexApprovalPolicy = 'on-request';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _cliPathController = TextEditingController();
    _cliArgsController = TextEditingController();
    _environmentController = TextEditingController();

    // Auto-select the first agent.
    final agents = widget.settings.availableAgents;
    if (agents.isNotEmpty) {
      _selectedAgentId = agents.first.id;
      _loadSelectedAgent();
    }
  }

  @override
  void didUpdateWidget(_AgentsSettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if the selected agent still exists.
    if (_selectedAgentId != null) {
      final agent = widget.settings.agentById(_selectedAgentId!);
      if (agent != null) {
        _loadSelectedAgent();
      } else {
        // Selected agent was removed.
        setState(() {
          _selectedAgentId = null;
          _clearForm();
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cliPathController.dispose();
    _cliArgsController.dispose();
    _environmentController.dispose();
    super.dispose();
  }

  void _loadSelectedAgent() {
    if (_selectedAgentId == null) return;
    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    _nameController.text = agent.name;
    _cliPathController.text = agent.cliPath;
    _cliArgsController.text = agent.cliArgs;
    _environmentController.text = agent.environment;
    _driver = agent.driver;
    final modelOpts = _modelOptionsForDriver(agent.driver);
    _defaultModel = agent.defaultModel.isEmpty && modelOpts.isNotEmpty
        ? modelOpts.first.$1
        : agent.defaultModel;
    _defaultPermissions = agent.defaultPermissions;
    _codexSandboxMode = agent.codexSandboxMode ?? 'workspace-write';
    _codexApprovalPolicy = agent.codexApprovalPolicy ?? 'on-request';
  }

  void _clearForm() {
    _nameController.clear();
    _cliPathController.clear();
    _cliArgsController.clear();
    _environmentController.clear();
    _driver = 'claude';
    _defaultModel = 'default';
    _defaultPermissions = 'default';
    _codexSandboxMode = 'workspace-write';
    _codexApprovalPolicy = 'on-request';
  }

  void _saveCurrentAgent() {
    if (_selectedAgentId == null) return;
    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    final updated = agent.copyWith(
      name: _nameController.text.trim(),
      driver: _driver,
      cliPath: _cliPathController.text.trim(),
      cliArgs: _cliArgsController.text.trim(),
      defaultModel: _defaultModel,
      environment: _environmentController.text,
      defaultPermissions: _defaultPermissions,
      codexSandboxMode: _driver == 'codex' ? _codexSandboxMode : null,
      codexApprovalPolicy: _driver == 'codex' ? _codexApprovalPolicy : null,
    );

    unawaited(widget.settings.updateAgent(updated));

    // Re-check CLI availability when paths or drivers change.
    if (updated.cliPath != agent.cliPath || updated.driver != agent.driver) {
      final cliAvailability = context.read<CliAvailabilityService>();
      unawaited(cliAvailability.checkAgents(RuntimeConfig.instance.agents));
    }
  }

  void _addAgent() {
    final newAgent = AgentConfig(
      id: AgentConfig.generateId(),
      name: 'New Agent',
      driver: 'claude',
      cliPath: '',
      cliArgs: '',
      environment: '',
      defaultModel: 'default',
      defaultPermissions: 'default',
    );

    unawaited(widget.settings.addAgent(newAgent));
    setState(() {
      _selectedAgentId = newAgent.id;
      _loadSelectedAgent();
    });

    // Start backend to discover models for the new agent.
    final backendService = context.read<BackendService>();
    unawaited(backendService.startAgent(newAgent.id, config: newAgent));
  }

  void _removeAgent() {
    if (_selectedAgentId == null) return;

    final agents = widget.settings.availableAgents;
    if (agents.length <= 1) return;

    final agent = widget.settings.agentById(_selectedAgentId!);
    if (agent == null) return;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Agent'),
        content: Text(
          'Are you sure you want to remove agent \'${agent.name}\'?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final agentId = _selectedAgentId!;
              unawaited(widget.settings.removeAgent(agentId));

              // Terminate chats that were using this agent.
              final project = context.read<ProjectState>();
              for (final worktree in project.allWorktrees) {
                for (final chat in worktree.chats) {
                  if (chat.agentId == agentId) {
                    unawaited(chat.terminateForAgentRemoval());
                  }
                }
              }

              // Dispose the backend instance for this agent.
              final backendService = context.read<BackendService>();
              unawaited(backendService.disposeAgent(agentId));

              setState(() {
                _selectedAgentId = null;
                _clearForm();
              });
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _setAsDefault() {
    if (_selectedAgentId == null) return;
    unawaited(widget.settings.setDefaultAgent(_selectedAgentId!));
  }

  Future<void> _pickCliPath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CLI executable',
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        setState(() => _cliPathController.text = path);
        _saveCurrentAgent();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final agents = widget.settings.availableAgents;
    final defaultAgentId = widget.settings.defaultAgentId;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category header
              Text(
                'Agents',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure AI agents and their backend drivers',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // Agent list
              for (final agent in agents) ...[
                _AgentRow(
                  agent: agent,
                  isSelected: agent.id == _selectedAgentId,
                  isDefault: agent.id == defaultAgentId,
                  onTap: () {
                    setState(() {
                      _selectedAgentId = agent.id;
                      _loadSelectedAgent();
                    });
                  },
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
              // Add Agent button
              SizedBox(
                height: 36,
                child: InsightsTonalButton(
                  onPressed: _addAgent,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Agent'),
                ),
              ),
              // Detail form (shown when an agent is selected)
              if (_selectedAgentId != null) ...[
                Divider(
                  height: 48,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                Text(
                  'Agent Configuration',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                _FormField(
                  label: 'Name',
                  child: InsightsTextField(
                    controller: _nameController,
                    hintText: 'Agent name',
                    onSubmitted: (_) => _saveCurrentAgent(),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                const SizedBox(height: 16),
                // Driver
                _FormField(
                  label: 'Driver',
                  child: _buildDropdown(
                    value: _driver,
                    options: const [
                      ('claude', 'Claude'),
                      ('codex', 'Codex'),
                      ('acp', 'ACP'),
                    ],
                    onChanged: (value) {
                      setState(() => _driver = value);
                      _saveCurrentAgent();
                      // Start backend for updated driver to trigger model discovery.
                      if (_selectedAgentId != null) {
                        final bs = context.read<BackendService>();
                        unawaited(bs.startAgent(_selectedAgentId!));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // CLI Path
                Builder(builder: (context) {
                  final cliService = context.watch<CliAvailabilityService>();
                  final isAvailable = _selectedAgentId != null &&
                      cliService.isAgentAvailable(_selectedAgentId!);
                  final resolvedPath = _selectedAgentId != null
                      ? cliService.resolvedPathForAgent(_selectedAgentId!)
                      : null;
                  final showAutoDetected =
                      _cliPathController.text.trim().isEmpty;

                  return _FormField(
                    label: 'CLI Path',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _cliPathController,
                                style: mono,
                                decoration: InputDecoration(
                                  hintText: 'Auto-detect',
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
                                onSubmitted: (_) => _saveCurrentAgent(),
                                onTapOutside: (_) => _saveCurrentAgent(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.folder_open, size: 18),
                              tooltip: 'Browse',
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _pickCliPath,
                            ),
                          ],
                        ),
                        if (showAutoDetected && isAvailable && resolvedPath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              resolvedPath,
                              style: mono.copyWith(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        if (showAutoDetected && !isAvailable && cliService.checked)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _CliNotFoundMessage(driver: _driver),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                // CLI Arguments
                _FormField(
                  label: 'CLI Arguments',
                  child: TextField(
                    controller: _cliArgsController,
                    style: mono,
                    decoration: InputDecoration(
                      hintText: 'Optional',
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
                    onSubmitted: (_) => _saveCurrentAgent(),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                // Default Model (Claude and Codex only — ACP has no model concept)
                if (_driver == 'claude' || _driver == 'codex') ...[
                  const SizedBox(height: 16),
                  Builder(builder: (context) {
                    final bs = context.watch<BackendService>();
                    final isLoading = _selectedAgentId != null &&
                        (bs.isModelListLoadingForAgent(_selectedAgentId!) ||
                            bs.isStartingForAgent(_selectedAgentId!));
                    final modelOpts = _modelOptionsForDriver(_driver);

                    return _FormField(
                      label: 'Default Model',
                      child: isLoading && modelOpts.length <= 1
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Discovering models...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _buildDropdownWithDescriptions(
                              value: modelOpts.any((o) => o.$1 == _defaultModel)
                                  ? _defaultModel
                                  : modelOpts.first.$1,
                              options: modelOpts,
                              onChanged: (value) {
                                setState(() => _defaultModel = value);
                                _saveCurrentAgent();
                              },
                            ),
                    );
                  }),
                ],
                // Default Permissions (Claude only)
                if (_driver == 'claude') ...[
                  const SizedBox(height: 16),
                  _FormField(
                    label: 'Default Permissions',
                    child: _buildDropdown(
                      value: _defaultPermissions,
                      options: const [
                        ('default', 'Default'),
                        ('acceptEdits', 'Accept Edits'),
                        ('plan', 'Plan'),
                        ('bypassPermissions', 'Bypass'),
                      ],
                      onChanged: (value) {
                        setState(() => _defaultPermissions = value);
                        _saveCurrentAgent();
                      },
                    ),
                  ),
                ],
                // Codex security settings
                if (_driver == 'codex') ...[
                  const SizedBox(height: 16),
                  _FormField(
                    label: 'Security',
                    child: SecurityConfigGroup(
                      config: CodexSecurityConfig(
                        sandboxMode:
                            CodexSandboxMode.fromNameOrWire(_codexSandboxMode),
                        approvalPolicy: CodexApprovalPolicy.fromNameOrWire(
                            _codexApprovalPolicy),
                      ),
                      capabilities: CodexSecurityCapabilities(),
                      onConfigChanged: (config) {
                        setState(() {
                          _codexSandboxMode = config.sandboxMode.wireValue;
                          _codexApprovalPolicy =
                              config.approvalPolicy.wireValue;
                        });
                        _saveCurrentAgent();
                      },
                    ),
                  ),
                ],
                // Environment
                _FormField(
                  label: 'Environment',
                  child: TextField(
                    controller: _environmentController,
                    style: mono,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'KEY=VALUE\nONE_PER_LINE',
                      hintStyle: mono.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.all(10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onTapOutside: (_) => _saveCurrentAgent(),
                  ),
                ),
                const SizedBox(height: 24),
                // Action buttons
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_selectedAgentId != defaultAgentId)
                      InsightsTonalButton(
                        onPressed: _setAsDefault,
                        icon: const Icon(Icons.star_outline, size: 16),
                        label: const Text('Set as Default'),
                      ),
                    if (agents.length > 1)
                      InsightsOutlinedButton(
                        onPressed: _removeAgent,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        child: const Text('Remove Agent'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Returns dropdown options for the model field based on driver type.
  ///
  /// Returns tuples of (id, label, description).
  List<(String, String, String)> _modelOptionsForDriver(String driver) {
    switch (driver) {
      case 'claude':
        return ChatModelCatalog.claudeModels
            .map((m) => (m.id, m.label, m.description))
            .toList();
      case 'codex':
        return ChatModelCatalog.codexModels
            .map((m) => (m.id, m.label, m.description))
            .toList();
      default:
        return const [];
    }
  }

  Widget _buildDropdown({
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    return _buildDropdownWithDescriptions(
      value: value,
      options: options.map((o) => (o.$1, o.$2, '')).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownWithDescriptions({
    required String value,
    required List<(String, String, String)> options,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDescriptions = options.any((o) => o.$3.isNotEmpty);

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
          value: value,
          isDense: true,
          isExpanded: true,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          // Show just label + description hint in the collapsed button.
          selectedItemBuilder: hasDescriptions
              ? (context) => options.map((opt) {
                    final desc = opt.$3;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        desc.isNotEmpty ? '${opt.$2}  ·  $desc' : opt.$2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    );
                  }).toList()
              : null,
          items: options
              .map(
                (opt) => DropdownMenuItem<String>(
                  value: opt.$1,
                  child: opt.$3.isNotEmpty
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(opt.$2),
                            Text(
                              opt.$3,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        )
                      : Text(opt.$2),
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

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.isSelected,
    required this.isDefault,
    required this.onTap,
  });

  final AgentConfig agent;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Agent name
              Expanded(
                child: Text(
                  agent.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Driver badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  agent.driver,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Default indicator
              if (isDefault) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.star,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a "CLI not found" message with a clickable install link.
class _CliNotFoundMessage extends StatelessWidget {
  const _CliNotFoundMessage({required this.driver});

  final String driver;

  static const _installUrls = {
    'claude': 'https://docs.anthropic.com/en/docs/claude-code/overview',
    'codex': 'https://github.com/openai/codex',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final driverLabel = driver.substring(0, 1).toUpperCase() + driver.substring(1);
    final installUrl = _installUrls[driver];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.warning_amber_rounded,
          size: 14,
          color: colorScheme.error.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 4),
        Text(
          '$driverLabel CLI not found. ',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.error.withValues(alpha: 0.8),
          ),
        ),
        if (installUrl != null)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(installUrl)),
              child: Text(
                'Install $driverLabel CLI',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
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
