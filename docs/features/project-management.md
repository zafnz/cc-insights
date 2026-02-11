# Project Management — Ticket System

## Overview

A structured ticket/task system for CC-Insights that enables users to plan, track, and execute work across a project. Agents generate tickets during planning conversations, tickets form a dependency DAG (directed acyclic graph), and users can dispatch agents to work on tickets in specific worktrees.

**Why it exists**: When using Claude Code for large features, the planning phase produces a mental model of tasks and dependencies that immediately evaporates. This feature captures that structure as persistent, actionable tickets — bridging the gap between "agent understands the plan" and "human can see, edit, prioritize, and dispatch work."

### Design Principles

- **Tickets belong to the Project, not a worktree** — work may span multiple worktrees
- **Many-to-many relationships** — a ticket can be linked to multiple worktrees/chats, and vice versa
- **User is the coordinator** — no autonomous central agent; the user reviews, approves, and dispatches
- **Manual first, automation later** — manual dispatch in Phase 1, auto-readiness detection in Phase 5

---

## User Stories

### Planning & Creation

1. **As a user**, I want to describe a feature to an agent and have it generate a structured set of tickets, so I don't have to manually decompose work.
2. **As a user**, I want to review agent-proposed tickets in bulk before they are created, so I can edit titles, adjust dependencies, and reject irrelevant tickets.
3. **As a user**, I want to manually create tickets via a form, so I can add tasks the agent didn't think of.
4. **As a user**, I want each ticket to have a unique auto-incrementing ID (TKT-001, TKT-002, ...) so I can reference them easily in conversation.

### Viewing & Navigation

5. **As a user**, I want to see all tickets in a filterable, searchable list grouped by category, so I can quickly find what I'm looking for.
6. **As a user**, I want to see tickets as a dependency graph, so I can understand the execution order and identify bottlenecks.
7. **As a user**, I want to click a ticket to see its full detail — description, metadata, dependencies, linked work, and cost — in a detail panel.
8. **As a user**, I want the navigation rail to show a Tickets button with a badge count of active tickets.

### Execution & Dispatch

9. **As a user**, I want to click "Begin work" on a ticket and have an agent start working on it in a new or existing worktree, so I can dispatch work with one click.
10. **As a user**, I want to see which worktrees and chats are linked to a ticket, so I can track where work is happening.
11. **As a user**, I want ticket status to update automatically when an agent completes or gets blocked, so I don't have to manually track progress.

### Management

12. **As a user**, I want to edit ticket metadata (title, description, priority, category, dependencies, tags) after creation, so I can refine the plan as understanding evolves.
13. **As a user**, I want to split a ticket into subtasks, so I can break down work that turns out to be larger than expected.
14. **As a user**, I want to cancel tickets and see cancelled tickets dimmed in the list.

---

## Ticket Data Model

### TicketData

Immutable data class following the existing `*Data` / `*State` pattern.

```dart
@immutable
class TicketData {
  final int id;                          // Auto-increment per project (1, 2, 3, ...)
  final String displayId;                // "TKT-001" (derived from id, zero-padded)
  final String title;                    // Short summary
  final String description;              // Markdown body — detailed requirements
  final TicketStatus status;             // Current lifecycle state
  final TicketKind kind;                 // Type of work
  final TicketPriority priority;         // Urgency
  final TicketEffort effort;             // Estimated size
  final String? category;                // Grouping label (e.g., "Auth", "UI", "Backend")
  final Set<String> tags;                // Freeform labels
  final List<int> dependsOn;             // IDs of tickets this depends on
  final List<int> blocks;                // IDs of tickets this blocks (derived/denormalized)
  final List<LinkedWorktree> linkedWorktrees; // Worktrees where work is happening
  final List<LinkedChat> linkedChats;    // Chats associated with this ticket
  final String? sourceConversationId;    // Chat that created this ticket (if agent-created)
  final TicketCostStats? costStats;      // Accumulated cost/time from linked chats
  final DateTime createdAt;
  final DateTime updatedAt;

  const TicketData({...});
  TicketData copyWith({...}) => TicketData(...);
  Map<String, dynamic> toJson() => {...};
  factory TicketData.fromJson(Map<String, dynamic> json) => TicketData(...);
}
```

