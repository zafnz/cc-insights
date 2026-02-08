# Task 3a Implementation Spec: Codex → InsightsEvent Conversion

**For:** Sonnet implementation in Task 3b
**File to modify:** `codex_dart_sdk/lib/src/codex_session.dart`

---

## Current State (Post-Task 1)

Task 1 is complete. `CodexSession` already has:
- `_eventsController` (broadcast `StreamController<InsightsEvent>`) — line 41
- `events` getter — line 70
- `_eventsController.close()` in `_dispose()` — line 628
- Import for `agent_sdk_core` (which re-exports `InsightsEvent` types) — line 5

**What's missing:** Nothing is ever added to `_eventsController`. The event emission code doesn't exist yet.

---

## Overview

Add InsightsEvent emission to `CodexSession` so that every Codex JSON-RPC notification and server request produces the corresponding typed event on the `events` stream — **directly**, without going through synthetic SDKMessage JSON.

### Current "Squish" Flow (being bypassed)

```
Codex notification → _handleNotification() → _emitSdkMessage() → SDKMessage on _messagesController
                                                                  ↓
                                                     SdkMessageHandler reads rawJson back out
```

### New Direct Flow (what we're adding)

```
Codex notification → _handleNotification() → existing SDKMessage flow (unchanged)
                                            ↓
                                            _eventsController.add(InsightsEvent)
```

**Key principle:** We emit InsightsEvents **alongside** the existing SDKMessage flow. The SDKMessage path remains for backwards compatibility until Task 5 removes it. Each handler method emits one event at the point where the data is already extracted.

---

## Architectural Difference from Task 2a (Claude)

In Claude's `CliSession`, all incoming data is raw JSON parsed in a single `_handleMessage()` method, so a centralized `_convertToInsightsEvents(json)` makes sense.

In Codex's `CodexSession`, the data is already destructured by the JSON-RPC layer into typed `JsonRpcNotification` / `JsonRpcServerRequest` objects, and further broken down in per-handler methods (`_handleThreadStarted`, `_handleItemStarted`, etc.). The data is already in local variables at the point of use.

**Therefore:** Instead of a centralized converter, we emit InsightsEvents **inline within each existing handler method**, right alongside the existing `_emitSdkMessage()` calls. This avoids redundant re-parsing and keeps each event emission close to its data source.

---

## Change 1: New Imports

No new imports needed. `CodexSession` already imports `package:agent_sdk_core/agent_sdk_core.dart` (line 5), which re-exports all InsightsEvent types, `BackendProvider`, `ToolKind`, `TokenUsage`, etc.

---

## Change 2: Event ID Generation

Add a monotonic counter for unique event IDs within a session. Add after `_effortOverride` (line 61):

```dart
int _eventIdCounter = 0;

String _nextEventId() {
  _eventIdCounter++;
  return 'evt-codex-${threadId.hashCode.toRadixString(16)}-$_eventIdCounter';
}
```

Pattern matches Claude's `_nextEventId()` but with a `codex` prefix for easy identification in debugging. Uses `threadId` instead of `sessionId` (they're the same in Codex, but `threadId` is the canonical name).

---

## Change 3: Codex-Specific ToolKind Mapping Helper

Codex uses item types (`commandExecution`, `fileChange`, `mcpToolCall`) rather than tool names. Add a helper method to map Codex item types to `ToolKind` and display tool names. Add after `_nextEventId()`:

```dart
/// Maps a Codex item type to a ToolKind and display tool name.
({ToolKind kind, String toolName}) _codexToolKind(String itemType, Map<String, dynamic> item) {
  return switch (itemType) {
    'commandExecution' => (kind: ToolKind.execute, toolName: 'Bash'),
    'fileChange' => (kind: ToolKind.edit, toolName: 'FileChange'),
    'mcpToolCall' => (
      kind: ToolKind.mcp,
      toolName: _mcpToolName(item),
    ),
    _ => (kind: ToolKind.other, toolName: itemType),
  };
}

/// Constructs a Claude-compatible MCP tool name: `mcp__<server>__<tool>`.
String _mcpToolName(Map<String, dynamic> item) {
  final server = item['server'] as String? ?? '';
  final tool = item['tool'] as String? ?? '';
  if (server.isNotEmpty && tool.isNotEmpty) {
    return 'mcp__${server}__$tool';
  }
  return 'McpTool';
}
```

**Why `_mcpToolName` constructs `mcp__<server>__<tool>`:** This matches the Claude CLI's naming convention for MCP tools. The frontend's `ToolCard` uses this pattern to detect MCP tools and apply MCP-specific rendering. Without it, MCP tool calls from Codex would render as generic tools.

