# Flutter Integration Guide

This document describes how to integrate the Dart SDK into the Flutter application.

## Overview

The Flutter app will:

1. Spawn the Node backend on startup
2. Use `ClaudeBackend` and `ClaudeSession` for all Claude interactions
3. Wire SDK streams to UI state
4. Handle permissions and hooks via streams

## Dependency Setup

### pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0
  # ... other deps

  # Local Dart SDK
  claude_sdk:
    path: ../dart_sdk
```

## App Startup

### main.dart

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:claude_sdk/claude_sdk.dart';

import 'providers/app_state.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parse command line args
  final args = _parseArgs();

  // Spawn backend
  final backend = await ClaudeBackend.spawn(
    backendPath: _getBackendPath(),
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<ClaudeBackend>.value(value: backend),
        ChangeNotifierProvider(
          create: (_) => AppState(
            backend: backend,
            defaultCwd: args.cwd ?? Directory.current.path,
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

String _getBackendPath() {
  // In development: use the built backend
  // In production: bundled with app

  if (Platform.environment.containsKey('CLAUDE_BACKEND_PATH')) {
    return Platform.environment['CLAUDE_BACKEND_PATH']!;
  }

  // Default: relative to app
  final appDir = Platform.resolvedExecutable;
  final backendPath = '${Directory(appDir).parent.path}/backend/index.js';

  if (File(backendPath).existsSync()) {
    return backendPath;
  }

  // Fallback for development
  return '../backend-node/dist/index.js';
}

class _Args {
  final String? cwd;
  _Args({this.cwd});
}

_Args _parseArgs() {
  final args = Platform.executableArguments;
  String? cwd;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--cwd' && i + 1 < args.length) {
      cwd = args[i + 1];
    }
  }

  return _Args(cwd: cwd);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Agent Insights',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}
```

## App State

### providers/app_state.dart

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:claude_sdk/claude_sdk.dart';

/// Application state managing Claude sessions.
class AppState extends ChangeNotifier {
  final ClaudeBackend backend;
  final String defaultCwd;

  AppState({
    required this.backend,
    required this.defaultCwd,
  }) {
    // Listen for backend errors
    backend.errors.listen(_handleBackendError);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Sessions
  // ═══════════════════════════════════════════════════════════════════════════

  final Map<String, SessionState> _sessions = {};
  String? _activeSessionId;

  Map<String, SessionState> get sessions => Map.unmodifiable(_sessions);
  SessionState? get activeSession =>
      _activeSessionId != null ? _sessions[_activeSessionId] : null;

  /// Create a new Claude session.
  Future<SessionState> createSession({
    required String prompt,
    String? cwd,
    SessionOptions? options,
  }) async {
    final session = await backend.createSession(
      prompt: prompt,
      cwd: cwd ?? defaultCwd,
      options: options ?? const SessionOptions(
        model: 'sonnet',
        permissionMode: PermissionMode.default_,
        includePartialMessages: true,
        settingSources: [SettingSource.user, SettingSource.project, SettingSource.local],
        systemPrompt: PresetSystemPrompt(),
      ),
    );

    final state = SessionState(session: session);
    _sessions[session.sessionId] = state;
    _activeSessionId = session.sessionId;

    // Wire up streams
    _wireSession(state);

    notifyListeners();
    return state;
  }

  /// Set the active session.
  void setActiveSession(String sessionId) {
    if (_sessions.containsKey(sessionId)) {
      _activeSessionId = sessionId;
      notifyListeners();
    }
  }

  /// Remove a session.
  Future<void> removeSession(String sessionId) async {
    final state = _sessions.remove(sessionId);
    if (state != null) {
      await state.session.kill();
      state.dispose();
    }

    if (_activeSessionId == sessionId) {
      _activeSessionId = _sessions.keys.firstOrNull;
    }

    notifyListeners();
  }

  void _wireSession(SessionState state) {
    final session = state.session;

    // SDK messages
    state._messagesSub = session.messages.listen((msg) {
      state._handleMessage(msg);
      notifyListeners();
    });

    // Permission requests
    state._permissionsSub = session.permissionRequests.listen((req) {
      state._pendingPermission = req;
      notifyListeners();
    });

    // Hook requests
    state._hooksSub = session.hookRequests.listen((req) {
      state._pendingHooks.add(req);
      notifyListeners();
    });
  }

  void _handleBackendError(BackendError error) {
    // Handle backend errors (e.g., show snackbar)
    debugPrint('Backend error: ${error.code} - ${error.message}');
  }

  @override
  void dispose() {
    for (final state in _sessions.values) {
      state.dispose();
    }
    backend.dispose();
    super.dispose();
  }
}

/// State for a single Claude session.
class SessionState {
  final ClaudeSession session;