### Enums

```dart
enum TicketStatus {
  draft,      // Just created, not yet refined
  ready,      // Refined and ready to be worked on
  active,     // Agent is currently working on it
  blocked,    // Waiting on a dependency
  needsInput, // Agent hit a question/decision point
  inReview,   // Work done, awaiting user review
  completed,  // Done
  cancelled,  // Abandoned
}

enum TicketKind {
  feature,    // New functionality
  bugfix,     // Fix a defect
  research,   // Investigation / spike
  split,      // Meta-ticket that was split into subtasks
  question,   // Decision point / question to resolve
  test,       // Test coverage
  docs,       // Documentation
  chore,      // Maintenance / cleanup
}

enum TicketPriority { low, medium, high, critical }

enum TicketEffort { small, medium, large }
```

### Supporting Types

```dart
@immutable
class LinkedWorktree {
  final String worktreeRoot;
  final String? branch;     // Snapshot at link time
  const LinkedWorktree({...});
}

@immutable
class LinkedChat {
  final String chatId;
  final String chatName;
  final String worktreeRoot;
  const LinkedChat({...});
}

@immutable
class TicketCostStats {
  final int totalTokens;
  final double totalCost;
  final Duration agentTime;
  final Duration waitingTime;
  const TicketCostStats({...});
}
```

### Dependency Rules (DAG Constraints)

- A ticket cannot depend on itself
- Dependencies must not form cycles — validate on every add
- A ticket in `blocked` status has at least one incomplete dependency
- When all dependencies complete, status can auto-transition `blocked` → `ready`

---

## State Management

### TicketBoardState

Manages the full collection of tickets for a project. Analogous to how `ProjectState` manages worktrees.

```dart
class TicketBoardState extends ChangeNotifier {
  final String projectId;
  List<TicketData> _tickets = [];
  int _nextId = 1;

  // Selection & view state
  int? _selectedTicketId;
  TicketViewMode _viewMode = TicketViewMode.list;  // list | graph
  String _searchQuery = '';
  TicketStatus? _statusFilter;
  TicketKind? _kindFilter;
  String? _categoryFilter;
  TicketGroupBy _groupBy = TicketGroupBy.category;

  // Computed views
  List<TicketData> get filteredTickets => ...;
  Map<String, List<TicketData>> get groupedTickets => ...;
  TicketData? get selectedTicket => ...;
  Map<String, CategoryProgress> get categoryProgress => ...;

  // CRUD
  TicketData createTicket({...});
  void updateTicket(int id, TicketData Function(TicketData) updater);
  void deleteTicket(int id);

  // Bulk operations (for agent proposals)
  List<TicketData> proposeBulk(List<TicketProposal> proposals);
  void approveBulk(List<int> ids);
  void rejectBulk(List<int> ids);

  // Status transitions
  void beginWork(int ticketId, String worktreeRoot, String chatId);
  void markCompleted(int ticketId);
  void markBlocked(int ticketId);
  void markNeedsInput(int ticketId);

  // Dependency management
  void addDependency(int ticketId, int dependsOnId);  // validates DAG
  void removeDependency(int ticketId, int dependsOnId);
  bool wouldCreateCycle(int fromId, int toId);

  // Persistence
  Future<void> save();
  Future<void> load();
}

enum TicketViewMode { list, graph }
enum TicketGroupBy { category, status, kind, priority }
```

### Integration with SelectionState

Add a `ContentPanelMode` value for the ticket screen, or — since the mockup shows a full-screen layout (ticket list + detail side-by-side) — add a new `IndexedStack` index in `MainScreen`, similar to how the File Manager screen works.

