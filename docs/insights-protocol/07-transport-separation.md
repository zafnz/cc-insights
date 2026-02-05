# Transport Separation & Containerization

This document describes how the InsightsEvent model enables separating backends from the frontend, running them in Docker containers or on remote hosts.

## Goal

Today, backends run **in-process** — the Flutter app spawns Claude CLI or Codex as subprocesses directly. This works but has limitations:

- **Security**: Agent subprocesses run with the same permissions as the desktop app
- **Isolation**: A misbehaving agent can crash the app, consume all memory, or modify the app's files
- **Scalability**: Multiple heavy agent sessions compete for the same machine's resources
- **Deployment**: Can't run agents on a beefy remote server while viewing results on a lightweight client

The InsightsEvent model is designed to be **transport-agnostic**: the same events flow whether the backend is in-process, in a container, or across a network.

## Architecture

### Current: In-Process

```
┌─────────────────────────────────────┐
│           Flutter App               │
│                                     │
│  EventHandler ← Stream<InsightsEvent> ← BackendAdapter
│                                     │      ↓
│                                     │  [CliProcess]
│                                     │  (subprocess)
│                                     │      ↓
│                                     │  Claude CLI
└─────────────────────────────────────┘
```

### Future: Remote/Containerized

```
┌────────────────────┐     WebSocket/gRPC     ┌─────────────────────┐
│    Flutter App      │◄─────────────────────►│   Backend Container  │
│                     │     InsightsEvent       │                     │
│  EventHandler       │     (serialized)       │  BackendAdapter      │
│  ← Stream<I.E.>    │                        │  ← CliProcess        │
│  ← from Transport   │                        │  ← Claude CLI        │
│                     │                        │  → serializes I.E.   │
└────────────────────┘                        └─────────────────────┘
```

## InsightsEvent Serialization

Every `InsightsEvent` must be serializable to JSON for transport. The `raw` field (original wire data) is also serialized, preserving the debug viewer's ability to show original backend messages.

```dart
sealed class InsightsEvent {
  Map<String, dynamic> toJson();
  static InsightsEvent fromJson(Map<String, dynamic> json);
}
```

### Wire Format

Events are transported as newline-delimited JSON (JSONL), matching the established pattern:

```jsonl
{"event":"session_init","id":"ev-001","timestamp":"...","sessionId":"abc","model":"claude-sonnet-4-5","provider":"claude","cwd":"/project","availableTools":["Bash","Read",...]}
{"event":"tool_invocation","id":"ev-002","timestamp":"...","callId":"tu-001","kind":"execute","toolName":"Bash","input":{"command":"npm test"}}
{"event":"stream_delta","id":"ev-003","timestamp":"...","kind":"text","textDelta":"Running "}
{"event":"stream_delta","id":"ev-004","timestamp":"...","kind":"text","textDelta":"tests..."}
{"event":"tool_completion","id":"ev-005","timestamp":"...","callId":"tu-001","status":"completed","output":{"stdout":"OK","exit_code":0}}
{"event":"turn_complete","id":"ev-006","timestamp":"...","costUsd":0.012,"usage":{"inputTokens":5000,"outputTokens":1200}}
```

### Event Type Discriminator

The `event` field identifies the event type for deserialization:

| `event` value | Dart class |
|---------------|------------|
| `session_init` | `SessionInitEvent` |
| `session_status` | `SessionStatusEvent` |
| `text` | `TextEvent` |
| `user_input` | `UserInputEvent` |
| `tool_invocation` | `ToolInvocationEvent` |
| `tool_completion` | `ToolCompletionEvent` |
| `subagent_spawn` | `SubagentSpawnEvent` |
| `subagent_complete` | `SubagentCompleteEvent` |
| `turn_complete` | `TurnCompleteEvent` |
| `context_compaction` | `ContextCompactionEvent` |
| `permission_request` | `PermissionRequestEvent` |
| `stream_delta` | `StreamDeltaEvent` |

## Transport Layer

### `EventTransport` Interface

```dart
abstract class EventTransport {
  /// Incoming events from the backend.
  Stream<InsightsEvent> get events;

  /// Send a command to the backend (user message, permission response, etc.)
  Future<void> send(BackendCommand command);

  /// Connection status.
  Stream<TransportStatus> get status;

  /// Clean up.
  Future<void> dispose();
}

enum TransportStatus { connecting, connected, disconnected, error }
```

### Transport Implementations

#### `InProcessTransport`

The current model — backend runs in the same process.

```dart
class InProcessTransport implements EventTransport {
  final AgentSession _session;

  @override
  Stream<InsightsEvent> get events => _session.events;

  @override
  Future<void> send(BackendCommand command) async {
    switch (command) {
      case SendMessageCommand c:
        await _session.send(c.text);
      case PermissionResponseCommand c:
        c.request.allow(); // or deny
      case InterruptCommand _:
        await _session.interrupt();
    }
  }
}
```

#### `WebSocketTransport`

For remote backends over WebSocket.

```dart
class WebSocketTransport implements EventTransport {
  final WebSocket _socket;

  @override
  Stream<InsightsEvent> get events =>
    _socket.stream
      .map((data) => jsonDecode(data))
      .map((json) => InsightsEvent.fromJson(json));

  @override
  Future<void> send(BackendCommand command) async {
    _socket.add(jsonEncode(command.toJson()));
  }
}
```

#### `DockerTransport`

Manages a Docker container lifecycle and connects via stdio or port mapping.

