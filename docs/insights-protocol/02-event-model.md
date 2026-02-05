# InsightsEvent — Event Model

This document defines the complete `InsightsEvent` type hierarchy. All types live in `agent_sdk_core`.

## Design Decisions

### Why Sealed Classes, Not JSON

The current system dispatches on `rawJson['type']` strings. This means:
- Typos compile fine, fail at runtime
- Adding a new event type doesn't produce compiler errors at consumption sites
- Every field access is a nullable cast from `dynamic`

Dart 3 sealed classes give us:
- **Exhaustive pattern matching** — the compiler requires handling every subtype
- **Typed fields** — no casts, no null-checking fields that are always present
- **IDE support** — autocomplete, refactoring, find-references all work

### Why `ToolKind` Is an Enum, Not a String

The current system uses tool name strings (`"Bash"`, `"Write"`, `"Edit"`) which are Claude-specific. Codex maps its items to these strings, losing semantic information.

`ToolKind` is an enum aligned with ACP's `kind` field:

```dart
enum ToolKind {
  execute,  // Shell/command execution (Bash, ShellTool)
  read,     // File reading (Read, ReadFileTool)
  edit,     // File modification (Edit, Write, EditTool, WriteFileTool)
  delete,   // File deletion
  move,     // File rename/move
  search,   // Content/file search (Grep, Glob, GrepTool, GlobTool)
  fetch,    // Web fetching (WebFetch, WebFetchTool)
  browse,   // Web search (WebSearch, WebSearchTool)
  think,    // Subagent/delegation (Task)
  ask,      // User interaction (AskUserQuestion)
  memory,   // State tracking (TodoWrite, MemoryTool)
  mcp,      // MCP server tool call
  other,    // Unknown/custom tools
}
```

Each backend maps its native tool names/types into these kinds. The original tool name is preserved in `toolName` for display and backend-specific rendering.

## Event Hierarchy

```dart
sealed class InsightsEvent {
  /// Unique event ID (UUID or backend-provided).
  final String id;

  /// When this event was created.
  final DateTime timestamp;

  /// Which backend produced this event.
  final BackendProvider provider;

  /// Original wire-format data for debugging.
  final Map<String, dynamic>? raw;

  /// Provider-specific extensions that don't fit the common model.
  final Map<String, dynamic>? extensions;
}
```

### `BackendProvider`

```dart
enum BackendProvider {
  claude,
  codex,
  gemini,
  acp,    // Generic ACP-compatible agent
}
```

## Event Types

### Session Lifecycle

#### `SessionInitEvent`

Emitted once when the session is established and ready for prompts.

```dart
class SessionInitEvent extends InsightsEvent {
  /// The session identifier (for resume, routing, etc.)
  final String sessionId;

  /// The model being used.
  final String? model;

  /// Working directory for this session.
  final String? cwd;

  /// Available tools reported by the backend.
  final List<String>? availableTools;

  /// MCP server statuses.
  final List<McpServerStatus>? mcpServers;

  /// Permission mode in effect.
  final String? permissionMode;

  /// Account information (Claude-specific, null for others).
  final AccountInfo? account;

  /// Available slash commands.
  final List<SlashCommand>? slashCommands;

  /// Available models (from init response).
  final List<ModelInfo>? availableModels;
}
```

**Claude**: Populated from the `control_response` (models, account, commands) and `system`/`init` message (tools, MCP, permission mode, cwd, model).
**Codex**: Populated from `thread/started` (model only). Other fields null.
**ACP**: Populated from `initialize` response (capabilities) and `session/new` response.

#### `SessionStatusEvent`

Backend status changes during a session.

```dart
class SessionStatusEvent extends InsightsEvent {
  final String sessionId;
  final SessionStatus status;
  final String? message;
}

enum SessionStatus {
  compacting,    // Context is being compacted
  resuming,      // Session is being resumed
  interrupted,   // User interrupted execution
  ended,         // Session ended normally
  error,         // Session encountered an error
}
```

### Content Events

#### `TextEvent`

Text output from the assistant (regular text or extended thinking).

```dart
class TextEvent extends InsightsEvent {
  final String sessionId;
  final String text;
  final TextKind kind;
  final String? parentCallId;  // Non-null if from a subagent

  /// The model that generated this text, if known.
  final String? model;
}

enum TextKind {
  text,      // Regular assistant output
  thinking,  // Extended thinking / reasoning
  plan,      // Execution plan (Codex)
  error,     // Error message from the model
}
```

#### `UserInputEvent`

A user message was sent (for display in the conversation log).

```dart
class UserInputEvent extends InsightsEvent {
  final String sessionId;
  final String text;
  final List<ImageData>? images;
  final bool isSynthetic;   // System-generated (e.g., replay)
}
```

### Tool Events

#### `ToolInvocationEvent`

A tool has been invoked. Emitted when the backend starts executing a tool.

