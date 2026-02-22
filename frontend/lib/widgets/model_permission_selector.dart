import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendCapabilities, PermissionMode;
import 'package:flutter/material.dart';

import '../models/chat_model.dart';

/// Keys for testing [ModelPermissionSelector] widgets.
class ModelPermissionSelectorKeys {
  ModelPermissionSelectorKeys._();

  static const container = Key('model_permission_selector');
  static const modelDropdown = Key('model_permission_selector_model');
  static const permissionDropdown = Key('model_permission_selector_permission');
  static const modelLabel = Key('model_permission_selector_model_label');
  static const permissionLabel =
      Key('model_permission_selector_permission_label');
}

/// Reusable widget for selecting a model and permission mode.
///
/// Designed for use across the app: conversation toolbar, run orchestration
/// popup, settings screen, etc. Each backend may have different available
/// options, so the widget accepts the available choices dynamically.
///
/// When [capabilities] indicates a feature is unsupported, the corresponding
/// dropdown is disabled and shows a tooltip explaining why.
class ModelPermissionSelector extends StatelessWidget {
  const ModelPermissionSelector({
    super.key,
    required this.models,
    required this.selectedModelId,
    required this.onModelChanged,
    required this.permissionModes,
    required this.selectedPermissionMode,
    required this.onPermissionModeChanged,
    this.capabilities = const BackendCapabilities(),
    this.direction = Axis.horizontal,
    this.compact = false,
  });

  /// Available models for the current backend.
  final List<ChatModel> models;

  /// Currently selected model ID (matches [ChatModel.id]).
  final String? selectedModelId;

  /// Called when the user selects a different model.
  final ValueChanged<String> onModelChanged;

  /// Available permission modes.
  final List<PermissionMode> permissionModes;

  /// Currently selected permission mode.
  final PermissionMode selectedPermissionMode;

  /// Called when the user selects a different permission mode.
  final ValueChanged<PermissionMode> onPermissionModeChanged;

  /// Backend capabilities - used to enable/disable controls.
  final BackendCapabilities capabilities;

  /// Layout direction for the selectors.
  final Axis direction;

  /// Whether to use a compact layout (no labels, smaller text).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Flexible(
        child: _ModelDropdown(
          models: models,
          selectedModelId: selectedModelId,
          onChanged: onModelChanged,
          enabled: capabilities.supportsModelChange,
          compact: compact,
        ),
      ),
      SizedBox(
        width: direction == Axis.horizontal ? 12 : 0,
        height: direction == Axis.vertical ? 8 : 0,
      ),
      Flexible(
        child: _PermissionDropdown(
          modes: permissionModes,
          selectedMode: selectedPermissionMode,
          onChanged: onPermissionModeChanged,
          enabled: capabilities.supportsPermissionModeChange,
          compact: compact,
        ),
      ),
    ];

    return direction == Axis.horizontal
        ? Row(
            key: ModelPermissionSelectorKeys.container,
            mainAxisSize: MainAxisSize.min,
            children: children,
          )
        : Column(
            key: ModelPermissionSelectorKeys.container,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
  }
}

class _ModelDropdown extends StatelessWidget {
  const _ModelDropdown({
    required this.models,
    required this.selectedModelId,
    required this.onChanged,
    required this.enabled,
    required this.compact,
  });

  final List<ChatModel> models;
  final String? selectedModelId;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Resolve selected value - fall back to first model if no match.
    final effectiveId = models.any((m) => m.id == selectedModelId)
        ? selectedModelId
        : (models.isNotEmpty ? models.first.id : null);

    final dropdown = DropdownButtonFormField<String>(
      key: ModelPermissionSelectorKeys.modelDropdown,
      value: effectiveId,
      decoration: InputDecoration(
        labelText: compact ? null : 'Model',
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 8 : 12,
        ),
        isDense: compact,
      ),
      isExpanded: true,
      style: TextStyle(
        fontSize: compact ? 12 : 14,
        color: colorScheme.onSurface,
      ),
      items: models.map((model) {
        return DropdownMenuItem<String>(
          value: model.id,
          child: Text(
            model.label,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: enabled ? (value) => value != null ? onChanged(value) : null : null,
    );

    if (!enabled) {
      return Tooltip(
        message: 'Model selection not supported by this backend',
        child: dropdown,
      );
    }

    return dropdown;
  }
}

class _PermissionDropdown extends StatelessWidget {
  const _PermissionDropdown({
    required this.modes,
    required this.selectedMode,
    required this.onChanged,
    required this.enabled,
    required this.compact,
  });

  final List<PermissionMode> modes;
  final PermissionMode selectedMode;
  final ValueChanged<PermissionMode> onChanged;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Resolve selected value - fall back to first mode if no match.
    final effectiveMode =
        modes.contains(selectedMode) ? selectedMode : modes.first;

    final dropdown = DropdownButtonFormField<PermissionMode>(
      key: ModelPermissionSelectorKeys.permissionDropdown,
      value: effectiveMode,
      decoration: InputDecoration(
        labelText: compact ? null : 'Permission Mode',
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 8 : 12,
        ),
        isDense: compact,
      ),
      isExpanded: true,
      style: TextStyle(
        fontSize: compact ? 12 : 14,
        color: colorScheme.onSurface,
      ),
      items: modes.map((mode) {
        return DropdownMenuItem<PermissionMode>(
          value: mode,
          child: Text(
            _formatPermissionMode(mode),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: enabled ? (value) => value != null ? onChanged(value) : null : null,
    );

    if (!enabled) {
      return Tooltip(
        message: 'Permission mode changes not supported by this backend',
        child: dropdown,
      );
    }

    return dropdown;
  }

  static String _formatPermissionMode(PermissionMode mode) {
    return switch (mode) {
      PermissionMode.defaultMode => 'Default',
      PermissionMode.acceptEdits => 'Accept Edits',
      PermissionMode.bypassPermissions => 'Bypass Permissions',
      PermissionMode.plan => 'Plan',
    };
  }
}
