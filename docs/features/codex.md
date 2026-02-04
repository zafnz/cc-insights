# Codex Integration Research

Research into integrating OpenAI Codex CLI as a backend for CC-Insights,
alongside the existing Claude backend.

**Status:** Research complete. Feasibility confirmed. Ready for implementation
planning.

**Codex CLI version tested:** 0.93.0 (installed at `/opt/homebrew/bin/codex`)

---

## Executive Summary

Codex can serve as a CC-Insights backend. There are **two viable integration
paths**, each with trade-offs:

| Approach | Protocol | Permissions | Complexity | Recommended |
|----------|----------|-------------|------------|-------------|
| `codex exec --json` | One-shot JSONL | No interactive UI | Low | For MVP |
| `codex app-server` | Bidirectional JSON-RPC | Full approval flow | Medium | For full integration |

**Recommendation: Use `codex app-server`.** It provides a bidirectional
JSON-RPC protocol over stdin/stdout, very similar to how we drive Claude's CLI
directly. It supports interactive permission approvals, streaming events, and
multi-turn conversations through a long-lived process -- exactly what
CC-Insights needs.

---

## Two Protocols Discovered

### 1. `codex exec --json` (Simple, one-shot)

```bash
echo "prompt" | codex exec --json [options] [resume <thread_id>]
```

- Spawns a **new process per turn**
- Writes prompt to stdin, closes stdin, reads JSONL events from stdout
- Process exits when the turn completes
- Session continuity via filesystem (`~/.codex/sessions`) + `resume <thread_id>`
- **No interactive permissions** -- approval requests are auto-cancelled in exec
  mode (confirmed in Rust source: `codex-rs/exec/src/lib.rs:524-532`)
- Default approval policy: `Never`
- Used by the TypeScript SDK (`@openai/codex-sdk`)

**JSONL Event Types:**

```
{"type":"thread.started","thread_id":"<uuid>"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"...","status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"...","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"..."}}
{"type":"turn.completed","usage":{"input_tokens":N,"cached_input_tokens":N,"output_tokens":N}}
```

**Item types:** `agent_message`, `reasoning`, `command_execution`, `file_change`,
`mcp_tool_call`, `web_search`, `todo_list`, `error`, `collab_tool_call`

### 2. `codex app-server` (Full, bidirectional)

```bash
codex app-server
# Then send JSON-RPC messages via stdin, read from stdout
```

- **Long-lived process** -- single process handles all threads and turns
- **Bidirectional JSON-RPC** over stdin/stdout (one JSON object per line)
- Full permission/approval flow via server-initiated requests
- Streaming item-level events (deltas for messages, reasoning, command output)
- This is the protocol used by the **VS Code Codex extension**
- 94 total methods: 56 client requests, 31 server notifications, 7 server
  requests

**Verified working handshake (tested):**

```
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"cc-insights","version":"0.1.0"}}}
← {"id":1,"result":{"userAgent":"cc-insights/0.93.0 ..."}}

→ {"jsonrpc":"2.0","method":"initialized"}

→ {"jsonrpc":"2.0","id":2,"method":"thread/start","params":{"workingDirectory":"/path","skipGitRepoCheck":true}}
← {"id":2,"result":{"thread":{"id":"<uuid>","preview":"","modelProvider":"openai",...}}}
← {"method":"thread/started","params":{"thread":{...}}}

→ {"jsonrpc":"2.0","id":3,"method":"turn/start","params":{"threadId":"<uuid>","input":[{"type":"text","text":"..."}]}}
← {"id":3,"result":{"turn":{"id":"0","items":[],"status":"inProgress"}}}
← {"method":"turn/started","params":{...}}
← {"method":"item/started","params":{"item":{"type":"reasoning",...}}}
← {"method":"item/reasoning/summaryTextDelta","params":{...}}
← {"method":"item/completed","params":{"item":{"type":"reasoning",...}}}
← {"method":"item/started","params":{"item":{"type":"commandExecution","command":"..."}}}
← {"method":"item/commandExecution/outputDelta","params":{...}}
← {"method":"item/completed","params":{"item":{"type":"commandExecution",...}}}
← {"method":"item/started","params":{"item":{"type":"agentMessage",...}}}
← {"method":"item/agentMessage/delta","params":{...}}
← {"method":"item/completed","params":{"item":{"type":"agentMessage","text":"..."}}}
← {"method":"turn/completed","params":{"turn":{"status":"completed"}}}
```

---

## Comparison with Claude Integration

