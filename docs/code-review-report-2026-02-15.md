# Frontend Codebase Review - Antipatterns & Bad Design

**Date:** 2026-02-15
**Scope:** `frontend/lib/` - state management, widgets/UI, services, models

---

## Critical Issues

### 1. ~~Write Queue Error Swallowing~~ FIXED

**File:** `services/persistence_service.dart:414`

```dart
_writeQueues[path] = current.catchError((_) {});  // Swallows ALL errors
return current;  // Returns the original (throwing) future
```

The write queue serializes appends correctly, but `.catchError((_) {})` silently swallows failures in the queue chain. If one write fails, subsequent writes proceed as if nothing happened, potentially writing to a corrupted file. The caller gets the exception via the returned `current`, but the queue itself continues silently. This directly undermines the JSONL corruption fix that serializes writes per file path.

---

### 2. ~~Mutable State Exposed via Getter~~ FIXED

**File:** `state/file_manager_state.dart:145`

```dart
Set<String> get expandedPaths => _expandedPaths;
```

Returns a direct reference to the internal mutable `Set`. External code can call `.add()` / `.remove()` without triggering `notifyListeners()`, silently breaking state consistency. Should return `Set.unmodifiable(_expandedPaths)`.

---

### 3. God Classes (Single Responsibility Violations)

| File | Lines | Concerns |
|------|-------|----------|
| `screens/settings_screen.dart` | 2,372 | Category nav, forms for ALL categories, dialogs, reset logic |
| `panels/worktree_panel.dart` | 1,935 | Tree building, selection, creation, deletion, restoration |
| `panels/information_panel.dart` | 1,735 | Branch info, 6+ git operations, conflict resolution, dialogs |
| `widgets/permission_dialog.dart` | 1,578 | Tool-specific builders, suggestion handlers, 3 footer variants |
| `services/persistence_service.dart` | 1,565 | 7 separate concerns: projects index, chat meta, chat history, cost tracking, tickets, archiving, worktree tags |
| `services/event_handler.dart` | 1,106 | Event routing, streaming state, title generation, tool tracking maps |
| `state/ticket_board_state.dart` | 1,076 | CRUD, selection, filtering, grouping, view modes, DAG validation, bulk proposals, persistence, callbacks |

---

## High Severity

### 4. Callback-Based State Wiring

**File:** `state/ticket_board_state.dart:96-108`

```dart
void Function({required int approvedCount, required int rejectedCount})?
    onBulkReviewComplete;
void Function(TicketData ticket)? onTicketReady;
```

`InternalToolsService` (lines 176-197) sets these callbacks directly, then manually nulls them after firing. This creates hidden dependencies, memory/dangling-closure risk, and bypasses Provider's compositional model entirely.

---

### 5. Fire-and-Forget Without Error Handling

**File:** `services/backend_service.dart` - lines 261, 303, 484, 587, 632

Multiple `unawaited()` calls for model refresh and agent startup. The called methods only log errors internally - no propagation to UI. Users get no feedback when model loading or agent startup fails.

---

### 6. ~~Persistence Operations Swallow Errors~~ FIXED

**File:** `services/persistence_service.dart` - lines 444, 522, 601, 669, 732, 799, 858, 1036, 1118

Nearly every write operation follows the pattern:

```dart
// errors are logged but not thrown to avoid blocking UI operations
```

Users get zero feedback when persistence fails, leading to silent data loss.

---

### 7. ~~Expensive Computations in Getters (No Caching)~~ FIXED

**File:** `state/ticket_board_state.dart`

| Getter | Lines | Cost |
|--------|-------|------|
| `allCategories` | 172-180 | Set build + sort on every access |
| `nextReadyTicket` | 186-207 | Filter + multi-key sort on every access |
| `filteredTickets` | 213-247 | 4 chained `.where()` calls on every access |
| `groupedTickets` | 254-295 | Map creation + per-group sorting on every access |
| `categoryProgress` | 300-315 | Full iteration + counter computation on every access |

These run on every widget rebuild, even when unrelated state changes trigger a notification. No caching or memoization.

---

### 8. ~~Helper Methods Returning Widgets Instead of Widget Classes~~ FIXED

