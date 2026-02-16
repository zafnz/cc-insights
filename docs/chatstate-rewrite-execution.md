# ChatState Rewrite Execution Tracker

## Purpose

This document is the single source of truth for executing
`docs/chatstate-rewrite-proposal-2.md`.

Use it to track progress, decisions, risks, and acceptance gates.

---

## Ground Rules

1. No big-bang rewrite.
2. One chunk at a time.
3. Each chunk ends with tests and a checkpoint commit.
4. Keep compatibility facade until late migration.
5. Do not proceed if acceptance criteria for the active chunk fail.

---

## Active Branch + Worktree

- Branch: `codex/chatstate-rewrite-codex` (update if different)
- Worktree: `/Users/zaf/projects/.cc-insights-wt/cci/chatstate-rewrite-codex`

---

## Global Acceptance Gates

These must all be true before declaring rewrite complete:

1. `ChatState` removed from production code.
2. `Chat` is a plain container (no side effects, no notifier).
3. Per-session event routing state only (`SessionEventPipeline`).
4. Single idempotent teardown path in session lifecycle.
5. UI-ephemeral state isolated in `ChatViewState`.
6. Chat persistence is serialized and failure-observable.
7. Behavior parity maintained (resume, permissions, subagents, streaming, usage).

---

## Chunk Plan

Status values: `todo`, `in_progress`, `done`, `blocked`

| ID | Chunk | Status | Notes |
|---|---|---|---|
| A | Build sub-state skeletons + compatibility facade scaffolding | done | Sub-state facade classes added; ChatState now fans out notifications to sub-states; no provider migration yet. |
| B | Session lifecycle consolidation + state machine + teardown unification | done | Added `SessionPhase` lifecycle state machine and a single idempotent teardown path in ChatState; preserved interrupt semantics (no full teardown). |
| C | Permission flow isolation | done | Moved permission queue mutations/flow into `ChatPermissionState`; `ChatState` permission APIs now delegate for compatibility. |
| D | Metrics/context extraction | done | Moved usage/context/timing logic ownership into `ChatMetricsState`; `ChatState` metrics APIs now delegate for compatibility. |
| E | Persistence coordinator with serialized queues/retry semantics | done | Added `ChatPersistenceState` coordinator with queued/retried writes; `ChatState` persistence APIs now delegate for compatibility. |
| F | SessionEventPipeline (per-session routing state) | done | Added `SessionEventPipeline` and moved event routing/tool pairing/streaming state to per-session pipelines keyed by chat session lifecycle. |
| G | UI state decoupling (`ChatViewState`) | done | Moved draft/unread/viewed ownership into `ChatViewState`; kept `ChatState` view APIs as compatibility delegates. |
| H | Provider/consumer migration | done | Migrated key service/panel/selection consumers to sub-state APIs and Listenable composition; preserved ChatState compatibility facade and runtime behavior. |
| I | Facade removal + hardening + final gate validation | done | Final hardening pass completed: `Chat` is no longer used as a notifier/listenable, remaining direct listener assumptions were migrated to sub-state listenables, and full frontend test suite passed. |
| J | Alias removal + test migration to `Chat` | done | Removed the temporary `ChatState` alias, migrated remaining test references to `Chat`, and drove `ChatState` references to zero in `frontend/lib` and `frontend/test`. |

---

## Execution Log

### Template

```text
Date:
Chunk:
Summary:
Files touched:
Tests run:
Result:
Follow-ups:
```

### 2026-02-16 — Chunk A

```text
Date: 2026-02-16
Chunk: A
Summary:
- Added compatibility-facade sub-state scaffolding under frontend/lib/models/chat_state/.
- Wired ChatState to instantiate and expose session/permission/settings/metrics/agent/conversation/view sub-states.
- Kept existing runtime behavior by delegating sub-state APIs back to current ChatState methods.
- Added notification fan-out from ChatState.notifyListeners() to all sub-state notifiers.
- Added focused scaffold tests for facade exposure, notification propagation, and delegated mutations.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_settings_state.dart
- frontend/lib/models/chat_state/chat_metrics_state.dart
- frontend/lib/models/chat_state/chat_agent_state.dart
- frontend/lib/models/chat_state/chat_conversation_state.dart
- frontend/lib/models/chat_state/chat_view_state.dart
- frontend/test/models/chat_substate_scaffolding_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_substate_scaffolding_test.dart test/models/chat_test.dart

Result:
- Pass (65 tests passed)

Follow-ups:
- Start Chunk B only after agreeing on session-state-machine boundary and teardown unification approach.
```

### 2026-02-16 — Chunk B