| Aspect | Claude CLI | Codex `exec --json` | Codex `app-server` |
|--------|-----------|---------------------|-------------------|
| Process model | Long-lived | New per turn | Long-lived |
| Protocol | JSON Lines | JSON Lines | JSON-RPC |
| Bidirectional | Yes | No | Yes |
| Permission callbacks | Yes | No (auto-cancelled) | Yes |
| Streaming events | Yes | Yes | Yes (with deltas) |
| Multi-turn | In-process | Via filesystem resume | In-process |
| Init handshake | control_request/response | None | initialize/initialized |
| Message format | SDK messages | ThreadEvents | JSON-RPC notifications |
| Turn management | `session.create` on stdin | New process spawn | `turn/start` request |

### Key Differences from Claude

1. **No `stream-json` input mode.** Codex doesn't accept structured JSON on
   stdin in the way Claude does with `--input-format stream-json`. The
   `app-server` uses JSON-RPC instead.

2. **Thread-based, not session-based.** Codex calls them "threads" with
   "turns". Claude calls them "sessions" with messages. Semantically similar.

3. **App-server is the VS Code protocol.** Unlike Claude which has one
   protocol for all consumers, Codex has `exec` for automation and
   `app-server` for IDE integration. We want the IDE protocol.

4. **Richer item types.** Codex has `collab_tool_call` for multi-agent
   coordination (spawn, send_input, wait, close_agent) which Claude exposes
   differently via subagent conversations.

5. **Schema generation built in.** `codex app-server generate-json-schema`
   produces full JSON Schema for the entire protocol, making type generation
   straightforward.

---

## App-Server Protocol Details

### Client -> Server Requests (key methods)

**Lifecycle:**
- `initialize` -- handshake with clientInfo
- `thread/start` -- start new thread (params: workingDirectory, skipGitRepoCheck)
- `thread/resume` -- resume existing thread by ID
- `thread/fork` -- fork a thread
- `turn/start` -- send a turn (params: threadId, input)
- `turn/interrupt` -- cancel running turn

**Thread management:**
- `thread/list`, `thread/read`, `thread/archive`, `thread/unarchive`
- `thread/name/set`, `thread/rollback`

**Configuration:**
- `config/read`, `config/batchWrite`, `config/value/write`
- `model/list` -- list available models
- `skills/list` -- list available skills

### Server -> Client Notifications (streaming events)

**Turn lifecycle:**
- `turn/started`, `turn/completed`

**Item streaming:**
- `item/started`, `item/completed`
- `item/agentMessage/delta` -- streaming text chunks
- `item/commandExecution/outputDelta` -- streaming command output
- `item/reasoning/summaryTextDelta` -- streaming reasoning text
- `item/reasoning/summaryPartAdded`
- `item/fileChange/outputDelta`
- `item/mcpToolCall/progress`

**System:**
- `thread/started`, `thread/tokenUsage/updated`
- `account/rateLimits/updated`
- `error`

### Server -> Client Requests (permission flow)

These are requests **from Codex to us** that require a response:

- `item/commandExecution/requestApproval` -- approve/deny shell command
- `item/fileChange/requestApproval` -- approve/deny file modification
- `item/tool/requestUserInput` -- user input for tool (experimental)
- `item/tool/call` -- dynamic tool call execution on client side

**Legacy (deprecated but still present):**
- `execCommandApproval`
- `applyPatchApproval`

---

## Verified Test Results

### Test 1: exec --json simple query
```bash
echo "What is 2+2? Reply with just the number." | codex exec --json --skip-git-repo-check --sandbox read-only
```
**Result:** `4` -- works, clean JSONL output.

### Test 2: exec --json multi-turn resume
```bash
# Turn 1: Store info
echo "Remember ALPHA-7734" | codex exec --json --skip-git-repo-check --sandbox read-only
# → thread_id: 019c260f-7f3f-76b1-8a3d-6a95e1df5196

# Turn 2: Recall info
echo "What was the code?" | codex exec --json --skip-git-repo-check resume 019c260f-7f3f-76b1-8a3d-6a95e1df5196
# → "ALPHA-7734" ✓
```

### Test 3: exec --json command execution
```bash
echo "List files in current directory" | codex exec --json --sandbox read-only -C /path
```
**Result:** `command_execution` items with command, aggregated_output, exit_code,
and status lifecycle (in_progress -> completed).

### Test 4: app-server full turn (Python test script)
- Initialize handshake: works
- Thread creation: works (returns thread ID, path, model provider)
- Turn execution: works (streaming item events, deltas, completion)
- Multi-step: reasoning -> command_execution -> agent_message flow observed

---

## Implementation Strategy

### Recommended: Dart `CodexAppServerProcess`

Model this on `CliProcess` / `CliSession` but adapted for JSON-RPC:

