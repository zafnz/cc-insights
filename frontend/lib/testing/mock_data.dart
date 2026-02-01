import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import '../models/conversation.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import 'message_log_player.dart';

/// Configurable base path for mock data.
///
/// Set this before creating mock projects to use a custom path instead of
/// the default `/tmp/cc-insights`. Useful for integration tests that need
/// to use a real directory or avoid conflicts with parallel tests.
///
/// Example:
/// ```dart
/// mockDataProjectPath = '/var/folders/xyz/cc-insights-test';
/// final project = MockDataFactory.createMockProject();
/// ```
String mockDataProjectPath = '/tmp/cc-insights';

/// Factory class for creating mock data for testing purposes.
///
/// Provides static methods to create sample [ProjectState], [WorktreeState],
/// and [ChatState] instances with realistic mock data. Useful for:
/// - Unit testing model classes
/// - Integration testing UI components
/// - Development and demonstration
///
/// Example usage:
/// ```dart
/// final project = MockDataFactory.createMockProject();
/// final worktree = project.primaryWorktree;
/// final chat = worktree.chats.first;
/// ```
class MockDataFactory {
  // Private constructor to prevent instantiation.
  MockDataFactory._();

  /// Creates a complete mock project with worktrees, chats, and conversations.
  ///
  /// The mock project structure:
  /// ```
  /// Project: "CC-Insights"
  /// |-- Worktree: main (primary)
  /// |   |-- Chat: "Initial setup"
  /// |   |   |-- Primary conversation (4 output entries)
  /// |   |   +-- Subagent: "Explore" (2 output entries)
  /// |   +-- Chat: "Add dark mode"
  /// |       +-- Primary conversation (empty)
  /// |-- Worktree: feat-dark-mode (linked)
  /// |   +-- Chat: "Theme implementation"
  /// |       +-- Primary conversation (2 output entries)
  /// +-- Worktree: fix-auth-bug (linked)
  ///     +-- (no chats)
  /// ```
  ///
  /// Returns a [ProjectState] with the primary worktree selected by default.
  ///
  /// [watchFilesystem] defaults to false for tests to avoid pending timers.
  /// [autoValidate] defaults to false for tests to avoid filesystem checks.
  static ProjectState createMockProject({
    bool watchFilesystem = false,
    bool autoValidate = false,
  }) {
    final basePath = mockDataProjectPath;
    final wtBasePath = '${basePath}-wt';

    // Create the primary worktree with 2 chats.
    final primaryWorktree = createMockWorktree(
      worktreeRoot: basePath,
      isPrimary: true,
      branch: 'main',
      uncommittedFiles: 3,
      stagedFiles: 1,
      commitsAhead: 2,
      commitsBehind: 0,
      chats: [
        _createInitialSetupChat(basePath),
        _createAddDarkModeChat(basePath),
      ],
    );

    // Create the feat-dark-mode linked worktree with 1 chat.
    final darkModeWorktree = createMockWorktree(
      worktreeRoot: '$wtBasePath/dark-mode',
      isPrimary: false,
      branch: 'feat-dark-mode',
      uncommittedFiles: 5,
      stagedFiles: 2,
      commitsAhead: 3,
      commitsBehind: 1,
      chats: [
        _createThemeImplementationChat(
          '$wtBasePath/dark-mode',
        ),
      ],
    );

    // Create the fix-auth-bug linked worktree with no chats.
    final authBugWorktree = createMockWorktree(
      worktreeRoot: '$wtBasePath/fix-auth',
      isPrimary: false,
      branch: 'fix-auth-bug',
      uncommittedFiles: 2,
      stagedFiles: 0,
      commitsAhead: 1,
      commitsBehind: 0,
      hasMergeConflict: true,
      chats: [],
    );

    return ProjectState(
      ProjectData(
        name: 'CC-Insights',
        repoRoot: basePath,
      ),
      primaryWorktree,
      linkedWorktrees: [darkModeWorktree, authBugWorktree],
      autoValidate: autoValidate,
      watchFilesystem: watchFilesystem,
      // Primary worktree selected by default.
    );
  }

