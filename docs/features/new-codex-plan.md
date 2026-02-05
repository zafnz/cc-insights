# Codex App-Server Integration Plan (Proper Split)

## Summary
Integrate OpenAI Codex CLI app-server JSON-RPC as a first-class backend
alongside Claude by splitting shared types into a new core package and
shipping a separate `codex_dart_sdk`. The goal is a clean, maintainable
multi-backend architecture with minimal UI churn, plus permission
approvals, tool output, and session resume support.

This plan assumes I will implement all tasks end-to-end.

Sources:
- `docs/features/codex.md` (protocol details, item taxonomy, handshake)
- Existing `claude_dart_sdk` and `frontend` architecture
- `docs/features/codex-schema/` (generated JSON schema files)

## Non-Negotiables
- Full split: `agent_sdk_core`, `claude_dart_sdk`, `codex_dart_sdk`.
- Codex uses `app-server` only (no `exec --json`).
- Frontend stays stable by normalizing Codex events into `SDKMessage`.
- All tests pass (per `AGENTS.md`).

## Status (as of this plan update)
- Phase 0 complete: schema generated in `docs/features/codex-schema`.
  - Validation counts: ClientRequest=56, ServerNotification=31,
    ServerRequest=7.
- Phase 1 complete: `agent_sdk_core` created, Claude SDK re-exports added.
- Phase 2 complete: `codex_dart_sdk` JSON-RPC layer added.
- Phase 3 complete: Codex backend/session added (non-streaming MVP).
- Phases 4-8 remain (polish, UI integration, tests, streaming).

## Current Architecture Snapshot (post-split)
- `agent_sdk_core` owns `AgentBackend`, `AgentSession`, shared types, and
  permission data structures.
- `claude_dart_sdk` re-exports shared types and depends on
  `agent_sdk_core` and `codex_dart_sdk`.
- `codex_dart_sdk` contains JSON-RPC plumbing, a long-lived app-server
  process, and Codex-specific backend/session.
- `BackendFactory` supports `codex` as a `BackendType`.
- `frontend` now has a `ChatModel` abstraction and backend selection
  plumbing, but message rendering still expects Claude-style `SDKMessage`.
- Tool rendering expects Claude-style tool names (`Bash`, `Read`, `Write`,
  `Edit`, `Task`, etc.).

## Guiding Decisions
1. Use Codex `app-server` JSON-RPC only.
2. Keep shared types in `agent_sdk_core` and keep backend packages thin.
3. Preserve frontend message handling by normalizing Codex events into
   Claude-style `SDKMessage` raw JSON shapes.
4. Use a model abstraction in the frontend so Claude/Codex models can
   coexist without a Claude-only enum.

## Implementation Plan

### Phase 0: Protocol and schema validation (DONE)
Steps:
- Run `codex app-server generate-json-schema`.
- Store output under `docs/features/codex-schema/`.
- Validate counts (56 client requests, 31 server notifications, 7 server
  requests) by counting `oneOf` entries in JSON schema files.

Deliverables:
- `docs/features/codex-schema/` updated and committed.

Review checklist:
- [x] `ClientRequest.json` has 56 `oneOf` entries.
- [x] `ServerNotification.json` has 31 `oneOf` entries.
- [x] `ServerRequest.json` has 7 `oneOf` entries.
- [x] Any count change triggers a plan and mapping review.

### Phase 1: Create `agent_sdk_core` (DONE)
Steps:
- Extract shared interfaces and types from `claude_dart_sdk` into a new
  `agent_sdk_core` package.
- Add re-exports in `claude_dart_sdk` to keep existing imports stable.
- Add `resolvedSessionId` getter to `AgentSession` (defaults to
  `sessionId`).
- Update package dependencies and imports.
- Add doc comments for public APIs per `FLUTTER.md`.

Deliverables:
- `agent_sdk_core` package in the repo root.
- `claude_dart_sdk` builds with re-exported shared types.

Review checklist:
- [x] No direct imports into moved files remain in `frontend`.
- [x] `claude_dart_sdk` compiles with updated dependencies.
- [x] `resolvedSessionId` is used wherever session IDs are stored.

### Phase 2: Codex JSON-RPC process layer (DONE)
Steps:
- Implement `JsonRpcClient` for request/response correlation and
  line-delimited parsing.
- Implement `CodexProcess` to spawn `codex app-server` and expose:
  - notification stream
  - server request stream (approval flow)
  - logs stream
- Centralize JSON parsing and error handling in JSON-RPC layer.
- Use `SdkLogger` rather than `print`.

Deliverables:
- `codex_dart_sdk/lib/src/json_rpc.dart`.
- `codex_dart_sdk/lib/src/codex_process.dart`.

Review checklist:
- [x] Initialize/initialized handshake succeeds.
- [x] Request IDs correlate correctly under parallel requests.
- [x] Notifications and server requests are routed without loss.