Pervasive across the codebase - `_build*()` methods instead of separate Widget classes:

- **`widgets/tool_card.dart`**: `_buildToolSummaryWidget()` (63 lines), `_buildToolInput()` (98 lines), `_buildToolResult()` (98 lines)
- **`widgets/permission_dialog.dart`**: `_buildCompactView()` + helpers (328 lines combined)
- **`panels/conversation_panel.dart`**: `_buildEntryList()` (49 lines), `_buildPermissionWidget()` (59 lines)
- **`panels/information_panel.dart`**: numerous `_build*()` methods throughout

These prevent Flutter's widget reconciliation from optimizing rebuilds and make code harder to test in isolation.

---

### 9. ~~UI Tightly Coupled to Business Logic~~ FIXED

- **`panels/conversation_panel.dart:602-755`**: Directly calls `chat.allowPermission()`, `chat.denyPermission()`, `chat.interrupt()`, and orchestrates backend session creation with full error handling logic
- **`panels/information_panel.dart:211-322`**: Git service calls + merge operation logic embedded in widget state methods
- **`widgets/message_input.dart:276-333`**: File picker, clipboard handling, and image processing logic embedded in widget

Business logic should be in services, not in `build()` methods or widget state.

---

## Medium Severity

### 10. Implicit EventHandler Dependencies

**File:** `services/event_handler.dart:93, 99-100`

```dart
RateLimitState? rateLimitState;     // Set via direct assignment in main.dart:425
TicketBoardState? ticketBoard;      // Set via direct assignment in main.dart:1102, 1125
```

Dependencies are set post-construction through direct field assignment. The dependency graph is invisible to Provider. Should accept dependencies via constructor or use Provider's nested contexts.

---

### 11. ~~Manual Listener Pattern~~ FIXED

**File:** `state/file_manager_state.dart:48-107`

`FileManagerState` manually calls `_selectionState.addListener()` in its constructor and `removeListener()` in `dispose()`. This duplicates Provider's `ChangeNotifierProxyProvider` dependency tracking, is fragile during hot reload, and creates a hidden coupling path alongside the Provider tree.

---

### 12. ~~EventHandler Tracking Maps Never Cleaned~~ FIXED

**File:** `services/event_handler.dart:59-85`

```dart
final Map<String, ToolUseOutputEntry> _toolCallIndex = {};
final Map<String, String> _agentIdToConversationId = {};
final Map<String, String> _toolUseIdToAgentId = {};
final Map<String, bool> _hasAssistantOutputThisTurn = {};
final Map<String, bool> _expectingContextSummary = {};
```

These maps accumulate entries across sessions with no clear cleanup trigger. Memory leak risk over long-running usage.

---

### 13. ~~SelectionState Fire-and-Forget Loading~~ FIXED

**File:** `state/selection_state.dart:160-184`

