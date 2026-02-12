**ACP Backend Implementation Plan**

This plan breaks the ACP backend into manageable tasks. Each task includes requirements, tests, and a measurable definition of done (DoD). The checklist fields are mandatory for each task:
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

---

**Task 1: Finalize ACP Protocol Surface**
- Description: Capture ACP v1 method and payload shapes used by the app, including tool calls, permissions, config options, and session updates.
- Requirements:
  - Identify ACP v1 methods and `sessionUpdate` variants from `schema/schema.json`.
  - Document exact payload field names used for mapping.
  - Note differences vs existing docs in `docs/insights-protocol/05-gemini-acp-mapping.md`.
- Tests needed:
  - None (documentation-only).
- Definition of Done:
  - A new protocol summary section exists in `docs/acp-backend/` and all used field names match `schema/schema.json`.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 2: Add ACP Backend Type and Wiring**
- Description: Add ACP as a selectable backend across core and frontend.
- Requirements:
  - Add `BackendType.acp` in `claude_dart_sdk/lib/src/backend_factory.dart`.
  - Update backend selection in `frontend` (backend service, runtime config, chat model lists, UI labels).
  - Add ACP executable path config in `RuntimeConfig` and settings UI.
- Tests needed:
  - Unit test for `BackendFactory.parseType` to accept `acp`.
  - UI test for backend selection options.
- Definition of Done:
  - ACP appears as a backend option in UI and can be selected without runtime errors.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 3: Create `acp_dart_sdk` Package Skeleton**
- Description: Add new Dart package with project structure, pubspec, and exports aligned to other SDKs.
- Requirements:
  - `acp_dart_sdk/` with `lib/acp_sdk.dart` exporting `agent_sdk_core` and ACP backend classes.
  - Build scripts and test scaffolding consistent with existing SDK packages.
- Tests needed:
  - None initially (smoke build later in Task 6/7).
- Definition of Done:
  - Package compiles in isolation and is importable by `frontend`.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 4: Implement ACP JSON-RPC Client (stdio)**
- Description: Implement line-delimited JSON-RPC client for ACP transport.
- Requirements:
  - Reuse or copy `codex_dart_sdk/lib/src/json_rpc.dart`.
  - Ensure ACP spec: UTF-8, newline-delimited, no embedded newlines.
  - Structured protocol logging via `LogEntry`.
- Tests needed:
  - Unit tests for request/response pairing, notification parsing, and error handling.
- Definition of Done:
  - JSON-RPC client passes tests and can parse/send ACP messages in isolation.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 5: Implement `AcpProcess`**
- Description: Spawn ACP agent subprocess and run `initialize`.
- Requirements:
  - Launch agent executable with args (configurable).
  - Send `initialize` with protocolVersion=1 and client capabilities.
  - Capture `initialize` response and expose capability info.
  - Provide stdout/stderr log streams.
- Tests needed:
  - Unit test with a fake process stream to validate `initialize` request format.
- Definition of Done:
  - `AcpProcess.start()` returns a ready process and stores negotiated capabilities.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 6: Implement `AcpBackend`**
- Description: ACP backend implementing `AgentBackend`.
- Requirements:
  - Manage sessions and backend lifecycle.
  - Provide logs, errors, and capabilities.
  - Create sessions and pass session options.
- Tests needed:
  - Unit test for session creation path calling `session/new`.
- Definition of Done:
  - Backend can create a session and emit a `SessionInitEvent`.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 7: Implement `AcpSession` Core**
- Description: Session lifecycle methods and messaging.
- Requirements:
  - `send`, `sendWithContent`, `interrupt`, `kill`, `setModel`, `setPermissionMode`, `setReasoningEffort`.
  - Support `session/new`, optional `session/load`, `session/prompt`, `session/cancel`.
- Tests needed:
  - Unit tests for request payload shapes for `session/prompt`, `session/cancel`.
- Definition of Done:
  - ACP session executes a prompt and accepts cancel.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 8: Add New InsightsEvent Types**
- Description: Add events for ACP config options, modes, and commands.
- Requirements:
  - Add `ConfigOptionsEvent`, `AvailableCommandsEvent`, `SessionModeEvent` to `agent_sdk_core`.
  - Serialization/deserialization tests.
  - Update `frontend` event handler to route new events.
- Tests needed:
  - Unit tests for JSON round-trip in `agent_sdk_core`.
- Definition of Done:
  - New event types are usable in frontend with no runtime errors.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 9: ACP `session/update` Mapping (Text + Plan)**
- Description: Map ACP message chunks and plan updates to InsightsEvents.
- Requirements:
  - `agent_message_chunk` -> `TextEvent` or `StreamDeltaEvent`.
  - `agent_thought_chunk` -> `TextEvent` or `StreamDeltaEvent` with `TextKind.thinking`.
  - `plan` -> `TextEvent` with `TextKind.plan`, include raw plan entries in extensions.
  - `user_message_chunk` -> `UserInputEvent` with `isSynthetic: true`.
- Tests needed:
  - Unit tests for each session update variant mapping.