**Why `FileChange` instead of `Write`:** Codex's `fileChange` is semantically different from Claude's `Write` tool — it can contain multiple files and always carries diffs. Using `FileChange` as the display name preserves Codex's native semantics. The `ToolKind.edit` classification still triggers the correct UI rendering.

---

## Change 4: Location Extraction Helper for Codex

Add after `_codexToolKind`:

```dart
/// Extract file paths from a Codex item for the `locations` field.
List<String>? _extractCodexLocations(String itemType, Map<String, dynamic> item) {
  switch (itemType) {
    case 'commandExecution':
      // No file location for commands (cwd is not a target)
      return null;
    case 'fileChange':
      final changes = item['changes'] as List<dynamic>? ?? const [];
      final paths = changes
          .whereType<Map<String, dynamic>>()
          .map((c) => c['path'] as String?)
          .whereType<String>()
          .toList();
      return paths.isNotEmpty ? paths : null;
    case 'mcpToolCall':
      // MCP tools don't have standard file paths
      return null;
    default:
      return null;
  }
}
```

---

## Change 5: Emit Events in `_handleThreadStarted`

**Wire format (JSON-RPC notification from Codex):**

```json
{
  "jsonrpc": "2.0",
  "method": "thread/started",
  "params": {
    "thread": {
      "id": "thread-abc-123",
      "model": "o4-mini"
    }
  }
}
```

Current code (lines 209-221):

```dart
void _handleThreadStarted(Map<String, dynamic> params) {
  final thread = params['thread'] as Map<String, dynamic>?;
  final id = thread?['id'] as String?;
  if (id != threadId) return;

  _emitSdkMessage({
    'type': 'system',
    'subtype': 'init',
    'session_id': threadId,
    'uuid': _nextUuid(),
    'model': thread?['model'] as String?,
  });
}
```

**Add after the `_emitSdkMessage()` call (before closing `}`):**

```dart
_eventsController.add(SessionInitEvent(
  id: _nextEventId(),
  timestamp: DateTime.now(),
  provider: BackendProvider.codex,
  raw: params,
  sessionId: threadId,
  model: thread?['model'] as String?,
  // Codex doesn't provide these in thread/started:
  // cwd, availableTools, mcpServers, permissionMode,
  // account, slashCommands, availableModels
));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `thread.id` | `sessionId` | Already validated = `threadId` |
| `thread.model` | `model` | |
| — | `cwd` | null (Codex doesn't report) |
| — | `availableTools` | null (Codex manages tools internally) |
| — | `mcpServers` | null |
| — | `permissionMode` | null (Codex manages server-side) |
| — | `account` | null |
| — | `slashCommands` | null |
| — | `availableModels` | null (comes from separate `model/list` call) |

---

## Change 6: Emit Events in `_handleTurnStarted`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "turn/started",
  "params": {
    "threadId": "thread-abc-123",
    "turn": {"id": "turn-xyz"}
  }
}
```

Current code (lines 223-229):

```dart
void _handleTurnStarted(Map<String, dynamic> params) {
  final id = params['threadId'] as String?;
  if (id != threadId) return;

  final turn = params['turn'] as Map<String, dynamic>?;
  _currentTurnId = turn?['id'] as String?;
}
```

**No InsightsEvent emitted.** Per the mapping doc, `turn/started` only tracks the turn ID internally for interrupt support. The frontend sees the turn via subsequent item events.

**No change needed.** (Documented here for completeness.)

---

## Change 7: Emit Events in `_handleTokenUsageUpdated`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "thread/tokenUsage/updated",
  "params": {
    "threadId": "thread-abc-123",
    "tokenUsage": {
      "total": {
        "inputTokens": 5000,
        "outputTokens": 1500,
        "cachedInputTokens": 3000
      }
    }
  }
}
```

Current code (lines 231-235):

```dart
void _handleTokenUsageUpdated(Map<String, dynamic> params) {
  final id = params['threadId'] as String?;
  if (id != threadId) return;
  _latestTokenUsage = params['tokenUsage'] as Map<String, dynamic>?;
}
```

**No InsightsEvent emitted.** Token usage is accumulated internally and included in the `TurnCompleteEvent` when the turn finishes.

**No change needed.** (Documented here for completeness.)

---

## Change 8: Emit Events in `_handleItemStarted`

Current code (lines 237-274) handles three item types: `commandExecution`, `fileChange`, `mcpToolCall`.

**For each case, add a `_eventsController.add(ToolInvocationEvent(...))` call alongside the existing `_emitToolUse()` call.**

### 8a: `commandExecution` started

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-001",
      "type": "commandExecution",
      "command": "npm test",
      "cwd": "/Users/zaf/project"
    }
  }
}
```

