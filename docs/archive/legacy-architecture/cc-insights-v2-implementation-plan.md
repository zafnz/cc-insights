# CC-Insights V2 Implementation Plan

## Overview

This document outlines the phased implementation of CC-Insights V2, based on the architecture defined in `cc-insights-v2-architecture.md`.

---

## ⚠️ CRITICAL: Dart MCP Tools Requirement (For Claude)

**These instructions are for CLAUDE (the AI assistant), not for human developers.**

Claude must ALWAYS use Dart MCP tools for Flutter/Dart development. Claude must NEVER use Bash commands like `flutter test`, `dart test`, `flutter pub`, etc.

### MCP Tools Claude Must Use

- **`mcp__dart__run_tests`** - Run tests (Claude: NEVER use Bash `flutter test`)
- **`mcp__dart__pub`** - Manage packages (Claude: NEVER use Bash `flutter pub`)
- **`mcp__dart__dart_format`** - Format code (Claude: NEVER use Bash `dart format`)
- **`mcp__dart__dart_fix`** - Apply fixes (Claude: NEVER use Bash `dart fix`)
- **`mcp__dart__analyze_files`** - Analyze code (Claude: NEVER use Bash `flutter analyze`)

### Why This Matters for Claude

The Dart MCP server provides:
- Clean, parseable output optimized for AI agents
- Proper error handling and structured responses
- Workspace-aware operations with root management
- Consistent behavior across all development operations

### Before Claude Starts Any Phase

1. Ensure Dart MCP server is connected
2. Register project roots with `mcp__dart__add_roots` if needed
3. Use MCP tools exclusively for all Dart/Flutter operations

**Claude: Violating this requirement will result in messy output, parsing failures, and wasted effort.**

**Human developers**: You can use regular `flutter test`, `flutter pub`, etc. commands normally.

---

### Guiding Principles

1. **Each phase produces a runnable app** - At the end of each phase, the app can be launched and demonstrates new functionality
2. **Mockups before implementation** - Each phase begins with UI mockups that define the visual target
3. **Integration tests with screenshots** - Every phase includes integration tests that capture screenshots for visual verification
4. **Claude reviews screenshots** - Before phase completion, Claude analyzes screenshots to verify correctness against mockups
5. **Human verification gate** - Each phase ends with a checklist for human operator testing
6. **No phase begins until previous passes** - Strict sequential progression

### Phase Structure

Each phase follows this template:
- **Goal**: What this phase achieves
- **Design Decisions**: Questions to resolve before implementation begins (where applicable)
- **Mockups**: Visual designs created before implementation begins
- **Deliverables**: Concrete outputs (files, features)
- **Integration Tests**: Tests that run the app and capture screenshots
- **Screenshot Verification**: What Claude should check in screenshots (compared to mockups)
- **Human Verification Checklist**: Manual tests for the operator

Design decisions are resolved at the start of each phase, not upfront. This allows decisions to be informed by learnings from previous phases.

### Testing Protocol (For Claude)

**Claude must use Dart MCP tools for ALL test execution:**

```
❌ NEVER DO THIS (Claude):
Bash("flutter test test/models/")
Bash("dart test test/integration/")

✅ ALWAYS DO THIS (Claude):
mcp__dart__run_tests with:
{
  "roots": [{
    "root": "file:///absolute/path/to/flutter_app_v2"
  }],
  "testRunnerArgs": {
    // Optional: filter by path, tags, etc.
  }
}
```

**Why this matters for Claude in each phase:**
- Clean test output that's easy to parse
- Proper error reporting for debugging
- Consistent behavior across test runs
- Integration with workspace management
- Better performance and reliability

**Human developers** can use `flutter test` normally from the command line.

---

## Theme Specification

All mockups must follow the existing CC-Insights theme:

### Colors (Material 3 with Deep Purple seed)
- **Seed Color**: `Colors.deepPurple`
- **Surface containers**: Use `surfaceContainerHigh` for nav bars, `surfaceContainerHighest` for cards
- **Primary container**: For user messages (light purple/blue tint)
- **Outline variant**: For subtle borders (30% opacity)

### Typography
- **Monospace font**: JetBrains Mono at 12px for code, file paths, commands
- **Material 3 text styles**: Use standard `textTheme` for UI text

### Component Styling
| Element | Background | Border Radius |
|---------|-----------|---------------|
| Cards | surfaceContainerHighest | 8px |
| User messages | primaryContainer | 8px |
| Code blocks | black87 with greenAccent text | 4px |
| Nav bars | surfaceContainerHigh | 0 |
| Containers | surfaceContainerHighest | 4-8px |

### Tool Card Colors
- **Blue**: Read, Write, Edit (file operations)
- **Purple**: Glob, Grep (search)
- **Orange**: Bash (commands)
- **Orange/Red**: Task (subagents)
- **Green**: AskUserQuestion
- **Cyan**: WebSearch, WebFetch
- **Teal**: TodoWrite

### Status Colors
- **Success**: Green
- **Error**: Red
- **Warning**: Orange
- **Pending**: Blue

### Dark Mode
- App supports both light and dark mode (system preference)
- All mockups should be provided in both light and dark variants

---

## Phase 0: Project Scaffold

**Goal**: Create `flutter_app_v2/` with proper structure, dependencies, and a minimal running app.

### Mockups

Create mockups showing the minimal app shell:

1. **`mockups/phase0_app_shell_light.png`** - Light mode
   - Window with title bar showing "CC-Insights V2"
   - Empty content area with centered placeholder text: "Welcome to CC-Insights V2"
   - Proper Material 3 theming with deep purple accents
   - Window size: approximately 1200x800

2. **`mockups/phase0_app_shell_dark.png`** - Dark mode
   - Same layout as light mode
   - Dark surface colors per Material 3 dark theme

### Deliverables

