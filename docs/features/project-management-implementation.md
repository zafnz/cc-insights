# Project Management — Implementation Plan

> **Reference**: See [project-management.md](project-management.md) for the full feature spec, data model, UI design, and mockups.

---

## How This Plan Works

This document breaks the project management feature into granular, self-contained implementation tasks. Each task is designed to be picked up by an agent and completed independently.

### Task Lifecycle

Every task follows this lifecycle:

```
Implemented → Tests Written & Passed → Code Review Passed → Done
```

A code review **must** pass before a task is considered done. If the review finds issues, they go back for fixes, then re-tested, then re-reviewed — repeating until the review passes.

### Task Checklist

Each task has this checklist:

```
- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done
```

### Agent Assignments

- **Engineer (sonnet)**: Straightforward implementation tasks with clear specs. The agent writes code and tests following the patterns described.
- **Senior Dev (opus)**: Tasks requiring architectural decisions, complex logic, integration across multiple systems, or nuanced judgment calls.

### Critical Rules for All Agents

1. **Read `FLUTTER.md` before writing any code** — it contains the project's coding standards
2. **Read `TESTING.md` before writing any tests** — it contains test patterns and rules
3. **Run `./frontend/run-flutter-test.sh` after every task** — ALL tests must pass, not just new ones
4. **Follow existing patterns exactly** — read the referenced source files before writing new code
5. **Never use `pumpAndSettle()` without timeout** — use `safePumpAndSettle()` from test helpers
6. **Use `TestResources` in all tests** — track and dispose all resources in `tearDown()`

---

## Phase 1: Foundation

### Task 1.1 — TicketData Model and Enums

**Assigned to: Engineer (sonnet)**

#### Overview

Create the core data model for tickets. This is the foundational type that everything else builds on. It must follow the exact same `@immutable` data class pattern used by `ProjectData`, `WorktreeData`, `ChatData`, and `Agent` in the existing codebase.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards (required for all tasks)
- `frontend/lib/models/agent.dart` — simplest example of the `@immutable` data class pattern with `copyWith`, `==`, `hashCode`, `toString`, no State class
- `frontend/lib/models/cost_tracking.dart` — example of `@immutable` data class with `toJson()`/`fromJson()`, nested types, and `Duration` serialization
- `frontend/lib/models/output_entry.dart` — example of enum serialization and factory `fromJson` with type discriminators
- `frontend/lib/models/conversation.dart` — example of named constructors and nullable fields
- `docs/features/project-management.md` — the "Ticket Data Model" section for the full spec

#### What to Implement

Create `frontend/lib/models/ticket.dart` containing:

**Enums:**
- `TicketStatus` — `draft`, `ready`, `active`, `blocked`, `needsInput`, `inReview`, `completed`, `cancelled`
- `TicketKind` — `feature`, `bugfix`, `research`, `split`, `question`, `test`, `docs`, `chore`
- `TicketPriority` — `low`, `medium`, `high`, `critical`
- `TicketEffort` — `small`, `medium`, `large`
- `TicketViewMode` — `list`, `graph`
- `TicketGroupBy` — `category`, `status`, `kind`, `priority`

Each enum should have a `String get label` that returns a human-readable display name (e.g., `needsInput` → `'Needs Input'`). Each enum should have a `String get jsonValue` for serialization (e.g., `needsInput` → `'needs_input'`) and a static `fromJson(String)` factory. Follow the pattern in `PermissionMode` from `chat.dart` for enums with extra data.

**Supporting types (all `@immutable` with `const` constructors):**
- `LinkedWorktree` — fields: `worktreeRoot` (String), `branch` (String?). Include `toJson()`, `factory fromJson()`, `==`, `hashCode`.
- `LinkedChat` — fields: `chatId` (String), `chatName` (String), `worktreeRoot` (String). Include `toJson()`, `factory fromJson()`, `==`, `hashCode`.
- `TicketCostStats` — fields: `totalTokens` (int), `totalCost` (double), `agentTimeMs` (int), `waitingTimeMs` (int). Include `toJson()`, `factory fromJson()`, `==`, `hashCode`. Use millisecond ints for Duration serialization (same pattern as `TimingStats`).

**Main class:**
- `TicketData` — `@immutable` with `const` constructor
  - Fields: `id` (int), `title` (String), `description` (String), `status` (TicketStatus), `kind` (TicketKind), `priority` (TicketPriority), `effort` (TicketEffort), `category` (String?), `tags` (Set\<String\>), `dependsOn` (List\<int\>), `linkedWorktrees` (List\<LinkedWorktree\>), `linkedChats` (List\<LinkedChat\>), `sourceConversationId` (String?), `costStats` (TicketCostStats?), `createdAt` (DateTime), `updatedAt` (DateTime)
  - Computed: `String get displayId` → `'TKT-${id.toString().padLeft(3, '0')}'`
  - Computed: `bool get isTerminal` → `status == completed || status == cancelled`
  - `copyWith({...})` — all fields optional, same pattern as `WorktreeData.copyWith`. For nullable fields that need to be cleared, use `clearX` boolean flags (see `WorktreeData.copyWith` for this pattern).
  - `toJson()` — use camelCase keys to match existing convention (`CostTrackingEntry` uses camelCase). Serialize enums via their `jsonValue`. Serialize `DateTime` via `.toUtc().toIso8601String()`. Serialize `Set<String>` as `List<String>`.
  - `factory TicketData.fromJson(Map<String, dynamic> json)` — null-safe with fallbacks. Use `?? ''`, `?? 0` patterns from `CostTrackingEntry.fromJson`.
  - `operator ==`, `hashCode` (use `Object.hash` with all fields), `toString()`

**Import:** Only `import 'package:flutter/foundation.dart';` — no other dependencies.

#### Tests to Write

Create `frontend/test/models/ticket_test.dart`:

1. **Enum tests:**
   - Each enum's `label` getter returns correct display strings
   - Each enum's `jsonValue` serializes correctly
   - Each enum's `fromJson` round-trips correctly
   - `fromJson` throws on invalid values

2. **TicketData tests:**
   - `displayId` formats correctly: id=1 → `'TKT-001'`, id=42 → `'TKT-042'`, id=1000 → `'TKT-1000'`
   - `isTerminal` returns true for `completed` and `cancelled`, false for all others
   - `copyWith` preserves unchanged fields
   - `copyWith` updates specified fields
   - `toJson()` → `fromJson()` round-trip preserves all fields
   - `fromJson` handles missing optional fields (category, costStats, sourceConversationId)
   - Equality: same fields → equal, different fields → not equal
   - `hashCode`: equal objects have equal hashCodes

3. **Supporting type tests:**
   - `LinkedWorktree` toJson/fromJson round-trip
   - `LinkedChat` toJson/fromJson round-trip
   - `TicketCostStats` toJson/fromJson round-trip

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- File `frontend/lib/models/ticket.dart` exists with all types
- File `frontend/test/models/ticket_test.dart` exists with all test cases listed above
- `./frontend/run-flutter-test.sh test/models/ticket_test.dart` passes
- `./frontend/run-flutter-test.sh` (all tests) passes
- No `flutter analyze` warnings in the new file

---

### Task 1.2 — TicketBoardState Core (CRUD + Selection)

**Assigned to: Senior Dev (opus)**

#### Overview

Create the state management class for the ticket system. This is the central nervous system — it holds all tickets, manages selection, and provides CRUD operations. It needs to handle DAG cycle detection correctly, which requires careful graph algorithms.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `frontend/lib/models/project.dart` — `ProjectState` pattern: `ChangeNotifier` with private `_data`, getters, methods that call `notifyListeners()`
- `frontend/lib/state/selection_state.dart` — how selection state works, `ContentPanelMode` enum
- `frontend/lib/services/persistence_service.dart` — all static methods, path patterns, write queue mechanism
- `frontend/lib/models/ticket.dart` — the model you're managing (created in Task 1.1)
- `docs/features/project-management.md` — the "State Management" and "Persistence" sections

#### What to Implement

Create `frontend/lib/state/ticket_board_state.dart`:

```dart
class TicketBoardState extends ChangeNotifier {
  final String projectId;
  final PersistenceService _persistence;
```

**Internal state:**
- `List<TicketData> _tickets = []`
- `int _nextId = 1`
- `int? _selectedTicketId`
- `TicketViewMode _viewMode = TicketViewMode.list`
- `String _searchQuery = ''`
- `TicketStatus? _statusFilter`
- `TicketKind? _kindFilter`
- `TicketPriority? _priorityFilter`
- `String? _categoryFilter`
- `TicketGroupBy _groupBy = TicketGroupBy.category`
- `TicketDetailMode _detailMode = TicketDetailMode.detail` (enum: `detail`, `create`, `edit`, `bulkReview`)

**Getters:**
- `List<TicketData> get tickets` — unmodifiable view of all tickets
- `TicketData? get selectedTicket` — ticket matching `_selectedTicketId`
- `int get activeCount` — count of tickets with `status == active`
- `TicketViewMode get viewMode`
- `String get searchQuery`
- `TicketGroupBy get groupBy`
- `TicketDetailMode get detailMode`
- All filter getters
- `List<String> get allCategories` — unique categories from all tickets, sorted
- `List<TicketData> get filteredTickets` — apply search + all filters. Search matches against `displayId`, `title`, `description` (case-insensitive). Status/kind/priority/category filters are AND-combined.
- `Map<String, List<TicketData>> get groupedTickets` — group `filteredTickets` by the current `_groupBy` field. Key is the group label. Items within each group sorted by priority (critical first), then by id.
- `Map<String, ({int completed, int total})> get categoryProgress` — for each category, count completed vs total

**CRUD methods (all call `notifyListeners()` and trigger `_autoSave()`):**
- `TicketData createTicket({required String title, required TicketKind kind, ...})` — assigns `_nextId++`, sets `createdAt`/`updatedAt` to now, `status` defaults to `ready`
- `void updateTicket(int id, TicketData Function(TicketData) updater)` — applies updater, sets `updatedAt` to now
- `void deleteTicket(int id)` — removes ticket, also removes it from other tickets' `dependsOn` lists
- `TicketData? getTicket(int id)` — find by id