### Phase 3: Codex backend and session (DONE)
Steps:
- Implement `CodexBackend` with one shared app-server process.
- Implement `CodexSession` using `thread/start`, `thread/resume`,
  `turn/start`, `turn/interrupt`.
- Ensure `sessionId` is the thread ID and `resolvedSessionId` is exposed.
- `sendWithContent` maps `ContentBlock` into Codex input items.

Deliverables:
- `codex_dart_sdk/lib/src/codex_backend.dart`.
- `codex_dart_sdk/lib/src/codex_session.dart`.

Review checklist:
- [x] New thread creation returns a valid thread ID.
- [x] Resume uses `SessionOptions.resume` and restores via `thread/resume`.
- [x] `interrupt` and `kill` behave like Claude sessions.

### Phase 4: Codex -> Claude-style message normalization (IN PROGRESS)
Steps:
- Normalize Codex notifications into Claude-style `SDKMessage` JSON:
  - `thread/started` -> `system` init message
  - `item/started` -> `assistant` tool_use for tool-like items
  - `item/completed` -> `assistant` text/thinking or `tool_result`
  - `turn/completed` -> `result` message with usage
- Normalize tool names to match existing UI expectations.
- Implement non-streaming MVP first; map deltas later.

Deliverables:
- Stable message mapping that renders correctly in existing UI.

Review checklist:
- [ ] Tool cards render for `commandExecution` and `fileChange`.
- [ ] Assistant text appears without requiring UI changes.
- [ ] Usage shows in `result` entries when available.

### Phase 5: Backend selection and configuration (IN PROGRESS)
Steps:
- Add `BackendType.codex` and parse config values.
- Update `BackendFactory` to delegate to `CodexBackend`.
- Update `BackendService.start()` to accept a backend type.
- Persist default backend in `SettingsService` and sync to `RuntimeConfig`.
- Add optional codex executable path support.

Deliverables:
- Backend selection works end-to-end without code changes elsewhere.

Review checklist:
- [ ] Switching backend creates correct session type.
- [ ] Backend choice persists across app restarts.
- [ ] Codex executable path can be set and used.

### Phase 6: Model and permission abstraction (IN PROGRESS)
Steps:
- Introduce `ChatModel` value object and catalog for Claude and Codex.
- Replace `ClaudeModel` usage in models/panels/services.
- Define initial Codex model list; later load via `model/list`.
- Map UI permission modes to Codex config or safely ignore.

Deliverables:
- Model dropdowns support both providers.
- Chats persist model + provider in metadata.

Review checklist:
- [ ] Model selection works for both backends.
- [ ] Existing Claude chats migrate with correct model mapping.
- [ ] Permission mode selections do not break Codex flows.

### Phase 7: Persistence and resume (IN PROGRESS)
Steps:
- Extend `ChatMeta` with `backendType` and model identifiers.
- Update restore logic to use `ChatModelCatalog`.
- Ensure Codex thread IDs are stored in `ChatReference.lastSessionId`.

Deliverables:
- Codex threads resume across app restarts.

Review checklist:
- [ ] Codex chats reopen and resume correctly.
- [ ] Missing/unknown models fall back safely.
- [ ] No migration regressions for existing Claude data.

### Phase 8: Tests, tooling, and verification (PENDING)
Steps:
- Add unit tests for JSON-RPC parsing and Codex message mapping.
- Add unit tests for permission request flow.
- Add integration test for Codex backend (thread start, tool approval).
- Run `dart_format`, `dart_fix`, and `analyze_files`.
- Run full test suite and integration test via MCP tools.

Deliverables:
- CI-safe test coverage for the new backend.

Review checklist:
- [ ] `mcp__flutter-test__run_tests` passes.
- [ ] `mcp__flutter-test__run_tests(path: "integration_test/app_test.dart")`
      passes.
- [ ] Lint and format checks are clean.

## Cross-Cutting Quality Gates
- Follow `FLUTTER.md` for formatting, doc comments, and linting.
- Prefer immutable data and `ChangeNotifier` patterns already in use.
- Use `logging` package instead of `print`.
- Keep code small and explicit; avoid premature abstractions.

## Open Questions / Risks
- Approval response payloads for `requestApproval` still need confirmed
  field-level mapping (schema vs. runtime).
- File change payload shape (patch vs. full content) affects `Edit` vs
  `Write` mapping.
- Streaming deltas require buffering strategy to avoid UI churn.
- Collab/multi-agent events may need a dedicated UI treatment later.

## Minimal MVP Milestone
- Codex backend starts, thread/turn works, assistant text appears.
- Basic command execution shows as `Bash` tool use with output.
- Permission requests display using existing dialog.
- Session resume works via stored thread ID.

## Test Plan (must pass before completion)
- `mcp__flutter-test__run_tests`
- `mcp__flutter-test__run_tests(path: "integration_test/app_test.dart")`