```dart
// Option: New IndexedStack index in MainScreen
// Index 0: Main panels (dashboard)
// Index 1: File manager
// Index 2: Settings
// Index 3: Log viewer
// Index 4: Ticket board   <-- NEW
```

The navigation rail gets a new button:

```dart
_NavRailButton(
  icon: Icons.task_alt_outlined,
  selectedIcon: Icons.task_alt,
  tooltip: 'Tickets',
  isSelected: _selectedNavIndex == 4,
  badge: ticketBoard.activeCount,  // number of active tickets
  onTap: () => setState(() => _selectedNavIndex = 4),
),
```

### Provider Setup

```dart
// In main.dart or wherever providers are configured
ChangeNotifierProvider(create: (_) => TicketBoardState(projectId: projectId)),
```

`TicketBoardState` is project-scoped — disposed when the project closes, created when a project opens.

---

## Persistence

### Storage Location

```
~/.ccinsights/projects/<project-hash>/
├── chats/
│   └── ...
├── tracking.jsonl
└── tickets.json              <-- NEW
```

### File Format: `tickets.json`

A single JSON file containing the full ticket state. Chosen over JSONL because:
- Tickets are mutable (status, description, dependencies change frequently)
- The set is bounded (hundreds, not thousands)
- Need random access for updates
- Need atomic writes (read-modify-write pattern)

```json
{
  "nextId": 8,
  "tickets": [
    {
      "id": 1,
      "title": "Add JWT authentication middleware",
      "description": "Create Express middleware that validates JWT tokens...",
      "status": "completed",
      "kind": "feature",
      "priority": "high",
      "effort": "medium",
      "category": "Auth",
      "tags": ["auth", "security"],
      "dependsOn": [],
      "linkedWorktrees": [
        { "worktreeRoot": "/path/to/wt", "branch": "feat-auth" }
      ],
      "linkedChats": [
        { "chatId": "chat-123", "chatName": "Auth implementation", "worktreeRoot": "/path/to/wt" }
      ],
      "sourceConversationId": "chat-001",
      "costStats": { "totalTokens": 45000, "totalCost": 0.12, "agentTimeMs": 180000, "waitingTimeMs": 30000 },
      "createdAt": "2025-07-15T10:30:00Z",
      "updatedAt": "2025-07-15T14:22:00Z"
    }
  ]
}
```

### Persistence Pattern

Follow the existing `PersistenceService` pattern with write queues:

```dart
// In PersistenceService (static methods)
static String ticketsPath(String projectId) =>
    '$baseDir/projects/$projectId/tickets.json';

static Future<void> saveTickets(String projectId, Map<String, dynamic> data) async {
  await _enqueueWrite(ticketsPath(projectId), jsonEncode(data));
}

static Future<Map<String, dynamic>?> loadTickets(String projectId) async {
  final file = File(ticketsPath(projectId));
  if (!await file.exists()) return null;
  return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
}
```

---

## UI Components

All UI follows existing patterns — `PanelWrapper` for panels, Material 3 deep purple dark theme, `surfaceContainerHighest` headers, etc. See `docs/mocks/` for visual reference.

### Ticket Screen Layout

Full-screen view (new `IndexedStack` index), composed of:

```
┌──────┬────────────────┬──────────────────────────┐
│ Nav  │  Ticket List   │     Ticket Detail         │
│ Rail │  (320px)       │     (flex)                │
│      │                │                           │
│      │  [Search]      │  TKT-003 ● Active         │
│      │  [Filter][+]   │  Add JWT auth middleware   │
│      │                │                           │
│      │  ▸ Auth (2/4)  │  [metadata pills]         │
│      │    TKT-001 ✓   │  [description]            │
│      │    TKT-002 ●   │  [dependencies]           │
│      │    TKT-003 ●   │  [linked work]            │
│      │    TKT-004 ○   │  [actions]                │
│      │                │  [cost stats]             │
│      │  ▸ UI (1/3)    │                           │
│      │    TKT-005 ○   │                           │
│      │    ...         │                           │
├──────┴────────────────┴──────────────────────────┤
│  Status bar: 14 tickets · 3 active · 4 ready     │
└──────────────────────────────────────────────────┘
```

