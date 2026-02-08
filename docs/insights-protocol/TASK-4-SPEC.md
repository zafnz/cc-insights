# Task 4: EventHandler — Replace SdkMessageHandler with InsightsEvent Consumption

**Phase 2 of the migration plan (see `10-migration.md` §2.1–2.3).**

This spec covers Tasks 4b–4e: building `EventHandler` to consume typed `InsightsEvent` objects instead of raw JSON dictionaries. The EventHandler will eventually replace `SdkMessageHandler` (1133 lines).

---

## Overview

### Current Data Flow (SdkMessageHandler)

```
CliSession._handleMessage(json)
  → SDKMessage.fromJson(json)       ← typed object created
  → emit on messages stream
  → ChatState._messageSubscription
    → msg.rawJson ?? {}              ← typed object discarded!
    → SdkMessageHandler.handleMessage(chat, rawJson)
      → switch on rawJson['type'] string
      → creates OutputEntry objects
```

### New Data Flow (EventHandler)

```
CliSession._handleMessage(json)
  → InsightsEvent (typed, sealed class)
  → emit on events stream
  → ChatState._eventSubscription
    → EventHandler.handleEvent(chat, event)
      → sealed class switch (exhaustive)
      → creates OutputEntry objects
```

---

## Method Mapping: SdkMessageHandler → EventHandler

| SdkMessageHandler Method | InsightsEvent Type | EventHandler Method |
|---|---|---|
| `handleMessage` (switch on `type` string) | sealed `InsightsEvent` | `handleEvent` (sealed class switch) |
| `_handleSystemMessage` → `init` | `SessionInitEvent` | `_handleSessionInit` |
| `_handleSystemMessage` → `status` | `SessionStatusEvent` | `_handleSessionStatus` |
| `_handleSystemMessage` → `compact_boundary` | `ContextCompactionEvent` | `_handleCompaction` |
| `_handleSystemMessage` → `context_cleared` | `ContextCompactionEvent` (trigger=cleared) | `_handleCompaction` |
| `_handleAssistantMessage` → `text` block | `TextEvent` (kind=text) | `_handleText` |
| `_handleAssistantMessage` → `thinking` block | `TextEvent` (kind=thinking) | `_handleText` |
| `_handleAssistantMessage` → `tool_use` block | `ToolInvocationEvent` | `_handleToolInvocation` |
| `_handleUserMessage` → `tool_result` | `ToolCompletionEvent` | `_handleToolCompletion` |
| `_handleUserMessage` → context summary | `UserInputEvent` (isSynthetic=true) | `_handleUserInput` |
| `_handleUserMessage` → local cmd output | `UserInputEvent` (extensions.isReplay=true) | `_handleUserInput` |
| `_handleResultMessage` (main) | `TurnCompleteEvent` (no parentCallId) | `_handleTurnComplete` |
| `_handleResultMessage` (subagent) | `TurnCompleteEvent` (has parentCallId) | `_handleTurnComplete` |
| `_handleTaskToolSpawn` | `SubagentSpawnEvent` | `_handleSubagentSpawn` |
| `_handleTaskToolResult` | `SubagentCompleteEvent` | `_handleSubagentComplete` |
| `_handleStreamEvent` | `StreamDeltaEvent` | `_handleStreamDelta` |
| `_handleUnknownMessage` | default branch | `_handleUnknown` |
| `_finalizeStreamingEntries` | (internal) | `_finalizeStreamingEntries` |
| `generateChatTitle` | N/A | `generateChatTitle` (copied as-is) |
| `clearStreamingState` | N/A | `clearStreamingState` (copied as-is) |
| `clear` / `dispose` | N/A | `clear` / `dispose` (copied as-is) |

---

## State Maps