  /// Creates a mock worktree with the given parameters.
  ///
  /// [worktreeRoot] is the filesystem path to the worktree.
  /// [isPrimary] indicates whether this is the primary worktree.
  /// [branch] is the current git branch name.
  /// [chats] is the list of chats in this worktree, defaults to empty.
  /// Git status fields default to 0 or false.
  static WorktreeState createMockWorktree({
    required String worktreeRoot,
    required bool isPrimary,
    required String branch,
    int uncommittedFiles = 0,
    int stagedFiles = 0,
    int commitsAhead = 0,
    int commitsBehind = 0,
    bool hasMergeConflict = false,
    List<ChatState>? chats,
  }) {
    return WorktreeState(
      WorktreeData(
        worktreeRoot: worktreeRoot,
        isPrimary: isPrimary,
        branch: branch,
        uncommittedFiles: uncommittedFiles,
        stagedFiles: stagedFiles,
        commitsAhead: commitsAhead,
        commitsBehind: commitsBehind,
        hasMergeConflict: hasMergeConflict,
      ),
      chats: chats,
    );
  }

  /// Creates a mock chat with sample output entries.
  ///
  /// [name] is the user-visible chat name.
  /// [worktreeRoot] is the path to the parent worktree.
  /// [entries] is the list of output entries for the primary conversation.
  /// [subagentConversations] is an optional map of subagent conversations.
  static ChatState createMockChat({
    required String name,
    required String worktreeRoot,
    List<OutputEntry> entries = const [],
    Map<String, ConversationData> subagentConversations = const {},
  }) {
    final id = 'chat-mock-${name.hashCode.abs()}';
    final primaryConversationId = 'conv-primary-$id';

    final primaryConversation = ConversationData(
      id: primaryConversationId,
      entries: entries,
      totalUsage: const UsageInfo.zero(),
    );

    return ChatState(
      ChatData(
        id: id,
        name: name,
        worktreeRoot: worktreeRoot,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        primaryConversation: primaryConversation,
        subagentConversations: subagentConversations,
      ),
    );
  }

