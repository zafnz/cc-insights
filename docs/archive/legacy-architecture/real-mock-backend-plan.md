# External Mock Backend Plan

## Overview

This document outlines the plan for creating an **external mock backend** that can replace `backend-node` entirely. Unlike the in-process mock infrastructure (documented in `mock-backend-plan.md`), this external mock runs as a standalone process that the Flutter app spawns, enabling:

1. **Full integration testing** - Test the complete communication stack including subprocess spawning, stdin/stdout protocol handling, and JSON line parsing
2. **Manual testing** - Interactive testing without consuming Claude API credits
3. **Scenario replay** - Record and replay production scenarios for debugging
4. **Demo mode** - Run the app in a deterministic demo mode for presentations

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Flutter App                                                             │
│  ┌──────────────────┐    ┌──────────────────┐                          │
│  │ BackendService   │───▶│ SessionProvider  │───▶ UI Widgets           │
│  └────────┬─────────┘    └──────────────────┘                          │
│           │                                                             │
└───────────┼─────────────────────────────────────────────────────────────┘
            │ spawns (configurable path)
            ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ Mock Backend Process (mock-backend/)                                    │
│  ┌──────────────────┐    ┌──────────────────┐                          │
│  │ Protocol Handler │◀──▶│ Scenario Engine  │                          │
│  │ (stdin/stdout)   │    │ (responses)      │                          │
│  └──────────────────┘    └──────────────────┘                          │
│                                │                                        │
│                                ▼                                        │
│                          ┌──────────────────┐                          │
│                          │ Scenario Files   │                          │
│                          │ (JSON/YAML)      │                          │
│                          └──────────────────┘                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Protocol Specification

The mock backend must implement the exact same stdin/stdout JSON lines protocol as `backend-node`.

### Communication Format

- Each message is a single JSON object on one line
- Messages are terminated with newline (`\n`)
- stdin: receives messages from Flutter/Dart SDK
- stdout: sends messages to Flutter/Dart SDK
- stderr: diagnostic logs (optional, but helpful for debugging)

### Incoming Messages (Flutter → Mock Backend)

#### session.create
```json
{
  "type": "session.create",
  "id": "request-uuid",
  "payload": {
    "prompt": "Initial user message",
    "cwd": "/path/to/working/directory",
    "options": {
      "model": "claude-sonnet-4-5-20250514",
      "permission_mode": "default",
      "max_turns": 50
    }
  }
}
```

#### session.send
```json
{
  "type": "session.send",
  "id": "request-uuid",
  "session_id": "session-uuid",
  "payload": {
    "message": "Follow-up user message"
  }
}
```

#### session.interrupt
```json
{
  "type": "session.interrupt",
  "id": "request-uuid",
  "session_id": "session-uuid",
  "payload": {}
}
```

#### session.kill
```json
{
  "type": "session.kill",
  "id": "request-uuid",
  "session_id": "session-uuid",
  "payload": {}
}
```

#### callback.response
```json
{
  "type": "callback.response",
  "id": "callback-request-id",
  "session_id": "session-uuid",
  "payload": {
    "behavior": "allow",
    "updated_input": { "command": "ls -la" }
  }
}
```

#### query.call
```json
{
  "type": "query.call",
  "id": "request-uuid",
  "session_id": "session-uuid",
  "payload": {
    "method": "supportedModels",
    "args": []
  }
}
```

### Outgoing Messages (Mock Backend → Flutter)

#### session.created
```json
{
  "type": "session.created",
  "id": "echoed-request-id",
  "session_id": "new-session-uuid",
  "payload": {
    "sdk_session_id": "optional-sdk-id"
  }
}
```

