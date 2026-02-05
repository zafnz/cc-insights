# Protocol Comparison: Dart-Node-TS-Claude (Historical)

> **Note:** This is a historical document that compares the old Node.js backend architecture
> with the direct CLI approach. The Node.js backend has been removed entirely.
> The direct CLI approach (`ClaudeCliBackend`) is now the default and only backend.

This document compares the three protocol layers in the previous architecture and demonstrates why direct Dart ↔ Claude communication was feasible.

---

## Architecture Layers

```
┌─────────────┐
│  Dart SDK   │
└──────┬──────┘
       │ Layer 1: Custom JSON Lines (Dart ↔ Node.js)
       │ Protocol: backend-node/src/protocol.ts
       │
┌──────▼──────────┐
│  Node.js Backend│
└──────┬──────────┘
       │ Layer 2: TypeScript SDK API
       │ API: @anthropic-ai/claude-agent-sdk
       │
┌──────▼──────────┐
│ TypeScript SDK  │
└──────┬──────────┘
       │ Layer 3: claude-cli JSON Lines (TS ↔ Claude)
       │ Protocol: stdin/stdout stream-json
       │
┌──────▼──────────┐
│  claude-cli  │
└─────────────────┘
```

---

## Layer 1: Dart ↔ Node.js Protocol

**File:** `backend-node/src/protocol.ts`, `claude_dart_sdk/lib/src/protocol.dart`

### Dart → Node.js Messages

#### `session.create`
```json
{
  "type": "session.create",
  "id": "uuid",
  "payload": {
    "prompt": "Hello, Claude!",
    "cwd": "/path/to/project",
    "options": {
      "model": "sonnet",
      "permission_mode": "acceptEdits",
      "max_turns": 50
    }
  }
}
```

#### `session.send`
```json
{
  "type": "session.send",
  "id": "uuid",
  "session_id": "session-uuid",
  "payload": {
    "message": "Follow-up message"
  }
}
```

#### `callback.response`
```json
{
  "type": "callback.response",
  "id": "callback-uuid",
  "session_id": "session-uuid",
  "payload": {
    "behavior": "allow",
    "updated_input": { /* tool input */ }
  }
}
```

### Node.js → Dart Messages

#### `session.created`
```json
{
  "type": "session.created",
  "id": "uuid",
  "session_id": "session-uuid",
  "payload": {
    "sdk_session_id": "sdk-session-uuid"
  }
}
```

#### `sdk.message` (The Key Message!)
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    // ← THIS IS THE RAW CLAUDE BINARY MESSAGE!
    "type": "assistant",
    "uuid": "message-uuid",
    "session_id": "sdk-session-uuid",
    "message": {
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "Hello! I'm Claude."
        }
      ]
    }
  }
}
```

**Critical observation:** The `payload` field contains the **exact** message from the claude-cli, unchanged!

#### `callback.request`
```json
{
  "type": "callback.request",
  "id": "callback-uuid",
  "session_id": "session-uuid",
  "payload": {
    "callback_type": "can_use_tool",
    "tool_name": "Bash",
    "tool_input": { "command": "ls" }
  }
}
```

---

## Layer 3: TypeScript SDK ↔ claude-cli

**Source:** `examples/typescript-claude.jsonl` (protocol capture)

### TS SDK → claude-cli Messages

#### Initialization
```json
{
  "request_id": "uuid",
  "type": "control_request",
  "request": {
    "subtype": "initialize",
    "systemPrompt": "Custom system prompt...",
    "mcpServers": { /* ... */ },
    "agents": { /* ... */ }
  }
}
```

#### User Message
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Hello, Claude!"
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

### claude-cli → TS SDK Messages

#### System Initialization
```json
{
  "type": "system",
  "subtype": "init",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "cwd": "/path/to/project",
  "tools": ["Task", "Bash", "Read", "Write"],
  "model": "claude-sonnet-4-5-20250929",
  "permissionMode": "acceptEdits"
}
```

#### Assistant Response
```json
{
  "type": "assistant",
  "uuid": "message-uuid",
  "session_id": "session-uuid",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "text",
        "text": "Hello! I'm Claude."
      }
    ]
  },
  "parent_tool_use_id": null
}
```

---

## Direct Comparison: Layer 1 vs Layer 3

### User Message Flow

**Layer 1 (Dart → Node.js):**
```json
{
  "type": "session.send",
  "id": "correlation-uuid",
  "session_id": "session-uuid",
  "payload": {
    "message": "Read the README"
  }
}
```

**What Node.js does:**
```typescript
// session-manager.ts:394
const userMessage: SDKUserMessage = {
  type: "user",
  message: {
    role: "user",
    content: msg.payload.message,  // ← Extract message
  },
  parent_tool_use_id: null,
  session_id: msg.session_id,
};
session.messageQueue.push(userMessage);  // ← Push to SDK
```

**Layer 3 (TS SDK → Claude):**
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Read the README"
  },
  "parent_tool_use_id": null,
  "session_id": "session-uuid"
}
```

