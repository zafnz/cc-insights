# Task 2a Implementation Spec: Claude CLI → InsightsEvent Conversion

**For:** Sonnet implementation in Task 2b
**File to modify:** `claude_dart_sdk/lib/src/cli_session.dart`

---

## Current State (Post-Task 1)

Task 1 is complete. `CliSession` already has:
- `_eventsController` (broadcast `StreamController<InsightsEvent>`) — line 37
- `events` getter — line 47
- `_eventsController.close()` in `_dispose()` — line 491
- Import for `types/insights_events.dart` — line 7

**What's missing:** Nothing is ever added to `_eventsController`. The conversion methods don't exist yet.

---

## Overview

Add conversion methods to `CliSession` that transform incoming CLI JSON messages into `InsightsEvent` objects and emit them on the existing `_eventsController`.

### Data Flow

```
JSON from CLI → _handleMessage() → SDKMessage on _messagesController (existing)
                                  ↓
                                  _convertToInsightsEvents(json) → List<InsightsEvent>
                                  ↓
                                  _eventsController.add(event) for each
```

**Key principle:** One incoming JSON message can produce **multiple** InsightsEvent objects. An `assistant` message with `[text, thinking, tool_use]` content blocks produces 3 events (possibly 4 if the tool_use is a Task tool, which also emits SubagentSpawnEvent).

---

## Reference: Claude CLI Wire Format

This section contains everything Sonnet needs to know about the incoming JSON shapes and how they map to InsightsEvent types. All example JSON is taken from the actual CLI protocol.

### ToolKind Mapping Table

`ToolKind.fromToolName(toolName)` already exists in `agent_sdk_core/lib/src/types/tool_kind.dart`. The mapping:

| Claude CLI Tool Name | → `ToolKind` |
|----------------------|--------------|
| `Bash` | `execute` |
| `Read` | `read` |
| `Write` | `edit` |
| `Edit` | `edit` |
| `NotebookEdit` | `edit` |
| `Glob` | `search` |
| `Grep` | `search` |
| `WebFetch` | `fetch` |
| `WebSearch` | `browse` |
| `Task` | `think` |
| `AskUserQuestion` | `ask` |
| `TodoWrite` | `memory` |
| `mcp__*` (any prefix) | `mcp` |
| (anything else) | `other` |

### Message Type: `system` (subtype: `init`)

Example JSON:
```json
{
  "type": "system",
  "subtype": "init",
  "session_id": "abc-123",
  "uuid": "...",
  "model": "claude-sonnet-4-5-20250929",
  "cwd": "/Users/zaf/project",
  "tools": ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Task", "WebFetch", "WebSearch", "AskUserQuestion", "TodoWrite", "NotebookEdit"],
  "mcp_servers": [{"name": "flutter-test", "status": "connected"}],
  "permissionMode": "default",
  "apiKeySource": "ANTHROPIC_API_KEY",
  "slash_commands": ["compact", "clear", "help"],
  "output_style": "concise"
}
```

→ **`SessionInitEvent`**

| JSON field | → Event field | Notes |
|------------|---------------|-------|
| `session_id` | `sessionId` | |
| `model` | `model` | |
| `cwd` | `cwd` | |
| `tools` | `availableTools` | `List<String>` |
| `mcp_servers` | `mcpServers` | Parsed via `McpServerStatus.fromJson` |
| `permissionMode` | `permissionMode` | |
| `slash_commands` | `slashCommands` | Fallback: wrap strings as `SlashCommand(name: s, description: '', argumentHint: '')` |
| `apiKeySource` | `extensions['claude.apiKeySource']` | Claude-specific |
| `output_style` | `extensions['claude.outputStyle']` | Claude-specific |

Additionally merges data from the stored `control_response` (see below).

### Message Type: `control_response` (during initialization)

Example JSON:
```json
{
  "type": "control_response",
  "response": {
    "models": [
      {"value": "claude-sonnet-4-5-20250929", "displayName": "Sonnet 4.5", "description": "..."}
    ],
    "account": {
      "email": "user@example.com",
      "organization": "...",
      "subscriptionType": "pro",
      "tokenSource": "...",
      "apiKeySource": "..."
    },
    "commands": [
      {"name": "compact", "description": "Compact conversation", "argumentHint": ""}
    ],
    "output_style": "concise",
    "available_output_styles": ["plain", "concise", "verbose"]
  }
}
```

This is NOT emitted as a separate event. It's captured during `create()` and merged into `SessionInitEvent`:

| JSON path (under `response`) | → Event field | Notes |
|------------------------------|---------------|-------|
| `models[]` | `availableModels` | Parsed via `ModelInfo.fromJson` |
| `account` | `account` | Parsed via `AccountInfo.fromJson` |
| `commands[]` | `slashCommands` | Overrides the simple string list from `system/init`. Parsed via `SlashCommand.fromJson` |

### Message Type: `system` (subtype: `status`)

Example JSON:
```json
{"type": "system", "subtype": "status", "session_id": "abc-123", "status": "compacting"}
```

→ **`SessionStatusEvent`**

| JSON field | → Event field | Notes |
|------------|---------------|-------|
| `session_id` | `sessionId` | |
| `status` | `status` | Map string → `SessionStatus` enum: `"compacting"` → `.compacting`, `"resuming"` → `.resuming`, `"interrupted"` → `.interrupted`, `"ended"` → `.ended`, default → `.error` |
| `message` | `message` | Optional |

### Message Type: `system` (subtype: `compact_boundary`)

Example JSON:
```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "session_id": "abc-123",
  "compact_metadata": {"trigger": "auto", "pre_tokens": 180000}
}
```

→ **`ContextCompactionEvent`**

| JSON field | → Event field | Notes |
|------------|---------------|-------|
| `session_id` | `sessionId` | |
| `compact_metadata.trigger` | `trigger` | `"auto"` → `.auto`, `"manual"` → `.manual` |
| `compact_metadata.pre_tokens` | `preTokens` | |

### Message Type: `system` (subtype: `context_cleared`)