**Selection methods:**
- `void selectTicket(int? id)` — sets `_selectedTicketId`, also sets `_detailMode = detail`
- `void setViewMode(TicketViewMode mode)`
- `void setSearchQuery(String query)`
- `void setStatusFilter(TicketStatus? status)`
- `void setKindFilter(TicketKind? kind)`
- `void setPriorityFilter(TicketPriority? priority)`
- `void setCategoryFilter(String? category)`
- `void setGroupBy(TicketGroupBy groupBy)`
- `void showCreateForm()` — sets `_detailMode = create`, clears selection
- `void showDetail()` — sets `_detailMode = detail`

**Dependency methods:**
- `void addDependency(int ticketId, int dependsOnId)` — validates: not self, target exists, no cycle. Throws `ArgumentError` on invalid.
- `void removeDependency(int ticketId, int dependsOnId)`
- `bool wouldCreateCycle(int fromId, int toId)` — DFS from `toId` following `dependsOn` edges. Returns true if `fromId` is reachable from `toId`. This means: if we add an edge "fromId depends on toId", would there be a cycle? Check if fromId is reachable from toId via existing dependsOn.
- `List<int> getBlockedBy(int ticketId)` — returns IDs of tickets that this ticket blocks (i.e., other tickets whose `dependsOn` contains `ticketId`)

**Status methods:**
- `void setStatus(int ticketId, TicketStatus status)` — direct status set
- `void markCompleted(int ticketId)` — sets status to `completed`
- `void markCancelled(int ticketId)` — sets status to `cancelled`