```text
Date: 2026-02-16
Chunk: B
Summary:
- Added explicit `SessionPhase` lifecycle state machine to ChatState/session facade.
- Enforced transition guards for message sending during transient/error phases.
- Consolidated session teardown to one idempotent `_teardownSession(...)` path and routed:
  - stopSession
  - clearSession
  - stream onDone handler
  - stream onError handler
- Preserved existing runtime interrupt behavior (interrupt clears working state but does not tear down active session).
- Added/updated lifecycle tests for phase transitions and teardown idempotency.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/test/models/chat_session_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/models/chat_test.dart test/services/chat_session_service_test.dart

Result:
- Pass (102 tests passed)

Follow-ups:
- Do not start Chunk C in this changeset.
```

### 2026-02-16 — Chunk C

```text
Date: 2026-02-16
Chunk: C
Summary:
- Moved permission queue behavior into `ChatPermissionState`:
  - enqueue/add permission requests
  - allow/deny responses
  - remove-by-toolUseId timeout cleanup
  - permission queue clear helpers
- Kept existing `ChatState` public permission methods as compatibility delegates to preserve call sites and runtime behavior.
- Wired permission flow to session/metrics/settings via sub-state APIs while preserving:
  - stopwatch pause/resume behavior around permission waits
  - permission mode sync behavior from updated permissions
  - ticket status transition callback (`EventHandler.handlePermissionResponse`)
  - desktop permission notifications
- Added direct facade test coverage for permission flow via `chat.permissions`.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/chat_state/chat_metrics_state.dart
- frontend/test/models/chat_substate_scaffolding_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_test.dart test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/services/chat_session_service_test.dart test/services/ticket_status_transition_test.dart test/widget/conversation_panel_test.dart

Result:
- Pass (131 tests passed)

Follow-ups:
- Do not start Chunk D in this changeset.
```

### 2026-02-16 — Chunk D

```text
Date: 2026-02-16
Chunk: D
Summary:
- Moved metrics/context logic ownership into `ChatMetricsState`:
  - in-turn output token accumulation
  - cumulative usage/model usage merge
  - context updates/resets
  - restore-from-meta usage/context/timing hydration
  - permission response timing updates
  - Claude working-time accumulation hook
- Kept `ChatState` metrics APIs (`updateContextFromUsage`, `addInTurnOutputTokens`, `updateCumulativeUsage`, `resetContext`, `restoreFromMeta`) as compatibility delegates.
- Updated `setWorking(false)` to route working-time accumulation through metrics state.
- Added focused facade test coverage for metrics/context delegation.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_metrics_state.dart
- frontend/test/models/chat_substate_scaffolding_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_substate_scaffolding_test.dart test/models/chat_test.dart test/models/chat_session_test.dart test/services/event_handler_test.dart test/services/stats_service_test.dart test/widget/project_stats_screen_test.dart

Result:
- Pass (200 tests passed)

Follow-ups:
- Do not start Chunk E in this changeset.
```

### 2026-02-16 — Chunk E

```text
Date: 2026-02-16
Chunk: E
Summary:
- Added `ChatPersistenceState` compatibility-facade coordinator under `frontend/lib/models/chat_state/`.
- Moved persistence ownership for project binding, debounced meta timer, and persistence operations from `ChatState` internals into the coordinator.
- Added per-target serialized queues and bounded retry/backoff for:
  - chat JSONL appends
  - chat meta saves
  - projects index updates (rename/session-id)
- Preserved runtime behavior by keeping `ChatState` persistence methods and delegating to `chat.persistence`.
- Added focused tests for:
  - retry on transient append/index write failures
  - serialized index writes across rapid consecutive renames
  - scaffold exposure of the `chat.persistence` facade.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_persistence_state.dart
- frontend/test/models/chat_test.dart
- frontend/test/models/chat_substate_scaffolding_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_test.dart test/models/chat_substate_scaffolding_test.dart test/models/chat_session_test.dart test/services/project_restore_service_test.dart
- ./frontend/run-flutter-test.sh test/services/event_handler_test.dart

Result:
- Pass (106 tests passed + 82 tests passed)

Follow-ups:
- Do not start Chunk F in this changeset.
```

### 2026-02-16 — Chunk F