Current (lines 246-254):
```dart
case 'commandExecution':
  _emitToolUse(
    toolUseId: item['id'] as String? ?? '',
    toolName: 'Bash',
    toolInput: {
      'command': item['command'] ?? '',
      'cwd': item['cwd'] ?? '',
    },
  );
```

**Add after `_emitToolUse(...)` and before the next `case`:**

```dart
  _eventsController.add(ToolInvocationEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    kind: ToolKind.execute,
    toolName: 'Bash',
    input: {
      'command': item['command'] ?? '',
      'cwd': item['cwd'] ?? '',
    },
    extensions: {
      'codex.itemType': 'commandExecution',
    },
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `item.id` | `callId` | |
| — | `parentCallId` | null (Codex doesn't support subagents) |
| `"commandExecution"` | `kind` = `ToolKind.execute` | |
| `"Bash"` | `toolName` | Mapped for display compatibility |
| `item.command` | `input.command` | |
| `item.cwd` | `input.cwd` | |
| — | `locations` | null (cwd is not a file target) |
| `"commandExecution"` | `extensions['codex.itemType']` | Preserves native vocabulary |

### 8b: `fileChange` started

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-002",
      "type": "fileChange",
      "changes": [
        {"path": "/project/src/main.dart", "diff": "--- a/...\n+++ b/..."}
      ]
    }
  }
}
```

**Key change from current approach:** Instead of flattening multi-file changes into a single `file_path` + `content` string (losing all but the first path), we preserve the full `changes` array in `input` and extract all paths into `locations`.

Current (lines 255-260):
```dart
case 'fileChange':
  _emitToolUse(
    toolUseId: item['id'] as String? ?? '',
    toolName: 'Write',
    toolInput: _fileChangeInput(item),
  );
```

**Add after `_emitToolUse(...)` and before the next `case`:**

```dart
  final fileChangePaths = _extractCodexLocations('fileChange', item);
  _eventsController.add(ToolInvocationEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    kind: ToolKind.edit,
    toolName: 'FileChange',
    input: _fileChangeInput(item),
    locations: fileChangePaths,
    extensions: {
      'codex.itemType': 'fileChange',
    },
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `item.id` | `callId` | |
| `"fileChange"` | `kind` = `ToolKind.edit` | |
| `"FileChange"` | `toolName` | Preserves Codex semantics (not "Write") |
| `_fileChangeInput(item)` | `input` | Reuses existing helper |
| `changes[].path` | `locations` | All affected file paths |
| `"fileChange"` | `extensions['codex.itemType']` | |

### 8c: `mcpToolCall` started

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/started",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-003",
      "type": "mcpToolCall",
      "server": "flutter-test",
      "tool": "run_tests",
      "arguments": {"project_path": "/project"}
    }
  }
}
```

**Key change from current approach:** Instead of mapping to the made-up name `McpTool`, we reconstruct the `mcp__<server>__<tool>` naming convention so `ToolCard` can apply its MCP-specific rendering.

Current (lines 261-270):
```dart
case 'mcpToolCall':
  _emitToolUse(
    toolUseId: item['id'] as String? ?? '',
    toolName: 'McpTool',
    toolInput: {
      'server': item['server'],
      'tool': item['tool'],
      'arguments': item['arguments'],
    },
  );
```

**Add after `_emitToolUse(...)` and before `default`:**

```dart
  _eventsController.add(ToolInvocationEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    kind: ToolKind.mcp,
    toolName: _mcpToolName(item),
    input: {
      'server': item['server'],
      'tool': item['tool'],
      'arguments': item['arguments'],
    },
    extensions: {
      'codex.itemType': 'mcpToolCall',
    },
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `item.id` | `callId` | |
| `"mcpToolCall"` | `kind` = `ToolKind.mcp` | |
| `mcp__<server>__<tool>` | `toolName` | Reconstructed via `_mcpToolName()` |
| `{server, tool, arguments}` | `input` | |
| `"mcpToolCall"` | `extensions['codex.itemType']` | |

---

## Change 9: Emit Events in `_handleItemCompleted`

Current code (lines 276-324) handles six item types: `agentMessage`, `reasoning`, `plan`, `commandExecution`, `fileChange`, `mcpToolCall`.

### 9a: `agentMessage` completed → `TextEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-004",
      "type": "agentMessage",
      "text": "Here's what I found..."
    }
  }
}
```

Current (lines 285-286):
```dart
case 'agentMessage':
  _emitAssistantText(item['text'] as String? ?? '');
```

**Add after `_emitAssistantText(...):`**

```dart
  _eventsController.add(TextEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    sessionId: threadId,
    text: item['text'] as String? ?? '',
    kind: TextKind.text,
  ));
