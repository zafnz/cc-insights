import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cli_launcher_service.dart';

/// Keys for testing CliLauncherDialog widgets.
class CliLauncherDialogKeys {
  CliLauncherDialogKeys._();

  static const dialog = Key('cli_launcher_dialog');
  static const installButton = Key('cli_launcher_install');
  static const reinstallButton = Key('cli_launcher_reinstall');
  static const skipButton = Key('cli_launcher_skip');
  static const cancelButton = Key('cli_launcher_cancel');
  static const closeButton = Key('cli_launcher_close');
  static const locationWarning = Key('cli_launcher_location_warning');
  static const successMessage = Key('cli_launcher_success');
  static const errorMessage = Key('cli_launcher_error');
  static const pathHint = Key('cli_launcher_path_hint');
  static const addToPathButton = Key('cli_launcher_add_to_path');
  static const pathAdded = Key('cli_launcher_path_added');
}

/// Result of the CLI launcher dialog.
enum CliLauncherResult { installed, skipped, cancelled }

/// Shows the CLI launcher installation dialog.
///
/// When [isFirstRun] is true, a "Skip" button is shown instead of "Cancel".
Future<CliLauncherResult> showCliLauncherDialog({
  required BuildContext context,
  bool isFirstRun = false,
  // Testing overrides
  LocationCheck Function()? locationCheckOverride,
  Future<String?> Function()? installOverride,
  bool Function()? isInstalledOverride,
  Future<bool> Function()? isCommandInPathOverride,
  Future<String?> Function()? addToPathOverride,
}) async {
  final result = await showDialog<CliLauncherResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) => CliLauncherDialog(
      isFirstRun: isFirstRun,
      locationCheckOverride: locationCheckOverride,
      installOverride: installOverride,
      isInstalledOverride: isInstalledOverride,
      isCommandInPathOverride: isCommandInPathOverride,
      addToPathOverride: addToPathOverride,
    ),
  );
  return result ?? CliLauncherResult.cancelled;
}

enum _DialogState { prompt, installing, success, error }

/// Dialog for installing the CLI launcher script at ~/.local/bin/cc-insights.
class CliLauncherDialog extends StatefulWidget {
  const CliLauncherDialog({
    super.key,
    this.isFirstRun = false,
    this.locationCheckOverride,
    this.installOverride,
    this.isInstalledOverride,
    this.isCommandInPathOverride,
    this.addToPathOverride,
  });

  final bool isFirstRun;

  /// For testing: override location check result.
  final LocationCheck Function()? locationCheckOverride;

  /// For testing: override install function.
  final Future<String?> Function()? installOverride;

  /// For testing: override isInstalled check.
  final bool Function()? isInstalledOverride;

  /// For testing: override isCommandInPath check.
  final Future<bool> Function()? isCommandInPathOverride;

  /// For testing: override addToPath function.
  final Future<String?> Function()? addToPathOverride;

  @override
  State<CliLauncherDialog> createState() => _CliLauncherDialogState();
}

class _CliLauncherDialogState extends State<CliLauncherDialog> {
  late LocationCheck _locationCheck;
  late bool _alreadyInstalled;
  _DialogState _state = _DialogState.prompt;
  String? _errorMessage;
  bool _commandInPath = true; // assume in PATH until checked
  bool _pathAdded = false;

  @override
  void initState() {
    super.initState();
    _locationCheck = widget.locationCheckOverride?.call() ??
        CliLauncherService.checkAppLocation();
    _alreadyInstalled = widget.isInstalledOverride?.call() ??
        CliLauncherService.isInstalled();
  }