```text
Date: 2026-02-16
Chunk: F
Summary:
- Added `SessionEventPipeline` (`frontend/lib/services/session_event_pipeline.dart`) to own per-session event routing state:
  - tool invocation/completion pairing
  - parentCallId -> conversation routing
  - resumed-agent callId -> sdkAgentId mapping
  - context-summary expectation and assistant-output turn tracking
  - streaming state via per-pipeline `StreamingProcessor`
- Refactored `EventHandler` to use session-local pipelines instead of shared global mutable maps.
- Added explicit pipeline lifecycle APIs:
  - `beginSession(chatId)` to start a fresh pipeline
  - `endSession(chatId)` to dispose per-session state
- Wired `ChatState` session lifecycle to pipeline lifecycle:
  - start session -> `eventHandler.beginSession(chatId)`
  - teardown -> `eventHandler.endSession(chatId)`
- Preserved existing runtime behavior and compatibility facade shape.
- Added focused isolation tests validating:
  - no subagent routing leakage across chats
  - no routing/tool pairing leakage across session restarts

Files touched:
- frontend/lib/services/session_event_pipeline.dart
- frontend/lib/services/event_handler.dart
- frontend/lib/services/event_handler_lifecycle.dart
- frontend/lib/services/event_handler_subagents.dart
- frontend/lib/models/chat.dart
- frontend/test/services/event_handler_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/services/event_handler_test.dart test/services/ticket_status_transition_test.dart test/models/chat_session_test.dart
- ./frontend/run-flutter-test.sh test/models/chat_test.dart test/services/chat_session_service_test.dart

Result:
- Pass (129 tests passed + 76 tests passed)

Follow-ups:
- Do not start Chunk G in this changeset.
```

### 2026-02-16 — Chunk G

```text
Date: 2026-02-16
Chunk: G
Summary:
- Moved UI-ephemeral view state ownership into `ChatViewState`:
  - `draftText`
  - unread count
  - viewed/unviewed flag
- Kept existing `ChatState` public view APIs as compatibility delegates:
  - `draftText` getter/setter
  - `hasUnreadMessages`
  - `unreadCount`
  - `markAsViewed()`
  - `markAsNotViewed()`
- Routed unread increments through `ChatViewState` while preserving runtime notification behavior.
- Added focused scaffold coverage validating `ChatState`/`ChatViewState` compatibility for draft and unread/viewed flows.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_view_state.dart
- frontend/test/models/chat_substate_scaffolding_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_substate_scaffolding_test.dart test/models/chat_test.dart test/models/selection_state_test.dart test/services/chat_session_service_test.dart
- ./frontend/run-flutter-test.sh test/widget/ticket_dispatch_integration_test.dart

Result:
- Pass (111 tests passed + 15 tests passed)

Follow-ups:
- Do not start Chunk H in this changeset.
```

### 2026-02-16 — Chunk H

```text
Date: 2026-02-16
Chunk: H
Summary:
- Migrated provider/consumer call sites in key services, selection state, and core panels to sub-state APIs while preserving ChatState compatibility:
  - session flow -> `chat.session.*`
  - permission flow -> `chat.permissions.*`
  - settings/model reads -> `chat.settings.*`
  - conversation selection/rename/entry routing -> `chat.conversations.*`
  - draft/unread/view state -> `chat.viewState.*`
  - metrics/agent reads in header/panel -> `chat.metrics.*` / `chat.agents.*`
- Updated panel listen patterns to merge targeted sub-state listenables instead of relying on broad ChatState rebuild behavior where possible.
- Preserved existing runtime behavior (no provider topology migration and no facade removal).
- Refreshed ChatState reference inventory for `frontend/lib` and `frontend/test`.

Files touched:
- frontend/lib/services/chat_session_service.dart
- frontend/lib/services/ticket_dispatch_service.dart
- frontend/lib/state/selection_state.dart
- frontend/lib/panels/chats_panel.dart
- frontend/lib/panels/worktree_panel.dart
- frontend/lib/panels/content_panel.dart
- frontend/lib/panels/agents_panel.dart
- frontend/lib/panels/conversation_panel.dart
- frontend/lib/panels/conversation_header.dart
- docs/chatstate-rewrite-execution.md

Tests run:
- ./frontend/run-flutter-test.sh test/models/selection_state_test.dart test/services/chat_session_service_test.dart test/widget/conversation_header_test.dart test/widget/conversation_panel_test.dart test/widget/ticket_dispatch_integration_test.dart
- ./frontend/run-flutter-test.sh test/widget/app_providers_test.dart test/widget/panel_merge_test.dart test/widget/conversation_header_test.dart test/widget/conversation_panel_test.dart test/models/selection_state_test.dart test/services/chat_session_service_test.dart test/widget/ticket_dispatch_integration_test.dart

Result:
- Pass (73 tests passed + 102 tests passed)
- Observed existing `safePumpAndSettle` timeout warnings in some widget tests; suites still passed.

Follow-ups:
- Do not start Chunk I in this changeset.
```

### 2026-02-16 — Chunk I (slice 1)