### TicketListPanel

Left sidebar (320px). Wrapped in `PanelWrapper` with `task_alt` icon.

**Components:**
- **Search bar**: Filters tickets by title, ID, description substring
- **Toolbar**: Filter button (opens filter popover), Add (+) button (opens create form), List/Graph toggle
- **Group-by selector**: Dropdown — Category, Status, Kind, Priority
- **Category headers**: Collapsible, show name + progress (e.g., "3/7") + progress bar
- **Ticket items**: Status icon, ticket ID (monospace), title, effort badge, kind badge

**Interaction:**
- Click item → select ticket, show detail in right panel
- Click (+) → switch to create form view
- Toggle Graph → switch to graph view in the detail area

### TicketDetailPanel

Right content area. Shows full detail for the selected ticket.

**Sections:**
1. **Header**: Large status icon (40px), ticket ID, title, Edit button
2. **Metadata row**: Status pill, kind pill, priority pill, category pill
3. **Tags**: Chip row
4. **Description**: Markdown-rendered card
5. **Dependencies**: "Depends on" and "Blocks" with clickable ticket chips
6. **Linked Work**: Worktree entries (branch + path) and chat entries (name + status)
7. **Actions**: "Begin in new worktree", "Begin in worktree...", "Open linked chat", "Split into subtasks"
8. **Cost & Time**: 4-column grid — Tokens, Cost, Agent time, Waiting

### TicketCreateForm

Shown in the detail area when user clicks (+). Same layout pattern as `CreateWorktreePanel` — centered, max-width 600px, 32px padding.

**Fields:**
- Title (text input, required)
- Kind (dropdown: feature/bugfix/research/split/question/test/docs/chore)
- Priority (dropdown: low/medium/high/critical)
- Category (text input with autocomplete from existing categories)
- Description (textarea, markdown)
- Depends on (chip input — search/select existing tickets)
- Estimated effort (radio: small/medium/large)
- Tags (chip input)

**Actions:** Cancel, Create Ticket

### TicketGraphView

Shown in the detail area when user toggles to Graph view.

**Implementation:** Use the `graphview` package with Sugiyama algorithm for DAG layout. If that proves insufficient, fall back to a custom positioned layout.

**Node rendering:**
- Each node is a 140px card with: status color border, icon + ID header, title, colored progress bar
- Selected node gets highlight ring
- Edges are SVG lines with arrowhead markers

**Controls:** Zoom in/out, fit to screen, pan (drag background)

**Legend:** Bottom-left overlay showing status color meanings

### TicketBulkReviewPanel

Shown when an agent proposes tickets. Full-screen overlay or dedicated panel.

**Components:**
- **Header**: "Review Proposed Tickets" + context (which chat proposed them)
- **Table**: Checkbox, ID, Title, Kind, Category, Dependencies columns
- **Inline edit card**: Expands below selected row — editable title, kind, category, dependencies, description
- **Action bar**: Select All, Deselect All, Reject All, Approve N Selected

---

## Agent Integration

### How Agents Create Tickets

Agents create tickets via a **custom tool** registered in the session. When the user asks an agent to plan work, the agent calls this tool to propose tickets.

```dart
// Tool definition provided to the agent session
{
  "name": "create_tickets",
  "description": "Propose a set of structured tickets for the user to review. Each ticket should have a clear title, description, kind, and dependencies.",
  "input_schema": {
    "type": "object",
    "properties": {
      "tickets": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "title": { "type": "string" },
            "description": { "type": "string" },
            "kind": { "type": "string", "enum": ["feature", "bugfix", "research", "split", "question", "test", "docs", "chore"] },
            "priority": { "type": "string", "enum": ["low", "medium", "high", "critical"] },
            "effort": { "type": "string", "enum": ["small", "medium", "large"] },
            "category": { "type": "string" },
            "tags": { "type": "array", "items": { "type": "string" } },
            "dependsOnIndices": { "type": "array", "items": { "type": "integer" }, "description": "Zero-based indices into this same array for dependency ordering" }
          },
          "required": ["title", "description", "kind"]
        }
      }
    },
    "required": ["tickets"]
  }
}
```