#### sdk.message (system - init)
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    "type": "system",
    "subtype": "init",
    "uuid": "message-uuid",
    "session_id": "session-uuid",
    "cwd": "/path/to/cwd",
    "model": "claude-sonnet-4-5-20250514",
    "permissionMode": "default",
    "tools": ["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    "mcp_servers": []
  }
}
```

#### sdk.message (assistant)
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    "type": "assistant",
    "uuid": "message-uuid",
    "session_id": "session-uuid",
    "message": {
      "role": "assistant",
      "content": [
        { "type": "text", "text": "I'll help you with that." },
        {
          "type": "tool_use",
          "id": "tool-use-id",
          "name": "Read",
          "input": { "file_path": "/tmp/test.txt" }
        }
      ],
      "usage": {
        "input_tokens": 100,
        "output_tokens": 50,
        "cache_creation_input_tokens": 0,
        "cache_read_input_tokens": 80
      }
    },
    "parent_tool_use_id": null
  }
}
```

#### sdk.message (user - tool result)
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    "type": "user",
    "uuid": "message-uuid",
    "session_id": "session-uuid",
    "message": {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "tool-use-id",
          "content": "File contents here..."
        }
      ]
    },
    "isSynthetic": true,
    "tool_use_result": {
      "content": "File contents here..."
    }
  }
}
```

#### sdk.message (result)
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    "type": "result",
    "subtype": "success",
    "uuid": "message-uuid",
    "session_id": "session-uuid",
    "duration_ms": 5000,
    "duration_api_ms": 4500,
    "is_error": false,
    "num_turns": 3,
    "total_cost_usd": 0.015,
    "usage": {
      "input_tokens": 500,
      "output_tokens": 200
    }
  }
}
```

#### callback.request (permission)
```json
{
  "type": "callback.request",
  "id": "callback-uuid",
  "session_id": "session-uuid",
  "payload": {
    "callback_type": "can_use_tool",
    "tool_name": "Bash",
    "tool_input": { "command": "rm -rf /tmp/test" },
    "suggestions": ["Bash(rm *)"],
    "tool_use_id": "tool-use-id",
    "agent_id": null,
    "blocked_path": null,
    "decision_reason": null
  }
}
```

#### query.result
```json
{
  "type": "query.result",
  "id": "echoed-request-id",
  "session_id": "session-uuid",
  "payload": {
    "success": true,
    "result": ["claude-sonnet-4-5-20250514", "claude-opus-4-5-20251101"]
  }
}
```

#### session.interrupted
```json
{
  "type": "session.interrupted",
  "id": "echoed-request-id",
  "session_id": "session-uuid",
  "payload": {}
}
```

#### session.killed
```json
{
  "type": "session.killed",
  "id": "echoed-request-id",
  "session_id": "session-uuid",
  "payload": {}
}
```

#### error
```json
{
  "type": "error",
  "id": "optional-request-id",
  "session_id": "optional-session-id",
  "payload": {
    "code": "SESSION_NOT_FOUND",
    "message": "Session abc123 not found",
    "details": null
  }
}
```

## Implementation Plan

### Phase 1: Core Mock Backend

Create a new `mock-backend/` directory at the project root with a minimal TypeScript implementation.

#### Directory Structure
```
mock-backend/
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts              # Entry point (stdin/stdout handler)
│   ├── protocol.ts           # Reuse types from backend-node
│   ├── session-manager.ts    # Mock session state management
│   ├── scenario-engine.ts    # Scenario execution engine
│   └── scenarios/
│       ├── simple-echo.ts    # Basic echo responses
│       ├── tool-usage.ts     # Tool call + permission scenarios
│       └── multi-turn.ts     # Multi-turn conversation scenarios
├── scenarios/                # JSON scenario files (external)
│   ├── demo.json
│   └── test-*.json
└── dist/                     # Compiled output
```

#### Key Files

**src/index.ts** - Entry point
```typescript
import * as readline from 'readline';
import { SessionManager } from './session-manager';

const manager = new SessionManager();

const rl = readline.createInterface({
  input: process.stdin,
  terminal: false,
});

rl.on('line', async (line) => {
  if (!line.trim()) return;

  try {
    const msg = JSON.parse(line);
    const response = await manager.handleMessage(msg);
    if (response) {
      console.log(JSON.stringify(response));
    }
  } catch (e) {
    console.log(JSON.stringify({
      type: 'error',
      payload: {
        code: 'INVALID_MESSAGE',
        message: `Failed to parse message: ${e}`,
      },
    }));
  }
});

rl.on('close', () => {
  process.exit(0);
});

process.on('SIGTERM', () => {
  process.exit(0);
});
```