```text
Date: 2026-02-16
Chunk: I
Summary:
- Started facade-removal hardening by making `Chat` the canonical model type in `frontend/lib/models/chat.dart`.
- Added a temporary compatibility alias (`typedef ChatState = Chat`) to preserve existing behavior and call sites during migration.
- Migrated production type references from `ChatState` to `Chat` across `frontend/lib` services, state, panels, models, and testing helpers.
- Added/adjusted tests for this transition:
  - Added canonical/legacy constructor compatibility coverage in `chat_test.dart`.
  - Hardened a SessionEventPipeline isolation test against timestamp-ID collisions by ensuring unique chat IDs in test setup.
- Verified behavior with a broad regression suite spanning models/services/widgets.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/worktree.dart
- frontend/lib/models/agent.dart
- frontend/lib/models/chat_state/chat_agent_state.dart
- frontend/lib/models/chat_state/chat_conversation_state.dart
- frontend/lib/models/chat_state/chat_metrics_state.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_persistence_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/chat_state/chat_settings_state.dart
- frontend/lib/models/chat_state/chat_view_state.dart
- frontend/lib/panels/chats_agents_panel.dart
- frontend/lib/panels/chats_panel.dart
- frontend/lib/panels/conversation_header.dart
- frontend/lib/panels/conversation_panel.dart
- frontend/lib/panels/welcome_card.dart
- frontend/lib/panels/worktrees_chats_agents_panel.dart
- frontend/lib/panels/worktrees_chats_panel.dart
- frontend/lib/services/chat_session_service.dart
- frontend/lib/services/chat_title_service.dart
- frontend/lib/services/event_handler.dart
- frontend/lib/services/event_handler_lifecycle.dart
- frontend/lib/services/event_handler_subagents.dart
- frontend/lib/services/git_operations_service.dart
- frontend/lib/services/project_restore_service.dart
- frontend/lib/services/session_event_pipeline.dart
- frontend/lib/services/streaming_processor.dart
- frontend/lib/services/ticket_dispatch_service.dart
- frontend/lib/services/ticket_event_bridge.dart
- frontend/lib/state/selection_state.dart
- frontend/lib/testing/mock_data.dart
- frontend/lib/testing/replay_conversation_provider.dart
- frontend/test/models/chat_test.dart
- frontend/test/services/event_handler_test.dart
- docs/chatstate-rewrite-execution.md

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_test.dart test/models/worktree_test.dart test/models/selection_state_test.dart test/services/project_restore_service_test.dart test/services/chat_session_service_test.dart test/services/event_handler_test.dart test/widget/conversation_header_test.dart test/widget/conversation_panel_test.dart test/widget/panel_merge_test.dart test/widget/app_providers_test.dart

Result:
- Pass (282 tests passed)
- Observed existing `safePumpAndSettle` timeout warnings in some widget tests; suites still passed.

Follow-ups:
- Continue Chunk I with facade internals removal and final hard-gate validation; do not start Chunk J.
```

### 2026-02-16 — Chunk J

```text
Date: 2026-02-16
Chunk: J
Summary:
- Removed the temporary compatibility alias by deleting `typedef ChatState = Chat` from `frontend/lib/models/chat.dart`.
- Updated remaining `ChatState` references in `chat.dart` comments/log labels to `Chat`.
- Migrated all remaining `ChatState` references in `frontend/test` to `Chat`.
- Preserved runtime behavior; this chunk is type-name and test migration only.
- Refreshed ChatState inventory for `frontend/lib` and `frontend/test` after migration.

Files touched:
- frontend/lib/models/chat.dart
- frontend/test/models/chat_capabilities_test.dart
- frontend/test/models/chat_security_config_test.dart
- frontend/test/models/chat_security_notification_test.dart
- frontend/test/models/chat_session_test.dart
- frontend/test/models/chat_substate_scaffolding_test.dart
- frontend/test/models/chat_test.dart
- frontend/test/models/selection_state_test.dart
- frontend/test/models/worktree_test.dart
- frontend/test/services/chat_session_service_test.dart
- frontend/test/services/event_handler_test.dart
- frontend/test/services/project_restore_service_test.dart
- frontend/test/services/stats_service_test.dart
- frontend/test/services/ticket_status_transition_test.dart
- frontend/test/widget/conversation_header_test.dart
- frontend/test/widget/conversation_panel_test.dart
- frontend/test/widget/conversation_scroll_issues_test.dart
- frontend/test/widget/conversation_scroll_test.dart
- frontend/test/widget/project_stats_screen_test.dart
- frontend/test/widget/settings_screen_test.dart
- frontend/test/widget/ticket_dispatch_integration_test.dart
- frontend/test/widget/ticket_full_integration_test.dart
- docs/chatstate-rewrite-execution.md

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_capabilities_test.dart test/models/chat_security_config_test.dart test/models/chat_security_notification_test.dart test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/models/chat_test.dart test/models/selection_state_test.dart test/models/worktree_test.dart test/services/chat_session_service_test.dart test/services/event_handler_test.dart test/services/project_restore_service_test.dart test/services/stats_service_test.dart test/services/ticket_status_transition_test.dart test/widget/conversation_header_test.dart test/widget/conversation_panel_test.dart test/widget/conversation_scroll_issues_test.dart test/widget/conversation_scroll_test.dart test/widget/project_stats_screen_test.dart test/widget/settings_screen_test.dart test/widget/ticket_dispatch_integration_test.dart test/widget/ticket_full_integration_test.dart

Result:
- Pass (456 tests passed)
- Observed existing `safePumpAndSettle` timeout warnings in some widget tests; suites still passed.

Follow-ups:
- Do not start Chunk K in this changeset.
```