```dart
class ToolInvocationEvent extends InsightsEvent {
  /// Unique identifier for this tool call (for pairing with completion).
  final String callId;

  /// Parent tool call ID (non-null when this is a subagent tool).
  final String? parentCallId;

  /// Session this tool call belongs to.
  final String sessionId;

  /// Semantic category of the tool (ACP-aligned).
  final ToolKind kind;

  /// Backend-specific tool name for display ("Bash", "ShellTool", "commandExecution").
  final String toolName;

  /// Human-readable description of what the tool is doing.
  final String? title;

  /// Tool input parameters.
  final Map<String, dynamic> input;

  /// File paths affected by this tool call.
  final List<String>? locations;

  /// The model that invoked this tool.
  final String? model;
}
```

**Field mapping by backend:**

| Field | Claude CLI | Codex | ACP |
|-------|-----------|-------|-----|
| `callId` | `tool_use` block `id` | `item.id` | `toolCallId` |
| `parentCallId` | `parent_tool_use_id` | Always null | TBD |
| `kind` | Derived from tool name | Derived from item type | `kind` field directly |
| `toolName` | `tool_use` block `name` | Item type → mapped name | `tool_name` or tool ID |
| `title` | Not provided (can derive) | Not provided | `title` field |
| `input` | `tool_use` block `input` | Extracted from item fields | `rawInput` |
| `locations` | Extracted from input (file_path, etc.) | Extracted from changes[].path | `locations` |
| `model` | From `message.model` or init | From thread model | From session model |

#### `ToolCompletionEvent`

A tool call has completed (success or failure).

```dart
class ToolCompletionEvent extends InsightsEvent {
  /// The tool call ID this completes.
  final String callId;

  /// Session this belongs to.
  final String sessionId;

  /// Completion status.
  final ToolCallStatus status;

  /// Result data (structure depends on tool kind).
  final dynamic output;

  /// Whether the tool execution resulted in an error.
  final bool isError;

  /// Rich content blocks (diffs, terminal output, images, etc.)
  final List<ContentBlock>? content;

  /// File paths modified by this tool call.
  final List<String>? locations;
}

enum ToolCallStatus {
  completed,
  failed,
  cancelled,
}
```

#### `SubagentSpawnEvent`