```

**Mapping:**

| JSON path | → Event field |
|-----------|---------------|
| `item.text` | `text` |
| — | `kind` = `TextKind.text` |
| — | `parentCallId` = null (no subagents in Codex) |
| — | `model` = null (not available per-item) |

### 9b: `reasoning` completed → `TextEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-005",
      "type": "reasoning",
      "summary": ["Analyzing the code structure..."],
      "content": ["Let me think about this..."]
    }
  }
}
```

Current (lines 287-293):
```dart
case 'reasoning':
  final summary = (item['summary'] as List?)?.join('\n') ?? '';
  final content = (item['content'] as List?)?.join('\n') ?? '';
  final thinking = summary.isNotEmpty ? summary : content;
  if (thinking.isNotEmpty) {
    _emitAssistantThinking(thinking);
  }
```

**Add after the `if (thinking.isNotEmpty) { _emitAssistantThinking(thinking); }` block:**

```dart
  if (thinking.isNotEmpty) {
    _eventsController.add(TextEvent(
      id: _nextEventId(),
      timestamp: DateTime.now(),
      provider: BackendProvider.codex,
      raw: params,
      sessionId: threadId,
      text: thinking,
      kind: TextKind.thinking,
    ));
  }
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `summary.join('\n')` or `content.join('\n')` | `text` | Prefers summary |
| — | `kind` = `TextKind.thinking` | |

### 9c: `plan` completed → `TextEvent`

Current (lines 294-295):
```dart
case 'plan':
  _emitAssistantText(item['text'] as String? ?? '');
```

**Add after `_emitAssistantText(...):`**

```dart
  _eventsController.add(TextEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    sessionId: threadId,
    text: item['text'] as String? ?? '',
    kind: TextKind.plan,
  ));
```

**Mapping:**

| JSON path | → Event field |
|-----------|---------------|
| `item.text` | `text` |
| — | `kind` = `TextKind.plan` |

### 9d: `commandExecution` completed → `ToolCompletionEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-001",
      "type": "commandExecution",
      "aggregatedOutput": "All tests passed\n",
      "exitCode": 0
    }
  }
}
```

Current (lines 296-306):
```dart
case 'commandExecution':
  _emitToolResult(
    toolUseId: item['id'] as String? ?? '',
    result: {
      'stdout': item['aggregatedOutput'] ?? '',
      'stderr': '',
      'exit_code': item['exitCode'],
    },
    isError: (item['exitCode'] as int?) != null &&
        (item['exitCode'] as int?) != 0,
  );
```

**Add after `_emitToolResult(...):`**

```dart
  final cmdIsError = (item['exitCode'] as int?) != null &&
      (item['exitCode'] as int?) != 0;
  _eventsController.add(ToolCompletionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    status: cmdIsError ? ToolCallStatus.failed : ToolCallStatus.completed,
    output: {
      'stdout': item['aggregatedOutput'] ?? '',
      'stderr': '',
      'exit_code': item['exitCode'],
    },
    isError: cmdIsError,
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `item.id` | `callId` | Pairs with `ToolInvocationEvent.callId` |
| `item.exitCode != 0` | `isError` | |
| `item.exitCode != 0` | `status` = `failed` or `completed` | |
| `{stdout: aggregatedOutput, stderr: '', exit_code: exitCode}` | `output` | Structured for consistency |

### 9e: `fileChange` completed → `ToolCompletionEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-002",
      "type": "fileChange",
      "status": "completed",
      "changes": [
        {"path": "/project/src/main.dart", "diff": "--- a/...\n+++ b/..."}
      ]
    }
  }
}
```

Current (lines 307-312):
```dart
case 'fileChange':
  _emitToolResult(
    toolUseId: item['id'] as String? ?? '',
    result: _fileChangeResult(item),
    isError: (item['status'] as String?) == 'failed',
  );
```

**Add after `_emitToolResult(...):`**

```dart
  final fileIsError = (item['status'] as String?) == 'failed';
  final completedPaths = _extractCodexLocations('fileChange', item);
  _eventsController.add(ToolCompletionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    status: fileIsError ? ToolCallStatus.failed : ToolCallStatus.completed,
    output: _fileChangeResult(item),
    isError: fileIsError,
    locations: completedPaths,
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `item.id` | `callId` | |
| `item.status == "failed"` | `isError` | |
| `_fileChangeResult(item)` | `output` | Reuses existing helper |
| `changes[].path` | `locations` | All affected file paths |

### 9f: `mcpToolCall` completed → `ToolCompletionEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "item/completed",
  "params": {
    "threadId": "thread-abc-123",
    "item": {
      "id": "item-003",
      "type": "mcpToolCall",
      "result": {"summary": "5 tests passed"},
      "error": null
    }
  }
}
```

Current (lines 313-320):
```dart
case 'mcpToolCall':
  final error = item['error'] as Map<String, dynamic>?;
  final result = item['result'] as Map<String, dynamic>?;
  _emitToolResult(
    toolUseId: item['id'] as String? ?? '',
    result: result ?? error ?? {},
    isError: error != null,
  );