| State Map | SdkMessageHandler Name | EventHandler Name | Changes? |
|---|---|---|---|
| Tool pairing: toolUseId → entry | `_toolUseIdToEntry` | `_toolCallIndex` | Rename only |
| Agent routing: parentToolUseId → convId | `_agentIdToConversationId` | `_agentIdToConversationId` | Unchanged |
| Resume routing: new toolUseId → agentId | `_toolUseIdToAgentId` | `_toolUseIdToAgentId` | Unchanged |
| Assistant output tracker | `_hasAssistantOutputThisTurn` | `_hasAssistantOutputThisTurn` | Unchanged |
| Post-compaction flag | `_expectingContextSummary` | `_expectingContextSummary` | Unchanged |
| Title gen service/sets | `_askAiService`, `_pendingTitleGenerations`, `_titlesGenerated` | Same | Unchanged |
| Streaming blocks | `_streamingBlocks` | `_streamingBlocks` | Unchanged |
| Streaming context | `_streamingConversationId`, `_streamingChat` | Same | Unchanged |
| Active streaming entries | `_activeStreamingEntries` | `_activeStreamingEntries` | Unchanged |
| Throttle timer | `_notifyTimer`, `_hasPendingNotify` | Same | Unchanged |

---

## Key Design Decisions

1. **`_resolveConversationId`** renames parameter from `parentToolUseId` to `parentCallId` to match InsightsEvent field names. Logic is identical.

2. **Context usage tracking**: `SdkMessageHandler` calls `chat.updateContextFromUsage(usage)` from the assistant message's `usage` field. `TextEvent` doesn't carry usage data. This moves to `_handleTurnComplete` which has `TurnCompleteEvent.usage`.

3. **Streaming finalization**: In SdkMessageHandler, `_handleAssistantMessage` checks for `_activeStreamingEntries` and finalizes them. In EventHandler, `_handleText` and `_handleToolInvocation` perform the same check — when a non-streaming event arrives and there are active streaming entries for that conversation, finalize the first matching entry.

4. **`context_cleared`**: Uses `ContextCompactionEvent` with `trigger: CompactionTrigger.cleared`.

5. **`UserInputEvent` replay detection**: Check `event.extensions?['isReplay']` for local command output.

6. **`TurnCompleteEvent` parent detection**: Check `event.extensions?['parent_tool_use_id']` to distinguish main agent vs subagent results.

---

## Dependency Graph

```
4b (skeleton + tool events)
 ├── 4c (text, user input, lifecycle, compaction, turn complete)
 ├── 4d (streaming delta handling)
 └── 4e (subagent routing + title generation)
```

4c, 4d, and 4e are independent of each other — all depend only on 4b. Run them sequentially to avoid merge conflicts in the same file.

---

## Brief 4b: Core Skeleton + Tool Events

**File to create:** `frontend/lib/services/event_handler.dart`
**Test file to create:** `frontend/test/services/event_handler_test.dart`

### What to Build

1. **Class skeleton** with all state maps and constructor:

```dart
import 'dart:async';
import 'dart:developer' as developer;

import 'package:agent_sdk_core/agent_sdk_core.dart' show BackendProvider, InsightsEvent, ToolInvocationEvent, ToolCompletionEvent, TextEvent, UserInputEvent, TurnCompleteEvent, SessionInitEvent, SessionStatusEvent, ContextCompactionEvent, SubagentSpawnEvent, SubagentCompleteEvent, StreamDeltaEvent, PermissionRequestEvent, ToolKind, TextKind, ToolCallStatus, SessionStatus, CompactionTrigger, StreamDeltaKind, TokenUsage, ModelTokenUsage;
import 'package:flutter/foundation.dart';

import '../models/agent.dart';
import '../models/chat.dart';
import '../models/output_entry.dart';
import 'ask_ai_service.dart';
import 'log_service.dart';
import 'runtime_config.dart';
```

State maps (copy all from SdkMessageHandler, rename `_toolUseIdToEntry` → `_toolCallIndex`).

2. **`handleEvent(ChatState chat, InsightsEvent event)`** — sealed class switch:

```dart
void handleEvent(ChatState chat, InsightsEvent event) {
  switch (event) {
    case ToolInvocationEvent e:    _handleToolInvocation(chat, e);
    case ToolCompletionEvent e:    _handleToolCompletion(chat, e);
    case TextEvent e:              _handleText(chat, e);
    case UserInputEvent e:         _handleUserInput(chat, e);
    case TurnCompleteEvent e:      _handleTurnComplete(chat, e);
    case SessionInitEvent e:       _handleSessionInit(chat, e);
    case SessionStatusEvent e:     _handleSessionStatus(chat, e);
    case ContextCompactionEvent e: _handleCompaction(chat, e);
    case SubagentSpawnEvent e:     _handleSubagentSpawn(chat, e);
    case SubagentCompleteEvent e:  _handleSubagentComplete(chat, e);
    case StreamDeltaEvent e:       _handleStreamDelta(chat, e);
    case PermissionRequestEvent _: break; // Handled via permission stream
  }
}
```