Example JSON:
```json
{"type": "system", "subtype": "context_cleared", "session_id": "abc-123"}
```

→ **`ContextCompactionEvent`** with `trigger: CompactionTrigger.cleared`

### Message Type: `assistant`

Example JSON:
```json
{
  "type": "assistant",
  "uuid": "...",
  "session_id": "abc-123",
  "parent_tool_use_id": null,
  "message": {
    "role": "assistant",
    "model": "claude-sonnet-4-5-20250929",
    "content": [
      {"type": "text", "text": "Here's the fix..."},
      {"type": "thinking", "thinking": "Let me analyze...", "signature": "..."},
      {"type": "tool_use", "id": "tu_123", "name": "Edit", "input": {"file_path": "/foo/bar.dart", "old_string": "...", "new_string": "..."}}
    ],
    "usage": {"input_tokens": 1000, "output_tokens": 500}
  }
}
```

Each content block produces a **separate** event:

#### `text` block → `TextEvent`

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].text` | `text` | |
| `parent_tool_use_id` | `parentCallId` | Non-null for subagent messages |
| `message.model` | `model` | |
| — | `kind` | Always `TextKind.text` |
| `session_id` | `sessionId` | |

#### `thinking` block → `TextEvent`

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].thinking` | `text` | Note: field is `thinking`, not `text` |
| `parent_tool_use_id` | `parentCallId` | |
| `message.model` | `model` | |
| — | `kind` | Always `TextKind.thinking` |
| `session_id` | `sessionId` | |

#### `tool_use` block → `ToolInvocationEvent`

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].id` | `callId` | Unique tool call ID for pairing with completion |
| `message.content[].name` | `toolName` | Raw tool name string |
| `message.content[].name` | `kind` | Derived via `ToolKind.fromToolName(toolName)` |
| `message.content[].input` | `input` | `Map<String, dynamic>` |
| `parent_tool_use_id` | `parentCallId` | |
| `message.model` | `model` | |
| `session_id` | `sessionId` | |
| Extracted from `input` | `locations` | See `_extractLocations` helper below |

#### `tool_use` where `name == "Task"` → additionally `SubagentSpawnEvent`

When the tool name is `"Task"`, emit **both** a `ToolInvocationEvent` (as above) **and** a `SubagentSpawnEvent`:

| JSON path (from `input`) | → Event field | Notes |
|--------------------------|---------------|-------|
| `input.subagent_type` or `input.name` | `agentType` | Try `subagent_type` first, fall back to `name` |
| `input.description` or `input.prompt` or `input.task` | `description` | Try in this order |
| `input.resume` | `isResume` | `true` if `resume` is non-null |
| `input.resume` | `resumeAgentId` | The agent ID being resumed |
| `message.content[].id` | `callId` | Same `callId` as the `ToolInvocationEvent` |
| `session_id` | `sessionId` | |

#### Location Extraction from Tool Input

The `_extractLocations` helper extracts file paths from tool input for display:

| Input field | Used by tools | Notes |
|-------------|--------------|-------|
| `file_path` | Read, Write, Edit | Primary file target |
| `path` | Grep, Glob | Search path/directory |
| `notebook_path` | NotebookEdit | Notebook file target |
| `pattern` | Glob only | Glob pattern as display location |

`cwd` from Bash input is intentionally **excluded** — it's a working directory, not a target.

### Message Type: `user`

Example JSON (tool result):
```json
{
  "type": "user",
  "uuid": "...",
  "session_id": "abc-123",
  "parent_tool_use_id": null,
  "isSynthetic": false,
  "tool_use_result": {"stdout": "file1.dart\nfile2.dart", "stderr": "", "exit_code": 0},
  "message": {
    "role": "user",
    "content": [
      {"type": "tool_result", "tool_use_id": "tu_123", "content": "file1.dart\nfile2.dart", "is_error": false}
    ]
  }
}
```

#### `tool_result` block → `ToolCompletionEvent`

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].tool_use_id` | `callId` | Pairs with the `ToolInvocationEvent.callId` |
| `tool_use_result` (top-level) | `output` | **Preferred** — richer structured data |
| `message.content[].content` | `output` | Fallback if `tool_use_result` is absent |
| `message.content[].is_error` | `isError` | |
| — | `status` | `isError ? ToolCallStatus.failed : ToolCallStatus.completed` |
| `session_id` | `sessionId` | |

**Why prefer `tool_use_result`:** The `content[].content` field is a flattened string. The `tool_use_result` field is structured data from the tool itself (e.g., `{stdout, stderr, exit_code}` for Bash, `{oldTodos, newTodos}` for TodoWrite).

#### Synthetic user message (context summary after compaction) → `TextEvent`

