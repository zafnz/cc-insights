import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/git_service.dart';

/// Keys for testing DirectoryValidationDialog widgets.
class DirectoryValidationDialogKeys {
  DirectoryValidationDialogKeys._();

  static const dialog = Key('directory_validation_dialog');
  static const openPrimaryButton = Key('directory_validation_open_primary');
  static const chooseAnotherButton = Key('directory_validation_choose_another');
  static const openAnywayButton = Key('directory_validation_open_anyway');
  static const messageText = Key('directory_validation_message');
  static const pathText = Key('directory_validation_path');
}

/// Result of the directory validation.
enum DirectoryValidationResult {
  /// User chose to open the primary worktree root.
  openPrimary,

  /// User chose to select a different folder.
  chooseDifferent,

  /// User chose to open the directory anyway.
  openAnyway,

  /// User cancelled (closed the dialog without choosing).
  cancelled,
}

/// Shows the directory validation dialog for problematic directory selections.
///
/// Returns [DirectoryValidationResult] indicating the user's choice.
Future<DirectoryValidationResult> showDirectoryValidationDialog({
  required BuildContext context,
  required DirectoryGitInfo gitInfo,
}) async {
  final result = await showDialog<DirectoryValidationResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) => DirectoryValidationDialog(gitInfo: gitInfo),
  );
  return result ?? DirectoryValidationResult.cancelled;
}

/// Dialog shown when the user attempts to open a directory that isn't ideal.
///
/// Handles three scenarios:
/// 1. Directory is a linked worktree (not the primary/repo root)
/// 2. Directory is inside a git repo but not at the top
/// 3. Directory is not a git repo at all
class DirectoryValidationDialog extends StatelessWidget {
  const DirectoryValidationDialog({
    super.key,
    required this.gitInfo,
  });

  final DirectoryGitInfo gitInfo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      key: DirectoryValidationDialogKeys.dialog,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 350),
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
                  child: _buildContent(context, colorScheme),
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
            Icons.info_outline,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Directory Notice',
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

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    final (message, suggestedPath) = _getMessageAndPath();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: DirectoryValidationDialogKeys.messageText,
          message,
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
        ),
        if (suggestedPath != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              key: DirectoryValidationDialogKeys.pathText,
              suggestedPath,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  (String message, String? suggestedPath) _getMessageAndPath() {
    if (!gitInfo.isInGitRepo) {
      // Not a git repo at all
      return (
        'CC Insights works best when working inside a git repository.',
        null,
      );
    }

    if (gitInfo.isLinkedWorktree) {
      // It's a linked worktree, suggest opening the primary
      return (
        'CC Insights works best when opening the primary worktree (repository root).',
        gitInfo.repoRoot,
      );
    }

    if (!gitInfo.isAtWorktreeRoot) {
      // Inside a git repo but not at the top
      return (
        'CC Insights works best when opening the top of the git repository.',
        gitInfo.worktreeRoot,
      );
    }

    // Shouldn't reach here, but just in case
    return ('This directory may not be ideal for CC Insights.', null);
  }

  Widget _buildFooter(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildButtons(context, colorScheme),
      ),
    );
  }

  List<Widget> _buildButtons(BuildContext context, ColorScheme colorScheme) {
    final buttons = <Widget>[];

    // "Open primary worktree root" button - only when relevant
    if (gitInfo.isInGitRepo &&
        (gitInfo.isLinkedWorktree || !gitInfo.isAtWorktreeRoot)) {
      final targetPath = gitInfo.isLinkedWorktree
          ? gitInfo.repoRoot
          : gitInfo.worktreeRoot;

      if (targetPath != null) {
        buttons.add(
          FilledButton.icon(
            key: DirectoryValidationDialogKeys.openPrimaryButton,
            onPressed: () => Navigator.of(context).pop(
              DirectoryValidationResult.openPrimary,
            ),
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Open primary worktree root'),
          ),
        );
        buttons.add(const SizedBox(height: 8));
      }
    }

    // "Choose a different folder" button
    buttons.add(
      OutlinedButton(
        key: DirectoryValidationDialogKeys.chooseAnotherButton,
        onPressed: () => Navigator.of(context).pop(
          DirectoryValidationResult.chooseDifferent,
        ),
        child: const Text('Choose a different folder'),
      ),
    );
    buttons.add(const SizedBox(height: 8));

    // "Open anyway" button
    buttons.add(
      TextButton(
        key: DirectoryValidationDialogKeys.openAnywayButton,
        onPressed: () => Navigator.of(context).pop(
          DirectoryValidationResult.openAnyway,
        ),
        child: const Text('Open anyway'),
      ),
    );

    return buttons;
  }
}

/// A screen widget that displays the directory validation message.
///
/// This is used instead of the welcome screen when the app is launched
/// from CLI with a directory that needs validation.
class DirectoryValidationScreen extends StatelessWidget {
  const DirectoryValidationScreen({
    super.key,
    required this.gitInfo,
    required this.onResult,
  });

  final DirectoryGitInfo gitInfo;
  final ValueChanged<DirectoryValidationResult> onResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final (message, suggestedPath) = _getMessageAndPath();

    return Scaffold(
      key: DirectoryValidationDialogKeys.dialog,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Title image
                Image.asset(
                  'assets/title.png',
                  width: 400,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 48),

                // Message
                Text(
                  key: DirectoryValidationDialogKeys.messageText,
                  message,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Path (if applicable)
                if (suggestedPath != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      key: DirectoryValidationDialogKeys.pathText,
                      suggestedPath,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Buttons
                ..._buildButtons(context, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (String message, String? suggestedPath) _getMessageAndPath() {
    if (!gitInfo.isInGitRepo) {
      return (
        'CC Insights works best when working inside a git repository.',
        null,
      );
    }

    if (gitInfo.isLinkedWorktree) {
      return (
        'CC Insights works best when opening the primary worktree (repository root).',
        gitInfo.repoRoot,
      );
    }

    if (!gitInfo.isAtWorktreeRoot) {
      return (
        'CC Insights works best when opening the top of the git repository.',
        gitInfo.worktreeRoot,
      );
    }

    return ('This directory may not be ideal for CC Insights.', null);
  }

  List<Widget> _buildButtons(BuildContext context, ColorScheme colorScheme) {
    final buttons = <Widget>[];

    // "Open primary worktree root" button - only when relevant
    if (gitInfo.isInGitRepo &&
        (gitInfo.isLinkedWorktree || !gitInfo.isAtWorktreeRoot)) {
      final targetPath = gitInfo.isLinkedWorktree
          ? gitInfo.repoRoot
          : gitInfo.worktreeRoot;

      if (targetPath != null) {
        buttons.add(
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: DirectoryValidationDialogKeys.openPrimaryButton,
              onPressed: () => onResult(DirectoryValidationResult.openPrimary),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Open primary worktree root'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ),
        );
        buttons.add(const SizedBox(height: 12));
      }
    }

    // "Choose a different folder" button
    buttons.add(
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          key: DirectoryValidationDialogKeys.chooseAnotherButton,
          onPressed: () => onResult(DirectoryValidationResult.chooseDifferent),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
          ),
          child: const Text('Choose a different folder'),
        ),
      ),
    );
    buttons.add(const SizedBox(height: 12));

    // "Open anyway" button
    buttons.add(
      SizedBox(
        width: double.infinity,
        child: TextButton(
          key: DirectoryValidationDialogKeys.openAnywayButton,
          onPressed: () => onResult(DirectoryValidationResult.openAnyway),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
          ),
          child: const Text('Open anyway'),
        ),
      ),
    );

    return buttons;
  }
}