**Transformation:** Just unwrapping! `payload.message` → `message.content`

---

### Response Message Flow

**Layer 3 (Claude → TS SDK):**
```json
{
  "type": "assistant",
  "uuid": "msg-uuid",
  "session_id": "session-uuid",
  "message": {
    "role": "assistant",
    "content": [
      { "type": "text", "text": "I'll read the file." },
      { "type": "tool_use", "id": "tool-id", "name": "Read", "input": {...} }
    ]
  }
}
```

**What Node.js does:**
```typescript
// session-manager.ts:339
this.send({
  type: "sdk.message",
  session_id: session.id,
  payload: message,  // ← Forward verbatim!
});
```

**Layer 1 (Node.js → Dart):**
```json
{
  "type": "sdk.message",
  "session_id": "session-uuid",
  "payload": {
    // ← EXACT SAME MESSAGE from claude-cli
    "type": "assistant",
    "uuid": "msg-uuid",
    "session_id": "session-uuid",
    "message": {
      "role": "assistant",
      "content": [...]
    }
  }
}
```

**Transformation:** Just wrapping! Entire message → `payload`

---

## What Node.js Actually Does

From `backend-node/src/session-manager.ts` analysis:

### Session Creation (~100 lines)

```typescript
// 1. Create session state
const sessionId = uuidv4();
const abortController = new AbortController();
const callbacks = new CallbackBridge(sessionId, this.send);
const messageQueue = new MessageQueue();

// 2. Build SDK options (simple mapping)
const options: Options = {
  cwd: msg.payload.cwd,
  model: opts?.model,
  permissionMode: opts?.permission_mode,
  // ... just passing through
  canUseTool: (tool, input, ctx) => callbacks.requestPermission(...),
};

// 3. Start SDK query
const q = query({
  prompt: messageQueue.generate(),
  options,
});

// 4. Store session
this.sessions.set(sessionId, { id, query: q, ... });

// 5. Notify Dart
this.send({ type: "session.created", ... });

// 6. Forward messages
for await (const message of session.query) {
  this.send({
    type: "sdk.message",
    payload: message,  // ← Verbatim forwarding!
  });
}
```

**Key insight:** It's just session bookkeeping and message forwarding!

---

### Message Sending (~30 lines)

```typescript
// 1. Look up session
const session = this.sessions.get(msg.session_id);

// 2. Build SDK message
const userMessage: SDKUserMessage = {
  type: "user",
  message: {
    role: "user",
    content: msg.payload.message,  // ← Extract content
  },
  parent_tool_use_id: null,
  session_id: msg.session_id,
};

// 3. Push to queue (which feeds the SDK)
session.messageQueue.push(userMessage);
```

**Key insight:** Just unwrapping and forwarding!

---

### Callback Bridge (~250 lines)

```typescript
// When SDK calls canUseTool:
async requestPermission(toolName, toolInput, context) {
  const id = uuidv4();

  return new Promise((resolve, reject) => {
    // 1. Store pending promise
    this.pending.set(id, { resolve, reject, timeout });

    // 2. Ask Dart for approval
    this.send({
      type: "callback.request",
      id,
      payload: {
        callback_type: "can_use_tool",
        tool_name: toolName,
        tool_input: toolInput,
      },
    });

    // 3. Wait for Dart to respond via callback.response
    // ... (resolved in separate method)
  });
}

// When Dart responds:
resolve(id, response) {
  const pending = this.pending.get(id);
  pending.resolve({
    behavior: response.behavior,
    updatedInput: response.updated_input,
  });
}
```

**Key insight:** Just promise-based request/response bridging!

---

## What Would Change with Direct Connection

### Current Flow (3 hops)

```
Dart → Node.js → TS SDK → claude-cli
     ↓          ↓         ↓
   Wrap in   Unwrap   Send to
   envelope  & call   binary
              SDK

claude-cli → TS SDK → Node.js → Dart
              ↓        ↓         ↓
           Return  Wrap in   Forward
           message envelope  payload
```

### Direct Flow (1 hop)

```
Dart → claude-cli
     ↓
   Send to binary
   (almost same format!)

claude-cli → Dart
              ↓
           Forward message
           (already correct format!)
```

---

## Message Format Similarity

### Sending User Message

**Current (Dart → Node.js):**
```json
{
  "type": "session.send",
  "payload": { "message": "Hello" }
}
```

**Direct (Dart → Claude):**
```json
{
  "type": "user",
  "message": { "role": "user", "content": "Hello" },
  "parent_tool_use_id": null,
  "session_id": "uuid"
}
```

**Change needed:** Add `message.role`, `parent_tool_use_id`, move `payload.message` → `message.content`

---

### Receiving Assistant Message

**Current (Node.js → Dart):**
```json
{
  "type": "sdk.message",
  "payload": {
    "type": "assistant",
    "message": { "content": [...] }
  }
}
```

