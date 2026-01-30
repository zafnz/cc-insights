# Streaming Input Mode Refactor

## Overview

The backend has been refactored to use **streaming input mode** instead of single-shot queries. This is the recommended pattern for the Claude Agent SDK and fixes the "process exited with code 1" error that occurred on follow-up messages.

## What Changed

### Before (Single-Shot Mode) ❌
```typescript
// First message - spawn process
const q = query({ prompt: "message 1", options });
for await (const msg of q) { /* ... */ }  // Process exits

// Second message - spawn NEW process (crashed on Node v25)
const q2 = query({
  prompt: "message 2",
  options: { resume: sessionId }
});
```

**Problems:**
- New Claude process spawned for each message
- Process killed and restarted between messages
- Crashed when using bundled CLI on Node v25
- Inefficient resource usage
- Not the recommended SDK pattern

### After (Streaming Input Mode) ✅
```typescript
// Create message queue
const queue = new MessageQueue();

// Spawn ONE process with async generator
const q = query({ prompt: queue.generate(), options });

// Push messages to queue - same process receives them
queue.push({ type: "user", message: "message 1" });
queue.push({ type: "user", message: "message 2" });
```

**Benefits:**
- Single long-lived Claude process per session
- Messages fed through async generator
- No process restarts between messages
- Recommended SDK pattern
- Better performance

## Implementation Details

### MessageQueue Class (`message-queue.ts`)
A queue that bridges external message pushing with async generators:

```typescript
class MessageQueue {
  push(message: SDKUserMessage): void { /* ... */ }
  async *generate(): AsyncGenerator<SDKUserMessage> { /* ... */ }
  close(): void { /* ... */ }
}
```

**How it works:**
1. `generate()` creates an async generator that yields messages
2. `push()` adds messages to the queue
3. If generator is waiting, it receives the message immediately
4. If no consumer is waiting, message is queued
5. `close()` terminates the generator

### Session Structure
Each session now includes:
```typescript
interface Session {
  id: string;
  query: Query;              // The running query
  messageQueue: MessageQueue; // NEW: Queue for feeding messages
  abortController: AbortController;
  callbacks: CallbackBridge;
  sdkSessionId?: string;
  cwd: string;
}
```

### createSession()
1. Creates a `MessageQueue`
2. Pushes initial prompt to queue
3. Starts query with `query({ prompt: queue.generate() })`
4. Claude process stays alive, waiting for messages from generator

### sendMessage()
1. Finds the existing session
2. Pushes new message to `messageQueue`
3. Generator yields it to the **same** running Claude process
4. No new process spawned

### killSession()
1. Aborts the controller
2. **Closes the message queue** (terminates generator)
3. Cleans up session

## Testing

To test the streaming mode:

1. **Hot reload Flutter app** to pick up the rebuilt backend
2. **Create a session** with an initial message
3. **Send a follow-up message**
4. **Verify in logs**:
   - Initial: `Starting SDK query with streaming input mode`
   - Follow-up: `Pushing message to session queue`
   - Should see `Message pushed to queue successfully`
   - **No** `Claude Code process exited with code 1` error

### Expected Logs

**First message:**
```
[INFO] Creating session
[INFO] Starting SDK query with streaming input mode
[INFO] Session created successfully
[INFO] Processing SDK messages
```

**Second message (same session):**
```
[INFO] Pushing message to session queue
[INFO] Message pushed to queue successfully
```

**Key difference:** No new "Processing SDK messages" or "Starting SDK query" on follow-up messages - the **same query** is still running!

## Benefits of Streaming Mode

1. ✅ **Single process per session** - better resource usage
2. ✅ **No restart overhead** - instant message delivery
3. ✅ **Proper SDK usage** - follows recommended patterns
4. ✅ **Fixes Node v25 issues** - no more process spawn/kill cycles
5. ✅ **Enables advanced features** - interrupt, image uploads, hooks work properly

## Migration Notes

The public API (protocol messages) remains unchanged:
- `session.create` still creates sessions
- `session.send` still sends messages
- `session.kill` still kills sessions

The change is purely internal to how the backend manages the Claude process.

## References

- SDK Docs: `docs/sdk/streaming-vs-single-mode.md`
- SDK Docs: `docs/sdk/sessions.md`
- TypeScript SDK Reference: `docs/sdk/typescript.md`
