import 'package:flutter/material.dart';

/// Keys for testing BaseSelectorDialog widgets.
class BaseSelectorDialogKeys {
  BaseSelectorDialogKeys._();

  /// The dialog itself.
  static const dialog = Key('base_selector_dialog');

  /// Radio tile for "main".
  static const mainOption = Key('base_selector_main_option');

  /// Radio tile for "origin/main".
  static const originMainOption = Key('base_selector_origin_main_option');

  /// Radio for "Custom" option.
  static const customOption = Key('base_selector_custom_option');

  /// Text field for custom ref input.
  static const customField = Key('base_selector_custom_field');

  /// The cancel button.
  static const cancelButton = Key('base_selector_cancel');

  /// The apply button.
  static const applyButton = Key('base_selector_apply');
}

/// Shows a dialog to select a base ref for a worktree.
///
/// [currentBase] is the current per-worktree base value,
/// or null if using the default (main).
///
/// Returns the new base value: a ref string like "main" or
/// "origin/main", or null if cancelled.
Future<String?> showBaseSelectorDialog(
  BuildContext context, {
  String? currentBase,
}) async {
  return showDialog<String?>(
    context: context,
    builder: (context) => BaseSelectorDialog(
      currentBase: currentBase,
    ),
  );
}

/// Dialog for selecting a base ref for a worktree.
///
/// Presents radio options for common base refs plus a custom text field.
/// The dialog returns a ref string, [_projectDefaultSentinel] for
/// "use project default", or null if cancelled.
class BaseSelectorDialog extends StatefulWidget {
  const BaseSelectorDialog({
    super.key,
    this.currentBase,
  });

  /// The current per-worktree base, or null if using project default.
  final String? currentBase;

  @override
  State<BaseSelectorDialog> createState() => _BaseSelectorDialogState();
}

/// The selection categories. "custom" means the user typed a freeform ref.
enum _BaseOption { main, originMain, custom }

class _BaseSelectorDialogState extends State<BaseSelectorDialog> {
  late _BaseOption _selected;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    final current = widget.currentBase;
    if (current == null || current == 'main') {
      _selected = _BaseOption.main;
      _customController = TextEditingController();
    } else if (current == 'origin/main') {
      _selected = _BaseOption.originMain;
      _customController = TextEditingController();
    } else {
      _selected = _BaseOption.custom;
      _customController = TextEditingController(text: current);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  /// Resolves the current selection to the value to return from the dialog.
  String? _resolveValue() {
    switch (_selected) {
      case _BaseOption.main:
        return 'main';
      case _BaseOption.originMain:
        return 'origin/main';
      case _BaseOption.custom:
        final text = _customController.text.trim();
        return text.isEmpty ? null : text;
    }
  }

  bool get _canApply {
    if (_selected == _BaseOption.custom) {
      return _customController.text.trim().isNotEmpty;
    }
    return true;
  }

  void _handleApply() {
    final value = _resolveValue();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      key: BaseSelectorDialogKeys.dialog,
      title: const Text('Change Base Ref'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the branch used for merge and diff comparisons '
              'in this worktree.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildRadioTile(
              key: BaseSelectorDialogKeys.mainOption,
              title: 'main',
              value: _BaseOption.main,
              monospace: true,
            ),
            _buildRadioTile(
              key: BaseSelectorDialogKeys.originMainOption,
              title: 'origin/main',
              value: _BaseOption.originMain,
              monospace: true,
            ),
            // Custom option with inline text field
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Radio<_BaseOption>(
                  key: BaseSelectorDialogKeys.customOption,
                  value: _BaseOption.custom,
                  groupValue: _selected,
                  onChanged: (value) {
                    if (value != null) setState(() => _selected = value);
                  },
                ),
                Expanded(
                  child: TextField(
                    key: BaseSelectorDialogKeys.customField,
                    controller: _customController,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Custom',
                      hintStyle: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                        fontFamily: 'JetBrains Mono',
                        fontSize: 13,
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onTap: () {
                      // Select the custom option when tapping the text field
                      if (_selected != _BaseOption.custom) {
                        setState(() => _selected = _BaseOption.custom);
                      }
                    },
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (_canApply) _handleApply();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: BaseSelectorDialogKeys.cancelButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: BaseSelectorDialogKeys.applyButton,
          onPressed: _canApply ? _handleApply : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _buildRadioTile({
    required Key key,
    required String title,
    required _BaseOption value,
    String? subtitle,
    bool monospace = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return RadioListTile<_BaseOption>(
      key: key,
      title: Text(
        title,
        style: monospace
            ? textTheme.bodyMedium?.copyWith(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
              )
            : textTheme.bodyMedium,
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      value: value,
      groupValue: _selected,
      onChanged: (v) {
        if (v != null) setState(() => _selected = v);
      },
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
