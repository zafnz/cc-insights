# Claude Dart SDK

A Dart/Flutter SDK for communicating with Claude Code agents via the Claude CLI.

## Overview

The Claude Dart SDK provides native Dart bindings for interacting with Claude AI agents through the Claude CLI. It supports:

- **Direct CLI communication** via stdin/stdout JSON streaming
- **Session management** with persistent conversations
- **Permission handling** for tool approvals
- **Multi-modal input** including images
- **Token usage and cost tracking**
- **Subagent support** for complex workflows

## Quick Start

```dart
import 'package:claude_sdk/claude_sdk.dart';

void main() async {
  // Create a backend
  final backend = await BackendFactory.create();

  try {
    // Create a session
    final session = await backend.createSession(
      prompt: 'Hello, Claude!',
      cwd: '/my/project',
    );

    // Listen for messages
    session.messages.listen((msg) {
      if (msg is SDKAssistantMessage) {
        print('Claude: ${msg.textContent}');
      } else if (msg is SDKResultMessage) {
        print('Cost: \$${msg.totalCostUsd}');
      }
    });

    // Handle permission requests
    session.permissionRequests.listen((request) {
      print('Permission needed for: ${request.toolName}');
      request.allow(); // Or request.deny('reason')
    });

    // Send follow-up messages
    await session.send('What files are in this directory?');

  } finally {
    await backend.dispose();
  }
}
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                     Your Flutter App                      │
└────────────────────────────┬─────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────┐
│                    Claude Dart SDK                        │
│  ┌─────────────────────────────────────────────────────┐ │
│  │            BackendFactory.create()                   │ │
│  └────────────────────────┬────────────────────────────┘ │
│                           │                              │
│  ┌────────────────────────▼────────────────────────────┐ │
│  │              AgentBackend Interface                  │ │
│  │                                                      │ │
│  │              ┌───────────────────────┐              │ │
│  │              │   ClaudeCliBackend    │              │ │
│  │              └───────────┬───────────┘              │ │
│  └──────────────────────────┼──────────────────────────┘ │
│             │                                            │
│  ┌──────────▼──────────────────────────────────────────┐ │
│  │              AgentSession Interface                  │ │
│  │                                                      │ │
│  │  • messages stream      • permissionRequests stream │ │
│  │  • send()               • interrupt()               │ │
│  │  • sendWithContent()    • kill()                    │ │
│  │  • setModel()           • setPermissionMode()       │ │
│  └──────────┬──────────────────────────────────────────┘ │
└─────────────┼────────────────────────────────────────────┘
              │
┌─────────────▼────────────────────────────────────────────┐
│                      Claude CLI                           │
│              (stdin/stdout JSON stream)                   │
└──────────────────────────────────────────────────────────┘
```

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](GETTING_STARTED.md) | Setup, installation, and basic usage |
| [API Reference](API_REFERENCE.md) | Complete API documentation |
| [Protocol](PROTOCOL.md) | Claude CLI JSON stream protocol |
| [Examples](EXAMPLES.md) | Code examples and patterns |
| [Agent Howto](AGENT_HOWTO.md) | Concise guide for AI agents |

## Key Concepts

### Backend

The SDK uses a **Direct CLI Backend** that spawns a separate `claude` CLI process for each session. This provides:

- Isolation between sessions
- Clean process lifecycle management
- Direct communication via stdin/stdout JSON streaming

### Sessions

A session represents an ongoing conversation with Claude. Sessions:

- Have a unique `sessionId`
- Emit messages via the `messages` stream
- Emit permission requests via the `permissionRequests` stream
- Support sending text and multi-modal content
- Can be interrupted or killed

### Messages

The SDK uses typed message classes:

| Type | Description |
|------|-------------|
| `SDKSystemMessage` | System initialization and status |
| `SDKAssistantMessage` | Claude's responses |
| `SDKUserMessage` | User messages and tool results |
| `SDKResultMessage` | Turn completion with usage data |
| `SDKStreamEvent` | Streaming content deltas |
| `SDKErrorMessage` | Error notifications |

### Permissions

When Claude wants to use a tool, it may request permission. The SDK provides:

- `permissionRequests` stream for receiving requests
- `allow()` and `deny()` methods for responding
- Permission modes (`default`, `acceptEdits`, `bypassPermissions`, `plan`)
- Permission suggestions for auto-approval rules

## Requirements

- Dart SDK >= 3.0.0
- Claude CLI installed and accessible in PATH
- Valid Claude API key or Claude Max subscription

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  claude_sdk:
    path: ../claude_dart_sdk  # Or your path to the SDK
```

## License

See the project's LICENSE file for details.