**Flow:**
1. Agent calls `create_tickets` tool with an array of ticket proposals
2. CC-Insights intercepts the tool call in `EventHandler`
3. Proposals are staged in `TicketBoardState` as `draft` tickets
4. The Bulk Review panel opens automatically
5. User reviews, edits, approves/rejects
6. Approved tickets become `ready`; rejected ones are deleted
7. Tool result is returned to the agent summarizing what was approved

### How Agents Work on Tickets

When the user clicks "Begin work" on a ticket:

1. **Worktree selection**: User picks "new worktree" or selects an existing one
2. **Chat creation**: A new chat is created in that worktree
3. **Session initialization**: The chat's initial message includes the ticket context:
   ```
   You are working on ticket TKT-003: "Add JWT authentication middleware"

   Description:
   Create Express middleware that validates JWT tokens from the Authorization header...

   Dependencies (completed):
   - TKT-001: Set up user database schema ✓
   - TKT-002: Create user registration endpoint ✓

   Please implement this ticket. When done, summarize what you did.
   ```
4. **Linking**: The ticket is linked to the worktree and chat
5. **Status update**: Ticket status → `active`
6. **Monitoring**: As the chat progresses, cost stats accumulate on the ticket

### Status Auto-Transitions

| Event | Transition |
|-------|-----------|
| Agent calls `create_tickets` tool | → `draft` |
| User approves in bulk review | `draft` → `ready` |
| User clicks "Begin work" | `ready` → `active` |
| Agent requests permission/input | `active` → `needsInput` |
| User responds to permission/input | `needsInput` → `active` |
| Agent session completes (turn done) | `active` → `inReview` |
| All dependencies of a blocked ticket complete | `blocked` → `ready` |
| User manually marks complete | any → `completed` |
| User manually cancels | any → `cancelled` |

---

## Implementation Plan

### Phase 1: Foundation — Model, Storage, List View

**Goal:** Tickets exist, can be created manually, and appear in a list panel.

#### Files to create:
```
frontend/lib/models/ticket.dart              # TicketData, enums, supporting types
frontend/lib/state/ticket_board_state.dart    # TicketBoardState (ChangeNotifier)
frontend/lib/panels/ticket_list_panel.dart    # List view with search, filter, group-by
frontend/lib/panels/ticket_detail_panel.dart  # Detail view for selected ticket
frontend/lib/panels/ticket_create_form.dart   # Manual creation form
frontend/lib/screens/ticket_screen.dart       # Composes list + detail into a screen
frontend/test/models/ticket_test.dart         # TicketData unit tests
frontend/test/state/ticket_board_state_test.dart  # State management tests
frontend/test/widget/ticket_list_panel_test.dart  # Widget tests
frontend/test/widget/ticket_detail_panel_test.dart
frontend/test/widget/ticket_create_form_test.dart
```

#### Files to modify:
```
frontend/lib/services/persistence_service.dart  # Add ticketsPath(), saveTickets(), loadTickets()
frontend/lib/widgets/navigation_rail.dart       # Add Tickets button with badge
frontend/lib/screens/main_screen.dart           # Add IndexedStack index for ticket screen
frontend/lib/main.dart                          # Add TicketBoardState provider
```

#### Implementation steps:

1. **TicketData model** (`frontend/lib/models/ticket.dart`)
   - `@immutable class TicketData` with all fields, `copyWith`, `toJson`, `fromJson`
   - Enums: `TicketStatus`, `TicketKind`, `TicketPriority`, `TicketEffort`
   - Supporting types: `LinkedWorktree`, `LinkedChat`, `TicketCostStats`
   - `==`, `hashCode`, `toString` overrides
   - Unit tests for serialization round-trip, copyWith, equality

