# Frontend Code Review Report — 2026-02-16

Thorough review of the frontend codebase covering state management, services, widgets/panels, models/data flow, and app structure.

---

## Critical Issues

### 1. ChatState is a God Object

**File:** `frontend/lib/models/chat.dart` (2150+ lines)

ChatState has 58+ fields, 100+ methods, and manages 10+ concerns: session lifecycle, permissions, usage tracking, persistence, context management, agent management, UI state, timing stats, model sync, and conversation selection. It directly depends on 7+ services via imports.

This makes it extremely hard to test in isolation. It should be decomposed into focused classes (`ChatSessionLifecycle`, `ChatPermissionManager`, `ChatUsageTracker`, `ChatPersistence`) with ChatState as a lightweight coordinator.

### 2. Unsafe Concurrent Writes in CostTrackingService

**File:** `frontend/lib/services/cost_tracking_service.dart:115-119`

Uses `File.writeAsString` with `FileMode.append` — the exact same pattern that corrupted JSONL persistence data. `PersistenceService` already has the fix (serialized `_writeQueues` map), but `CostTrackingService` doesn't use it. Can corrupt cost tracking data under concurrent async writes.

### 3. Timer Resource Leak in StreamingProcessor

**File:** `frontend/lib/services/streaming_processor.dart:181-189`

`_notifyTimer` is a `Timer.periodic(50ms)` that calls `notifyListeners()` on the streaming chat. If an exception occurs during delta handling before `_onMessageStop()` is called, the timer is never cancelled. This results in the timer calling `notifyListeners()` on a potentially disposed/invalid chat reference.

### 4. Zombie Processes in GitService

**File:** `frontend/lib/services/git_service.dart:1068-1278`

`Process.run(...).timeout(_mergeTimeout)` is used in `merge()`, `rebase()`, and `squashCommits()`. On timeout, the spawned git process continues running and is never killed. Should use `Process.start()` with `proc.kill()` on timeout instead.

---

## High Severity

### 5. BackendService is a Dual God Class

**File:** `frontend/lib/services/backend_service.dart:39-95`

Maintains parallel tracking structures for two backend types: `_backends` + `_agentBackends`, `_errors` + `_agentErrors`, `_starting` + `_agentStarting`, etc. `dispose()` needs to clean up 8+ separate state maps. Should be split into two focused services with a facade.

### 6. EventHandler Has Unsynchronized Tracking Maps

**File:** `frontend/lib/services/event_handler.dart:51-65`

Six separate tracking maps (`_toolCallIndex`, `_agentIdToConversationId`, `_toolUseIdToAgentId`, etc.) with no validation in `clearChat()`. If `_resolveConversationId()` returns a stale ID, entries silently go to the wrong conversation. Should use a unified `ConversationState` structure.

### 7. Mutable Collections Break hashCode Contract

**File:** `frontend/lib/models/output_entry.dart:487, 609-615`

`ToolUseOutputEntry.toolInput` is `final Map<String, dynamic>` but contents are mutated in-place by `event_handler.dart:177-179` (`.clear()` + `.addAll()`). `toolInput` is used in `hashCode` calculation. If the entry is stored in a Set/HashMap before mutation, lookup invariants break.

### 8. SelectionState Mixes Concerns

**File:** `frontend/lib/state/selection_state.dart:259-282`

`closeChat()` handles session stopping, file deletion, worktree mutation, and persistence routing. SelectionState should only manage what is selected, not how to close/delete. Should delegate to a `ChatManagementService`.

### 9. LogService.dispose() Doesn't Await Sink Close

**File:** `frontend/lib/services/log_service.dart:300-306`

`disableFileLogging()` is async but NOT awaited in `dispose()`. The sink may still be writing when the app exits, causing recent logs to be lost.

---

## Medium Severity

### 10. SettingsService File Watch Race Condition

**File:** `frontend/lib/services/settings_service.dart:687-742`

Uses an arbitrary 1-second `_selfWriting` flag delay to prevent re-reading its own writes. If the disk is slow, `_onFileChanged()` fires before the flag resets and reads partially-written data. Should use a completion token or file locking.

### 11. PersistenceService Write Queue Error Swallowing

**File:** `frontend/lib/services/persistence_service.dart:384-421`

`_writeQueues[path] = current.catchError(...)` logs the error but continues the chain, while `return current` returns the original future without the error handler. Callers get uncaught errors while the queue silently continues.

### 12. Massive Widget Files Lack Decomposition

Large StatefulWidgets that should be broken into smaller, focused widget classes:

| File | Lines | Issue |
|------|-------|-------|
| `panels/create_worktree_panel.dart` | 1748 | Single StatefulWidget with 800+ line build method |
| `widgets/delete_worktree_dialog.dart` | 1384 | 11 action states, 800+ lines of workflow logic |
| `widgets/commit_dialog.dart` | 1234 | Mixed file list, diff view, and message editor |

