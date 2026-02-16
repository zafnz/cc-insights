# ChatState Rewrite Proposal 1 (Merged Plan)

**Date:** 2026-02-16  
**Status:** Proposal  
**Intent:** Merge the strongest parts of:

- `docs/code-review-report-2026-02-16-chatstate-rewrite.md` (concrete decomposition and migration mechanics)
- `docs/code-review-report-2026-02-16-chatstate-subsystem-rewrite.md` (hard architecture constraints and failure-mode fixes)

---

## Executive Summary

`ChatState` is currently both data model and execution engine. This proposal replaces that with a **chat subsystem** composed of focused state objects and controllers, while preserving incremental delivery.

Key decisions:

1. Keep `ChangeNotifier + Provider` (no state-management framework switch).
2. Split chat concerns into sub-states with explicit ownership.
3. Move cross-concern orchestration to services/controllers.
4. Enforce non-negotiable architecture gates so we do not end with a thinner god class.

---

## Problem Statement

`frontend/lib/models/chat.dart` currently combines:

- Session/transport lifecycle
- Permission workflow and timing behavior
- Conversation storage and selection
- Agent/subagent runtime state
- Usage/context/timing aggregation
- Persistence side effects
- UI-ephemeral concerns (`draftText`, viewed flags)

This causes:

- High coupling and difficult testing
- Rebuild over-notification from one monolithic notifier
- Duplicated cleanup paths and lifecycle drift
- Weak persistence durability (fire-and-forget behavior)
- Routing risk from shared mutable event state

---

## Target Architecture

## 1) Chat aggregate and sub-states

Introduce a plain `Chat` aggregate that owns sub-state instances.

```text
Chat (plain aggregate, disposable)
├── ChatConversationState   (ChangeNotifier)
├── ChatSessionState        (ChangeNotifier)
├── ChatPermissionState     (ChangeNotifier)
├── ChatSettingsState       (ChangeNotifier)
├── ChatMetricsState        (ChangeNotifier)
├── ChatAgentState          (ChangeNotifier)
└── ChatViewState           (ChangeNotifier, UI-ephemeral only)
```

### Ownership boundaries

- `ChatConversationState`
  - Owns conversation entries, selected conversation id, unread counters.
  - Does not own UI draft text.
- `ChatSessionState`
  - Owns session lifecycle state and transport handles.
  - No direct persistence writes.
- `ChatPermissionState`
  - Owns permission queue state only.
  - Timing metrics updates delegated via orchestrator.
- `ChatSettingsState`
  - Owns model/security/ACP/reasoning settings.
- `ChatMetricsState`
  - Owns usage, context, and timing aggregates.
- `ChatAgentState`
  - Owns active agents and agent removal/missing status.
- `ChatViewState`
  - Owns `draftText`, viewed flags, and other UI-ephemeral values.

## 2) Service/controller layer

- `ChatSessionService` becomes the primary orchestrator for multi-state operations.
- Add `ChatPersistenceCoordinator` for all chat write operations.
- Add `SessionEventPipeline` as a **per-session** event-routing/pairing instance.

## 3) Event architecture rule

- `EventHandler` may remain as a dispatcher/factory, but mutable pairing/routing state must be in `SessionEventPipeline` tied to one session lifetime.
- No global cross-chat maps for tool pairing or routing.

## 4) Persistence architecture rule

- No fire-and-forget as default for critical writes.
- Serialized write queues per path.
- Explicit error handling and retry policy.
- Writes are observable to callers where user-visible consistency depends on them.

---

## What Stays The Same

- Provider-based dependency wiring.
- Existing transport abstraction (`EventTransport` and backend integrations).
- High-level user features (session start, permissions, subagents, usage display).

---

## Non-Negotiable Constraints (Architecture Gates)

Rewrite is not complete unless all are true:

1. `ChatState` no longer directly owns transport subscriptions, timers, and persistence writes.
2. Event routing/pairing mutable state is per-session, never process-global.
3. UI-ephemeral state is removed from domain/runtime chat state.
4. Session teardown has exactly one idempotent implementation path.
5. Chat persistence writes are serialized and failure-observable.
6. Existing behavior parity is preserved (resume, permissions, subagents, streaming, usage/timing).

---

## Large Implementation Chunks

## Chunk A: Introduce Chat Aggregate + Sub-States

- Create sub-state classes and move fields/methods by ownership.
- Keep temporary compatibility shims in `ChatState` to reduce immediate breakage.
- Ensure each sub-state is independently unit-testable.

## Chunk B: Session Lifecycle Consolidation

- Move start/send/interrupt/stop/reset into `ChatSessionState` + orchestrator flows.
- Replace duplicated cleanup branches with one teardown path.
- Add explicit lifecycle enum/state machine.

## Chunk C: Permission Flow Isolation

- Move queueing and allow/deny/timeout mechanics into `ChatPermissionState`.
- Keep stopwatch/timing coordination in service layer (not inside queue object).

## Chunk D: Metrics and Context Extraction

- Move cumulative usage, in-turn tokens, timing stats, and context integration into `ChatMetricsState`.
- Keep calculations pure and deterministic.

## Chunk E: Persistence Reliability Upgrade

- Introduce `ChatPersistenceCoordinator`.
- Convert entry/meta/session-id/rename writes to serialized queued writes.
- Define retry and surfaced-failure semantics.

## Chunk F: Event Pipeline Re-Architecture

- Replace shared tracking maps with `SessionEventPipeline` instances.
- Scope streaming state, tool pairing, and routing cleanup to session lifecycle.

## Chunk G: UI State Decoupling

- Move `draftText` and viewed flags to `ChatViewState`.
- Update panels/widgets to watch only required sub-states.

## Chunk H: Provider and Consumer Migration

- Update provider graph to expose selected chat and sub-states cleanly.
- Migrate major consumers (`ConversationPanel`, `ConversationHeader`, `ChatsPanel`, `AgentsPanel`, `SelectionState`, restore flows).

## Chunk I: Compatibility Removal and Hardening

- Remove temporary shims/deprecated pass-through methods.
- Enforce architecture gates in tests and code review checklist.

---

## Provider/Consumer Strategy

- Continue exposing selected chat from `SelectionState`.
- Provide sub-states via focused providers/selectors so widgets rebuild only for relevant concerns.
- Avoid broad `ListenableBuilder` on aggregate chat object when a narrower sub-state is sufficient.

---

## Scope and Impact

Expected impact is **substantial**, not moderate:

- Core code paths: chat model, event handling, session orchestration, persistence.
- Consumer updates across panels and state classes.
- Broad test updates due to API boundary movement.

Estimated touch surface: **30-50 files** across `frontend/lib` and `frontend/test`.

---

## Testing Strategy

- Add direct unit tests per sub-state (conversation, session, permission, settings, metrics, agents, view-state).
- Add session pipeline tests for routing/pairing isolation by session.
- Preserve/extend integration tests for:
  - permission request/response flows
  - session resume
  - streaming finalization
  - usage/timing rollups
  - chat close/reset semantics

---

## Risks and Mitigations

- Risk: Migration complexity and temporary dual-path behavior.
  - Mitigation: Keep compatibility layer only during migration and remove by Chunk I.
- Risk: Event ordering regressions.
  - Mitigation: Session pipeline tests and lifecycle boundary assertions.
- Risk: Persistence regressions.
  - Mitigation: Queue-based write tests and fault-injection tests.

---

## Final Recommendation

Adopt this merged plan.

It combines:

- The concrete decomposition and migration practicality of the first plan.
- The architectural rigor and anti-regression gates of the subsystem rewrite plan.

This is the most credible route to eliminate the ChatState god object without a full application rewrite.