```

**Add after `_emitToolResult(...):`**

```dart
  _eventsController.add(ToolCompletionEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    callId: item['id'] as String? ?? '',
    sessionId: threadId,
    status: error != null ? ToolCallStatus.failed : ToolCallStatus.completed,
    output: result ?? error ?? {},
    isError: error != null,
  ));
```

**Mapping:**

| JSON path | → Event field |
|-----------|---------------|
| `item.id` | `callId` |
| `item.error != null` | `isError` |
| `item.result ?? item.error` | `output` |

---

## Change 10: Emit Events in `_handleTurnCompleted`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "method": "turn/completed",
  "params": {
    "threadId": "thread-abc-123"
  }
}
```

Note: The token usage data comes from a **prior** `thread/tokenUsage/updated` notification (see Change 7 wire format), stored in `_latestTokenUsage`. The `turn/completed` notification itself has no usage data — it triggers reading the accumulated state.

Current code (lines 326-353):

```dart
void _handleTurnCompleted(Map<String, dynamic> params) {
  final id = params['threadId'] as String?;
  if (id != threadId) return;
  _currentTurnId = null;

  final usage = _latestTokenUsage?['total'] as Map<String, dynamic>?;
  final inputTokens = (usage?['inputTokens'] as num?)?.toInt() ?? 0;
  final outputTokens = (usage?['outputTokens'] as num?)?.toInt() ?? 0;
  final cachedInput = (usage?['cachedInputTokens'] as num?)?.toInt() ?? 0;

  _emitSdkMessage({...});
}
```

**Add after `_emitSdkMessage(...)` and before closing `}`:**

```dart
_eventsController.add(TurnCompleteEvent(
  id: _nextEventId(),
  timestamp: DateTime.now(),
  provider: BackendProvider.codex,
  raw: params,
  sessionId: threadId,
  isError: false,
  subtype: 'success',
  usage: TokenUsage(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: cachedInput > 0 ? cachedInput : null,
  ),
  // Codex doesn't provide these:
  // costUsd, durationMs, durationApiMs, numTurns,
  // modelUsage, permissionDenials, errors, result
));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| — | `isError` = false | Codex doesn't report turn-level errors |
| — | `subtype` = `"success"` | |
| Accumulated `tokenUsage.total.inputTokens` | `usage.inputTokens` | |
| Accumulated `tokenUsage.total.outputTokens` | `usage.outputTokens` | |
| Accumulated `tokenUsage.total.cachedInputTokens` | `usage.cacheReadTokens` | null if 0 |
| — | `costUsd` | null (Codex doesn't report cost) |
| — | `durationMs` | null |
| — | `durationApiMs` | null |
| — | `numTurns` | null |
| — | `modelUsage` | null (Codex doesn't report per-model breakdown) |
| — | `permissionDenials` | null |

---

## Change 11: Emit Events in `_handleServerRequest` — Permission Requests

Current code (lines 108-143) handles three request types. For each, emit a `PermissionRequestEvent` **alongside** the existing `PermissionRequest` on the permission stream.

### 11a: `item/commandExecution/requestApproval` → `PermissionRequestEvent`

**Wire format (JSON-RPC server request — requires response):**

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "method": "item/commandExecution/requestApproval",
  "params": {
    "threadId": "thread-abc-123",
    "command": "rm -rf node_modules",
    "cwd": "/Users/zaf/project",
    "itemId": "item-010",
    "commandActions": ["allow", "deny"],
    "reason": "This command modifies the filesystem"
  }
}
```

**Response mapping (for reference — handled by existing approval code):**
- `allow()` → JSON-RPC response: `{decision: "accept"}`
- `deny(interrupt: false)` → `{decision: "decline"}`
- `deny(interrupt: true)` → `{decision: "cancel"}`

Current (lines 115-124):
```dart
case 'item/commandExecution/requestApproval':
  _emitApprovalRequest(
    request,
    toolName: 'Bash',
    toolInput: {
      'command': params['command'] ?? '',
      'cwd': params['cwd'] ?? '',
    },
    toolUseId: params['itemId'] as String?,
  );
```

**Add after `_emitApprovalRequest(...):`**