  /// Finds the tools-test.jsonl file by checking several locations.
  ///
  /// Returns null if the file cannot be found.
  static File? _findToolsTestFile() {
    const fileName = 'tools-test.jsonl';
    final tried = <String>[];

    File tryPath(String path) {
      tried.add(path);
      return File(path);
    }

    // Try configured mock path first
    final configuredPath = '$mockDataProjectPath/frontend/$fileName';
    var file = tryPath(configuredPath);
    if (file.existsSync()) return file;

    // Try current directory (works when running from frontend)
    file = tryPath('${Directory.current.path}/$fileName');
    if (file.existsSync()) return file;

    // Try current directory with frontend subdirectory
    file = tryPath('${Directory.current.path}/frontend/$fileName');
    if (file.existsSync()) return file;

    // Try based on Platform.script (works in some contexts)
    try {
      final scriptPath = Platform.script.toFilePath();
      if (scriptPath.contains('frontend')) {
        final idx = scriptPath.indexOf('frontend');
        final projectRoot =
            scriptPath.substring(0, idx + 'frontend'.length);
        file = tryPath('$projectRoot/$fileName');
        if (file.existsSync()) return file;
      }
    } catch (_) {
      // Platform.script may not be available in all contexts
    }

    // Try based on Platform.resolvedExecutable (works for compiled apps)
    try {
      final exePath = Platform.resolvedExecutable;
      if (exePath.contains('frontend')) {
        final idx = exePath.indexOf('frontend');
        final projectRoot = exePath.substring(0, idx + 'frontend'.length);
        file = tryPath('$projectRoot/$fileName');
        if (file.existsSync()) return file;
      }
    } catch (_) {
      // May not be available in all contexts
    }

    // Try walking up from current directory looking for frontend
    var dir = Directory.current;
    for (var i = 0; i < 5; i++) {
      file = tryPath('${dir.path}/frontend/$fileName');
      if (file.existsSync()) return file;

      // Check if we're already in frontend
      if (dir.path.endsWith('frontend')) {
        file = tryPath('${dir.path}/$fileName');
        if (file.existsSync()) return file;
      }

      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // Debug: print where we looked
    debugPrint('Could not find $fileName. Tried: $tried');
    return null;
  }

  // --- Private helper methods for creating specific mock chats ---

  /// Creates the "Initial setup" chat with entries loaded from the log file.
  ///
  /// If the log file exists at /tmp/test.msgs.jsonl, loads entries from it.
  /// Otherwise falls back to sample mock data.
  static ChatState _createInitialSetupChat(String worktreeRoot) {
    const chatId = 'chat-initial-setup';
    const primaryConversationId = 'conv-primary-$chatId';
    final now = DateTime.now();

    // Try to load entries from log file
    List<OutputEntry> primaryEntries = _loadEntriesFromLogFile();

    // If no log file, use fallback mock data
    if (primaryEntries.isEmpty) {
      primaryEntries = [
        UserInputEntry(
          timestamp: now.subtract(const Duration(minutes: 30)),
          text: 'Help me set up the project structure for CC-Insights V2',
        ),
        TextOutputEntry(
          timestamp: now.subtract(const Duration(minutes: 29)),
          text:
              "I'll help you set up the project structure. Let me first "
              'explore the existing codebase to understand the current '
              'architecture.',
          contentType: 'thinking',
        ),
        TextOutputEntry(
          timestamp: now.subtract(const Duration(minutes: 28)),
          text:
              "I'll analyze the current project structure and create a plan "
              'for V2. Let me read the architecture documentation first.',
          contentType: 'text',
        ),
        ToolUseOutputEntry(
          timestamp: now.subtract(const Duration(minutes: 27)),
          toolName: 'Read',
          toolUseId: 'tool-read-001',
          toolInput: {
            'file_path': '$worktreeRoot/docs/architecture.md',
          },
          result: '# CC-Insights Architecture\n\n## Overview\n...',
          isError: false,
          isExpanded: false,
        ),
      ];
    }

    return ChatState(
      ChatData(
        id: chatId,
        name: 'Log Replay',
        worktreeRoot: worktreeRoot,
        createdAt: now.subtract(const Duration(minutes: 30)),
        primaryConversation: ConversationData(
          id: primaryConversationId,
          entries: primaryEntries,
          totalUsage: const UsageInfo.zero(),
        ),
        subagentConversations: const {},
      ),
    );
  }

  /// Loads output entries from the tools-test.jsonl file synchronously.
  ///
  /// Expects proper JSONL format (one JSON object per line).
  ///
  /// Returns an empty list if the file doesn't exist or can't be parsed.
  static List<OutputEntry> _loadEntriesFromLogFile() {
    final file = _findToolsTestFile();
    if (file == null) {
      return [];
    }
    if (!file.existsSync()) {
      return [];
    }

    try {
      final lines = file.readAsLinesSync();
      final entries = <OutputEntry>[];
      final transformer = MessageTransformer();

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json =
              (const JsonDecoder().convert(line)) as Map<String, dynamic>;
          final logEntry = LogEntry.fromJson(json);
          entries.addAll(transformer.transform(logEntry));
        } catch (_) {
          // Skip malformed lines
        }
      }

      return entries;
    } catch (e) {
      return [];
    }
  }

  /// Creates the "Add dark mode" chat with an empty primary conversation.
  static ChatState _createAddDarkModeChat(String worktreeRoot) {
    const chatId = 'chat-add-dark-mode';
    const primaryConversationId = 'conv-primary-$chatId';

    return ChatState(
      ChatData(
        id: chatId,
        name: 'Add dark mode',
        worktreeRoot: worktreeRoot,
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        primaryConversation: ConversationData.primary(
          id: primaryConversationId,
        ),
        subagentConversations: const {},
      ),
    );
  }

  /// Creates the "Theme implementation" chat with sample output entries.
  static ChatState _createThemeImplementationChat(String worktreeRoot) {
    const chatId = 'chat-theme-impl';
    const primaryConversationId = 'conv-primary-$chatId';
    final now = DateTime.now();

    final entries = <OutputEntry>[
      UserInputEntry(
        timestamp: now.subtract(const Duration(minutes: 20)),
        text: 'Create a ThemeProvider that supports light and dark modes',
      ),
      ToolUseOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 19)),
        toolName: 'Edit',
        toolUseId: 'tool-edit-001',
        toolInput: {
          'file_path': '$worktreeRoot/lib/providers/theme_provider.dart',
          'old_string': '',
          'new_string':
              'class ThemeProvider extends ChangeNotifier {\n'
              '  ThemeMode _themeMode = ThemeMode.system;\n'
              '  ThemeMode get themeMode => _themeMode;\n'
              '  ...\n'
              '}',
        },
        result: 'File created successfully',
        isError: false,
        isExpanded: true,
      ),
    ];

    return ChatState(
      ChatData(
        id: chatId,
        name: 'Theme implementation',
        worktreeRoot: worktreeRoot,
        createdAt: now.subtract(const Duration(minutes: 20)),
        primaryConversation: ConversationData(
          id: primaryConversationId,
          entries: entries,
          totalUsage: const UsageInfo.zero(),
        ),
        subagentConversations: const {},
      ),
    );
  }

  /// Creates sample output entries for testing tool card display.
  ///
  /// Returns a list containing examples of each major entry type:
  /// - [UserInputEntry]
  /// - [TextOutputEntry] (regular and thinking)
  /// - [ToolUseOutputEntry] (Bash, Read, Edit)
  static List<OutputEntry> createSampleOutputEntries() {
    final now = DateTime.now();

    return [
      UserInputEntry(
        timestamp: now.subtract(const Duration(minutes: 10)),
        text: 'What files are in the lib directory?',
      ),
      TextOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9, seconds: 55)),
        text:
            'Let me think about how to best explore the directory '
            'structure...',
        contentType: 'thinking',
      ),
      TextOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9, seconds: 50)),
        text: "I'll list the files in the lib directory for you.",
        contentType: 'text',
      ),
      ToolUseOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9, seconds: 45)),
        toolName: 'Bash',
        toolUseId: 'tool-bash-sample-001',
        toolInput: const {'command': 'ls -la lib/'},
        result:
            'total 24\ndrwxr-xr-x  8 user  staff   256 Jan 15 10:30 .\n'
            'drwxr-xr-x 12 user  staff   384 Jan 15 10:30 ..\n'
            '-rw-r--r--  1 user  staff  1234 Jan 15 10:30 main.dart\n'
            'drwxr-xr-x  5 user  staff   160 Jan 15 10:30 models\n'
            'drwxr-xr-x  3 user  staff    96 Jan 15 10:30 panels\n',
        isError: false,
        isExpanded: false,
      ),
      ToolUseOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9, seconds: 30)),
        toolName: 'Read',
        toolUseId: 'tool-read-sample-001',
        toolInput: const {'file_path': 'lib/main.dart'},
        result:
            "import 'package:flutter/material.dart';\n\n"
            'void main() {\n'
            '  runApp(const MyApp());\n'
            '}\n',
        isError: false,
        isExpanded: false,
      ),
      ToolUseOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9, seconds: 15)),
        toolName: 'Edit',
        toolUseId: 'tool-edit-sample-001',
        toolInput: const {
          'file_path': 'lib/main.dart',
          'old_string': 'const MyApp()',
          'new_string': 'const MyApp(title: "CC-Insights")',
        },
        result: 'Edit applied successfully',
        isError: false,
        isExpanded: false,
      ),
      TextOutputEntry(
        timestamp: now.subtract(const Duration(minutes: 9)),
        text:
            'The lib directory contains:\n'
            '- **main.dart** - The application entry point\n'
            '- **models/** - Data model classes\n'
            '- **panels/** - UI panel components\n\n'
            "I've also updated main.dart to include an application title.",
        contentType: 'text',
      ),
    ];
  }
}
