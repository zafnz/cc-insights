# Dart SDK Architecture Overview

This document describes the architecture for Claude Agent Insights, featuring a Dart SDK that communicates directly with the Claude CLI.

## Goals

1. **Direct CLI communication** - No intermediate Node.js backend
2. **Native Dart SDK** - First-class Dart/Flutter API for Claude
3. **No data loss** - Raw SDK messages forwarded, frontend has full information
4. **Consistent patterns** - Same stdin/stdout JSON pattern
5. **Simplified deployment** - No Node.js dependency, just the Claude CLI

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter App (UI layer)                             │
│  - Widgets, screens, state management               │
│  - Uses Dart SDK for all Claude interactions        │
└─────────────────────┬───────────────────────────────┘
                      │ imports
┌─────────────────────▼───────────────────────────────┐
│  Dart SDK (claude_dart_sdk/)                               │
│  - BackendFactory: backend type selection           │
│  - ClaudeCliBackend: manages CLI sessions           │
│  - CliSession: session API, streams                 │
│  - CliProcess: subprocess management                │
│  - SDK message types as Dart classes                │
│  - Permission request handling                      │
└─────────────────────┬───────────────────────────────┘
                      │ spawns, stdin/stdout JSON lines
                      │ --output-format stream-json
                      │ --input-format stream-json
┌─────────────────────▼───────────────────────────────┐
│  Claude CLI (claude binary)                         │
│  - One process per session                          │
│  - Handles tool execution, permissions              │
│  - Manages MCP servers                              │
└─────────────────────┬───────────────────────────────┘
                      │ Claude API
┌─────────────────────▼───────────────────────────────┐
│  Anthropic API                                      │
└─────────────────────────────────────────────────────┘
```

## Communication Pattern

The Dart SDK communicates with the Claude CLI using **newline-delimited JSON over stdin/stdout**.

```
Dart SDK                          Claude CLI
     │                                  │
     │──── JSON line (stdin) ──────────>│
     │                                  │
     │<─── JSON line (stdout) ──────────│
     │                                  │
     │<─── debug logs (stderr) ─────────│
```

## Key Design Decisions

### 1. Direct CLI Communication

The Dart SDK spawns the Claude CLI directly with stream-json format:

```bash
claude --output-format stream-json \
       --input-format stream-json \
       --permission-prompt-tool stdio \
       --cwd /path/to/project
```

### 2. Session per Process

Each CLI session spawns a separate `claude` process:
- Clean isolation between sessions
- Natural resource cleanup when process exits
- Simple lifecycle management

### 3. Permission Request Flow

Permission requests from the CLI are routed to the UI:

1. CLI sends `callback.request` with `subtype: "can_use_tool"`
2. Dart SDK emits on `CliSession.permissionRequests` stream
3. UI shows permission dialog
4. User approves/denies
5. Dart SDK sends `callback.response` to CLI
6. CLI continues or aborts tool execution

### 4. Initialization Sequence

Session initialization follows the CLI protocol:

1. Dart sends `control_request` with `subtype: "initialize"`
2. CLI responds with `control_response` (commands, models, account)
3. CLI sends `system` message with `subtype: "init"` (tools, MCP servers)
4. Dart sends `session.create` with initial prompt
5. CLI sends `session.created` confirmation
6. Message streaming begins

## Documents

| Document | Description |
|----------|-------------|
| [01-implementation-plan.md](./01-implementation-plan.md) | Phased implementation plan |
| [02-protocol.md](./02-protocol.md) | JSON protocol specification |
| [03-dart-sdk-api.md](./03-dart-sdk-api.md) | Dart SDK public API |
| [05-flutter-integration.md](./05-flutter-integration.md) | Flutter app integration |
| [06-sdk-message-types.md](./06-sdk-message-types.md) | SDK message type reference |

## File Structure

```
claude-project/
├── claude_dart_sdk/                        # Dart SDK
│   ├── lib/
│   │   ├── claude_sdk.dart          # Public exports
│   │   └── src/
│   │       ├── cli_process.dart     # CliProcess - subprocess management
│   │       ├── cli_session.dart     # CliSession - session API
│   │       ├── cli_backend.dart     # ClaudeCliBackend - backend impl
│   │       ├── backend_factory.dart # BackendFactory - type selection
│   │       ├── backend_interface.dart # AgentBackend/AgentSession interfaces
│   │       └── types/
│   │           ├── sdk_messages.dart
│   │           ├── control_messages.dart
│   │           ├── session_options.dart
│   │           ├── callbacks.dart
│   │           └── usage.dart
│   ├── pubspec.yaml
│   └── test/
│       ├── cli_process_test.dart
│       ├── cli_session_test.dart
│       ├── cli_backend_test.dart
│       └── integration/
│           └── cli_integration_test.dart
│
├── frontend/                        # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   └── backend_service.dart # Uses BackendFactory
│   │   └── widgets/
│   └── pubspec.yaml
│
└── docs/
    └── dart-sdk/                    # This documentation
```

## Benefits

1. **Simpler architecture** - No Node.js backend to manage
2. **Lower memory footprint** - One less process per session
3. **Easier debugging** - Direct communication with CLI
4. **Direct access to CLI features** - No translation layer
5. **Full SDK fidelity** - No information lost in translation
6. **Type safety** - Dart classes match CLI protocol exactly
