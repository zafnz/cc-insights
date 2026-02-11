import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:flutter/material.dart';

/// Test keys for WorkspaceSettingsPanel widget.
class WorkspaceSettingsPanelKeys {
  static const panel = Key('workspace_settings_panel');
  static const networkAccessToggle = Key('network_access_toggle');
  static const excludeSlashTmpToggle = Key('exclude_slash_tmp_toggle');
  static const excludeTmpdirToggle = Key('exclude_tmpdir_toggle');
  static const addPathButton = Key('add_path_button');
  static const webSearchDropdown = Key('web_search_dropdown');

  static Key removePath(String path) => Key('remove_path_$path');
}

/// Shows the workspace settings panel dialog.
Future<void> showWorkspaceSettingsPanel({
  required BuildContext context,
  required CodexWorkspaceWriteOptions options,
  required CodexWebSearchMode? webSearch,
  required ValueChanged<CodexWorkspaceWriteOptions> onOptionsChanged,
  required ValueChanged<CodexWebSearchMode> onWebSearchChanged,
}) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      child: WorkspaceSettingsPanel(
        options: options,
        webSearch: webSearch,
        onOptionsChanged: onOptionsChanged,
        onWebSearchChanged: onWebSearchChanged,
      ),
    ),
  );
}

/// Fine-grained Codex workspace-write sandbox settings panel.
///
/// Shows toggles and controls for:
/// - Network access
/// - Temp directory exclusions
/// - Additional writable paths
/// - Web search mode
class WorkspaceSettingsPanel extends StatefulWidget {
  const WorkspaceSettingsPanel({
    super.key,
    required this.options,
    required this.webSearch,
    required this.onOptionsChanged,
    required this.onWebSearchChanged,
  });

  final CodexWorkspaceWriteOptions options;
  final CodexWebSearchMode? webSearch;
  final ValueChanged<CodexWorkspaceWriteOptions> onOptionsChanged;
  final ValueChanged<CodexWebSearchMode> onWebSearchChanged;

  @override
  State<WorkspaceSettingsPanel> createState() => _WorkspaceSettingsPanelState();
}

class _WorkspaceSettingsPanelState extends State<WorkspaceSettingsPanel> {
  late CodexWorkspaceWriteOptions _localOptions;

  @override
  void initState() {
    super.initState();
    _localOptions = widget.options;
  }

  void _updateOptions(CodexWorkspaceWriteOptions newOptions) {
    setState(() {
      _localOptions = newOptions;
    });
    widget.onOptionsChanged(newOptions);
  }

  Future<void> _addPath() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add writable path'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '/path/to/directory',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newRoots = [..._localOptions.writableRoots, result];
      _updateOptions(_localOptions.copyWith(writableRoots: newRoots));
    }
  }

  void _removePath(String path) {
    final newRoots = _localOptions.writableRoots.where((p) => p != path).toList();
    _updateOptions(_localOptions.copyWith(writableRoots: newRoots));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      key: WorkspaceSettingsPanelKeys.panel,
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Workspace Write Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Body - scrollable
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Network section
                  _buildSectionLabel('Network'),
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    key: WorkspaceSettingsPanelKeys.networkAccessToggle,
                    label: 'Network access',
                    value: _localOptions.networkAccess,
                    onChanged: (value) {
                      _updateOptions(_localOptions.copyWith(networkAccess: value));
                    },
                    showStateLabel: true,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 132),
                    child: Text(
                      'Allow commands to access the network',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),

                  // Temp directories section
                  _buildSectionLabel('Temp directories'),
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    key: WorkspaceSettingsPanelKeys.excludeSlashTmpToggle,
                    label: 'Exclude /tmp',
                    value: _localOptions.excludeSlashTmp,
                    onChanged: (value) {
                      _updateOptions(_localOptions.copyWith(excludeSlashTmp: value));
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    key: WorkspaceSettingsPanelKeys.excludeTmpdirToggle,
                    label: 'Exclude \$TMPDIR',
                    value: _localOptions.excludeTmpdirEnvVar,
                    onChanged: (value) {
                      _updateOptions(_localOptions.copyWith(excludeTmpdirEnvVar: value));
                    },
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),

                  // Additional writable paths section
                  _buildSectionLabel('Additional writable paths'),
                  const SizedBox(height: 8),
                  ..._localOptions.writableRoots.map((path) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              path,
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 11,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            key: WorkspaceSettingsPanelKeys.removePath(path),
                            onTap: () => _removePath(path),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // Add path button
                  InkWell(
                    key: WorkspaceSettingsPanelKeys.addPathButton,
                    onTap: _addPath,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: colorScheme.outlineVariant,
                                  style: BorderStyle.solid,
                                ),
                              ),
                            ),
                            child: Text(
                              'Add path...',
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.add,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),

                  // Web search section
                  _buildSectionLabel('Web search'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Search mode',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<CodexWebSearchMode>(
                          key: WorkspaceSettingsPanelKeys.webSearchDropdown,
                          value: widget.webSearch ?? CodexWebSearchMode.disabled,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                          dropdownColor: colorScheme.surfaceContainerHigh,
                          underline: Container(
                            height: 1,
                            color: colorScheme.outlineVariant,
                          ),
                          items: CodexWebSearchMode.values.map((mode) {
                            return DropdownMenuItem(
                              value: mode,
                              child: Text(_webSearchModeLabel(mode)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              widget.onWebSearchChanged(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: Colors.white.withValues(alpha: 0.7),
        letterSpacing: 0.02,
      ),
    );
  }

  Widget _buildToggleRow({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool showStateLabel = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _ToggleSwitch(
          key: key,
          value: value,
          onChanged: onChanged,
        ),
        if (showStateLabel) ...[
          const SizedBox(width: 6),
          Text(
            value ? 'Enabled' : 'Disabled',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  String _webSearchModeLabel(CodexWebSearchMode mode) {
    return switch (mode) {
      CodexWebSearchMode.disabled => 'Disabled',
      CodexWebSearchMode.cached => 'Cached (default)',
      CodexWebSearchMode.live => 'Live',
    };
  }
}

/// Custom toggle switch widget.
class _ToggleSwitch extends StatelessWidget {
  const _ToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: value
              ? colorScheme.primaryContainer
              : colorScheme.outlineVariant,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
