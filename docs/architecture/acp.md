# ACP Integration Architecture

This document describes how CC-Insights will integrate with the Agent Client Protocol (ACP) to support multiple AI coding agents.

---

## Overview

### What is ACP?

The **Agent Client Protocol (ACP)** is a standardized protocol for communication between code editors/IDEs and AI coding agents. It's analogous to LSP (Language Server Protocol) but for AI agents.

Key characteristics:
- **JSON-RPC 2.0** over stdio (or HTTP/WebSocket for remote agents)
- **Bidirectional**: Agents can request permissions from clients
- **MCP-compatible**: Reuses Model Context Protocol content types
- **Multi-agent ecosystem**: Claude Code, Codex, Gemini CLI, Copilot, and more

### Why ACP for CC-Insights?

| Current Architecture | ACP Architecture |
|---------------------|------------------|
| Custom Node.js backend | Direct agent spawning |
| Claude-only | Multi-agent support |
| Proprietary protocol | Industry standard |
| SDK wrapper maintenance | Drop-in agent compatibility |

### Supported Agents

With ACP, CC-Insights will support:
- **Claude Code** (via `claude-code-acp` adapter)
- **OpenAI Codex CLI** (via adapter)
- **Google Gemini CLI**
- **GitHub Copilot** (ACP support in preview)
- **Goose**, **OpenHands**, **Augment Code**, and others

---

## Architecture Changes

### Current vs. New Architecture

```
CURRENT ARCHITECTURE:

┌─────────────────┐     JSON lines      ┌─────────────────┐
│     Flutter     │◄──────────────────►│   Node.js       │
│     Frontend    │   custom protocol   │   Backend       │
└────────┬────────┘                     └────────┬────────┘
         │                                       │
         │ Provider                              │ Claude
         ▼                                       ▼ Agent SDK
   ┌───────────┐                          ┌───────────┐
   │ ChatState │                          │ SDK Query │
   └───────────┘                          └───────────┘


NEW ARCHITECTURE (ACP):

┌─────────────────┐      JSON-RPC 2.0     ┌─────────────────┐
│     Flutter     │◄────────────────────►│   ACP Agent     │
│     Frontend    │   ACP over stdio      │   (any agent)   │
└────────┬────────┘                       └─────────────────┘
         │                                        │
         │ Provider                               │ LLM API
         ▼                                        ▼
   ┌───────────┐                          ┌───────────────┐
   │ ChatState │                          │ Claude/GPT/   │
   └───────────┘                          │ Gemini/etc.   │
                                          └───────────────┘
```

### Components to Remove

