import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cli_availability_service.dart';
import '../services/settings_service.dart';

/// Screen shown when the Claude CLI is not found on the system.
///
/// Displays install instructions, a link to docs, and an input for the
/// user to manually specify the Claude CLI path.
class CliRequiredScreen extends StatefulWidget {
  const CliRequiredScreen({
    super.key,
    required this.cliAvailability,
    required this.settingsService,
    required this.onCliFound,
  });

  final CliAvailabilityService cliAvailability;
  final SettingsService settingsService;
  final VoidCallback onCliFound;

  @override
  State<CliRequiredScreen> createState() => _CliRequiredScreenState();
}

class _CliRequiredScreenState extends State<CliRequiredScreen> {
  final _pathController = TextEditingController();
  String? _error;
  bool _verifying = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Claude CLI executable',
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        _pathController.text = path;
      }
    }
  }

  Future<void> _verify() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Please enter a path to the Claude CLI.');
      return;
    }

    setState(() {
      _error = null;
      _verifying = true;
    });

    // Save the custom path to settings
    await widget.settingsService.setValue('session.claudeCliPath', path);

    // Re-check availability with the new path
    await widget.cliAvailability.checkAll(
      claudePath: path,
      codexPath:
          widget.settingsService.getEffectiveValue<String>('session.codexCliPath'),
    );

    if (!mounted) return;

    if (widget.cliAvailability.claudeAvailable) {
      widget.onCliFound();
    } else {
      setState(() {
        _error = 'Could not find a valid Claude CLI at "$path".';
        _verifying = false;
      });
    }
  }

  Future<void> _retryDefault() async {
    setState(() {
      _error = null;
      _verifying = true;
    });

    // Re-check without custom path (maybe user just installed it)
    await widget.cliAvailability.checkAll(
      codexPath:
          widget.settingsService.getEffectiveValue<String>('session.codexCliPath'),
    );

    if (!mounted) return;

    if (widget.cliAvailability.claudeAvailable) {
      widget.onCliFound();
    } else {
      setState(() {
        _error = 'Claude CLI still not found in PATH.';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 56,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Claude CLI Required',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'CC Insights requires the Claude CLI to function.\n'
                          'Please install it or provide the path to an existing installation.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Install instructions
                  Text(
                    'Install Claude CLI',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (Platform.isMacOS) ...[
                    _CommandBlock(
                      command: 'brew install --cask claude-code',
                      mono: mono,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'or',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CommandBlock(
                      command:
                          'curl -fsSL https://claude.ai/install.sh | bash',
                      mono: mono,
                      colorScheme: colorScheme,
                    ),
                  ] else ...[
                    // Linux / WSL
                    _CommandBlock(
                      command:
                          'curl -fsSL https://claude.ai/install.sh | bash',
                      mono: mono,
                      colorScheme: colorScheme,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://code.claude.com/docs/en/overview',
                        ),
                      ),
                      child: Text(
                        'Learn more at code.claude.com/docs',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Manual path entry
                  Text(
                    'Or specify the path manually',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pathController,
                          style: mono,
                          decoration: InputDecoration(
                            hintText: '/usr/local/bin/claude',
                            hintStyle: mono.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onSubmitted: (_) => _verify(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Browse for Claude CLI',
                        onPressed: _pickFile,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Error message
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _verifying ? null : _retryDefault,
                        child: const Text('Retry Detection'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _verifying ? null : _verify,
                        child: _verifying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Verify & Continue'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A monospace command block with a copy-to-clipboard button.
class _CommandBlock extends StatelessWidget {
  const _CommandBlock({
    required this.command,
    required this.mono,
    required this.colorScheme,
  });

  final String command;
  final TextStyle mono;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(command, style: mono),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy to clipboard',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
