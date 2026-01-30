# Git Worktrees Feature Implementation Plan

## Overview

Add Git worktree support to CC Insights, enabling users to work on isolated branches in separate directories with dedicated sessions. This feature introduces three new slash commands (`/workstart`, `/workdone`, `/worktrees`) and per-project configuration storage.

## Commands Summary

| Command | Description |
|---------|-------------|
| `/workstart <task>` | Create a new worktree + session for a task |
| `/workdone` | Mark current worktree as complete (with warnings) |
| `/worktrees` | List all worktrees and their status |

---

## Data Model

### Project Configuration (`~/.ccinsights/projects.json`)

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
        "name": "Why is the sky blue?"
      }
    ],
    "worktrees": {
      "cci/add-dark-mode": {
        "name": "Add Dark Mode",
        "merged": false,
        "branchName": "add-dark-mode",
        "createdAt": "2025-01-24T10:30:00Z",
        "taskDescription": "Add dark mode toggle",
        "deleted": false,
        "sessions": [
          {
            "sessionId": "123-456-789",
            "name": "Add Dark Mode"
          }
        ]
      }
    }
  }
}
```

### Session Model Extension

Add to `Session` class:
- `worktreeBranch: String?` - branch name if worktree session
- `isWorktreeSession` getter - `worktreeBranch != null`
- `isMainSession` getter - `worktreeBranch == null`

---

## Implementation Components

### 1. New Service: `ProjectConfigService`

**File:** `flutter_app/lib/services/project_config_service.dart`

Follows `RuntimeConfig` pattern for per-project settings persistence.

**Key Methods:**
- `initialize()` - Load from `~/.ccinsights/projects.json`
- `getProject(path)` - Get config for a project
- `enableWorktrees(projectPath, mainBranch, worktreePath)` - Enable feature
- `addWorktree(projectPath, branchName, sessionId, task)` - Register worktree
- `markWorktreeMerged(projectPath, branchName)` - Mark as done
- `removeWorktree(projectPath, branchName)` - Remove from config
- `set autoSelectWorktree` - User preference

**Data Classes:**
- `ProjectWorktreeConfig` - Per-project settings
- `WorktreeInfo` - Individual worktree metadata

### 2. New Service: `GitWorktreeService`

**File:** `flutter_app/lib/services/git_worktree_service.dart`

Executes git commands via `dart:io Process.run()` directly in Flutter.

**Key Methods:**
```dart
Future<GitRepoInfo?> getRepoInfo(String directory)
// Checks if directory is git repo root, returns main branch, current branch

Future<WorktreeCreateResult> createWorktree({
  required String repoPath,
  required String worktreePath,
  required String branchName,
  required String baseBranch,
})
// git fetch origin && git worktree add -b <branch> <path> origin/<base>

Future<MergeStatus> checkMergeStatus({
  required String repoPath,
  required String branch,
  required String targetBranch,
})
// Uses git branch --merged + git log <target>..<branch> for detection

Future<bool> hasUncommittedChanges(String worktreePath)
// git status --porcelain

Future<void> removeWorktree(String repoPath, String worktreePath)
// git worktree remove <path>

String generateBranchName(String task, {List<String> existingBranches})
// Converts "Add dark mode" -> "cci/add-dark-mode", handles conflicts with -1, -2
```

**Branch Name Algorithm:**
1. Lowercase the task
2. Replace non-alphanumeric with hyphens
3. Collapse multiple hyphens
4. Trim to max 50 chars
5. Prepend `cci/`
6. If exists, append `-1`, `-2`, etc.

### 3. Slash Command Handlers

**Modify:** `flutter_app/lib/providers/session_provider.dart`

#### `/workstart <task>` Handler

```
1. Parse task from command
2. If worktrees not enabled for project → show onboarding dialog
3. Generate branch name (with conflict suffix if needed)
4. Create worktree: git worktree add -b cci/task-slug <path> origin/<main>
5. Save to project config
6. Create new session with worktree path as cwd
7. Auto-select new session (if user preference enabled)
8. Show success message in original session
```

#### `/workdone` Handler

```
1. Validate this is a worktree session (else error)
2. Check for uncommitted changes: git status --porcelain
3. Check merge status (merged / not merged / uncertain)
4. Show confirmation dialog with:
   - Warnings for uncommitted changes
   - Warning if not merged or uncertain
   - Checkbox: "Delete worktree directory"
   - Checkbox: "Close this session"
5. On confirm:
   - Mark worktree as merged in config
   - Optionally delete directory: git worktree remove <path>
   - Optionally close session
```

#### `/worktrees` Handler

```
1. Get project config for current cwd
2. If not enabled → show message about /workstart
3. List all worktrees with status:
   - Branch name
   - Task description
   - Merged status (✓ / ✗ / ?)
   - Session status (active / closed)
