# Direct claude-cli Protocol (Historical)

> **Note:** This is a historical document that described the migration plan from the Node.js backend
> to direct CLI communication. The migration is complete. The Node.js backend has been removed.
> See `ClaudeCliBackend` in `claude_dart_sdk/lib/src/cli_backend.dart` for the current implementation.

This document describes the protocol between the TypeScript SDK and the claude-cli, and the rationale for bypassing the Node.js backend to talk directly to the claude-cli from Dart.

---

## Current Architecture

```
Dart SDK → Node.js Backend → TypeScript SDK → claude-cli
```

**Layers:**
1. **Dart ↔ Node.js**: Custom JSON Lines protocol (`backend-node/src/protocol.ts`)
2. **Node.js ↔ TypeScript SDK**: TypeScript SDK's `query()` API
3. **TypeScript SDK ↔ claude-cli**: JSON Lines over stdin/stdout

**Total complexity:** ~1,045 lines of TypeScript bridging code

---

## Proposed Direct Architecture

```
Dart SDK → claude-cli
```

**Why this works:**
- The TypeScript SDK is a thin wrapper (~1,000 lines)
- It mostly just spawns the CLI and forwards messages
- The protocols are nearly identical (both JSON Lines)
- The claude-cli handles everything (MCPs, tools, permissions, etc.)

---

## claude-cli Protocol

### Transport

- **Format:** Newline-delimited JSON (JSON Lines / NDJSON)
- **Direction:** Bidirectional over stdin/stdout
- **Encoding:** UTF-8
- **Logging:** Debug output goes to stderr

### CLI Arguments

From protocol captures (`examples/typescript-claude.jsonl`):

```bash
claude \
  --output-format stream-json \
  --input-format stream-json \
  --model sonnet \
  --permission-mode acceptEdits \
  --permission-prompt-tool stdio \
  --setting-sources '' \
  --verbose
```

**Key arguments:**
- `--output-format stream-json` - Use JSON Lines output (not human-readable)
- `--input-format stream-json` - Expect JSON Lines input
- `--model <model>` - Claude model to use (sonnet, opus, haiku)
- `--permission-mode <mode>` - Permission mode (default, acceptEdits, bypassPermissions, plan)
- `--permission-prompt-tool stdio` - Use stdin/stdout for permission prompts (not interactive TTY)
- `--setting-sources <sources>` - Comma-separated setting sources (user, project, local, or empty)
- `--verbose` - Enable verbose logging to stderr

**Other available arguments** (from SDK Options):
- `--max-turns <n>` - Maximum conversation turns
- `--max-budget-usd <n>` - Maximum budget in USD
- `--max-thinking-tokens <n>` - Maximum thinking tokens
- `--cwd <path>` - Working directory
- `--resume <session-id>` - Resume previous session
- `--additional-directories <dirs>` - Additional directories to access (comma-separated)

---

## Message Types

### Message Envelope

All messages (both stdin and stdout) are single-line JSON objects.

**Common fields:**
- `type` - Message type identifier
- `session_id` - Session identifier (when applicable)
- `uuid` - Unique message identifier (stdout messages)

---

## Stdin Messages (Dart → claude-cli)

### 1. `control_request` - Initialization

Sent once at startup to initialize the session.

```json
{
  "request_id": "unique-uuid",
  "type": "control_request",
  "request": {
    "subtype": "initialize",
    "systemPrompt": "Your custom system prompt...",
    "mcpServers": { /* MCP server configs */ },
    "agents": { /* Agent definitions */ },
    "hooks": { /* Hook configurations */ }
  }
}
```

**Response:** `control_response` with session metadata

**Fields:**
- `request_id` - Correlation ID for matching response
- `request.subtype` - Always `"initialize"` for startup
- `request.systemPrompt` - Custom system prompt (optional, empty string for default)
- `request.mcpServers` - MCP server configurations (optional)
- `request.agents` - Programmatic agent definitions (optional)
- `request.hooks` - Hook configurations (optional)

---

### 2. `user` - User Message

Send user input to Claude.

