# Worktrees UI Refactor - Implementation Tasks

## Overview

This task list implements the UI refactor described in `refactor-plan.md`. Each task is designed to be completable in one session with clear acceptance criteria.

**Workflow for each task:**
1. Implement the feature
2. Write/update tests as specified
3. Run full test suite via `mcp__dart__run_tests`
4. Have reviewer verify task completion
5. Mark as done

---

## Phase 1: Config Schema Update

### Task 1: Create SessionInfo Class
**File:** `lib/services/project_config_service.dart`

Create the `SessionInfo` class for tracking session metadata in config.

```dart
class SessionInfo {
  final String? sessionId;  // null = no Claude session yet
  final String name;
  final DateTime createdAt;
}
```

**Acceptance Criteria:**
- [x] `SessionInfo` class with `sessionId`, `name`, `createdAt` fields
- [x] `sessionId` is nullable (null means UI-only session, no Claude session)
- [x] `fromJson()` and `toJson()` methods
- [x] `copyWith()` method for immutable updates

**Tests to Write:**
- [x] `test/services/project_config_models_test.dart`: Add `SessionInfo` serialization tests
  - Round-trip JSON serialization with all fields
  - Serialization with `sessionId: null`
  - `copyWith()` creates correct copy

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 2: Update WorktreeInfo to Use Sessions Array
**File:** `lib/services/project_config_service.dart`

Replace single `sessionId` with `List<SessionInfo> sessions`.

**Changes:**
- Remove `sessionId` field
- Add `List<SessionInfo> sessions` field
- Add `deleted` field (bool, default false)
- Update `fromJson()` / `toJson()`
- Update `copyWith()`

**Acceptance Criteria:**
- [x] `WorktreeInfo` has `sessions` array instead of `sessionId`
- [x] `WorktreeInfo` has `deleted` field
- [x] JSON serialization handles empty sessions array

**Tests to Write:**
- [x] `test/services/project_config_models_test.dart`: Update `WorktreeInfo` tests
  - Serialization with multiple sessions
  - Serialization with empty sessions array
  - Serialization with `deleted: true`
  - `copyWith()` with new fields

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 3: Add Sessions Array to ProjectWorktreeConfig
**File:** `lib/services/project_config_service.dart`

Add root-level sessions array for main branch sessions.

**Changes:**
- Add `List<SessionInfo> sessions` field
- Update `fromJson()` / `toJson()`
- Update `copyWith()`

**Acceptance Criteria:**
- [x] `ProjectWorktreeConfig` has `sessions` field
- [x] JSON serialization includes sessions array
- [x] Empty sessions array serialized as `[]`

**Tests to Write:**
- [x] `test/services/project_config_models_test.dart`: Update `ProjectWorktreeConfig` tests
  - Full config serialization with main sessions
  - Config with empty sessions array
  - Config with sessions in both main and worktrees

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 4: Add Session Management Helper Methods
**File:** `lib/services/project_config_service.dart`

Add methods to `ProjectConfigService` for managing sessions in config.

**New Methods:**
```dart
// Add session to main branch
Future<void> addMainSession(String projectPath, SessionInfo session)

// Add session to worktree
Future<void> addWorktreeSession(String projectPath, String branchName, SessionInfo session)

// Update session (e.g., set sessionId, rename)
Future<void> updateSession(String projectPath, String? branchName, String oldSessionId, SessionInfo updated)

// Remove session
Future<void> removeSession(String projectPath, String? branchName, String sessionId)

// Get all sessions for a project (main + all worktrees)
List<(String? branch, SessionInfo session)> getAllSessions(String projectPath)
```

**Acceptance Criteria:**
- [x] All helper methods implemented
- [x] Methods call `notifyListeners()` and `_saveToFile()`
- [x] `branchName: null` means main branch session

**Tests to Write:**
- [x] `test/services/project_config_service_test.dart`: Add session management tests
  - `addMainSession()` adds to main sessions list
  - `addWorktreeSession()` adds to correct worktree
  - `updateSession()` updates correct session (main and worktree)
  - `removeSession()` removes from correct location
  - `getAllSessions()` returns all sessions with branch info
  - Methods call `notifyListeners()` (use mock listener)

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 5: Update Existing Code for New Schema
**Files:** Multiple