### 2026-02-16 — Chunk I (slice 2, completion)

```text
Date: 2026-02-16
Chunk: I
Summary:
- Completed facade hardening by migrating remaining production call sites from direct `Chat` facade methods to sub-state APIs:
  - session operations -> `chat.session.*`
  - settings operations -> `chat.settings.*`
  - conversation mutations -> `chat.conversations.*`
  - agent updates -> `chat.agents.*`
  - metrics/context updates -> `chat.metrics.*`
  - persistence writes/init -> `chat.persistence.*`
  - permission cleanup -> `chat.permissions.*`
- Updated in-place conversation mutation notifications in streaming/event flows to use conversation-level notifier hooks.
- Added `ChatSessionState.reset()` for parity so session reset flow is driven through sub-state API.
- Re-validated migration with targeted high-value service/model/widget tests.
- Re-ran ChatState inventory check: still zero references in `frontend/lib` and `frontend/test`.

Files touched:
- frontend/lib/main.dart
- frontend/lib/screens/main_screen.dart
- frontend/lib/panels/welcome_card.dart
- frontend/lib/panels/chats_agents_panel.dart
- frontend/lib/panels/worktrees_chats_agents_panel.dart
- frontend/lib/services/chat_session_service.dart
- frontend/lib/services/chat_title_service.dart
- frontend/lib/services/event_handler.dart
- frontend/lib/services/event_handler_lifecycle.dart
- frontend/lib/services/event_handler_subagents.dart
- frontend/lib/services/git_operations_service.dart
- frontend/lib/services/project_restore_service.dart
- frontend/lib/services/streaming_processor.dart
- frontend/lib/models/chat_state/chat_conversation_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/testing/replay_conversation_provider.dart
- docs/chatstate-rewrite-execution.md

Tests run:
- ./frontend/run-flutter-test.sh test/services/event_handler_test.dart test/services/project_restore_service_test.dart test/services/chat_session_service_test.dart test/models/chat_test.dart test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/widget/conversation_panel_test.dart test/widget/conversation_header_test.dart test/widget/panel_merge_test.dart test/widget/app_providers_test.dart test/widget/ticket_dispatch_integration_test.dart test/widget/ticket_full_integration_test.dart

Result:
- Pass (311 tests passed)
- Observed existing `safePumpAndSettle` timeout warnings in some widget tests; suites still passed.

Follow-ups:
- Chunk I complete. Do not start Chunk K in this changeset.
```

### 2026-02-16 — Chunk I (post-review hardening pass)