1. **New Flutter project** at `flutter_app_v2/`
2. **Directory structure** per architecture doc:
   ```
   lib/
   ├── main.dart
   ├── models/
   ├── state/
   ├── services/
   ├── panels/
   ├── widgets/
   │   ├── display/
   │   └── input/
   └── screens/
   ```
3. **pubspec.yaml** with required dependencies:
   - `provider` (state management)
   - `flutter_test`, `integration_test` (testing)
   - Dependencies from existing app that will be needed (copy from `flutter_app/pubspec.yaml`)
4. **Minimal main.dart** that shows a placeholder screen with app title
5. **Integration test infrastructure** set up

### Integration Tests

- `test/integration/app_launch_test.dart`
  - Launches the app
  - Verifies app title is visible
  - Captures screenshot: `screenshots/phase0_app_launch.png`

### Screenshot Verification (Claude)

- App window is visible
- Title "CC-Insights" (or placeholder) is displayed
- No error screens or red error boxes
- App renders without visual glitches

### Human Verification Checklist

- [ ] Run `flutter test` to verify tests pass
- [ ] Run `flutter run` in `flutter_app_v2/` - app launches
- [ ] App window appears with title
- [ ] No console errors on startup
- [ ] App can be closed cleanly

---

## Phase 1: Core Models

**Goal**: Implement the data models (Project, Worktree, Chat, Conversation, Agent, OutputEntry) with unit tests, and display mock data in the UI.

### Mockups

Create mockups showing worktree list with mock data:

1. **`mockups/phase1_worktree_list_light.png`** - Light mode
   - Left sidebar (width ~250px) with worktree list
   - Header: "Worktrees" with subtle background
   - 3 worktree entries showing:
     - Branch name (bold): "main", "feat-dark-mode", "fix-auth-bug"
     - Path (muted): "~/projects/cc-insights", "../cc-insights-wt/dark-mode", etc.
     - Status icons placeholder: "↑2 ↓0 ~3"
   - First worktree visually selected (highlighted background)
   - Right area: placeholder content showing selected worktree name

2. **`mockups/phase1_worktree_list_dark.png`** - Dark mode variant

3. **`mockups/phase1_worktree_selected_light.png`** - Different worktree selected
   - Second worktree highlighted instead of first
   - Right area updated to show new selection

### Deliverables

1. **Model files**:
   - `lib/models/project.dart`
   - `lib/models/worktree.dart`
   - `lib/models/chat.dart`
   - `lib/models/conversation.dart`
   - `lib/models/agent.dart`
   - `lib/models/output_entry.dart` (copy from existing, extract from session.dart)

2. **SelectionState**:
   - `lib/state/selection_state.dart`

3. **Mock data factory** for testing:
   - `lib/testing/mock_data.dart` - creates sample Project with Worktrees, Chats, Conversations

4. **Updated main.dart**:
   - Displays mock project name
   - Lists mock worktrees (simple ListView)
   - Shows selected worktree name when tapped

### Integration Tests

- `test/integration/models_display_test.dart`
  - Launches app with mock data
  - Verifies worktree list is visible
  - Taps a worktree, verifies selection updates
  - Captures screenshots:
    - `screenshots/phase1_worktree_list.png`
    - `screenshots/phase1_worktree_selected.png`

### Screenshot Verification (Claude)

- Worktree list shows multiple entries
- Each entry displays branch name and path
- Selected worktree is visually highlighted
- Layout is reasonable (no overflow, proper spacing)

### Human Verification Checklist

- [ ] Run `flutter test test/models/` to verify all model tests pass
- [ ] App launches and shows project name
- [ ] Worktree list displays at least 2 worktrees
- [ ] Tapping a worktree highlights it
- [ ] Worktree entries show branch and path

---

## Phase 2: Panel Infrastructure

**Goal**: Implement basic panel system with resizable splits. No drag-drop yet, just the foundation.

### Mockups

Create mockups showing resizable two-panel layout:

1. **`mockups/phase2_two_panel_layout_light.png`** - Light mode
   - Two-column layout with visible divider
   - Left panel (~30%): Worktree list from Phase 1
   - Divider: 4px wide, subtle color, cursor indicator for draggability
   - Right panel (~70%): Placeholder content "Select a worktree to begin"
   - Both panels have headers with panel name

2. **`mockups/phase2_two_panel_layout_dark.png`** - Dark mode variant

3. **`mockups/phase2_resized_layout_light.png`** - After resize
   - Left panel now ~50% width
   - Right panel ~50% width
   - Demonstrates resize capability

4. **`mockups/phase2_divider_hover_light.png`** - Divider hover state
   - Divider highlighted (slightly brighter)
   - Cursor shown as col-resize

### Deliverables

1. **Panel manager foundation**:
   - `lib/panels/panel_manager.dart` - manages panel layout
   - `lib/panels/panel_container.dart` - wrapper for individual panels
   - `lib/panels/resizable_divider.dart` - draggable divider between panels

2. **Basic layout**: Two-column split
   - Left: Worktree list panel
   - Right: Placeholder content panel

3. **Worktree panel**:
   - `lib/panels/worktree_panel.dart` - displays worktree list with proper styling

### Integration Tests

- `test/integration/panel_resize_test.dart`
  - Launches app
  - Captures initial layout screenshot
  - Drags divider to resize panels
  - Captures resized layout screenshot
  - Screenshots:
    - `screenshots/phase2_initial_layout.png`
    - `screenshots/phase2_resized_layout.png`

### Screenshot Verification (Claude)

- Two distinct panels visible
- Divider is visible between panels
- After resize, proportions have changed
- Both panels remain functional (content visible)
- No visual artifacts from resize

### Human Verification Checklist