Find and update all code that uses `WorktreeInfo.sessionId`.

**Likely locations:**
- `lib/providers/session_provider.dart` - worktree command handlers
- `lib/widgets/session_list.dart` - session display
- Tests in `test/services/` and `test/providers/`

**Acceptance Criteria:**
- [x] No compilation errors
- [x] All references to `WorktreeInfo.sessionId` updated
- [x] Existing tests pass (update as needed)

**Tests to Update:**
- [x] `test/services/project_config_service_test.dart`: Update any tests using old schema
- [x] `test/providers/session_provider_worktree_test.dart`: Update for new schema
- [x] `test/integration/workstart_command_test.dart`: Update for new schema
- [x] `test/integration/workdone_command_test.dart`: Update for new schema

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 2: Welcome Screen

### Task 6: Create WelcomeScreen Widget
**File:** `lib/widgets/welcome_screen.dart` (new)

Create the welcome screen shown when project is not in config.

**UI Elements:**
- App logo/title
- Current directory path display
- "Begin work in this folder" button
- "Open a different folder..." button

**Acceptance Criteria:**
- [x] Widget displays current working directory
- [x] "Begin work" button calls `onBeginWork` callback
- [x] "Open different folder" button calls `onOpenFolder` callback
- [x] Clean, centered layout matching app style

**Tests to Write:**
- [x] `test/widget/welcome_screen_test.dart` (new)
  - Renders current directory path
  - "Begin work" button triggers callback
  - "Open different folder" button triggers callback
  - Layout renders without overflow

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 7: Add Project Management Methods
**File:** `lib/services/project_config_service.dart`

Add methods for checking and adding projects.

**New Methods:**
```dart
// Check if a project path is in config
bool hasProject(String projectPath)

// Add a new project with minimal config
Future<void> addProject(String projectPath, {String? mainBranch})
```

**Acceptance Criteria:**
- [x] `hasProject()` returns true if path exists in config
- [x] `addProject()` creates minimal entry (path, empty sessions, worktrees disabled)
- [x] `addProject()` auto-detects main branch if not provided (via GitWorktreeService)
- [x] Calls `notifyListeners()` and saves to file

**Tests to Write:**
- [x] `test/services/project_config_service_test.dart`: Add project management tests
  - `hasProject()` returns false for unknown path
  - `hasProject()` returns true after `addProject()`
  - `addProject()` creates config with empty sessions
  - `addProject()` with explicit mainBranch uses it
  - `addProject()` without mainBranch auto-detects (mock GitWorktreeService)
  - `addProject()` calls `notifyListeners()`

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 8: Integrate Welcome Screen into HomeScreen
**File:** `lib/screens/home_screen.dart`

Show welcome screen when project not in config.

**Changes:**
- Check `ProjectConfigService.hasProject(cwd)` on build
- If false, show `WelcomeScreen` instead of normal UI
- Handle "Begin work" → call `addProject()`, rebuild
- Handle "Open folder" → show folder picker, then `addProject()`

**Acceptance Criteria:**
- [x] Welcome screen shown when project not in config
- [x] After adding project, main UI shown
- [x] Folder picker works (macOS file dialog)
- [x] State updates correctly via `ListenableBuilder`

**Tests to Write:**
- [x] `test/integration/welcome_flow_test.dart` (new)
  - Shows welcome screen when project not in config
  - "Begin work" adds project and shows main UI
  - Main UI shown when project already in config

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 3: Sessions Panel Redesign

### Task 9: Create SessionGroup Widget
**File:** `lib/widgets/session_group.dart` (new)

Create collapsible group widget for sessions panel.

**Props:**
- `title` - group header text (e.g., "main", "cci/add-feature")
- `sessions` - list of sessions to display
- `isExpanded` - whether group is expanded
- `onToggle` - callback when header tapped
- `isMerged` - show [done] badge if true
- `onSessionTap` - callback when session tapped
- `selectedSessionId` - currently selected session
- `onContextMenu` - callback for right-click on header

