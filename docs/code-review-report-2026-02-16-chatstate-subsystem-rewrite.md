# ChatState Subsystem Rewrite Proposal — 2026-02-16

## Context

`frontend/lib/models/chat.dart` has grown into a multi-concern subsystem rather than a state holder. It currently mixes:

- Session lifecycle and transport wiring
- Permission queueing and user-response timing
- Conversation storage and subagent routing
- Usage/context/timing aggregation
- Persistence side effects
- UI-ephemeral state (`draftText`, viewed/unread behavior)

This proposal defines a rewrite of the **chat subsystem** (not the full app) to remove the God-object failure mode and establish hard ownership boundaries.

---

## Decision

This should be treated as a **significant subsystem rewrite**, not a light refactor.

Reason:

- The current API shape encourages direct cross-layer mutation.
- There are multiple duplicated cleanup and lifecycle paths.
- Event routing state is split across global maps and chat-local fields.
- Persistence and runtime flow are interleaved, making failure handling weak.

If we do not change the subsystem boundaries, we will preserve the same design risks even after extraction work.

---

## Rewrite Scope

In scope:

- `frontend/lib/models/chat.dart`
- `frontend/lib/services/event_handler.dart` and part files
- `frontend/lib/services/chat_session_service.dart` (contract realignment)
- UI call sites that currently mutate `ChatState` internals directly
- Tests that assume current monolithic behavior

Out of scope:

- Project/worktree domain model redesign
- Global app state architecture rewrite
- Complete Provider strategy changes across unrelated features

---

## Architecture Goals

1. `ChatState` is no longer the execution engine.
2. Side effects (transport, timers, file writes, notifications) are isolated.
3. Session-scoped runtime state is not shared through global mutable maps.
4. UI state is separated from domain/runtime state.
5. Teardown is single-path and idempotent.
6. Persistence writes are durable, serialized, and observable.

---

## Target Architecture

### 1) ChatAggregate (domain + runtime facade)

Replace monolithic `ChatState` internals with a composition root (`ChatAggregate` conceptually), exposed through a compatibility facade initially.

Responsibilities:

- Expose stable read model for UI (`data`, selected conversation, status flags)
- Forward commands to owned subsystems
- Emit one notification stream for UI (`ChangeNotifier` compatibility during migration)

Non-responsibilities:

- Direct transport lifecycle management
- Direct file I/O
- Internal event routing map ownership

### 2) SessionLifecycle subsystem

Owns:

- Start/send/interrupt/stop/reset lifecycle
- Transport subscription management
- Capability capture and server-reported sync
- Single teardown path

Hard rule:

- Session state transitions are explicit (`idle`, `starting`, `active`, `stopping`, `ended`, `errored`).

### 3) PermissionFlow subsystem

Owns:

- Pending permission queue
- allow/deny/timeout behavior
- Stopwatch pause/resume policy for permission waits
- Permission-response timing metrics

Hard rule:

- Permission queue state is isolated and testable without active transport.

### 4) ConversationStore subsystem

Owns:

- Primary/subagent conversation entry append/update
- Subagent agent map and routing lookup
- Selection within a chat
- Unread/viewed counters

Hard rule:

- Conversation mutation APIs are explicit; no external in-place map/list mutation.

### 5) UsageAndContext subsystem

Owns:

- In-turn token accumulation
- Cumulative usage merge and model usage derivation
- Context window/autocompact tracking
- Claude/user timing stats

Hard rule:

- Usage/timing state updates do not touch transport or persistence directly.

### 6) ChatPersistence subsystem

Owns:

- Entry append scheduling and durability policy
- Chat meta save/debounce policy
- Session-id and rename persistence
- Retry/queue behavior and failure reporting

Hard rule:

- All chat writes use serialized queues per target path.

### 7) SessionEventPipeline (per-session instance)

Replace shared `EventHandler` mutable tracking maps with a per-session pipeline object.

Owns:

- Tool invocation/completion pairing for that session
- Parent call routing for that session
- Streaming state for that session
- Cleanup for exactly that session