- [ ] App shows two-panel layout
- [ ] Divider is visible and cursor changes on hover
- [ ] Dragging divider resizes panels smoothly
- [ ] Panels have minimum size (can't collapse to zero)
- [ ] Worktree list remains functional in left panel

---

## Phase 3: Chat Panel & Conversation Display

**Goal**: Add chat panel, conversation list, and basic conversation viewer with mock output entries.

### Mockups

Create mockups showing the three-panel chat interface:

1. **`mockups/phase3_three_panel_layout_light.png`** - Light mode, full layout
   - Left panel (~200px): Worktrees list
   - Middle panel (~200px): Chats list with conversation tree
     - Header: "Chats"
     - Chat entries: "Chat 1", "Chat 2" with unread indicators (○/-)
     - Expanded chat showing conversations:
       - "Primary"
       - "Subagent: Explore"
       - "Subagent: Plan"
   - Right panel (remaining): Conversation viewer
     - Header showing chat/conversation name
     - Output entries area (scrollable)

2. **`mockups/phase3_three_panel_layout_dark.png`** - Dark mode variant

3. **`mockups/phase3_conversation_with_entries_light.png`** - Conversation with mock output
   - Conversation viewer showing:
     - User message (primaryContainer background): "Help me add a dark mode toggle"
     - Text response block
     - Tool card (collapsed): "Read" with file path
     - Tool card (expanded): "Bash" showing command in black box with green text
     - Tool card (collapsed): "Edit" with file path and diff preview

4. **`mockups/phase3_tool_card_expanded_light.png`** - Close-up of expanded tool card
   - Tool name with icon (e.g., orange Bash icon)
   - Command display in black box
   - Result/output section
   - Collapse affordance

5. **`mockups/phase3_subagent_selected_light.png`** - Subagent conversation view
   - Subagent conversation selected in tree
   - Conversation viewer showing subagent output
   - NO input box visible (read-only)

### Deliverables

1. **Chat panel**:
   - `lib/panels/chat_panel.dart` - lists chats for selected worktree

2. **Conversation panel**:
   - `lib/panels/conversation_panel.dart` - lists conversations (primary + subagents) for selected chat

3. **Conversation viewer panel**:
   - `lib/panels/conversation_viewer_panel.dart` - displays OutputEntry list

4. **Copy display widgets from existing app**:
   - `lib/widgets/display/output_entries.dart`
   - `lib/widgets/display/output_panel.dart`
   - `lib/widgets/display/tool_card.dart`
   - `lib/widgets/display/diff_view.dart`
   - Adapt imports as needed

5. **Three-column layout**:
   - Left: Worktrees
   - Middle: Chats + Conversations (stacked or tabbed)
   - Right: Conversation viewer

6. **Mock output entries** in test data:
   - TextOutputEntry samples
   - ToolUseOutputEntry samples (Bash, Read, Edit)

### Integration Tests

- `test/integration/conversation_flow_test.dart`
  - Select worktree → shows chats
  - Select chat → shows conversations
  - Select conversation → shows output entries
  - Screenshots:
    - `screenshots/phase3_chat_list.png`
    - `screenshots/phase3_conversation_selected.png`
    - `screenshots/phase3_output_entries.png`

### Screenshot Verification (Claude)

- Chat list shows chat names
- Conversation list shows "Primary" and subagent labels
- Output entries render correctly (text blocks, tool cards)
- Tool cards show tool names and have expand/collapse affordance
- Three-panel layout is coherent

### Human Verification Checklist

- [ ] Selecting worktree shows its chats
- [ ] Selecting chat shows its conversations (Primary + any subagents)
- [ ] Selecting conversation shows output entries
- [ ] Tool cards render with proper icons
- [ ] Text entries display markdown correctly
- [ ] Scroll works in conversation viewer

---

## Phase 4: Backend Integration (No UI Input Yet)

**Goal**: Connect to the Node.js backend, create a real ClaudeSession, and display real SDK messages.

### Design Decisions

Before implementation, resolve:
- Error display strategy: inline in conversation vs banner vs toast?
- Loading indicator style: spinner, pulsing dots, skeleton?

### Mockups

Create mockups showing real API interaction states:

1. **`mockups/phase4_waiting_for_response_light.png`** - Light mode
   - Conversation viewer showing:
     - User message: "Say hello in exactly 5 words"
     - Loading indicator below (spinner or pulsing dots)
     - Status text: "Waiting for response..."

2. **`mockups/phase4_waiting_for_response_dark.png`** - Dark mode variant

3. **`mockups/phase4_response_received_light.png`** - Response displayed
   - User message visible
   - Claude's response visible (text block)
   - Thinking block visible (if extended thinking enabled) - collapsed by default
   - No loading indicator

4. **`mockups/phase4_backend_error_light.png`** - Error state
   - Error banner at top of conversation viewer
   - Red/error colored with error icon
   - Message: "Backend connection failed" or similar
   - Retry button

### Deliverables

1. **Copy backend service**:
   - `lib/services/backend_service.dart` (adapt from existing)

2. **Copy SDK message handler**:
   - `lib/services/sdk_message_handler.dart` (adapt for new models)

3. **Chat model integration**:
   - `ChatState.ensureSession()` creates real session
   - SDK messages flow to ConversationData.entries

4. **dart_sdk dependency**:
   - Add path dependency to `dart_sdk/`

5. **Test helper for programmatic message sending**:
   - Expose method for integration tests to send messages without UI
   - Keep app code clean - no test-specific startup behavior

### Integration Tests

- `test/integration/backend_connection_test.dart`
  - Launches app
  - Waits for backend to spawn
  - **Programmatically creates a chat and sends test prompt** ("Say hello in exactly 5 words")
  - Waits for response
  - Verifies response appears in conversation
  - Screenshots:
    - `screenshots/phase4_waiting_response.png`
    - `screenshots/phase4_response_received.png`

### Screenshot Verification (Claude)

- Conversation shows "Say hello in exactly 5 words" as user input
- Response from Claude is visible
- Response is approximately 5 words (validates real API connection)
- No error states visible

### Human Verification Checklist

- [ ] App launches and backend process starts (check process list)
- [ ] Run integration test - test prompt is sent and response received
- [ ] Response content makes sense (is a greeting, ~5 words)
- [ ] Backend logs appear in expected location (`/tmp/...`)
- [ ] App can be closed and backend process terminates

---

## Phase 5: User Input

**Goal**: Add message input to conversation viewer, allow user to send messages and receive responses.

### Mockups

Create mockups showing the input interface:

1. **`mockups/phase5_input_box_light.png`** - Light mode
   - Conversation viewer with input box at bottom
   - Input box styling:
     - Full width with padding
     - Subtle border (outlineVariant)
     - Placeholder text: "Type a message..."
     - Send button on right (primary color, icon or "Send" text)
   - Input box has focus ring when active

2. **`mockups/phase5_input_box_dark.png`** - Dark mode variant

3. **`mockups/phase5_typing_message_light.png`** - Message being typed
   - Input box with text visible: "What files handle authentication?"
   - Send button enabled/highlighted

4. **`mockups/phase5_message_sent_light.png`** - After send
   - User message appears in conversation (primaryContainer)
   - Input box cleared
   - Loading indicator below message

5. **`mockups/phase5_conversation_flow_light.png`** - Multi-turn conversation
   - Multiple user messages and responses
   - Demonstrates natural conversation flow
   - Scroll position showing recent messages

6. **`mockups/phase5_after_clear_light.png`** - After /clear command
   - Empty conversation viewer
   - Divider or message indicating "Conversation cleared"
   - Input box ready for new input

### Deliverables

1. **Message input widget**:
   - `lib/widgets/input/message_input.dart` (copy from existing)

2. **Input integration in conversation viewer**:
   - Input box at bottom of primary conversation
   - No input box for subagent conversations

3. **Send message flow**:
   - User types message → Chat.sendMessage() → ClaudeSession.send()
   - Response flows back via SDK message handler

4. **Remove auto-send test prompt** from Phase 4

5. **Basic /clear command support**:
   - Typing "/clear" clears session (new session on next message)

### Integration Tests

- `test/integration/user_input_test.dart`
  - Types a message in input box
  - Sends message
  - Waits for response
  - Verifies both user message and response appear
  - Tests /clear command
  - Screenshots:
    - `screenshots/phase5_typing_message.png`
    - `screenshots/phase5_message_sent.png`
    - `screenshots/phase5_response_received.png`
    - `screenshots/phase5_after_clear.png`

### Screenshot Verification (Claude)

- Input box is visible at bottom of conversation
- User message appears in conversation after send
- Response appears below user message
- After /clear, conversation is empty or shows cleared state
- Input box remains functional after /clear

### Human Verification Checklist

- [ ] Input box is visible and focusable
- [ ] Can type a message
- [ ] Pressing Enter (or Send button) sends message
- [ ] User message appears immediately in conversation
- [ ] Response appears after API responds
- [ ] Typing /clear clears the conversation
- [ ] Can send new message after /clear
- [ ] Input box NOT visible when viewing subagent conversation

---

## Phase 6: Permission Handling

**Goal**: Display permission requests and allow user to approve/deny them.

### Mockups

Create mockups showing permission request UI:

1. **`mockups/phase6_permission_request_light.png`** - Light mode
   - Permission request card prominently displayed:
     - Header: "Permission Required" with warning icon
     - Tool name and icon (e.g., "Read" with blue icon)
     - Tool details: file path, command, etc.
     - Two buttons: "Allow" (primary/green) and "Deny" (outlined/red)
     - Optional: "Always allow" checkbox
   - Rest of conversation visible but dimmed/behind

2. **`mockups/phase6_permission_request_dark.png`** - Dark mode variant

3. **`mockups/phase6_permission_bash_light.png`** - Bash permission
   - Shows Bash command in black box with green text
   - Command clearly visible for review
   - Explains what the command will do

4. **`mockups/phase6_permission_edit_light.png`** - Edit permission
   - Shows file path
   - Shows diff preview (old vs new)
   - Uses diff colors (red for removed, green for added)

5. **`mockups/phase6_permission_approved_light.png`** - After approval
   - Permission card dismissed
   - Tool card shows as "in progress" or completed
   - Result visible in tool card

6. **`mockups/phase6_permission_denied_light.png`** - After denial
   - Tool card shows error/denied state
   - Error message: "Permission denied by user"
   - Conversation continues

### Deliverables

1. **Copy permission widgets**:
   - `lib/widgets/display/permission_widgets.dart` (adapt from existing)

2. **Permission request queue** in Chat model (already designed)

3. **Permission UI integration**:
   - Permission requests appear in conversation viewer
   - Approve/Deny buttons functional
   - Response sent back to SDK

4. **Test scenario**: Ask Claude to read a file (triggers Read permission)

### Integration Tests

- `test/integration/permission_flow_test.dart`
  - Sends prompt that triggers tool use requiring permission
  - Verifies permission request appears
  - Clicks approve
  - Verifies tool proceeds
  - Screenshots:
    - `screenshots/phase6_permission_request.png`
    - `screenshots/phase6_permission_approved.png`
    - `screenshots/phase6_tool_completed.png`

### Screenshot Verification (Claude)

- Permission request card is visible with tool details
- Approve/Deny buttons are visible and properly styled
- After approval, tool result appears
- Tool card shows completed state

### Human Verification Checklist

- [ ] Send message that requires file read (e.g., "Read the file pubspec.yaml")
- [ ] Permission request appears with file path
- [ ] Clicking Approve allows tool to proceed
- [ ] Tool result appears in conversation
- [ ] Clicking Deny blocks the tool (test separately)
- [ ] Multiple permission requests queue correctly

---

## Phase 7: Git Integration & Worktree Discovery

**Goal**: Discover real worktrees from a git repository, display actual git status.

### Design Decisions

Before implementation, resolve:
- Error handling: what if path isn't a git repo? What if git isn't installed?
- Status refresh strategy: manual only, periodic polling, or file system watching?
- Project picker UX: directory browser, recent projects, or command line argument?

### Mockups

Create mockups showing real git data display:

1. **`mockups/phase7_worktree_with_status_light.png`** - Light mode
   - Worktree list with real-looking data:
     - Entry 1: "main" | "~/projects/cc-insights" | "↑0 ↓0 ~0" (clean)
     - Entry 2: "feat-dark-mode" | "../wt/dark-mode" | "↑3 ↓1 ~5" (changes)
     - Entry 3: "fix-auth" | "../wt/fix-auth" | "↑1 ↓0 ~2 ⚠" (conflict)
   - Status icons clearly visible and color-coded:
     - ↑ (green): commits ahead
     - ↓ (orange): commits behind
     - ~ (blue): uncommitted changes
     - ⚠ (red): merge conflict

2. **`mockups/phase7_worktree_with_status_dark.png`** - Dark mode variant

3. **`mockups/phase7_primary_vs_linked_light.png`** - Visual distinction
   - Primary worktree has subtle different styling (e.g., icon, background)
   - Linked worktrees show relative paths
   - Clear hierarchy

4. **`mockups/phase7_project_picker_light.png`** - Project selection dialog
   - Modal dialog: "Open Project"
   - Directory browser or recent projects list
   - "Open" and "Cancel" buttons

### Deliverables

1. **Git service**:
   - `lib/services/git_service.dart`
   - `discoverWorktrees(repoRoot)` - finds primary and linked worktrees
   - `getWorktreeStatus(worktreePath)` - uncommitted, ahead/behind, conflicts
   - `getCurrentBranch(worktreePath)` - current branch name

2. **Project initialization from real repo**:
   - App opens with directory picker (or uses current directory)
   - Discovers worktrees from selected repo
   - Populates Project model with real data

3. **Worktree panel updates**:
   - Shows real branch names
   - Shows real paths
   - Shows real status icons (↑↓~⚠)

4. **Status refresh**:
   - Periodic refresh of git status
   - Manual refresh button

### Integration Tests

- `test/integration/git_discovery_test.dart`
  - Launches app pointed at test repo (create fixture)
  - Verifies worktrees discovered
  - Verifies status icons appear
  - Screenshots:
    - `screenshots/phase7_real_worktrees.png`
    - `screenshots/phase7_worktree_status.png`

### Screenshot Verification (Claude)

- Worktree list shows real branch names (not mock data)
- Paths are real filesystem paths
- Status icons reflect actual git state
- Primary worktree is distinguishable from linked

### Human Verification Checklist

- [ ] Launch app in a real git repo with worktrees
- [ ] All worktrees are discovered and listed
- [ ] Branch names are correct
- [ ] Paths are correct
- [ ] Make a file change, status updates (after refresh)
- [ ] Commit count ahead/behind is accurate

---

## Phase 8: Persistence

**Goal**: Save and restore project state, chats, and conversations across app restarts.

### Design Decisions

Before implementation, resolve:
- What triggers auto-save: on every change, debounced, or explicit save?
- Conversation entry serialization: full entries or metadata only for now?
- Startup behavior when saved project no longer exists on disk?

### Mockups

Create mockups showing persistence-related UI:

1. **`mockups/phase8_startup_loading_light.png`** - Light mode
   - App startup with loading state
   - Centered spinner or progress indicator
   - Text: "Loading project..."
   - Previous project name shown if available

2. **`mockups/phase8_startup_loading_dark.png`** - Dark mode variant

3. **`mockups/phase8_restored_state_light.png`** - After restore
   - App showing restored state
   - Same worktree/chat selected as before
   - Conversation history visible
   - Visual indicator that state was restored (optional, subtle)

4. **`mockups/phase8_no_project_light.png`** - No saved project
   - Welcome/empty state
   - "Open a project to get started"
   - "Open Project" button prominently displayed
   - Recent projects list if any exist

### Deliverables

1. **Persistence service**:
   - `lib/services/persistence_service.dart`
   - Save/load projects.json
   - Save/load chat JSON files
   - Handle conversation entries (future: full logs)

2. **App startup flow**:
   - Load last project from persistence
   - Restore worktree/chat/conversation selection
   - Or show project picker if no saved state

3. **Auto-save on changes**:
   - Save chat metadata when created/modified
   - Save selection state

4. **Persistence location**: `~/.cc-insights/`

### Integration Tests

- `test/integration/persistence_test.dart`
  - Creates a chat, sends a message
  - Captures state
  - Simulates app restart (or tests persistence service directly)
  - Verifies state restored
  - Screenshots:
    - `screenshots/phase8_before_restart.png`
    - `screenshots/phase8_after_restart.png`

### Screenshot Verification (Claude)

- Before restart: conversation has messages
- After restart: same conversation visible with same messages
- Selection state preserved (same worktree/chat selected)

### Human Verification Checklist

- [ ] Create a chat and send messages
- [ ] Close app completely
- [ ] Reopen app
- [ ] Same project is loaded
- [ ] Chat is still there with messages
- [ ] Selection is restored
- [ ] Check `~/.cc-insights/` contains expected files

---

## Phase 9: Files Panel & File Viewer

**Goal**: Add file tree navigator and read-only file viewer with syntax highlighting.

### Mockups

Create mockups showing file browser and viewer:

1. **`mockups/phase9_file_tree_light.png`** - Light mode
   - Files panel showing directory tree:
     - Header: "Files" with refresh button
     - Root folder: project name
     - Expanded folders with indent
     - File icons by type (dart, md, json, yaml, etc.)
     - Folder expand/collapse arrows
   - Example structure:
     ```
     📁 lib/
       📁 models/
         📄 project.dart
         📄 worktree.dart
       📁 panels/
         📄 worktree_panel.dart
       📄 main.dart
     📁 test/
     📄 pubspec.yaml
     ```

2. **`mockups/phase9_file_tree_dark.png`** - Dark mode variant

3. **`mockups/phase9_file_viewer_light.png`** - File content display
   - File viewer panel showing:
     - Header: file name and path
     - Line numbers on left
     - Syntax highlighted code
     - Monospace font (JetBrains Mono)
   - Dart file with proper highlighting:
     - Keywords (class, final, void) in one color
     - Strings in another
     - Comments in muted color

4. **`mockups/phase9_file_selected_light.png`** - File selected in tree
   - File tree with one file highlighted
   - File viewer showing that file's content
   - Clear visual connection between selection and viewer

5. **`mockups/phase9_four_panel_layout_light.png`** - Layout with files panel
   - Full layout showing:
     - Worktrees (left)
     - Chats (middle-left)
     - Conversation (middle-right)
     - Files (right)
   - Or alternative arrangement

### Deliverables

1. **Files panel**:
   - `lib/panels/files_panel.dart`
   - Tree view of worktree directory
   - Expand/collapse folders
   - File icons by type

2. **File viewer panel**:
   - `lib/panels/file_viewer_panel.dart`
   - Read-only display of selected file
   - Syntax highlighting (use existing package or simple approach)

3. **Selection integration**:
   - Clicking file updates `selectionState.selectedFilePath`
   - File viewer shows selected file

4. **Panel layout update**:
   - Files panel can be added to layout
   - File viewer can be added to layout

### Integration Tests

- `test/integration/file_browser_test.dart`
  - Navigate file tree
  - Select a file
  - Verify file content displayed
  - Screenshots:
    - `screenshots/phase9_file_tree.png`
    - `screenshots/phase9_file_selected.png`
    - `screenshots/phase9_file_content.png`

### Screenshot Verification (Claude)

- File tree shows folder structure
- Folders have expand/collapse icons
- Files have type-appropriate icons
- Selected file is highlighted
- File viewer shows file content
- Syntax highlighting is applied (colors visible)

### Human Verification Checklist

- [ ] File tree shows worktree directory contents
- [ ] Can expand/collapse folders
- [ ] Clicking file shows content in viewer
- [ ] Syntax highlighting works for .dart files
- [ ] Large files scroll properly
- [ ] Selecting different worktree updates file tree

---

## Phase 10: Git Status Panel

**Goal**: Add git status panel showing branch info, uncommitted changes, and commit history.

### Mockups

Create mockups showing git status panel:

1. **`mockups/phase10_git_status_panel_light.png`** - Light mode
   - Git status panel showing:
     - Header: "Git Status" with refresh button
     - Branch info section:
       - Current branch: "feat-dark-mode"
       - Upstream: "origin/feat-dark-mode"
       - "Forked from main, 5 commits ahead, 2 behind"
     - Uncommitted changes section:
       - Header: "Uncommitted Changes (7)"
       - File list with status icons:
         - M (modified, yellow): lib/main.dart
         - A (added, green): lib/theme.dart
         - D (deleted, red): lib/old_theme.dart
         - ? (untracked, grey): lib/temp.dart
     - Recent commits section:
       - Header: "Recent Commits"
       - Commit entries: hash (truncated) + message
         - "abc1234 Add dark theme toggle"
         - "def5678 Create theme provider"

2. **`mockups/phase10_git_status_panel_dark.png`** - Dark mode variant

3. **`mockups/phase10_git_actions_light.png`** - Action buttons
   - Bottom of git status panel:
     - "Stage All" button
     - "Commit..." button (opens dialog)
     - "Merge to main..." button (placeholder/disabled)
   - Buttons styled per theme

4. **`mockups/phase10_clean_worktree_light.png`** - Clean state
   - Git status for a worktree with no changes:
     - "Working tree clean" message
     - No uncommitted changes section
     - Commit history still visible

### Deliverables

1. **Git status panel**:
   - `lib/panels/git_status_panel.dart`
   - Branch name and upstream info
   - List of uncommitted changes (M/A/D/?)
   - Recent commits since fork point

2. **Git service extensions**:
   - `getUncommittedChanges(worktreePath)`
   - `getRecentCommits(worktreePath, count)`
   - `getForkPoint(worktreePath)` (for branches)

3. **Action buttons** (UI only, not functional yet):
   - Stage All
   - Commit...
   - Merge... (placeholder)

### Integration Tests

- `test/integration/git_status_test.dart`
  - Display git status for a worktree
  - Verify uncommitted files shown
  - Verify commits shown
  - Screenshots:
    - `screenshots/phase10_git_status.png`
    - `screenshots/phase10_uncommitted_changes.png`

### Screenshot Verification (Claude)

- Branch name is displayed
- Uncommitted changes list shows file paths with status icons
- Commit list shows commit hashes and messages
- Action buttons are visible (even if non-functional)

### Human Verification Checklist

- [ ] Git status panel shows current branch
- [ ] Uncommitted changes are listed correctly
- [ ] Change a file, verify it appears after refresh
- [ ] Commit history shows recent commits
- [ ] Switching worktrees updates git status panel

---

## Phase 11: Panel Drag & Drop

**Goal**: Implement full panel drag-and-drop with ghost targets for flexible layout.

### Design Decisions

Before implementation, resolve:
- Ghost target visual design: how to indicate valid drop zones?
- Drop behavior: what happens when dropping on center (tab vs replace)?
- Collapse behavior: icon bar position (left, right, or contextual)?
- Layout data structure: how to serialize/deserialize panel arrangements?
- Minimum panel sizes: what are the constraints?

### Mockups

Create mockups showing drag-and-drop interactions:

1. **`mockups/phase11_panel_header_light.png`** - Draggable panel header
   - Panel header with:
     - Panel title
     - Drag handle icon (grip dots or similar)
     - Collapse button
     - Close button (optional)
   - Hover state showing drag affordance

2. **`mockups/phase11_dragging_panel_light.png`** - Panel being dragged
   - Semi-transparent panel following cursor
   - Original position shows empty/placeholder state
   - Ghost panel has drop shadow

3. **`mockups/phase11_ghost_targets_light.png`** - Ghost targets visible
   - Current layout with ghost targets overlaid:
     - Edge targets (hash marks at top, bottom, left, right of each panel)
     - Center target for each panel
     - Outer edge targets for full-width/height splits
   - Ghost targets shown as semi-transparent rectangles
   - Active/hovered target highlighted

4. **`mockups/phase11_ghost_targets_dark.png`** - Dark mode variant

5. **`mockups/phase11_drop_preview_light.png`** - Drop preview
   - Target highlighted showing where panel will land
   - Preview of resulting layout (outline)
   - Clear visual feedback

6. **`mockups/phase11_after_drop_light.png`** - After successful drop
   - New layout with panel in new position
   - Dividers properly positioned
   - All panels functional

7. **`mockups/phase11_collapsed_panel_light.png`** - Collapsed panel
   - Panel collapsed to icon in sidebar
   - Icon with panel name tooltip
   - Click to expand

8. **`mockups/phase11_icon_bar_light.png`** - Icon bar with collapsed panels
   - Vertical bar on edge of screen
   - Icons for collapsed panels
   - Expand on click

### Deliverables

1. **Enhanced panel manager**:
   - Drag panel headers to reposition
   - Ghost targets appear during drag
   - Drop zones: edges (split) and center (replace/tab)

2. **Layout serialization**:
   - Save panel layout to persistence
   - Restore layout on app start

3. **Panel collapse/expand**:
   - Collapse panel to icon bar
   - Expand from icon bar

### Integration Tests

- `test/integration/panel_drag_drop_test.dart`
  - Drag a panel to new location
  - Verify layout changes
  - Collapse and expand a panel
  - Screenshots:
    - `screenshots/phase11_dragging.png`
    - `screenshots/phase11_ghost_targets.png`
    - `screenshots/phase11_dropped.png`
    - `screenshots/phase11_collapsed.png`

### Screenshot Verification (Claude)

- Ghost targets visible during drag
- Ghost targets highlight valid drop zones
- After drop, panel is in new location
- Collapsed panel shows as icon
- Layout is coherent after changes

### Human Verification Checklist

- [ ] Can drag panel by header
- [ ] Ghost targets appear during drag
- [ ] Dropping on edge creates split
- [ ] Dropping in center replaces/tabs
- [ ] Collapsed panel can be expanded
- [ ] Layout persists across restart

---

## Phase 12: Subagent Display

**Goal**: Properly handle subagent creation, display subagent conversations, and route subagent permissions.

### Mockups

Create mockups showing subagent handling:

1. **`mockups/phase12_subagent_in_tree_light.png`** - Light mode
   - Chat panel showing conversation tree:
     - Chat 1 expanded:
       - "Primary" (selected or default)
       - "Subagent: Explore" with icon
       - "Subagent: Plan" with icon
     - Subagent entries indented
     - Status indicators (working, completed, error)

2. **`mockups/phase12_subagent_in_tree_dark.png`** - Dark mode variant

3. **`mockups/phase12_subagent_output_light.png`** - Subagent conversation view
   - Subagent selected in tree
   - Conversation viewer showing:
     - Header: "Subagent: Explore"
     - Task description shown
     - Subagent's tool uses and output
   - NO input box at bottom

4. **`mockups/phase12_subagent_creating_light.png`** - Subagent being created
   - Task tool card in primary conversation
   - Shows subagent type and description
   - Status: "Creating subagent..."
   - Spinner or progress indicator

5. **`mockups/phase12_subagent_permission_light.png`** - Subagent permission request
   - Permission request from subagent
   - Clear indication it's from subagent (badge or header)
   - Shows which subagent is requesting
   - Approve/Deny buttons

6. **`mockups/phase12_subagent_completed_light.png`** - Completed subagent
   - Subagent in tree showing completed status (checkmark)
   - Subagent conversation showing final result
   - Result summary visible

7. **`mockups/phase12_multiple_subagents_light.png`** - Multiple active subagents
   - Tree showing multiple subagents with different statuses:
     - "Explore" - completed (✓)
     - "Plan" - working (spinner)
     - "Bash" - error (✗)
   - Visual hierarchy clear

### Deliverables

1. **Subagent creation handling**:
   - SDK message handler detects Task tool creating subagent
   - Creates Conversation for subagent
   - Creates runtime Agent linked to Conversation

2. **Conversation tree in chat panel**:
   - Shows Primary + subagent conversations
   - Subagents show label (Explore, Plan, etc.)

3. **Subagent output routing**:
   - SDK messages for subagent go to correct Conversation
   - Selecting subagent conversation shows its output

4. **Subagent permission routing**:
   - Permission requests from subagent appear
   - Approval/denial sent for correct agent

### Integration Tests

- `test/integration/subagent_test.dart`
  - Send prompt that triggers subagent (e.g., "Search the codebase for X")
  - Verify subagent conversation created
  - Verify subagent output appears in correct conversation
  - Screenshots:
    - `screenshots/phase12_subagent_created.png`
    - `screenshots/phase12_subagent_output.png`
    - `screenshots/phase12_subagent_permission.png`

### Screenshot Verification (Claude)

- Conversation tree shows Primary + subagent
- Subagent has descriptive label
- Subagent output is separate from primary
- Subagent conversation has no input box
- Permission request shows subagent context

### Human Verification Checklist

- [ ] Send prompt that creates subagent (Task tool usage)
- [ ] Subagent appears in conversation tree
- [ ] Clicking subagent shows its output
- [ ] Subagent conversation has no input box
- [ ] Primary conversation still works
- [ ] Subagent permissions can be approved/denied

---

## Phase 13: Polish & Migration

**Goal**: Final polish, migrate from flutter_app to flutter_app_v2, update documentation.

### Mockups

Create mockups showing final polished application:

1. **`mockups/phase13_full_layout_light.png`** - Light mode, complete app
   - Full application showing all panels working together:
     - Worktrees panel (left)
     - Chats panel (with conversation tree)
     - Conversation viewer (main area)
     - Files panel (right or bottom)
     - Git status panel (right or bottom)
   - All panels with proper headers, icons, styling
   - Resizable dividers visible
   - Active conversation with multiple messages
   - One subagent in tree
   - File selected in file tree
   - Git status showing some changes

2. **`mockups/phase13_full_layout_dark.png`** - Dark mode, complete app
   - Same layout as light mode
   - All colors properly adapted for dark theme
   - Ensure contrast and readability

3. **`mockups/phase13_empty_project_light.png`** - No project loaded
   - Welcome state when no project is open:
     - Centered content area
     - App logo or icon
     - "Welcome to CC-Insights V2"
     - "Open a project to get started"
     - "Open Project" button (primary styled)
     - "Recent Projects" list if any exist
   - Subtle, clean design

4. **`mockups/phase13_empty_project_dark.png`** - Dark mode variant

5. **`mockups/phase13_empty_worktree_light.png`** - No chats in worktree
   - Worktree selected but no chats yet
   - Chat panel showing:
     - "No chats yet"
     - "Start a new chat with Claude"
     - "New Chat" button
   - Conversation viewer empty or showing prompt

6. **`mockups/phase13_error_backend_light.png`** - Backend error state
   - Error banner across top of app:
     - Red/error colored background
     - Error icon
     - "Backend disconnected" or "Backend crashed"
     - "Retry" button
   - Rest of UI dimmed or showing last state
   - Clear that app is not functional until resolved

7. **`mockups/phase13_error_backend_dark.png`** - Dark mode variant

8. **`mockups/phase13_error_api_light.png`** - API error state
   - Conversation showing API error:
     - User message visible
     - Error card where response would be:
       - Red border
       - Error icon
       - "API Error: Rate limit exceeded" or similar
       - "Retry" button
   - Rest of conversation still visible

9. **`mockups/phase13_loading_state_light.png`** - App loading
   - Splash/loading state on startup:
     - App logo centered
     - Loading spinner
     - "Loading project..."
     - Optional: progress text "Connecting to backend..."

10. **`mockups/phase13_panel_icons_light.png`** - Panel header icons
    - Close-up of panel headers showing standard icons:
      - Worktrees: folder tree icon
      - Chats: chat bubble icon
      - Files: folder icon
      - Git Status: git branch icon
      - Conversation: message icon
    - Consistent icon style throughout

### Deliverables

1. **Visual polish**:
   - Consistent theming
   - Icons for all panels
   - Loading states
   - Error states

2. **Edge case handling**:
   - Empty states (no chats, no worktrees)
   - Error recovery
   - Backend crash handling

3. **Documentation update**:
   - Update CLAUDE.md to reflect V2 structure
   - Update README if exists

4. **Cleanup**:
   - Remove any temporary test code
   - Ensure all phases' tests still pass

### Integration Tests

- `test/integration/full_workflow_test.dart`
  - Complete workflow: open project, create chat, send messages, use tools
  - Verify all panels work together
  - Screenshots:
    - `screenshots/phase13_full_layout.png`
    - `screenshots/phase13_empty_state.png`
    - `screenshots/phase13_error_state.png`

### Screenshot Verification (Claude)

- Full layout is polished and consistent
- Empty states are user-friendly
- Error states are informative
- All panels render correctly together

### Human Verification Checklist

- [ ] Complete workflow works end-to-end
- [ ] App handles empty project gracefully
- [ ] App handles backend crash gracefully
- [ ] All panels work together
- [ ] Layout is visually polished
- [ ] Documentation is updated
- [ ] All previous phase tests still pass

---

## Summary

| Phase | Goal | Key Deliverables |
|-------|------|------------------|
| 0 | Project Scaffold | New Flutter project, directory structure, test infra |
| 1 | Core Models | Data models, SelectionState, mock data display |
| 2 | Panel Infrastructure | Resizable panels, basic two-column layout |
| 3 | Chat & Conversation Display | Chat panel, conversation viewer, copied display widgets |
| 4 | Backend Integration | Real ClaudeSession, SDK message flow |
| 5 | User Input | Message input, send/receive messages, /clear |
| 6 | Permission Handling | Permission request display, approve/deny flow |
| 7 | Git Integration | Worktree discovery, real git status |
| 8 | Persistence | Save/restore state across restarts |
| 9 | Files Panel | File tree, read-only file viewer |
| 10 | Git Status Panel | Uncommitted changes, commit history |
| 11 | Panel Drag & Drop | Full panel rearrangement with ghost targets |
| 12 | Subagent Display | Subagent conversations, output routing |
| 13 | Polish & Migration | Final polish, migrate to flutter_app |

---

## Phase Gate Checklist Template

Before proceeding to next phase, verify:

- [ ] All integration tests pass
- [ ] All screenshots captured
- [ ] Claude has reviewed screenshots and approved
- [ ] Human has verified all checklist items
- [ ] No regressions from previous phases
- [ ] Code committed with phase tag (e.g., `v2-phase-3`)