  SessionState({required this.session});

  // ═══════════════════════════════════════════════════════════════════════════
  // Message History
  // ═══════════════════════════════════════════════════════════════════════════

  final List<SDKMessage> _messages = [];
  List<SDKMessage> get messages => List.unmodifiable(_messages);

  // Processed data
  String? _model;
  List<String>? _tools;
  String? _permissionMode;

  String? get model => _model;
  List<String>? get tools => _tools;
  String? get permissionMode => _permissionMode;

  // Current turn state
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // Usage tracking
  Usage? _lastUsage;
  double _totalCost = 0;
  Usage? get lastUsage => _lastUsage;
  double get totalCost => _totalCost;

  // Agent hierarchy
  final Map<String, AgentInfo> _agents = {};
  Map<String, AgentInfo> get agents => Map.unmodifiable(_agents);

  // ═══════════════════════════════════════════════════════════════════════════
  // Pending Callbacks
  // ═══════════════════════════════════════════════════════════════════════════

  PermissionRequest? _pendingPermission;
  final List<HookRequest> _pendingHooks = [];

  PermissionRequest? get pendingPermission => _pendingPermission;
  List<HookRequest> get pendingHooks => List.unmodifiable(_pendingHooks);

  /// Respond to pending permission request.
  void respondToPermission(bool approved, {Map<String, dynamic>? updatedInput}) {
    final req = _pendingPermission;
    if (req == null) return;

    if (approved) {
      req.allow(updatedInput: updatedInput);
    } else {
      req.deny('User declined');
    }

    _pendingPermission = null;
  }

  /// Respond to a hook request.
  void respondToHook(HookRequest request, HookResponse response) {
    request.respond(response);
    _pendingHooks.remove(request);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════════

  /// Send a follow-up message.
  Future<void> send(String message) async {
    _isRunning = true;
    await session.send(message);
  }

  /// Interrupt the current execution.
  Future<void> interrupt() async {
    await session.interrupt();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Message Processing
  // ═══════════════════════════════════════════════════════════════════════════

  void _handleMessage(SDKMessage msg) {
    _messages.add(msg);

    switch (msg) {
      case SDKSystemMessage m when m.subtype == 'init':
        _model = m.model;
        _tools = m.tools;
        _permissionMode = m.permissionMode;
        _isRunning = true;

        // Initialize main agent
        _agents['main'] = AgentInfo(
          id: 'main',
          label: 'Main',
          parentId: null,
        );

      case SDKAssistantMessage m:
        _processAssistantMessage(m);

      case SDKUserMessage m:
        _processUserMessage(m);

      case SDKResultMessage m:
        _isRunning = false;
        _lastUsage = m.usage;
        if (m.totalCostUsd != null) {
          _totalCost += m.totalCostUsd!;
        }

      case SDKStreamEvent _:
        // Streaming events handled separately if needed
        break;

      default:
        break;
    }
  }

  void _processAssistantMessage(SDKAssistantMessage msg) {
    final parentId = msg.parentToolUseId;
    final agentId = _getAgentId(parentId);

    for (final block in msg.message.content) {
      if (block is ToolUseBlock && block.name == 'Task') {
        // Task tool = new subagent
        final taskId = block.id;
        final description = block.input['description'] as String? ??
            block.input['prompt'] as String? ??
            'Subagent';

        _agents[taskId] = AgentInfo(
          id: taskId,
          label: _generateLabel(agentId),
          parentId: agentId,
          description: description,
        );
      }
    }
  }

  void _processUserMessage(SDKUserMessage msg) {
    // Tool results - check for task completion
    for (final block in msg.message.content) {
      if (block is ToolResultBlock) {
        final agent = _agents[block.toolUseId];
        if (agent != null) {
          agent.isCompleted = true;
        }
      }
    }
  }

  String _getAgentId(String? parentToolUseId) {
    if (parentToolUseId == null) return 'main';
    return _agents.containsKey(parentToolUseId) ? parentToolUseId : 'main';
  }

  String _generateLabel(String parentId) {
    final parent = _agents[parentId];
    if (parent == null) return 'Sub1';

    final siblings = _agents.values.where((a) => a.parentId == parentId).length;
    if (parentId == 'main') {
      return 'Sub${siblings + 1}';
    } else {
      return '${parent.label}.${siblings + 1}';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Subscriptions
  // ═══════════════════════════════════════════════════════════════════════════

  StreamSubscription<SDKMessage>? _messagesSub;
  StreamSubscription<PermissionRequest>? _permissionsSub;
  StreamSubscription<HookRequest>? _hooksSub;

  void dispose() {
    _messagesSub?.cancel();
    _permissionsSub?.cancel();
    _hooksSub?.cancel();
  }
}

/// Information about an agent in the hierarchy.
class AgentInfo {
  final String id;
  final String label;
  final String? parentId;
  final String? description;
  bool isCompleted = false;

  AgentInfo({
    required this.id,
    required this.label,
    this.parentId,
    this.description,
  });
}
```

## Widget Updates

### Permission Dialog

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:claude_sdk/claude_sdk.dart';
import '../providers/app_state.dart';

class PermissionDialog extends StatelessWidget {
  const PermissionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final session = state.activeSession;
        final request = session?.pendingPermission;

        if (request == null) return const SizedBox.shrink();

        return AlertDialog(
          title: Text('Permission Required'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tool: ${request.toolName}'),
              const SizedBox(height: 8),
              Text(
                'Input: ${_formatInput(request.toolInput)}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => session.respondToPermission(false),
              child: const Text('Deny'),
            ),
            ElevatedButton(
              onPressed: () => session.respondToPermission(true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
  }

  String _formatInput(Map<String, dynamic> input) {
    // Format tool input for display
    if (input.containsKey('command')) {
      return input['command'] as String;
    }
    if (input.containsKey('file_path')) {
      return input['file_path'] as String;
    }
    return input.toString();
  }
}
```

### Output Panel

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:claude_sdk/claude_sdk.dart';
import '../providers/app_state.dart';

class OutputPanel extends StatelessWidget {
  const OutputPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final session = state.activeSession;
        if (session == null) {
          return const Center(child: Text('No active session'));
        }

        return ListView.builder(
          itemCount: session.messages.length,
          itemBuilder: (context, index) {
            return _buildMessage(session.messages[index]);
          },
        );
      },
    );
  }

  Widget _buildMessage(SDKMessage msg) {
    switch (msg) {
      case SDKAssistantMessage m:
        return _buildAssistantMessage(m);
      case SDKUserMessage m:
        return _buildUserMessage(m);
      case SDKResultMessage m:
        return _buildResultMessage(m);
      case SDKSystemMessage m:
        return _buildSystemMessage(m);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAssistantMessage(SDKAssistantMessage msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in msg.message.content)
          _buildContentBlock(block),
      ],
    );
  }