**Persistence:**
- `Future<void> load()` — reads from `PersistenceService`, populates `_tickets` and `_nextId`
- `Future<void> save()` — writes to `PersistenceService`
- `void _autoSave()` — calls `save()` (debounce is handled by PersistenceService's write queue)

**Also add to `PersistenceService`:**
- `static String ticketsPath(String projectId)` → `'$baseDir/projects/$projectId/tickets.json'`
- `Future<Map<String, dynamic>?> loadTickets(String projectId)` — instance method, reads file, returns parsed JSON or null
- `Future<void> saveTickets(String projectId, Map<String, dynamic> data)` — instance method, uses write queue

#### Tests to Write

Create `frontend/test/state/ticket_board_state_test.dart`:

1. **CRUD tests:**
   - `createTicket` assigns incrementing IDs (1, 2, 3...)
   - `createTicket` sets `createdAt` and `updatedAt`
   - `createTicket` returns the created ticket
   - `updateTicket` modifies the ticket and updates `updatedAt`
   - `updateTicket` with non-existent ID does nothing (no crash)
   - `deleteTicket` removes the ticket
   - `deleteTicket` removes the ID from other tickets' `dependsOn`
   - `getTicket` returns correct ticket or null

2. **Selection tests:**
   - `selectTicket` updates `selectedTicket`
   - `selectTicket(null)` clears selection
   - `showCreateForm` sets detailMode and clears selection

3. **Filtering tests:**
   - `filteredTickets` with no filters returns all tickets
   - `setSearchQuery` filters by title substring (case-insensitive)
   - `setSearchQuery` filters by displayId substring
   - `setStatusFilter` filters by status
   - `setKindFilter` filters by kind
   - Multiple filters are AND-combined
   - Clearing a filter (set to null) removes that filter

4. **Grouping tests:**
   - `groupedTickets` with `groupBy: category` groups correctly
   - `groupedTickets` with `groupBy: status` groups correctly
   - Tickets without a category go into an "Uncategorized" group
   - Items within groups are sorted by priority then id

5. **Dependency / DAG tests:**
   - `addDependency` adds to `dependsOn` list
   - `addDependency` with self-reference throws `ArgumentError`
   - `addDependency` with non-existent target throws `ArgumentError`
   - `addDependency` that would create a direct cycle (A→B, B→A) throws
   - `addDependency` that would create an indirect cycle (A→B, B→C, C→A) throws
   - `wouldCreateCycle` correctly detects cycles without modifying state
   - `wouldCreateCycle` returns false for valid additions
   - `removeDependency` removes from `dependsOn` list
   - `getBlockedBy` returns correct reverse-dependency list

6. **Progress tests:**
   - `categoryProgress` computes correct completed/total per category
   - `activeCount` counts only active tickets

7. **Persistence tests:**
   - `save()` then `load()` round-trips all state (tickets, nextId)
   - `load()` with no file starts empty
   - `load()` with corrupt file doesn't crash (logs error, starts empty)
   - Creating a ticket triggers auto-save

8. **Notification tests:**
   - Each mutating method calls `notifyListeners()` (verify with a listener counter)

Use `TestResources` and `setupTestConfig()` for test isolation. Mock `PersistenceService` or use temp directory.

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/state/ticket_board_state.dart` exists
- `PersistenceService` has `ticketsPath`, `loadTickets`, `saveTickets` methods
- `frontend/test/state/ticket_board_state_test.dart` exists with all test groups above
- `./frontend/run-flutter-test.sh test/state/ticket_board_state_test.dart` passes
- `./frontend/run-flutter-test.sh` (all tests) passes
- DAG cycle detection is correct for all cases (direct, indirect, self-reference)

---

### Task 1.3 — Ticket Screen Shell and Navigation Rail

**Assigned to: Engineer (sonnet)**

#### Overview

Create the ticket screen skeleton and wire it into the app's navigation. After this task, users can click a "Tickets" button in the nav rail and see an empty ticket screen. No ticket list or detail content yet — just the structural shell.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `frontend/lib/screens/main_screen.dart` — the `IndexedStack` structure, how screens are added, `_selectedNavIndex` routing, `_handleNavigationChange`
- `frontend/lib/widgets/navigation_rail.dart` — the `AppNavigationRail` widget, `_NavRailButton` pattern, existing destinations and indices
- `frontend/lib/screens/file_manager_screen.dart` — example of a full-screen view that exists as an IndexedStack child (for pattern reference, first 50 lines)
- `frontend/lib/main.dart` — provider setup, where `TicketBoardState` provider needs to be added
- `frontend/lib/state/ticket_board_state.dart` — the state class created in Task 1.2

#### What to Implement

**1. Create `frontend/lib/screens/ticket_screen.dart`:**
- `TicketScreen extends StatelessWidget`
- Layout: `Row` with a fixed-width left panel (320px) and a flexible right panel
- Left panel: placeholder `Container` with text "Ticket List" (replaced in Task 1.5)
- Right panel: placeholder `Container` with text "Ticket Detail" (replaced in Task 1.6)
- Divider: `VerticalDivider(width: 1)` between the panels
- Watch `TicketBoardState` via `context.watch<TicketBoardState>()`

**2. Modify `frontend/lib/widgets/navigation_rail.dart`:**
- Add a new `_NavRailButton` for Tickets
  - `icon: Icons.task_alt_outlined`
  - `selectedIcon: Icons.task_alt`
  - `tooltip: 'Tickets'`
  - Index: `4`
- Position it after File Manager (index 1) and before the `Spacer`
- Add a badge showing active ticket count (from `TicketBoardState.activeCount`)
  - Access via `context.watch<TicketBoardState>()` — the rail now needs to be wrapped in a widget that can access providers, OR pass the count as a parameter
  - Follow whichever pattern is simpler given the existing code structure. If `AppNavigationRail` currently takes `selectedIndex` and `onDestinationSelected` as params, add an `int ticketBadgeCount` param and pass it from `MainScreen`

**3. Modify `frontend/lib/screens/main_screen.dart`:**
- Add `TicketScreen()` as index 4 in the `IndexedStack`
- Update `_handleNavigationChange` if needed (keyboard interception handling for index 4 — tickets should behave like the main view, no special suspension needed)

**4. Modify `frontend/lib/main.dart`:**
- Add `ChangeNotifierProvider<TicketBoardState>` to the `MultiProvider` list
- Create it with the project's `projectId` (from `PersistenceService.generateProjectId(project.data.repoRoot)`) and the `PersistenceService` instance
- Call `ticketBoardState.load()` during initialization (after provider creation)

#### Tests to Write

Create `frontend/test/widget/ticket_screen_test.dart`:

1. **Screen renders:** TicketScreen renders without errors when wrapped in providers
2. **Layout structure:** The screen contains a left and right section
3. **Navigation rail badge:** Verify the badge shows the correct active ticket count (0 when empty, N when there are active tickets)

Create or update `frontend/test/widget/navigation_rail_test.dart` (if it exists, add tests; if not, create):

4. **Tickets button exists:** The nav rail shows a Tickets button
5. **Tickets button callback:** Tapping the Tickets button calls `onDestinationSelected` with index 4

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/screens/ticket_screen.dart` exists
- Nav rail shows a Tickets button with a badge
- MainScreen IndexedStack index 4 renders TicketScreen
- `TicketBoardState` provider is wired into the app
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.4 — Ticket Status Visuals Utility

**Assigned to: Engineer (sonnet)**

#### Overview

Create a shared utility that maps ticket statuses, kinds, priorities, and efforts to their visual representations (icons, colors, labels). This utility is used by every ticket UI component, so building it as a shared module avoids duplication.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `frontend/lib/models/ticket.dart` — the enums (Task 1.1)
- `docs/mocks/ticket-list-panel-mock.html` — the exact status icons and colors used in the mockups
- `docs/mocks/ticket-detail-panel-mock.html` — metadata pill colors

#### What to Implement

Create `frontend/lib/widgets/ticket_visuals.dart`:

**Status visuals:**
```dart
class TicketStatusVisuals {
  static IconData icon(TicketStatus status) => switch (status) {
    TicketStatus.draft => Icons.edit_note,
    TicketStatus.ready => Icons.radio_button_unchecked,
    TicketStatus.active => Icons.play_circle_outline,
    TicketStatus.blocked => Icons.block,
    TicketStatus.needsInput => Icons.help_outline,
    TicketStatus.inReview => Icons.rate_review_outlined,
    TicketStatus.completed => Icons.check_circle_outline,
    TicketStatus.cancelled => Icons.cancel_outlined,
  };

  static Color color(TicketStatus status, ColorScheme cs) => switch (status) {
    // Map to theme-appropriate colors using the ColorScheme
    // Green for done, blue for active, grey for ready/draft,
    // orange for blocked/input, purple for review, red for cancelled
  };
}
```

**Kind visuals:**
```dart
class TicketKindVisuals {
  static IconData icon(TicketKind kind) => ...;
  static Color color(TicketKind kind, ColorScheme cs) => ...;
}
```

**Priority visuals:**
```dart
class TicketPriorityVisuals {
  static IconData icon(TicketPriority priority) => ...;
  static Color color(TicketPriority priority, ColorScheme cs) => ...;
}
```

**Effort visuals:**
```dart
class TicketEffortVisuals {
  static Color color(TicketEffort effort, ColorScheme cs) => ...;
}
```

**Reusable widgets:**
- `TicketStatusIcon` — `StatelessWidget` that renders the status icon at a given size with the correct color
- `MetadataPill` — `StatelessWidget` that renders a small chip with icon + label + background color. Used for status, kind, priority, category pills in the detail view. Parameters: `IconData icon`, `String label`, `Color color`.
- `EffortBadge` — `StatelessWidget` that renders a tiny badge like "S", "M", "L" with the effort color
- `KindBadge` — `StatelessWidget` that renders the kind label as a tiny colored badge

#### Tests to Write

Create `frontend/test/widget/ticket_visuals_test.dart`:

1. **TicketStatusIcon renders for each status:** Verify it renders an Icon with the correct IconData
2. **MetadataPill renders label and icon:** Verify the pill shows the expected text and icon
3. **EffortBadge renders for each effort level:** Verify correct text (S/M/L)
4. **All statuses have distinct icons:** No two statuses share the same icon
5. **All statuses have non-null colors:** Every status returns a valid color

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/widgets/ticket_visuals.dart` exists
- Every enum value maps to an icon and color
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.5 — Ticket List Panel

**Assigned to: Senior Dev (opus)**

#### Overview

Build the ticket list panel — the left sidebar of the ticket screen. This is the primary navigation interface for tickets. It includes search, filter controls, group-by headers, and individual ticket items. It is the most complex UI component of Phase 1.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `TESTING.md` — test patterns
- `frontend/lib/panels/worktree_panel.dart` — the most similar existing panel: `PanelWrapper` usage, `ListView.builder`, selection highlighting, item layout
- `frontend/lib/panels/chats_panel.dart` — another list panel example with status indicators
- `frontend/lib/panels/panel_wrapper.dart` — the standard panel wrapper
- `frontend/lib/state/ticket_board_state.dart` — the state class (Task 1.2)
- `frontend/lib/widgets/ticket_visuals.dart` — the visual utilities (Task 1.4)
- `docs/mocks/ticket-list-panel-mock.html` — the exact visual design

#### What to Implement

Create `frontend/lib/panels/ticket_list_panel.dart`:

**Static test keys class:**
```dart
class TicketListPanelKeys {
  TicketListPanelKeys._();
  static const Key searchField = Key('ticket-list-search');
  static const Key addButton = Key('ticket-list-add');
  static const Key filterButton = Key('ticket-list-filter');
  static const Key listViewToggle = Key('ticket-list-view-toggle');
  static const Key graphViewToggle = Key('ticket-graph-view-toggle');
  static const Key groupByDropdown = Key('ticket-list-group-by');
  // Add more as needed
}
```

**Main widget: `TicketListPanel extends StatelessWidget`**
- Wraps content in `PanelWrapper(title: 'Tickets', icon: Icons.task_alt, ...)`
- Content is a `Column`:
  1. **Search bar**: `TextField` with search icon prefix, calls `ticketBoard.setSearchQuery()` on change
  2. **Toolbar row**: Filter icon button, Add (+) icon button (calls `ticketBoard.showCreateForm()`), List/Graph segmented toggle
  3. **Group-by dropdown**: Small dropdown that sets `ticketBoard.setGroupBy()`
  4. **Ticket list**: `Expanded` → `ListView.builder`

**Ticket list rendering:**
- Use `groupedTickets` from `TicketBoardState`
- Flatten the grouped map into a flat list of items for `ListView.builder`: alternating group headers and ticket items
- **Group header**: Category name, completed/total count, thin progress bar
- **Ticket item**: Row with status icon, display ID (monospace, `fontFamily: 'JetBrains Mono'`), title (ellipsis overflow), effort badge
- **Selected state**: Background `primaryContainer.withValues(alpha: 0.3)` when selected (match `worktree_panel.dart` pattern)
- **Tap handler**: `ticketBoard.selectTicket(ticket.id)`
- **Terminal ticket styling**: Completed/cancelled tickets get reduced opacity (0.5)

**Filter popover** (when filter button is tapped):
- Show a `PopupMenuButton` or similar with filter options:
  - Status dropdown
  - Kind dropdown
  - Priority dropdown
  - "Clear filters" option
- Active filters should show a dot/badge on the filter button

#### Tests to Write

Create `frontend/test/widget/ticket_list_panel_test.dart`:

1. **Renders empty state:** When no tickets, shows appropriate message
2. **Renders tickets:** When tickets exist, shows them in the list
3. **Search filters tickets:** Typing in search field filters the visible list
4. **Group headers show:** Category groups show headers with correct counts
5. **Selecting a ticket:** Tapping a ticket item calls `selectTicket` on the state
6. **Selected ticket highlighting:** The selected ticket has the correct background color
7. **Add button:** Tapping (+) calls `showCreateForm()`
8. **View toggle:** Tapping graph toggle calls `setViewMode(TicketViewMode.graph)`
9. **Completed tickets dimmed:** Completed tickets render with reduced opacity
10. **Status icons correct:** Each status shows the correct icon from `TicketStatusVisuals`

Use `ChangeNotifierProvider<TicketBoardState>.value` to provide a real `TicketBoardState` (populated with test data) in tests. Use `TestResources` to track it.

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/panels/ticket_list_panel.dart` exists
- All 10 test cases pass
- Panel matches the mockup layout (search, toolbar, grouped list)
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.6 — Ticket Detail Panel

**Assigned to: Senior Dev (opus)**

#### Overview

Build the ticket detail panel — the right content area of the ticket screen. Shows full detail for the selected ticket including header, metadata pills, description, dependencies, and placeholder sections for linked work and actions.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `TESTING.md` — test patterns
- `frontend/lib/panels/content_panel.dart` — how content panels switch between modes
- `frontend/lib/widgets/markdown_renderer.dart` — the existing markdown renderer (use for description)
- `frontend/lib/widgets/ticket_visuals.dart` — visual utilities (Task 1.4)
- `frontend/lib/state/ticket_board_state.dart` — state management (Task 1.2)
- `docs/mocks/ticket-detail-panel-mock.html` — the exact visual design

#### What to Implement

Create `frontend/lib/panels/ticket_detail_panel.dart`:

**Static test keys class:**
```dart
class TicketDetailPanelKeys {
  TicketDetailPanelKeys._();
  static const Key editButton = Key('ticket-detail-edit');
  static const Key statusPill = Key('ticket-detail-status-pill');
  static const Key descriptionSection = Key('ticket-detail-description');
  static const Key dependsOnSection = Key('ticket-detail-depends-on');
  static const Key blocksSection = Key('ticket-detail-blocks');
  static const Key actionsSection = Key('ticket-detail-actions');
  static const Key costSection = Key('ticket-detail-cost');
}
```

**Widget: `TicketDetailPanel extends StatelessWidget`**

When no ticket is selected, show a centered empty state message: "Select a ticket to view details".

When a ticket is selected, show a `SingleChildScrollView` with:

1. **Header section:**
   - `TicketStatusIcon` at 40px size
   - Display ID in monospace (e.g., `TKT-003`)
   - Title in `headlineSmall` text style
   - Edit button (icon button, wired in a later task for now just shows the button)
   - Optional: More menu (three-dot) with "Delete", "Cancel" options

2. **Metadata pills row:**
   - `Wrap` of `MetadataPill` widgets for: status, kind, priority, category (if set)
   - 8px spacing between pills

3. **Tags section** (if tags is not empty):
   - `Wrap` of `Chip` widgets, teal-ish color

4. **Description section:**
   - Section header label: "Description"
   - Card with `surfaceContainerLow` background
   - `MarkdownRenderer(data: ticket.description)` inside the card
   - If description is empty, show "No description" in `bodySmall` with reduced opacity

5. **Dependencies section:**
   - "Depends on" sub-header with list of clickable ticket chips (display ID + title truncated)
     - Each chip: `InkWell` that calls `ticketBoard.selectTicket(depId)` on tap
     - Show status icon on each dependency chip
   - "Blocks" sub-header with similar list (from `ticketBoard.getBlockedBy(ticket.id)`)
   - If no dependencies in either direction, show "No dependencies"

6. **Linked Work section** (placeholder for Phase 3):
   - Section header label: "Linked Work"
   - If `linkedWorktrees` or `linkedChats` is not empty, render them
   - For now, this will typically be empty since linking is Phase 3

7. **Actions section** (placeholder buttons for Phase 3):
   - "Begin in new worktree" — `FilledButton`, disabled (wired in Phase 3)
   - "Begin in worktree..." — `OutlinedButton`, disabled (wired in Phase 3)
   - Status change buttons: "Mark Complete" (`OutlinedButton`, calls `ticketBoard.markCompleted`), "Cancel" (`OutlinedButton` with red tint, calls `ticketBoard.markCancelled`)

8. **Cost & Time section** (if `costStats` is not null):
   - 4-column grid: Tokens, Cost, Agent Time, Waiting
   - Each cell: label on top in `labelSmall`, value below in `titleMedium`

**Section dividers:** Use thin `Divider` with `outlineVariant.withValues(alpha: 0.3)` between sections. Add a label for each section in `labelMedium` with `onSurfaceVariant` color.

#### Tests to Write

Create `frontend/test/widget/ticket_detail_panel_test.dart`:

1. **Empty state:** When no ticket selected, shows "Select a ticket" message
2. **Renders header:** Shows correct display ID, title, and status icon
3. **Renders metadata pills:** Shows status, kind, priority pills
4. **Renders category pill:** When category is set, shows category pill; when null, no category pill
5. **Renders tags:** When tags exist, shows chip widgets
6. **Renders description:** Description text appears in the card
7. **Renders empty description:** Shows "No description" when description is empty
8. **Renders dependencies:** Shows "Depends on" chips for each dependency
9. **Clicking dependency selects it:** Tapping a dependency chip calls `selectTicket`
10. **Renders blocks:** Shows "Blocks" section with reverse dependencies
11. **Mark Complete button:** Tapping "Mark Complete" calls `markCompleted` on state
12. **Cancel button:** Tapping "Cancel" calls `markCancelled` on state
13. **Cost stats render:** When costStats is present, shows the 4-column grid

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/panels/ticket_detail_panel.dart` exists
- All 13 test cases pass
- Panel matches the mockup layout
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.7 — Ticket Create Form

**Assigned to: Engineer (sonnet)**

#### Overview

Build the form for manually creating tickets. This follows the exact same layout pattern as `CreateWorktreePanel` — centered, max-width 600px, 32px padding, with text fields, dropdowns, and action buttons.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `TESTING.md` — test patterns
- `frontend/lib/panels/create_worktree_panel.dart` — **the primary reference** for form layout, field styling, button patterns, cancel behavior, error handling. Follow this pattern exactly.
- `frontend/lib/state/ticket_board_state.dart` — `createTicket()`, `showDetail()`, `allCategories`
- `frontend/lib/models/ticket.dart` — enums for dropdowns
- `docs/mocks/ticket-create-form-mock.html` — the exact visual design

#### What to Implement

Create `frontend/lib/panels/ticket_create_form.dart`:

**Static test keys class:**
```dart
class TicketCreateFormKeys {
  TicketCreateFormKeys._();
  static const Key titleField = Key('ticket-create-title');
  static const Key kindDropdown = Key('ticket-create-kind');
  static const Key priorityDropdown = Key('ticket-create-priority');
  static const Key categoryField = Key('ticket-create-category');
  static const Key descriptionField = Key('ticket-create-description');
  static const Key effortSelector = Key('ticket-create-effort');
  static const Key cancelButton = Key('ticket-create-cancel');
  static const Key createButton = Key('ticket-create-submit');
}
```

**Widget: `TicketCreateForm extends StatefulWidget`**

State fields:
- `TextEditingController` for: title, category, description
- `TicketKind _selectedKind = TicketKind.feature`
- `TicketPriority _selectedPriority = TicketPriority.medium`
- `TicketEffort _selectedEffort = TicketEffort.medium`
- `List<int> _selectedDependencies = []`
- `Set<String> _tags = {}`
- `String? _tagInput` (for the tag chip input)
- `bool _isCreating = false` (loading state for create button)

Layout (match `CreateWorktreePanel`):
- Centered `ConstrainedBox(maxWidth: 600)`
- 32px padding
- Header: Icon (28px, `add_task`) + "Create Ticket" in `headlineSmall`
- Form fields with 16px vertical spacing:

  1. **Title** — `TextField` with `surfaceContainerLow` fill, required
  2. **Kind** — `DropdownButtonFormField<TicketKind>` with all enum values
  3. **Priority** — `DropdownButtonFormField<TicketPriority>` with all enum values
  4. **Category** — `TextField` with autocomplete (use `Autocomplete` widget with `allCategories` from state)
  5. **Description** — `TextField` with `maxLines: 6`, `surfaceContainerLow` fill
  6. **Estimated Effort** — Row of 3 selectable chips/radio buttons for small/medium/large, with colors from `TicketEffortVisuals`
  7. **Dependencies** — chip input: `TextField` at bottom, chips above showing selected dependencies (display ID + title). Remove chip via X button. Dropdown/autocomplete to search existing tickets by ID or title.
  8. **Tags** — chip input: `TextField` where pressing Enter adds the typed text as a tag chip. Remove via X button.

- Action bar at bottom:
  - `OutlinedButton` "Cancel" → calls `ticketBoard.showDetail()`
  - `FilledButton` "Create Ticket" → validates title is not empty, calls `ticketBoard.createTicket(...)`, then `ticketBoard.selectTicket(newTicket.id)`

#### Tests to Write

Create `frontend/test/widget/ticket_create_form_test.dart`:

1. **Renders all fields:** All form fields are present (title, kind, priority, category, description, effort, dependencies, tags)
2. **Title is required:** Tapping Create with empty title shows validation error or is disabled
3. **Kind dropdown shows all values:** Opening the kind dropdown shows all TicketKind values
4. **Priority dropdown shows all values:** Opening the priority dropdown shows all TicketPriority values
5. **Effort selector works:** Tapping a different effort option changes the selection
6. **Cancel navigates back:** Tapping Cancel calls `showDetail()` on the state
7. **Create ticket:** Filling in title and tapping Create calls `createTicket()` on the state
8. **Created ticket is selected:** After creation, the new ticket is selected

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/panels/ticket_create_form.dart` exists
- All 8 test cases pass
- Form follows the same visual pattern as `CreateWorktreePanel`
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.8 — Wire Ticket Screen Together

**Assigned to: Engineer (sonnet)**

#### Overview

Connect all the Phase 1 components into the ticket screen. The screen should switch between detail view and create form based on `TicketBoardState.detailMode`. Replace the placeholder panels from Task 1.3 with the real `TicketListPanel`, `TicketDetailPanel`, and `TicketCreateForm`.

#### Background — Read These Files First

- `frontend/lib/screens/ticket_screen.dart` — the shell created in Task 1.3
- `frontend/lib/panels/ticket_list_panel.dart` — Task 1.5
- `frontend/lib/panels/ticket_detail_panel.dart` — Task 1.6
- `frontend/lib/panels/ticket_create_form.dart` — Task 1.7
- `frontend/lib/state/ticket_board_state.dart` — `detailMode`, `TicketDetailMode`
- `frontend/lib/panels/content_panel.dart` — example of switching content based on mode

#### What to Implement

Update `frontend/lib/screens/ticket_screen.dart`:

- Left panel (320px): `TicketListPanel()`
- Right panel (flex): switches on `ticketBoard.detailMode`:
  - `TicketDetailMode.detail` → `TicketDetailPanel()`
  - `TicketDetailMode.create` → `TicketCreateForm()`
  - `TicketDetailMode.edit` → `TicketDetailPanel()` (edit mode is a future task, same as detail for now)
  - `TicketDetailMode.bulkReview` → placeholder `Center(child: Text('Bulk Review'))` (Phase 2)
- Divider between panels: `VerticalDivider(width: 1, color: outlineVariant.withValues(alpha: 0.3))`

**Also update the `PanelWrapper` usage** — the list panel is already wrapped by `TicketListPanel` internally. The right side does NOT need a PanelWrapper since the detail panel and create form handle their own layout.

#### Tests to Write

Update `frontend/test/widget/ticket_screen_test.dart`:

1. **Default view:** TicketScreen shows TicketListPanel on the left and TicketDetailPanel on the right
2. **Create mode:** When `ticketBoard.showCreateForm()` is called, the right side shows TicketCreateForm
3. **Back to detail:** After creating a ticket (or cancelling), the right side shows TicketDetailPanel again
4. **End-to-end create flow:** Click (+) in list panel → see create form → fill in title → click Create → see ticket in list → see ticket in detail panel

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Ticket screen renders the real panels (not placeholders)
- Mode switching works (detail ↔ create)
- End-to-end create-and-view flow works
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.9 — Ticket Editing

**Assigned to: Engineer (sonnet)**

#### Overview

Add the ability to edit existing tickets. The user clicks "Edit" on the detail panel, and the detail view transforms into an editable form (similar to the create form but pre-populated). Save applies the changes, Cancel reverts.

#### Background — Read These Files First

- `frontend/lib/panels/ticket_detail_panel.dart` — the detail panel (Task 1.6)
- `frontend/lib/panels/ticket_create_form.dart` — the create form (Task 1.7), reuse as much as possible
- `frontend/lib/state/ticket_board_state.dart` — `updateTicket()`, `detailMode`

#### What to Implement

**Option A (preferred): In-place edit mode in TicketDetailPanel**

When the user clicks the Edit button:
- `ticketBoard.setDetailMode(TicketDetailMode.edit)`
- The detail panel switches to an editable version:
  - Title becomes a `TextField` pre-filled with current title
  - Metadata pills become dropdowns (status, kind, priority)
  - Category becomes a `TextField`
  - Description becomes a `TextField` with `maxLines: 6`
  - Dependencies become an editable chip input
  - Tags become an editable chip input
  - Effort becomes a radio selector
- Action buttons change to: "Cancel" (reverts to detail mode) and "Save" (calls `updateTicket`)

**Option B: Reuse TicketCreateForm with pre-population**

Create an `editing` mode flag on `TicketCreateForm` that pre-populates all fields and calls `updateTicket` instead of `createTicket`.

Choose whichever is simpler. If Option A, create a new widget `TicketEditForm` or add the editing state to `TicketDetailPanel`. If Option B, modify `TicketCreateForm` to accept an optional `TicketData? editingTicket` parameter.

#### Tests to Write

Add to `frontend/test/widget/ticket_detail_panel_test.dart` or create `frontend/test/widget/ticket_edit_test.dart`:

1. **Edit button switches to edit mode:** Tapping Edit changes the view to editable fields
2. **Fields are pre-populated:** Edit mode shows the current ticket's values
3. **Save applies changes:** Modifying title and clicking Save updates the ticket
4. **Cancel reverts:** Clicking Cancel returns to detail mode without saving
5. **Status change persists:** Changing status in edit mode and saving updates the status

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Edit button on detail panel works
- All ticket fields are editable
- Save persists changes, Cancel discards
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 1.10 — Phase 1 Integration Testing

**Assigned to: Senior Dev (opus)**

#### Overview

Verify that all Phase 1 components work together end-to-end. This task writes integration-style tests that exercise the full flow from navigation to ticket creation to selection to editing. Also ensures all existing tests still pass.

#### Background — Read These Files First

- `TESTING.md` — test patterns, especially integration test guidance
- `frontend/test/test_helpers.dart` — helpers
- All Phase 1 source files

#### What to Implement

No new production code. Only tests.

#### Tests to Write

Create `frontend/test/widget/ticket_integration_test.dart`:

1. **Full creation flow:** Navigate to tickets → click (+) → fill title "Test Ticket" → fill description → set kind to bugfix → click Create → verify ticket appears in list → verify ticket is selected in detail
2. **Search flow:** Create 3 tickets with different titles → type search query → verify only matching tickets visible → clear search → all visible again
3. **Filter flow:** Create tickets with different statuses → apply status filter → verify only matching tickets visible
4. **Group-by switching:** Create tickets in different categories → verify category groups show → switch group-by to status → verify groups change
5. **Edit flow:** Create a ticket → select it → click Edit → change title → Save → verify title updated in list and detail
6. **Delete flow:** Create a ticket → select it → delete → verify removed from list
7. **Dependency management:** Create TKT-001 and TKT-002 → edit TKT-002 to depend on TKT-001 → verify dependency shows in detail → verify TKT-001's "Blocks" shows TKT-002
8. **Cycle prevention:** Create A, B, C → A depends on B → B depends on C → attempt C depends on A → verify it's rejected
9. **Persistence round-trip:** Create tickets → recreate the TicketBoardState and load → verify all tickets restored

Also run the full test suite:
10. **No regressions:** `./frontend/run-flutter-test.sh` passes with zero failures

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/test/widget/ticket_integration_test.dart` exists with all 10 test cases
- ALL tests in the project pass (not just the new ones)
- Zero test failures from `./frontend/run-flutter-test.sh`

---

## Phase 2: Agent Ticket Creation

### Task 2.1 — Bulk Proposal State Management

**Assigned to: Senior Dev (opus)**

#### Overview

Extend `TicketBoardState` to support bulk ticket proposals from agents. Proposals are staged as `draft` tickets with a review workflow — the user can check/uncheck, edit, approve, or reject.

#### Background — Read These Files First

- `frontend/lib/state/ticket_board_state.dart` — existing state (Tasks 1.2)
- `frontend/lib/services/event_handler.dart` — how events are processed, tool interception pattern
- `docs/features/project-management.md` — "Agent Integration" section

#### What to Implement

**Add to `TicketBoardState`:**

New types:
```dart
@immutable
class TicketProposal {
  final String title;
  final String description;
  final TicketKind kind;
  final TicketPriority priority;
  final TicketEffort effort;
  final String? category;
  final Set<String> tags;
  final List<int> dependsOnIndices; // indices into the proposal array
  const TicketProposal({...});
  factory TicketProposal.fromJson(Map<String, dynamic> json) => ...;
}
```

New state fields:
- `String? _proposalSourceChatId` — which chat proposed these tickets
- `String? _proposalSourceChatName`
- `Set<int> _proposalCheckedIds = {}` — which proposed tickets are checked for approval
- `int? _proposalEditingId` — which proposed ticket is being inline-edited

New methods:
- `List<TicketData> proposeBulk(List<TicketProposal> proposals, {required String sourceChatId, required String sourceChatName})`:
  - Creates `draft` tickets from proposals
  - Converts `dependsOnIndices` to actual ticket IDs
  - All newly created tickets are auto-checked
  - Sets `_detailMode = TicketDetailMode.bulkReview`
  - Returns the created tickets
- `void toggleProposalChecked(int ticketId)` — toggle check state
- `void setProposalAllChecked(bool checked)` — check/uncheck all
- `void setProposalEditing(int? ticketId)` — select ticket for inline editing
- `void approveBulk()`:
  - Checked draft tickets → status `ready`
  - Unchecked draft tickets → deleted
  - Returns to detail mode
  - Returns summary string for tool result
- `void rejectAll()`:
  - All draft tickets deleted
  - Returns to detail mode
- `String get proposalSourceChatName`
- `List<TicketData> get proposedTickets` — all draft tickets from current proposal
- `Set<int> get proposalCheckedIds`
- `int? get proposalEditingId`

#### Tests to Write

Create `frontend/test/state/ticket_board_bulk_test.dart`:

1. **proposeBulk creates draft tickets:** All created tickets have status `draft`
2. **proposeBulk converts dependency indices:** Index 0 maps to the first created ticket's ID
3. **proposeBulk invalid dependency index:** Out-of-range indices are silently dropped
4. **proposeBulk sets detailMode to bulkReview**
5. **toggleProposalChecked:** Toggling flips the checked state
6. **setProposalAllChecked(true):** Checks all proposed tickets
7. **setProposalAllChecked(false):** Unchecks all
8. **approveBulk:** Checked tickets become `ready`, unchecked are deleted
9. **approveBulk returns to detail mode**
10. **rejectAll:** All draft tickets are deleted
11. **proposalSourceChatName:** Returns the correct chat name

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Bulk proposal API works correctly
- All 11 test cases pass
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 2.2 — Bulk Review Panel UI

**Assigned to: Engineer (sonnet)**

#### Overview

Build the bulk review panel that appears when an agent proposes tickets. Shows a table of proposals with checkboxes, an inline edit card for the selected proposal, and approve/reject action buttons.

#### Background — Read These Files First

- `FLUTTER.md` — coding standards
- `TESTING.md` — test patterns
- `frontend/lib/state/ticket_board_state.dart` — bulk proposal state (Task 2.1)
- `frontend/lib/widgets/ticket_visuals.dart` — visual utilities (Task 1.4)
- `docs/mocks/ticket-bulk-review-mock.html` — the exact visual design

#### What to Implement

Create `frontend/lib/panels/ticket_bulk_review_panel.dart`:

**Static test keys:**
```dart
class TicketBulkReviewKeys {
  TicketBulkReviewKeys._();
  static const Key selectAllButton = Key('bulk-review-select-all');
  static const Key deselectAllButton = Key('bulk-review-deselect-all');
  static const Key rejectAllButton = Key('bulk-review-reject-all');
  static const Key approveButton = Key('bulk-review-approve');
  static const Key editCard = Key('bulk-review-edit-card');
}
```

**Widget: `TicketBulkReviewPanel extends StatelessWidget`**

Layout:
1. **Header:**
   - Icon: `playlist_add_check`, title: "Review Proposed Tickets"
   - Subtitle: "Agent proposed N tickets from chat [chatName]"

2. **Table:**
   - Columns: Checkbox, ID, Title, Kind, Category, Depends
   - Each row from `ticketBoard.proposedTickets`
   - Checkbox: checked state from `proposalCheckedIds`, tap calls `toggleProposalChecked`
   - Unchecked rows: dimmed with reduced opacity
   - Row tap: calls `setProposalEditing(ticket.id)`
   - Selected row: highlighted background

3. **Inline edit card** (shown below the table when `proposalEditingId` is not null):
   - Card with `surfaceContainerLow` background
   - Editable fields: title `TextField`, kind `DropdownButton`, category `TextField`, dependencies chip editor, description `TextField`
   - Changes call `updateTicket` on the state
   - Close button to dismiss

4. **Action bar** (bottom):
   - "Select All" `TextButton`
   - "Deselect All" `TextButton`
   - "Reject All" `OutlinedButton` (red tint)
   - "Approve N Selected" `FilledButton` (purple) — N is count of checked tickets

#### Tests to Write

Create `frontend/test/widget/ticket_bulk_review_panel_test.dart`:

1. **Renders proposals:** Shows all proposed tickets in the table
2. **Checkbox toggles:** Tapping checkbox calls `toggleProposalChecked`
3. **Unchecked rows dimmed:** Unchecked rows have reduced opacity
4. **Select All:** Tapping "Select All" checks all proposals
5. **Deselect All:** Tapping "Deselect All" unchecks all
6. **Row tap opens edit card:** Tapping a row shows the inline edit card
7. **Edit card has correct values:** The edit card shows the selected ticket's data
8. **Approve button count:** The approve button shows the correct count
9. **Approve calls approveBulk:** Tapping Approve calls the state method
10. **Reject All calls rejectAll:** Tapping Reject All calls the state method

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `frontend/lib/panels/ticket_bulk_review_panel.dart` exists
- All 10 test cases pass
- Panel matches the mockup layout
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 2.3 — Event Handler Integration for create_tickets Tool

**Assigned to: Senior Dev (opus)**

#### Overview

Wire the `create_tickets` tool into the agent event pipeline. When an agent calls `create_tickets`, the `EventHandler` intercepts it, parses the proposals, stages them in `TicketBoardState`, and navigates to the bulk review panel. After the user approves/rejects, a tool result is sent back to the agent.

#### Background — Read These Files First

- `frontend/lib/services/event_handler.dart` — how events are processed, the `handleEvent` switch on event types, tool invocation/completion handling
- `agent_sdk_core/lib/src/types/insights_events.dart` — `ToolInvocationEvent`, `ToolCompletionEvent` types
- `frontend/lib/state/ticket_board_state.dart` — `proposeBulk()` (Task 2.1)
- `frontend/lib/models/chat.dart` — `ChatState`, session management, how tool results are sent
- `docs/features/project-management.md` — "How Agents Create Tickets" section

#### What to Implement

**1. Tool detection in EventHandler:**
- In the `ToolInvocationEvent` handler, check if `event.toolName == 'create_tickets'`
- If so:
  - Parse `event.toolInput['tickets']` as a list of `TicketProposal.fromJson()`
  - Validate: reject if empty, reject if more than 50, reject if missing required `title`/`description`/`kind` fields
  - Get the `TicketBoardState` — this requires EventHandler to have access to it. Add a `TicketBoardState?` field that gets set during initialization.
  - Call `ticketBoard.proposeBulk(proposals, sourceChatId: chat.data.id, sourceChatName: chat.data.name)`
  - **Do NOT send a tool result yet** — the result depends on user review

**2. Tool result after review:**
- When `approveBulk()` is called on `TicketBoardState`, it should emit a callback or event that `EventHandler` can listen to
- The tool result message should summarize what was approved and rejected
- Send the result back via the chat's transport: `chat.sendToolResult(toolUseId, resultText)`
- This may require storing the pending `toolUseId` from the `ToolInvocationEvent`

**3. Navigation:**
- After `proposeBulk()` is called, the UI needs to navigate to the ticket screen (index 4) and show the bulk review panel
- This can be handled by `TicketBoardState` setting `detailMode = bulkReview`, and having `MainScreen` listen for this and switch to index 4

**4. Session options update:**
- The `create_tickets` tool needs to be available to the agent. This may involve:
  - Adding it to the system prompt that's sent with each session
  - Or registering it as a custom tool in the session options
  - Investigate how the existing session setup works in `ChatState` and `BackendService`

#### Tests to Write

Create `frontend/test/services/event_handler_ticket_test.dart`:

1. **Tool detection:** EventHandler recognizes `create_tickets` tool invocation
2. **Proposal parsing:** Valid tool input creates correct `TicketProposal` objects
3. **Invalid input handling:** Missing required fields logs error, doesn't crash
4. **Too many tickets:** More than 50 proposals are rejected with error
5. **Empty proposals:** Empty array is rejected
6. **Proposals staged as draft:** After tool invocation, draft tickets exist in TicketBoardState
7. **Detail mode set to bulkReview:** After proposals, the state is in bulk review mode

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- `create_tickets` tool calls are intercepted and processed
- Proposals appear in the bulk review panel
- Tool result is sent back after user review
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 2.4 — Wire Bulk Review into Ticket Screen

**Assigned to: Engineer (sonnet)**

#### Overview

Connect the bulk review panel into the ticket screen's mode switching, and ensure navigation from the main view to the ticket screen happens automatically when proposals arrive.

#### Background — Read These Files First

- `frontend/lib/screens/ticket_screen.dart` — mode switching (Task 1.8)
- `frontend/lib/panels/ticket_bulk_review_panel.dart` — the bulk review panel (Task 2.2)
- `frontend/lib/screens/main_screen.dart` — navigation index switching

#### What to Implement

1. **Update `TicketScreen`**: Add `TicketDetailMode.bulkReview` case that renders `TicketBulkReviewPanel()`

2. **Auto-navigate to ticket screen**: When `TicketBoardState.detailMode` changes to `bulkReview`, `MainScreen` should switch to index 4. This can be done via a listener on `TicketBoardState` in `MainScreen`.

3. **After approval/rejection**: The screen stays on the ticket view showing the approved tickets. The user can navigate back to the dashboard manually.

#### Tests to Write

Update `frontend/test/widget/ticket_screen_test.dart`:

1. **Bulk review mode:** When detailMode is bulkReview, the right panel shows TicketBulkReviewPanel
2. **After approve:** When approveBulk is called, mode returns to detail

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Bulk review panel appears in ticket screen when proposals arrive
- Navigation to ticket screen is automatic
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 2.5 — Phase 2 Integration Testing

**Assigned to: Senior Dev (opus)**

#### Overview

End-to-end testing of the agent ticket creation flow. Simulate an agent calling `create_tickets`, verify proposals appear, test the review workflow, and verify the tool result.

#### What to Implement

No new production code. Only tests.

#### Tests to Write

Create `frontend/test/widget/ticket_bulk_integration_test.dart`:

1. **Full proposal flow:** Simulate tool event with 3 proposals → verify bulk review shows → check 2, uncheck 1 → approve → verify 2 tickets are `ready`, 1 is deleted
2. **Reject all flow:** Simulate proposals → reject all → verify all deleted, mode returns to detail
3. **Edit before approve:** Simulate proposals → select one → edit title → approve → verify edited title persisted
4. **Dependency resolution:** Proposals with `dependsOnIndices` → verify converted to real IDs after creation
5. **No regressions:** Full test suite passes

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- All integration tests pass
- Full test suite passes with zero failures

---

## Phase 3: Agent Dispatch

### Task 3.1 — Ticket Dispatch Service

**Assigned to: Senior Dev (opus)**

#### Overview

Create the service that handles dispatching an agent to work on a ticket. This involves creating (or selecting) a worktree, creating a chat, composing the initial prompt with ticket context, and linking everything together.

#### Background — Read These Files First

- `frontend/lib/services/worktree_service.dart` — how worktrees are created
- `frontend/lib/models/chat.dart` — `ChatData.create()`, `ChatState`, session creation
- `frontend/lib/models/worktree.dart` — `WorktreeState`, `addChat()`
- `frontend/lib/state/ticket_board_state.dart` — `beginWork()`, status transitions
- `frontend/lib/state/selection_state.dart` — navigation methods
- `docs/features/project-management.md` — "How Agents Work on Tickets" section

#### What to Implement

Create `frontend/lib/services/ticket_dispatch_service.dart`:

```dart
class TicketDispatchService {
  final TicketBoardState _ticketBoard;
  final ProjectState _project;
  final SelectionState _selection;
  final WorktreeService _worktreeService;
  final GitService _gitService;
  final PersistenceService _persistence;

  /// Begin work on a ticket in a new worktree
  Future<void> beginInNewWorktree(int ticketId) async {
    // 1. Get ticket data
    // 2. Derive branch name: 'tkt-{id}-{slugified-title}' (max 50 chars)
    // 3. Create linked worktree via WorktreeService
    // 4. Create chat in the new worktree
    // 5. Set chat's initial/welcome draft to the ticket context prompt
    // 6. Link ticket to worktree and chat
    // 7. Set ticket status to active
    // 8. Navigate to the new chat (switch to main view, select worktree, select chat)
  }

  /// Begin work on a ticket in an existing worktree
  Future<void> beginInWorktree(int ticketId, WorktreeState worktree) async {
    // Similar but skip worktree creation
  }

  /// Build the initial prompt for an agent working on a ticket
  String buildTicketPrompt(TicketData ticket, List<TicketData> allTickets) {
    // Include ticket title, description
    // List completed dependencies with summaries
    // List incomplete dependencies as blockers
    // Return formatted prompt string
  }
}
```

Also add `LinkedWorktree` and `LinkedChat` linking methods to `TicketBoardState`:
- `void linkWorktree(int ticketId, String worktreeRoot, String? branch)`
- `void linkChat(int ticketId, String chatId, String chatName, String worktreeRoot)`

#### Tests to Write

Create `frontend/test/services/ticket_dispatch_test.dart`:

1. **Branch name derivation:** Various titles produce valid branch names (no spaces, no special chars, max 50 chars)
2. **Prompt includes ticket info:** Built prompt contains ticket ID, title, description
3. **Prompt lists completed deps:** Completed dependencies are listed with checkmarks
4. **Prompt handles no deps:** Works correctly when ticket has no dependencies
5. **linkWorktree adds to ticket:** After linking, ticket's `linkedWorktrees` contains the entry
6. **linkChat adds to ticket:** After linking, ticket's `linkedChats` contains the entry
7. **beginInNewWorktree changes status to active**

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Dispatch service creates worktree + chat with ticket context
- Ticket gets linked and status transitions to active
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 3.2 — Wire Dispatch Actions into Detail Panel

**Assigned to: Engineer (sonnet)**

#### Overview

Connect the "Begin work" buttons in the ticket detail panel to the `TicketDispatchService`. The "Begin in new worktree" button creates a new worktree and starts a chat. The "Begin in worktree..." button shows a picker dialog.

#### Background — Read These Files First

- `frontend/lib/panels/ticket_detail_panel.dart` — the action buttons (Task 1.6)
- `frontend/lib/services/ticket_dispatch_service.dart` — dispatch service (Task 3.1)
- `frontend/lib/models/project.dart` — `ProjectState.allWorktrees` for the picker
- `frontend/lib/screens/main_screen.dart` — navigation index for returning to main view

#### What to Implement

1. **"Begin in new worktree" button:** Enable (was disabled placeholder). On tap, call `ticketDispatch.beginInNewWorktree(ticket.id)`. Show loading indicator while worktree is being created.

2. **"Begin in worktree..." button:** Enable. On tap, show a dialog listing all available worktrees. On selection, call `ticketDispatch.beginInWorktree(ticket.id, selectedWorktree)`.

3. **"Open linked chat" button:** Show only when `linkedChats` is not empty. On tap, navigate to the chat.

4. **Button state logic:**
   - "Begin" buttons: only enabled when status is `ready` or `needsInput`
   - "Open linked chat": only shown when links exist
   - "Mark Complete" and "Cancel": only shown when not already terminal

5. **Provider wiring:** Add `TicketDispatchService` as a provider, or create it on-demand from available providers.

#### Tests to Write

Update `frontend/test/widget/ticket_detail_panel_test.dart`:

1. **Begin buttons enabled when ready:** For a `ready` ticket, Begin buttons are enabled
2. **Begin buttons disabled when active:** For an `active` ticket, Begin buttons are disabled
3. **Open linked chat shows:** When ticket has linked chats, the button appears
4. **Open linked chat hidden:** When no linked chats, the button is absent
5. **Worktree picker dialog:** Tapping "Begin in worktree..." opens a dialog with worktree options

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Action buttons work correctly based on ticket state
- Dispatch creates worktree + chat and navigates
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 3.3 — Status Auto-Transitions from Chat Events

**Assigned to: Senior Dev (opus)**

#### Overview

Wire ticket status updates to chat lifecycle events. When a linked chat's session completes, the ticket should transition to `inReview`. When the agent needs input, the ticket should transition to `needsInput`. Cost stats should accumulate.

#### Background — Read These Files First

- `frontend/lib/services/event_handler.dart` — `TurnCompleteEvent`, `PermissionRequestEvent` handling
- `frontend/lib/state/ticket_board_state.dart` — status transition methods
- `frontend/lib/models/chat.dart` — `ChatState` working state, session lifecycle

#### What to Implement

1. **Ticket-aware event handling in EventHandler:**
   - After processing `TurnCompleteEvent`: check if the chat is linked to any tickets. If so, update ticket status to `inReview` and accumulate cost stats.
   - After processing `PermissionRequestEvent`: if chat is linked, update ticket status to `needsInput`.
   - When user responds to permission: update ticket back to `active`.

2. **Chat-to-ticket mapping:**
   - `TicketBoardState` needs a method: `List<TicketData> getTicketsForChat(String chatId)`
   - EventHandler uses this to find linked tickets

3. **Cost stats accumulation:**
   - On `TurnCompleteEvent`, get the chat's usage stats
   - Add to the ticket's `costStats` (create if null, accumulate if exists)
   - Update `totalTokens`, `totalCost` from the turn's usage

4. **Dependency auto-unblock:**
   - When a ticket is marked `completed`, scan all other tickets
   - For each ticket that has this one in `dependsOn`: check if ALL dependencies are now complete
   - If so, transition from `blocked` → `ready`

#### Tests to Write

Create `frontend/test/services/ticket_status_transition_test.dart`:

1. **Turn complete → inReview:** When a linked chat's turn completes, ticket goes to `inReview`
2. **Permission request → needsInput:** When a linked chat requests permission, ticket goes to `needsInput`
3. **Permission response → active:** When permission is responded, ticket goes back to `active`
4. **Cost accumulation:** Turn complete adds token usage to ticket's costStats
5. **Cost accumulation from zero:** First turn creates costStats from null
6. **Dependency auto-unblock:** Completing TKT-001 that TKT-002 depends on → TKT-002 becomes `ready` (if it was `blocked`)
7. **Partial dependency unblock:** If TKT-003 depends on both TKT-001 and TKT-002, completing only TKT-001 does NOT unblock TKT-003
8. **Chat not linked:** Events for chats not linked to any ticket don't crash or cause transitions

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Ticket status auto-updates based on chat lifecycle events
- Cost stats accumulate correctly
- Dependency auto-unblocking works
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 3.4 — Phase 3 Integration Testing

**Assigned to: Senior Dev (opus)**

#### Overview

End-to-end testing of the dispatch flow. Verify create ticket → begin work → agent runs → status updates → ticket completes.

#### Tests to Write

Create `frontend/test/widget/ticket_dispatch_integration_test.dart`:

1. **Full dispatch flow:** Create ticket → Begin in new worktree → verify worktree created → verify chat created with ticket prompt → verify ticket status is `active` → verify ticket linked to worktree and chat
2. **Begin in existing worktree:** Create ticket → Begin in existing worktree → verify chat created in that worktree
3. **Open linked chat navigation:** Create and dispatch ticket → click "Open linked chat" → verify navigation to correct worktree and chat
4. **Status transitions end-to-end:** Dispatch ticket → simulate turn complete → verify `inReview` → mark complete → verify `completed`
5. **No regressions:** Full test suite passes

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Full dispatch flow works end-to-end
- All tests pass

---

## Phase 4: Graph View

### Task 4.1 — Graph Layout Algorithm

**Assigned to: Senior Dev (opus)**

#### Overview

Implement the DAG layout algorithm for the ticket dependency graph. This is a standalone computational module — no UI yet. It takes a list of tickets with dependencies and outputs positioned coordinates for nodes and edges.

#### Background — Read These Files First

- `frontend/pubspec.yaml` — check if `graphview` is already a dependency; if not, evaluate whether to add it or build custom
- `docs/mocks/ticket-graph-view-mock.html` — the visual design showing layered DAG layout
- `docs/features/project-management.md` — "TicketGraphView" section

#### What to Implement

Create `frontend/lib/widgets/ticket_graph_layout.dart`:

**Option A: Use `graphview` package**
- Add to `pubspec.yaml`
- Create a wrapper that converts `List<TicketData>` to `graphview`'s graph model
- Use `SugiyamaConfiguration` for layered DAG layout
- Return positioned node rectangles and edge paths

**Option B: Custom layout (if graphview is insufficient)**
```dart
class TicketGraphLayout {
  /// Compute layout for a set of tickets
  static GraphLayoutResult compute(List<TicketData> tickets, {
    double nodeWidth = 140,
    double nodeHeight = 80,
    double horizontalGap = 40,
    double verticalGap = 60,
  });
}

@immutable
class GraphLayoutResult {
  final Map<int, Offset> nodePositions; // ticketId -> (x, y)
  final List<GraphEdge> edges;
  final Size totalSize;
}

@immutable
class GraphEdge {
  final int fromId;
  final int toId;
  final List<Offset> points; // line segments
}
```

Algorithm (Sugiyama-style):
1. **Topological sort** — identify layers (tickets with no deps in layer 0, etc.)
2. **Handle disconnected components** — lay them out side by side
3. **Assign layers** — each ticket goes in the layer after its latest dependency
4. **Order within layers** — minimize edge crossings (barycenter heuristic)
5. **Assign coordinates** — center each layer, space evenly

#### Tests to Write

Create `frontend/test/widget/ticket_graph_layout_test.dart`:

1. **Single ticket:** One ticket, positioned at origin
2. **Linear chain:** A→B→C, laid out in 3 layers vertically
3. **Diamond:** A→B, A→C, B→D, C→D, laid out as diamond shape
4. **Disconnected components:** Two separate subgraphs, positioned side by side
5. **No tickets:** Empty input returns empty result
6. **Wide graph:** 10 tickets all depending on 1, laid out in 2 layers with correct spacing
7. **Total size is correct:** The bounding box encompasses all nodes

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Layout algorithm produces correct positions for all test cases
- Handles edge cases (empty, single, disconnected)
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 4.2 — Graph View Widget

**Assigned to: Engineer (sonnet)**

#### Overview

Build the interactive graph visualization widget. Renders ticket nodes as cards with edges between them, supports zoom/pan, and syncs selection with the rest of the ticket screen.

#### Background — Read These Files First

- `frontend/lib/widgets/ticket_graph_layout.dart` — the layout algorithm (Task 4.1)
- `frontend/lib/widgets/ticket_visuals.dart` — visual utilities (Task 1.4)
- `frontend/lib/state/ticket_board_state.dart` — `selectedTicket`, `selectTicket`, `filteredTickets`
- `docs/mocks/ticket-graph-view-mock.html` — the exact visual design

#### What to Implement

Create `frontend/lib/panels/ticket_graph_view.dart`:

**Widget: `TicketGraphView extends StatefulWidget`**

State:
- `TransformationController _transformController` for zoom/pan
- Computed `GraphLayoutResult` from the current `filteredTickets`

Layout:
1. **Toolbar:** (same as list panel toolbar but simpler)
   - List/Graph toggle (tapping List switches `viewMode` back)
   - Ticket count label
   - Zoom in / Zoom out / Fit to screen buttons

2. **Graph area:** `InteractiveViewer` (for zoom/pan) containing a `Stack`:
   - **Edge layer:** `CustomPaint` widget that draws all edges as lines with arrowheads
   - **Node layer:** `Positioned` widgets for each ticket node

3. **Node widget (`_TicketGraphNode`):**
   - 140px wide card
   - Status color as left border (4px)
   - Header row: `TicketStatusIcon` (small) + display ID in monospace
   - Title text (max 2 lines, ellipsis overflow)
   - Bottom bar in status color (thin line)
   - Tap: `ticketBoard.selectTicket(ticket.id)`
   - Selected state: highlight ring around the card

4. **Edge painter (`_EdgePainter extends CustomPainter`):**
   - Draws lines between node centers (or edge midpoints)
   - Arrowhead at the end (dependency direction: from→depends on)
   - Color: `outlineVariant.withValues(alpha: 0.5)`

5. **Legend overlay:**
   - `Positioned(bottom: 16, left: 16)`
   - Small card showing status colors with labels

6. **Fit to screen:**
   - Calculate the bounding box of all nodes
   - Set `_transformController` to fit that box in the viewport

#### Tests to Write

Create `frontend/test/widget/ticket_graph_view_test.dart`:

1. **Renders nodes:** When tickets exist, graph nodes are rendered
2. **Empty state:** When no tickets, shows empty message
3. **Node shows ticket info:** Each node shows the display ID and title
4. **Node selection:** Tapping a node calls `selectTicket`
5. **Selected node highlighted:** Selected node has different styling
6. **Zoom buttons work:** Tapping zoom in/out changes the transform
7. **View toggle:** Tapping List toggle calls `setViewMode(list)`

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- Graph renders with correct topology
- Zoom/pan works
- Selection syncs with detail panel
- `./frontend/run-flutter-test.sh` (all tests) passes

---

### Task 4.3 — Wire Graph View into Ticket Screen

**Assigned to: Engineer (sonnet)**

#### Overview

Connect the graph view into the ticket screen's view mode switching. When the user toggles to graph view, the right panel (or both panels) should show the graph.

#### Background — Read These Files First

- `frontend/lib/screens/ticket_screen.dart` — current layout
- `frontend/lib/panels/ticket_graph_view.dart` — graph widget (Task 4.2)
- `frontend/lib/state/ticket_board_state.dart` — `viewMode`

#### What to Implement

When `ticketBoard.viewMode == TicketViewMode.graph`:
- The right panel shows `TicketGraphView` (replaces the detail panel)
- The list panel is still visible on the left (for navigation and context)
- OR: The graph takes the full width (list panel hidden). Choose whichever makes more sense given the mockup design.

When the user selects a ticket in the graph:
- `selectedTicket` updates
- Switching back to list mode shows the detail for the selected ticket

#### Tests to Write

Update `frontend/test/widget/ticket_screen_test.dart`:

1. **Graph mode:** When viewMode is graph, the graph view is shown
2. **List mode:** When viewMode is list, the detail panel is shown
3. **Selection persists across mode switch:** Select ticket in graph → switch to list → detail shows that ticket

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- View mode toggle works
- Graph and list modes both work correctly
- `./frontend/run-flutter-test.sh` (all tests) passes

---

## Phase 5: Coordination & Automation

### Task 5.1 — Auto-Readiness and Notifications

**Assigned to: Engineer (sonnet)**

#### Overview

When a ticket is completed, automatically check if any blocked tickets are now unblocked (all dependencies complete). Show a desktop notification when a ticket becomes ready.

#### Background — Read These Files First

- `frontend/lib/state/ticket_board_state.dart` — current state management
- `frontend/lib/services/notification_service.dart` — how desktop notifications work (if it exists, check)
- Task 3.3 already implements the core auto-unblock logic. This task extends it with notifications.

#### What to Implement

1. **Notification on readiness:** When `markCompleted` triggers auto-unblock (blocked → ready), show a desktop notification: "TKT-005: [title] is now ready to work on"

2. **Badge update:** The nav rail badge already shows `activeCount`. Verify it also updates correctly when tickets transition.

3. **Visual indicator in list:** Newly-ready tickets could have a brief highlight animation (optional, low priority).

#### Tests to Write

1. **Notification fires on auto-ready:** When a dependency completes and unblocks a ticket, a notification is triggered
2. **No notification for manual status change:** Manually setting status to `ready` doesn't double-notify
3. **Badge updates:** Nav rail badge count updates when ticket becomes active

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

---

### Task 5.2 — Ticket Splitting

**Assigned to: Engineer (sonnet)**

#### Overview

Add the ability to split a ticket into subtasks. The parent ticket's status becomes `split` and kind becomes `split`. Child tickets are created with the parent as a dependency.

#### Background — Read These Files First

- `frontend/lib/state/ticket_board_state.dart` — `createTicket()`, dependency management
- `frontend/lib/panels/ticket_detail_panel.dart` — "Split into subtasks" button

#### What to Implement

1. **Split method on TicketBoardState:**
   ```dart
   List<TicketData> splitTicket(int parentId, List<({String title, TicketKind kind})> subtasks) {
     // Update parent: status → split, kind → split
     // Create child tickets with parent in dependsOn
     // Return created children
   }
   ```

2. **Split dialog:** When user clicks "Split into subtasks" on the detail panel:
   - Show a dialog with a dynamic list of subtask rows
   - Each row: title TextField + kind dropdown + remove button
   - "Add subtask" button to add more rows
   - "Cancel" and "Split" action buttons

3. **Visual indicator:** Split tickets show a tree icon and their children are visually linked in the list view.

#### Tests to Write

Create `frontend/test/state/ticket_split_test.dart`:

1. **Split creates children:** Splitting a ticket creates the specified subtasks
2. **Parent becomes split:** Parent ticket status and kind both become `split`
3. **Children depend on parent:** Each child has the parent in `dependsOn`
4. **Children inherit category:** Children get the parent's category
5. **Empty subtasks rejected:** Splitting with no subtasks throws

Create `frontend/test/widget/ticket_split_dialog_test.dart`:

6. **Dialog renders:** Split dialog shows with input rows
7. **Add subtask:** Clicking "Add subtask" adds a new row
8. **Remove subtask:** Clicking remove removes the row
9. **Split button creates tickets:** Filling in subtasks and clicking Split creates them

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

---

### Task 5.3 — Status Bar Integration

**Assigned to: Engineer (sonnet)**

#### Overview

Show ticket summary statistics in the app's status bar at the bottom of the screen.

#### Background — Read These Files First

- `frontend/lib/screens/main_screen.dart` — check if a status bar exists already; if so, extend it
- `frontend/lib/state/ticket_board_state.dart` — computed getters for counts
- `docs/mocks/ticket-screen-layout-mock.html` — status bar design

#### What to Implement

1. **Ticket status summary widget:** A small widget that shows "14 tickets · 3 active · 4 ready" (or similar format)

2. **Integration:** Add the widget to the bottom of `MainScreen` or the ticket screen's bottom bar.

3. **Reactive:** Watches `TicketBoardState` to update counts in real-time.

#### Tests to Write

1. **Renders correct counts:** Shows accurate ticket counts
2. **Updates on change:** When a ticket status changes, the counts update
3. **Zero state:** When no tickets, shows "0 tickets" or hides

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

---

### Task 5.4 — One-Click Dispatch Queue

**Assigned to: Engineer (sonnet)**

#### Overview

Add a "Start next ready ticket" button that picks the highest-priority ready ticket and dispatches it.

#### Background — Read These Files First

- `frontend/lib/services/ticket_dispatch_service.dart` — dispatch methods (Task 3.1)
- `frontend/lib/state/ticket_board_state.dart` — filtering ready tickets

#### What to Implement

1. **Next ready ticket getter** on `TicketBoardState`:
   ```dart
   TicketData? get nextReadyTicket {
     // Return highest-priority ready ticket (critical > high > medium > low)
     // Break ties by ticket ID (lower first)
   }
   ```

2. **Button in ticket screen header or toolbar:**
   - "Start Next" button, enabled only when `nextReadyTicket != null`
   - On tap: same as "Begin in new worktree" for the next ready ticket
   - Show which ticket will be started (tooltip or subtitle)

#### Tests to Write

1. **nextReadyTicket returns highest priority:** Among ready tickets, returns the critical one first
2. **nextReadyTicket returns null when none ready:** When no tickets are ready, returns null
3. **Button disabled when none ready**
4. **Button dispatches correct ticket**

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

---

### Task 5.5 — Final Integration Testing and Polish

**Assigned to: Senior Dev (opus)**

#### Overview

Final comprehensive testing across all phases. Verify the complete feature works end-to-end. Fix any issues found. Ensure all tests pass.

#### What to Implement

- Fix any bugs found during testing
- Ensure all edge cases are handled
- Verify persistence works across all scenarios
- Clean up any TODO comments left in the code

#### Tests to Write

Create `frontend/test/widget/ticket_full_integration_test.dart`:

1. **Complete lifecycle:** Create tickets manually → dispatch agent → agent completes → mark done → verify everything
2. **Agent proposal lifecycle:** Agent proposes → user reviews → approves → dispatches → completes
3. **Dependency chain:** Create A→B→C chain → complete C → verify B auto-unblocks → complete B → verify A auto-unblocks
4. **Split and complete:** Create ticket → split → complete subtasks → verify parent status
5. **Search and filter persistence:** Set filters → navigate away → come back → filters preserved
6. **Graph view accuracy:** Create complex dependency graph → verify graph layout matches expected topology
7. **Persistence full cycle:** Create various tickets in various states → simulate app restart (recreate providers) → verify everything restored
8. **Edge cases:** Cancel all tickets, delete tickets with dependencies, duplicate category names, very long titles, empty descriptions
9. **No regressions:** `./frontend/run-flutter-test.sh` passes with ZERO failures

#### Definition of Done

- [ ] Implemented
- [ ] Tests written and passed
- [ ] Code review passed
- [ ] Done

**Measurable criteria:**
- ALL tests in the entire project pass
- Zero `flutter analyze` warnings in new code
- Feature works end-to-end as described in the spec

---

## Summary

| Task | Phase | Description | Assigned To |
|------|-------|-------------|-------------|
| 1.1 | 1 | TicketData model and enums | Engineer (sonnet) |
| 1.2 | 1 | TicketBoardState core (CRUD + selection + DAG) | Senior Dev (opus) |
| 1.3 | 1 | Ticket screen shell and navigation rail | Engineer (sonnet) |
| 1.4 | 1 | Ticket status visuals utility | Engineer (sonnet) |
| 1.5 | 1 | Ticket list panel | Senior Dev (opus) |
| 1.6 | 1 | Ticket detail panel | Senior Dev (opus) |
| 1.7 | 1 | Ticket create form | Engineer (sonnet) |
| 1.8 | 1 | Wire ticket screen together | Engineer (sonnet) |
| 1.9 | 1 | Ticket editing | Engineer (sonnet) |
| 1.10 | 1 | Phase 1 integration testing | Senior Dev (opus) |
| 2.1 | 2 | Bulk proposal state management | Senior Dev (opus) |
| 2.2 | 2 | Bulk review panel UI | Engineer (sonnet) |
| 2.3 | 2 | Event handler integration for create_tickets | Senior Dev (opus) |
| 2.4 | 2 | Wire bulk review into ticket screen | Engineer (sonnet) |
| 2.5 | 2 | Phase 2 integration testing | Senior Dev (opus) |
| 3.1 | 3 | Ticket dispatch service | Senior Dev (opus) |
| 3.2 | 3 | Wire dispatch actions into detail panel | Engineer (sonnet) |
| 3.3 | 3 | Status auto-transitions from chat events | Senior Dev (opus) |
| 3.4 | 3 | Phase 3 integration testing | Senior Dev (opus) |
| 4.1 | 4 | Graph layout algorithm | Senior Dev (opus) |
| 4.2 | 4 | Graph view widget | Engineer (sonnet) |
| 4.3 | 4 | Wire graph view into ticket screen | Engineer (sonnet) |
| 5.1 | 5 | Auto-readiness and notifications | Engineer (sonnet) |
| 5.2 | 5 | Ticket splitting | Engineer (sonnet) |
| 5.3 | 5 | Status bar integration | Engineer (sonnet) |
| 5.4 | 5 | One-click dispatch queue | Engineer (sonnet) |
| 5.5 | 5 | Final integration testing and polish | Senior Dev (opus) |

**Total: 27 tasks** — 15 Engineer (sonnet), 12 Senior Dev (opus)

### Task Dependencies

```
Phase 1: 1.1 → 1.2 → 1.3 (parallel with 1.4) → 1.5, 1.6, 1.7 (parallel) → 1.8 → 1.9 → 1.10
Phase 2: 2.1 → 2.2 (parallel with 2.3) → 2.4 → 2.5
Phase 3: 3.1 → 3.2 (parallel with 3.3) → 3.4
Phase 4: 4.1 → 4.2 → 4.3
Phase 5: 5.1, 5.2, 5.3, 5.4 (parallel) → 5.5
```

Tasks within a phase that share no dependencies can be run in parallel. Phases must be completed sequentially.