When `isSynthetic == true` and content contains a `text` block:

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].text` | `text` | The compaction summary |
| — | `kind` | `TextKind.text` |
| — | `extensions['claude.isSynthetic']` | `true` |
| `session_id` | `sessionId` | |

#### Replay user message (session resume) → `TextEvent`

When `isReplay == true` and content contains a `text` block:

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `message.content[].text` | `text` | Contains `<local-command-stdout>` XML tags |
| — | `kind` | `TextKind.text` |
| — | `extensions['claude.isReplay']` | `true` |
| `session_id` | `sessionId` | |

#### Regular user text

When `isSynthetic == false` and `isReplay == false`, text blocks in user messages are **not emitted** as events. The frontend already knows what the user typed.

#### String content

When `message.content` is a plain string (not a list), return empty — no event.

### Message Type: `result`

Example JSON:
```json
{
  "type": "result",
  "subtype": "success",
  "uuid": "...",
  "session_id": "abc-123",
  "duration_ms": 15000,
  "duration_api_ms": 12000,
  "is_error": false,
  "num_turns": 3,
  "total_cost_usd": 0.0234,
  "usage": {
    "input_tokens": 50000,
    "output_tokens": 3000,
    "cache_creation_input_tokens": 10000,
    "cache_read_input_tokens": 40000
  },
  "modelUsage": {
    "claude-sonnet-4-5-20250929": {
      "inputTokens": 50000,
      "outputTokens": 3000,
      "cacheReadInputTokens": 40000,
      "cacheCreationInputTokens": 10000,
      "webSearchRequests": 0,
      "costUSD": 0.0234,
      "contextWindow": 200000
    }
  },
  "permission_denials": [
    {"tool_name": "Bash", "tool_use_id": "tu_456", "tool_input": {"command": "rm -rf /"}}
  ]
}
```

→ **`TurnCompleteEvent`**

| JSON field | → Event field | Notes |
|------------|---------------|-------|
| `subtype` | `subtype` | `"success"`, `"error_max_turns"`, etc. |
| `is_error` | `isError` | |
| `duration_ms` | `durationMs` | Claude-only |
| `duration_api_ms` | `durationApiMs` | Claude-only |
| `num_turns` | `numTurns` | Claude-only |
| `total_cost_usd` | `costUsd` | Claude-only. Note: snake_case on wire |
| `result` | `result` | Final text output |
| `errors` | `errors` | `List<String>` |
| `session_id` | `sessionId` | |

**Aggregate `usage` (snake_case keys on wire):**

| JSON path | → `TokenUsage` field |
|-----------|---------------------|
| `usage.input_tokens` | `inputTokens` |
| `usage.output_tokens` | `outputTokens` |
| `usage.cache_read_input_tokens` | `cacheReadTokens` |
| `usage.cache_creation_input_tokens` | `cacheCreationTokens` |

**Per-model `modelUsage` (camelCase keys on wire, map keyed by model name):**

| JSON path | → `ModelTokenUsage` field | Notes |
|-----------|--------------------------|-------|
| `modelUsage.<model>.inputTokens` | `inputTokens` | camelCase on wire |
| `modelUsage.<model>.outputTokens` | `outputTokens` | camelCase on wire |
| `modelUsage.<model>.cacheReadInputTokens` | `cacheReadTokens` | camelCase on wire |
| `modelUsage.<model>.cacheCreationInputTokens` | `cacheCreationTokens` | camelCase on wire |
| `modelUsage.<model>.costUSD` | `costUsd` | **Capital `USD` on wire** |
| `modelUsage.<model>.contextWindow` | `contextWindow` | camelCase on wire |
| `modelUsage.<model>.webSearchRequests` | `webSearchRequests` | camelCase on wire |

**Permission denials:**

| JSON path | → `PermissionDenial` field |
|-----------|--------------------------|
| `permission_denials[].tool_name` | `toolName` |
| `permission_denials[].tool_use_id` | `toolUseId` |
| `permission_denials[].tool_input` | `toolInput` |

Parse via existing `PermissionDenial.fromJson()`.

### Message Type: `control_request`

Example JSON:
```json
{
  "type": "control_request",
  "request_id": "req-789",
  "session_id": "abc-123",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": {"command": "npm test"},
    "tool_use_id": "tu_789",
    "permission_suggestions": [
      {
        "type": "addRules",
        "rules": [{"toolName": "Bash", "ruleContent": "npm test:*"}],
        "behavior": "allow",
        "destination": "localSettings"
      }
    ],
    "blocked_path": "/Users/zaf/project"
  }
}
```

→ **`PermissionRequestEvent`** (only for `subtype == "can_use_tool"`)

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `request_id` | `requestId` | |
| `session_id` | `sessionId` | |
| `request.tool_name` | `toolName` | |
| `request.tool_name` | `toolKind` | Derived via `ToolKind.fromToolName` |
| `request.input` | `toolInput` | |
| `request.tool_use_id` | `toolUseId` | |
| `request.blocked_path` | `blockedPath` | |
| `request.permission_suggestions[]` | `suggestions` | Mapped to `PermissionSuggestionData` (see below) |

**PermissionSuggestionData mapping** (simplified data-only form, NOT the full `PermissionSuggestion` type):

| JSON path | → `PermissionSuggestionData` field |
|-----------|-----------------------------------|
| `type` | `type` |
| `tool_name` | `toolName` |
| `directory` | `directory` |
| `mode` | `mode` |
| `description` | `description` |

Note: also check for `suggestions` key (without `permission_` prefix) as a fallback — `request['permission_suggestions'] ?? request['suggestions']`.

Other `control_request` subtypes (e.g., `set_model`, `interrupt`) are **not** converted to events — return empty list.

### Message Type: `stream_event`

Example JSON sequence:
```json
{"type": "stream_event", "session_id": "abc-123", "parent_tool_use_id": null,
 "event": {"type": "message_start", "message": {"id": "msg_01...", "model": "claude-sonnet-4-5-20250929"}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Here"}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "Let me..."}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "content_block_delta", "index": 1, "delta": {"type": "input_json_delta", "partial_json": "{\"command\":"}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "content_block_stop", "index": 0}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "message_delta", "delta": {"stop_reason": "end_turn"}}}

{"type": "stream_event", "session_id": "abc-123",
 "event": {"type": "message_stop"}}