**Acceptance Criteria:**
- [x] Collapsible header with ▼/▸ indicator
- [x] Shows [done] badge when `isMerged` is true
- [x] Sessions list hidden when collapsed
- [x] Each session row shows name, status indicator
- [x] Sessions with `sessionId: null` show "Start chatting"
- [x] Right-click on header triggers context menu callback

**Tests to Write:**
- [x] `test/widget/session_group_test.dart` (new)
  - Renders expanded with sessions visible
  - Renders collapsed with sessions hidden
  - Toggle callback fires on header tap
  - Shows [done] badge when `isMerged: true`
  - Session tap callback fires with correct session
  - Shows "Start chatting" for null sessionId
  - Context menu callback fires on right-click

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 10: Rewrite SessionList for Grouped View
**File:** `lib/widgets/session_list.dart`

Complete rewrite to show sessions grouped by worktree.

**Structure:**
```
Sessions [+]
─────────────
▼ main
  • Session 1
  • Session 2
▼ cci/add-dark-mode
  • Add Dark Mode
▸ cci/old-feature [done]
```

**Logic:**
1. Get project config for current cwd
2. Build list of groups: main first, then worktrees by date
3. Filter out deleted worktrees (or show them differently?)
4. Track expanded/collapsed state per group (local state for now)
5. Merged worktrees collapsed by default

**Acceptance Criteria:**
- [x] Main branch group always first
- [x] Worktrees sorted by creation date (newest first)
- [x] Merged worktrees show [done] badge, collapsed by default
- [x] Clicking session selects it
- [x] Clicking group header toggles collapse
- [x] [+] button in header (functionality TBD - maybe creates session in selected group)
- [x] Handles empty state (no sessions yet)

**Tests to Write:**
- [x] `test/widget/session_list_test.dart` (update or new)
  - Main group appears first
  - Worktrees sorted by creation date
  - Merged worktrees start collapsed
  - Session selection works
  - Group collapse/expand works
  - Empty state renders correctly

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 11: Add Context Menu to Worktree Groups
**File:** `lib/widgets/session_list.dart`

Add right-click context menu on worktree group headers.

**Menu Items:**
- "New session" - creates new session in this worktree
- "Mark as done" - triggers `/worktree done` flow for this worktree
- (Separator)
- "Delete worktree" - with confirmation

**Acceptance Criteria:**
- [x] Context menu appears on right-click
- [x] "New session" creates session entry with `sessionId: null`
- [x] "Mark as done" calls appropriate handler (reuse existing flow)
- [x] No context menu on main branch group (or different options)

**Tests to Write:**
- [x] `test/widget/session_list_test.dart`: Add context menu tests
  - Context menu appears on worktree group right-click
  - No context menu (or different) on main group
  - "New session" creates null-session entry
  - "Mark as done" triggers correct callback

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 12: Connect SessionList to Config and Provider
**File:** `lib/widgets/session_list.dart`

Wire up the new session list to data sources.

**Data Flow:**
- Listen to `ProjectConfigService` for session/worktree config
- Listen to `SessionProvider` for active sessions and selection
- Map config sessions to runtime sessions where they exist
- Handle sessions that exist in config but not in provider (show as inactive)

**Acceptance Criteria:**
- [x] UI updates when config changes
- [x] UI updates when provider changes
- [x] Sessions from config displayed even if no active Claude session
- [x] Active sessions show running indicator
- [x] Selection state synced with provider

**Tests to Write:**
- [x] `test/widget/session_list_test.dart`: Add data binding tests
  - Rebuilds when config changes
  - Rebuilds when provider changes
  - Shows inactive sessions from config
  - Shows running indicator for active sessions
  - Selection highlights correct session

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 4: Project Opened Panel

### Task 13: Create ProjectOpenedPanel Widget
**File:** `lib/widgets/project_opened_panel.dart` (new)

Panel shown when project loaded but no session active.

**UI Elements:**
- "Begin chatting below" header
- Model selector dropdown
- Tip box about `/worktree new`
- Message input at bottom