**src/session-manager.ts** - Session state
```typescript
import { v4 as uuidv4 } from 'uuid';
import { ScenarioEngine } from './scenario-engine';

interface Session {
  id: string;
  cwd: string;
  options: Record<string, unknown>;
  scenario: ScenarioEngine;
  pendingCallbacks: Map<string, (response: unknown) => void>;
}

export class SessionManager {
  private sessions = new Map<string, Session>();

  async handleMessage(msg: IncomingMessage): Promise<OutgoingMessage | null> {
    switch (msg.type) {
      case 'session.create':
        return this.handleCreate(msg);
      case 'session.send':
        return this.handleSend(msg);
      case 'session.interrupt':
        return this.handleInterrupt(msg);
      case 'session.kill':
        return this.handleKill(msg);
      case 'callback.response':
        return this.handleCallback(msg);
      case 'query.call':
        return this.handleQuery(msg);
      default:
        return {
          type: 'error',
          payload: { code: 'UNKNOWN_MESSAGE', message: `Unknown type: ${msg.type}` },
        };
    }
  }

  private async handleCreate(msg: SessionCreateMessage): Promise<void> {
    const sessionId = uuidv4();
    const scenario = new ScenarioEngine(sessionId, msg.payload.options);

    this.sessions.set(sessionId, {
      id: sessionId,
      cwd: msg.payload.cwd,
      options: msg.payload.options || {},
      scenario,
      pendingCallbacks: new Map(),
    });

    // Send session.created
    console.log(JSON.stringify({
      type: 'session.created',
      id: msg.id,
      session_id: sessionId,
      payload: {},
    }));

    // Execute initial scenario (responds to prompt)
    await scenario.executeInitialPrompt(msg.payload.prompt, (message) => {
      console.log(JSON.stringify(message));
    });
  }

  // ... other handlers
}
```

### Phase 2: Scenario Engine

The scenario engine determines how the mock responds to messages. It supports:

1. **Built-in scenarios** - Hardcoded TypeScript scenarios for common patterns
2. **JSON scenario files** - External files for custom scenarios
3. **Echo mode** - Simple mode that echoes back user input

#### Scenario Types

**Simple Echo** - Returns user message as response
```typescript
class EchoScenario implements Scenario {
  async respond(prompt: string, emit: EmitFn): Promise<void> {
    emit(systemInit(this.sessionId, this.options));
    emit(assistantText(`You said: ${prompt}`));
    emit(result({ numTurns: 1 }));
  }
}
```

**Tool Usage** - Demonstrates tool calls with permissions
```typescript
class ToolUsageScenario implements Scenario {
  async respond(prompt: string, emit: EmitFn): Promise<void> {
    emit(systemInit(this.sessionId, this.options));

    // Send assistant with tool use
    const toolUseId = uuidv4();
    emit(assistantWithTool({
      text: "I'll read that file for you.",
      tool: {
        id: toolUseId,
        name: 'Read',
        input: { file_path: '/tmp/example.txt' },
      },
    }));

    // Request permission
    const callbackId = uuidv4();
    emit(permissionRequest({
      id: callbackId,
      toolName: 'Read',
      toolInput: { file_path: '/tmp/example.txt' },
      toolUseId,
    }));

    // Wait for callback response (handled by session manager)
    await this.waitForCallback(callbackId);

    // Send tool result
    emit(userToolResult({
      toolUseId,
      content: 'Mock file contents here...',
    }));

    // Final response
    emit(assistantText('Here are the file contents.'));
    emit(result({ numTurns: 2 }));
  }
}
```

