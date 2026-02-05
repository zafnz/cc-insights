# Merge/Information Panel Redesign

## Overview

Redesign the Information Panel to be state-driven by two configuration axes:
1. **Base ref** — what branch this worktree compares against (local `main` vs `origin/main` vs custom)
2. **Upstream status** — whether the branch is published (has a remote tracking branch) or not

These two axes produce three distinct panel states (see `docs/mocks/information-panel-mock.html`):

| Base | Upstream | Panel State |
|------|----------|-------------|
| Local (`main`) | Not published | **Local workflow** — rebase/merge onto main, merge branch into main |
| Remote (`origin/main`) | Not published | **Remote-base, unpublished** — rebase/merge onto origin/main, publish (push -u), create PR (disabled until pushed) |
| Remote (`origin/main`) | Published (`origin/branch`) | **Remote-base, published** — rebase/merge onto origin/main, sync (push/pull), create PR |

The current `_workflowMode` toggle (Local/PR) and `_updateSource` dropdown are replaced by this data-driven approach.

---

## Changes Required

### 1. Project Config: Default Base Setting

**Files:** `project_config.dart`, `project_config_service.dart`, `project_settings_panel.dart`

Add a `defaultBase` field to `ProjectConfig`:

```dart
// project_config.dart
class ProjectConfig {
  // ... existing fields ...
  final String? defaultBase; // "main", "origin/main", or a custom ref
  // null means auto-detect (current behaviour)
}
```

JSON key: `"default-base"`.

**Project Settings Panel** — add a new "Git" category to the settings sidebar:

```dart
_SettingsCategory(
  id: 'git',
  label: 'Git',
  icon: Icons.call_split,
  description: 'Default branch comparison settings',
)
```

The Git settings section contains a single setting:
- **Default base for new worktrees** — a selector with options:
  - `auto` (default) — current auto-detect logic: upstream exists → `origin/main`, otherwise → local `main`
  - `main` — always compare against local `main`
  - `origin/main` — always compare against `origin/main`
  - *Custom...* — text field for a custom ref (e.g. `develop`, `origin/develop`)

The value is stored in `.ccinsights/config.json` at the project root.

### 2. Per-Worktree Base Override

**Files:** `worktree.dart`, `persistence_service.dart`, `worktree_watcher_service.dart`

Each worktree needs an optional base override stored in the persistence layer (not in WorktreeData, which is transient git status). Add a `baseOverride` field to `WorktreeInfo` in the persistence models:

```dart
// In persistence_service.dart / WorktreeInfo
class WorktreeInfo {
  // ... existing fields ...
  final String? baseOverride; // null = use project default
}
```

And expose it on `WorktreeState`:

```dart
// worktree.dart
class WorktreeState extends ChangeNotifier {
  String? _baseOverride; // null = use project default

  String? get baseOverride => _baseOverride;

  void setBaseOverride(String? value) {
    if (_baseOverride == value) return;
    _baseOverride = value;
    notifyListeners();
  }
}
```

The "Change..." button in the panel opens a small popup/dialog to select a base ref (same options as project default + "Use project default").

**Watcher integration** — `WorktreeWatcherService._pollGitStatus()` currently auto-detects the base ref. Change it to:

```
1. Check worktree.baseOverride
2. If null, check ProjectConfig.defaultBase
3. If null or "auto", use existing auto-detect logic
4. Otherwise, use the specified ref directly
```

This replaces the current auto-detect at lines 218-239 of `worktree_watcher_service.dart`.

### 3. Periodic `git fetch`

**Files:** `worktree_watcher_service.dart`

All worktrees share the same `.git` directory, so a single `git fetch origin` run against the **primary worktree** updates remote refs for every worktree. There is no need to fetch per-worktree.

Add a project-level fetch timer to `WorktreeWatcherService`, separate from the per-worktree polling:

```dart
// New field on WorktreeWatcherService:
Timer? _fetchTimer;
DateTime? _lastFetchTime;
static const fetchInterval = Duration(minutes: 2);

// Start in constructor (alongside _startGitDirWatcher):
_startPeriodicFetch();

void _startPeriodicFetch() {
  if (!_enablePeriodicPolling) return;
  _fetchTimer = Timer.periodic(fetchInterval, (_) => _fetchOrigin());
}

Future<void> _fetchOrigin() async {
  if (_disposed) return;
  _lastFetchTime = DateTime.now();
  try {
    await _gitService.fetch(_project.data.repoRoot);
  } catch (_) {
    // Network failures are non-fatal
  }
  // After fetch completes, refresh all worktrees so they pick up
  // updated remote refs.
  if (!_disposed) {
    forceRefreshAll();
  }
}
```

