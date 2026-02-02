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
│ ClaudeCliBackend │
│    CliSession    │
│    CliProcess    │
└────────┬─────────┘
         │ stdin/stdout (stream-json)
┌────────▼─────────┐
│   Claude CLI     │
│ (one per session)│
└──────────────────┘
```

## Protocol Summary

### Dart → CLI

| Message | Purpose |
|---------|---------|
| `control_request` | Initialize, get commands/models |
| `session.create` | Start new session |
| `session.send` | Send follow-up |
| `session.interrupt` | Stop execution |
| `callback.response` | Respond to permission request |

### CLI → Dart

| Message | Purpose |
|---------|---------|
| `control_response` | Commands, models, account |
| `session.created` | Session started |
| `system` | Init, tools, MCP servers |
| `assistant` | Claude's response |
| `user` | Tool results |
| `result` | Turn complete |
| `callback.request` | Need permission response |
| `error` | Error occurred |

## Dart SDK API

### Using BackendFactory

```dart
// Create backend (direct CLI)
final backend = await BackendFactory.create(
  type: BackendType.directCli,
);

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

// Cleanup
await backend.dispose();
```

### One-Shot Requests

```dart
// Create client (no backend needed)
final claude = ClaudeSingleRequest();

// Make a single request
final result = await claude.request(
  prompt: 'Generate a commit message for staged changes',
  workingDirectory: '/path/to/repo',
  options: SingleRequestOptions(
    model: 'haiku',
    allowedTools: ['Bash(git:*)', 'Read'],
  ),
);

if (result != null && !result.isError) {
  print(result.result);
  print('Cost: \$${result.totalCostUsd}');
}
```

## SDK Message Types

| Type | Description |
|------|-------------|
| `SDKSystemMessage` | Session init, compact boundary |
| `SDKAssistantMessage` | Claude's response |
| `SDKUserMessage` | User input, tool results |
| `SDKResultMessage` | Turn complete, usage |
| `SDKStreamEvent` | Partial streaming |
| `SDKControlRequest` | Permission request from CLI |
| `SDKControlResponse` | Initialize response |

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

## Permission Flow

```
CLI sends callback.request
    ↓
CliSession emits CliPermissionRequest
    ↓
UI shows dialog
    ↓
User clicks allow/deny
    ↓
App calls request.allow() or request.deny()
    ↓
Dart sends callback.response
    ↓
CLI continues or aborts
```

## File Structure

```
dart_sdk/lib/
├── claude_sdk.dart           # Exports
└── src/
    ├── cli_process.dart      # CliProcess
    ├── cli_session.dart      # CliSession
    ├── cli_backend.dart      # ClaudeCliBackend
    ├── backend_factory.dart  # BackendFactory
    ├── backend_interface.dart # AgentBackend, AgentSession
    ├── single_request.dart   # ClaudeSingleRequest (one-shot)
    └── types/
        ├── sdk_messages.dart
        ├── control_messages.dart
        ├── session_options.dart
        ├── callbacks.dart
        └── usage.dart

frontend/lib/
├── main.dart
└── services/
    └── backend_service.dart  # Uses BackendFactory
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CODE_PATH` | Path to claude CLI executable |

## Key Design Principles

1. **Direct CLI** - No intermediate Node.js process
2. **Session per process** - Each session spawns own CLI
3. **Stream-json protocol** - Bidirectional JSON lines
4. **Permission routing** - CLI requests routed to UI
5. **Clean lifecycle** - Process death = session end