- Definition of Done:
  - All ACP text/plan updates appear in the conversation view and streaming respects config.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 10: ACP Tool Call Mapping**
- Description: Map `tool_call` and `tool_call_update` updates to tool events.
- Requirements:
  - Use `title` as `toolName` fallback to `kind`.
  - Map status transitions to invocation/completion.
  - Preserve `rawInput`/`rawOutput` and `locations`.
  - Map ACP tool content (`content`, `diff`, `terminal`) into output/extension fields.
- Tests needed:
  - Unit tests for tool call lifecycle and completion status mapping.
- Definition of Done:
  - Tool cards show ACP tool activity and results reliably.
- [x] Implemented
- [x] Tests written
- [x] Review passed
- [x] Done

**Task 11: ACP Permissions Mapping**
- Description: Handle `session/request_permission` and respond with ACP outcomes.
- Requirements:
  - Emit `PermissionRequestEvent` with ACP options in extensions.
  - Map user choices to ACP `RequestPermissionOutcome`.
  - Support cancel -> `outcome: cancelled`.
- Tests needed:
  - Unit tests for permission request parsing and response formatting.
- Definition of Done:
  - Permission dialog renders ACP options and responses are accepted by stub ACP agent.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 12: Filesystem RPC Methods**
- Description: Implement `fs/read_text_file` and `fs/write_text_file` server-side in the client.
- Requirements:
  - Absolute path enforcement.
  - Repo-root + allowlist checks.
  - Permission request for out-of-scope access (default deny).
- Tests needed:
  - Unit tests for path validation and access policies.
- Definition of Done:
  - ACP agent can read/write files inside repo root; blocked outside.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 13: Terminal RPC Methods**
- Description: Implement `terminal/*` operations for ACP.
- Requirements:
  - Create, output, wait, kill, release.
  - Enforce `outputByteLimit` truncation.
  - Apply path policies to `cwd` and request permission if needed.
- Tests needed:
  - Unit tests for create/output/wait flow and truncation behavior.
- Definition of Done:
  - ACP agent can run a command and retrieve output through ACP terminal APIs.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 14: Config Options and Modes Handling**
- Description: Emit events for ACP config options and mode updates.
- Requirements:
  - Emit `ConfigOptionsEvent` from `session/new` and `session/update`.
  - Emit `SessionModeEvent` from `session/new` and `current_mode_update`.
  - Implement `setModel` and `setPermissionMode` using ACP config/mode APIs.
- Tests needed:
  - Unit tests for config update response parsing and event emission.
- Definition of Done:
  - Config options and modes appear in the UI via new events.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 15: Available Commands Handling**
- Description: Emit `AvailableCommandsEvent` and store for UI.
- Requirements:
  - Parse `available_commands_update` session updates.
  - Emit `AvailableCommandsEvent` with command list.
- Tests needed:
  - Unit test for command update mapping.
- Definition of Done:
  - Commands are visible to UI for toolbar/menu integration.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 16: Content Block Support (ACP/MCP)**
- Description: Extend content blocks to cover ACP content types.
- Requirements:
  - Add support for `resource`, `resource_link`, `audio`, and ACP `image` format if needed.
  - Update serialization and UI rendering fallbacks.
- Tests needed:
  - Unit tests for content block parsing and JSON serialization.
- Definition of Done:
  - ACP content blocks render without crashing; text content still primary.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 17: Toolbar UI for ACP Config Options**
- Description: Display ACP config selectors on the conversation toolbar.
- Requirements:
  - Show `model` and `mode` categories prominently.
  - Overflow menu for other categories.
  - Hide selectors with a single value.
- Tests needed:
  - Widget tests for selector rendering and update actions.
- Definition of Done:
  - Users can change ACP config options from toolbar and see updates reflected.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 18: Permission Dialog for ACP Options**
- Description: Render ACP permission options in the dialog.
- Requirements:
  - New dialog layout path for ACP provider.
  - Buttons built from ACP `options` list.
- Tests needed:
  - Widget test for ACP permission dialog with options.
- Definition of Done:
  - ACP permission prompts render with correct option labels and outcomes.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 19: Update Mapping Documentation**
- Description: Update `docs/insights-protocol/05-gemini-acp-mapping.md` to ACP v1 field names and current mapping strategy.
- Requirements:
  - Replace old protocol version and fields with ACP v1.
  - Align with new event types and tool content handling.
- Tests needed:
  - None.
- Definition of Done:
  - Document matches ACP v1 and this implementation plan.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done

**Task 20: End-to-End ACP Session Smoke Test**
- Description: Validate the full ACP session lifecycle with a stub ACP agent.
- Requirements:
  - Stub agent that supports initialize, session/new, prompt, update, request_permission, fs, terminal.
  - Validate tool call mapping, permissions, and config options.
- Tests needed:
  - Integration test running the stub agent.
- Definition of Done:
  - ACP session runs end-to-end and passes integration test.
- [ ] Implemented
- [ ] Tests written
- [ ] Review passed
- [ ] Done