**Acceptance Criteria:**
- [x] Displays model selector (Opus/Sonnet/Haiku)
- [x] Shows tip about worktrees
- [x] Message input functional
- [x] On submit, calls callback with message and selected model

**Tests to Write:**
- [x] `test/widget/project_opened_panel_test.dart` (new)
  - Renders model selector with options
  - Renders tip text about worktrees
  - Message input accepts text
  - Submit callback receives message and selected model
  - Model selection changes work

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 14: Create NewWorktreePanel Variant
**File:** `lib/widgets/project_opened_panel.dart`

Variant of ProjectOpenedPanel shown for new worktree sessions.

**Differences from base panel:**
- Header shows "Working on: cci/branch-name"
- Tip box explains `/worktree done` instead of `/worktree new`

**Implementation Options:**
1. Separate widget `NewWorktreePanel`
2. Parameter on `ProjectOpenedPanel`: `worktreeBranch: String?`

**Acceptance Criteria:**
- [x] Shows worktree branch name in header
- [x] Tip explains how to finish worktree
- [x] Same message input functionality as base panel

**Tests to Write:**
- [x] `test/widget/project_opened_panel_test.dart`: Add worktree variant tests
  - Shows branch name in header when `worktreeBranch` provided
  - Shows `/worktree done` tip for worktree variant
  - Submit works same as base panel

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 15: Integrate Panels into HomeScreen
**File:** `lib/screens/home_screen.dart`

Show appropriate panel in conversation area.

**Logic:**
```
if (no session selected):
  show ProjectOpenedPanel
else if (selected session has sessionId == null):
  if (session is worktree):
    show NewWorktreePanel
  else:
    show ProjectOpenedPanel
else:
  show ConversationPanel (existing)
```

**Acceptance Criteria:**
- [x] Correct panel shown based on selection state
- [x] Smooth transition when state changes
- [x] Message submission creates/activates session

**Tests to Write:**
- [x] `test/integration/panel_switching_test.dart` (new)
  - Shows ProjectOpenedPanel when no session selected
  - Shows ProjectOpenedPanel for null-session on main (skipped - needs Task 16)
  - Shows NewWorktreePanel for null-session on worktree (skipped - needs Task 16)
  - Shows ConversationPanel for active session
  - Transitions correctly when state changes

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 5: Session Lifecycle

### Task 16: Support Sessions with Null SessionId
**File:** `lib/providers/session_provider.dart`

Allow creating and managing sessions without Claude backend session.

**Changes:**
- `createSessionEntry()` - creates UI session without Claude session
- Track sessions with `sessionId: null` separately
- On first message to null-session, create Claude session

**Acceptance Criteria:**
- [x] Can create session entry without starting Claude session
- [x] Null-session appears in session list as "Start chatting"
- [x] Selecting null-session shows appropriate panel
- [x] Sending message to null-session creates Claude session

**Tests to Write:**
- [x] `test/providers/session_provider_test.dart`: Add null-session tests
  - `createSessionEntry()` creates entry without Claude session
  - Null-session appears in session list
  - Null-session can be selected
  - Null-session has correct initial state

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 17: Implement First Message Handling
**File:** `lib/providers/session_provider.dart`

Handle first message to a null-session.

**Flow:**
1. User sends message to session with `sessionId: null`
2. Create Claude session via backend
3. Update session in config: set `sessionId`, generate name
4. Continue as normal session

**Acceptance Criteria:**
- [x] Claude session created on first message
- [x] Config updated with new sessionId
- [x] Session name generated from first message
- [x] Conversation continues normally after

**Tests to Write:**
- [x] `test/providers/session_provider_test.dart`: Add first message tests
  - Sending to null-session creates Claude session
  - Config updated with sessionId after creation
  - Session name updated from message
- [x] `test/integration/first_message_test.dart` (new)
  - Full flow: null-session → message → active session

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 18: Implement Session Name Generation
**File:** `lib/providers/session_provider.dart` (or new utility)

Generate session name from first message.

```dart
String generateSessionName(String firstMessage) {
  // Take first ~40 chars or 5-6 words
  // Clean up, add ellipsis if truncated
}
```