Key considerations:
- Runs once every 2 minutes against the **primary worktree path** (`_project.data.repoRoot`)
- After fetch, calls `forceRefreshAll()` so all worktrees re-poll their ahead/behind counts with fresh remote refs
- Network timeout already exists on `fetch()` (30 seconds)
- Fetch failures are silently ignored — status polls continue with stale remote data
- Disposed alongside other timers in `dispose()`
- Disabled when `enablePeriodicPolling` is false (tests)

### 4. `git pull` Operation

**Files:** `git_service.dart`

Add `pull` and `pullRebase` methods to the `GitService` interface and implementation:

```dart
// Interface
Future<MergeResult> pull(String path);
Future<MergeResult> pullRebase(String path);

// Implementation
Future<MergeResult> pull(String path) async {
  // git pull (merge strategy)
  // Returns MergeResult with hasConflicts, operation, error
}

Future<MergeResult> pullRebase(String path) async {
  // git pull --rebase
  // Returns MergeResult with hasConflicts, operation, error
}
```

These return `MergeResult` just like `merge()` and `rebase()`, so the existing conflict resolution flow works unchanged.

### 5. Redesigned Information Panel

**Files:** `information_panel.dart`

Replace the current `_WorktreeInfo` widget with a new state-driven layout. Remove `_workflowMode` and `_updateSource` state entirely — the panel reads its state from:

- `data.baseRef` / `data.isRemoteBase` — determines which actions section to show
- `data.upstreamBranch` — determines upstream display and sync/publish section
- `worktree.baseOverride` — for the "Change..." button

#### Panel Sections (top to bottom)

**A. Working Tree** (always shown)
```
Working tree
Uncommitted / Staged / Commits:  N / N / N
```
- "Stage and commit all" button when there are changes (existing behaviour, keep as-is)

**B. Base** (always shown for non-primary worktrees)
```
Base
{icon} {baseRef}                    [Change...]
   +N  -N
```
- Icon: house for local, globe for remote
- `baseRef` displayed as-is (e.g. "local main", "origin/main")
- +N (green) / -N (orange) from `commitsAheadOfMain` / `commitsBehindMain`
- "Change..." button opens base selector popup

**C. Upstream** (always shown for non-primary worktrees)

When no upstream:
```
Upstream
cloud — (not published)
```

When upstream exists:
```
Upstream
cloud origin/branch-name...
   up-arrow N  down-arrow N
```

**D. Actions section** — determined by base type

**If local base:**
```
--- Local actions ---
[Rebase onto main]  [Merge main into branch]

--- Integrate locally ---
[Merge branch -> main]
```

**If remote base, no upstream (not published):**
```
--- Remote-base actions ---
[Rebase onto origin/main]  [Merge origin/main into branch]

--- Publish ---
[Push to origin/{branch}...]

--- Pull Request ---
[Create PR (push required)]     // disabled
```

**If remote base, has upstream (published):**
```
--- Remote-base actions ---
[Rebase onto origin/main]  [Merge origin/main into branch]

--- Sync ---
[Push]  [Pull / Rebase]

--- Pull Request ---
[Create PR]
```

**E. Conflict section** (shown instead of actions when conflict in progress)

Keep existing `_ConflictInProgress` widget unchanged — it already handles both merge and rebase conflicts with Abort/Continue/Ask Claude buttons.

#### Button Behaviour

| Button | Action | Can Conflict? |
|--------|--------|---------------|
| Rebase onto {base} | `showConflictResolutionDialog` with rebase | Yes |
| Merge {base} into branch | `showConflictResolutionDialog` with merge | Yes |
| Merge branch -> main | `showConflictResolutionDialog` (runs in primary worktree) | Yes |
| Push to origin/{branch} | `gitService.push(path, setUpstream: true)` then refresh | No |
| Push | `gitService.push(path)` then refresh | No |
| Pull / Rebase | `showConflictResolutionDialog` with pull-rebase (new) | Yes |
| Create PR | `showCreatePrDialog` (existing) | No |
| Create PR (push required) | Disabled, tooltip explains | N/A |

