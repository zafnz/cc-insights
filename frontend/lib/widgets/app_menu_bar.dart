import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/runtime_config.dart';

/// Callbacks for menu actions that need to be handled by the parent widget.
class MenuCallbacks {
  // Project menu
  final VoidCallback? onOpenProject;
  final VoidCallback? onProjectSettings;
  final VoidCallback? onCloseProject;

  // Worktree menu
  final VoidCallback? onNewWorktree;
  final VoidCallback? onRestoreWorktree;
  final VoidCallback? onDeleteWorktree;
  final VoidCallback? onNewChat;

  // Worktree > Actions submenu
  final VoidCallback? onActionTest;
  final VoidCallback? onActionRun;

  // Worktree > Git submenu
  final VoidCallback? onGitStageCommit;
  final VoidCallback? onGitRebase;
  final VoidCallback? onGitMerge;
  final VoidCallback? onGitMergeIntoMain;
  final VoidCallback? onGitPush;
  final VoidCallback? onGitPull;
  final VoidCallback? onGitCreatePR;

  // View menu
  final VoidCallback? onShowWorkspace;
  final VoidCallback? onShowFileManager;
  final VoidCallback? onShowSettings;
  final VoidCallback? onShowLogs;
  final VoidCallback? onShowStats;

  // Panels
  final VoidCallback? onToggleMergeChatsAgents;

  /// Whether the chats and agents panels are currently merged.
  final bool agentsMergedIntoChats;

  const MenuCallbacks({
    this.onOpenProject,
    this.onProjectSettings,
    this.onCloseProject,
    this.onNewWorktree,
    this.onRestoreWorktree,
    this.onDeleteWorktree,
    this.onNewChat,
    this.onActionTest,
    this.onActionRun,
    this.onGitStageCommit,
    this.onGitRebase,
    this.onGitMerge,
    this.onGitMergeIntoMain,
    this.onGitPush,
    this.onGitPull,
    this.onGitCreatePR,
    this.onShowWorkspace,
    this.onShowFileManager,
    this.onShowSettings,
    this.onShowLogs,
    this.onShowStats,
    this.onToggleMergeChatsAgents,
    this.agentsMergedIntoChats = false,
  });
}

/// Application menu bar using Flutter's PlatformMenuBar.
///
/// On macOS, this integrates with the native menu bar at the top of the screen.
/// On Windows/Linux, behavior may vary based on platform support.
///
/// Menu structure:
/// - CC Insights: About, Settings, Quit
/// - Project: Open, Settings, Close
/// - Edit: Standard undo/redo/cut/copy/paste/select all
/// - Worktree: New Worktree, Delete Worktree, New Chat, Actions submenu, Git submenu
/// - View: Workspace, File Manager, Settings
/// - Help: GitHub, Report Bug, View Logs
class AppMenuBar extends StatelessWidget {
  final Widget child;
  final MenuCallbacks callbacks;

  /// Whether a project is currently open.
  /// When false, project-specific menu items are disabled.
  final bool hasProject;