```text
Date: 2026-02-16
Chunk: I
Summary:
- Applied final hardening from review recommendations:
  - made `Chat` a non-notifier plain facade (removed listener forwarding)
  - removed global fan-out notify path and switched to targeted sub-state notifications
  - split subagent-conversation creation from agent mutation boundaries
  - migrated remaining production listener assumptions from `Chat` to sub-state listenables
  - migrated remaining `chat.addListener` test usage to relevant sub-state listeners
- Updated test resource tracking to support disposable non-ChangeNotifier objects (needed for `Chat` cleanup in tests).
- Revalidated inventory:
  - `ChatState` references in `frontend/lib` and `frontend/test`: zero
  - direct `Chat` listenable usage (`listenable: widget.chat/provider.chat`): zero

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_agent_state.dart
- frontend/lib/models/chat_state/chat_conversation_state.dart
- frontend/lib/models/chat_state/chat_metrics_state.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/chat_state/chat_settings_state.dart
- frontend/lib/models/chat_state/chat_view_state.dart
- frontend/lib/panels/chats_agents_panel.dart
- frontend/lib/panels/conversation_panel.dart
- frontend/lib/panels/worktree_panel_items.dart
- frontend/lib/panels/worktrees_chats_agents_panel.dart
- frontend/lib/screens/replay_demo_screen.dart
- frontend/lib/screens/settings_screen_agents.dart
- frontend/lib/services/stats_service.dart
- frontend/lib/testing/test_helpers.dart
- frontend/lib/widgets/status_bar.dart
- frontend/test/models/chat_security_config_test.dart
- frontend/test/models/chat_session_test.dart
- frontend/test/models/chat_substate_scaffolding_test.dart
- frontend/test/models/chat_test.dart
- frontend/test/services/project_restore_service_test.dart
- docs/chatstate-rewrite-execution.md

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_security_config_test.dart test/services/project_restore_service_test.dart test/widget/conversation_panel_test.dart test/models/chat_session_test.dart
- ./frontend/run-flutter-test.sh test/models/chat_test.dart test/models/chat_substate_scaffolding_test.dart test/widget/panel_merge_test.dart test/widget/app_providers_test.dart test/integration/navigation_integration_test.dart test/integration/app_launch_test.dart
- ./frontend/run-flutter-test.sh

Result:
- Pass (59 tests passed + 125 tests passed + 2773 tests passed, 2 skipped)
- Existing `safePumpAndSettle` timeout warnings remain in some widget/integration tests; suites still passed.

Follow-ups:
- No additional Chunk I defects found in this pass.
```

---

## Decision Log

Record architecture decisions that affect future chunks.

### Template

```text
Decision:
Date:
Rationale:
Alternatives considered:
Consequences:
```

### 2026-02-16 — Chunk B interrupt semantics

```text
Decision:
Keep interrupt as a non-teardown operation while introducing SessionPhase/teardown unification.
Date:
2026-02-16
Rationale:
Current runtime behavior expects interrupt to stop generation but keep session context alive for continued conversation.
Alternatives considered:
Treat interrupt as a teardown path that ends the session.
Consequences:
Session teardown unification applies to stop/stream-end/error/clear paths; interrupt continues to be active-session preserving.
```

### 2026-02-16 — Chunk C compatibility boundary

```text
Decision:
Keep `ChatState` permission APIs (`addPendingPermission`, `allowPermission`, `denyPermission`, etc.) as delegates while moving logic ownership to `ChatPermissionState`.
Date:
2026-02-16
Rationale:
Preserves existing runtime behavior and broad call sites during staged migration.
Alternatives considered:
Immediate call-site migration to `chat.permissions.*` across services/widgets/tests.
Consequences:
Chunk C remains atomic and behavior-preserving, while enabling later provider/consumer migration without another permission-flow rewrite.
```

### 2026-02-16 — Chunk D compatibility boundary

```text
Decision:
Keep `ChatState` metrics/context APIs as delegates while moving implementation ownership to `ChatMetricsState`.
Date:
2026-02-16
Rationale:
Preserves behavior and existing service/widget call sites while establishing sub-state ownership for usage/context/timing logic.
Alternatives considered:
Immediate migration of all metrics call sites to `chat.metrics.*`.
Consequences:
Chunk D remains atomic; provider/consumer migration can proceed later without redoing metrics internals.
```

### 2026-02-16 — Chunk E compatibility boundary

```text
Decision:
Keep `ChatState` persistence APIs (`initPersistence`, `persistStreamingEntry`, `persistToolResult`, etc.) as delegates while moving persistence coordination ownership to `ChatPersistenceState`.
Date:
2026-02-16
Rationale:
Preserves behavior and existing call sites while introducing serialized write queues and retry semantics in one isolated chunk.
Alternatives considered:
Immediate migration of all persistence call sites to `chat.persistence.*`.
Consequences:
Chunk E remains atomic and behavior-preserving, and later provider/consumer migration can move call sites without reworking persistence internals.
```

### 2026-02-16 — Chunk F compatibility boundary

```text
Decision:
Keep `EventHandler.handleEvent(chat, event)` API stable while introducing per-session `SessionEventPipeline` instances under the hood.
Date:
2026-02-16
Rationale:
Preserves existing call sites and runtime flow while eliminating shared mutable routing state across chats/sessions.
Alternatives considered:
Immediate migration to a new public event-pipeline API with direct consumer ownership.
Consequences:
Chunk F remains atomic and behavior-preserving; later chunks can migrate providers/consumers without reworking event ordering or routing internals.
```

### 2026-02-16 — Chunk G compatibility boundary

