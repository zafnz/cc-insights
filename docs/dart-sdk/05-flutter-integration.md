# Flutter Integration Guide

This document describes how to integrate the Dart SDK into the Flutter application.

## Overview

The Flutter app will:

1. Use `BackendFactory` to create a `ClaudeCliBackend` on startup
2. Use `AgentBackend` and `AgentSession` interfaces for all Claude interactions
3. Wire SDK streams to UI state
4. Handle permission requests via streams

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
    path: ../claude_dart_sdk
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

  // Create backend (direct CLI)
  final backend = await BackendFactory.create(
    type: BackendType.directCli,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<AgentBackend>.value(value: backend),
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
  final AgentBackend backend;
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
  final AgentSession session;

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

  PermissionRequest? get pendingPermission => _pendingPermission;

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

  void dispose() {
    _messagesSub?.cancel();
    _permissionsSub?.cancel();
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

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_PATH` | Path to claude CLI executable (optional, defaults to `claude` in PATH) |

## Migration Checklist

- [x] Add `claude_sdk` dependency to pubspec.yaml
- [x] Update `main.dart` to use BackendFactory
- [x] Create new `AppState` provider using AgentBackend
- [x] Update session creation to use SDK
- [x] Update output panel for SDK message types
- [x] Update permission handling for SDK callbacks
- [x] Update agent tree for SDK-based hierarchy
- [x] Update input panel for SDK session methods
- [x] Remove WebSocket service
- [x] Remove old message types
- [x] Test all functionality
- [x] Update CLAUDE.md with new architecture
