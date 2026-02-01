import 'package:flutter/material.dart';

/// Keys for testing EditActionDialog widgets.
class EditActionDialogKeys {
  EditActionDialogKeys._();

  /// The dialog itself.
  static const dialog = Key('edit_action_dialog');

  /// The command text field.
  static const commandField = Key('edit_action_command_field');

  /// The cancel button.
  static const cancelButton = Key('edit_action_cancel');

  /// The save button.
  static const saveButton = Key('edit_action_save');
}

/// Shows a dialog to configure an action command.
///
/// Returns the new command string, or null if cancelled.
Future<String?> showEditActionDialog(
  BuildContext context, {
  required String actionName,
  String? currentCommand,
  String? workingDirectory,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => EditActionDialog(
      actionName: actionName,
      initialCommand: currentCommand,
      workingDirectory: workingDirectory,
    ),
  );
}

/// Dialog for editing an action's command.
class EditActionDialog extends StatefulWidget {
  const EditActionDialog({
    super.key,
    required this.actionName,
    this.initialCommand,
    this.workingDirectory,
  });

  /// The name of the action being configured (e.g., "Test", "Run").
  final String actionName;

  /// The current command, or null if not yet configured.
  final String? initialCommand;

  /// The working directory where the command will run.
  final String? workingDirectory;

  @override
  State<EditActionDialog> createState() => _EditActionDialogState();
}

class _EditActionDialogState extends State<EditActionDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCommand ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      key: EditActionDialogKeys.dialog,
      title: Text('Configure "${widget.actionName}" Action'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Command',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: EditActionDialogKeys.commandField,
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: './script.sh',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: 'Shell command to execute',
                  helperStyle: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'JetBrains Mono',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Command is required';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _handleSave(),
              ),
              if (widget.workingDirectory != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Runs in: ${widget.workingDirectory}',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: EditActionDialogKeys.cancelButton,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: EditActionDialogKeys.saveButton,
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