**Enable/disable logic:**
- Rebase/Merge onto base: enabled when `commitsBehindMain > 0` and not primary
- Merge branch -> main: enabled when `commitsAheadOfMain > 0` and `commitsBehindMain == 0` and not primary
- Push (initial publish): always enabled for non-primary (it's the first push)
- Push (sync): enabled when `commitsAhead > 0` (ahead of upstream)
- Pull / Rebase: enabled when `commitsBehind > 0` (behind upstream)
- Create PR: enabled when `commitsAheadOfMain > 0` and has upstream and not primary

### 6. Conflict Resolution for Pull

**Files:** `conflict_resolution_dialog.dart`

The existing dialog already handles merge and rebase. For pull operations, we need to extend it slightly:

- Add a `pull` variant to `MergeOperationType` (or handle it as a rebase-from-upstream)
- The dry-run check for pull-rebase: we can use `wouldRebaseConflict(path, upstreamBranch)` since pull --rebase is equivalent to rebase onto the upstream
- The actual operation calls `gitService.pullRebase(path)` instead of `gitService.rebase()`

Alternatively, since `git pull --rebase` is essentially `git fetch` + `git rebase origin/branch`, we could:
1. Fetch first (already done by periodic polling)
2. Use the existing rebase flow against the upstream branch

This second approach is simpler and reuses existing code entirely. The "Pull / Rebase" button would:
1. Call `gitService.fetch(path)` to ensure latest
2. Show `ConflictResolutionDialog` with `operation: rebase` and `targetBranch: upstreamBranch`

This means no new `MergeOperationType` is needed and no changes to the dialog.

---

## Implementation Order

### Phase 1: Settings Infrastructure
1. Add `defaultBase` to `ProjectConfig` model + serialization
2. Add `baseOverride` to `WorktreeInfo` persistence + `WorktreeState`
3. Add "Git" category to Project Settings Panel with base selector
4. Add `PersistenceService` methods to save/load base override per worktree

### Phase 2: Watcher Integration
5. Update `WorktreeWatcherService._pollGitStatus()` to use base override / project default
6. Add `git fetch` to periodic polls when remote-related

### Phase 3: Git Operations
7. Add `pull` / `pullRebase` to `GitService` (or confirm rebase-against-upstream approach)
8. Add base selector popup widget (the "Change..." button UI)

### Phase 4: Panel Redesign
9. Rewrite `_WorktreeInfo.build()` to be state-driven (remove `_workflowMode`, `_updateSource`)
10. Implement the three panel states as described above
11. Wire up new buttons (Publish push, Pull/Rebase, etc.)
12. Ensure conflict flow works for all operations

### Phase 5: Testing
13. Unit tests for `ProjectConfig` with `defaultBase`
14. Unit tests for base resolution logic in watcher
15. Widget tests for the three panel states
16. Widget tests for base selector popup
17. Integration test for full rebase/merge/push flow

---

## Files Modified (Summary)

| File | Change |
|------|--------|
| `models/project_config.dart` | Add `defaultBase` field |
| `services/project_config_service.dart` | Serialize `defaultBase` |
| `panels/project_settings_panel.dart` | Add "Git" settings category |
| `models/worktree.dart` | Add `baseOverride` getter/setter to `WorktreeState` |
| `services/persistence_service.dart` | Add `baseOverride` to `WorktreeInfo`, save/load methods |
| `services/worktree_watcher_service.dart` | Use base override, add periodic fetch |
| `services/git_service.dart` | Add `pull()` / `pullRebase()` (if needed) |
| `panels/information_panel.dart` | Rewrite to state-driven layout |
| `widgets/conflict_resolution_dialog.dart` | Minor: support pull-rebase variant (if separate from rebase) |

---

## Design Decisions

1. **No workflow mode toggle** — the panel state is derived from data, not user selection. If you switch your base from `main` to `origin/main`, the panel automatically shows remote-appropriate actions.

2. **Base stored in project config, not git** — git doesn't have a concept of "comparison base". This is a CC-Insights concept, so it lives in `.ccinsights/config.json`.

3. **Upstream is read-only from git** — we never store upstream info; it's always read from `git rev-parse --abbrev-ref @{upstream}`. This stays in sync with what git knows.

4. **Fetch is opportunistic** — periodic fetch keeps remote info fresh but failures are silent. Users can always force-refresh.

5. **Pull/Rebase uses existing conflict flow** — rather than adding a new operation type, we fetch + rebase against upstream. The existing `ConflictResolutionDialog` handles it unchanged.

6. **Per-worktree override persisted in projects.json** — keeps it with other worktree metadata rather than in `.ccinsights/config.json` or a separate file.