```dart
  _eventsController.add(PermissionRequestEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    sessionId: threadId,
    requestId: request.id.toString(),
    toolName: 'Bash',
    toolKind: ToolKind.execute,
    toolInput: {
      'command': params['command'] ?? '',
      'cwd': params['cwd'] ?? '',
    },
    toolUseId: params['itemId'] as String?,
    reason: params['reason'] as String?,
    extensions: {
      if (params['commandActions'] != null)
        'codex.commandActions': params['commandActions'],
    },
  ));
```

**Mapping:**

| JSON path | → Event field | Notes |
|-----------|---------------|-------|
| `request.id` (JSON-RPC) | `requestId` (as string) | |
| `"Bash"` | `toolName` | |
| `ToolKind.execute` | `toolKind` | |
| `{command, cwd}` | `toolInput` | |
| `params.itemId` | `toolUseId` | |
| `params.reason` | `reason` | |
| — | `suggestions` | null (Codex doesn't support) |
| — | `blockedPath` | null |
| `params.commandActions` | `extensions['codex.commandActions']` | Codex-specific |

### 11b: `item/fileChange/requestApproval` → `PermissionRequestEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "id": 43,
  "method": "item/fileChange/requestApproval",
  "params": {
    "threadId": "thread-abc-123",
    "grantRoot": "/Users/zaf/project/src",
    "itemId": "item-011"
  }
}
```

Current (lines 125-133):
```dart
case 'item/fileChange/requestApproval':
  _emitApprovalRequest(
    request,
    toolName: 'Write',
    toolInput: {
      'file_path': params['grantRoot'] ?? '',
    },
    toolUseId: params['itemId'] as String?,
  );
```

**Add after `_emitApprovalRequest(...):`**

```dart
  _eventsController.add(PermissionRequestEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    sessionId: threadId,
    requestId: request.id.toString(),
    toolName: 'Write',
    toolKind: ToolKind.edit,
    toolInput: {
      'file_path': params['grantRoot'] ?? '',
    },
    toolUseId: params['itemId'] as String?,
    extensions: {
      if (params['grantRoot'] != null)
        'codex.grantRoot': params['grantRoot'],
    },
  ));
```

**Mapping:**

| JSON path | → Event field |
|-----------|---------------|
| `request.id` | `requestId` |
| `"Write"` | `toolName` |
| `ToolKind.edit` | `toolKind` |
| `{file_path: grantRoot}` | `toolInput` |
| `params.itemId` | `toolUseId` |
| `params.grantRoot` | `extensions['codex.grantRoot']` |

### 11c: `item/tool/requestUserInput` → `PermissionRequestEvent`

**Wire format:**

```json
{
  "jsonrpc": "2.0",
  "id": 44,
  "method": "item/tool/requestUserInput",
  "params": {
    "threadId": "thread-abc-123",
    "questions": [{"text": "Which database?", "options": ["PostgreSQL", "SQLite"]}],
    "itemId": "item-012"
  }
}
```

**Response mapping (for reference):**
- `allow(updatedInput: {answers: {...}})` → JSON-RPC response: `{answers: {...}}`
- `deny()` → `{answers: {}}`

Current (lines 134-135):
```dart
case 'item/tool/requestUserInput':
  _emitAskUserQuestion(request, params);
```

**Add after `_emitAskUserQuestion(...):`**

```dart
  _eventsController.add(PermissionRequestEvent(
    id: _nextEventId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.codex,
    raw: params,
    sessionId: threadId,
    requestId: request.id.toString(),
    toolName: 'AskUserQuestion',
    toolKind: ToolKind.ask,
    toolInput: {
      'questions': params['questions'] ?? const [],
    },
    toolUseId: params['itemId'] as String?,
  ));