Hard rule:

- No cross-chat map state in singleton handler for routing correctness.

---

## Large Rewrite Chunks

## Chunk A: Session Core Rewrite

Deliverables:

- Extract lifecycle logic from `ChatState` into `SessionLifecycle`
- Consolidate all teardown branches into one idempotent shutdown path
- Move transport/subscription ownership out of `ChatState`

Outcome:

- Session bugs become local to one subsystem.
- Start/stop/interrupt/reset semantics become deterministic.

## Chunk B: Permission + Timing Isolation

Deliverables:

- Build `PermissionFlow` with queue and response timing APIs
- Remove permission queue mutation from `ChatState`
- Wire UI dialogs to `PermissionFlow` command methods

Outcome:

- Permission behavior becomes independently testable and less fragile.

## Chunk C: Conversation Runtime Separation

Deliverables:

- Build `ConversationStore` for entries, selection, unread, subagent linkage
- Stop direct entry/pairing mutations from external services
- Route all conversation writes through store commands

Outcome:

- Conversation consistency and unread/viewed behavior are centralized.

## Chunk D: Usage/Context Model Rewrite

Deliverables:

- Build `UsageAndContext` module
- Move in-turn/cumulative merge logic and timing stats logic out of `ChatState`
- Expose read-only value objects to UI

Outcome:

- Usage math becomes isolated and easier to validate.

## Chunk E: Persistence Reliability Rewrite

Deliverables:

- Move chat persistence operations into `ChatPersistence`
- Queue all writes; remove fire-and-forget patterns where data loss is possible
- Define failure semantics (retry policy + surfaced error state)

Outcome:

- Persistence behavior is predictable under load and crash scenarios.

## Chunk F: Event Pipeline Re-architecture

Deliverables:

- Replace singleton map-based `EventHandler` state with per-session `SessionEventPipeline`
- Keep a thin process-wide dispatcher only for non-session global concerns
- Move streaming lifecycle ownership to the per-session pipeline

Outcome:

- Eliminates cross-chat contamination risk and stale routing maps.

## Chunk G: UI State Decoupling

Deliverables:

- Move `draftText` and similar ephemeral state out of domain/runtime model
- Introduce `ChatViewState` (or equivalent) tied to selection/UI layer
- Update panels to read/write UI state from view-state provider

Outcome:

- Domain state is no longer polluted by input-widget concerns.

## Chunk H: API Stabilization + Backward-Compatibility Cleanup

Deliverables:

- Keep a compatibility `ChatState` facade while internals migrate
- Deprecate direct mutation accessors
- Remove temporary shims after call sites and tests are fully migrated

Outcome:

- Allows staged rollout without freezing feature work.

---

## Hard Acceptance Gates

The rewrite is considered complete only when all gates are true:

1. `ChatState` no longer owns transport, subscriptions, timers, or file writes.
2. Session routing/pairing state is per-session, not shared globally.
3. No UI-ephemeral fields remain on domain/runtime chat model.
4. There is exactly one teardown path for active session cleanup.
5. Chat persistence writes are serialized and observable.
6. Existing user-facing chat behavior is preserved (session resume, permissions, subagents, streaming, usage display).

---

## Risk and Tradeoffs

Primary risks:

- Temporary dual-path complexity during migration
- Regression risk in event ordering/streaming finalization
- Test churn due to API boundary changes

Tradeoff:

- Higher near-term change cost in exchange for lower long-term defect rate and much better testability.

Not doing this rewrite keeps shipping velocity superficially high but preserves a high-risk defect surface.

---

## Proposed End State for ChatState

After rewrite, `ChatState` should be either:

- A thin compatibility facade over composed subsystems, or
- Replaced with a smaller aggregate class with a narrow contract.

Target characteristics:

- Small API surface
- No hidden side effects
- No business logic spanning multiple subsystems
- Purely orchestration/read-model responsibilities

If `ChatState` still directly handles lifecycle + permissions + persistence + usage logic at the end, the rewrite has failed.