```text
Decision:
Keep `ChatState` view-facing APIs stable while moving storage/mutation ownership of draft/unread/viewed to `ChatViewState`.
Date:
2026-02-16
Rationale:
Preserves runtime behavior and broad existing call sites while isolating UI-ephemeral state into the intended sub-state.
Alternatives considered:
Immediate migration of all call sites to `chat.viewState.*` with removal of `ChatState` compatibility methods.
Consequences:
Chunk G remains atomic and behavior-preserving; provider/consumer migration in Chunk H can proceed without additional view-state internals work.
```

### 2026-02-16 — Chunk H migration boundary

```text
Decision:
Migrate high-impact provider/consumer call sites to sub-state APIs without changing provider topology or removing the ChatState compatibility facade.
Date:
2026-02-16
Rationale:
Reduces rebuild coupling and direct god-object usage while preserving runtime behavior and avoiding cross-chunk risk from provider graph changes.
Alternatives considered:
Immediate provider topology migration and facade removal in the same chunk.
Consequences:
Chunk H remains atomic and behavior-preserving; Chunk I can focus on facade removal/hardening and final gate validation.
```

### 2026-02-16 — Chunk I canonical-type boundary (slice 1)

```text
Decision:
Introduce `Chat` as the canonical production type and retain `ChatState` only as a temporary compatibility alias during facade removal.
Date:
2026-02-16
Rationale:
Decouples production consumers from the legacy facade name while preserving runtime behavior and keeping migration risk low.
Alternatives considered:
Attempt full ChatState facade deletion and all remaining internal rewrites in one step.
Consequences:
Production ChatState references are reduced to the compatibility layer in `chat.dart`; remaining Chunk I work can now focus on removing the alias/facade internals and validating hard gates.
```

### 2026-02-16 — Chunk J alias-removal boundary

```text
Decision:
Remove the temporary `ChatState` compatibility alias and migrate all remaining tests to `Chat` in one atomic step.
Date:
2026-02-16
Rationale:
Eliminates the last code-level dependency on the legacy type name and validates that production and tests compile/run directly on `Chat`.
Alternatives considered:
Keep the alias longer and defer test migration to a later chunk.
Consequences:
`ChatState` references are now zero in `frontend/lib` and `frontend/test`; further rewrite work can focus on architectural hard gates rather than naming compatibility.
```

### 2026-02-16 — Chunk I completion boundary (slice 2)

```text
Decision:
Complete Chunk I by migrating remaining production consumer calls off direct `Chat` facade methods to sub-state APIs while preserving runtime behavior.
Date:
2026-02-16
Rationale:
Finalizes the staged facade hardening goal with minimal risk: no behavioral model changes, but clearer ownership boundaries and reduced god-object coupling in production call paths.
Alternatives considered:
Keep production direct `Chat` method calls and defer migration to a later chunk.
Consequences:
Chunk I is complete and validated by targeted regression tests; remaining work (if any) is beyond the defined chunk plan.
```

### 2026-02-16 — Post-review findings remediation

```text
Date: 2026-02-16
Chunk: I/J follow-up (review remediation)
Summary:
- Stabilized the `Chat`/`_ChatCore` split by wiring `_ChatCore` callbacks through an attached `Chat` facade.
- Added missing compatibility delegation on `Chat` so existing runtime/test call-sites continue to route through sub-state owners.
- Migrated high-noise tests to sub-state access where practical (`chat_test`, `event_handler_test`) and kept compatibility for the remaining suite.
- Updated production direct accesses still bypassing sub-states (`worktree` usage aggregation and selection lazy-load guard).
- Re-ran focused and full frontend test suites to confirm behavior parity.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/chat_state/chat_persistence_state.dart
- frontend/lib/models/worktree.dart
- frontend/lib/state/selection_state.dart
- frontend/test/models/chat_test.dart
- frontend/test/services/event_handler_test.dart
- frontend/test/widget/ticket_full_integration_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_test.dart
- ./frontend/run-flutter-test.sh test/services/event_handler_test.dart test/services/project_restore_service_test.dart test/services/chat_session_service_test.dart test/models/chat_test.dart test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/widget/conversation_panel_test.dart test/widget/conversation_header_test.dart test/widget/panel_merge_test.dart test/widget/app_providers_test.dart test/widget/ticket_dispatch_integration_test.dart test/widget/ticket_full_integration_test.dart
- ./frontend/run-flutter-test.sh

Result:
- Pass (focused suite: 311 tests; full suite: 2773 passed, 2 skipped)

Follow-ups:
- Complete remaining gate work to remove `Chat` compatibility notifier/delegates once provider migration fully isolates sub-state listeners.
```

### 2026-02-16 — Final compatibility-facade cleanup + logging hardening