```

**Mapping:**

| JSON path | → Event field |
|-----------|---------------|
| `request.id` | `requestId` |
| `"AskUserQuestion"` | `toolName` |
| `ToolKind.ask` | `toolKind` |
| `{questions}` | `toolInput` |
| `params.itemId` | `toolUseId` |

---

## Summary of All Changes

| # | Location | Change | Lines (approx) |
|---|----------|--------|----------------|
| 1 | — | No new imports needed | 0 |
| 2 | After `_effortOverride` | Add `_eventIdCounter` + `_nextEventId()` | 6 |
| 3 | After `_nextEventId()` | Add `_codexToolKind()` + `_mcpToolName()` | 18 |
| 4 | After `_mcpToolName()` | Add `_extractCodexLocations()` | 16 |
| 5 | `_handleThreadStarted` | Add `SessionInitEvent` emission | 10 |
| 6 | `_handleTurnStarted` | No change needed | 0 |
| 7 | `_handleTokenUsageUpdated` | No change needed | 0 |
| 8a | `_handleItemStarted` (commandExecution) | Add `ToolInvocationEvent` emission | 14 |
| 8b | `_handleItemStarted` (fileChange) | Add `ToolInvocationEvent` emission | 15 |
| 8c | `_handleItemStarted` (mcpToolCall) | Add `ToolInvocationEvent` emission | 14 |
| 9a | `_handleItemCompleted` (agentMessage) | Add `TextEvent` emission | 9 |
| 9b | `_handleItemCompleted` (reasoning) | Add `TextEvent` emission | 10 |
| 9c | `_handleItemCompleted` (plan) | Add `TextEvent` emission | 9 |
| 9d | `_handleItemCompleted` (commandExecution) | Add `ToolCompletionEvent` emission | 14 |
| 9e | `_handleItemCompleted` (fileChange) | Add `ToolCompletionEvent` emission | 14 |
| 9f | `_handleItemCompleted` (mcpToolCall) | Add `ToolCompletionEvent` emission | 11 |
| 10 | `_handleTurnCompleted` | Add `TurnCompleteEvent` emission | 14 |
| 11a | `_handleServerRequest` (commandExecution approval) | Add `PermissionRequestEvent` emission | 16 |
| 11b | `_handleServerRequest` (fileChange approval) | Add `PermissionRequestEvent` emission | 15 |
| 11c | `_handleServerRequest` (userInput) | Add `PermissionRequestEvent` emission | 13 |

**Total new code:** ~200 lines
**Modified existing code:** 0 lines (all additions, no existing lines changed)

---

## Events NOT Emitted by Codex

These InsightsEvent types are **never** emitted by Codex (null/empty in all cases):

| Event Type | Reason |
|------------|--------|
| `SessionStatusEvent` | Codex doesn't send session status notifications |
| `UserInputEvent` | User input is handled by the frontend, not echoed back |
| `ContextCompactionEvent` | Codex doesn't perform context compaction |
| `SubagentSpawnEvent` | Codex doesn't support subagents |
| `SubagentCompleteEvent` | Codex doesn't support subagents |
| `StreamDeltaEvent` | Codex sends completed items, not streaming deltas |

---

## What Codex Doesn't Provide (Frontend Impact)

These fields are always null in Codex InsightsEvents. The frontend should hide or gracefully degrade the corresponding UI elements:

| Feature | Status | Frontend Behavior |
|---------|--------|-------------------|
| Cost tracking | Not available | Cost badge hidden |
| Duration metrics | Not available | Duration hidden |
| Per-model usage | Not available | Model breakdown hidden |
| Context window size | Not available | Context meter hidden |
| Permission suggestions | Not available | No auto-approve suggestions shown |
| Permission denials | Not reported | Turn summary omits denials |
| Subagent routing | No `parentToolUseId` | All output in primary conversation |
| Streaming deltas | Not supported | No typing effect; content appears on completion |
| MCP server status | Not reported | MCP panel hidden |
| Available tools list | Not reported | Tool palette hidden |
| Slash commands | Not available | Command palette hidden |
| Account info | Not available | Account badge hidden |
| Compaction events | Not available | No compaction indicators |
| File read events | Not reported | Read operations invisible |
| Search events | Not reported | Search operations invisible |

---

## Codex-Specific Extensions Data

Data unique to Codex, preserved via the `extensions` map on InsightsEvents:

| Data | Where It Goes | Why It Matters |
|------|--------------|----------------|
| `item.type` (original) | `extensions['codex.itemType']` | Preserves native vocabulary for debugging/display |
| `commandActions` | `extensions['codex.commandActions']` | Richer approval options (allow/deny/cancel) |
| `grantRoot` | `extensions['codex.grantRoot']` | Directory-level file change approval |
| Multi-file changes | `ToolInvocationEvent.input` and `.locations` | Full change set preserved (not flattened) |

**Not yet used but available for future extension:**

| Data | Potential Location | Notes |
|------|-------------------|-------|
| `turnId` | `extensions['codex.turnId']` | Needed for interrupt support — not emitted in this task since `_currentTurnId` is already tracked internally |
| `effortLevel` | `extensions['codex.effortLevel']` | Codex supports reasoning effort — could be added to `SessionInitEvent` if needed |

---

## Process Architecture Context

Unlike Claude CLI (one process per session), Codex uses a **single shared `CodexProcess`** for all sessions. This means:

- The `CodexProcess` is created once when the backend starts
- Sessions are `thread/start` requests on the same process
- All notifications are multiplexed; each must be filtered by `threadId`
- The process lifecycle is tied to the backend, not individual sessions

**Implication for event emission:** Every handler method in `CodexSession` already validates `threadId` before processing (`if (id != threadId) return;`). This ensures events are only emitted for the correct session despite all sessions sharing one process.

---

## Edge Cases

1. **Missing fields:** All field access uses null-aware operators (`as String?`) with `?? defaultValue` fallbacks. No `!` operators.

2. **Empty item object:** The `if (item == null) return;` guard in `_handleItemStarted` and `_handleItemCompleted` protects against this. No event emitted.

3. **Unknown item types:** The `default: break` in the switch silently ignores unknown types. No event emitted. No error.

4. **MCP tool with missing server/tool:** `_mcpToolName()` falls back to `'McpTool'` if either field is empty.

5. **Zero cached tokens:** `cacheReadTokens` set to null if `cachedInput == 0` (rather than reporting 0, which would be misleading — it means "we have no data" not "zero cache hits").

6. **Thread ID mismatch:** Each handler validates `threadId` before processing. Mismatched notifications are silently ignored (no event emitted).

7. **Disposed session:** The `if (_disposed) return;` guard at the top of `_handleNotification` and `_handleServerRequest` prevents event emission after disposal.

8. **Extensions with null values:** The `if (params['commandActions'] != null)` guards prevent null values from appearing in the extensions map.

---

## Testing Strategy (for Task 3c)

Tests should use `CodexSession.forTesting(threadId: 'test-thread')` and manually invoke the handler methods to emit events.

**Problem:** The handler methods (`_handleNotification`, `_handleServerRequest`) are private. The test session constructor doesn't set up streams.

**Solution:** Add a `@visibleForTesting` method to emit test events, mirroring the pattern used in `CliSession`:

```dart
/// Injects a notification for testing purposes.
@visibleForTesting
void injectNotification(JsonRpcNotification notification) {
  _handleNotification(notification);
}