```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Your message here"
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

**Response:** Stream of `assistant`, `user` (with tool results), and eventually `result` messages

**Fields:**
- `message.role` - Always `"user"`
- `message.content` - String message or array of content blocks
- `parent_tool_use_id` - Parent tool use ID for subagent messages (null for main agent)
- `session_id` - Session identifier

**Tool results format:**
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_xxx",
        "content": "Result text...",
        "is_error": false
      }
    ]
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

---

### 3. Permission Response (Implicit)

When claude-cli outputs a message requiring permission (detected by SDK), the response is sent back as a structured message.

**Note:** The exact format for permission responses needs to be determined from captures. The TypeScript SDK handles this via `canUseTool` callback, which gets invoked somehow by the CLI's output.

---

## Stdout Messages (claude-cli → Dart)

### 1. `control_response` - Initialization Response

Response to `control_request`.

```json
{
  "type": "control_response",
  "response": {
    "subtype": "success",
    "request_id": "matching-uuid",
    "response": {
      "commands": [
        {
          "name": "compact",
          "description": "Clear conversation history...",
          "argumentHint": "..."
        }
      ],
      "output_style": "default",
      "available_output_styles": ["default", "Explanatory", "Learning"],
      "models": [
        {
          "value": "default",
          "displayName": "Claude Sonnet 4.5",
          "description": "..."
        }
      ]
    }
  }
}
```

**Fields:**
- `response.subtype` - `"success"` or error type
- `response.request_id` - Correlation ID from request
- `response.response` - Initialization metadata (commands, models, etc.)

---

### 2. `system` - System Message

Session initialization or status update.

```json
{
  "type": "system",
  "subtype": "init",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "cwd": "/path/to/working/directory",
  "tools": ["Task", "Bash", "Read", "Write", "..."],
  "mcp_servers": [],
  "model": "claude-sonnet-4-5-20250929",
  "permissionMode": "acceptEdits",
  "slash_commands": ["compact", "context", "cost", "..."],
  "apiKeySource": "none",
  "claude_code_version": "2.1.17",
  "output_style": "default",
  "agents": ["Bash", "general-purpose", "Explore", "Plan"],
  "skills": [],
  "plugins": []
}
```

**Subtypes:**
- `init` - Session initialization
- `compact_boundary` - Context was compacted
- `status` - Status update

**Key fields:**
- `tools` - Available tools
- `mcp_servers` - Connected MCP servers
- `permissionMode` - Current permission mode
- `agents` - Available subagent types
- `slash_commands` - Available slash commands

---

### 3. `assistant` - Assistant Response

Assistant's response with text and/or tool calls.

```json
{
  "type": "assistant",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": {
    "id": "msg_xxx",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-5-20250929",
    "content": [
      {
        "type": "text",
        "text": "I'll read the file for you."
      },
      {
        "type": "tool_use",
        "id": "toolu_xxx",
        "name": "Read",
        "input": {
          "file_path": "/path/to/file"
        }
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 123,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 456,
      "output_tokens": 78
    }
  },
  "parent_tool_use_id": null
}
```

**Content block types:**
- `text` - Text response
- `tool_use` - Tool call request

**Fields:**
- `message` - Full Anthropic API message structure
- `parent_tool_use_id` - Parent tool use ID for subagent messages (null for main agent)

---

### 4. `user` - Tool Results

Tool execution results sent back as user messages.

```json
{
  "type": "user",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "tool_result",
        "tool_use_id": "toolu_xxx",
        "content": "File contents here...",
        "is_error": false
      }
    ]
  },
  "parent_tool_use_id": null,
  "tool_use_result": {
    "tool_name": "Read",
    "tool_use_id": "toolu_xxx",
    "result": { /* structured result */ },
    "is_error": false
  }
}
```

**Fields:**
- `message.content` - Array of tool results
- `tool_use_result` - Structured result metadata (optional)

---

### 5. `result` - Final Result

Conversation turn completed.

```json
{
  "type": "result",
  "subtype": "success",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "duration_ms": 1234,
  "duration_api_ms": 1000,
  "is_error": false,
  "num_turns": 3,
  "result": "Task completed successfully",
  "total_cost_usd": 0.0012,
  "usage": {
    "input_tokens": 500,
    "output_tokens": 200,
    "cache_creation_input_tokens": 100,
    "cache_read_input_tokens": 1000
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 500,
      "outputTokens": 200,
      "cacheReadInputTokens": 1000,
      "cacheCreationInputTokens": 100,
      "webSearchRequests": 0,
      "costUSD": 0.0012,
      "contextWindow": 200000
    }
  },
  "permission_denials": []
}
```

**Subtypes:**
- `success` - Turn completed successfully
- `error_max_turns` - Hit max turns limit
- `error_during_execution` - Error during execution
- `error_max_budget_usd` - Hit budget limit

**Key fields:**
- `result` - Final result text (success only)
- `errors` - Array of error messages (error subtypes only)
- `usage` - Aggregate token usage
- `modelUsage` - Per-model usage breakdown
- `total_cost_usd` - Total cost in USD
- `permission_denials` - Array of denied permissions

---

### 6. `stream_event` - Partial Message (Optional)

Real-time streaming updates (only if `includePartialMessages` enabled).

```json
{
  "type": "stream_event",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "parent_tool_use_id": null,
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": {
      "type": "text_delta",
      "text": "partial text..."
    }
  }
}
```

**Event types:** Same as Anthropic streaming API
- `message_start`
- `content_block_start`
- `content_block_delta`
- `content_block_stop`
- `message_delta`
- `message_stop`

---

## Permission Callbacks

**Question:** How does the claude-cli communicate permission requests?

From the TypeScript SDK code, there's a `canUseTool` callback that gets invoked. This needs to be determined from the protocol captures.

**Hypothesis 1:** Special message type (e.g., `permission_request`)
**Hypothesis 2:** Tool execution happens synchronously, and the CLI pauses waiting for approval via stdin
**Hypothesis 3:** The `--permission-prompt-tool stdio` flag changes behavior to use a specific message protocol

**TODO:** Examine captures for permission request flow.

---

## Comparison: Current vs Direct Protocol

### Current Protocol (Dart ↔ Node.js ↔ TS SDK ↔ Claude)

**Dart → Node.js (Stdin):**
```json
{
  "type": "session.create",
  "id": "correlation-uuid",
  "payload": {
    "prompt": "Hello",
    "cwd": "/path",
    "options": { "model": "sonnet" }
  }
}
```

**Node.js → Dart (Stdout):**
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    "type": "assistant",
    "uuid": "message-uuid",
    "message": { /* ... */ }
  }
}
```

