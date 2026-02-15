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

part 'settings_screen_inputs.dart';
part 'settings_screen_colors.dart';
part 'settings_screen_tags.dart';
part 'settings_screen_agents.dart';

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

}