**Direct (Claude → Dart):**
```json
{
  "type": "assistant",
  "message": { "content": [...] }
}
```

**Change needed:** Just remove the `sdk.message` wrapper! The payload IS the message.

---

## Dart SDK Changes Required

### 1. Remove Wrapper Layer (Easy)

**Current parsing:**
```dart
// protocol.dart:202
class SdkMessageMessage extends IncomingMessage {
  final SDKMessage payload;  // ← Nested structure

  factory SdkMessageMessage.fromJson(Map<String, dynamic> json) {
    return SdkMessageMessage(
      sessionId: json['session_id'],
      payload: SDKMessage.fromJson(json['payload']),  // ← Parse nested
    );
  }
}
```

**Direct parsing:**
```dart
// Just parse directly!
final message = SDKMessage.fromJson(jsonLine);
// No wrapper needed
```

**Impact:** **Simpler code!** Remove one layer of nesting.

---

### 2. Add Initialization (New)

**New message type:**
```dart
class ControlRequest {
  final String requestId;
  final String subtype;
  final String systemPrompt;
  final Map<String, dynamic>? mcpServers;
  final Map<String, dynamic>? agents;
  final Map<String, dynamic>? hooks;
}

class ControlResponse {
  final String subtype;
  final String requestId;
  final Map<String, dynamic> response;
}
```

**Usage:**
```dart
// Send initialization
final request = ControlRequest(
  requestId: uuid(),
  subtype: 'initialize',
  systemPrompt: options.systemPrompt ?? '',
);
process.stdin.writeln(jsonEncode(request.toJson()));

// Wait for response
final response = await waitForControlResponse(request.requestId);
```

**Impact:** ~50 lines of new code

---

### 3. Handle Permissions Directly (Port from Node.js)

**Current (via Node.js bridge):**
```
Claude calls canUseTool
  ↓
Node.js sends callback.request to Dart
  ↓
Dart shows UI dialog
  ↓
Dart sends callback.response to Node.js
  ↓
Node.js resolves SDK promise
```

**Direct (in Dart):**
```
Claude sends permission request (TBD format)
  ↓
Dart shows UI dialog
  ↓
Dart sends permission response to Claude
```

**Impact:** ~250 lines (port `CallbackBridge` from TypeScript)

---

## Code Deletion with Direct Connection

### Can Delete Entirely

- `backend-node/src/session-manager.ts` (596 lines)
- `backend-node/src/callback-bridge.ts` (254 lines)
- `backend-node/src/protocol.ts` (195 lines)
- `backend-node/src/message-queue.ts` (not shown, ~100 lines?)
- `backend-node/src/logger.ts` (not shown, ~50 lines?)
- `backend-node/package.json`, `tsconfig.json`, etc.

**Total deletion:** ~1,200+ lines of TypeScript + Node.js dependency

---

### Must Add to Dart

- claude-cli spawning (~100 lines)
- Control message handling (~100 lines)
- Permission callback handling (~300 lines)
- Query method implementations (~100 lines)

**Total addition:** ~600 lines of Dart

**Net reduction:** ~600 lines + removes Node.js dependency!

---

## Key Insights

### 1. The Protocols Are Nearly Identical

The main differences are:
- Session management envelope (`session.create` vs direct messages)
- SDK message wrapping (`sdk.message` wrapper vs direct)
- Initialization (`control_request` vs implicit in SDK options)

**The actual message payloads are identical!**

---

### 2. Node.js Is Mostly Bookkeeping

The Node.js backend doesn't add business logic, it just:
- Manages session state (map of session IDs)
- Wraps/unwraps messages
- Bridges async callbacks with promises

**All of this is straightforward to do in Dart!**

---

### 3. Dart SDK Already Parses Claude Messages

The `SDKMessage.fromJson()` in Dart already handles:
- `system` messages
- `assistant` messages
- `user` messages
- `result` messages
- `stream_event` messages

**These are the exact messages from the claude-cli!**

---

### 4. The TypeScript SDK Doesn't Do Much

From examining the code:
- It spawns the claude-cli subprocess
- It sends messages to stdin
- It reads messages from stdout
- It provides callback mechanisms

**All of this is already in our Dart codebase for the Node.js backend!**

---

## Conclusion

**The migration is feasible because:**

1. ✅ **Same transport:** Both use JSON Lines over stdin/stdout
2. ✅ **Same message types:** `system`, `assistant`, `user`, `result`
3. ✅ **Same message structure:** Dart SDK already parses them
4. ✅ **Thin wrapper:** Node.js just wraps/unwraps, no transformations
5. ✅ **Existing infrastructure:** Dart already spawns processes and handles streams
6. ✅ **Net code reduction:** ~600 fewer lines + removes dependency

**The only unknowns:**

1. ❓ Permission callback protocol (examine captures)
2. ❓ Hook callback protocol (examine captures)
3. ❓ Other control message types (examine captures)

**Estimated effort:** 1 week for full migration

---

## Next Steps

See `direct-claude-binary-protocol.md` for implementation details.
