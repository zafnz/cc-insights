# Worktrees UI Refactor Plan

## Overview

Refactor the UI to properly support worktrees by:
1. Adding a welcome screen for new projects
2. Separating project/worktree entries from active Claude sessions
3. Grouping sessions by worktree in a flat list
4. Supporting multiple sessions per worktree
5. Renaming commands to `/worktree new` and `/worktree done`

---

## Updated Config Schema

```json
{
  "/tmp/cc-insights/claude-system": {
    "mainBranch": "main",
    "worktreeEnabled": true,
    "worktreePath": "/tmp/cc-insights/claude-system-wt",
    "autoSelectWorktree": true,
    "sessions": [
      {
        "sessionId": "123-456-789",
        "name": "Why is the sky blue?",
        "createdAt": "2025-01-24T10:30:00Z"
      }
    ],
    "worktrees": {
      "cci/add-dark-mode": {
        "taskDescription": "Add dark mode toggle",
        "merged": false,
        "createdAt": "2025-01-24T10:30:00Z",
        "deleted": false,
        "sessions": [
          {
            "sessionId": "456-789-012",
            "name": "Add Dark Mode",
            "createdAt": "2025-01-24T10:35:00Z"
          }
        ]
      }
    }
  }
}
```

**Key changes from current schema:**
- Root-level `sessions` array for main branch sessions
- `WorktreeInfo.sessions` is now an array (was single `sessionId`)
- Added `deleted` field to `WorktreeInfo` for history/undo
- Added `SessionInfo` class with `sessionId`, `name`, `createdAt`

**Session without Claude session:**
- A session entry can have `sessionId: null` - this represents a UI session that hasn't sent its first message yet
- Displayed as "Start chatting" until first message sent
- On first message: create Claude session, update `sessionId`, rename to first few words of message

---

## UI Flow

### App Startup

```
┌─────────────────────────────────────────────────────────┐
│ Is current directory in projects.json?                  │
├──────────────┬──────────────────────────────────────────┤
│     NO       │                  YES                     │
│              │                                          │
│  Welcome     │  Load project config                     │
│  Screen      │  Show sessions panel                     │
│              │  Show ProjectOpenedPanel if no session   │
│              │  selected, else show conversation        │
└──────────────┴──────────────────────────────────────────┘
```

### Welcome Screen

Shown when cwd is not in `projects.json`. Full-screen, replaces normal UI.

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│              Welcome to CC Insights                     │
│                                                         │
│   Current directory:                                    │
│   /tmp/cc-insights/my-project                        │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │  Begin work in this folder                      │   │
│   └─────────────────────────────────────────────────┘   │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │  Open a different folder...                     │   │
│   └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Actions:**
- "Begin work in this folder" → Creates project entry in config (minimal: just the path), shows main UI
- "Open a different folder" → Opens folder picker, then creates project entry for selected folder

---

### Sessions Panel (Flat List with Groups)

```
┌──────────────────────────┐
│ Sessions            [+]  │
├──────────────────────────┤
│ ▼ main                   │  ← Collapsible group header
│   • Session 1            │
│   • Session 2            │
│ ▼ cci/add-dark-mode      │  ← Worktree group
│   • Add Dark Mode        │
│   • Debug session        │
│ ▼ cci/fix-login-bug      │
│   • Fix Login Bug        │
│ ▸ cci/old-feature [done] │  ← Collapsed, marked merged
│                          │
└──────────────────────────┘
```

**Features:**
- Groups are collapsible (▼ expanded, ▸ collapsed)
- Main branch group always first
- Worktrees sorted by creation date (newest first)
- Merged/done worktrees show `[done]` badge, collapsed by default
- Right-click on worktree group header → context menu:
  - "New session" - creates session in this worktree
  - "Mark as done" - runs `/worktree done` flow
- `[+]` button in header creates new session in main branch (or currently selected worktree?)

**Session display:**
- Sessions with `sessionId: null` show "Start chatting" as name
- Sessions show name (editable in future), truncated
- Selected session highlighted
- Running indicator (green dot) if Claude session active

---

### Project Opened Panel