**The `payload` is the raw SDK message** - exactly what comes from the claude-cli!

---

### Direct Protocol (Dart ↔ Claude)

**Dart → Claude (Stdin):**
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Hello"
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

**Claude → Dart (Stdout):**
```json
{
  "type": "assistant",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": { /* ... */ }
}
```

**This is identical to the `payload` field in the current protocol!**

---

## What the Node.js Backend Actually Does

From `backend-node/src/session-manager.ts` (~596 lines):

1. **Spawn claude-cli** (via TypeScript SDK's `query()`)
2. **Send initialization** (via SDK options)
3. **Forward user messages** (via `messageQueue.push()`)
4. **Parse responses** (via `for await (const message of session.query)`)
5. **Bridge callbacks** (via `CallbackBridge` ~254 lines)
   - Receive `canUseTool` callback from SDK
   - Send `callback.request` to Dart
   - Wait for `callback.response` from Dart
   - Resolve promise back to SDK
6. **Handle query methods** (via `query.supportedModels()`, etc.)

**Total:** ~850 lines of actual logic (excluding protocol definitions)

**Most of this is just forwarding!** The SDK messages come out of the claude-cli and get wrapped in `sdk.message` envelopes.

---

## What We Need to Implement in Dart

### 1. claude-cli Spawning

```dart
class ClaudeCliBackend {
  Future<Process> spawnClaude(SessionOptions options) async {
    final args = [
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--model', options.model ?? 'sonnet',
      '--permission-mode', options.permissionMode ?? 'default',
      '--permission-prompt-tool', 'stdio',
      '--setting-sources', (options.settingSources ?? []).join(','),
      if (options.verbose) '--verbose',
      if (options.cwd != null) '--cwd', options.cwd!,
      if (options.maxTurns != null) '--max-turns', options.maxTurns.toString(),
      // ... other options
    ];

    final claudePath = options.pathToClaudeCodeExecutable ?? 'claude';
    return await Process.start(claudePath, args);
  }
}
```

### 2. Initialization Message

```dart
Future<void> initialize(Process process, SessionOptions options) async {
  final request = {
    'request_id': generateUuid(),
    'type': 'control_request',
    'request': {
      'subtype': 'initialize',
      'systemPrompt': options.systemPrompt ?? '',
      if (options.mcpServers != null) 'mcpServers': options.mcpServers,
      if (options.agents != null) 'agents': options.agents,
      if (options.hooks != null) 'hooks': options.hooks,
    },
  };

  process.stdin.writeln(jsonEncode(request));

  // Wait for control_response
  // ...
}
```

### 3. Message Parsing (Already Done!)

Your existing `SDKMessage.fromJson()` already handles:
- ✅ `system` messages → `SDKSystemMessage`
- ✅ `assistant` messages → `SDKAssistantMessage`
- ✅ `user` messages → `SDKUserMessage`
- ✅ `result` messages → `SDKResultMessage`
- ✅ `stream_event` messages → `SDKStreamEvent`

**Only need to add:**
- ❌ `control_response` → `SDKControlResponse` (new, simple)

### 4. Callback Bridging (Port from TypeScript)

Port `callback-bridge.ts` (~254 lines) to Dart:

```dart
class CallbackBridge {
  final _pendingCallbacks = <String, Completer>{};

  Future<PermissionResult> requestPermission(
    String toolName,
    Map<String, dynamic> toolInput,
    PermissionContext context,
  ) async {
    final id = generateUuid();
    final completer = Completer<PermissionResult>();
    _pendingCallbacks[id] = completer;

    // Show permission UI
    final approved = await showPermissionDialog(toolName, toolInput);

    if (approved) {
      return PermissionResult.allow(updatedInput: toolInput);
    } else {
      return PermissionResult.deny(message: 'User denied');
    }
  }

  void resolve(String id, PermissionResult result) {
    _pendingCallbacks[id]?.complete(result);
    _pendingCallbacks.remove(id);
  }
}
```

**Note:** The exact mechanism for how claude-cli requests permissions needs to be determined from captures.

### 5. User Message Sending (Already Done!)

Your existing protocol already sends the exact format Claude expects:

```dart
final userMessage = {
  'type': 'user',
  'message': {
    'role': 'user',
    'content': message,
  },
  'parent_tool_use_id': null,
  'session_id': sessionId,
};
process.stdin.writeln(jsonEncode(userMessage));
```

---

## Implementation Estimate

### Phase 1: Basic Direct Connection (1-2 days)

**Tasks:**
- Create `ClaudeCliBackend` class
- Implement claude-cli spawning with CLI args
- Send `control_request` initialization
- Parse `control_response`
- Forward user messages
- Parse responses with existing `SDKMessage.fromJson()`

**Complexity:** Low - mostly adapting existing code

**Lines of code:** ~200 lines

---

### Phase 2: Permission Callbacks (2-3 days)

**Tasks:**
- Determine permission request protocol from captures
- Port `CallbackBridge` logic to Dart
- Handle permission requests from claude-cli
- Route to existing UI permission dialogs
- Send permission responses back to CLI

**Complexity:** Medium - depends on permission protocol

**Lines of code:** ~300 lines

---

### Phase 3: Advanced Features (1-2 days)

**Tasks:**
- Implement query methods (setModel, setPermissionMode, etc.)
- Session resumption support
- Error recovery and timeout handling
- Comprehensive logging

**Complexity:** Low - straightforward implementations

**Lines of code:** ~200 lines

---

### Total Effort

- **Time:** ~1 week
- **Code:** ~700 lines of Dart (vs ~1,045 lines of TypeScript we can delete)
- **Risk:** Low - protocols are well-documented via captures

---

## Benefits of Direct Connection

1. **Simpler deployment** - No Node.js dependency
2. **Lower memory footprint** - One less process (~50-100MB saved)
3. **Direct control** - No abstraction layer in the way
4. **Lower latency** - No serialization/deserialization hop
5. **Easier debugging** - Fewer layers to trace through
6. **Better error handling** - Direct access to claude-cli stderr
7. **Cleaner architecture** - Dart ↔ Claude is the natural boundary

---

## Risks and Unknowns

### 1. Permission Protocol Details

**Status:** Unknown from captures so far

**Questions:**
- How does the claude-cli request permission?
- Is it a special message type?
- Does it pause execution waiting for stdin response?
- What format does the response take?

**Mitigation:** Examine `examples/typescript-claude.jsonl` for permission flow

---

### 2. Hook System

**Status:** Partially understood from SDK docs

**Questions:**
- How are hooks communicated to the CLI?
- Are they configured via `control_request` initialization?
- How are hook callbacks triggered?

**Mitigation:** Check initialization protocol and SDK hook documentation

---

### 3. Control Messages

**Status:** Only saw `initialize` so far

**Questions:**
- What other control message types exist?
- How are query methods (setModel, etc.) implemented?
- Are they control messages or something else?

**Mitigation:** Search captures for other `control_request` types

---

### 4. claude-cli Availability

**Status:** Need to determine

**Questions:**
- Where is the claude-cli located?
- How is it distributed?
- Does it require installation or is it bundled?

**Mitigation:** Check TypeScript SDK for CLI path logic

---

## Next Steps

1. **Document permission protocol** - Examine captures for permission request/response flow
2. **Document hook protocol** - Understand how hooks are configured and triggered
3. **Document control messages** - List all control message types
4. **Create prototype** - Build minimal `ClaudeCliBackend` class
5. **Test against captures** - Validate protocol implementation against known-good data
6. **Migrate incrementally** - Add feature flag to switch between backends

---

## References

- Protocol captures: `examples/typescript-claude.jsonl`
- Current Dart protocol: `claude_dart_sdk/lib/src/protocol.dart`
- Current Node.js backend: `backend-node/src/session-manager.ts`
- SDK message types: `claude_dart_sdk/lib/src/types/sdk_messages.dart`
- TypeScript SDK docs: `docs/sdk/typescript.md`
