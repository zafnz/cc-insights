# Quick Reference

A condensed reference for the Dart SDK architecture.

## Architecture Diagram

```
┌──────────────────┐
│   Flutter App    │
│   (UI Layer)     │
└────────┬─────────┘
         │ uses
┌────────▼─────────┐
│    Dart SDK      │
│  ClaudeBackend   │
│  ClaudeSession   │
└────────┬─────────┘
         │ stdin/stdout (JSON lines)
┌────────▼─────────┐
│  Node Backend    │
│  (~200 lines)    │
└────────┬─────────┘
         │ spawns via SDK
┌────────▼─────────┐
│   Claude CLI     │
└──────────────────┘
```

## Protocol Summary

### Dart → Backend

| Message | Purpose |
|---------|---------|
| `session.create` | Start new session |
| `session.send` | Send follow-up |
| `session.interrupt` | Stop execution |
| `session.kill` | Terminate session |
| `callback.response` | Respond to permission/hook |
| `query.call` | Call Query method |

### Backend → Dart

| Message | Purpose |
|---------|---------|
| `session.created` | Session started |
| `sdk.message` | Raw SDK message |
| `callback.request` | Need permission/hook response |
| `query.result` | Query method result |
| `session.interrupted` | Interrupted |
| `session.killed` | Terminated |
| `error` | Error occurred |

## Dart SDK API

```dart
// Spawn backend
final backend = await ClaudeBackend.spawn();

// Create session
final session = await backend.createSession(
  prompt: 'Hello',
  cwd: '/path/to/project',
  options: SessionOptions(model: 'sonnet'),
);

// Listen to messages
session.messages.listen((msg) { ... });

// Handle permissions
session.permissionRequests.listen((req) {
  req.allow();  // or req.deny('reason');
});

// Send follow-up
await session.send('Do something else');

// Interrupt
await session.interrupt();

// Query methods
final models = await session.supportedModels();
await session.setModel('opus');

// Cleanup
await backend.dispose();
```

## SDK Message Types

| Type | Description |
|------|-------------|
| `SDKSystemMessage` | Session init, compact boundary |
| `SDKAssistantMessage` | Claude's response |
| `SDKUserMessage` | User input, tool results |
| `SDKResultMessage` | Turn complete, usage |
| `SDKStreamEvent` | Partial streaming |

## Content Blocks

| Type | Description |
|------|-------------|
| `TextBlock` | Text content |
| `ThinkingBlock` | Thinking content |
| `ToolUseBlock` | Tool invocation |
| `ToolResultBlock` | Tool result |
| `ImageBlock` | Image content |

## Session Options

```dart
SessionOptions(
  model: 'sonnet',
  permissionMode: PermissionMode.default_,
  allowedTools: ['Read', 'Write', 'Bash'],
  disallowedTools: [],
  systemPrompt: PresetSystemPrompt(),
  maxTurns: 100,
  maxBudgetUsd: 1.0,
  maxThinkingTokens: 10000,
  includePartialMessages: true,
  enableFileCheckpointing: true,
  additionalDirectories: ['/other/path'],
  settingSources: [SettingSource.user, SettingSource.project],
  betas: ['context-1m-2025-08-07'],
)
```

## Callback Flow

```
SDK calls canUseTool
    ↓
Backend sends callback.request
    ↓
Dart receives PermissionRequest
    ↓
UI shows dialog
    ↓
User clicks allow/deny
    ↓
Dart sends callback.response
    ↓
Backend resolves Promise
    ↓
SDK continues
```

## File Structure

```
backend-node/src/
├── index.ts           # Entry point
├── session-manager.ts # Session lifecycle
├── callback-bridge.ts # Pending callbacks
└── protocol.ts        # Message types

dart_sdk/lib/
├── claude_sdk.dart    # Exports
└── src/
    ├── backend.dart   # ClaudeBackend
    ├── session.dart   # ClaudeSession
    ├── protocol.dart  # JSON line I/O
    └── types/
        ├── sdk_messages.dart
        ├── session_options.dart
        ├── callbacks.dart
        └── usage.dart

flutter_app/lib/
├── main.dart          # Spawn backend
└── providers/
    └── app_state.dart # Uses Dart SDK
```

## Implementation Phases

1. **Protocol** - Define JSON messages
2. **Node Backend** - Thin bridge (~200 lines)
3. **Dart Types** - SDK message classes
4. **Dart SDK** - ClaudeBackend, ClaudeSession
5. **Flutter** - Wire up to new SDK
6. **Polish** - Error handling, bundling

## Key Design Principles

1. **Raw forwarding** - SDK messages passed verbatim
2. **Unified callbacks** - Same mechanism for permissions + hooks
3. **Subprocess model** - Backend is child process, no ports
4. **Session multiplexing** - Multiple sessions, one backend
5. **Dart owns logic** - Backend makes no decisions
