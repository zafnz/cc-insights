# InsightsEvent Protocol — Overview

## The Problem

CC-Insights supports multiple AI coding agent backends (Claude CLI, Codex, and eventually Gemini/ACP-compatible agents). Each backend uses a different wire protocol:

| Backend | Wire Protocol | Tool Representation |
|---------|--------------|---------------------|
| Claude CLI | JSON Lines (stream-json) | `tool_use`/`tool_result` content blocks inside `assistant`/`user` messages |
| Codex | JSON-RPC 2.0 | `item/started`/`item/completed` notifications |
| ACP agents | JSON-RPC 2.0 | `session/update` with `tool_call_update` notifications |

Currently, the Codex SDK translates its native events into **synthetic Claude-format JSON** — fabricating `assistant` messages with `tool_use` content blocks so the frontend can treat everything as if it came from Claude. This works but has real costs:

1. **Information loss** — Codex's `fileChange` (with rich diff data) becomes a generic `Write` tool. MCP tools become `McpTool` instead of `mcp__server__tool`, losing special UI rendering.
2. **Serialize-parse-read round-trip** — Codex builds JSON dicts → `SDKMessage.fromJson()` parses them → `SdkMessageHandler` reads `msg.rawJson` (the same JSON). The typed objects in the middle do nothing.
3. **No room for backend-specific richness** — Claude's cost tracking, context window info, permission suggestions, and subagent routing have no equivalents in the "canonical" format but are core to the app's value.
4. **Frontend coupled to Claude's wire format** — `SdkMessageHandler` parses raw JSON field names like `parent_tool_use_id`, `modelUsage`, `tool_use_result`, `isSynthetic`. Adding a backend means producing identical JSON.

## The Solution: InsightsEvent

InsightsEvent is a **provider-neutral event model** that sits between the backend SDKs and the frontend. It is inspired by the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/) but extended with rich metadata that ACP deliberately omits (cost, context window, permission suggestions, subagent routing, streaming deltas).

```
Claude CLI (stream-json)  →  claude_dart_sdk  →  InsightsEvent stream
Codex (JSON-RPC)          →  codex_dart_sdk   →  InsightsEvent stream
ACP agent (JSON-RPC)      →  acp_dart_sdk     →  InsightsEvent stream
                                                       ↓
                                                   Frontend
```

### Design Principles

1. **No lowest-common-denominator** — The protocol carries the full richness of each backend. If Claude provides cost data and Codex doesn't, the cost field is optional, not removed. The frontend decides what to show based on what's available.

2. **Backend-specific extensions welcome** — An `extensions` map on events carries provider-specific data that doesn't fit the common model. The frontend can have Claude-specific UI (cost badge, context window meter) without polluting the core protocol.

3. **Typed, not stringly** — Dart sealed classes with exhaustive pattern matching replace string-keyed JSON dispatch. Adding a new event kind or tool kind is a compile error everywhere it needs handling.

4. **ACP-aligned semantics** — Tool categories use ACP's `kind` vocabulary (`read`, `edit`, `execute`, `search`, `fetch`, `think`, `other`) so that ACP backends map with zero translation. Claude and Codex map their tool names into these categories.

5. **Transport-separable** — The event model is serializable. Today, backends run in-process. Tomorrow, they run in Docker containers and stream events over a socket. The frontend doesn't care.

6. **Raw data preserved** — Every event carries an optional `raw` field with the original wire-format data for the JSON debug viewer.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                     Frontend                          │
│                                                       │
│  EventHandler ← Stream<InsightsEvent> ← BackendBridge │
│       │                                    │          │
│  OutputEntry                          InsightsEvent   │
│  ToolCard                             (Dart sealed)   │
│  PermissionDialog                                     │
│  CostBadge                                            │
│  ContextMeter                                         │
└──────────────────────────────────────────────────────┘
                          ↑
           ┌──────────────┼──────────────┐
           │              │              │
    ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴──────┐
    │ Claude SDK │ │ Codex SDK  │ │  ACP SDK    │
    │            │ │            │ │             │
    │ CliSession │ │ CodexSess. │ │ AcpSession  │
    │ → emits    │ │ → emits    │ │ → emits     │
    │ Insights-  │ │ Insights-  │ │ Insights-   │
    │ Events     │ │ Events     │ │ Events      │
    └──────┬─────┘ └──────┬─────┘ └──────┬──────┘
           │              │              │
    Claude CLI      Codex app-server   Any ACP agent
    (subprocess)    (subprocess)       (subprocess/remote)