**Acceptance Criteria:**
- [x] Returns first ~40 chars of message
- [x] Truncates at word boundary if possible
- [x] Adds "..." if truncated
- [x] Handles edge cases (empty, very short, very long)

**Tests to Write:**
- [x] Tests in `test/provider/session_provider_test.dart` (implemented in Task 17)
  - Short message returned as-is
  - Long message truncated at word boundary
  - Adds "..." when truncated
  - Empty message returns default name
  - Very long single word truncated with "..."
  - Whitespace-only message returns default name

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done (implemented as part of Task 17)

---

### Task 19: Persist Sessions to Config
**File:** `lib/providers/session_provider.dart`

Save session info to config when sessions are created/updated.

**When to persist:**
- Session created → add to config
- Session renamed → update in config
- Session gets Claude sessionId → update in config

**Acceptance Criteria:**
- [x] New sessions added to config immediately
- [x] SessionId updates persisted
- [x] Name changes persisted
- [x] Correct worktree/main association

**Tests to Write:**
- [x] `test/providers/session_provider_test.dart`: Add persistence tests
  - Session creation persists to config
  - SessionId update persists to config
  - Name change persists to config
  - Worktree session persists to correct worktree
  - Main session persists to main sessions

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 6: Command Rename

### Task 20: Rename /workstart to /worktree new
**File:** `lib/providers/session_provider.dart`

Replace `/workstart` command with `/worktree new`.

**Changes:**
- Detect `/worktree new`, `/worktree create`, `/worktree add`
- Parse task description from remainder of command
- Reuse existing worktree creation logic
- Remove `/workstart` detection

**Acceptance Criteria:**
- [x] `/worktree new <task>` works
- [x] `/worktree create <task>` works (alias)
- [x] `/worktree add <task>` works (alias)
- [x] `/workstart` no longer recognized (or shows deprecation message)
- [x] Existing creation logic preserved

**Tests to Write:**
- [x] `test/providers/session_provider_worktree_test.dart`: Update command tests
  - `/worktree new` creates worktree
  - `/worktree create` creates worktree (alias)
  - `/worktree add` creates worktree (alias)
  - `/workstart` shows error or deprecation message
  - Task description parsed correctly from all variants

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 21: Rename /workdone to /worktree done
**File:** `lib/providers/session_provider.dart`

Replace `/workdone` command with `/worktree done`.

**Changes:**
- Detect `/worktree done`, `/worktree finished`, `/worktree close`
- Reuse existing workdone logic
- Remove `/workdone` detection

**Acceptance Criteria:**
- [x] `/worktree done` works
- [x] `/worktree finished` works (alias)
- [x] `/worktree close` works (alias)
- [x] `/workdone` no longer recognized (or shows deprecation message)
- [x] Existing completion logic preserved

**Tests to Write:**
- [x] `test/providers/session_provider_worktree_test.dart`: Update command tests
  - `/worktree done` triggers completion flow
  - `/worktree finished` triggers completion flow (alias)
  - `/worktree close` triggers completion flow (alias)
  - `/workdone` shows error or deprecation message

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 22: Add /worktree list Command
**File:** `lib/providers/session_provider.dart`

Add `/worktree list` as alias for `/worktrees`.

**Acceptance Criteria:**
- [x] `/worktree list` shows worktree list
- [x] `/worktrees` still works
- [x] Same output for both

**Tests to Write:**
- [x] `test/providers/worktrees_command_test.dart`: Add list command tests
  - `/worktree list` produces output
  - `/worktrees` produces same output
  - Output format is correct

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 23: Add Non-Main-Branch Warning
**File:** `lib/providers/session_provider.dart`

Warn when creating worktree from non-main branch.

**Flow:**
1. User runs `/worktree new` while on `feature-x` branch
2. Show warning dialog: "You're creating from `feature-x`, not `main`. Continue?"
3. [Abort] → cancel, [Continue] → proceed

**Acceptance Criteria:**
- [x] Warning shown when current branch != mainBranch
- [x] User can abort or continue
- [x] No warning when on main/master
- [x] Dialog matches app style