A subagent was spawned (Claude's Task tool). This is separate from `ToolInvocationEvent` because it has lifecycle implications (creating a new conversation).

```dart
class SubagentSpawnEvent extends InsightsEvent {
  final String sessionId;

  /// The tool call ID that spawned this subagent.
  final String callId;

  /// The subagent type (e.g., "Explore", "Plan", "Bash").
  final String? agentType;

  /// The task description given to the subagent.
  final String? description;

  /// Whether this is resuming a previous agent.
  final bool isResume;

  /// The agent ID being resumed (if isResume).
  final String? resumeAgentId;
}
```

#### `SubagentCompleteEvent`

A subagent finished its work.

```dart
class SubagentCompleteEvent extends InsightsEvent {
  final String sessionId;
  final String callId;
  final String? agentId;   // For future resume
  final String? status;    // "completed", "error", etc.
  final String? summary;   // Result summary
}
```

### Turn Lifecycle

#### `TurnCompleteEvent`

A turn (prompt → response cycle) has completed.

```dart
class TurnCompleteEvent extends InsightsEvent {
  final String sessionId;

  /// Whether the turn ended successfully.
  final bool isError;

  /// Turn result subtype ("success", "error_max_turns", etc.)
  final String? subtype;

  /// Error messages, if any.
  final List<String>? errors;

  /// Final text result (if any).
  final String? result;

  // --- Usage (optional, not all backends provide all fields) ---

  /// Total cost in USD for this turn.
  final double? costUsd;

  /// Wall-clock duration in milliseconds.
  final int? durationMs;

  /// API-only duration in milliseconds.
  final int? durationApiMs;

  /// Number of agentic turns taken.
  final int? numTurns;

  /// Aggregate token usage.
  final TokenUsage? usage;

  /// Per-model usage breakdown (Claude-specific).
  final Map<String, ModelTokenUsage>? modelUsage;

  /// Permission denials that occurred during this turn.
  final List<PermissionDenial>? permissionDenials;
}
```

### Context Management

#### `ContextCompactionEvent`

The context window was compacted (automatically or manually).

```dart
class ContextCompactionEvent extends InsightsEvent {
  final String sessionId;

  /// What triggered the compaction.
  final CompactionTrigger trigger;

  /// Token count before compaction.
  final int? preTokens;

  /// Summary of compacted content (arrives in a separate TextEvent).
  final String? summary;
}

enum CompactionTrigger {
  auto,     // Context grew too large
  manual,   // User requested via /compact
  cleared,  // User requested via /clear
}
```

### Permission Events

#### `PermissionRequestEvent`

The backend needs user permission to proceed.

```dart
class PermissionRequestEvent extends InsightsEvent {
  final String sessionId;
  final String requestId;

  /// The tool requesting permission.
  final String toolName;

  /// Semantic tool category.
  final ToolKind toolKind;

  /// The tool's proposed input.
  final Map<String, dynamic> toolInput;

  /// The tool use ID (for correlating with tool events).
  final String? toolUseId;

  /// Why permission was requested.
  final String? reason;

  /// Filesystem path that triggered the block (Claude-specific).
  final String? blockedPath;

  /// Permission suggestions for auto-approval rules (Claude-specific).
  final List<PermissionSuggestion>? suggestions;

  /// The Completer for responding to this request.
  /// (Not serialized — only valid in-process.)
  final Completer<PermissionResponse> _completer;

  void allow({Map<String, dynamic>? updatedInput, ...});
  void deny(String message, {bool interrupt = false});
}
```

### Streaming Events

#### `StreamDeltaEvent`

Partial content arriving during streaming. Only Claude CLI currently emits these.

```dart
class StreamDeltaEvent extends InsightsEvent {
  final String sessionId;
  final String? parentCallId;
  final StreamDeltaKind kind;

  /// For text/thinking deltas.
  final String? textDelta;

  /// For tool input JSON deltas.
  final String? jsonDelta;

  /// Index of the content block being streamed.
  final int? blockIndex;

  /// The tool call ID (for tool input streaming).
  final String? callId;
}

enum StreamDeltaKind {
  text,         // Regular text delta
  thinking,     // Thinking text delta
  toolInput,    // Tool input JSON delta
  messageStart, // Message streaming began
  messageStop,  // Message streaming ended
  blockStart,   // Content block streaming began
  blockStop,    // Content block streaming ended
}
```

## Supporting Types

### `TokenUsage`

```dart
@immutable
class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheReadTokens;
  final int? cacheCreationTokens;
}
```

### `ModelTokenUsage`

Extended per-model usage (Claude-specific richness).

```dart
@immutable
class ModelTokenUsage extends TokenUsage {
  final double? costUsd;
  final int? contextWindow;
  final int? webSearchRequests;
}
```

### `PermissionSuggestion`

Auto-approval rule suggestion from Claude CLI.

```dart
@immutable
class PermissionSuggestion {
  final String type;       // "allow_tool", "allow_directory", "set_mode"
  final String? toolName;
  final String? directory;
  final String? mode;
  final String description;
}
```

### `PermissionDenial`

Record of a tool that was denied during a turn.

```dart
@immutable
class PermissionDenial {
  final String toolName;
  final String toolUseId;
  final Map<String, dynamic> toolInput;
}
```

### `ContentBlock`

Reused from the existing `agent_sdk_core` definition (TextBlock, ThinkingBlock, ImageBlock, ToolUseBlock, ToolResultBlock, UnknownBlock). Extended with:

```dart
/// A diff content block for file modifications.
class DiffBlock extends ContentBlock {
  final String filePath;
  final String? oldContent;
  final String? newContent;
  final String? unifiedDiff;
}

/// A terminal output content block.
class TerminalBlock extends ContentBlock {
  final String output;
  final String? stderr;
  final int? exitCode;
}
```

## Tool Kind Mapping

How backend-specific tool names map to `ToolKind`:

### Claude CLI

| Tool Name | ToolKind |
|-----------|----------|
| `Bash` | `execute` |
| `Read` | `read` |
| `Write` | `edit` |
| `Edit` | `edit` |
| `Glob` | `search` |
| `Grep` | `search` |
| `WebFetch` | `fetch` |
| `WebSearch` | `browse` |
| `Task` | `think` |
| `AskUserQuestion` | `ask` |
| `TodoWrite` | `memory` |
| `NotebookEdit` | `edit` |
| `mcp__*` | `mcp` |
| (unknown) | `other` |

### Codex

| Item Type | ToolKind | Mapped `toolName` |
|-----------|----------|-------------------|
| `commandExecution` | `execute` | `Bash` |
| `fileChange` | `edit` | `FileChange` (not `Write` — preserves semantics) |
| `mcpToolCall` | `mcp` | `mcp__<server>__<tool>` (reconstructed) |

### ACP / Gemini CLI

| ACP `kind` / Gemini Tool | ToolKind |
|---------------------------|----------|
| `execute` / `ShellTool` | `execute` |
| `read` / `ReadFileTool` | `read` |
| `edit` / `WriteFileTool`, `EditTool` | `edit` |
| `delete` | `delete` |
| `move` | `move` |
| `search` / `GrepTool`, `GlobTool` | `search` |
| `fetch` / `WebFetchTool` | `fetch` |
| `think` | `think` |
| `other` / `MemoryTool` | `memory` |
| MCP-prefixed | `mcp` |

## Extension Points

The `extensions` map on `InsightsEvent` carries data that is:
- Backend-specific (only one provider produces it)
- Experimental (not yet promoted to a typed field)
- Custom (user-defined MCP tool metadata, etc.)

Example Claude extensions:
```dart
extensions: {
  'claude.apiKeySource': 'ANTHROPIC_API_KEY',
  'claude.outputStyle': 'concise',
  'claude.isSynthetic': true,
  'claude.isReplay': false,
}
```

Example Codex extensions:
```dart
extensions: {
  'codex.turnId': 'turn-abc-123',
  'codex.effortLevel': 'high',
  'codex.commandActions': [...],
  'codex.grantRoot': '/path/to/project',
}
```

When an extension proves universally useful, it gets promoted to a typed field on the event class.