Shown in conversation area when:
- Project is loaded (in config)
- No session is currently selected, OR
- Selected session has no Claude session yet (`sessionId: null`)

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│              Begin chatting below                       │
│                                                         │
│   Model: [Opus ▼]                                       │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │ Tip: Create worktrees to work on multiple       │   │
│   │ branches simultaneously. Type /worktree new     │   │
│   └─────────────────────────────────────────────────┘   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ What would you like to work on?                     [>] │
└─────────────────────────────────────────────────────────┘
```

**On message submit:**
1. Create Claude session via backend
2. Update session entry: set `sessionId`, rename to first words of message
3. Show conversation panel with the new session

---

### New Worktree Panel

Shown in conversation area when a new worktree session is created (via `/worktree new`).
This is the `ProjectOpenedPanel` but with worktree-specific content.

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│          Working on: cci/add-dark-mode                  │
│                                                         │
│   Model: [Opus ▼]                                       │
│                                                         │
│   ┌─────────────────────────────────────────────────┐   │
│   │ When you're done with this feature and have     │   │
│   │ merged the branch, type /worktree done or       │   │
│   │ right-click the worktree in the sidebar.        │   │
│   └─────────────────────────────────────────────────┘   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ What would you like to work on?                     [>] │
└─────────────────────────────────────────────────────────┘
```

---

## Command Changes

### Remove
- `/workstart` → replaced by `/worktree new`
- `/workdone` → replaced by `/worktree done`

### New Command Structure

```
/worktree new <task>      (aliases: create, add)
/worktree done            (aliases: finished, close)
/worktree list            (shows all worktrees, also keep /worktrees as alias)
```

### `/worktree new <task>` Flow

1. Parse task description from command
2. If not a git repo → error message
3. If current branch is not main/master → warning dialog:
   > "You're creating a worktree from branch `feature-x`, not `main`. Continue?"
   > [Abort] [Continue]
4. Generate branch name `cci/<task-slug>` with conflict resolution (-1, -2, etc.)
5. Create git worktree via `git worktree add -b <branch> <path> origin/<main>`
6. Add worktree to config with empty `sessions` array
7. Create new session entry in the worktree:
   - `sessionId: null` (no Claude session yet)
   - `name: "Start chatting"`
   - `createdAt: now`
8. Select the new session
9. Show NewWorktreePanel in conversation area

**Note:** No onboarding dialog needed. Worktrees are enabled implicitly on first use. The config fields `worktreeEnabled`, `worktreePath`, etc. are populated with defaults when first worktree is created.

### `/worktree done` Flow

1. Validate we're in a worktree session (else error)
2. Check uncommitted changes via `git status --porcelain` → warning if any
3. Check merge status → warning if not merged or uncertain
4. Show confirmation dialog (existing `WorkdoneConfirmationDialog`)
5. On confirm:
   - Set `merged: true` in config
   - Set `deleted: true` if user chose to delete directory
   - Run `git worktree remove <path>` if deleting
   - Optionally close session

---

## Data Model Changes

### New: `SessionInfo` class

```dart
class SessionInfo {
  final String? sessionId;  // null = no Claude session yet
  final String name;
  final DateTime createdAt;

  // Future fields:
  // final double totalCost;
  // final int tokenCount;
}
```

### Updated: `WorktreeInfo` class

```dart
class WorktreeInfo {
  final String taskDescription;
  final bool merged;
  final DateTime createdAt;
  final bool deleted;
  final List<SessionInfo> sessions;  // Changed from single sessionId
}
```

### Updated: `ProjectWorktreeConfig` class

```dart
class ProjectWorktreeConfig {
  final String mainBranch;
  final bool worktreeEnabled;
  final String worktreePath;
  final bool autoSelectWorktree;
  final List<SessionInfo> sessions;  // NEW: main branch sessions
  final Map<String, WorktreeInfo> worktrees;
}
```

### Session name generation

When first message is sent to a session with `sessionId: null`:
1. Create Claude session via backend
2. Update `sessionId` in config
3. Generate name from first message: `generateSessionName(message)` → async function
   - For now: first 5-6 words, truncated to ~40 chars
   - Future: LLM-generated summary

---

## Implementation Tasks