```

### Where InsightsEvent Lives

The event model is defined in `agent_sdk_core` — the shared package that all SDKs already depend on. It replaces (or sits alongside) the current `SDKMessage` hierarchy.

### What Changes

| Layer | Current | After |
|-------|---------|-------|
| `agent_sdk_core` | `SDKMessage` sealed class (Claude's format) | `InsightsEvent` sealed class (neutral) |
| `AgentSession.messages` | `Stream<SDKMessage>` | `Stream<InsightsEvent>` |
| `claude_dart_sdk` | Parses CLI JSON → `SDKMessage` | Parses CLI JSON → `InsightsEvent` directly |
| `codex_dart_sdk` | Builds synthetic Claude JSON → `SDKMessage.fromJson()` | Maps Codex events → `InsightsEvent` directly |
| `SdkMessageHandler` | Dispatches on `rawJson['type']` strings | Dispatches on sealed class pattern match |
| `ToolCard` | Switches on `toolName` string | Switches on `ToolKind` enum (compile-checked) |

### What Stays the Same

- `OutputEntry` hierarchy (the frontend's persistence model)
- `ToolCard` visual design (just changes how it gets its data)
- `PermissionRequest`/`PermissionResponse` (already generic, stays)
- `AgentBackend` interface (unchanged)
- Each backend's subprocess management

## Relationship to ACP

ACP is designed for **editor ↔ agent** integration. It defines the minimum contract an editor needs: session lifecycle, message streaming, tool call reporting, permission requests.

InsightsEvent is designed for **monitoring and deep inspection**. It extends ACP's concepts with:

| ACP Concept | InsightsEvent Extension |
|-------------|------------------------|
| `tool_call_update` with `status` | + `costUsd`, `durationMs`, per-model usage breakdown |
| `session/update` content blocks | + `parentCallId` for subagent conversation routing |
| `session/request_permission` | + `suggestions` (auto-approve rules), `blockedPath`, `decisionReason` |
| No concept | Context window tracking (`currentTokens`, `maxTokens`, compaction events) |
| No concept | Per-model cost breakdown (`modelUsage`) |
| No concept | Account metadata (email, org, subscription type, API key source) |
| No concept | MCP server status tracking |
| No concept | Streaming deltas (text, thinking, tool input JSON) |
| `kind` enum (read/edit/execute/...) | Same vocabulary, used as `ToolKind` |

If a pure ACP agent connects, its events map into InsightsEvent with the ACP fields populated and the extensions left null. The frontend gracefully degrades — no cost badge, no context meter, but tool cards and permissions work perfectly.

## Document Index

| Document | Contents |
|----------|----------|
| [02 — Event Model](02-event-model.md) | Complete `InsightsEvent` type hierarchy, field definitions, `ToolKind` enum |
| [03 — Claude Mapping](03-claude-mapping.md) | How Claude CLI stream-json maps to InsightsEvent (the richest backend) |
| [04 — Codex Mapping](04-codex-mapping.md) | How Codex JSON-RPC maps to InsightsEvent, what it doesn't provide |
| [05 — Gemini/ACP Mapping](05-gemini-acp-mapping.md) | How ACP-compatible agents (including Gemini CLI) map to InsightsEvent |
| [06 — Frontend Consumption](06-frontend-consumption.md) | How the frontend uses InsightsEvent, backend-aware UI, feature detection |
| [07 — Transport Separation](07-transport-separation.md) | Serialization, Docker containers, remote backends, phased rollout |
| [08 — Permissions](08-permissions.md) | Permission model deep dive: Claude suggestions, Codex decisions, ACP options |
| [09 — Streaming](09-streaming.md) | Streaming model across backends: Claude SSE, ACP chunks, Codex batch |
| [10 — Migration](10-migration.md) | Phased migration guide from SDKMessage to InsightsEvent |
