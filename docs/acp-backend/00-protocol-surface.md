**ACP Protocol Surface (Schema v1)**

Source of truth: `../acp-support/packages/agent-client-protocol/schema/schema.json`. This summary only covers ACP methods and payloads used by CC-Insights.

**Client → Agent methods (JSON-RPC requests/notifications)**

| Method | Params (required) | Notes |
| --- | --- | --- |
| `initialize` | `protocolVersion`, `clientCapabilities` (optional), `clientInfo` (optional) | `protocolVersion` is a `uint16` integer. |
| `session/new` | `cwd`, `mcpServers` | `mcpServers` is required (can be empty array). |
| `session/load` | `sessionId`, `cwd`, `mcpServers` | Only when `agentCapabilities.loadSession` is true. |
| `session/prompt` | `sessionId`, `prompt` | `prompt` is an array of `ContentBlock`. |
| `session/cancel` | `sessionId` | Notification (no response expected). |
| `session/set_mode` | `sessionId`, `modeId` | Response body is an empty object. |

**Agent → Client requests (client must implement)**

| Method | Params (required) | Response |
| --- | --- | --- |
| `session/request_permission` | `sessionId`, `toolCall`, `options` | `outcome` with `outcome: "selected"` + `optionId`, or `outcome: "cancelled"`. |
| `fs/read_text_file` | `sessionId`, `path` | `content` string. Optional `line`, `limit`. |
| `fs/write_text_file` | `sessionId`, `path`, `content` | Empty object. |
| `terminal/create` | `sessionId`, `command` | `terminalId`. Optional `args`, `cwd`, `env`, `outputByteLimit`. |
| `terminal/output` | `sessionId`, `terminalId` | `output`, `truncated`, optional `exitStatus`. |
| `terminal/wait_for_exit` | `sessionId`, `terminalId` | Optional `exitCode` and `signal`. |
| `terminal/kill` | `sessionId`, `terminalId` | Empty object. |
| `terminal/release` | `sessionId`, `terminalId` | Empty object. |

**Agent → Client notifications**

`session/update` notification params contain `sessionId` and `update`. The `update` object carries a `sessionUpdate` discriminator and the fields for the variant below.

| `sessionUpdate` value | Payload fields |
| --- | --- |
| `user_message_chunk` | `content` (`ContentBlock`) |
| `agent_message_chunk` | `content` (`ContentBlock`) |
| `agent_thought_chunk` | `content` (`ContentBlock`) |
| `tool_call` | `ToolCall` |
| `tool_call_update` | `ToolCallUpdate` |
| `plan` | `entries` (`PlanEntry[]`) |
| `available_commands_update` | `availableCommands` (`AvailableCommand[]`) |
| `current_mode_update` | `currentModeId` |

**Tool call shapes**

`ToolCall` fields: `toolCallId` (required), `title` (required), `kind`, `status`, `content`, `locations`, `rawInput`, `rawOutput`.

`ToolCallUpdate` fields: `toolCallId` (required), optional `title`, `kind`, `status`, `content`, `locations`, `rawInput`, `rawOutput`.

`ToolCallContent` discriminators: `type: "content"` (wraps `ContentBlock`), `type: "diff"` (uses `Diff` with `path`, `newText`, optional `oldText`), `type: "terminal"` (uses `terminalId`).

**Permissions payloads**

`session/request_permission` request fields: `sessionId`, `toolCall` (`ToolCallUpdate`), `options` (`PermissionOption[]` with `optionId`, `name`, `kind`).

`session/request_permission` response fields: `outcome` where `outcome: "selected"` includes `optionId`, or `outcome: "cancelled"`.

**Content blocks**

`ContentBlock` discriminator is `type`. Supported types in schema: `text` (`text`), `image` (`data`, `mimeType`, optional `uri`), `audio` (`data`, `mimeType`), `resource_link` (`uri`, optional `mimeType`), `resource` (`uri`, `name`, optional `size`/`title`, and `contents`).

**Differences vs `docs/insights-protocol/05-gemini-acp-mapping.md`**

`protocolVersion` is an integer (`uint16`), not a string like `"0.1"`.

`session/prompt` uses `prompt` (array of `ContentBlock`), not `content`.

`session/update` params use `update` at the top level, and the discriminator field is `sessionUpdate` (not `type`).

`ContentChunk` carries a single `content` block, not a `content` array.

`current_mode_update` is the schema update name; the older doc shows `mode_change`.

`session/new` requires `mcpServers`, and the response includes optional `modes`; there is no `configOptions` or `session/set_config_option` in the schema.