```text
Date: 2026-02-16
Chunk: Final cleanup pass (post J)
Summary:
- Removed the remaining `Chat` compatibility facade surface (delegating getters/methods), leaving `Chat` as a plain container over sub-states.
- Updated production/test call sites to use sub-state APIs (`session`, `permissions`, `settings`, `metrics`, `persistence`, `agents`, `conversations`, `viewState`).
- Addressed review finding #1 by making `_NestedChatOnlyItem` reactive to conversation-state updates via `ListenableBuilder(Listenable.merge([chat.conversations]))`.
- Addressed review finding #2 by simplifying `EventHandler.clearChat` to `clearChat(String chatId)` and removing dead params/suppression.
- Addressed review finding #3 by removing cross-substate notifications from `ChatPermissionState` and moving orchestration into `ChatSessionService` with explicit `allowPermission`/`denyPermission` flows.
- Replaced fallback persistence `debugPrint` error reporting with structured `LogService.instance.error(...)` metadata logging in `ChatPersistenceState`.
- Added explicit session refresh API (`chat.session.notifyPermissionQueueChanged()`) so services do not call `notifyListeners()` directly.
- Added widget regression coverage for nested chat rename reactivity in `panel_merge_test.dart`.

Files touched:
- frontend/lib/models/chat.dart
- frontend/lib/models/chat_state/chat_agent_state.dart
- frontend/lib/models/chat_state/chat_permission_state.dart
- frontend/lib/models/chat_state/chat_persistence_state.dart
- frontend/lib/models/chat_state/chat_session_state.dart
- frontend/lib/models/worktree.dart
- frontend/lib/panels/conversation_panel.dart
- frontend/lib/panels/worktrees_chats_panel.dart
- frontend/lib/services/chat_session_service.dart
- frontend/lib/services/event_handler.dart
- frontend/lib/services/project_restore_service.dart
- frontend/lib/services/stats_service.dart
- frontend/test/models/chat_capabilities_test.dart
- frontend/test/models/chat_security_config_test.dart
- frontend/test/models/chat_security_notification_test.dart
- frontend/test/models/chat_session_test.dart
- frontend/test/models/chat_substate_scaffolding_test.dart
- frontend/test/models/selection_state_test.dart
- frontend/test/services/chat_session_service_test.dart
- frontend/test/services/project_restore_service_test.dart
- frontend/test/services/stats_service_test.dart
- frontend/test/widget/conversation_header_test.dart
- frontend/test/widget/conversation_panel_test.dart
- frontend/test/widget/conversation_scroll_issues_test.dart
- frontend/test/widget/panel_merge_test.dart
- frontend/test/widget/project_stats_screen_test.dart
- frontend/test/widget/settings_screen_test.dart
- frontend/test/widget/ticket_dispatch_integration_test.dart

Tests run:
- ./frontend/run-flutter-test.sh test/models/chat_security_config_test.dart test/models/chat_security_notification_test.dart test/models/chat_capabilities_test.dart test/models/chat_session_test.dart test/models/chat_substate_scaffolding_test.dart test/models/selection_state_test.dart test/services/chat_session_service_test.dart test/services/project_restore_service_test.dart test/services/stats_service_test.dart test/widget/conversation_header_test.dart test/widget/conversation_panel_test.dart test/widget/conversation_scroll_issues_test.dart test/widget/project_stats_screen_test.dart test/widget/settings_screen_test.dart test/widget/panel_merge_test.dart test/widget/ticket_dispatch_integration_test.dart

Result:
- Pass (227 tests passed)

Follow-ups:
- None for this cleanup pass; remaining analyzer warnings are pre-existing and out of scope for this rewrite chunk sequence.
```

---

## Risk Register

| Risk | Severity | Mitigation | Owner | Status |
|---|---|---|---|---|
| Event ordering regressions during pipeline swap | High | Add focused pipeline + integration tests before migration | Codex | open |
| Persistence regressions under concurrent writes | High | Queue writes per file path and inject failure tests | Codex | open |
| Scope underestimation due broad ChatState references | Medium | Maintain file inventory and burn-down each chunk | Codex | open |

---

## File Inventory (to be updated during execution)

Track remaining production/test references to `ChatState` until zero in production.

- Inventory snapshot date: 2026-02-16 (post-Chunk I completion)
- Inventory command:
  - `rg --line-number "\bChatState\b" frontend/lib`
  - `rg --line-number "\bChatState\b" frontend/test`
- Production refs remaining: **0 references across 0 files**
- Test refs remaining: **0 references across 0 files**

### Production (`frontend/lib`) reference counts

- None.

### Test (`frontend/test`) reference counts

- None.