### Phase 1: Config Schema Update
1. Create `SessionInfo` class with `sessionId`, `name`, `createdAt`
2. Update `WorktreeInfo` to use `List<SessionInfo> sessions` instead of `sessionId`
3. Add `deleted` field to `WorktreeInfo`
4. Add `List<SessionInfo> sessions` to `ProjectWorktreeConfig` (main branch sessions)
5. Update JSON serialization/deserialization
6. Update all code that references `WorktreeInfo.sessionId`
7. Add helper methods: `addSession()`, `updateSessionName()`, `removeSession()`

### Phase 2: Welcome Screen
1. Create `WelcomeScreen` widget in `lib/widgets/welcome_screen.dart`
2. Add `hasProject(String path)` method to `ProjectConfigService`
3. Add `addProject(String path)` method to `ProjectConfigService` (creates minimal entry)
4. Update `HomeScreen` to check if project exists on startup
5. Show `WelcomeScreen` if project not in config
6. Handle folder picker for "Open different folder"
7. On project add → show main UI

### Phase 3: Sessions Panel Redesign
1. Create `SessionGroup` widget (collapsible header + session list)
2. Rewrite `SessionList` to show grouped sessions:
   - Main branch group first
   - Worktree groups sorted by creation date
   - Merged worktrees collapsed by default with `[done]` badge
3. Add context menu to worktree group headers
4. Handle session selection within groups
5. Show "Start chatting" for sessions with `sessionId: null`
6. Add `[+]` button behavior

### Phase 4: Project Opened Panel
1. Create `ProjectOpenedPanel` widget in `lib/widgets/project_opened_panel.dart`
2. Include model selector dropdown
3. Include worktree tip text
4. Include message input at bottom
5. Show in conversation area when no active session
6. Create `NewWorktreePanel` variant with worktree-specific text

### Phase 5: Session Lifecycle
1. Support sessions with `sessionId: null` in `SessionProvider`
2. On first message to null-session:
   - Create Claude session via backend
   - Update `sessionId` in config
   - Generate and set session name
3. Add `generateSessionName(String firstMessage)` function
4. Track which worktree/main a session belongs to
5. Persist session info to config on creation

### Phase 6: Command Rename
1. Replace `/workstart` handler with `/worktree new` (+ aliases: create, add)
2. Replace `/workdone` handler with `/worktree done` (+ aliases: finished, close)
3. Add `/worktree list` (alias for existing `/worktrees`)
4. Remove onboarding dialog trigger - worktrees enabled implicitly
5. Add "creating from non-main branch" warning dialog
6. Update all help text and user-facing messages
7. Update tests to use new command names

### Phase 7: Testing
1. Unit tests for new `SessionInfo` class
2. Unit tests for updated config serialization
3. Widget tests for `WelcomeScreen`
4. Widget tests for `SessionGroup` and new `SessionList`
5. Widget tests for `ProjectOpenedPanel`
6. Integration tests for full flow:
   - App startup → welcome screen → add project → main UI
   - Create worktree → new session → send message → conversation
   - `/worktree done` flow

---

## Files to Create

| File | Purpose |
|------|---------|
| `lib/widgets/welcome_screen.dart` | Welcome screen for new projects |
| `lib/widgets/project_opened_panel.dart` | Panel shown before first message |
| `lib/widgets/session_group.dart` | Collapsible session group in sidebar |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/services/project_config_service.dart` | Schema changes, new classes, helper methods |
| `lib/widgets/session_list.dart` | Complete rewrite for grouped view |
| `lib/screens/home_screen.dart` | Welcome screen integration, panel switching |
| `lib/providers/session_provider.dart` | Command rename, null-session support, session persistence |
| `lib/main.dart` | Project existence check on startup |
| `lib/widgets/worktree_onboarding_dialog.dart` | May be removed or simplified |

---

## Migration Notes

Since this is dogfooding only, no migration needed. Existing `projects.json` files can be deleted and recreated.

---

## Future Considerations (Not in This Refactor)

1. **Session persistence across restarts** - Load sessions from config, resume Claude sessions
2. **LLM-generated session names** - Use Claude to summarize first message into a good name
3. **Trusted/untrusted project check** - Security consideration for opening arbitrary folders
4. **Token usage tracking** - Track cost per session, store in config
5. **Session renaming UI** - Allow users to edit session names
6. **Collapsed state persistence** - Remember which groups are collapsed