/// Injects a server request for testing purposes.
@visibleForTesting
void injectServerRequest(JsonRpcServerRequest request) {
  _handleServerRequest(request);
}
```

**Test cases to cover:**

| Test | Input | Expected Events |
|------|-------|-----------------|
| Thread started | `thread/started` with `{thread: {id: 'test-thread', model: 'o4-mini'}}` | 1 × `SessionInitEvent(model: 'o4-mini')` |
| Command execution started | `item/started` with `commandExecution` item | 1 × `ToolInvocationEvent(kind: execute, toolName: 'Bash')` |
| File change started | `item/started` with `fileChange` item + 2 paths | 1 × `ToolInvocationEvent(kind: edit, locations: [path1, path2])` |
| MCP tool started | `item/started` with `mcpToolCall` item | 1 × `ToolInvocationEvent(kind: mcp, toolName: 'mcp__server__tool')` |
| Agent message completed | `item/completed` with `agentMessage` item | 1 × `TextEvent(kind: text)` |
| Reasoning completed | `item/completed` with `reasoning` item | 1 × `TextEvent(kind: thinking)` |
| Plan completed | `item/completed` with `plan` item | 1 × `TextEvent(kind: plan)` |
| Command completed (success) | `item/completed` with `exitCode: 0` | 1 × `ToolCompletionEvent(status: completed, isError: false)` |
| Command completed (failure) | `item/completed` with `exitCode: 1` | 1 × `ToolCompletionEvent(status: failed, isError: true)` |
| File change completed | `item/completed` with `fileChange` item | 1 × `ToolCompletionEvent` with `locations` |
| File change failed | `item/completed` with `status: 'failed'` | 1 × `ToolCompletionEvent(isError: true)` |
| MCP tool completed | `item/completed` with `mcpToolCall` result | 1 × `ToolCompletionEvent(isError: false)` |
| MCP tool error | `item/completed` with `mcpToolCall` error | 1 × `ToolCompletionEvent(isError: true)` |
| Turn completed with usage | `turn/completed` after `tokenUsage/updated` | 1 × `TurnCompleteEvent` with `usage.inputTokens` etc. |
| Turn completed without usage | `turn/completed` with no prior `tokenUsage/updated` | 1 × `TurnCompleteEvent(usage: TokenUsage(0, 0))` |
| Command approval request | `item/commandExecution/requestApproval` | 1 × `PermissionRequestEvent(toolName: 'Bash', toolKind: execute)` |
| File change approval | `item/fileChange/requestApproval` | 1 × `PermissionRequestEvent(toolName: 'Write', toolKind: edit)` |
| User input request | `item/tool/requestUserInput` | 1 × `PermissionRequestEvent(toolName: 'AskUserQuestion', toolKind: ask)` |
| Thread ID mismatch | Any notification with wrong `threadId` | 0 events |
| Empty reasoning | `reasoning` with empty summary and content | 0 events (guarded by `thinking.isNotEmpty`) |
| Extensions preserved | Command approval with `commandActions` | Event has `extensions['codex.commandActions']` |
| Event IDs are unique | Emit 3 events | All 3 have different `id` values |

---

## End of Specification