```

→ **`StreamDeltaEvent`** (one per stream_event message)

| Wire `event.type` | `event.delta.type` | → `StreamDeltaKind` | Data extracted |
|--------------------|--------------------|----------------------|----------------|
| `message_start` | — | `messageStart` | — |
| `content_block_start` | — | `blockStart` | `blockIndex` ← `event.index`; `callId` ← `event.content_block.id` if `content_block.type == "tool_use"` |
| `content_block_delta` | `text_delta` | `text` | `textDelta` ← `delta.text` |
| `content_block_delta` | `thinking_delta` | `thinking` | `textDelta` ← `delta.thinking` |
| `content_block_delta` | `input_json_delta` | `toolInput` | `jsonDelta` ← `delta.partial_json` |
| `content_block_stop` | — | `blockStop` | `blockIndex` ← `event.index` |
| `message_stop` | — | `messageStop` | — |
| `message_delta` | — | `messageStop` | `extensions['claude.stopReason']` ← `delta.stop_reason` |

Common fields for all `StreamDeltaEvent`:
- `sessionId` ← `json['session_id']`
- `parentCallId` ← `json['parent_tool_use_id']`

If `event.type` is unrecognized → return empty list (no error).

### Types NOT Converted to Events

| Wire type | Reason |
|-----------|--------|
| `control_response` | Data captured during `create()`, merged into `SessionInitEvent` |
| Unknown types | Return empty list, no error |
| `control_request` with subtype != `can_use_tool` | Not a permission event |

---

## Change 1: Store control_response Data

The `control_response` received during `create()` contains models, account info, and slash commands needed for `SessionInitEvent`. Currently this data is discarded after the handshake check. Store it.

### Add instance field (after line 34, `final SDKSystemMessage systemInit;`):

```dart
/// Data from the control_response received during initialization.
/// Merged into SessionInitEvent when system/init arrives.
final Map<String, dynamic>? _controlResponseData;
```

### Update constructor (line 24):

```dart
CliSession._({
  required CliProcess process,
  required this.sessionId,
  required this.systemInit,
  Map<String, dynamic>? controlResponseData,
}) : _process = process,
     _controlResponseData = controlResponseData {
  _setupMessageRouting();
}
```

### Capture in create() — around line 281-283:

Currently:
```dart
if (type == 'control_response') {
  controlResponseReceived = true;
  _t('CliSession', 'Step 3: control_response received');
```

Add a local variable before the `await for` loop (after line 269):
```dart
Map<String, dynamic>? controlResponseData;
```

Inside the `control_response` check:
```dart
if (type == 'control_response') {
  controlResponseReceived = true;
  controlResponseData = json['response'] as Map<String, dynamic>?;
  _t('CliSession', 'Step 3: control_response received');
```

Pass to constructor (line 329):
```dart
return CliSession._(
  process: process,
  sessionId: sessionId,
  systemInit: systemInit,
  controlResponseData: controlResponseData,
);
```

---

## Change 2: Event ID Generation

Add a monotonic counter for unique event IDs within a session.

### Add after the `_controlResponseData` field:

```dart
int _eventIdCounter = 0;

/// Generate a unique event ID for this session.
String _nextEventId() {
  _eventIdCounter++;
  return 'evt-${sessionId.hashCode.toRadixString(16)}-$_eventIdCounter';
}
```

Why this pattern:
- No external dependency (no `uuid` package needed)
- Unique within a session (counter is per-instance)
- Includes session hash for cross-session uniqueness
- Short and readable for debugging

---

## Change 3: New Imports

Add these imports at the top of `cli_session.dart` (some may already exist — only add what's missing):

```dart
import 'types/backend_provider.dart';
import 'types/tool_kind.dart';
import 'types/usage.dart';
```

`insights_events.dart` is already imported (line 7).

---

## Change 4: Main Conversion Method

Add after `_handleMessage()` (after line 168):

```dart
/// Convert a CLI JSON message into InsightsEvent objects.
///
/// Returns a list because some messages (e.g., assistant with multiple
/// content blocks) produce multiple events.
List<InsightsEvent> _convertToInsightsEvents(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  final subtype = json['subtype'] as String?;

  return switch (type) {
    'system' => switch (subtype) {
      'init' => [_convertSystemInit(json)],
      'status' => [_convertSystemStatus(json)],
      'compact_boundary' => [_convertCompactBoundary(json)],
      'context_cleared' => [_convertContextCleared(json)],
      _ => <InsightsEvent>[],
    },
    'assistant' => _convertAssistant(json),
    'user' => _convertUser(json),
    'result' => _convertResult(json),
    'control_request' => _convertControlRequest(json),
    'stream_event' => _convertStreamEvent(json),
    _ => <InsightsEvent>[],
  };
}
```

---

## Change 5: Integration into _handleMessage

At the end of `_handleMessage()`, after the existing switch statement (before the closing `}`), add:

```dart
// Emit InsightsEvents
try {
  final insightsEvents = _convertToInsightsEvents(json);
  for (final event in insightsEvents) {
    _eventsController.add(event);
  }
} catch (e) {
  SdkLogger.instance.error(
    'Failed to convert to InsightsEvent',
    sessionId: sessionId,
    data: {'error': e.toString(), 'type': json['type']},
  );
}
```

**Important:** This runs for ALL message types including `control_request`. The existing `control_request` case in the switch handles the permission flow via `_permissionRequestsController`. The new code additionally emits a `PermissionRequestEvent` on the events stream. Both streams are needed: the permission requests stream drives the interactive allow/deny flow, while the events stream is for observation/logging.

**Also important:** The `control_response` case currently does nothing (`break`). We do NOT emit an event for `control_response` — its data is captured during `create()` and merged into `SessionInitEvent` when `system/init` arrives.

---

## Change 6: Per-Message Conversion Methods

### 6.1: _convertSystemInit

Merges `system/init` JSON with stored `_controlResponseData`.

```dart
SessionInitEvent _convertSystemInit(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;

  // Parse MCP servers from system/init
  List<McpServerStatus>? mcpServers;
  final mcpList = json['mcp_servers'] as List?;
  if (mcpList != null) {
    mcpServers = mcpList
        .whereType<Map<String, dynamic>>()
        .map((m) => McpServerStatus.fromJson(m))
        .toList();
  }

  // Slash commands: start with simple string list from system/init
  List<SlashCommand>? slashCommands;
  final slashList = json['slash_commands'] as List?;
  if (slashList != null) {
    slashCommands = slashList
        .whereType<String>()
        .map((name) => SlashCommand(name: name, description: '', argumentHint: ''))
        .toList();
  }

  // Merge richer data from control_response
  List<ModelInfo>? availableModels;
  AccountInfo? account;
  if (_controlResponseData != null) {
    // Richer slash commands override the string list
    final commands = _controlResponseData!['commands'] as List?;
    if (commands != null) {
      slashCommands = commands
          .whereType<Map<String, dynamic>>()
          .map((c) => SlashCommand.fromJson(c))
          .toList();
    }

    final models = _controlResponseData!['models'] as List?;
    if (models != null) {
      availableModels = models
          .whereType<Map<String, dynamic>>()
          .map((m) => ModelInfo.fromJson(m))
          .toList();
    }

    final accountJson = _controlResponseData!['account'] as Map<String, dynamic>?;
    if (accountJson != null) {
      account = AccountInfo.fromJson(accountJson);
    }
  }

  // Claude-specific extensions
  final extensions = <String, dynamic>{};
  final apiKeySource = json['apiKeySource'] as String?;
  if (apiKeySource != null) extensions['claude.apiKeySource'] = apiKeySource;
  final outputStyle = json['output_style'] as String?;
  if (outputStyle != null) extensions['claude.outputStyle'] = outputStyle;

  return SessionInitEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    extensions: extensions.isNotEmpty ? extensions : null,
    sessionId: sid,
    model: json['model'] as String?,
    cwd: json['cwd'] as String?,
    availableTools: (json['tools'] as List?)?.cast<String>(),
    mcpServers: mcpServers,
    permissionMode: json['permissionMode'] as String?,
    account: account,
    slashCommands: slashCommands,
    availableModels: availableModels,
  );
}
```

**JSON paths consumed:**
| JSON path | → Event field |
|-----------|---------------|
| `session_id` | `sessionId` |
| `model` | `model` |
| `cwd` | `cwd` |
| `tools` | `availableTools` |
| `mcp_servers[].{name, status, serverInfo}` | `mcpServers` |
| `permissionMode` | `permissionMode` |
| `slash_commands[]` | `slashCommands` (fallback) |
| `apiKeySource` | `extensions['claude.apiKeySource']` |
| `output_style` | `extensions['claude.outputStyle']` |
| _From stored `_controlResponseData`:_ | |
| `commands[].{name, description, argumentHint}` | `slashCommands` (preferred) |
| `models[].{value, displayName, description}` | `availableModels` |
| `account.{email, organization, subscriptionType, ...}` | `account` |

---

### 6.2: _convertSystemStatus

```dart
SessionStatusEvent _convertSystemStatus(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final statusStr = json['status'] as String?;

  final status = switch (statusStr) {
    'compacting' => SessionStatus.compacting,
    'resuming' => SessionStatus.resuming,
    'interrupted' => SessionStatus.interrupted,
    'ended' => SessionStatus.ended,
    _ => SessionStatus.error,
  };

  return SessionStatusEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sid,
    status: status,
    message: json['message'] as String?,
  );
}
```

---

### 6.3: _convertCompactBoundary

```dart
ContextCompactionEvent _convertCompactBoundary(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final metadata = json['compact_metadata'] as Map<String, dynamic>?;

  final trigger = switch (metadata?['trigger'] as String?) {
    'manual' => CompactionTrigger.manual,
    _ => CompactionTrigger.auto,
  };

  return ContextCompactionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: sid,
    trigger: trigger,
    preTokens: metadata?['pre_tokens'] as int?,
  );
}
```

---

### 6.4: _convertContextCleared

```dart
ContextCompactionEvent _convertContextCleared(Map<String, dynamic> json) {
  return ContextCompactionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    raw: json,
    sessionId: json['session_id'] as String? ?? sessionId,
    trigger: CompactionTrigger.cleared,
  );
}
```

---

### 6.5: _convertAssistant

Returns **multiple events** — one per content block. This is the most complex converter.

```dart
List<InsightsEvent> _convertAssistant(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final parentToolUseId = json['parent_tool_use_id'] as String?;
  final message = json['message'] as Map<String, dynamic>?;
  final model = message?['model'] as String?;
  final content = message?['content'] as List?;

  if (content == null || content.isEmpty) return [];

  final events = <InsightsEvent>[];

  for (final block in content) {
    if (block is! Map<String, dynamic>) continue;
    final blockType = block['type'] as String?;

    switch (blockType) {
      case 'text':
        events.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          sessionId: sid,
          text: block['text'] as String? ?? '',
          kind: TextKind.text,
          parentCallId: parentToolUseId,
          model: model,
        ));

      case 'thinking':
        events.add(TextEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          sessionId: sid,
          text: block['thinking'] as String? ?? '',
          kind: TextKind.thinking,
          parentCallId: parentToolUseId,
          model: model,
        ));

      case 'tool_use':
        final callId = block['id'] as String? ?? _nextEventId();
        final toolName = block['name'] as String? ?? '';
        final input = block['input'] as Map<String, dynamic>? ?? {};

        events.add(ToolInvocationEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          callId: callId,
          parentCallId: parentToolUseId,
          sessionId: sid,
          kind: ToolKind.fromToolName(toolName),
          toolName: toolName,
          input: input,
          locations: _extractLocations(toolName, input),
          model: model,
        ));

        // Task tool → also emit SubagentSpawnEvent
        if (toolName == 'Task') {
          final resume = input['resume'] as String?;
          events.add(SubagentSpawnEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            sessionId: sid,
            callId: callId,
            agentType: input['subagent_type'] as String? ?? input['name'] as String?,
            description: input['description'] as String?
                ?? input['prompt'] as String?
                ?? input['task'] as String?,
            isResume: resume != null,
            resumeAgentId: resume,
          ));
        }
    }
  }

  return events;
}
```

**Content block → Event mapping:**

| Block type | → Event type | Key fields |
|------------|--------------|------------|
| `text` | `TextEvent(kind: TextKind.text)` | `block['text']` → `text` |
| `thinking` | `TextEvent(kind: TextKind.thinking)` | `block['thinking']` → `text` |
| `tool_use` | `ToolInvocationEvent` | `block['id']` → `callId`, `block['name']` → `toolName`, `block['input']` → `input` |
| `tool_use` where name == `Task` | `ToolInvocationEvent` + `SubagentSpawnEvent` | `input['subagent_type']` → `agentType`, `input['description']` → `description` |

**Common fields for all events from an assistant message:**
- `parentCallId` ← `json['parent_tool_use_id']` (non-null when this is a subagent response)
- `model` ← `json['message']['model']`
- `sessionId` ← `json['session_id']`

---

### 6.6: _extractLocations (helper)

```dart
/// Extract file/directory locations from tool input parameters.
List<String>? _extractLocations(String toolName, Map<String, dynamic> input) {
  final locations = <String>[];

  final filePath = input['file_path'] as String?;
  if (filePath != null) locations.add(filePath);

  final path = input['path'] as String?;
  if (path != null) locations.add(path);

  final notebookPath = input['notebook_path'] as String?;
  if (notebookPath != null) locations.add(notebookPath);

  // For Glob, the pattern is the location
  if (toolName == 'Glob') {
    final pattern = input['pattern'] as String?;
    if (pattern != null) locations.add(pattern);
  }

  return locations.isNotEmpty ? locations : null;
}
```

Supported input field names:
- `file_path` — Read, Write, Edit
- `path` — Grep, Glob (directory)
- `notebook_path` — NotebookEdit
- `pattern` — Glob only (treat glob pattern as a location for display)

Note: `cwd` from Bash input is intentionally excluded — it's a working directory, not a target location.

---

### 6.7: _convertUser

```dart
List<InsightsEvent> _convertUser(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final isSynthetic = json['isSynthetic'] as bool? ?? false;
  final isReplay = json['isReplay'] as bool? ?? false;
  final message = json['message'] as Map<String, dynamic>?;
  final content = message?['content'];

  // Handle string content (simple user text)
  if (content is String) {
    return []; // Plain user input — not emitted as InsightsEvent here
  }

  final contentList = content as List?;
  if (contentList == null || contentList.isEmpty) return [];

  final events = <InsightsEvent>[];

  for (final block in contentList) {
    if (block is! Map<String, dynamic>) continue;
    final blockType = block['type'] as String?;

    switch (blockType) {
      case 'tool_result':
        final toolUseId = block['tool_use_id'] as String? ?? _nextEventId();
        final isError = block['is_error'] as bool? ?? false;

        // Prefer structured tool_use_result over content field
        final output = json['tool_use_result'] ?? block['content'];

        events.add(ToolCompletionEvent(
          id: _nextEventId(),
          timestamp: DateTime.now(),
          provider: BackendProvider.claude,
          raw: json,
          callId: toolUseId,
          sessionId: sid,
          status: isError ? ToolCallStatus.failed : ToolCallStatus.completed,
          output: output,
          isError: isError,
        ));

      case 'text':
        if (isSynthetic || isReplay) {
          final extensions = <String, dynamic>{};
          if (isSynthetic) extensions['claude.isSynthetic'] = true;
          if (isReplay) extensions['claude.isReplay'] = true;

          events.add(TextEvent(
            id: _nextEventId(),
            timestamp: DateTime.now(),
            provider: BackendProvider.claude,
            raw: json,
            extensions: extensions,
            sessionId: sid,
            text: block['text'] as String? ?? '',
            kind: TextKind.text,
          ));
        }
        // Regular user text blocks in non-synthetic messages are not
        // emitted as events (the user's input was already sent by the
        // frontend — we don't echo it back).
    }
  }

  return events;
}
```

**Key behaviors:**
- `tool_result` blocks → `ToolCompletionEvent` with `callId` matching the original `ToolInvocationEvent.callId`
- `tool_use_result` field (top-level on the user message JSON) is preferred over `block['content']` because it contains richer structured data (e.g., TodoWrite returns `{oldTodos, newTodos}`)
- Synthetic text blocks (after compaction) → `TextEvent` with `extensions['claude.isSynthetic'] = true`
- Replay text blocks (session resume) → `TextEvent` with `extensions['claude.isReplay'] = true`
- Regular user text is NOT emitted (the frontend already knows what the user typed)

---

### 6.8: _convertResult

```dart
List<InsightsEvent> _convertResult(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;

  // Parse aggregate usage
  TokenUsage? usage;
  final usageJson = json['usage'] as Map<String, dynamic>?;
  if (usageJson != null) {
    usage = TokenUsage(
      inputTokens: usageJson['input_tokens'] as int? ?? 0,
      outputTokens: usageJson['output_tokens'] as int? ?? 0,
      cacheReadTokens: usageJson['cache_read_input_tokens'] as int?,
      cacheCreationTokens: usageJson['cache_creation_input_tokens'] as int?,
    );
  }

  // Parse per-model usage (camelCase keys on the wire)
  Map<String, ModelTokenUsage>? modelUsage;
  final modelUsageJson = json['modelUsage'] as Map<String, dynamic>?;
  if (modelUsageJson != null) {
    modelUsage = {};
    for (final entry in modelUsageJson.entries) {
      if (entry.value is! Map<String, dynamic>) continue;
      final m = entry.value as Map<String, dynamic>;
      modelUsage[entry.key] = ModelTokenUsage(
        inputTokens: m['inputTokens'] as int? ?? 0,
        outputTokens: m['outputTokens'] as int? ?? 0,
        cacheReadTokens: m['cacheReadInputTokens'] as int?,
        cacheCreationTokens: m['cacheCreationInputTokens'] as int?,
        costUsd: (m['costUSD'] as num?)?.toDouble(),
        contextWindow: m['contextWindow'] as int?,
        webSearchRequests: m['webSearchRequests'] as int?,
      );
    }
  }

  // Parse permission denials
  List<PermissionDenial>? permissionDenials;
  final denialsJson = json['permission_denials'] as List?;
  if (denialsJson != null) {
    permissionDenials = denialsJson
        .whereType<Map<String, dynamic>>()
        .map((d) => PermissionDenial.fromJson(d))
        .toList();
  }

  return [
    TurnCompleteEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sid,
      isError: json['is_error'] as bool? ?? false,
      subtype: json['subtype'] as String?,
      errors: (json['errors'] as List?)?.cast<String>(),
      result: json['result'] as String?,
      costUsd: (json['total_cost_usd'] as num?)?.toDouble(),
      durationMs: json['duration_ms'] as int?,
      durationApiMs: json['duration_api_ms'] as int?,
      numTurns: json['num_turns'] as int?,
      usage: usage,
      modelUsage: modelUsage,
      permissionDenials: permissionDenials,
    ),
  ];
}
```

**JSON → Event field mapping:**

| Wire JSON key | → Event field | Notes |
|---------------|---------------|-------|
| `subtype` | `subtype` | `"success"`, `"error_max_turns"`, etc. |
| `is_error` | `isError` | |
| `duration_ms` | `durationMs` | Claude-only |
| `duration_api_ms` | `durationApiMs` | Claude-only |
| `num_turns` | `numTurns` | Claude-only |
| `total_cost_usd` | `costUsd` | Claude-only |
| `result` | `result` | Final text output |
| `errors` | `errors` | Error message strings |
| `usage.input_tokens` | `usage.inputTokens` | snake_case on wire |
| `usage.output_tokens` | `usage.outputTokens` | snake_case on wire |
| `usage.cache_read_input_tokens` | `usage.cacheReadTokens` | snake_case on wire |
| `usage.cache_creation_input_tokens` | `usage.cacheCreationTokens` | snake_case on wire |
| `modelUsage.<model>.inputTokens` | `modelUsage[model].inputTokens` | camelCase on wire |
| `modelUsage.<model>.costUSD` | `modelUsage[model].costUsd` | Note: capital USD on wire |
| `modelUsage.<model>.contextWindow` | `modelUsage[model].contextWindow` | camelCase on wire |
| `permission_denials` | `permissionDenials` | Uses `PermissionDenial.fromJson` |

---

### 6.9: _convertControlRequest

```dart
List<InsightsEvent> _convertControlRequest(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final request = json['request'] as Map<String, dynamic>?;
  if (request == null) return [];

  // Only convert can_use_tool requests to events
  if (request['subtype'] != 'can_use_tool') return [];

  final toolName = request['tool_name'] as String? ?? '';
  final toolInput = request['input'] as Map<String, dynamic>? ?? {};

  // Parse permission suggestions into data-only form
  List<PermissionSuggestionData>? suggestions;
  final suggestionsJson = request['permission_suggestions'] as List?
      ?? request['suggestions'] as List?;
  if (suggestionsJson != null) {
    suggestions = suggestionsJson
        .whereType<Map<String, dynamic>>()
        .map((s) => PermissionSuggestionData(
              type: s['type'] as String? ?? '',
              toolName: s['tool_name'] as String?,
              directory: s['directory'] as String?,
              mode: s['mode'] as String?,
              description: s['description'] as String? ?? '',
            ))
        .toList();
  }

  return [
    PermissionRequestEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      sessionId: sid,
      requestId: json['request_id'] as String? ?? _nextEventId(),
      toolName: toolName,
      toolKind: ToolKind.fromToolName(toolName),
      toolInput: toolInput,
      toolUseId: request['tool_use_id'] as String?,
      blockedPath: request['blocked_path'] as String?,
      suggestions: suggestions,
    ),
  ];
}
```

**Note:** This emits a `PermissionRequestEvent` on the `events` stream alongside the existing `CliPermissionRequest` on the `permissionRequests` stream. They serve different purposes:
- `permissionRequests` stream: interactive flow (allow/deny with response callbacks)
- `events` stream: observation/logging (data-only, no response mechanism)

**Note on PermissionSuggestionData:** The events stream uses the simplified `PermissionSuggestionData` from `insights_events.dart`, NOT the full `PermissionSuggestion` type. The `PermissionSuggestion` type carries `rawJson` for passthrough to the SDK — that's only needed by the interactive permission flow, not the event observation layer.

---

### 6.10: _convertStreamEvent

```dart
List<InsightsEvent> _convertStreamEvent(Map<String, dynamic> json) {
  final sid = json['session_id'] as String? ?? sessionId;
  final parentToolUseId = json['parent_tool_use_id'] as String?;
  final event = json['event'] as Map<String, dynamic>?;
  if (event == null) return [];

  final eventType = event['type'] as String?;

  StreamDeltaKind? kind;
  String? textDelta;
  String? jsonDelta;
  int? blockIndex;
  String? callId;
  Map<String, dynamic>? extensions;

  switch (eventType) {
    case 'message_start':
      kind = StreamDeltaKind.messageStart;

    case 'content_block_start':
      kind = StreamDeltaKind.blockStart;
      blockIndex = event['index'] as int?;
      final contentBlock = event['content_block'] as Map<String, dynamic>?;
      if (contentBlock?['type'] == 'tool_use') {
        callId = contentBlock?['id'] as String?;
      }

    case 'content_block_delta':
      blockIndex = event['index'] as int?;
      final delta = event['delta'] as Map<String, dynamic>?;
      final deltaType = delta?['type'] as String?;

      switch (deltaType) {
        case 'text_delta':
          kind = StreamDeltaKind.text;
          textDelta = delta?['text'] as String?;
        case 'thinking_delta':
          kind = StreamDeltaKind.thinking;
          textDelta = delta?['thinking'] as String?;
        case 'input_json_delta':
          kind = StreamDeltaKind.toolInput;
          jsonDelta = delta?['partial_json'] as String?;
      }

    case 'content_block_stop':
      kind = StreamDeltaKind.blockStop;
      blockIndex = event['index'] as int?;

    case 'message_stop':
      kind = StreamDeltaKind.messageStop;

    case 'message_delta':
      kind = StreamDeltaKind.messageStop;
      final stopReason = (event['delta'] as Map<String, dynamic>?)?['stop_reason'] as String?;
      if (stopReason != null) {
        extensions = {'claude.stopReason': stopReason};
      }
  }

  if (kind == null) return [];

  return [
    StreamDeltaEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.claude,
      raw: json,
      extensions: extensions,
      sessionId: sid,
      parentCallId: parentToolUseId,
      kind: kind,
      textDelta: textDelta,
      jsonDelta: jsonDelta,
      blockIndex: blockIndex,
      callId: callId,
    ),
  ];
}
```

**Stream event type → StreamDeltaKind mapping:**

| Wire `event.type` | `event.delta.type` | → `StreamDeltaKind` | Data extracted |
|--------------------|--------------------|----------------------|----------------|
| `message_start` | — | `messageStart` | — |
| `content_block_start` | — | `blockStart` | `blockIndex`, `callId` (if tool_use) |
| `content_block_delta` | `text_delta` | `text` | `textDelta` ← `delta.text` |
| `content_block_delta` | `thinking_delta` | `thinking` | `textDelta` ← `delta.thinking` |
| `content_block_delta` | `input_json_delta` | `toolInput` | `jsonDelta` ← `delta.partial_json` |
| `content_block_stop` | — | `blockStop` | `blockIndex` |
| `message_stop` | — | `messageStop` | — |
| `message_delta` | — | `messageStop` | `stopReason` in extensions |

---

## Summary of All Changes

| # | Location | Change | Lines |
|---|----------|--------|-------|
| 1 | Instance field | Add `_controlResponseData` field | 3 |
| 2 | Constructor | Accept `controlResponseData` parameter | 3 |
| 3 | `create()` | Declare local var, capture response data, pass to constructor | 5 |
| 4 | Instance field + method | Add `_eventIdCounter` + `_nextEventId()` | 6 |
| 5 | Imports | Add `backend_provider.dart`, `tool_kind.dart`, `usage.dart` | 3 |
| 6 | New method | `_convertToInsightsEvents()` — main dispatch | 16 |
| 7 | `_handleMessage()` | Add event emission at end | 9 |
| 8 | New method | `_convertSystemInit()` | 55 |
| 9 | New method | `_convertSystemStatus()` | 18 |
| 10 | New method | `_convertCompactBoundary()` | 18 |
| 11 | New method | `_convertContextCleared()` | 10 |
| 12 | New method | `_convertAssistant()` | 75 |
| 13 | New method | `_extractLocations()` | 15 |
| 14 | New method | `_convertUser()` | 55 |
| 15 | New method | `_convertResult()` | 55 |
| 16 | New method | `_convertControlRequest()` | 35 |
| 17 | New method | `_convertStreamEvent()` | 55 |

**Total new code:** ~430 lines
**Modified existing code:** ~11 lines (constructor, create(), _handleMessage, imports)

---

## Edge Cases

1. **Missing fields:** All field access uses null-aware operators (`as String?`) with `?? defaultValue` fallbacks. No `!` operators.

2. **Malformed content blocks:** `if (block is! Map<String, dynamic>) continue` — silently skips non-map entries in content arrays.

3. **Empty content arrays:** Returns empty list — no error, no event emitted.

4. **Unknown block types:** The `switch` on `blockType` has no default — unknown types are silently ignored (standard Dart exhaustive-check-free switch).

5. **Multiple tool_results in one user message:** Each tool_result block produces a separate `ToolCompletionEvent`. The `tool_use_result` field (top-level) is shared across all — this is correct because Claude CLI only sends one tool_result per user message in practice. If multiple appear, all get the same structured result, but the `callId` differs.

6. **control_response during normal operation:** The existing `_handleMessage` already breaks on this case. The new `_convertToInsightsEvents` doesn't match it (no case for `'control_response'` in the switch), so it returns `[]`. Correct.

7. **Null event from stream_event:** If the `event.type` is unrecognized, `kind` remains null and we return `[]`. No crash.

---

## Testing Strategy (for Task 2c)

Tests should:
1. Construct a `CliSession` with mocked `CliProcess`
2. Feed known JSON messages via the process mock
3. Collect events from `session.events`
4. Assert event types, field values, and count

**Test cases to cover:**

| Test | Input JSON | Expected Events |
|------|-----------|-----------------|
| System init | `{type: system, subtype: init, ...}` | 1 × `SessionInitEvent` |
| System init with control_response | System init + stored control_response | `SessionInitEvent` with `availableModels`, `account`, rich `slashCommands` |
| System status | `{type: system, subtype: status, status: compacting}` | 1 × `SessionStatusEvent(status: compacting)` |
| Compact boundary | `{type: system, subtype: compact_boundary, compact_metadata: {trigger: auto, pre_tokens: 180000}}` | 1 × `ContextCompactionEvent(trigger: auto, preTokens: 180000)` |
| Context cleared | `{type: system, subtype: context_cleared}` | 1 × `ContextCompactionEvent(trigger: cleared)` |
| Assistant with text | `{type: assistant, message: {content: [{type: text, text: "Hi"}]}}` | 1 × `TextEvent(kind: text, text: "Hi")` |
| Assistant with thinking | `{type: assistant, message: {content: [{type: thinking, thinking: "..."}]}}` | 1 × `TextEvent(kind: thinking)` |
| Assistant with tool_use | `{type: assistant, message: {content: [{type: tool_use, id: "tu_1", name: "Bash", input: {command: "ls"}}]}}` | 1 × `ToolInvocationEvent(callId: "tu_1", kind: execute, toolName: "Bash")` |
| Assistant with mixed blocks | text + thinking + tool_use | 3 events in order |
| Assistant with Task tool | `{name: "Task", input: {subagent_type: "Explore", ...}}` | `ToolInvocationEvent` + `SubagentSpawnEvent` |
| User with tool_result | `{type: user, message: {content: [{type: tool_result, tool_use_id: "tu_1"}]}}` | 1 × `ToolCompletionEvent(callId: "tu_1")` |
| User with tool_use_result | Same + `tool_use_result: {stdout: "..."}` | `ToolCompletionEvent` with `output` = structured data |
| Synthetic user | `{isSynthetic: true, message: {content: [{type: text, text: "Summary"}]}}` | 1 × `TextEvent` with `extensions['claude.isSynthetic'] = true` |
| Result message | `{type: result, ...}` | 1 × `TurnCompleteEvent` with all fields |
| Control request | `{type: control_request, request: {subtype: can_use_tool, ...}}` | 1 × `PermissionRequestEvent` |
| Stream text delta | `{type: stream_event, event: {type: content_block_delta, delta: {type: text_delta, text: "Hi"}}}` | 1 × `StreamDeltaEvent(kind: text, textDelta: "Hi")` |
| Unknown type | `{type: "foo"}` | 0 events (no error) |
| parentToolUseId | assistant message with `parent_tool_use_id: "tu_parent"` | All events have `parentCallId: "tu_parent"` |

---

## End of Specification