`selectChat()` triggers `_loadChatHistoryIfNeeded()` without awaiting. Errors are caught and logged but swallowed. No loading indicator is shown to the user - chat history data just silently appears (or doesn't).

---

### 14. Services Extending ChangeNotifier

10+ service classes extend `ChangeNotifier`:
- `BackendService`
- `CliAvailabilityService`
- `InternalToolsService`
- `LogService`
- `MenuActionService`
- `ProjectConfigService`
- `ScriptExecutionService`
- `SettingsService`
- `WindowLayoutService`
- `WorktreeWatcherService`

This blurs the distinction between services (consumed for operations) and state (observed for UI rebuilds). Makes it unclear which services need listeners vs. just method calls.

---

### 15. ~~Git Service Silent Failures~~ FIXED

**File:** `services/git_service.dart:967-981`

Merge abort failures are caught with `catch (_)` and silently retried with `reset --merge`. If reset also fails, it throws without context about the original failure.

**File:** `services/git_service.dart:1254`

`getConflictOperation()` returns `null` for both "no conflict" and "error determining conflict" - callers cannot distinguish between the two.

---

### 16. ~~Subscription Cleanup Not Awaited~~ FIXED

**File:** `services/backend_service.dart:846-875`

`dispose()` calls `.cancel()` on subscriptions in a loop without awaiting. If one cancel throws, remaining subscriptions in the loop are leaked. Should use `Future.wait()` with `eagerError: false`.

---

### 17. ~~Duplicate Model Loading Code~~ FIXED

**File:** `services/backend_service.dart`

`_refreshModelsForAgent()` (lines 404-427) and `_refreshModelsIfSupported()` (lines 672-695) contain nearly identical logic. Bug fixes must be applied in two places.

---

### 18. ~~PTY Stream Missing Error Handler~~ FIXED

**File:** `services/script_execution_service.dart:176-180`

```dart
final outputSub = pty.output.listen((data) {
  script.appendBytes(data);
  final text = utf8.decode(data, allowMalformed: true);
  script._combined.write(text);
});
// No onError callback
```

If the PTY output stream errors, the listener crashes without notification.

---

### 19. Oversized Build Methods

| Widget | File | Build Lines |
|--------|------|-------------|
| `ConversationPanel` | `panels/conversation_panel.dart:369-495` | 126 lines |
| `PermissionDialog` | `widgets/permission_dialog.dart:216-311` | 95 lines |
| `MainScreen` | `screens/main_screen.dart:864-955` | 91 lines |

These should be decomposed into smaller widget classes.

---

### 20. ~~Duplicate Provider Registration~~ FIXED

**File:** `main.dart:1091-1137`

The `ChangeNotifierProxyProvider<ProjectState, TicketBoardState>` has nearly identical code in both its `create` and `update` callbacks. Changes must be synchronized in two places.

---

### 21. MainScreen Manual Listener Management

**File:** `screens/main_screen.dart:108-158`

`initState()` manually adds listeners to `BackendService` and subscribes to `LogService.instance.unhandledErrors` instead of using Provider's declarative approach. Creates imperative listener management alongside the declarative Provider tree.

---

## Low Severity

### 22. Hardcoded Values Throughout

Padding, margins, font sizes, border radii, animation durations, and truncation limits scattered as literals across `tool_card.dart`, `message_input.dart`, `permission_dialog.dart`, `conversation_panel.dart` and others. Not using theme extensions or named constants.

### 23. ~~Magic Logging Levels~~ FIXED

`persistence_service.dart` uses `level: 900` in 14+ locations. No named constant or documentation of what 900 represents.

### 24. ~~Missing `const` Constructors~~ NOT AN ISSUE

All listed widgets already have `const` constructors: `_ImagePreviewTile`, `_ImagePreviewRow`, `_ImageAttachButton`, `_SendButton`, `_ConversationPlaceholder`, `_AgentRemovedBanner`.

### 25. ~~ListView Without `.builder`~~ FIXED

**File:** `panels/agents_panel.dart:71-95`

Uses `ListView()` with list comprehension materializing all items at once instead of `ListView.builder()` for lazy rendering.

### 26. ~~RegExp in Build Methods~~ FIXED

**File:** `widgets/tool_card.dart:161`

`_formatToolName()` creates a `RegExp` on every invocation during build. Should be a `static final`.

### 27. ~~Unsafe Substring Operations~~ FIXED

**File:** `services/event_handler.dart:817`

```dart
'description=${event.description?.substring(0, event.description!.length > 50 ? 50 : event.description!.length) ?? "null"}...'
```

Calls `.length` three times and uses `!` after `?`. Should be simplified with a local variable.

---

## Systemic Patterns

The five most pervasive issues across the codebase:

1. **Silent error swallowing** - Persistence, backend, and git layers all prefer to silently continue rather than surface failures, making debugging extremely difficult and data loss invisible.

2. **God objects** - 7 files over 1,000 lines, each handling multiple unrelated concerns. Makes the codebase hard to navigate, test, and safely modify.

3. **Business logic in build methods** - UI widgets directly orchestrate backend operations, git commands, and complex state mutations instead of delegating to service layers.

4. **No computed value caching** - Expensive getters in state classes recompute collections, filters, and sorts on every access, causing unnecessary work on every widget rebuild.

5. **Implicit dependency wiring** - Callbacks, post-construction field assignment, and manual listeners create invisible coupling that Provider cannot track or optimize.