  Future<void> _doInstall() async {
    setState(() => _state = _DialogState.installing);

    final error = widget.installOverride != null
        ? await widget.installOverride!()
        : await CliLauncherService.install();

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _state = _DialogState.error;
        _errorMessage = error;
      });
    } else {
      // Check if cc-insights is resolvable from the user's shell
      final inPath = widget.isCommandInPathOverride != null
          ? await widget.isCommandInPathOverride!()
          : await CliLauncherService.isCommandInPath();
      if (!mounted) return;
      setState(() {
        _commandInPath = inPath;
        _state = _DialogState.success;
      });
    }
  }

  Future<void> _doAddToPath() async {
    final error = widget.addToPathOverride != null
        ? await widget.addToPathOverride!()
        : await CliLauncherService.addToPath();

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _state = _DialogState.error;
        _errorMessage = error;
      });
    } else {
      setState(() => _pathAdded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: CliLauncherDialogKeys.dialog,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colorScheme),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildContent(colorScheme),
                ),
              ),
            ),
            _buildFooter(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.terminal,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CLI Launcher',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    switch (_state) {
      case _DialogState.prompt:
        return _buildPromptContent(colorScheme);
      case _DialogState.installing:
        return _buildInstallingContent(colorScheme);
      case _DialogState.success:
        return _buildSuccessContent(colorScheme);
      case _DialogState.error:
        return _buildErrorContent(colorScheme);
    }
  }

  Widget _buildPromptContent(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _alreadyInstalled
              ? 'The CLI launcher is already installed. You can reinstall it to '
                  'update the path if the app has moved.'
              : 'Install a command-line launcher so you can open CC Insights '
                  'from your terminal.',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
        const SizedBox(height: 12),
        // Show the target path
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            CliLauncherService.launcherPath,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // Location warning
        if (!_locationCheck.isSane && _locationCheck.reason != null) ...[
          const SizedBox(height: 12),
          Container(
            key: CliLauncherDialogKeys.locationWarning,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _locationCheck.reason!,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInstallingContent(ColorScheme colorScheme) {
    return Row(
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          'Installing...',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildSuccessContent(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          key: CliLauncherDialogKeys.successMessage,
          children: [
            Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'CLI launcher installed successfully.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Usage:',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'cc-insights /path/to/project',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (!_commandInPath && !_pathAdded) ...[
          const SizedBox(height: 12),
          Container(
            key: CliLauncherDialogKeys.pathHint,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '~/.local/bin is not in your PATH.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: CliLauncherDialogKeys.addToPathButton,
                  onPressed: _doAddToPath,
                  child: const Text('Add to ~/.zshrc'),
                ),
              ],
            ),
          ),
        ],
        if (_pathAdded) ...[
          const SizedBox(height: 12),
          Container(
            key: CliLauncherDialogKeys.pathAdded,
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Added to ~/.zshrc. Restart your terminal to use '
                    'cc-insights.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorContent(ColorScheme colorScheme) {
    return Row(
      key: CliLauncherDialogKeys.errorMessage,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMessage ?? 'An unknown error occurred.',
            style: TextStyle(fontSize: 14, color: colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _buildButtons(context),
      ),
    );
  }

  List<Widget> _buildButtons(BuildContext context) {
    switch (_state) {
      case _DialogState.prompt:
        return [
          // Skip / Cancel button
          TextButton(
            key: widget.isFirstRun
                ? CliLauncherDialogKeys.skipButton
                : CliLauncherDialogKeys.cancelButton,
            onPressed: () => Navigator.of(context).pop(
              widget.isFirstRun
                  ? CliLauncherResult.skipped
                  : CliLauncherResult.cancelled,
            ),
            child: Text(widget.isFirstRun ? 'Skip' : 'Cancel'),
          ),
          const SizedBox(width: 8),
          // Install / Reinstall button
          FilledButton(
            key: _alreadyInstalled
                ? CliLauncherDialogKeys.reinstallButton
                : CliLauncherDialogKeys.installButton,
            onPressed:
                _locationCheck.isSane || !_locationCheck.isAppBundle
                    ? _doInstall
                    : null,
            child: Text(_alreadyInstalled ? 'Reinstall' : 'Install'),
          ),
        ];
      case _DialogState.installing:
        return [];
      case _DialogState.success:
      case _DialogState.error:
        return [
          FilledButton(
            key: CliLauncherDialogKeys.closeButton,
            onPressed: () => Navigator.of(context).pop(
              _state == _DialogState.success
                  ? CliLauncherResult.installed
                  : CliLauncherResult.cancelled,
            ),
            child: const Text('Close'),
          ),
        ];
    }
  }
}