**Tests to Write:**
- [x] `test/providers/non_main_branch_warning_test.dart`: Add warning tests
  - Warning dialog triggered on non-main branch
  - No warning on main branch
  - Abort cancels worktree creation
  - Continue proceeds with worktree creation

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 24: Remove Onboarding Dialog Trigger
**File:** `lib/providers/session_provider.dart`

Worktrees are now enabled implicitly on first use.

**Changes:**
- Remove check for `worktreeEnabled` before creating worktree
- On first worktree creation, auto-populate config:
  - `worktreeEnabled: true`
  - `worktreePath: <project>-wt`
  - `mainBranch: <detected>`
- Remove or simplify `WorktreeOnboardingDialog`

**Acceptance Criteria:**
- [x] First `/worktree new` works without onboarding
- [x] Config auto-populated with defaults
- [x] No onboarding dialog shown
- [x] Existing config values preserved if already set

**Tests to Write:**
- [x] `test/providers/session_provider_worktree_test.dart`: Update onboarding tests
  - First `/worktree new` auto-enables worktrees
  - Config populated with correct defaults
  - Existing config values not overwritten
  - No pending onboarding state set
- [x] `test/integration/worktree_full_flow_test.dart`: Step 6 updated
  - Tests auto-enable flow without onboarding dialog

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 25: Update Help Text and Messages
**Files:** Multiple

Update all user-facing text for new commands.

**Locations:**
- Error messages in command handlers
- Success messages
- Tip text in panels
- Any help/usage text

**Acceptance Criteria:**
- [x] All references to `/workstart` → `/worktree new`
- [x] All references to `/workdone` → `/worktree done`
- [x] Consistent command format in all messages

**Tests to Write:**
- [x] Existing tests verify correct command usage in messages
- [x] `test/widget/project_opened_panel_test.dart`: Tip text already uses new commands

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Phase 7: Final Integration Testing

### Task 26: Integration Test for Welcome Flow
**File:** `test/integration/welcome_flow_test.dart` (already exists)

End-to-end test for welcome screen flow.

**Test Scenarios:**
1. App startup with unknown project → welcome screen
2. "Begin work" → project added → main UI shown
3. App startup with known project → main UI directly

**Acceptance Criteria:**
- [x] All scenarios pass with mock backend
- [x] Config persisted correctly

**Tests Already Exist:**
- [x] `test/integration/welcome_flow_test.dart`
  - "displays WelcomeScreen for unregistered project"
  - "clicking 'Begin work' registers project and shows main UI"
  - "displays main UI directly when project exists in config"
  - Additional tests for state updates and folder picker

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 27: Integration Test for Session Lifecycle
**File:** `test/integration/first_message_test.dart` (already exists)

End-to-end test for session creation and first message.

**Test Scenarios:**
1. Create null-session → shows in list as "Start chatting"
2. Send first message → Claude session created → name updated
3. Session persisted to config correctly

**Acceptance Criteria:**
- [x] All scenarios pass with mock backend
- [x] Config updated at each step

**Tests Already Exist:**
- [x] `test/integration/first_message_test.dart`
  - "null-session becomes active after first message"
  - "session name is generated from first message"
  - "worktree session updates config on first message"

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 28: Integration Test for Worktree Commands
**Files:** Multiple existing test files

End-to-end test for new command syntax.

**Test Scenarios:**
1. `/worktree new <task>` → worktree created → session created
2. `/worktree done` → confirmation → worktree marked done
3. `/worktree list` → shows all worktrees

**Acceptance Criteria:**
- [x] All scenarios pass with mock backend and mock git
- [x] Config updated correctly

**Tests Already Exist:**
- [x] `test/integration/workstart_command_test.dart` - Tests `/worktree new` command
- [x] `test/integration/workdone_command_test.dart` - Tests `/worktree done` command
- [x] `test/integration/worktrees_command_test.dart` - Tests `/worktree list` command
- [x] `test/providers/session_provider_worktree_test.dart` - Tests all aliases

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

### Task 29: Full UI Flow Integration Test
**File:** `test/integration/worktree_full_flow_test.dart` (already exists)

Complete end-to-end test covering entire new UI flow.

