**Implementation Plan**

**Phase 1: ACP SDK scaffolding**
1. Create `acp_dart_sdk/` with `AcpProcess`, `AcpBackend`, `AcpSession`.
2. Reuse or copy `codex_dart_sdk/lib/src/json_rpc.dart` to implement line-delimited JSON-RPC.
3. `AcpProcess` spawns agent executable and runs `initialize` with ACP v1 and client capabilities.
4. `AcpBackend` implements `AgentBackend`, manages sessions, and exposes logs and errors.

**Phase 2: ACP session lifecycle**
1. `AcpSession` implements `AgentSession` and handles:
2. `session/new` and optional `session/load`.
3. `session/prompt` with content blocks.
4. `session/cancel`.
5. `session/set_mode` and `session/set_config_option` based on config options.

**Phase 3: Event mapping**
1. Map `session/update` notifications into InsightsEvents.
2. Add new InsightsEvent types for ACP updates and route them in `frontend/lib/services/event_handler.dart`.
3. Update tool and text streaming behavior to respect `RuntimeConfig.streamOfThought`.
4. Update `docs/insights-protocol/05-gemini-acp-mapping.md` to ACP v1 field names.

**Phase 4: ACP client-side methods**
1. Implement `fs/read_text_file` and `fs/write_text_file` with root + allowlist checks.
2. Implement `terminal/*` methods using a local terminal manager.
3. Add permission requests for out-of-scope file or terminal access.

**Phase 5: UI and toolbar**
1. Surface ACP config options on the conversation toolbar.
2. Prioritize `category: model` and `category: mode` options.
3. Add a compact dropdown for other categories (for example `thought_level`).
4. Update permission dialog to render ACP options from `extensions['acp.permissionOptions']`.

**Phase 6: Tests**
1. Unit tests for ACP mapping and JSON-RPC parsing.
2. Session-level tests for permission flow, config option updates, and tool call lifecycle.
3. Integration test with a stub ACP agent.

**Primary Files**
- `acp_dart_sdk/lib/src/acp_process.dart`
- `acp_dart_sdk/lib/src/acp_backend.dart`
- `acp_dart_sdk/lib/src/acp_session.dart`
- `acp_dart_sdk/lib/src/json_rpc.dart`
- `agent_sdk_core/lib/src/types/insights_events.dart`
- `frontend/lib/services/event_handler.dart`
- `frontend/lib/widgets/permission_dialog.dart`
- `frontend/lib/panels/conversation_header.dart`
- `docs/insights-protocol/05-gemini-acp-mapping.md`