  const AppMenuBar({
    super.key,
    required this.child,
    required this.callbacks,
    this.hasProject = false,
  });

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        // App menu (CC Insights)
        PlatformMenu(
          label: 'CC Insights',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'About CC Insights',
                  onSelected: () => _showAboutDialog(context),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Settings...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: callbacks.onShowSettings,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Quit CC Insights',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyQ,
                    meta: true,
                  ),
                  onSelected: () => _quitApp(),
                ),
              ],
            ),
          ],
        ),

        // Project menu
        PlatformMenu(
          label: 'Project',
          menus: [
            PlatformMenuItem(
              label: 'Open Project...',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: callbacks.onOpenProject,
            ),
            PlatformMenuItem(
              label: 'Project Settings...',
              onSelected: hasProject ? callbacks.onProjectSettings : null,
            ),
            PlatformMenuItem(
              label: 'Close Project',
              onSelected: hasProject ? callbacks.onCloseProject : null,
            ),
          ],
        ),

        // Edit menu (standard entries)
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Undo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                  ),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Redo',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyZ,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: () {},
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyX,
                    meta: true,
                  ),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyC,
                    meta: true,
                  ),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyV,
                    meta: true,
                  ),
                  onSelected: () {},
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyA,
                    meta: true,
                  ),
                  onSelected: () {},
                ),
              ],
            ),
          ],
        ),

        // Worktree menu
        PlatformMenu(
          label: 'Worktree',
          menus: [
            // Worktree operations group
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'New Worktree...',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyN,
                    meta: true,
                  ),
                  onSelected: hasProject ? callbacks.onNewWorktree : null,
                ),
                PlatformMenuItem(
                  label: 'Restore Worktree...',
                  onSelected: hasProject ? callbacks.onRestoreWorktree : null,
                ),
                PlatformMenuItem(
                  label: 'Delete Worktree...',
                  onSelected: null, // Not wired up yet
                ),
                PlatformMenuItem(
                  label: 'New Chat',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyN,
                    meta: true,
                    shift: true,
                  ),
                  onSelected: hasProject ? callbacks.onNewChat : null,
                ),
              ],
            ),
            // Actions submenu
            PlatformMenuItemGroup(
              members: [
                PlatformMenu(
                  label: 'Actions',
                  menus: [
                    PlatformMenuItem(
                      label: 'Test',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.digit1,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onActionTest : null,
                    ),
                    PlatformMenuItem(
                      label: 'Run',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.digit2,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onActionRun : null,
                    ),
                  ],
                ),
                // Git submenu
                PlatformMenu(
                  label: 'Git',
                  menus: [
                    PlatformMenuItem(
                      label: 'Stage & Commit',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyC,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitStageCommit : null,
                    ),
                    PlatformMenuItem(
                      label: 'Rebase',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyR,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitRebase : null,
                    ),
                    PlatformMenuItem(
                      label: 'Merge',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyM,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitMerge : null,
                    ),
                    PlatformMenuItem(
                      label: 'Merge into Main',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyI,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitMergeIntoMain : null,
                    ),
                    PlatformMenuItem(
                      label: 'Push',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyS,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitPush : null,
                    ),
                    PlatformMenuItem(
                      label: 'Pull',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyL,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitPull : null,
                    ),
                    PlatformMenuItem(
                      label: 'Create PR',
                      shortcut: const SingleActivator(
                        LogicalKeyboardKey.keyP,
                        meta: true,
                        shift: true,
                      ),
                      onSelected: hasProject ? callbacks.onGitCreatePR : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),

        // View menu
        PlatformMenu(
          label: 'View',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Main Screen',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit1,
                    meta: true,
                  ),
                  onSelected: hasProject ? callbacks.onShowWorkspace : null,
                ),
                PlatformMenuItem(
                  label: 'File Manager',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit2,
                    meta: true,
                  ),
                  onSelected: hasProject ? callbacks.onShowFileManager : null,
                ),
                PlatformMenuItem(
                  label: 'Settings',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit3,
                    meta: true,
                  ),
                  onSelected: callbacks.onShowSettings,
                ),
                PlatformMenuItem(
                  label: 'Project Stats',
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.digit5,
                    meta: true,
                  ),
                  onSelected: hasProject ? callbacks.onShowStats : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: callbacks.agentsMergedIntoChats
                      ? 'Split Chats & Agents'
                      : 'Merge Chats & Agents',
                  onSelected:
                      hasProject ? callbacks.onToggleMergeChatsAgents : null,
                ),
              ],
            ),
            PlatformMenuItem(
              label: 'Logs',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.digit4,
                meta: true,
              ),
              onSelected: callbacks.onShowLogs,
            ),
          ],
        ),

        // Help menu
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'CC Insights GitHub',
              onSelected: () => _openUrl('https://github.com/zafnz/cc-insights/'),
            ),
            PlatformMenuItem(
              label: 'Report Bug',
              onSelected: () => _openUrl('https://github.com/zafnz/cc-insights/issues/new'),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'View Logs',
                  onSelected: () => _openLogFile(),
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'CC Insights',
      applicationVersion: '2.0.0',
      applicationLegalese: '© 2024 CC Insights',
      children: [
        const SizedBox(height: 16),
        const Text(
          'Desktop application for monitoring and interacting '
          'with Claude Code agents.',
        ),
      ],
    );
  }

  void _quitApp() {
    SystemNavigator.pop();
  }

  /// Opens a URL in the system's default browser.
  void _openUrl(String url) {
    launchUrl(Uri.parse(url));
  }

  /// Opens the log file using the system's default handler.
  void _openLogFile() {
    final logPath = _expandPath(RuntimeConfig.instance.loggingFilePath);
    if (logPath.isEmpty) {
      debugPrint('No log file path configured');
      return;
    }

    final file = File(logPath);
    if (!file.existsSync()) {
      debugPrint('Log file does not exist: $logPath');
      return;
    }

    // Use launchUrl with file:// scheme to open with system default handler
    launchUrl(Uri.file(logPath));
  }

  /// Expands ~ to home directory in a path.
  String _expandPath(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('~/')) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return home + path.substring(1);
      }
    } else if (path == '~') {
      return Platform.environment['HOME'] ?? path;
    }
    return path;
  }
}