**Test Scenarios:**
1. Fresh start → welcome → add project → create session → chat
2. Create worktree → new session → chat → mark done
3. Multiple worktrees with multiple sessions

**Acceptance Criteria:**
- [x] Full happy path works
- [x] Config state correct throughout
- [x] UI state correct throughout

**Tests Already Exist:**
- [x] `test/integration/worktree_full_flow_test.dart`
  - "Widget tests with mocked git" group tests complete flow
  - Step 6: `/worktree new` auto-enables and creates session
  - Step 7: Auto-enabled worktrees creates session directly
  - Step 8: `/worktree done` marks worktree complete
  - Step 9: Completion flow with session cleanup
- [x] `test/integration/welcome_flow_test.dart` - Welcome screen flow
- [x] `test/integration/workdone_flow_test.dart` - Full done flow

**Completion:**
- [x] Full test suite passes (`mcp__dart__run_tests`)
- [x] Verified by reviewer
- [x] Done

---

## Task Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-5 | Config schema update |
| 2 | 6-8 | Welcome screen |
| 3 | 9-12 | Sessions panel redesign |
| 4 | 13-15 | Project opened panel |
| 5 | 16-19 | Session lifecycle |
| 6 | 20-25 | Command rename |
| 7 | 26-29 | Final integration testing |

**Total: 29 tasks**

---

## Dependencies

```
Phase 1 (Config) ──┬── Phase 2 (Welcome)
                   ├── Phase 3 (Sessions Panel)
                   ├── Phase 5 (Session Lifecycle)
                   └── Phase 6 (Commands)

Phase 2 + 3 + 5 ───── Phase 4 depends on these

Phase 1-6 ─────────── Phase 7 (Final Integration)
```

**Recommended order:** 1 → 2 → 3 → 5 → 4 → 6 → 7

---

## Test File Summary

**New test files to create:**
- `test/widget/welcome_screen_test.dart`
- `test/widget/session_group_test.dart`
- `test/widget/project_opened_panel_test.dart`
- `test/utils/session_name_test.dart`
- `test/integration/welcome_flow_test.dart`
- `test/integration/panel_switching_test.dart`
- `test/integration/first_message_test.dart`
- `test/integration/worktree_welcome_flow_test.dart`
- `test/integration/worktree_session_lifecycle_test.dart`
- `test/integration/worktree_commands_test.dart`
- `test/integration/worktree_full_ui_flow_test.dart`

**Existing test files to update:**
- `test/services/project_config_models_test.dart`
- `test/services/project_config_service_test.dart`
- `test/providers/session_provider_test.dart`
- `test/providers/session_provider_worktree_test.dart`
- `test/widget/session_list_test.dart`
- `test/integration/workstart_command_test.dart`
- `test/integration/workdone_command_test.dart`

---

## Testing Guidelines

**All tests MUST use mock git services only.** Do not use real git operations in tests.

- Use `MockGitWorktreeService` for all git-related functionality
- Tests that require real git operations should be disabled or moved to the "Deferred Tests" section below

---

## Discoveries & Issues

*(Add any issues or discoveries encountered during implementation here)*

---

## Deferred Tests (Require Real Git)

The following tests depend on real git operations and are deferred until a proper test git repository infrastructure is set up:

### Test Files Disabled:

1. **`test/services/git_worktree_service_test.dart`** - All tests
   - Tests GitWorktreeService methods against real git repositories
   - Requires TestGitRepo.create() which makes real git calls
   - Status: Entire group skipped with skip annotation

2. **`test/integration/worktree_full_flow_test.dart`** - Groups using real git
   - "Git operations (non-widget)" group - skipped
   - "Widget tests with real git" group - skipped
   - "Widget tests with mocked git" group - should still run (uses MockGitWorktreeService)
   - Status: Groups requiring real git skipped with skip annotations

### Helper Functions Disabled:

- **`test/helpers/test_git_repo.dart`** - All methods throw UnsupportedError
  - `TestGitRepo.create()` - throws with message directing to use MockGitWorktreeService
  - All instance methods (`git()`, `createFile()`, `commit()`, etc.) - throw UnsupportedError
  - Purpose: Ensures any test attempting real git operations fails fast with clear error message
