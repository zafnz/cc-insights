**ACP Event Model and InsightsEvent Extensions**

**New InsightsEvent Types**
1. `ConfigOptionsEvent`.
- Payload: `sessionId`, `configOptions` (ACP SessionConfigOption list).
- Emit on `session/new` response if `configOptions` present.
- Emit on `session/update` with `config_option_update`.
- Emit on `session/set_config_option` response.

2. `AvailableCommandsEvent`.
- Payload: `sessionId`, `availableCommands` list.
- Emit on `session/update` with `available_commands_update`.

3. `SessionModeEvent`.
- Payload: `sessionId`, `currentModeId`, `availableModes`.
- Emit on `session/new` response if `modes` present.
- Emit on `session/update` with `current_mode_update`.

**Text and Plan Mapping**
- `agent_message_chunk` maps to `TextEvent` or `StreamDeltaEvent` with `TextKind.text`.
- `agent_thought_chunk` maps to `TextEvent` or `StreamDeltaEvent` with `TextKind.thinking`.
- `plan` maps to `TextEvent` with `TextKind.plan`, with full plan entries stored in `extensions['acp.planEntries']`.
- `user_message_chunk` maps to `UserInputEvent` with `isSynthetic: true` for session replay.

**Tool Calls**
- `tool_call` and `tool_call_update` map to `ToolInvocationEvent` and `ToolCompletionEvent`.
- `toolName` uses ACP `title` when present; fallback to `kind`.
- `ToolKind` mapping is direct for ACP kinds.
- Tool content mapping:
- `content` becomes `ToolCompletionEvent.content` if supported by `ContentBlock` or stored in `extensions['acp.toolContent']`.
- `diff` and `terminal` are stored in `ToolCompletionEvent.output` and `extensions['acp.toolContent']`.

**Stop Reasons**
- `session/prompt` response `stopReason` maps to `TurnCompleteEvent.subtype`.
- If JSON-RPC error occurs, emit `SessionStatusEvent(status: error)` and set `TurnCompleteEvent.isError`.

**Capabilities and Init**
- `initialize` response `agentCapabilities`, `agentInfo`, `authMethods` should be included in `SessionInitEvent.extensions['acp.*']`.
- `session/new` response includes `sessionId` and optional `configOptions` and `modes`.

**Content Blocks**
ACP uses MCP `ContentBlock` types. To preserve fidelity:
- Extend `agent_sdk_core` content blocks to include `resource`, `resource_link`, `image`, and `audio` in addition to `text`.
- If not extended, store raw ACP content blocks in `extensions['acp.content']` and render as text fallback.
