# Dart SDK Architecture Overview

This document describes the new architecture for Claude Agent Insights, featuring a thin Node.js backend and a Dart SDK that provides a native Flutter interface to the Claude Agent SDK.

## Goals

1. **Thin backend** - Node.js backend becomes a minimal bridge (~200 lines)
2. **Native Dart SDK** - First-class Dart/Flutter API for Claude Agent SDK
3. **No data loss** - Raw SDK messages forwarded, frontend has full information
4. **Consistent patterns** - Same stdin/stdout JSON pattern at every layer
5. **Simplified deployment** - Backend is a subprocess, no network ports

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter App (UI layer)                             │
│  - Widgets, screens, state management               │
│  - Uses Dart SDK for all Claude interactions        │
└─────────────────────┬───────────────────────────────┘
                      │ imports
┌─────────────────────▼───────────────────────────────┐
│  Dart SDK (dart_sdk/)                               │
│  - ClaudeBackend: process lifecycle                 │
│  - ClaudeSession: session API, streams              │
│  - SDK message types as Dart classes                │
│  - Callback handling (permissions, hooks)           │
└─────────────────────┬───────────────────────────────┘
                      │ spawns, stdin/stdout JSON lines
┌─────────────────────▼───────────────────────────────┐
│  Node Backend (~200 lines)                          │
│  - Session map: id → { query, abortController }     │
│  - Forward raw SDK messages to stdout               │
│  - Bridge callbacks (canUseTool, hooks)             │
│  - Proxy Query method calls                         │
└─────────────────────┬───────────────────────────────┘
                      │ spawns via @anthropic-ai/claude-agent-sdk
┌─────────────────────▼───────────────────────────────┐
│  Claude CLI (claude binary)                         │
└─────────────────────────────────────────────────────┘
```

## Communication Pattern

Every layer uses the same pattern: **newline-delimited JSON over stdin/stdout**.

```
Parent Process                     Child Process
     │                                  │
     │──── JSON line (stdin) ──────────>│
     │                                  │
     │<─── JSON line (stdout) ──────────│
     │                                  │
     │<─── debug logs (stderr) ─────────│
```

This is how:
- The Claude Agent SDK communicates with the Claude CLI
- Our Node backend communicates with the Claude Agent SDK
- Our Dart SDK communicates with the Node backend

## Key Design Decisions

### 1. Raw SDK Message Forwarding

The Node backend forwards SDK messages **verbatim**. No transformation, no filtering. The Dart SDK receives exactly what the TypeScript SDK produces.

```
SDK produces:  { "type": "assistant", "uuid": "...", "message": {...} }
Backend sends: { "type": "sdk.message", "payload": { "type": "assistant", ... } }
Dart receives: SDKAssistantMessage with all fields intact
```

### 2. Unified Callback Bridge

Both `canUseTool` and hooks use the same mechanism:

1. SDK invokes callback
2. Backend generates callback ID, stores Promise
3. Backend sends `callback.request` to Dart
4. Dart processes, sends `callback.response`
5. Backend resolves Promise, returns to SDK

This means adding new callback types requires zero backend changes.

### 3. Subprocess Lifecycle

The Flutter app spawns the Node backend as a subprocess:
- Backend starts when app starts
- Backend dies when app dies
- No orphan processes
- No port conflicts

### 4. Session Multiplexing

Multiple Claude sessions share one backend process:
- Each session has unique ID
- All messages tagged with session ID
- Backend routes to correct session
- Dart SDK demultiplexes streams by session

## Documents

| Document | Description |
|----------|-------------|
| [01-implementation-plan.md](./01-implementation-plan.md) | Phased implementation plan |
| [02-protocol.md](./02-protocol.md) | JSON protocol specification |
| [03-dart-sdk-api.md](./03-dart-sdk-api.md) | Dart SDK public API |
| [04-node-backend.md](./04-node-backend.md) | Node backend implementation |
| [05-flutter-integration.md](./05-flutter-integration.md) | Flutter app changes |
| [06-sdk-message-types.md](./06-sdk-message-types.md) | SDK message type reference |

## File Structure

```
claude-project/
├── backend-node/                    # REWRITE - thin wrapper
│   ├── src/
│   │   ├── index.ts                 # Entry: stdin/stdout loop
│   │   ├── session-manager.ts       # Session lifecycle
│   │   ├── callback-bridge.ts       # Pending promises
│   │   └── protocol.ts              # Message types
│   ├── package.json
│   └── tsconfig.json
│
├── dart_sdk/                        # NEW - Dart SDK
│   ├── lib/
│   │   ├── claude_sdk.dart          # Public exports
│   │   └── src/
│   │       ├── backend.dart         # ClaudeBackend
│   │       ├── session.dart         # ClaudeSession
│   │       ├── protocol.dart        # JSON line I/O
│   │       └── types/
│   │           ├── sdk_messages.dart
│   │           ├── session_options.dart
│   │           ├── callbacks.dart
│   │           └── usage.dart
│   ├── pubspec.yaml
│   └── test/
│
├── flutter_app/                     # REFACTOR
│   ├── lib/
│   │   ├── main.dart                # Spawn backend
│   │   ├── providers/
│   │   │   └── app_provider.dart    # Uses Dart SDK
│   │   └── widgets/                 # Mostly unchanged
│   └── pubspec.yaml
│
└── docs/
    └── dart-sdk/                    # This documentation
```

## What Gets Deleted

| File | Reason |
|------|--------|
| `backend-node/src/agent-manager.ts` | Replaced by thin session-manager |
| `backend-node/src/agent-tracker.ts` | Logic moves to Dart SDK |
| `backend-node/src/question-handler.ts` | Unified callback bridge |
| `backend-node/src/permission-handler.ts` | Unified callback bridge |
| `flutter_app/lib/services/websocket_service.dart` | Replaced by Dart SDK |
| `flutter_app/lib/models/messages.dart` | Replaced by SDK types |
| `docs/websocket-protocol.md` | Replaced by this documentation |

## Benefits

1. **Full SDK fidelity** - No information lost in translation
2. **Easier SDK updates** - Just forward new message types
3. **Type safety** - Dart classes match SDK exactly
4. **Simpler debugging** - Same JSON at every layer
5. **Better UX** - Partial message streaming, all Query methods available
6. **Cleaner code** - Logic lives in one place (Dart), not split across two languages