```dart
class DockerTransport implements EventTransport {
  final String _imageName;
  final String _containerName;
  Process? _container;

  Future<void> start({
    required String cwd,
    required Map<String, String> env,
    List<String>? volumes,
  }) async {
    _container = await Process.start('docker', [
      'run', '--rm', '-i',
      '--name', _containerName,
      '-v', '$cwd:/workspace',
      '-e', 'ANTHROPIC_API_KEY=${env['ANTHROPIC_API_KEY']}',
      _imageName,
    ]);
    // Container reads JSONL commands on stdin, writes JSONL events on stdout
  }
}
```

## Backend Commands (Frontend → Backend)

Commands flow in the reverse direction. They are also serializable.

```dart
sealed class BackendCommand {
  Map<String, dynamic> toJson();
  static BackendCommand fromJson(Map<String, dynamic> json);
}

class SendMessageCommand extends BackendCommand {
  final String sessionId;
  final String text;
  final List<ImageData>? images;
}

class PermissionResponseCommand extends BackendCommand {
  final String requestId;
  final bool allowed;
  final String? message;
  final Map<String, dynamic>? updatedInput;
}

class InterruptCommand extends BackendCommand {
  final String sessionId;
}

class SetModelCommand extends BackendCommand {
  final String sessionId;
  final String model;
}

class SetPermissionModeCommand extends BackendCommand {
  final String sessionId;
  final String mode;
}

class CreateSessionCommand extends BackendCommand {
  final String cwd;
  final String prompt;
  final Map<String, dynamic>? options;
}
```

## Permission Handling Over Transport

Permissions are the trickiest part of transport separation because they require a round-trip:

1. Backend emits `PermissionRequestEvent`
2. Frontend shows dialog, user decides
3. Frontend sends `PermissionResponseCommand`
4. Backend receives response, continues/aborts

In-process, this uses a `Completer<PermissionResponse>` on the `PermissionRequest` object. Over a transport, the `Completer` doesn't exist on the frontend side.

### Solution: Request ID Correlation

```dart
// Backend side (in container):
class RemotePermissionBridge {
  final _pendingPermissions = <String, Completer<PermissionResponse>>{};

  void handlePermissionRequest(PermissionRequest request) {
    _pendingPermissions[request.id] = request._completer;
    // Emit InsightsEvent to transport
    transport.emit(PermissionRequestEvent.from(request));
  }

  void handlePermissionResponse(PermissionResponseCommand cmd) {
    final completer = _pendingPermissions.remove(cmd.requestId);
    if (completer == null) return;
    if (cmd.allowed) {
      completer.complete(PermissionAllowResponse(updatedInput: cmd.updatedInput));
    } else {
      completer.complete(PermissionDenyResponse(message: cmd.message));
    }
  }
}
```

The `requestId` correlates the frontend's response with the backend's pending Completer. This works identically for all backends (Claude, Codex, ACP) since they all use the `PermissionRequest` pattern already.

## Docker Container Design

### Backend Container Image

A single container image per backend type:

```dockerfile
# claude-backend/Dockerfile
FROM node:20-slim
RUN npm install -g @anthropic-ai/claude-code
COPY backend-bridge /usr/local/bin/
ENTRYPOINT ["backend-bridge", "--backend=claude"]
```

The `backend-bridge` binary:
1. Reads `CreateSessionCommand` from stdin
2. Spawns the agent subprocess internally
3. Translates agent events → `InsightsEvent` JSONL on stdout
4. Reads `BackendCommand` JSONL from stdin
5. Forwards commands to the agent subprocess

### Volume Mounts

The container needs access to the project files:

```
docker run -v /Users/zaf/project:/workspace \
           -e ANTHROPIC_API_KEY=sk-... \
           cc-insights-claude-backend
```

### Security Model

| Concern | Mitigation |
|---------|------------|
| Agent modifies app files | Container only mounts project dir, not app dir |
| Agent reads API keys | Only the needed key is passed via env var |
| Agent consumes all memory | Docker memory limits (`--memory 4g`) |
| Agent runs for too long | Docker CPU limits + timeout |
| Agent opens network connections | Docker network restrictions (`--network none` for paranoid mode) |
| Agent crashes | Container restarts cleanly; frontend reconnects |

### Process Architecture Per Backend

| Backend | Container Count | Why |
|---------|----------------|-----|
| Claude | One per session | Claude CLI = one process per session |
| Codex | One per backend | Codex = single shared process, multiplexed sessions |
| ACP | One per agent | ACP agents are typically single-process |

## Phased Rollout

### Phase 1: Transport Interface (No Docker)

- Define `EventTransport` interface
- Implement `InProcessTransport` wrapping the current in-process backends
- Frontend consumes `Stream<InsightsEvent>` via transport, not directly from sessions
- **No behavioral change** — same code paths, just abstracted behind an interface

### Phase 2: WebSocket Transport

- Implement `WebSocketTransport`
- Create a simple backend server that wraps the existing SDK in a WebSocket endpoint
- Test with backend running as a separate local process
- Enables remote viewing (e.g., watch agent progress from your phone)

### Phase 3: Docker Transport

- Create container images for each backend
- Implement `DockerTransport` with container lifecycle management
- Volume mounting for project access
- Environment variable passing for API keys
- Resource limits and health checks

### Phase 4: Multi-Machine

- Backend containers on remote servers (cloud VMs, dedicated hardware)
- Frontend connects over secure WebSocket
- Authentication and authorization for multi-user scenarios
- Session persistence across frontend restarts (reconnect to running backend)

## Compatibility

The transport layer is invisible to:
- `EventHandler` — consumes `Stream<InsightsEvent>` regardless of source
- `OutputEntry` — persistence is frontend-local regardless of where events come from
- `ToolCard` — renders `ToolUseOutputEntry` regardless of transport

The transport layer is visible to:
- `BackendService` — creates transports instead of direct sessions
- Permission dialogs — send `PermissionResponseCommand` instead of calling `allow()`/`deny()` directly
- Settings — choose between in-process, local container, or remote backend
