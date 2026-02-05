# Frontend Consumption of InsightsEvent

This document describes how the frontend consumes `InsightsEvent` streams, including backend-aware UI rendering and the transition from the current raw-JSON approach.

## Current Architecture (The Problem)

```
AgentSession.messages: Stream<SDKMessage>
         ↓
ChatState: msg.rawJson ?? {}     ← typed object discarded
         ↓
SdkMessageHandler: switch(rawJson['type'])   ← string dispatch on raw JSON
         ↓
OutputEntry (ToolUseOutputEntry, TextOutputEntry, ...)
         ↓
ToolCard: switch(entry.toolName)   ← string dispatch on tool name
```

Problems:
1. `SDKMessage` typed objects are parsed then immediately thrown away
2. `SdkMessageHandler` re-parses everything from raw JSON
3. Every field access is a nullable cast from `dynamic`
4. Tool-specific rendering is keyed on string tool names
5. Adding a backend means producing identical Claude-format JSON

## New Architecture

```
AgentSession.events: Stream<InsightsEvent>
         ↓
EventHandler: switch(event) {     ← sealed class pattern match
  case ToolInvocationEvent e => ...
  case TextEvent e => ...
  case TurnCompleteEvent e => ...
}
         ↓
OutputEntry (unchanged persistence model)
         ↓
ToolCard: switch(entry.toolKind) {   ← enum pattern match
  case ToolKind.execute => ...
  case ToolKind.edit => ...
}
```

### Key Changes

| Before | After |
|--------|-------|
| `Stream<SDKMessage>` | `Stream<InsightsEvent>` |
| `msg.rawJson['type']` string dispatch | Sealed class `switch` with exhaustive matching |
| `msg['tool_use_result']` raw map access | `event.output` typed field |
| `toolName == "Bash"` string comparison | `toolKind == ToolKind.execute` enum comparison |
| No provider awareness | `event.provider` tells you which backend |

## EventHandler: Replacing SdkMessageHandler

The new `EventHandler` consumes `InsightsEvent` and produces `OutputEntry` objects for the conversation.

```dart
class EventHandler {
  void handleEvent(ChatState chat, InsightsEvent event) {
    switch (event) {
      case SessionInitEvent e:
        _handleSessionInit(chat, e);
      case TextEvent e:
        _handleText(chat, e);
      case ToolInvocationEvent e:
        _handleToolInvocation(chat, e);
      case ToolCompletionEvent e:
        _handleToolCompletion(chat, e);
      case SubagentSpawnEvent e:
        _handleSubagentSpawn(chat, e);
      case SubagentCompleteEvent e:
        _handleSubagentComplete(chat, e);
      case TurnCompleteEvent e:
        _handleTurnComplete(chat, e);
      case PermissionRequestEvent e:
        _handlePermission(chat, e);
      case StreamDeltaEvent e:
        _handleStreamDelta(chat, e);
      case ContextCompactionEvent e:
        _handleCompaction(chat, e);
      case SessionStatusEvent e:
        _handleStatus(chat, e);
      case UserInputEvent e:
        _handleUserInput(chat, e);
    }
    // Compiler error if a new event type is added and not handled ✓
  }
}
```

### Tool Invocation → ToolUseOutputEntry

```dart
void _handleToolInvocation(ChatState chat, ToolInvocationEvent event) {
  final conversationId = _resolveConversation(chat, event.parentCallId);

  final entry = ToolUseOutputEntry(
    timestamp: event.timestamp,
    toolName: event.toolName,
    toolKind: event.kind,         // NEW: enum, not derived from string
    toolUseId: event.callId,
    toolInput: event.input,
    model: event.model,
    locations: event.locations,
    provider: event.provider,     // NEW: which backend
  );

  _toolCallIndex[event.callId] = entry;
  chat.addEntry(conversationId, entry);

  // Subagent handling
  if (event is SubagentSpawnEvent) {
    _handleSubagentSpawn(chat, event);
  }
}
```

### Tool Completion → Update Existing Entry

```dart
void _handleToolCompletion(ChatState chat, ToolCompletionEvent event) {
  final entry = _toolCallIndex[event.callId];
  if (entry == null) return;

  entry.updateResult(event.output, event.isError);

  // Rich content (diffs, terminal blocks) available for rendering
  if (event.content != null) {
    entry.richContent = event.content;
  }

  chat.notifyListeners();
}
```

## ToolUseOutputEntry: Extended

The existing `ToolUseOutputEntry` gains a few fields:

```dart
class ToolUseOutputEntry extends OutputEntry {
  final String toolName;          // Existing: "Bash", "Edit", etc.
  final ToolKind toolKind;        // NEW: enum for dispatch
  final String toolUseId;
  final Map<String, dynamic> toolInput;
  final String? model;
  final List<String>? locations;  // NEW: affected file paths
  final BackendProvider provider; // NEW: which backend
  dynamic result;
  bool isError;
  List<ContentBlock>? richContent; // NEW: typed content (DiffBlock, TerminalBlock)

  // Existing fields unchanged
  bool isExpanded;
  bool isStreaming;
  List<Map<String, dynamic>> rawMessages;
}
```

## ToolCard: Backend-Aware Rendering

The frontend should absolutely have backend-specific UI. Not every tool card looks the same across backends, and that's fine.

### Dispatch by ToolKind (Primary)