All three rely heavily on `_build*()` helper methods returning widgets instead of proper widget classes. This prevents const constructors, makes testing harder, and hurts reusability.

### 13. Hardcoded Colors Throughout

**Files:** `widgets/ticket_visuals.dart:34-96`, `widgets/tool_card.dart:59-69`, `panels/worktree_panel_items.dart:1233`

Direct use of `const Color(0xFF...)`, `Colors.orange`, `Colors.red`, `Colors.green` instead of theme-aware `ColorScheme` values. These won't adapt properly to dark mode or custom themes.

### 14. UI State Leaks Into Models

Domain models contain ephemeral UI concerns:

| Field | File | Issue |
|-------|------|-------|
| `ToolUseOutputEntry.isExpanded` | `models/output_entry.dart:501` | UI expand/collapse state on data model |
| `ChatState.draftText` | `models/chat.dart:398` | Ephemeral text input state |
| `WorktreeState.welcomeDraftText` | `models/worktree.dart:224` | Ephemeral text input state |

UI state should live in dedicated UI state objects, not on domain models.

### 15. SelectionState is a Delegation Facade, Not State

**File:** `frontend/lib/state/selection_state.dart:75-94`

`selectedWorktree` returns `_project.selectedWorktree`, `selectedChat` returns `selectedWorktree?.selectedChat`. SelectionState doesn't actually hold any state — it's a command dispatcher disguised as state. Mutations go to `_project` but notifications come from `SelectionState`, which is confusing to reason about.

### 16. Mock Code in Production

**File:** `frontend/lib/main.dart:56-57, 424-432`

Production `main.dart` imports `mock_backend.dart` and `mock_data.dart`. A global `useMockData` flag (`main.dart:60-63`) toggles mock mode. Tests should inject mocks via constructor parameters instead of toggling a global.

### 17. Duplicate UTF-8 Recovery Code

**Files:** `services/persistence_service.dart`, `services/cost_tracking_service.dart`

Both independently implement `utf8.decode(bytes, allowMalformed: true)` for reading JSONL files. Should be extracted to a shared `readJsonlFile()` utility to keep the fix in one place.

### 18. Synchronous StreamControllers Risk Re-Entrancy

**File:** `frontend/lib/state/bulk_proposal_state.dart:34-35`

`StreamController.broadcast(sync: true)` delivers events synchronously. If listeners mutate state during delivery, this causes re-entrancy bugs. Use async broadcast unless synchronous delivery is specifically required and safe.

---

## Low Severity

### 19. Excessive `dynamic` Usage

150+ instances of `dynamic` type in `tool_card.dart`, `tool_card_results.dart`, `tool_card_inputs.dart`, and `tool_card_shared.dart`. Should create strongly-typed model classes for tool inputs/outputs with schema validation at the SDK boundary.

### 20. Branch Hardcoded to 'main'

**File:** `frontend/lib/main.dart:203`

Primary worktree branch is hardcoded to `'main'` with a TODO comment. Should detect the actual git branch on startup.

### 21. Provider Update Called Unnecessarily

**File:** `frontend/lib/main.dart:1183-1186`

`ChangeNotifierProxyProvider3` update callback always calls `syncWithSelectionState()` even when `SelectionState` didn't change. Any of the three upstream providers changing triggers the sync.

### 22. TicketViewState Cache Over-Invalidation

**File:** `frontend/lib/state/ticket_view_state.dart:100-118`

Every `_onTicketDataChanged` call invalidates ALL caches (categories, filters, grouping) even when only one ticket property changed. Should invalidate selectively based on what actually changed.

### 23. Mixed Async Patterns

Some code uses `async/await`, some uses `.then()/.catchError()` chains (e.g., `main.dart:837-841`). Should standardize on `async/await` throughout.

### 24. Inconsistent Service Access

`WelcomeScreen` instantiates `PersistenceService()` directly (`welcome_screen.dart:48`) while everywhere else uses Provider. `LogService.instance` is used in 218+ locations alongside Provider-based access. The singleton and Provider patterns are mixed.

### 25. Fire-and-Forget Persistence

**Files:** `models/chat.dart:1225, 2203`

Entries are added to the UI and `notifyListeners()` is called before persistence completes. An app crash before the flush completes means data loss. No retry logic exists for failed writes.

---

## What's Done Well

- **Immutable data models** — `ChatData`, `ConversationData`, `WorktreeData`, `ProjectData` all have proper `==`/`hashCode`/`copyWith`
- **JSONL write serialization** in `PersistenceService` (just needs to be applied to `CostTrackingService` too)
- **Provider setup** with proper dependency chains in `main.dart`
- **Disposal patterns** are generally thorough in `MainScreen` and most services
- **Test infrastructure** — `TestResources`, `safePumpAndSettle`, `pumpUntil` helpers
- **Error boundary setup** with `FlutterError` and `PlatformDispatcher` interception
- **Transport abstraction layer** for future remote backend support