1. **backend-node/** - Entire directory removed
   - `index.ts`, `session-manager.ts`, `callback-bridge.ts`
   - `protocol.ts`, `message-queue.ts`, `logger.ts`

2. **dart_sdk/** - Replace with ACP client
   - Current `ClaudeBackend` and `ClaudeSession` classes
   - Custom protocol message types

### Components to Add

1. **acp_dart package** - Use the existing community Dart library
   - Add `acp_dart: ^0.3.0` to `pubspec.yaml`
   - Provides `ClientSideConnection`, type definitions, JSON-RPC handling

2. **Agent Registry** (`lib/services/agent_registry.dart`)
   - Discover and manage installed agents
   - Agent configuration and preferences

3. **Integration Layer** (`lib/acp/`)
   - Thin wrapper adapting `acp_dart` to CC-Insights patterns
   - Provider-compatible state management

---

## Using the acp_dart Package

### Package Overview

The [acp_dart](https://github.com/SkrOYC/acp-dart) package provides a complete Dart implementation of ACP:

- **`ClientSideConnection`** - For building ACP clients (what we need)
- **`AgentSideConnection`** - For building ACP agents (not needed)
- Complete type definitions for all ACP messages
- Type-safe RPC unions for request/response handling
- NDJSON-based stream communication
- Full null safety

### Installation

Add to `frontend/pubspec.yaml`:

```yaml
dependencies:
  acp_dart: ^0.3.0
```

### Directory Structure

```
frontend/lib/
├── acp/
│   ├── acp.dart                    # Library export
│   ├── acp_client_wrapper.dart     # Wraps ClientSideConnection
│   ├── acp_session_wrapper.dart    # Session with Provider support
│   └── handlers/
│       ├── fs_handler.dart         # File system request handler
│       └── terminal_handler.dart   # Terminal request handler
├── services/
│   ├── agent_registry.dart         # Agent discovery
│   ├── agent_service.dart          # Replaces backend_service.dart
│   └── ...
└── ...
```

### Using ClientSideConnection

The `acp_dart` package uses a **callback-based pattern** via the `Client` interface. You implement the `Client` abstract class to handle agent requests:

```dart
import 'package:acp_dart/acp_dart.dart';

/// Implement the Client interface to handle agent requests
class CCInsightsClient implements Client {
  final void Function(SessionUpdate) onSessionUpdate;
  final Future<RequestPermissionResponse> Function(RequestPermissionRequest) onPermissionRequest;

  CCInsightsClient({
    required this.onSessionUpdate,
    required this.onPermissionRequest,
  });

  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    // Called for each streaming update from the agent
    onSessionUpdate(params.update);
  }

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    // Called when agent needs permission for a tool
    return onPermissionRequest(params);
  }

  @override
  Future<ReadTextFileResponse> readTextFile(ReadTextFileRequest params) async {
    final content = await File(params.path).readAsString();
    return ReadTextFileResponse(content: content);
  }

  @override
  Future<WriteTextFileResponse> writeTextFile(WriteTextFileRequest params) async {
    await File(params.path).writeAsString(params.content);
    return WriteTextFileResponse();
  }

  @override
  Future<CreateTerminalResponse> createTerminal(CreateTerminalRequest params) async {
    // Implement terminal creation
    return CreateTerminalResponse(terminalId: 'term-${DateTime.now().microsecondsSinceEpoch}');
  }

  // ... other terminal methods ...
}

// Usage:
final process = await Process.start('claude-code-acp', []);
final stream = ndJsonStream(process.stdout, process.stdin);

// Create connection with client handler
final connection = ClientSideConnection(
  (agent) => CCInsightsClient(
    onSessionUpdate: (update) {
      // Handle streaming updates
      if (update is AgentMessageChunkSessionUpdate) {
        print((update.content as TextContentBlock).text);
      }
    },
    onPermissionRequest: (params) async {
      // Show UI, get user decision
      return RequestPermissionResponse(
        outcome: SelectedOutcome(optionId: 'allow'),
      );
    },
  ),
  stream,
);

// Initialize the connection
final initResult = await connection.initialize(
  InitializeRequest(
    protocolVersion: 1,
    clientCapabilities: ClientCapabilities(
      fs: FileSystemCapability(readTextFile: true, writeTextFile: true),
      terminal: true,
    ),
  ),
);

// Create a session
final sessionResult = await connection.newSession(
  NewSessionRequest(
    cwd: '/path/to/project',
    mcpServers: [],
  ),
);

// Send a prompt (updates arrive via sessionUpdate callback)
final promptResult = await connection.prompt(
  PromptRequest(
    sessionId: sessionResult.sessionId,
    prompt: [TextContentBlock(text: 'Hello, world!')],
  ),
);
```

### Core Wrapper Classes

The acp_dart library uses a callback-based `Client` interface pattern. We need to wrap this
with stream-based APIs that integrate well with Flutter's Provider and widget rebuilding.

#### CCInsightsACPClient (implements Client interface)

This class implements the `Client` interface from acp_dart and bridges callbacks to streams:

```dart
import 'dart:async';
import 'dart:io';
import 'package:acp_dart/acp_dart.dart';

/// Implements acp_dart's Client interface, bridging to stream-based APIs.
class CCInsightsACPClient implements Client {
  CCInsightsACPClient({
    required this.updateController,
    required this.permissionController,
    required this.terminalHandler,
  });

  final StreamController<SessionNotification> updateController;
  final StreamController<PendingPermission> permissionController;
  final TerminalHandler terminalHandler;

  @override
  Future<void> sessionUpdate(SessionNotification params) async {
    // Forward to stream for UI consumption
    updateController.add(params);
  }

  @override
  Future<RequestPermissionResponse> requestPermission(
    RequestPermissionRequest params,
  ) async {
    // Create a completer that UI will resolve
    final completer = Completer<RequestPermissionResponse>();

    permissionController.add(PendingPermission(
      request: params,
      completer: completer,
    ));

    return completer.future;
  }

  @override
  Future<ReadTextFileResponse> readTextFile(ReadTextFileRequest params) async {
    final content = await File(params.path).readAsString();
    return ReadTextFileResponse(content: content);
  }

  @override
  Future<WriteTextFileResponse> writeTextFile(WriteTextFileRequest params) async {
    await File(params.path).writeAsString(params.content);
    return WriteTextFileResponse();
  }

  @override
  Future<CreateTerminalResponse> createTerminal(CreateTerminalRequest params) async {
    return terminalHandler.create(params);
  }

  @override
  Future<TerminalOutputResponse> terminalOutput(TerminalOutputRequest params) async {
    return terminalHandler.output(params);
  }

  @override
  Future<ReleaseTerminalResponse> releaseTerminal(ReleaseTerminalRequest params) async {
    return terminalHandler.release(params);
  }

  @override
  Future<WaitForTerminalExitResponse> waitForTerminalExit(
    WaitForTerminalExitRequest params,
  ) async {
    return terminalHandler.waitForExit(params);
  }

  @override
  Future<KillTerminalCommandResponse> killTerminal(
    KillTerminalCommandRequest params,
  ) async {
    return terminalHandler.kill(params);
  }

  @override
  Future<Map<String, dynamic>>? extMethod(String method, Map<String, dynamic> params) async {
    return null; // Not implemented
  }

  @override
  Future<void>? extNotification(String method, Map<String, dynamic> params) async {
    // Log extension notifications
  }
}

/// Pending permission request with completer for UI resolution.
class PendingPermission {
  PendingPermission({required this.request, required this.completer});

  final RequestPermissionRequest request;
  final Completer<RequestPermissionResponse> completer;

  void allow(String optionId) {
    completer.complete(RequestPermissionResponse(
      outcome: SelectedOutcome(optionId: optionId),
    ));
  }

  void cancel() {
    completer.complete(RequestPermissionResponse(
      outcome: CancelledOutcome(),
    ));
  }
}
```

#### ACPClientWrapper

Wraps the connection lifecycle with Provider-compatible state management:

```dart
import 'dart:async';
import 'dart:io';
import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

/// Provider-compatible wrapper around acp_dart's ClientSideConnection.
class ACPClientWrapper extends ChangeNotifier {
  ACPClientWrapper({
    required this.agentConfig,
  });

  final AgentConfig agentConfig;

  Process? _process;
  ClientSideConnection? _connection;
  bool _isConnected = false;
  InitializeResponse? _initResult;

  // Stream controllers for bridging callbacks to streams
  final _updateController = StreamController<SessionNotification>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();
  final _terminalHandler = TerminalHandler();

  bool get isConnected => _isConnected;
  AgentCapabilities? get capabilities => _initResult?.agentCapabilities;
  AgentInfo? get agentInfo => _initResult?.agentInfo;

  Stream<SessionNotification> get updates => _updateController.stream;
  Stream<PendingPermission> get permissionRequests => _permissionController.stream;

  /// Connect to the agent and perform initialization.
  Future<void> connect() async {
    // Spawn the agent process
    _process = await Process.start(
      agentConfig.command,
      agentConfig.args,
      environment: {...Platform.environment, ...agentConfig.env},
    );

    // Create NDJSON stream
    final stream = ndJsonStream(_process!.stdout, _process!.stdin);

    // Create Client implementation
    final client = CCInsightsACPClient(
      updateController: _updateController,
      permissionController: _permissionController,
      terminalHandler: _terminalHandler,
    );

    // Create connection with our client handler
    _connection = ClientSideConnection((agent) => client, stream);

    // Initialize
    _initResult = await _connection!.initialize(
      InitializeRequest(
        protocolVersion: 1,
        clientCapabilities: ClientCapabilities(
          fs: FileSystemCapability(readTextFile: true, writeTextFile: true),
          terminal: true,
        ),
      ),
    );

    _isConnected = true;
    notifyListeners();
  }

  /// Create a new session.
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServer>? mcpServers,
  }) async {
    final result = await _connection!.newSession(
      NewSessionRequest(
        cwd: cwd,
        mcpServers: mcpServers ?? [],
      ),
    );

    return ACPSessionWrapper(
      connection: _connection!,
      sessionId: result.sessionId,
      modes: result.modes,
      updates: _updateController.stream,
      permissionRequests: _permissionController.stream,
    );
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _process?.kill();
    await _process?.exitCode;
    _process = null;
    _connection = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _updateController.close();
    _permissionController.close();
    super.dispose();
  }
}
```

#### ACPSessionWrapper

Wraps session operations with filtered streams for a specific session:

```dart
/// Wrapper around an ACP session with Provider-friendly streams.
class ACPSessionWrapper {
  ACPSessionWrapper({
    required this.connection,
    required this.sessionId,
    required Stream<SessionNotification> updates,
    required Stream<PendingPermission> permissionRequests,
    this.modes,
  }) {
    // Filter updates for this session only
    _updateSubscription = updates
        .where((n) => n.sessionId == sessionId)
        .listen((n) => _updateController.add(n.update));

    // Filter permissions for this session only
    _permissionSubscription = permissionRequests
        .where((p) => p.request.sessionId == sessionId)
        .listen((p) => _permissionController.add(p));
  }

  final ClientSideConnection connection;
  final String sessionId;
  SessionModes? modes;

  StreamSubscription<SessionUpdate>? _updateSubscription;
  StreamSubscription<PendingPermission>? _permissionSubscription;

  final _updateController = StreamController<SessionUpdate>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();

  /// Stream of session updates (agent messages, tool calls, etc.)
  Stream<SessionUpdate> get updates => _updateController.stream;

  /// Stream of pending permission requests for this session
  Stream<PendingPermission> get permissionRequests => _permissionController.stream;

  /// Send a prompt to the agent.
  Future<PromptResponse> prompt(List<ContentBlock> content) async {
    return connection.prompt(PromptRequest(
      sessionId: sessionId,
      prompt: content,
    ));
  }

  /// Cancel the current prompt turn.
  Future<void> cancel() async {
    await connection.cancel(CancelNotification(sessionId: sessionId));
  }

  /// Set the session mode.
  Future<SetSessionModeResponse?> setMode(String modeId) async {
    return connection.setSessionMode(SetSessionModeRequest(
      sessionId: sessionId,
      modeId: modeId,
    ));
  }

  void dispose() {
    _updateSubscription?.cancel();
    _permissionSubscription?.cancel();
    _updateController.close();
    _permissionController.close();
  }
}
```

### Type Usage

The `acp_dart` package provides all necessary types. Key types we'll use:

```dart
// From acp_dart - no need to define ourselves
import 'package:acp_dart/acp_dart.dart';

// Content types (note: "Block" suffix)
TextContentBlock(text: 'Hello')
ImageContentBlock(data: base64Data, mimeType: 'image/png')
ResourceContentBlock(resource: EmbeddedResource(...))
ResourceLinkContentBlock(uri: 'file:///path', name: 'file.txt')

// Session updates (note: "SessionUpdate" suffix)
AgentMessageChunkSessionUpdate   // Agent text output
UserMessageChunkSessionUpdate    // User message (replay)
AgentThoughtChunkSessionUpdate   // Extended thinking
ToolCallSessionUpdate            // New tool call
ToolCallUpdateSessionUpdate      // Tool call status change
PlanSessionUpdate                // Todo list / plan
CurrentModeUpdateSessionUpdate   // Mode changed
AvailableCommandsUpdateSessionUpdate  // Slash commands
UnknownSessionUpdate             // Fallback for unknown types

// Request/Response types
InitializeRequest / InitializeResponse
NewSessionRequest / NewSessionResponse
PromptRequest / PromptResponse
RequestPermissionRequest / RequestPermissionResponse

// Capabilities
ClientCapabilities
FileSystemCapability  // (not FsCapabilities)
AgentCapabilities

// Permission handling
RequestPermissionRequest
RequestPermissionResponse
SelectedOutcome / CancelledOutcome  // (not RequestPermissionOutcome)
PermissionOption

// MCP Server configs
StdioMcpServer
HttpMcpServer
SseMcpServer
```

---

## Protocol Mapping

### Message Type Mapping

| Current Protocol | ACP Protocol |
|-----------------|--------------|
| `session.create` | `initialize` + `session/new` |
| `session.send` | `session/prompt` |
| `session.interrupt` | `session/cancel` |
| `session.kill` | N/A (close connection) |
| `callback.request` (can_use_tool) | `session/request_permission` |
| `callback.response` | Response to `session/request_permission` |
| `sdk.message` | `session/update` notifications |
| `query.call` | N/A (use MCP or custom methods) |

### SDK Message to Session Update Mapping

| SDK Message Type | ACP Session Update | Dart Type |
|-----------------|-------------------|-----------|
| `assistant` (text) | `agent_message_chunk` | `AgentMessageChunkSessionUpdate` |
| `assistant` (thinking) | `agent_thought_chunk` | `AgentThoughtChunkSessionUpdate` |
| `assistant` (tool_use) | `tool_call` | `ToolCallSessionUpdate` |
| `user` (tool_result) | `tool_call_update` | `ToolCallUpdateSessionUpdate` |
| `system` (init) | N/A (handled during initialize) | - |
| `result` | N/A (usage in prompt response) | - |

### Tool Call Status Mapping

| Current Status | ACP Status |
|---------------|------------|
| `pending` | `pending` |
| `running` | `in_progress` |
| `completed` | `completed` |
| `error` | `failed` |

---

## Frontend Service Changes

### AgentService (replaces BackendService)

```dart
/// Service for managing agent connections.
/// Uses ACPClientWrapper which wraps the acp_dart package.
class AgentService extends ChangeNotifier {
  AgentService({
    required this.agentRegistry,
  });

  final AgentRegistry agentRegistry;

  ACPClientWrapper? _client;
  AgentConfig? _currentAgent;

  bool get isConnected => _client?.isConnected ?? false;
  AgentConfig? get currentAgent => _currentAgent;
  AgentCapabilities? get capabilities => _client?.capabilities;

  /// Connect to an agent.
  Future<void> connect(AgentConfig config) async {
    await disconnect();

    _currentAgent = config;
    _client = ACPClientWrapper(agentConfig: config);

    await _client!.connect();
    notifyListeners();
  }

  /// Create a session for a chat.
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServerConfig>? mcpServers,
  }) async {
    if (_client == null || !_client!.isConnected) {
      throw StateError('Agent not connected');
    }

    return _client!.createSession(
      cwd: cwd,
      mcpServers: mcpServers,
    );
  }

  /// Disconnect from the current agent.
  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
    _currentAgent = null;
    notifyListeners();
  }
}
```

### AgentRegistry

```dart
/// Registry of available ACP agents.
class AgentRegistry extends ChangeNotifier {
  List<AgentConfig> _agents = [];

  List<AgentConfig> get agents => List.unmodifiable(_agents);

  /// Discover installed agents.
  Future<void> discover() async {
    _agents = [];

    // Check for Claude Code ACP
    final claudeCode = await _discoverClaudeCode();
    if (claudeCode != null) _agents.add(claudeCode);

    // Check for Gemini CLI
    final gemini = await _discoverGemini();
    if (gemini != null) _agents.add(gemini);

    // Check for Codex CLI
    final codex = await _discoverCodex();
    if (codex != null) _agents.add(codex);

    // Load custom agents from config
    final custom = await _loadCustomAgents();
    _agents.addAll(custom);

    notifyListeners();
  }

  Future<AgentConfig?> _discoverClaudeCode() async {
    // Check if claude-code-acp is installed
    final result = await Process.run('which', ['claude-code-acp']);
    if (result.exitCode != 0) return null;

    final path = (result.stdout as String).trim();
    return AgentConfig(
      id: 'claude-code',
      name: 'Claude Code',
      command: path,
      args: [],
      env: {}, // ANTHROPIC_API_KEY from environment
    );
  }

  Future<AgentConfig?> _discoverGemini() async {
    final result = await Process.run('which', ['gemini']);
    if (result.exitCode != 0) return null;

    return AgentConfig(
      id: 'gemini-cli',
      name: 'Gemini CLI',
      command: (result.stdout as String).trim(),
      args: ['--acp'],
      env: {},
    );
  }
}

/// Configuration for an ACP agent.
class AgentConfig {
  const AgentConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  final String id;
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;
}
```

### ChatState Updates

The `ChatState` class needs updates to work with `ACPSessionWrapper`:

```dart
class ChatState extends ChangeNotifier {
  // Replace ClaudeSession with ACPSessionWrapper
  ACPSessionWrapper? _session;
  StreamSubscription<SessionUpdate>? _updateSubscription;
  StreamSubscription<PendingPermission>? _permissionSubscription;

  Future<void> startSession({
    required AgentService agentService,
    required String prompt,
    required String cwd,
    List<McpServer>? mcpServers,
  }) async {
    _session = await agentService.createSession(
      cwd: cwd,
      mcpServers: mcpServers,
    );

    // Subscribe to session updates
    _updateSubscription = _session!.updates.listen(_handleSessionUpdate);
    _permissionSubscription = _session!.permissionRequests.listen(_handlePermissionRequest);

    // Send initial prompt
    await sendMessage(prompt);
  }

  void _handleSessionUpdate(SessionUpdate update) {
    // Use pattern matching on actual acp_dart types
    switch (update) {
      case AgentMessageChunkSessionUpdate(:final content):
        _handleAgentMessage(content);
      case AgentThoughtChunkSessionUpdate(:final content):
        _handleThinkingMessage(content);
      case ToolCallSessionUpdate update:
        _handleNewToolCall(update);
      case ToolCallUpdateSessionUpdate update:
        _handleToolCallUpdate(update);
      case PlanSessionUpdate(:final entries):
        _handlePlan(entries);
      case CurrentModeUpdateSessionUpdate(:final currentModeId):
        _handleModeChange(currentModeId);
      case UserMessageChunkSessionUpdate(:final content):
        _handleUserMessage(content);
      case AvailableCommandsUpdateSessionUpdate(:final availableCommands):
        _handleCommands(availableCommands);
      case UnknownSessionUpdate(:final rawJson):
        debugPrint('Unknown session update: $rawJson');
    }
    notifyListeners();
  }

  void _handleNewToolCall(ToolCallSessionUpdate update) {
    final entry = ToolUseOutputEntry(
      id: update.toolCallId,
      toolName: update.title ?? 'Unknown',
      toolInput: update.rawInput ?? {},
      status: _mapStatus(update.status),
    );
    addOutputEntry(primaryConversationId, entry);

    // Check if this is a Task tool (subagent)
    if (_isTaskTool(update.title)) {
      _handleTaskToolSpawn(update);
    }
  }

  void _handleToolCallUpdate(ToolCallUpdateSessionUpdate update) {
    final existing = _findToolEntry(update.toolCallId);
    if (existing != null) {
      existing.updateStatus(_mapStatus(update.status));
      if (update.content != null) {
        existing.updateContent(update.content!);
      }
    }
  }

  void _handlePermissionRequest(PendingPermission request) {
    addPendingPermission(request);
  }

  Future<void> sendMessage(String text) async {
    if (_session == null) return;

    _isWorking = true;
    notifyListeners();

    try {
      final result = await _session!.prompt([
        TextContentBlock(text: text),
      ]);

      // Handle stop reason
      _handleStopReason(result.stopReason);
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  Future<void> interrupt() async {
    await _session?.cancel();
  }
}
```

---

## Session Update Handler

Replace `SdkMessageHandler` with `SessionUpdateHandler`:

```dart
/// Handles ACP session updates and routes them to conversations.
class SessionUpdateHandler {
  SessionUpdateHandler({
    required this.chat,
  });

  final ChatState chat;

  // Mapping from toolCallId to conversation for subagents
  final _toolCallToConversation = <String, String>{};

  void handleUpdate(SessionUpdate update) {
    switch (update) {
      case AgentMessageChunkSessionUpdate(:final content):
        _handleAgentMessage(content);
      case AgentThoughtChunkSessionUpdate(:final content):
        _handleThinking(content);
      case ToolCallSessionUpdate update:
        _handleToolCall(update);
      case ToolCallUpdateSessionUpdate update:
        _handleToolCallUpdate(update);
      case PlanSessionUpdate(:final entries):
        _handlePlan(entries);
      case CurrentModeUpdateSessionUpdate(:final currentModeId):
        _handleModeChange(currentModeId);
      case UserMessageChunkSessionUpdate(:final content):
        // Usually for replaying history during session load
        _handleUserMessage(content);
      case AvailableCommandsUpdateSessionUpdate(:final availableCommands):
        _handleCommands(availableCommands);
      case UnknownSessionUpdate(:final rawJson):
        debugPrint('Unknown update: $rawJson');
    }
  }

  void _handleToolCall(ToolCallSessionUpdate update) {
    // Determine target conversation
    // ACP doesn't have parent_tool_use_id, but we can track via our state
    final conversationId = _routeToolCall(update);

    // New tool call
    _createToolEntry(conversationId, update);

    // Check for Task tool (subagent spawn)
    if (_isTaskTool(update)) {
      _spawnSubagent(update);
    }
  }

  void _handleToolCallUpdate(ToolCallUpdateSessionUpdate update) {
    // Update existing tool call status
    _updateToolEntry(update);

    // Check for Task completion
    if (_isTaskToolById(update.toolCallId) && _isCompleted(update.status)) {
      _completeSubagent(update.toolCallId);
    }
  }

  bool _isTaskTool(ToolCallSessionUpdate update) {
    // Check if this is a Task tool by examining title or rawInput
    final title = update.title?.toLowerCase() ?? '';
    return title.contains('task') ||
           title.contains('agent') ||
           (update.rawInput?['subagent_type'] != null);
  }

  void _spawnSubagent(ToolCallSessionUpdate update) {
    final input = update.rawInput ?? {};
    final subagentType = input['subagent_type'] as String? ?? 'general';
    final description = input['description'] as String? ?? update.title ?? 'Subagent';

    final conversationId = chat.addSubagentConversation(
      toolCallId: update.toolCallId,
      type: subagentType,
      description: description,
    );

    _toolCallToConversation[update.toolCallId] = conversationId;
  }

  String _routeToolCall(ToolCallSessionUpdate update) {
    // If we've mapped this tool call to a subagent, route there
    final mapped = _toolCallToConversation[update.toolCallId];
    if (mapped != null) return mapped;

    // Otherwise route to primary conversation
    return chat.primaryConversationId;
  }
}
```

---

## File System and Terminal Capabilities

ACP agents can request file system and terminal access from the client. CC-Insights must implement these handlers:

### File System Handler

```dart
/// Handles fs/* requests from the agent.
class FileSystemHandler {
  Future<Map<String, dynamic>> handleRequest(JsonRpcRequest request) async {
    return switch (request.method) {
      'fs/read_text_file' => _readTextFile(request.params),
      'fs/write_text_file' => _writeTextFile(request.params),
      _ => throw JsonRpcError.methodNotFound(request.method),
    };
  }

  Future<Map<String, dynamic>> _readTextFile(Map<String, dynamic> params) async {
    final path = params['path'] as String;
    final file = File(path);

    if (!await file.exists()) {
      throw JsonRpcError.invalidParams('File not found: $path');
    }

    final content = await file.readAsString();
    return {'content': content};
  }

  Future<Map<String, dynamic>> _writeTextFile(Map<String, dynamic> params) async {
    final path = params['path'] as String;
    final content = params['content'] as String;

    await File(path).writeAsString(content);
    return {};
  }
}
```

### Terminal Handler

```dart
/// Handles terminal/* requests from the agent.
class TerminalHandler {
  final _terminals = <String, TerminalSession>{};

  Future<Map<String, dynamic>> handleRequest(JsonRpcRequest request) async {
    return switch (request.method) {
      'terminal/create' => _create(request.params),
      'terminal/output' => _output(request.params),
      'terminal/wait_for_exit' => _waitForExit(request.params),
      'terminal/kill' => _kill(request.params),
      'terminal/release' => _release(request.params),
      _ => throw JsonRpcError.methodNotFound(request.method),
    };
  }

  Future<Map<String, dynamic>> _create(Map<String, dynamic> params) async {
    final command = params['command'] as String;
    final cwd = params['cwd'] as String?;

    final process = await Process.start(
      '/bin/sh',
      ['-c', command],
      workingDirectory: cwd,
    );

    final id = 'term_${DateTime.now().microsecondsSinceEpoch}';
    _terminals[id] = TerminalSession(
      id: id,
      process: process,
    );

    return {'terminalId': id};
  }

  Future<Map<String, dynamic>> _output(Map<String, dynamic> params) async {
    final id = params['terminalId'] as String;
    final terminal = _terminals[id];

    if (terminal == null) {
      throw JsonRpcError.invalidParams('Terminal not found: $id');
    }

    return {
      'output': terminal.output,
      'exitCode': terminal.exitCode,
    };
  }
}
```

---

## Migration Plan

### Phase 1: Add acp_dart Package & Wrapper Layer (Week 1)

1. Add `acp_dart: ^0.3.0` to `pubspec.yaml`
2. Create `lib/acp/` directory with wrapper classes:
   - `ACPClientWrapper` - wraps `ClientSideConnection`
   - `ACPSessionWrapper` - wraps session with Provider-friendly streams
3. Implement file system and terminal handlers for agent requests
4. Add unit tests for wrapper layer

### Phase 2: Agent Registry & Discovery (Week 1-2)

1. Implement `AgentRegistry` service
2. Add agent discovery for Claude Code, Gemini, Codex
3. Create agent configuration UI (settings panel)
4. Persist agent preferences to config file

### Phase 3: Frontend Integration (Week 2-3)

1. Replace `BackendService` with `AgentService`
2. Update `ChatState` to use `ACPSessionWrapper`
3. Replace `SdkMessageHandler` with `SessionUpdateHandler`
4. Update UI components for multi-agent support
5. Add agent selection UI to chat creation flow

### Phase 4: Remove Legacy Code (Week 3)

1. Remove `backend-node/` directory entirely
2. Remove `dart_sdk/` (old SDK wrapper)
3. Update all tests to use new ACP layer
4. Update documentation

### Phase 5: Polish & Testing (Week 3-4)

1. Integration testing with real agents (Claude Code, Gemini)
2. Handle agent-specific capabilities and features
3. Error handling and recovery improvements
4. Performance optimization

---

## Testing Strategy

### Unit Tests

```dart
void main() {
  group('ACPClientWrapper', () {
    test('connects to agent and initializes', () async {
      // Mock process, verify initialize flow
    });

    test('creates session correctly', () async {
      // Verify session/new call
    });

    test('handles file system requests from agent', () async {
      // Verify fs/read_text_file handler
    });
  });

  group('ACPSessionWrapper', () {
    test('sends prompt and receives updates', () async {
      // Mock connection, verify protocol flow
    });

    test('handles permission requests', () async {
      // Verify permission flow
    });

    test('cancels prompt correctly', () async {
      // Verify cancellation protocol
    });
  });

  group('SessionUpdateHandler', () {
    test('routes tool calls to correct conversation', () {
      // Verify routing logic
    });

    test('spawns subagent on Task tool', () {
      // Verify subagent creation
    });
  });
}
```

### Integration Tests

1. Connect to real Claude Code ACP adapter
2. Run through complete conversation flow
3. Verify permission handling end-to-end
4. Test session persistence and resume

---

## Appendix: ACP Protocol Reference

### Key Methods

| Method | Direction | Description |
|--------|-----------|-------------|
| `initialize` | Client → Agent | Negotiate protocol version and capabilities |
| `authenticate` | Client → Agent | Authenticate if required |
| `session/new` | Client → Agent | Create new session |
| `session/load` | Client → Agent | Resume existing session |
| `session/prompt` | Client → Agent | Send user message |
| `session/cancel` | Client → Agent | Cancel current turn |
| `session/set_mode` | Client → Agent | Change operating mode |
| `session/request_permission` | Agent → Client | Request tool permission |
| `fs/read_text_file` | Agent → Client | Read file content |
| `fs/write_text_file` | Agent → Client | Write file content |
| `terminal/create` | Agent → Client | Create terminal |
| `terminal/output` | Agent → Client | Get terminal output |

### Key Notifications

| Notification | Direction | Description |
|--------------|-----------|-------------|
| `session/update` | Agent → Client | Session state change |

### Session Update Types

- `agent_message_chunk` - Agent text output
- `user_message_chunk` - User message (replay)
- `thought_message_chunk` - Agent thinking/reasoning
- `tool_call` - New tool call
- `tool_call_update` - Tool call status change
- `plan` - Agent's task plan
- `current_mode_update` - Mode changed
- `available_commands_update` - Available slash commands

---

## References

- [ACP Documentation](https://agentclientprotocol.com/)
- [acp_dart Package](https://github.com/SkrOYC/acp-dart) - Dart implementation we're using
- [ACP Schema](../packages/agent-client-protocol/schema/schema.json) - JSON Schema for code generation
- [Claude Code ACP Adapter](https://github.com/zed-industries/claude-code-acp)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)
- [MCP Content Types](https://modelcontextprotocol.io/specification/2025-06-18/schema#contentblock)