  Widget _buildContentBlock(ContentBlock block) {
    switch (block) {
      case TextBlock b:
        return Padding(
          padding: const EdgeInsets.all(8),
          child: SelectableText(b.text),
        );
      case ThinkingBlock b:
        return Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[900],
          child: SelectableText(
            b.thinking,
            style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic),
          ),
        );
      case ToolUseBlock b:
        return _buildToolUse(b);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildToolUse(ToolUseBlock block) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _formatToolInput(block.name, block.input),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserMessage(SDKUserMessage msg) {
    // Tool results
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in msg.message.content)
          if (block is ToolResultBlock)
            _buildToolResult(block),
      ],
    );
  }

  Widget _buildToolResult(ToolResultBlock block) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: block.isError == true ? Colors.red[900] : Colors.green[900],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _truncate(block.content?.toString() ?? '', 500),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  Widget _buildResultMessage(SDKResultMessage msg) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Turns: ${msg.numTurns}'),
          Text('Cost: \$${msg.totalCostUsd?.toStringAsFixed(4) ?? '?'}'),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(SDKSystemMessage msg) {
    if (msg.subtype != 'init') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.blue[900],
      child: Text('Model: ${msg.model} | Tools: ${msg.tools.length}'),
    );
  }

  String _formatToolInput(String toolName, Map<String, dynamic> input) {
    switch (toolName) {
      case 'Bash':
        return input['command'] as String? ?? '';
      case 'Read':
      case 'Write':
      case 'Edit':
        return input['file_path'] as String? ?? '';
      case 'Glob':
      case 'Grep':
        return input['pattern'] as String? ?? '';
      default:
        return input.toString();
    }
  }

  String _truncate(String s, int maxLength) {
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength)}...';
  }
}
```

## Files to Delete

After integration is complete, delete these files:

```
flutter_app/lib/services/websocket_service.dart
flutter_app/lib/models/messages.dart
flutter_app/lib/models/session.dart  (if redundant with SDK types)
docs/websocket-protocol.md
```

## Migration Checklist

- [ ] Add `claude_sdk` dependency to pubspec.yaml
- [ ] Update `main.dart` to spawn backend
- [ ] Create new `AppState` provider
- [ ] Update session creation to use SDK
- [ ] Update output panel for SDK message types
- [ ] Update permission handling for SDK callbacks
- [ ] Update agent tree for SDK-based hierarchy
- [ ] Update input panel for SDK session methods
- [ ] Remove WebSocket service
- [ ] Remove old message types
- [ ] Test all functionality
- [ ] Update CLAUDE.md with new architecture
