# Task 3c Summary: Codex Events Emission Tests

**Status:** ✅ Complete

## Overview

Implemented comprehensive tests for Codex → InsightsEvent conversion, verifying that `CodexSession` correctly emits InsightsEvents when processing Codex JSON-RPC notifications and server requests.

## Test File

- **Location:** `codex_dart_sdk/test/codex_session_events_test.dart`
- **Test Count:** 33 tests
- **Status:** All passing ✅

## Test Coverage

### 1. SessionInitEvent (2 tests)
- ✅ Emits `SessionInitEvent` on `thread/started` notification
- ✅ Ignores `thread/started` with wrong `threadId`

### 2. ToolInvocationEvent (6 tests)
- ✅ Emits for `commandExecution` started
- ✅ Emits for `fileChange` started with multiple paths
- ✅ Emits for `mcpToolCall` started with proper MCP naming (`mcp__server__tool`)
- ✅ Falls back to `McpTool` when server/tool names are missing
- ✅ Ignores `item/started` with wrong `threadId`
- ✅ Ignores `item/started` with unknown item type

### 3. TextEvent (5 tests)
- ✅ Emits for `agentMessage` completed
- ✅ Emits for `reasoning` completed (prefers summary over content)
- ✅ Emits for `reasoning` completed (falls back to content)
- ✅ Does NOT emit for empty reasoning
- ✅ Emits for `plan` completed

### 4. ToolCompletionEvent (6 tests)
- ✅ Emits for successful `commandExecution` (exit code 0)
- ✅ Emits for failed `commandExecution` (exit code != 0)
- ✅ Emits for successful `fileChange` with file paths
- ✅ Emits for failed `fileChange` (status == 'failed')
- ✅ Emits for successful `mcpToolCall`
- ✅ Emits for failed `mcpToolCall` (error present)

### 5. TurnCompleteEvent (3 tests)
- ✅ Emits with token usage (accumulated from prior `tokenUsage/updated`)
- ✅ Sets `cacheReadTokens` to null when `cachedInputTokens` is 0
- ✅ Emits with zero usage when no prior token update occurred

### 6. PermissionRequestEvent (4 tests)
- ✅ Emits for `commandExecution` approval request
- ✅ Emits for `fileChange` approval request
- ✅ Emits for user input request (`AskUserQuestion`)
- ✅ Ignores permission request with wrong `threadId`

### 7. Event ID Generation (1 test)
- ✅ Generates unique event IDs with `evt-codex-` prefix

### 8. Edge Cases (5 tests)
- ✅ Handles null item in `item/started`
- ✅ Handles null item in `item/completed`
- ✅ Handles missing fields gracefully (defaults to empty strings)
- ✅ Handles empty `fileChange` changes array
- ✅ Preserves raw params in all events

### 9. Complete Workflow (1 test)
- ✅ Emits correct sequence of events for a full turn:
  1. `SessionInitEvent` (thread started)
  2. `TextEvent` (agent message)
  3. `ToolInvocationEvent` (command started)
  4. `ToolCompletionEvent` (command completed)
  5. `TurnCompleteEvent` (turn finished with token usage)

## Key Implementation Details

### Test Setup
- Uses `CodexSession.forTesting(threadId: 'test-thread')` to create isolated test sessions
- Injects notifications via `session.injectNotification(JsonRpcNotification(...))`
- Injects server requests via `session.injectServerRequest(JsonRpcServerRequest(...))`
- Captures events via stream subscription to `session.events`
- Waits for async event processing with `waitForEvents()` helper

### Event Validation
Each test verifies:
1. **Correct event type** is emitted
2. **Provider** is `BackendProvider.codex`
3. **Session ID** matches test thread ID
4. **Event-specific fields** are correctly mapped from Codex JSON
5. **Extensions** preserve Codex-specific data (e.g., `codex.itemType`)
6. **Raw params** are preserved for debugging

### Codex-Specific Mappings Verified
- **ToolKind mapping:**
  - `commandExecution` → `ToolKind.execute` + `toolName: 'Bash'`
  - `fileChange` → `ToolKind.edit` + `toolName: 'FileChange'`
  - `mcpToolCall` → `ToolKind.mcp` + `toolName: 'mcp__<server>__<tool>'`

- **Text kinds:**
  - `agentMessage` → `TextKind.text`
  - `reasoning` → `TextKind.thinking`
  - `plan` → `TextKind.plan`

- **Tool statuses:**
  - `exitCode == 0` → `ToolCallStatus.completed`
  - `exitCode != 0` → `ToolCallStatus.failed`
  - `status == 'failed'` → `ToolCallStatus.failed`
  - `error != null` → `ToolCallStatus.failed`

- **File locations:**
  - `fileChange` events extract all paths from `changes[]` array into `locations`
  - Preserved in both `ToolInvocationEvent` and `ToolCompletionEvent`

## Alignment with Task 3a Spec

All test cases align with the implementation spec in `TASK-3A-SPEC.md`:

| Spec Section | Test Coverage | Status |
|--------------|---------------|--------|
| SessionInitEvent emission | SessionInitEvent group | ✅ |
| ToolInvocationEvent emission | ToolInvocationEvent group | ✅ |
| TextEvent emission | TextEvent group | ✅ |
| ToolCompletionEvent emission | ToolCompletionEvent group | ✅ |
| TurnCompleteEvent emission | TurnCompleteEvent group | ✅ |
| PermissionRequestEvent emission | PermissionRequestEvent group | ✅ |
| Event ID generation | Event ID generation group | ✅ |
| Edge case handling | Edge cases group | ✅ |
| Complete workflow | Complete workflow group | ✅ |

## Test Results

```
$ dart test codex_dart_sdk/test/codex_session_events_test.dart
00:00 +33: All tests passed!
```

All 33 tests pass successfully.

## Related Tasks

- **Task 3a:** Implementation spec (complete) → `TASK-3A-SPEC.md`
- **Task 3b:** Implementation (complete) → `codex_session.dart`
- **Task 3c:** Tests (complete, this document) → `codex_session_events_test.dart`

## Next Steps

With Task 3c complete, the Codex events emission is fully implemented and tested. The Codex backend now emits InsightsEvents that can be consumed by the frontend or any other client of the `CodexSession` API.