3. **`_resolveConversationId(ChatState chat, String? parentCallId)`** — identical logic to SdkMessageHandler's `_resolveConversationId`, just renames the parameter.

4. **`_handleToolInvocation(ChatState chat, ToolInvocationEvent event)`**:
   - Resolve conversation via `_resolveConversationId(chat, event.parentCallId)`.
   - Create `ToolUseOutputEntry(toolName: event.toolName, toolKind: event.kind, provider: event.provider, toolUseId: event.callId, toolInput: Map.from(event.input), model: event.model)`.
   - Add raw: `entry.addRawMessage(event.raw ?? {})`.
   - Register: `_toolCallIndex[event.callId] = entry`.
   - Add to conversation: `chat.addOutputEntry(conversationId, entry)`.
   - **Do NOT handle SubagentSpawnEvent here** — that's a separate event type in 4e.

5. **`_handleToolCompletion(ChatState chat, ToolCompletionEvent event)`**:
   - Look up `_toolCallIndex[event.callId]`.
   - If found: `entry.updateResult(event.output, event.isError)`, `entry.addRawMessage(event.raw ?? {})`, `chat.persistToolResult(event.callId, event.output, event.isError)`, `chat.notifyListeners()`.
   - **Do NOT handle SubagentCompleteEvent here** — that's in 4e.
   - Clear pending permission: `chat.removePendingPermissionByToolUseId(event.callId)`.

6. **`_formatTokens(int tokens)`** — copied from SdkMessageHandler.

7. **`clear()` and `dispose()`** — clear all state maps and timers.

8. **Stub methods** for 4c/4d/4e — empty private methods that will be filled in later:
   - `_handleText`, `_handleUserInput`, `_handleTurnComplete`
   - `_handleSessionInit`, `_handleSessionStatus`, `_handleCompaction`
   - `_handleSubagentSpawn`, `_handleSubagentComplete`
   - `_handleStreamDelta`

### Tests to Write

Use a `ChatState` test instance (same pattern as `sdk_message_handler_test.dart`). Create test events using the InsightsEvent constructors directly.

- `_handleToolInvocation` creates `ToolUseOutputEntry` with correct fields (toolName, toolKind, provider, callId, input, model).
- `_handleToolInvocation` routes to correct conversation via parentCallId.
- `_handleToolCompletion` pairs result with invocation entry.
- `_handleToolCompletion` handles error results (`isError: true`).
- `_handleToolCompletion` ignores unknown callId gracefully.
- `_handleToolCompletion` clears pending permission by toolUseId.
- `_handleToolCompletion` persists tool result.
- `clear()` resets all state maps.
- `handleEvent` dispatches to correct handler (verify with tool events).

### Key Reference Files

- **Source logic:** `frontend/lib/services/sdk_message_handler.dart` — lines 27-133 (state maps, constructor, handleMessage, resolveConversationId), lines 271-311 (tool_use handling in _handleAssistantMessage), lines 495-541 (tool_result handling in _handleUserMessage)
- **Event types:** `agent_sdk_core/lib/src/types/insights_events.dart`
- **Output entries:** `frontend/lib/models/output_entry.dart` — `ToolUseOutputEntry` constructor
- **Chat methods:** `frontend/lib/models/chat.dart` — `addOutputEntry`, `persistToolResult`, `removePendingPermissionByToolUseId`, `notifyListeners`
- **Test patterns:** `frontend/test/services/sdk_message_handler_test.dart` — test setup, ChatState creation

---

## Brief 4c: Text, User Input, Session Lifecycle, Compaction, Turn Complete

**File to modify:** `frontend/lib/services/event_handler.dart` (from 4b)
**Test file to modify:** `frontend/test/services/event_handler_test.dart` (from 4b)

**Dependency:** 4b must be complete.

### What to Build

Fill in the stub methods from 4b:

