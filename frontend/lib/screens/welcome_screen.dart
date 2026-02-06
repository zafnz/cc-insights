import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/git_service.dart';
import '../services/persistence_models.dart';
import '../services/persistence_service.dart';
import '../widgets/directory_validation_dialog.dart';
import '../widgets/insights_widgets.dart';

/// Callback when a project directory is selected.
typedef OnProjectSelected = void Function(String projectPath);

/// Welcome screen shown when the app is launched without a CLI context.
///
/// Displays:
/// - The CC Insights title image
/// - A list of recent projects (if any)
/// - A button to select a new project folder
class WelcomeScreen extends StatefulWidget {
  /// Callback when a project is selected.
  final OnProjectSelected onProjectSelected;

  const WelcomeScreen({
    super.key,
    required this.onProjectSelected,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  ProjectsIndex? _projectsIndex;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecentProjects();
  }

  Future<void> _loadRecentProjects() async {
    try {
      final persistence = PersistenceService();
      final index = await persistence.loadProjectsIndex();
      if (mounted) {
        setState(() {
          _projectsIndex = index;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Project Folder',
    );

    if (result != null) {
      await _validateAndOpenDirectory(result);
    }
  }

  /// Validates a directory and either opens it or shows the validation dialog.
  Future<void> _validateAndOpenDirectory(String path) async {
    // Analyze the directory using git service
    const gitService = RealGitService();
    final gitInfo = await gitService.analyzeDirectory(path);

    if (!mounted) return;

    // Check if the directory is ideal (primary worktree at root)
    if (gitInfo.isPrimaryWorktreeRoot) {
      // Ideal case - proceed directly
      widget.onProjectSelected(path);
      return;
    }

    // Show validation dialog for problematic directories
    final dialogResult = await showDirectoryValidationDialog(
      context: context,
      gitInfo: gitInfo,
    );

    if (!mounted) return;

    switch (dialogResult) {
      case DirectoryValidationResult.openPrimary:
        // User chose to open the primary/repo root
        final targetPath = gitInfo.isLinkedWorktree
            ? gitInfo.repoRoot
            : gitInfo.worktreeRoot;

        if (targetPath != null) {
          widget.onProjectSelected(targetPath);
        }
        break;

      case DirectoryValidationResult.chooseDifferent:
        // User wants to choose a different folder - re-show the picker
        await _selectFolder();
        break;

      case DirectoryValidationResult.openAnyway:
        // User chose to proceed with the current directory
        widget.onProjectSelected(path);
        break;

      case DirectoryValidationResult.cancelled:
        // User cancelled - do nothing, stay on welcome screen
        break;
    }
  }

  void _selectProject(String projectPath) {
    // Verify the project still exists
    final dir = Directory(projectPath);
    if (!dir.existsSync()) {
      showErrorSnackBar(
        context,
        'Project folder no longer exists: $projectPath',
      );
      return;
    }
    widget.onProjectSelected(projectPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
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

                // Welcome text
                Text(
                  'Welcome to CC Insights',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monitor and interact with Claude Code agents',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // Open folder button
                FilledButton.icon(
                  onPressed: _selectFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Project Folder'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Recent projects section
                if (_isLoading)
                  const CircularProgressIndicator()
                else if (_error != null)
                  Text(
                    'Error loading recent projects: $_error',
                    style: TextStyle(color: colorScheme.error),
                  )
                else
                  _buildRecentProjects(theme, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentProjects(ThemeData theme, ColorScheme colorScheme) {
    final projects = _projectsIndex?.projects ?? {};

    if (projects.isEmpty) {
      return Text(
        'No recent projects',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Sort by project path (most recently used would be better, but we don't
    // track that yet)
    final sortedEntries = projects.entries.toList()
      ..sort((a, b) => a.value.name.compareTo(b.value.name));

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Recent Projects',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                final projectPath = entry.key;
                final projectInfo = entry.value;

                return _RecentProjectTile(
                  projectPath: projectPath,
                  projectInfo: projectInfo,
                  onTap: () => _selectProject(projectPath),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A tile displaying a recent project.
class _RecentProjectTile extends StatelessWidget {
  final String projectPath;
  final ProjectInfo projectInfo;
  final VoidCallback onTap;

  const _RecentProjectTile({
    required this.projectPath,
    required this.projectInfo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Check if project directory exists
    final exists = Directory(projectPath).existsSync();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.folder,
          color: exists ? colorScheme.primary : colorScheme.outline,
        ),
        title: Text(
          projectInfo.name,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: exists ? null : colorScheme.outline,
          ),
        ),
        subtitle: Text(
          _abbreviatePath(projectPath),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: exists
                ? colorScheme.onSurfaceVariant
                : colorScheme.outline.withValues(alpha: 0.7),
          ),
        ),
        trailing: exists
            ? Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              )
            : Tooltip(
                message: 'Project folder not found',
                child: Icon(
                  Icons.warning_amber,
                  color: colorScheme.error,
                  size: 20,
                ),
              ),
        enabled: exists,
        onTap: exists ? onTap : null,
      ),
    );
  }

  /// Abbreviates a path by replacing the home directory with ~.
  String _abbreviatePath(String path) {
    final home = Platform.environment['HOME'];
    if (home != null && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}