```dart
Widget _buildToolContent(ToolUseOutputEntry entry) {
  return switch (entry.toolKind) {
    ToolKind.execute  => _ExecuteToolCard(entry: entry),
    ToolKind.read     => _ReadToolCard(entry: entry),
    ToolKind.edit     => _EditToolCard(entry: entry),
    ToolKind.search   => _SearchToolCard(entry: entry),
    ToolKind.fetch    => _FetchToolCard(entry: entry),
    ToolKind.browse   => _BrowseToolCard(entry: entry),
    ToolKind.think    => _SubagentToolCard(entry: entry),
    ToolKind.ask      => _AskUserToolCard(entry: entry),
    ToolKind.memory   => _MemoryToolCard(entry: entry),
    ToolKind.mcp      => _McpToolCard(entry: entry),
    ToolKind.delete   => _FileOpToolCard(entry: entry),
    ToolKind.move     => _FileOpToolCard(entry: entry),
    ToolKind.other    => _GenericToolCard(entry: entry),
  };
}
```

### Dispatch by Provider (Secondary, Within Tool Cards)

```dart
class _EditToolCard extends StatelessWidget {
  final ToolUseOutputEntry entry;

  @override
  Widget build(BuildContext context) {
    return switch (entry.provider) {
      BackendProvider.claude => _ClaudeEditCard(entry: entry),
      BackendProvider.codex  => _CodexEditCard(entry: entry),
      _                      => _GenericEditCard(entry: entry),
    };
  }
}
```

**Claude's Edit card** shows `old_string` / `new_string` with a DiffView widget.
**Codex's Edit card** shows the unified diff from `changes[].diff` with the same DiffView but sourced differently.
**Generic Edit card** shows whatever is in `input` as formatted JSON.

### Backend-Specific UI Components

These widgets only render for specific backends:

| Widget | Backend | Triggered By |
|--------|---------|-------------|
| **Cost Badge** | Claude | `TurnCompleteEvent.costUsd != null` |
| **Context Meter** | Claude | `ModelTokenUsage.contextWindow != null` |
| **Model Usage Breakdown** | Claude | `TurnCompleteEvent.modelUsage != null` |
| **Permission Suggestions** | Claude | `PermissionRequestEvent.suggestions != null` |
| **Account Badge** | Claude | `SessionInitEvent.account != null` |
| **MCP Server Status** | Claude | `SessionInitEvent.mcpServers != null` |
| **Slash Command Palette** | Claude | `SessionInitEvent.slashCommands != null` |
| **Reasoning Effort Selector** | Codex | `provider == BackendProvider.codex` |
| **ACP Mode Indicator** | ACP | `extensions['acp.mode'] != null` |

The pattern: **check if the data exists, not which backend it came from.** If a future Codex version adds cost tracking, the cost badge lights up automatically.

```dart
// Good: feature-detect
if (turnComplete.costUsd != null) {
  return CostBadge(cost: turnComplete.costUsd!);
}

// Bad: backend-detect
if (turnComplete.provider == BackendProvider.claude) {
  return CostBadge(cost: turnComplete.costUsd!);
}
```

Feature-detect where possible, backend-detect only when the semantics are genuinely different (e.g., Claude's Edit uses `old_string`/`new_string` vs Codex's unified diff).

## Conversation Routing

### Primary Conversation

All events with `parentCallId == null` go to the primary conversation. This is the default for Codex and ACP agents (no subagent support).

### Subagent Conversations

Events with `parentCallId != null` are routed to subagent conversations. Only Claude currently provides this.

```dart
String _resolveConversation(ChatState chat, String? parentCallId) {
  if (parentCallId == null) return chat.primaryConversationId;
  return _parentCallToConversation[parentCallId] ?? chat.primaryConversationId;
}
```

When a `SubagentSpawnEvent` arrives, a new conversation is created and the mapping is registered.

## Persistence

`OutputEntry` remains the persistence format (serialized to JSONL). The mapping is:

| InsightsEvent | OutputEntry |
|--------------|-------------|
| `TextEvent` | `TextOutputEntry` |
| `ToolInvocationEvent` | `ToolUseOutputEntry` |
| `ToolCompletionEvent` | `ToolResultEntry` (merged into `ToolUseOutputEntry`) |
| `UserInputEvent` | `UserInputEntry` |
| `ContextCompactionEvent` | `AutoCompactionEntry` / `ContextClearedEntry` |
| `SessionStatusEvent` | `SessionMarkerEntry` |
| `TurnCompleteEvent` | Updates `ConversationData.totalUsage` |

The `OutputEntry.toJson()` format is unchanged — old JSONL files remain readable.

## Migration Path

### Phase 1: Dual Emission

Both `SDKMessage` and `InsightsEvent` are emitted from sessions. The frontend still uses `SDKMessage` via `SdkMessageHandler`. New code can start consuming `InsightsEvent`.

### Phase 2: EventHandler Replaces SdkMessageHandler

The new `EventHandler` is wired up. `SdkMessageHandler` is deprecated. Both consume from the same session but the old handler is only used for any edge cases not yet ported.

### Phase 3: SDKMessage Removed

The `SDKMessage` hierarchy is removed from `agent_sdk_core`. Sessions only emit `InsightsEvent`. The Codex SDK no longer builds synthetic JSON.

See [10-migration.md](10-migration.md) for the detailed migration guide.