4. Output as formatted text in conversation
```

### 4. UI Components


#### Worktree Onboarding Dialog

**File:** `flutter_app/lib/widgets/worktree_onboarding_dialog.dart`

Shown on first `/workstart` when worktrees not enabled.

**Contents:**
- Explanation: "Worktrees let you work on multiple branches simultaneously..."
- Main branch dropdown (auto-detected, editable)
- Worktree directory path field (default: `<project>-wt`)
- Auto-select preference checkbox
- Cancel / Enable buttons

#### Workdone Confirmation Dialog

**File:** `flutter_app/lib/widgets/workdone_confirmation_dialog.dart`

**Contents:**
- Warning banner if uncommitted changes
- Warning banner if not merged / uncertain
- Checkbox: "Delete worktree directory"
- Checkbox: "Close this session"
- Cancel / "Mark as Done" buttons

#### Session List Worktree Indicator

**Modify:** `flutter_app/lib/widgets/session_list.dart`

Add branch badge to worktree sessions in `_SessionTile`:
```
[●] Add dark mode    [cci/add-dark-mode]
    2 agents • $0.15
```

---

## File Changes Summary

### New Files (6)

| File | Purpose |
|------|---------|
| `lib/services/project_config_service.dart` | Per-project config persistence |
| `lib/services/git_worktree_service.dart` | Git operations |
| `lib/widgets/worktree_onboarding_dialog.dart` | First-time setup dialog |
| `lib/widgets/workdone_confirmation_dialog.dart` | Completion confirmation |
| `test/services/project_config_service_test.dart` | Unit tests |
| `test/services/git_worktree_service_test.dart` | Unit tests |

### Modified Files (4)

| File | Changes |
|------|---------|
| `lib/models/session.dart` | Add `worktreeBranch` field and getters |
| `lib/providers/session_provider.dart` | Add command handlers, service injection |
| `lib/widgets/session_list.dart` | Add worktree branch indicator |
| `lib/main.dart` | Initialize `ProjectConfigService` |

---

## Implementation Sequence

### Phase 1: Data Layer
1. Create `ProjectConfigService` (follows `RuntimeConfig` pattern)
2. Create `GitWorktreeService` with git operations
3. Unit tests for both services

### Phase 2: Session Model
1. Add `worktreeBranch` to `Session` constructor
2. Add `isWorktreeSession` / `isMainSession` getters
3. Update `createSession` in `SessionProvider` to accept `worktreeBranch`

### Phase 3: Commands
1. Add `/workstart` handler with onboarding flow
2. Add `/workdone` handler with confirmation flow
3. Add `/worktrees` list command

### Phase 4: UI
1. Create `WorktreeOnboardingDialog`
2. Create `WorkdoneConfirmationDialog`
3. Update `session_list.dart` with branch indicator

### Phase 5: Testing & Polish
1. Integration tests for command flows
2. Error handling edge cases
3. User-facing messages refinement

---

## Error Handling

| Error | Detection | Response |
|-------|-----------|----------|
| Git not installed | `Process.run('git')` fails | "Git is not installed or not in PATH" |
| Not a git repo | `git rev-parse` fails | "This directory is not a git repository" |
| Not repo root | toplevel != cwd | "Open the app from the repository root to use worktrees" |
| Worktree exists | `Directory.exists()` | "Worktree directory already exists" |
| Git operation fails | Non-zero exit code | "Git error: {stderr}" |
| Merge check uncertain | Squash merge, rebase | Show warning, let user proceed |

---

## Merge Detection Strategy

Uses multiple git commands for reliability:

```dart
Future<MergeStatus> checkMergeStatus(branch, target) async {
  // Method 1: Check merged branches list
  final merged = await git(['branch', '--merged', target]);
  if (merged.contains(branch)) return MergeStatus.merged;

  // Method 2: Check for unmerged commits
  final log = await git(['log', '$target..$branch', '--oneline']);
  if (log.trim().isEmpty) return MergeStatus.merged;

  // Methods disagree or both show unmerged
  return MergeStatus.notMerged; // or .uncertain if errors
}
```

This catches both regular merges and squash merges.

---

## Verification Plan

1. **Manual Testing:**
   - Create worktree via `/workstart "test task"`
   - Verify branch created with correct name format
   - Verify session uses worktree directory as cwd
   - Make changes, commit, push, merge to main
   - Run `/workdone` and verify merge detection
   - Run `/worktrees` to see status list

2. **Unit Tests:**
   - Branch name generation (special chars, conflicts)
   - Project config serialization/deserialization
   - Git command result parsing

3. **Integration Tests:**
   - Mock git service for deterministic testing
   - Test onboarding flow triggers correctly
   - Test warning dialogs appear for edge cases

---

## Critical Files Reference

- `flutter_app/lib/services/runtime_config.dart` - Pattern for `ProjectConfigService`
- `flutter_app/lib/providers/session_provider.dart:506-570` - `/clear` command pattern for slash commands
- `flutter_app/lib/models/session.dart:64-69` - Session constructor to extend
- `flutter_app/lib/widgets/session_list.dart:273-327` - `_SessionTile` to modify