```
CodexAppServerProcess
  ├── Spawns: codex app-server
  ├── Protocol: JSON-RPC over stdin/stdout (line-delimited)
  ├── Initialization: initialize → initialized
  ├── Thread mgmt: thread/start, thread/resume
  ├── Turn mgmt: turn/start, turn/interrupt
  └── Permissions: Handle server requests for approval

CodexSession (implements some shared interface)
  ├── Wraps a thread_id
  ├── send() → turn/start
  ├── Stream<CodexEvent> for notifications
  └── Permission request handling
```

### Mapping to CC-Insights Models

| Codex Concept | CC-Insights Model |
|---------------|-------------------|
| Thread | Chat |
| Turn | A send/response cycle within a Chat |
| Item (agentMessage) | OutputEntry (assistant message) |
| Item (commandExecution) | OutputEntry (tool use) |
| Item (fileChange) | OutputEntry (tool use - file) |
| Item (reasoning) | OutputEntry (thinking/reasoning) |
| Item (mcpToolCall) | OutputEntry (tool use - MCP) |
| Item (collabToolCall) | Subagent activity |
| requestApproval | Permission dialog |

### Key Implementation Decisions

1. **Use `app-server`, not `exec`.** The long-lived process model with
   bidirectional communication matches CC-Insights' architecture.

2. **Single app-server process.** One codex app-server can manage multiple
   threads, so we need only one process per Codex backend instance.

3. **JSON-RPC library.** Need a Dart JSON-RPC client/server library that
   works over stdin/stdout. Or implement a lightweight one -- the protocol is
   simple (request/response with notifications).

4. **Schema-driven types.** Use `codex app-server generate-json-schema` to
   generate Dart types, ensuring protocol compatibility.

5. **Permission flow maps naturally.** Codex's `requestApproval` server
   requests map directly to CC-Insights' existing permission dialog UI.

---

## Further Investigation Needed

1. **Permission approval response format.** We tested without triggering
   approvals (default auto-approve). Need to test with explicit approval
   policy to verify the response format for `item/commandExecution/requestApproval`.
   The schema shows `CommandExecutionRequestApprovalResponse` but we haven't
   seen the actual response format yet.

2. **Thread resume via app-server.** Tested resume via `exec` mode. Need to
   confirm `thread/resume` works in app-server and what events are emitted.

3. **File change items.** Codex used `command_execution` (shell command) to
   create files rather than `file_change` items. Need to test with models
   that produce native file patches to see `file_change` events.

4. **Collab/multi-agent events.** The JSONL processor shows
   `collab_tool_call` events (spawn_agent, send_input, wait, close_agent).
   Need to test with tasks that trigger multi-agent collaboration.

5. **MCP tool integration.** How do MCP tools configured in Codex appear via
   the app-server protocol? The `mcp_startup_complete` notification is
   already observed.

6. **Error handling and recovery.** What happens when the app-server process
   crashes? How to detect and restart?

7. **Configuration management.** How to pass model selection, sandbox mode,
   and other config via app-server (the `config/*` methods).

8. **`codex app-server generate-ts`** -- generates TypeScript bindings. Could
   be useful reference for Dart type generation.

9. **Rate limit integration.** The `account/rateLimits/updated` notifications
   provide real-time rate limit info. Could surface this in the UI.

10. **Authentication.** The protocol includes `account/login/*` methods and
    `chatgptAuthTokens/refresh`. Need to understand how auth flows work for
    different providers (API key vs ChatGPT login).

---

## Reference: TypeScript SDK Architecture

The existing TypeScript SDK at `/Users/zaf/projects/codex/sdk/typescript` uses
the simpler `exec` protocol, NOT `app-server`. Key files:

- `src/codex.ts` - Entry point, creates `CodexExec` and `Thread` instances
- `src/exec.ts` - Spawns `codex exec --experimental-json` subprocess
- `src/thread.ts` - Thread class with `run()` and `runStreamed()` methods
- `src/events.ts` - JSONL event type definitions
- `src/items.ts` - Thread item type definitions

The TypeScript SDK is a reference for the exec protocol but not for
app-server. For app-server, the JSON Schema output (`codex app-server
generate-json-schema`) is the authoritative reference.

---

## Reference: Protocol Schema Files

Generated via `codex app-server generate-json-schema --out <dir>`:

- `ClientRequest.json` - All client->server request methods
- `ServerRequest.json` - All server->client request methods (approvals)
- `ServerNotification.json` - All server->client notifications (events)
- `ClientNotification.json` - Client notifications (just `initialized`)
- `EventMsg.json` - Internal event message types
- Individual param/response schemas for each method

These schemas can be used for automated Dart type generation.