1. **`_handleText(ChatState chat, TextEvent event)`**:
   - Resolve conversation via `_resolveConversationId(chat, event.parentCallId)`.
   - Check for streaming entries to finalize: `final streamingEntries = _activeStreamingEntries.remove(conversationId)`. If present and non-empty, finalize the first matching text entry (set `entry.text = event.text`, `entry.isStreaming = false`, `entry.addRawMessage(event.raw ?? {})`, `chat.persistStreamingEntry(entry)`). Then call `chat.notifyListeners()` and return.
   - Non-streaming path: create `TextOutputEntry(text: event.text, contentType: event.kind == TextKind.thinking ? 'thinking' : 'text', errorType: event.kind == TextKind.error ? 'error' : null)`.
   - Add raw message, add to conversation.
   - Mark `_hasAssistantOutputThisTurn[chat.data.id] = true` when `event.parentCallId == null`.

2. **`_handleUserInput(ChatState chat, UserInputEvent event)`**:
   - If `event.isSynthetic` OR `_expectingContextSummary[chat.data.id] == true`: reset flag, create `ContextSummaryEntry(summary: event.text)` if text is non-empty, return.
   - Check for local command replay: `final isReplay = event.extensions?['isReplay'] == true`. If so, extract text from `<local-command-stdout>` tags using regex, create `SystemNotificationEntry`, return.
   - Otherwise: no-op (user input entries are added by `ChatState.sendMessage`).

3. **`_handleSessionInit(ChatState chat, SessionInitEvent event)`**:
   - No-op (matches current SdkMessageHandler behavior for `system:init`).

4. **`_handleSessionStatus(ChatState chat, SessionStatusEvent event)`**:
   - `event.status == SessionStatus.compacting` → `chat.setCompacting(true)`.
   - Else → `chat.setCompacting(false)`.
   - Check `event.extensions?['permissionMode']` for permission mode sync → `chat.setPermissionMode(PermissionMode.fromApiName(mode))`.

5. **`_handleCompaction(ChatState chat, ContextCompactionEvent event)`**:
   - If `event.trigger == CompactionTrigger.cleared`: `chat.addEntry(ContextClearedEntry(...))`, `chat.resetContext()`, return.
   - Create `AutoCompactionEntry` with message from `_formatTokens(event.preTokens)` if available, `isManual: event.trigger == CompactionTrigger.manual`.
   - If `event.summary != null`: create `ContextSummaryEntry(summary: event.summary!)` immediately.
   - If `event.summary == null`: set `_expectingContextSummary[chat.data.id] = true`.