**JSON Scenario Format**
```json
{
  "name": "demo-conversation",
  "description": "Demo scenario for presentations",
  "steps": [
    {
      "type": "system_init",
      "model": "claude-sonnet-4-5-20250514",
      "tools": ["Read", "Write", "Bash"]
    },
    {
      "type": "assistant",
      "content": [
        { "type": "text", "text": "I'll help you with that task." }
      ],
      "delay_ms": 500
    },
    {
      "type": "assistant",
      "content": [
        { "type": "text", "text": "Let me read the file first." },
        { "type": "tool_use", "name": "Read", "input": { "file_path": "{{prompt}}" } }
      ]
    },
    {
      "type": "permission_request",
      "tool_name": "Read",
      "wait_for_response": true
    },
    {
      "type": "user_tool_result",
      "content": "# README\n\nThis is a sample file."
    },
    {
      "type": "assistant",
      "content": [
        { "type": "text", "text": "The file contains a README header." }
      ]
    },
    {
      "type": "result",
      "num_turns": 2,
      "total_cost_usd": 0.01
    }
  ]
}
```

### Phase 3: Flutter Integration

Modify the Flutter app to support switching between real and mock backends.

#### Option A: Environment Variable (Recommended)

```dart
// In BackendService._findBackendPath()
String _findBackendPath() {
  // Check for mock backend override
  final mockPath = Platform.environment['CLAUDE_MOCK_BACKEND'];
  if (mockPath != null && File(mockPath).existsSync()) {
    debugPrint('[BackendService] Using mock backend: $mockPath');
    return mockPath;
  }

  // ... existing path resolution
}
```

Usage:
```bash
# Run with mock backend
CLAUDE_MOCK_BACKEND=/path/to/mock-backend/dist/index.js flutter run -d macos

# Or use a shell script
./run-with-mock.sh
```

#### Option B: Command-Line Argument

```dart
// In main.dart
void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('backend', abbr: 'b', help: 'Path to backend script');

  final results = parser.parse(args);
  final backendPath = results['backend'] as String?;

  runApp(MyApp(backendOverride: backendPath));
}
```

Usage:
```bash
flutter run -d macos --dart-entrypoint-args="--backend /path/to/mock-backend/dist/index.js"
```

#### Option C: Settings UI

Add a developer settings panel that allows switching backends at runtime:
- Store backend path preference in local storage
- Restart backend when changed
- Show indicator when using mock backend

### Phase 4: Scenario Selection

Allow selecting which scenario to run via:

1. **Environment variable**: `MOCK_SCENARIO=tool-usage`
2. **First message prefix**: `__scenario:demo__` prefix in prompt
3. **Scenario file path**: `MOCK_SCENARIO_FILE=/path/to/scenario.json`

```typescript
// In scenario-engine.ts
export class ScenarioEngine {
  private scenario: Scenario;

  constructor(sessionId: string, options: SessionOptions) {
    const scenarioName = process.env.MOCK_SCENARIO || 'echo';
    const scenarioFile = process.env.MOCK_SCENARIO_FILE;

    if (scenarioFile) {
      this.scenario = JsonScenario.load(scenarioFile);
    } else {
      this.scenario = this.loadBuiltinScenario(scenarioName);
    }
  }

  private loadBuiltinScenario(name: string): Scenario {
    switch (name) {
      case 'echo': return new EchoScenario();
      case 'tool-usage': return new ToolUsageScenario();
      case 'multi-turn': return new MultiTurnScenario();
      case 'subagent': return new SubagentScenario();
      case 'error': return new ErrorScenario();
      default: return new EchoScenario();
    }
  }
}
```

### Phase 5: Advanced Features

#### Recording Mode

Record real backend sessions and replay them:

```typescript
// Start mock in record mode - proxies to real backend and records
MOCK_MODE=record MOCK_RECORD_FILE=session.json node mock-backend/dist/index.js

// Replay recorded session
MOCK_MODE=replay MOCK_RECORD_FILE=session.json node mock-backend/dist/index.js
```

#### Delay Simulation

Add realistic timing to responses:

```typescript
interface ScenarioStep {
  delay_ms?: number;        // Fixed delay before this step
  typing_delay_ms?: number; // Per-character delay for text (streaming simulation)
}
```

#### Failure Injection

Test error handling:

```json
{
  "type": "error_injection",
  "trigger": "after_step_3",
  "error": {
    "code": "API_ERROR",
    "message": "Rate limit exceeded"
  }
}
```