2. **TicketBoardState** (`frontend/lib/state/ticket_board_state.dart`)
   - CRUD operations with `notifyListeners()`
   - Auto-increment ID with `_nextId`
   - DAG cycle detection on `addDependency()` (simple DFS)
   - `blocks` list is computed (denormalized from other tickets' `dependsOn`)
   - Filter/search/group-by computed getters
   - `save()` / `load()` via `PersistenceService`
   - Unit tests for all operations, especially cycle detection

3. **Persistence** (`frontend/lib/services/persistence_service.dart`)
   - Add `ticketsPath(String projectId)` static method
   - Add `saveTickets()` and `loadTickets()` static methods
   - Use existing write-queue pattern

4. **TicketListPanel** (`frontend/lib/panels/ticket_list_panel.dart`)
   - `PanelWrapper` with title "Tickets", icon `task_alt`
   - Search `TextField` at top
   - Filter button + Add button in toolbar
   - `ListView.builder` with category group headers
   - Each item shows: status icon, ID (monospace), title, effort badge
   - `context.watch<TicketBoardState>()` for reactivity
   - Widget tests with mock state

5. **TicketDetailPanel** (`frontend/lib/panels/ticket_detail_panel.dart`)
   - Header with status icon + ID + title
   - Metadata pills row
   - Description section (use existing `MarkdownRenderer`)
   - Dependencies section with ticket chip links
   - Placeholder sections for linked work and actions (wired in Phase 3)
   - Widget tests

6. **TicketCreateForm** (`frontend/lib/panels/ticket_create_form.dart`)
   - Same layout pattern as `CreateWorktreePanel`
   - Form fields with validation
   - Category autocomplete from existing categories
   - Dependency chip input (search existing tickets)
   - "Create" calls `ticketBoard.createTicket()`, then selects the new ticket
   - Widget tests

7. **TicketScreen** (`frontend/lib/screens/ticket_screen.dart`)
   - Row layout: TicketListPanel (320px fixed) | TicketDetailPanel (flex)
   - Switches detail area between: detail, create form, graph (Phase 4)
   - Add to `MainScreen`'s `IndexedStack` at index 4

8. **Navigation rail update** (`frontend/lib/widgets/navigation_rail.dart`)
   - Add Tickets `_NavRailButton` between File Manager and the spacer
   - Badge shows count of active tickets

9. **Provider wiring** (`frontend/lib/main.dart`)
   - Add `ChangeNotifierProvider<TicketBoardState>` to the provider tree
   - Load tickets on project open
   - Save tickets on changes (debounced)

#### Verification:
- All new unit tests pass
- All new widget tests pass
- All existing tests still pass
- Can manually create, view, edit, and delete tickets
- Tickets persist across app restart

---

### Phase 2: Agent Creation — Bulk Proposals from Conversations

**Goal:** Agents can propose tickets via a tool call, and users review them in bulk.

#### Files to create:
```
frontend/lib/panels/ticket_bulk_review_panel.dart  # Bulk review UI
frontend/test/widget/ticket_bulk_review_panel_test.dart
```

#### Files to modify:
```
frontend/lib/services/event_handler.dart          # Intercept create_tickets tool call
frontend/lib/state/ticket_board_state.dart        # Add proposeBulk(), approveBulk(), rejectBulk()
frontend/lib/models/chat.dart                     # Register create_tickets tool in session options
frontend/lib/screens/ticket_screen.dart           # Show bulk review panel when proposals arrive
```

#### Implementation steps:

1. **Tool registration** — When creating a session, include `create_tickets` in the tool list or system prompt so the agent knows it can propose tickets.

2. **Event interception** — In `EventHandler`, detect when the agent calls `create_tickets`. Parse the tool input, create `draft` tickets in `TicketBoardState`, and open the bulk review panel.

3. **Bulk review panel** — Table with checkboxes, inline edit for selected row, approve/reject actions. Approved tickets become `ready`, rejected ones are deleted.

4. **Tool result** — After user review, return a tool result to the agent summarizing what was approved:
   ```
   Approved 5 of 7 proposed tickets:
   - TKT-001: Add JWT auth middleware (feature, high)
   - TKT-002: Create user model (feature, medium)
   ...
   Rejected:
   - "Add logging everywhere" — too vague
   - "Refactor all tests" — out of scope
   ```

#### Verification:
- Agent can propose tickets via tool call
- Bulk review panel appears with correct data
- Inline editing works
- Approve/reject correctly updates ticket state
- Tool result is returned to agent
- All existing tests pass

---

### Phase 3: Agent Dispatch — Begin Work on Tickets

**Goal:** Users can dispatch agents to work on tickets from the ticket detail panel.

#### Files to modify:
```
frontend/lib/panels/ticket_detail_panel.dart     # Wire up action buttons
frontend/lib/state/ticket_board_state.dart       # beginWork(), status transitions
frontend/lib/services/worktree_service.dart      # Create worktree for ticket (if new)
frontend/lib/models/chat.dart                    # Create chat with ticket context
frontend/lib/services/event_handler.dart         # Track cost stats per ticket
```

#### Implementation steps:

1. **"Begin in new worktree" action:**
   - Create a new linked worktree (branch name derived from ticket: `tkt-003-jwt-auth`)
   - Create a new chat in that worktree
   - Set the chat's initial message to the ticket context prompt
   - Link the ticket to the worktree and chat
   - Status → `active`
   - Navigate to the new chat

2. **"Begin in worktree..." action:**
   - Show a picker with existing worktrees
   - Create a new chat in the selected worktree
   - Same linking and status update

3. **Status auto-transitions:**
   - Listen to chat state changes (session complete, permission request, etc.)
   - Update ticket status accordingly
   - When all dependencies of a blocked ticket complete, transition to `ready`

4. **Cost tracking:**
   - When a linked chat accumulates usage, aggregate into the ticket's `costStats`
   - Update on `TurnComplete` events

5. **"Open linked chat" action:**
   - Navigate to the chat's worktree and select the chat
   - Switch back to dashboard view (index 0)

#### Verification:
- "Begin work" creates worktree + chat + sends initial message
- Ticket status updates as agent works
- Cost stats accumulate
- "Open linked chat" navigates correctly
- All existing tests pass

---

### Phase 4: Graph View & Visualization

**Goal:** Users can see tickets as a dependency graph.

#### Files to create:
```
frontend/lib/panels/ticket_graph_view.dart       # Graph visualization
frontend/test/widget/ticket_graph_view_test.dart
```

#### Files to modify:
```
frontend/lib/screens/ticket_screen.dart          # Toggle between list and graph
frontend/pubspec.yaml                            # Add graphview dependency (if used)
```

#### Implementation steps:

1. **Evaluate `graphview` package** — Test with Sugiyama algorithm for DAG layout. Needs to handle: multiple disconnected components, variable node sizes, edge routing.

2. **If `graphview` works:**
   - Use `GraphView` with `SugiyamaConfiguration`
   - Custom node builder: 140px card with status color, icon, ID, title, progress bar
   - Custom edge painter: lines with arrowheads
   - Tap node → select ticket (syncs with list panel)

3. **If `graphview` is insufficient:**
   - Custom layout: topological sort → assign layers → minimize crossings → position
   - Render with `CustomPaint` for edges, `Positioned` widgets for nodes
   - More work but full control

4. **Controls:** Transform widget for zoom/pan, fit-to-screen button, zoom in/out buttons

5. **Legend:** Positioned overlay at bottom-left showing status colors

6. **Sync with list:** Selecting a node in the graph selects it in the list (and vice versa). The detail panel updates regardless of which view is active.

#### Verification:
- Graph renders with correct topology
- Nodes show correct status colors
- Selecting a node updates detail panel
- Zoom/pan works
- Graph handles disconnected components
- All existing tests pass

---

### Phase 5: Coordination & Automation

**Goal:** Quality-of-life improvements for managing multiple active tickets.

#### Implementation steps:

1. **Auto-readiness detection:**
   - When a ticket completes, scan all tickets that depend on it
   - If all dependencies of a `blocked` ticket are now `completed`, transition to `ready`
   - Show a notification: "TKT-005 is now ready to work on"

2. **One-click dispatch queue:**
   - "Start next ready ticket" button on the ticket screen
   - Picks the highest-priority `ready` ticket
   - Same dispatch flow as Phase 3

3. **Ticket splitting:**
   - "Split into subtasks" action on a ticket
   - Opens a form to create N child tickets
   - Parent ticket status → `split`, kind → `split`
   - Child tickets get parent as dependency

4. **Status bar integration:**
   - Show ticket summary in the app status bar
   - Format: "14 tickets · 3 active · 4 ready"

5. **Ticket search in chat:**
   - When user types "TKT-003" in a chat message, it could be a clickable link
   - Low priority — nice to have

#### Verification:
- Auto-readiness works when dependencies complete
- One-click dispatch picks correct ticket
- Splitting creates child tickets with correct dependencies
- Status bar shows correct counts
- All existing tests pass

---

## Testing Strategy

### Unit Tests

- **TicketData**: Serialization round-trip, copyWith, equality, displayId formatting
- **TicketBoardState**: CRUD operations, filter/search/group-by, DAG cycle detection, auto-increment, status transitions, bulk operations
- **Persistence**: Save/load round-trip, missing file handling, corrupt file handling

### Widget Tests

- **TicketListPanel**: Renders tickets, search filters, group-by works, selection, empty state
- **TicketDetailPanel**: Renders all sections, metadata pills, dependency chips, action buttons
- **TicketCreateForm**: Validation, submission, cancel
- **TicketBulkReviewPanel**: Checkbox state, inline editing, approve/reject
- **TicketGraphView**: Renders nodes and edges, selection sync, zoom controls

### Integration Tests

- **Full flow**: Create ticket → begin work → agent runs → ticket completes
- **Bulk flow**: Agent proposes → user reviews → approves → tickets created
- **Persistence**: Create tickets → restart app → tickets still there

### Test Patterns

Follow existing patterns from `test/test_helpers.dart`:
- Use `safePumpAndSettle()` (never bare `pumpAndSettle()`)
- Use `TestResources` for cleanup
- Use `pumpUntilFound` / `pumpUntilGone` for async UI
- Use `setupTestConfig()` for temp directory isolation

---

## Edge Cases & Security

- **Cycle detection**: Must be bulletproof — a cycle in the DAG would cause infinite loops in topological sort and auto-readiness detection
- **Concurrent saves**: Use the existing write-queue pattern to prevent interleaved writes
- **Large ticket counts**: List uses `ListView.builder` (lazy rendering), graph may need viewport culling for 100+ nodes
- **Ticket ID overflow**: Auto-increment is per-project. If a project somehow hits 999 tickets, IDs still work (TKT-1000) — just wider
- **Orphaned links**: If a worktree or chat is deleted, the ticket's linked reference becomes stale. Handle gracefully (show "deleted" badge, don't crash)
- **Agent tool abuse**: Validate tool input — reject proposals with missing required fields, absurd dependency indices, or too many tickets in one call (cap at 50)

---

## Mockups

Interactive HTML mockups are available in `docs/mocks/`:

| Mockup | File |
|--------|------|
| Ticket list sidebar | `ticket-list-panel-mock.html` |
| Ticket detail view | `ticket-detail-panel-mock.html` |
| Ticket creation form | `ticket-create-form-mock.html` |
| Dependency graph | `ticket-graph-view-mock.html` |
| Bulk review panel | `ticket-bulk-review-mock.html` |
| Full screen layout | `ticket-screen-layout-mock.html` |

Open any file directly in a browser — they are fully self-contained with inline CSS.