6. **`_handleTurnComplete(ChatState chat, TurnCompleteEvent event)`**:
   - Determine if main agent or subagent: `final parentCallId = event.extensions?['parent_tool_use_id'] as String?`.
   - Extract usage: convert `event.usage` (TokenUsage) → `UsageInfo` for chat. Convert `event.modelUsage` (Map<String, ModelTokenUsage>) → `List<ModelUsageInfo>` for chat.
   - If main agent (`parentCallId == null`):
     - `chat.updateCumulativeUsage(usage: usageInfo, totalCostUsd: event.costUsd ?? 0.0, modelUsage: modelUsageList, contextWindow: contextWindow)`.
     - `chat.setWorking(false)`.
     - Handle no-output result: if `!(_hasAssistantOutputThisTurn[chatId] ?? false)` and `event.result` is non-empty, create `SystemNotificationEntry`.
     - Reset: `_hasAssistantOutputThisTurn[chatId] = false`.
   - If subagent:
     - Determine `AgentStatus` from `event.subtype` (same logic as SdkMessageHandler's `_handleResultMessage`).
     - `chat.updateAgent(status, parentCallId)`.

7. **`_finalizeStreamingEntries`** — adapt from SdkMessageHandler. Key change: instead of iterating a `content` list of blocks, this is called per-event. When `_handleText` is called and streaming entries exist, finalize the first matching text entry. When `_handleToolInvocation` is called (in 4b's method) and streaming entries exist, finalize the first matching tool entry. **Add the finalization check to `_handleToolInvocation` as well** (update the 4b method to check `_activeStreamingEntries` before creating a new entry).

### Tests to Write

- `_handleText` creates `TextOutputEntry` with `contentType: 'text'`.
- `_handleText` creates thinking entry with `contentType: 'thinking'`.
- `_handleText` creates error entry with `errorType: 'error'`.
- `_handleText` marks assistant output for main agent only (parentCallId null).
- `_handleText` does NOT mark assistant output for subagent (parentCallId set).
- `_handleText` finalizes streaming entries when present.
- `_handleText` creates normally when no streaming entries.
- `_handleUserInput` creates `ContextSummaryEntry` for synthetic messages.
- `_handleUserInput` creates `SystemNotificationEntry` for local command replay.
- `_handleUserInput` creates `ContextSummaryEntry` when `_expectingContextSummary` flag is set.
- `_handleUserInput` resets `_expectingContextSummary` flag after handling.
- `_handleSessionStatus` sets compacting to true.
- `_handleSessionStatus` sets compacting to false.
- `_handleSessionStatus` syncs permission mode from extensions.
- `_handleCompaction` creates `AutoCompactionEntry` with token message.
- `_handleCompaction` creates `AutoCompactionEntry` with manual flag.
- `_handleCompaction` with `CompactionTrigger.cleared` creates `ContextClearedEntry`.
- `_handleCompaction` sets `_expectingContextSummary` when no summary provided.
- `_handleCompaction` creates `ContextSummaryEntry` when summary is provided.
- `_handleTurnComplete` updates cumulative usage for main agent.
- `_handleTurnComplete` sets working to false for main agent.
- `_handleTurnComplete` updates agent status for subagent (completed).
- `_handleTurnComplete` updates agent status for subagent (error subtypes).
- `_handleTurnComplete` creates `SystemNotificationEntry` when no assistant output and result present.
- `_handleTurnComplete` does not create notification when result is null/empty.
- `_handleTurnComplete` resets `_hasAssistantOutputThisTurn` flag.

### Key Reference Files

- **Source logic:** `sdk_message_handler.dart` — lines 134-200 (system messages), lines 210-419 (assistant messages + finalization), lines 421-541 (user messages), lines 702-792 (result messages)
- **Event types:** `insights_events.dart` — `TextEvent`, `TextKind`, `UserInputEvent`, `SessionInitEvent`, `SessionStatusEvent`, `SessionStatus`, `ContextCompactionEvent`, `CompactionTrigger`, `TurnCompleteEvent`, `TokenUsage`, `ModelTokenUsage`
- **Output entries:** `output_entry.dart` — `TextOutputEntry`, `AutoCompactionEntry`, `ContextSummaryEntry`, `ContextClearedEntry`, `SystemNotificationEntry`, `UnknownMessageEntry`
- **Chat methods:** `chat.dart` — `setCompacting`, `resetContext`, `setWorking`, `updateCumulativeUsage`, `updateAgent`, `setPermissionMode`, `PermissionMode`, `persistStreamingEntry`

---

## Brief 4d: Streaming Delta Handling

**File to modify:** `frontend/lib/services/event_handler.dart` (from 4b)
**Test file to modify:** `frontend/test/services/event_handler_test.dart` (from 4b)

**Dependency:** 4b must be complete.

### What to Build

Fill in `_handleStreamDelta` and its supporting methods:

1. **`_handleStreamDelta(ChatState chat, StreamDeltaEvent event)`** — switch on `event.kind`:

```dart
void _handleStreamDelta(ChatState chat, StreamDeltaEvent event) {
  switch (event.kind) {
    case StreamDeltaKind.messageStart:
      _onMessageStart(chat, event.parentCallId);
    case StreamDeltaKind.blockStart:
      _onContentBlockStart(chat, event.blockIndex ?? 0, event);
    case StreamDeltaKind.text:
      _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
    case StreamDeltaKind.thinking:
      _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
    case StreamDeltaKind.toolInput:
      _onContentBlockDelta(chat, event.blockIndex ?? 0, event);
    case StreamDeltaKind.blockStop:
      _onContentBlockStop(event.blockIndex ?? 0);
    case StreamDeltaKind.messageStop:
      _onMessageStop(chat);
  }
}
```

2. **`_onMessageStart(ChatState chat, String? parentCallId)`** — same as SdkMessageHandler:
   - Set `_streamingConversationId = _resolveConversationId(chat, parentCallId)`.
   - Set `_streamingChat = chat`.
   - Clear `_streamingBlocks`.

3. **`_onContentBlockStart(ChatState chat, int index, StreamDeltaEvent event)`**:
   - Get `convId` from `_streamingConversationId`. Return if null.
   - Determine block type from event fields:
     - If `event.callId != null`: tool_use block → create `ToolUseOutputEntry(toolName: event.extensions?['tool_name'] ?? '', toolKind: ToolKind.fromToolName(event.extensions?['tool_name'] ?? ''), provider: event.provider, toolUseId: event.callId!, toolInput: {}, isStreaming: true)`. Register in `_toolCallIndex`.
     - If `event.extensions?['block_type'] == 'thinking'`: thinking block → create `TextOutputEntry(text: '', contentType: 'thinking', isStreaming: true)`.
     - Else: text block → create `TextOutputEntry(text: '', contentType: 'text', isStreaming: true)`.
   - Store in `_streamingBlocks[(convId, index)]`.
   - Add to conversation: `chat.addOutputEntry(convId, entry)`.
   - Track: `_activeStreamingEntries.putIfAbsent(convId, () => []).add(entry)`.

4. **`_onContentBlockDelta(ChatState chat, int index, StreamDeltaEvent event)`**:
   - Get entry from `_streamingBlocks[(_streamingConversationId, index)]`. Return if null.
   - Switch on `event.kind`:
     - `text` / `thinking`: if entry is `TextOutputEntry`, call `entry.appendDelta(event.textDelta ?? '')`.
     - `toolInput`: if entry is `ToolUseOutputEntry`, call `entry.appendInputDelta(event.jsonDelta ?? '')`.
   - Call `_scheduleNotify()`.

5. **`_onContentBlockStop(int index)`** — same as SdkMessageHandler.

6. **`_onMessageStop(ChatState chat)`** — same as SdkMessageHandler.

7. **`_scheduleNotify()`** — copied exactly from SdkMessageHandler.

8. **`clearStreamingState()`** — copied exactly from SdkMessageHandler.

### Tests to Write

- `blockStart` creates streaming `TextOutputEntry` for text block.
- `blockStart` creates streaming `TextOutputEntry` for thinking block.
- `blockStart` creates streaming `ToolUseOutputEntry` for tool block (with callId).
- `blockStart` registers tool entry in `_toolCallIndex`.
- `text` delta appends text to `TextOutputEntry`.
- `thinking` delta appends text to thinking `TextOutputEntry`.
- `toolInput` delta accumulates on `ToolUseOutputEntry`.
- `blockStop` marks entry as `isStreaming = false`.
- `messageStop` cancels timer and clears streaming state.
- `messageStart` sets streaming conversation context.
- Multiple blocks create separate entries at different indices.
- Subagent streaming routes to correct conversation via `parentCallId`.
- `clearStreamingState` finalizes in-flight entries and notifies.
- Deltas without prior `blockStart` are ignored (no crash).

### Key Reference Files

- **Source logic:** `sdk_message_handler.dart` — lines 794-963 (all streaming methods)
- **Event types:** `insights_events.dart` — `StreamDeltaEvent`, `StreamDeltaKind`
- **Output entries:** `output_entry.dart` — `TextOutputEntry.appendDelta`, `ToolUseOutputEntry.appendInputDelta`, `isStreaming` field

---

## Brief 4e: Subagent Routing + Title Generation

**File to modify:** `frontend/lib/services/event_handler.dart` (from 4b)
**Test file to modify:** `frontend/test/services/event_handler_test.dart` (from 4b)

**Dependency:** 4b must be complete.

### What to Build

1. **`_handleSubagentSpawn(ChatState chat, SubagentSpawnEvent event)`**:
   - If `event.isResume && event.resumeAgentId != null`:
     - Look up: `final existingAgent = chat.findAgentByResumeId(event.resumeAgentId!)`.
     - If found: `chat.updateAgent(AgentStatus.working, existingAgent.sdkAgentId)`, `_agentIdToConversationId[event.callId] = existingAgent.conversationId`, `_toolUseIdToAgentId[event.callId] = existingAgent.sdkAgentId`, return.
     - If not found: log warning, fall through to create new.
   - Create new: `chat.addSubagentConversation(event.callId, event.agentType, event.description)`.
   - Map routing: look up agent from `chat.activeAgents[event.callId]`, set `_agentIdToConversationId[event.callId] = agent.conversationId`.
   - Log agent creation (same logging as SdkMessageHandler).

2. **`_handleSubagentComplete(ChatState chat, SubagentCompleteEvent event)`**:
   - Look up correct agent ID: `final agentId = _toolUseIdToAgentId[event.callId] ?? event.callId`.
   - Determine `AgentStatus` from `event.status`:
     - `'completed'` → `AgentStatus.completed`
     - `'error'`, `'error_max_turns'`, `'error_tool'`, `'error_api'`, `'error_budget'` → `AgentStatus.error`
     - null / unknown → `AgentStatus.completed`
   - Call `chat.updateAgent(agentStatus, agentId, result: event.summary, resumeId: event.agentId)`.
   - Log completion.

3. **`generateChatTitle(ChatState chat, String userMessage)`** — copy verbatim from SdkMessageHandler (lines 1022-1106). This includes `_generateChatTitleAsync`.

### Tests to Write

- `_handleSubagentSpawn` creates subagent conversation with agentType and description.
- `_handleSubagentSpawn` maps callId to conversation for routing.
- `_handleSubagentSpawn` resumes existing agent (updates status, maps routing).
- `_handleSubagentSpawn` falls through to create when resumeAgentId not found.
- `_handleSubagentSpawn` handles missing agentType/description gracefully.
- `_handleSubagentComplete` updates agent to `completed`.
- `_handleSubagentComplete` updates agent to `error` for error statuses.
- `_handleSubagentComplete` uses `_toolUseIdToAgentId` for resumed agents.
- `_handleSubagentComplete` defaults to `completed` for unknown status.
- Conversation routing: messages with parentCallId route to subagent conversation.
- Conversation routing: messages without parentCallId route to primary.
- Title generation generates title (copy test from `sdk_message_handler_test.dart`).
- Title generation is idempotent (doesn't generate twice for same chat).
- Title generation handles failure gracefully.
- Title generation is no-op without AskAiService.

### Key Reference Files

- **Source logic:** `sdk_message_handler.dart` — lines 543-700 (Task tool spawn + result), lines 1010-1106 (title generation)
- **Event types:** `insights_events.dart` — `SubagentSpawnEvent`, `SubagentCompleteEvent`
- **Agent model:** `frontend/lib/models/agent.dart` — `Agent`, `AgentStatus`
- **Chat methods:** `chat.dart` — `addSubagentConversation`, `updateAgent`, `findAgentByResumeId`, `activeAgents`, `rename`
- **AskAI service:** `frontend/lib/services/ask_ai_service.dart` — `AskAiService` interface, `SingleRequestResult`

---

## Testing Conventions

All tests should follow the patterns established in `frontend/test/services/sdk_message_handler_test.dart`:

- Create a `ChatState` for testing using `ChatState(ChatData.create(name: 'Test', worktreeRoot: '/test'))`.
- Create `InsightsEvent` instances directly using their constructors.
- Use a shared helper to create events with default boilerplate fields (id, timestamp, provider).
- Use `test/test_helpers.dart` for `safePumpAndSettle`, `TestResources`, etc. if needed.
- Run all tests via `./frontend/run-flutter-test.sh test/services/event_handler_test.dart`.

### Test Event Helper Pattern

```dart
// Helper to reduce boilerplate in test event creation
String _nextId() => 'evt-${_idCounter++}';
int _idCounter = 0;

ToolInvocationEvent makeToolInvocation({
  String? callId,
  String toolName = 'Bash',
  ToolKind kind = ToolKind.execute,
  Map<String, dynamic> input = const {},
  String? parentCallId,
  String? model,
  Map<String, dynamic>? raw,
}) {
  return ToolInvocationEvent(
    id: _nextId(),
    timestamp: DateTime.now(),
    provider: BackendProvider.claude,
    callId: callId ?? 'call-${_nextId()}',
    sessionId: 'test-session',
    kind: kind,
    toolName: toolName,
    input: input,
    parentCallId: parentCallId,
    model: model,
    raw: raw,
  );
}
// ... similar helpers for other event types
```

---

## End of Specification