## Implementation Checklist

### Phase 1: Core (MVP)
- [ ] Create `mock-backend/` directory structure
- [ ] Set up TypeScript/Node.js project with package.json
- [ ] Copy protocol types from `backend-node/src/protocol.ts`
- [ ] Implement stdin/stdout JSON line handling
- [ ] Implement session state management
- [ ] Implement basic echo scenario
- [ ] Test with Flutter app using environment variable

### Phase 2: Scenarios
- [ ] Implement scenario engine interface
- [ ] Create built-in scenarios:
  - [ ] Simple echo
  - [ ] Tool usage with permission
  - [ ] Multi-turn conversation
  - [ ] Subagent (Task tool)
  - [ ] Compaction event
  - [ ] Error conditions
- [ ] Implement JSON scenario loader
- [ ] Add scenario selection via environment variable

### Phase 3: Flutter Integration
- [ ] Add environment variable support to BackendService
- [ ] Add command-line argument support
- [ ] Add visual indicator for mock mode
- [ ] Document usage in CLAUDE.md

### Phase 4: Polish
- [ ] Add delay simulation
- [ ] Add recording mode
- [ ] Add failure injection
- [ ] Create demo scenarios for common use cases
- [ ] Write integration tests using mock backend

## Files to Create

| File | Description |
|------|-------------|
| `mock-backend/package.json` | Node.js project configuration |
| `mock-backend/tsconfig.json` | TypeScript configuration |
| `mock-backend/src/index.ts` | Entry point |
| `mock-backend/src/protocol.ts` | Protocol types (copy from backend-node) |
| `mock-backend/src/session-manager.ts` | Session state management |
| `mock-backend/src/scenario-engine.ts` | Scenario execution |
| `mock-backend/src/scenarios/*.ts` | Built-in scenarios |
| `mock-backend/scenarios/*.json` | JSON scenario files |

## Files to Modify

| File | Change |
|------|--------|
| `flutter_app/lib/services/backend_service.dart` | Add mock backend path override |
| `CLAUDE.md` | Document mock backend usage |

## Usage Examples

### Running with Mock Backend

```bash
# Build mock backend
cd mock-backend && npm install && npm run build

# Run Flutter app with mock
cd flutter_app
CLAUDE_MOCK_BACKEND=../mock-backend/dist/index.js flutter run -d macos

# With specific scenario
CLAUDE_MOCK_BACKEND=../mock-backend/dist/index.js \
MOCK_SCENARIO=tool-usage \
flutter run -d macos

# With custom scenario file
CLAUDE_MOCK_BACKEND=../mock-backend/dist/index.js \
MOCK_SCENARIO_FILE=../mock-backend/scenarios/demo.json \
flutter run -d macos
```

### Testing Specific Behaviors

```bash
# Test permission UI
MOCK_SCENARIO=permission-flow flutter run -d macos

# Test error handling
MOCK_SCENARIO=api-errors flutter run -d macos

# Test compaction
MOCK_SCENARIO=compaction flutter run -d macos

# Test subagents
MOCK_SCENARIO=subagent-task flutter run -d macos
```

## Comparison with In-Process Mock

| Aspect | External Mock Backend | In-Process Mock (`mock_session.dart`) |
|--------|----------------------|--------------------------------------|
| **Testing Level** | Full integration (subprocess + protocol) | Unit/widget tests only |
| **Setup Complexity** | Requires building separate project | Just import mock classes |
| **Runtime Overhead** | Subprocess startup time | None |
| **Protocol Testing** | Tests real JSON line parsing | Skips protocol layer |
| **Use Cases** | Integration tests, manual testing, demos | Unit tests, widget tests |
| **Debugging** | Can inspect stdin/stdout directly | Programmatic control |

**Recommendation**: Use both. The in-process mock for fast unit/widget tests, and the external mock for integration tests and manual testing.

## Security Considerations

- Mock backend should never be deployed to production
- Scenario files should not contain real API keys or sensitive data
- Consider adding a "MOCK MODE" watermark to the UI when using mock backend
