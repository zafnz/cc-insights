# ChatState Rewrite Test Strategy

## Objectives

1. Prevent behavior regressions during decomposition.
2. Validate new boundaries (sub-states, orchestrator, pipeline, persistence).
3. Keep confidence high while changing core flow.

---

## Test Layers

## Layer 1: Sub-state unit tests

Add focused tests per sub-state:

- `ChatSessionState`
- `ChatPermissionState`
- `ChatSettingsState`
- `ChatMetricsState`
- `ChatAgentState`
- `ChatConversationState`
- `ChatViewState`

Required checks:

- state transitions
- notification behavior
- invariants
- edge conditions

## Layer 2: Pipeline tests

Add dedicated tests for `SessionEventPipeline`:

- tool invocation/completion pairing
- routing by parent call id
- streaming lifecycle behavior
- cleanup on session end
- no cross-session contamination

## Layer 3: Orchestration tests

For `ChatSessionService`:

- start/stop/reset flows
- permission allow/deny flows
- timing interactions (pause/resume)
- lifecycle + persistence coordination

## Layer 4: Integration/widget tests

Retain and update high-value tests:

- conversation flow with permissions
- session resume behavior
- subagent routing and display
- usage/timing display behavior
- unread + draft behavior

---

## Test Execution Rules

Use project standard runner:

- `./frontend/run-flutter-test.sh`

Do not use raw `flutter test` directly.

For each chunk:

1. Run targeted tests first.
2. Run broader related suite if targeted tests pass.
3. Record command set and results in execution log.

---

## Minimum Chunk Exit Criteria

A chunk is not complete unless:

1. New/updated tests for changed behavior are present.
2. Targeted tests pass.
3. No known regressions are introduced.
4. Execution tracker is updated.

