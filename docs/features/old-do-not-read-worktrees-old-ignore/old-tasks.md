# Git Worktrees Feature - Implementation Tasks

This document breaks down the worktrees feature implementation into discrete, independently implementable tasks. Each task can be completed by a future process with no prior context.

**Related Documents:**
- [Plan](./plan.md) - Full implementation plan
- [Request](./request.md) - Original feature request
- [Instructions](./instructions.md) - Task execution instructions

**Testing Requirements:**
- All UI features and functionality MUST have integration tests
- See `flutter_app/TESTS.md` for testing patterns and mocking infrastructure
- All pre-existing tests must continue to pass

---

## Task 1: Create Data Models for Worktree Configuration

**Description:**
Create the data model classes that represent worktree configuration. These are pure Dart classes with JSON serialization, no Flutter dependencies.

Create file `flutter_app/lib/services/project_config_service.dart` with:

1. `WorktreeInfo` class:
   - `sessionId: String` - ID of the associated session
   - `merged: bool` - Whether the worktree branch has been merged
   - `createdAt: DateTime` - When the worktree was created
   - `taskDescription: String` - The original task description
   - `toJson()` and `fromJson()` methods

2. `ProjectWorktreeConfig` class:
   - `mainBranch: String` - The main branch name (e.g., "main" or "master")
   - `worktreeEnabled: bool` - Whether worktrees are enabled for this project
   - `worktreePath: String` - Base directory where worktrees are created
   - `autoSelectWorktree: bool` - User preference for auto-selecting new worktree sessions
   - `worktrees: Map<String, WorktreeInfo>` - Map of branch name to worktree info
   - `toJson()` and `fromJson()` methods

**Files to Create:**
- `flutter_app/lib/services/project_config_service.dart` (data classes only, service class in Task 2)

**Reference Files:**
- `flutter_app/lib/services/runtime_config.dart` - For serialization patterns

**Tests Required:**
- `test/services/project_config_models_test.dart`:
  - Test `WorktreeInfo.toJson()` produces correct JSON structure
  - Test `WorktreeInfo.fromJson()` parses JSON correctly
  - Test `WorktreeInfo` handles DateTime serialization (ISO 8601 format)
  - Test `ProjectWorktreeConfig.toJson()` produces correct JSON structure
  - Test `ProjectWorktreeConfig.fromJson()` parses JSON correctly
  - Test `ProjectWorktreeConfig.fromJson()` handles empty worktrees map
  - Test round-trip: `fromJson(toJson())` preserves all data

**Acceptance Criteria:**
- Data classes compile without errors
- All JSON serialization tests pass
- Classes use immutable fields where appropriate
- DateTime is serialized as ISO 8601 string

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 2: Create ProjectConfigService for Persistence

**Description:**
Create the `ProjectConfigService` class that manages loading/saving project configurations to `~/.ccinsights/projects.json`. Follow the `RuntimeConfig` pattern with singleton initialization and debounced saves.

Add to `flutter_app/lib/services/project_config_service.dart`:

1. `ProjectConfigService` class extending `ChangeNotifier`:
   - `static Future<ProjectConfigService> initialize()` - Load config from file
   - `static ProjectConfigService get instance` - Singleton accessor
   - `static void resetInstance()` - For testing
   - `ProjectWorktreeConfig? getProject(String projectPath)` - Get config for a path
   - `Future<void> enableWorktrees({projectPath, mainBranch, worktreePath})` - Enable for project
   - `Future<void> addWorktree({projectPath, branchName, sessionId, taskDescription})` - Add worktree
   - `Future<void> updateWorktreeSessionId({projectPath, branchName, sessionId})` - Update session ID
   - `Future<void> markWorktreeMerged({projectPath, branchName})` - Mark as merged
   - `Future<void> removeWorktree({projectPath, branchName})` - Remove from config
   - `void setAutoSelectWorktree(String projectPath, bool value)` - Set preference
   - Private `_loadFromFile()` and `_saveToFile()` methods with debouncing

2. Config file location: `~/.ccinsights/projects.json`
   - Support `CCINSIGHTS_CONFIG_DIR` env var override for testing
   - Create directory if it doesn't exist

**Files to Modify:**
- `flutter_app/lib/services/project_config_service.dart` (add service class)

**Reference Files:**
- `flutter_app/lib/services/runtime_config.dart` - Lines 128-165 for singleton pattern, lines 356-434 for file I/O with debouncing

**Tests Required:**
- `test/services/project_config_service_test.dart`:
  - Test `initialize()` creates instance and loads from file
  - Test `initialize()` with non-existent file uses empty config
  - Test `getProject()` returns null for unknown project
  - Test `enableWorktrees()` creates project entry and saves
  - Test `addWorktree()` adds worktree to existing project
  - Test `addWorktree()` on non-enabled project throws or auto-enables
  - Test `markWorktreeMerged()` updates merged flag
  - Test `removeWorktree()` removes worktree entry
  - Test debounced saves (multiple rapid changes result in one file write)
  - Test file round-trip: save then reload preserves all data
  - Use temp directory for file I/O tests

**Acceptance Criteria:**
- Service initializes without errors
- Config persists across service restarts (file-based)
- Debouncing prevents excessive file writes
- All unit tests pass
- `notifyListeners()` called on state changes

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 3: Create GitWorktreeService - Git Detection Methods

**Description:**
Create the `GitWorktreeService` class with methods for detecting git repositories and their properties. This task covers read-only git operations.

Create file `flutter_app/lib/services/git_worktree_service.dart`:

1. Data classes:
   - `GitRepoInfo` - `root: String`, `currentBranch: String`, `mainBranch: String`
   - `GitAvailability` enum - `available`, `notInstalled`, `notInPath`

2. `GitWorktreeService` class:
   - `Future<GitAvailability> checkGitAvailable()` - Check if git is installed
   - `Future<GitRepoInfo?> getRepoInfo(String directory)` - Get repo info or null if not a repo
   - `Future<bool> isRepoRoot(String directory)` - Check if directory is repo root
   - `Future<String?> detectMainBranch(String repoPath)` - Detect main/master branch
   - Private `_runGit(List<String> args, {String? workingDirectory})` helper

3. Git commands used:
   - `git --version` - Check availability
   - `git rev-parse --show-toplevel` - Get repo root
   - `git symbolic-ref --short HEAD` - Get current branch
   - `git remote show origin` or `git symbolic-ref refs/remotes/origin/HEAD` - Detect main branch

**Files to Create:**
- `flutter_app/lib/services/git_worktree_service.dart`

**Tests Required:**
- `test/services/git_worktree_service_test.dart`:
  - Test `checkGitAvailable()` returns `available` when git is installed
  - Test `getRepoInfo()` returns info for valid git repo
  - Test `getRepoInfo()` returns null for non-repo directory
  - Test `isRepoRoot()` returns true for repo root, false for subdirectory
  - Test `detectMainBranch()` finds "main" or "master"
  - Test error handling when git commands fail
  - **IMPORTANT:** Use `TestGitRepo` helper (see `flutter_app/TESTS.md` "Testing Real Git Operations" section) to test against real git commands, not mocks

**Acceptance Criteria:**
- Can detect if a directory is a git repository
- Can determine the main branch name
- Returns null/error gracefully for non-repos
- All unit tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 4: Create GitWorktreeService - Branch Name Generation

**Description:**
Add the branch name generation method to `GitWorktreeService`. This is a pure function that converts task descriptions to valid git branch names.

Add to `flutter_app/lib/services/git_worktree_service.dart`:

1. `String generateBranchName(String task, {List<String> existingBranches = const []})`:
   - Algorithm:
     1. Lowercase the task
     2. Replace non-alphanumeric characters with hyphens
     3. Collapse multiple consecutive hyphens to single hyphen
     4. Remove leading/trailing hyphens
     5. Trim to max 50 characters (at word boundary if possible)
     6. Prepend `cci/`
     7. If result exists in `existingBranches`, append `-1`, `-2`, etc.
   - Examples:
     - "Add dark mode" → "cci/add-dark-mode"
     - "Fix bug #123 (critical!)" → "cci/fix-bug-123-critical"
     - "Add dark mode" with existing "cci/add-dark-mode" → "cci/add-dark-mode-1"

**Files to Modify:**
- `flutter_app/lib/services/git_worktree_service.dart`

**Tests Required:**
- Add to `test/services/git_worktree_service_test.dart`:
  - Test basic conversion: "Add feature" → "cci/add-feature"
  - Test special characters removed: "Fix bug #123!" → "cci/fix-bug-123"
  - Test multiple spaces/hyphens collapsed: "Add   new--feature" → "cci/add-new-feature"
  - Test long task truncated at 50 chars
  - Test conflict resolution: append -1, -2, -3
  - Test conflict with existing -1: jumps to -2
  - Test empty task returns reasonable default
  - Test task with only special chars

**Acceptance Criteria:**
- Branch names are valid git branch names
- Prefix is always `cci/`
- Conflicts are resolved with numeric suffixes
- Long names are truncated sensibly
- All unit tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 5: Create GitWorktreeService - Worktree Operations

**Description:**
Add methods for creating and removing git worktrees. These are the write operations.

Add to `flutter_app/lib/services/git_worktree_service.dart`:

1. Data classes:
   - `WorktreeCreateResult` - `success: bool`, `error: String?`, `worktreePath: String?`
   - `WorktreeEntry` - `path: String`, `branch: String`, `commit: String`

2. Methods:
   - `Future<WorktreeCreateResult> createWorktree({repoPath, worktreePath, branchName, baseBranch})`:
     - Run `git fetch origin` first
     - Run `git worktree add -b <branchName> <worktreePath> origin/<baseBranch>`
     - Return success/failure with error message
   - `Future<void> removeWorktree({repoPath, worktreePath})`:
     - Run `git worktree remove <worktreePath>`
   - `Future<List<WorktreeEntry>> listWorktrees(String repoPath)`:
     - Run `git worktree list --porcelain`
     - Parse output into list of WorktreeEntry

**Files to Modify:**
- `flutter_app/lib/services/git_worktree_service.dart`

**Tests Required:**
- Add to `test/services/git_worktree_service_test.dart`:
  - Test `createWorktree()` creates worktree and branch
  - Test `createWorktree()` returns error when branch already exists
  - Test `createWorktree()` returns error when path already exists
  - Test `removeWorktree()` removes worktree directory
  - Test `listWorktrees()` returns list of worktrees
  - Test `listWorktrees()` on repo with no worktrees returns empty list
  - **IMPORTANT:** Use `TestGitRepo` helper (see `flutter_app/TESTS.md` "Testing Real Git Operations" section) to test against real git commands in isolated temp repos

**Acceptance Criteria:**
- Can create a new worktree with a new branch
- Can remove an existing worktree
- Can list all worktrees
- Error cases return meaningful error messages
- All unit tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 6: Create GitWorktreeService - Status Checking Methods

**Description:**
Add methods for checking worktree status: uncommitted changes and merge status.

Add to `flutter_app/lib/services/git_worktree_service.dart`:

1. Data classes:
   - `MergeStatus` enum - `merged`, `notMerged`, `uncertain`

2. Methods:
   - `Future<bool> hasUncommittedChanges(String worktreePath)`:
     - Run `git status --porcelain` in worktree directory
     - Return true if output is non-empty
   - `Future<MergeStatus> checkMergeStatus({repoPath, branch, targetBranch})`:
     - Method 1: `git branch --merged <targetBranch>` - check if branch in list
     - Method 2: `git log <targetBranch>..<branch> --oneline` - check if empty (catches squash merges)
     - Return `merged` if either method confirms merge
     - Return `notMerged` if both methods confirm not merged
     - Return `uncertain` if methods disagree or errors occur

**Files to Modify:**
- `flutter_app/lib/services/git_worktree_service.dart`

**Tests Required:**
- Add to `test/services/git_worktree_service_test.dart`:
  - Test `hasUncommittedChanges()` returns false for clean worktree
  - Test `hasUncommittedChanges()` returns true with modified files
  - Test `hasUncommittedChanges()` returns true with untracked files
  - Test `checkMergeStatus()` returns `merged` for merged branch
  - Test `checkMergeStatus()` returns `notMerged` for unmerged branch
  - Test `checkMergeStatus()` handles squash merge detection
  - **IMPORTANT:** Use `TestGitRepo` helper (see `flutter_app/TESTS.md` "Testing Real Git Operations" section) to test with real git repos and commit histories

**Acceptance Criteria:**
- Can detect uncommitted changes in a worktree
- Can detect if a branch has been merged
- Handles both regular merges and squash merges
- Returns `uncertain` when detection is unreliable
- All unit tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 7: Extend Session Model with Worktree Fields

**Description:**
Add worktree-related fields to the `Session` model class to track which sessions are associated with worktrees.

Modify `flutter_app/lib/models/session.dart`:

1. Add to `Session` class constructor:
   - `this.worktreeBranch` - Optional parameter

2. Add fields:
   - `final String? worktreeBranch` - Branch name if this is a worktree session (e.g., "cci/add-feature")

3. Add getters:
   - `bool get isWorktreeSession => worktreeBranch != null`
   - `bool get isMainSession => worktreeBranch == null`

**Files to Modify:**
- `flutter_app/lib/models/session.dart` - Add field and getters to Session class

**Reference Files:**
- `flutter_app/lib/models/session.dart:64-69` - Current Session constructor

**Tests Required:**
- Create or add to `test/models/session_test.dart`:
  - Test Session without worktreeBranch has `isWorktreeSession == false`
  - Test Session without worktreeBranch has `isMainSession == true`
  - Test Session with worktreeBranch has `isWorktreeSession == true`
  - Test Session with worktreeBranch has `isMainSession == false`
  - Test worktreeBranch value is preserved

**Acceptance Criteria:**
- Session can be created with or without worktreeBranch
- Getters correctly identify worktree vs main sessions
- Existing code continues to work (backward compatible)
- All tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 8: Update SessionProvider.createSession for Worktrees

**Description:**
Modify `SessionProvider.createSession()` to accept an optional `worktreeBranch` parameter and pass it to the Session constructor.

Modify `flutter_app/lib/providers/session_provider.dart`:

1. Update `createSession()` signature:
   ```dart
   Future<void> createSession({
     required String prompt,
     required String cwd,
     String? model,
     String permissionMode = 'acceptEdits',
     String? worktreeBranch,  // Add this parameter
   })
   ```

2. Pass `worktreeBranch` to Session constructor (around line 64-70)

3. Add service dependencies (to be injected later):
   - Add `GitWorktreeService? _gitService` field
   - Add `ProjectConfigService? _projectConfigService` field
   - Add setters or constructor parameters for dependency injection

**Files to Modify:**
- `flutter_app/lib/providers/session_provider.dart`

**Reference Files:**
- `flutter_app/lib/providers/session_provider.dart:39-84` - Current createSession method

**Tests Required:**
- Add to existing provider tests or create `test/providers/session_provider_worktree_test.dart`:
  - Test createSession without worktreeBranch creates normal session
  - Test createSession with worktreeBranch creates worktree session
  - Test created session has correct worktreeBranch value

**Acceptance Criteria:**
- createSession accepts optional worktreeBranch parameter
- Sessions created with worktreeBranch have correct field values
- Existing calls to createSession continue to work
- All tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 9: Create WorktreeOnboardingDialog Widget

**Description:**
Create a dialog widget shown when users first use `/workstart` and worktrees are not yet enabled for the project. The dialog explains worktrees and collects configuration.

Create `flutter_app/lib/widgets/worktree_onboarding_dialog.dart`:

1. `WorktreeOnboardingDialog` StatefulWidget:
   - Props:
     - `projectPath: String` - The current project path
     - `detectedMainBranch: String` - Auto-detected main branch
     - `onEnable: void Function(String mainBranch, String worktreePath, bool autoSelect)` - Called when user enables
     - `onCancel: VoidCallback` - Called when user cancels

2. Dialog contents:
   - Title: "Enable Git Worktrees?"
   - Explanation text: "Worktrees let you work on multiple branches simultaneously in separate directories. Each task gets its own worktree and session."
   - Main branch field: TextField pre-filled with detected branch, editable
   - Worktree directory field: TextField with default `<projectPath>-wt`
   - Auto-select checkbox: "Automatically switch to new worktree sessions"
   - Buttons: "Cancel" (secondary), "Enable Worktrees" (primary)

3. Show using `showDialog()` pattern from existing code

**Files to Create:**
- `flutter_app/lib/widgets/worktree_onboarding_dialog.dart`

**Reference Files:**
- `flutter_app/lib/screens/settings_screen.dart:176-205` - Dialog pattern with RadioListTile
- `flutter_app/lib/widgets/session_list.dart:70-270` - `_NewSessionDialog` pattern

**Tests Required:**

*Unit Tests* - `test/widget/worktree_onboarding_dialog_test.dart`:
  - Test dialog displays all fields
  - Test main branch field is pre-filled with detected value
  - Test worktree path has sensible default
  - Test Cancel button calls onCancel
  - Test Enable button calls onEnable with correct values
  - Test Enable button disabled if required fields empty
  - Test checkbox state is passed correctly

*Integration Tests* - `test/integration/worktree_onboarding_dialog_test.dart`:
  - Test dialog renders within app context with mock services
  - Test dialog interaction flow (fill fields, click enable)
  - Test dialog dismissal on cancel
  - Test keyboard navigation and accessibility
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Dialog renders correctly
- Fields have sensible defaults
- Validation prevents enabling with empty fields
- Callbacks receive correct values
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 10: Create WorkdoneConfirmationDialog Widget

**Description:**
Create a dialog widget shown when users run `/workdone`. It displays warnings and options before completing a worktree.

Create `flutter_app/lib/widgets/workdone_confirmation_dialog.dart`:

1. `WorkdoneConfirmationDialog` StatefulWidget:
   - Props:
     - `branchName: String` - The worktree branch name
     - `hasUncommittedChanges: bool` - Whether there are uncommitted changes
     - `mergeStatus: MergeStatus` - merged/notMerged/uncertain
     - `onConfirm: void Function(bool deleteDirectory, bool closeSession)` - Called on confirm
     - `onCancel: VoidCallback` - Called when user cancels

2. Dialog contents:
   - Title: "Complete Worktree?"
   - Warning banner (if uncommitted changes): Yellow/orange banner with icon, "You have uncommitted changes in this worktree."
   - Warning banner (if not merged): Yellow/orange banner with icon, "This branch has not been merged to main." (or "Could not confirm if branch was merged." for uncertain)
   - Checkbox: "Delete worktree directory"
   - Checkbox: "Close this session"
   - Buttons: "Cancel" (secondary), "Mark as Done" (primary, maybe "Mark as Done Anyway" if warnings)

**Files to Create:**
- `flutter_app/lib/widgets/workdone_confirmation_dialog.dart`

**Reference Files:**
- `flutter_app/lib/widgets/permission_widgets.dart` - Warning banner patterns
- `flutter_app/lib/screens/home_screen.dart:490-510` - Danger warning box pattern

**Tests Required:**

*Unit Tests* - `test/widget/workdone_confirmation_dialog_test.dart`:
  - Test dialog displays without warnings when no issues
  - Test uncommitted changes warning appears when hasUncommittedChanges=true
  - Test merge warning appears when mergeStatus=notMerged
  - Test uncertain merge warning appears when mergeStatus=uncertain
  - Test no merge warning when mergeStatus=merged
  - Test checkbox states are passed to onConfirm
  - Test Cancel button calls onCancel
  - Test Confirm button calls onConfirm with checkbox values

*Integration Tests* - `test/integration/workdone_confirmation_dialog_test.dart`:
  - Test dialog renders within app context with mock services
  - Test warning banners display correctly with different status combinations
  - Test checkbox interaction and state persistence
  - Test dialog dismissal flows (confirm and cancel)
  - Test button text changes based on warning state ("Mark as Done" vs "Mark as Done Anyway")
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Dialog renders correctly
- Warnings display appropriately based on status
- Checkboxes work correctly
- Callbacks receive correct values
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 11: Implement /workstart Command Handler

**Description:**
Implement the `/workstart <task>` slash command handler in SessionProvider. This is the main command for creating new worktrees.

Modify `flutter_app/lib/providers/session_provider.dart`:

1. Add command detection in `sendInput()` method (after existing `/clear` check around line 507):
   ```dart
   if (text.trim().startsWith('/workstart ')) {
     await _handleWorkstartCommand(session, text);
     return;
   }
   ```

2. Implement `_handleWorkstartCommand(Session session, String text)`:
   - Parse task from command: `text.trim().substring('/workstart '.length).trim()`
   - If task is empty, show error message and return
   - Get repo info via `_gitService.getRepoInfo(session.cwd)`
   - If not a git repo, show error and return
   - Get project config via `_projectConfigService.getProject(session.cwd)`
   - If worktrees not enabled:
     - Set `_pendingWorktreeSetup = (session, task)`
     - Notify listeners to trigger onboarding dialog
     - Return (dialog will call back to continue)
   - Generate branch name via `_gitService.generateBranchName()`
   - Create worktree via `_gitService.createWorktree()`
   - If failed, show error and return
   - Save to config via `_projectConfigService.addWorktree()`
   - Create new session with worktree cwd and worktreeBranch
   - Auto-select if configured
   - Show success message in original session

3. Add state for pending onboarding:
   - `(Session, String)? _pendingWorktreeSetup` - Session and task waiting for onboarding
   - `void completeWorktreeSetup(String mainBranch, String worktreePath, bool autoSelect)` - Called after onboarding dialog

**Files to Modify:**
- `flutter_app/lib/providers/session_provider.dart`

**Reference Files:**
- `flutter_app/lib/providers/session_provider.dart:506-570` - `/clear` command pattern

**Tests Required:**

*Unit Tests* - `test/providers/workstart_command_test.dart` (with mock services):
  - Test empty task shows error message
  - Test non-git-repo shows error message
  - Test triggers onboarding when worktrees not enabled
  - Test creates worktree when enabled
  - Test creates new session with correct cwd
  - Test new session has worktreeBranch set
  - Test auto-selects session when configured
  - Test shows success message in original session
  - Test handles git errors gracefully

*Integration Tests* - `test/integration/workstart_command_test.dart`:
  - Test full /workstart flow with mock backend and git services
  - Test typing "/workstart Add feature" in message input triggers command
  - Test error messages appear in conversation output
  - Test success messages appear in conversation output
  - Test session list updates with new worktree session
  - Test onboarding dialog appears and can be completed
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Command is recognized and parsed correctly
- Onboarding is triggered for first-time use
- Worktree is created with correct branch name
- New session is created and optionally selected
- Error messages are user-friendly
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 12: Implement /workdone Command Handler

**Description:**
Implement the `/workdone` slash command handler in SessionProvider. This command marks a worktree as complete.

Modify `flutter_app/lib/providers/session_provider.dart`:

1. Add command detection in `sendInput()`:
   ```dart
   if (text.trim() == '/workdone') {
     await _handleWorkdoneCommand(session);
     return;
   }
   ```

2. Implement `_handleWorkdoneCommand(Session session)`:
   - Validate this is a worktree session, else show error
   - Get repo root from session.cwd (may need to traverse up)
   - Check uncommitted changes via `_gitService.hasUncommittedChanges()`
   - Check merge status via `_gitService.checkMergeStatus()`
   - Set `_pendingWorkdoneConfirmation` with session and status info
   - Notify listeners to trigger confirmation dialog

3. Add state and confirmation handler:
   - `WorkdoneConfirmation? _pendingWorkdoneConfirmation` class with session, hasUncommittedChanges, mergeStatus
   - `void confirmWorkdone(bool deleteDirectory, bool closeSession)` - Called after dialog confirm
   - In confirm handler:
     - Mark worktree merged in config
     - Optionally delete worktree via `_gitService.removeWorktree()`
     - Optionally close/archive session
     - Show completion message

**Files to Modify:**
- `flutter_app/lib/providers/session_provider.dart`

**Tests Required:**

*Unit Tests* - `test/providers/workdone_command_test.dart` (with mock services):
  - Test error when not in worktree session
  - Test checks uncommitted changes
  - Test checks merge status
  - Test triggers confirmation dialog with correct state
  - Test confirm marks worktree as merged
  - Test confirm with deleteDirectory removes worktree
  - Test confirm with closeSession closes session
  - Test handles errors gracefully

*Integration Tests* - `test/integration/workdone_command_test.dart`:
  - Test full /workdone flow with mock backend and git services
  - Test typing "/workdone" in worktree session triggers command
  - Test error message appears when run in non-worktree session
  - Test confirmation dialog appears with correct warnings
  - Test completing confirmation updates session and config
  - Test session closes when "Close this session" is checked
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Command only works in worktree sessions
- Status checks are performed before confirmation
- Confirmation dialog receives correct status
- Confirm action updates config and optionally cleans up
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 13: Implement /worktrees Command Handler

**Description:**
Implement the `/worktrees` slash command handler that lists all worktrees for the current project.

Modify `flutter_app/lib/providers/session_provider.dart`:

1. Add command detection in `sendInput()`:
   ```dart
   if (text.trim() == '/worktrees') {
     await _handleWorktreesCommand(session);
     return;
   }
   ```

2. Implement `_handleWorktreesCommand(Session session)`:
   - Add command to output: `session.addOutput('main', UserInputEntry('/worktrees'))`
   - Get project config via `_projectConfigService.getProject()`
   - If not enabled, show message: "Worktrees not enabled. Use `/workstart <task>` to create your first worktree."
   - If no worktrees, show: "No worktrees. Use `/workstart <task>` to create one."
   - Build formatted list of worktrees:
     ```
     **Worktrees for /path/to/project:**

     • `cci/add-dark-mode` - Add dark mode toggle
       Status: ✓ Merged | Session: Active

     • `cci/fix-login-bug` - Fix login bug
       Status: ✗ Not merged | Session: Closed
     ```
   - Add output as `TextOutputEntry` with contentType 'system'

**Files to Modify:**
- `flutter_app/lib/providers/session_provider.dart`

**Tests Required:**

*Unit Tests* - `test/providers/worktrees_command_test.dart`:
  - Test shows enable message when worktrees not enabled
  - Test shows empty message when no worktrees
  - Test lists worktrees with correct format
  - Test shows merged status correctly
  - Test shows session status (active/closed)
  - Test handles multiple worktrees

*Integration Tests* - `test/integration/worktrees_command_test.dart`:
  - Test full /worktrees flow with mock backend and config services
  - Test typing "/worktrees" displays output in conversation
  - Test output formatting renders correctly as markdown
  - Test clicking on branch names (if interactive)
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Command shows helpful message if worktrees not enabled
- Lists all worktrees with branch, task, and status
- Output is well-formatted markdown
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 14: Add Worktree Branch Indicator to Session List

**Description:**
Modify the session list sidebar to show a branch badge for worktree sessions.

Modify `flutter_app/lib/widgets/session_list.dart`:

1. In `_SessionTile` widget (around line 273-327):
   - Check if `session.isWorktreeSession`
   - If true, add a branch badge after the title or in the subtitle
   - Badge style: Small container with rounded corners, subtle background color
   - Badge content: Branch name (e.g., "cci/add-feature")
   - Consider truncating long branch names with ellipsis

2. Visual design:
   ```
   [●] Add dark mode toggle
       cci/add-dark-mode • 2 agents • $0.15
   ```
   Or:
   ```
   [●] Add dark mode toggle  [cci/add-dark-mode]
       2 agents • $0.15
   ```

**Files to Modify:**
- `flutter_app/lib/widgets/session_list.dart`

**Reference Files:**
- `flutter_app/lib/widgets/session_list.dart:273-327` - Current `_SessionTile` implementation

**Tests Required:**

*Unit Tests* - `test/widget/session_list_worktree_test.dart`:
  - Test regular session does not show branch badge
  - Test worktree session shows branch badge
  - Test branch badge displays correct branch name
  - Test long branch names are truncated
  - Test badge styling is visible

*Integration Tests* - `test/integration/session_list_worktree_test.dart`:
  - Test session list renders with mix of worktree and regular sessions
  - Test worktree badge is visually distinct and readable
  - Test selecting worktree session works correctly
  - Test session list updates when new worktree session is created
  - Test badge tooltip shows full branch name (if truncated)
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Worktree sessions are visually distinguishable
- Branch name is displayed
- Long names don't break layout
- Non-worktree sessions unchanged
- All unit tests pass
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 15: Wire Up Onboarding Dialog in Home Screen

**Description:**
Connect the WorktreeOnboardingDialog to the SessionProvider so it appears when needed during `/workstart`.

Modify `flutter_app/lib/screens/home_screen.dart` (or create a wrapper widget):

1. Listen to SessionProvider for `pendingWorktreeSetup` state
2. When set, show `WorktreeOnboardingDialog` via `showDialog()`
3. On dialog Enable:
   - Call `sessionProvider.completeWorktreeSetup(mainBranch, worktreePath, autoSelect)`
4. On dialog Cancel:
   - Call `sessionProvider.cancelWorktreeSetup()` or clear the pending state

Alternative approach: Create a `WorktreeDialogManager` widget that wraps the home screen and handles dialog display.

**Files to Modify:**
- `flutter_app/lib/screens/home_screen.dart` or new manager widget

**Tests Required:**

*Integration Tests* - `test/integration/worktree_onboarding_flow_test.dart`:
  - Test dialog appears when /workstart triggers onboarding (first time)
  - Test completing dialog creates worktree and session
  - Test canceling dialog does not create worktree
  - Test dialog uses detected main branch from git service
  - Test dialog does not appear on subsequent /workstart (already enabled)
  - Test config is persisted after onboarding completes
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Dialog appears at the right time
- User can complete or cancel onboarding
- Flow continues correctly after dialog
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 16: Wire Up Workdone Confirmation Dialog

**Description:**
Connect the WorkdoneConfirmationDialog to the SessionProvider so it appears when needed during `/workdone`.

Modify `flutter_app/lib/screens/home_screen.dart` (or the wrapper widget from Task 15):

1. Listen to SessionProvider for `pendingWorkdoneConfirmation` state
2. When set, show `WorkdoneConfirmationDialog` via `showDialog()`
3. On dialog Confirm:
   - Call `sessionProvider.confirmWorkdone(deleteDirectory, closeSession)`
4. On dialog Cancel:
   - Call `sessionProvider.cancelWorkdone()` or clear the pending state

**Files to Modify:**
- `flutter_app/lib/screens/home_screen.dart` or manager widget

**Tests Required:**

*Integration Tests* - `test/integration/workdone_flow_test.dart`:
  - Test dialog appears when /workdone is run in worktree session
  - Test dialog shows uncommitted changes warning when appropriate
  - Test dialog shows merge status warning when appropriate
  - Test confirm with "Delete directory" checked removes worktree
  - Test confirm with "Close session" checked closes the session
  - Test cancel does not modify worktree or session
  - Test config is updated after successful completion
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- Dialog appears at the right time
- Warnings are displayed correctly
- Confirm/cancel work as expected
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 17: Initialize Services in main.dart

**Description:**
Initialize the new services at app startup and provide them to the widget tree.

Modify `flutter_app/lib/main.dart`:

1. In `main()` function (around line 22-76):
   - Add `await ProjectConfigService.initialize()` after RuntimeConfig
   - Create `GitWorktreeService` instance

2. Inject services into SessionProvider:
   - Either via constructor or setter methods
   - Update Provider setup to include services

3. Add to Provider tree if needed for widget access

**Files to Modify:**
- `flutter_app/lib/main.dart`
- Possibly `flutter_app/lib/providers/session_provider.dart` for constructor changes

**Reference Files:**
- `flutter_app/lib/main.dart:22-76` - Current initialization flow
- `flutter_app/lib/services/runtime_config.dart:128-135` - RuntimeConfig.initialize() pattern

**Tests Required:**

*Integration Tests* - `test/integration/service_initialization_test.dart`:
  - Test app starts without errors with all services initialized
  - Test ProjectConfigService.instance is accessible after startup
  - Test GitWorktreeService is injected into SessionProvider
  - Test services are available in widget tree via Provider
  - Test app startup with missing config file (should create default)
  - Test app startup with corrupted config file (should handle gracefully)
  - Use mock infrastructure from `flutter_app/TESTS.md`

**Acceptance Criteria:**
- App starts successfully
- ProjectConfigService is initialized and accessible
- GitWorktreeService is created and injected
- No regression in existing functionality
- All integration tests pass

- [x] Written
- [x] Tested
- [x] Accepted

---

## Task 18: Widget Integration Test (Mock Backend + Real Git)

**Description:**
Create a comprehensive widget integration test that exercises the full worktree workflow using real git operations but a mock backend. This test runs fast with `flutter test`.

Create `test/integration/worktree_full_flow_test.dart`:

Test scenario:
1. Create a `TestGitRepo` for isolated real git operations
2. Start app with mock backend but real `GitWorktreeService` pointing to the test repo
3. Create initial session in the test git repo
4. Run `/workstart "Add new feature"`
5. Verify onboarding dialog appears (first time)
6. Complete onboarding with test values
7. Verify worktree is actually created (check filesystem)
8. Verify new session is created with correct cwd
9. Run `/worktrees` and verify listing
10. Run `/workdone` in worktree session
11. Verify confirmation dialog appears
12. Confirm completion
13. Verify worktree is marked as merged in config

**Files to Create:**
- `test/integration/worktree_full_flow_test.dart`

**Dependencies:**
- `TestGitRepo` helper (see `flutter_app/TESTS.md` "Testing Real Git Operations" section)
- Mock backend infrastructure (for UI/session simulation)
- Real `GitWorktreeService` (no mocking git operations)
- All previous tasks completed

**Tests Required:**
- Full happy path test as described above using `TestGitRepo`
- Test with git errors (e.g., create branch that already exists)
- Test cancel flows
- **IMPORTANT:** Use `TestGitRepo` helper for real git operations. Only mock the backend/SDK interactions, not git.

**Acceptance Criteria:**
- Full workflow executes without errors
- Real git worktrees are created and can be verified on disk
- All state transitions are correct
- UI updates appropriately at each step
- Test passes consistently
- Temp directories cleaned up after test

- [ ] Written
- [ ] Tested
- [ ] Accepted

---

## Task 19: Real E2E Integration Test (Real App + External Mock Backend + Real Git)

**Description:**
Create a true end-to-end integration test that launches the actual macOS app with the external mock backend and tests the worktree workflow. This test runs with `flutter test integration_test/` and uses the external mock backend (see `docs/features/real-mock-backend-plan.md`) for deterministic, API-credit-free testing.

Create `integration_test/worktree_test.dart`:

Test scenario:
1. Create a `TestGitRepo` for isolated real git operations
2. Launch the real app with `CLAUDE_MOCK_BACKEND` pointing to the mock backend
3. Set `MOCK_SCENARIO=worktree-test` for predictable responses
4. Wait for app and backend to initialize
5. Create a new session in the test git repo
6. Type `/workstart "E2E test feature"` and submit
7. Verify onboarding dialog appears, complete it
8. Verify worktree directory exists on filesystem
9. Verify new session appears in session list with branch badge
10. Type `/worktrees` and verify output shows the worktree
11. Type `/workdone` and verify confirmation dialog
12. Complete the workflow

**Files to Create:**
- `integration_test/worktree_test.dart`
- `mock-backend/src/scenarios/worktree-test.ts` (or add to existing scenarios)

**Dependencies:**
- `TestGitRepo` helper
- External mock backend (see `docs/features/real-mock-backend-plan.md`)
  - Must be built: `cd mock-backend && npm install && npm run build`
- All previous tasks completed
- Task 18 passing

**Tests Required:**
- Full happy path with real app launch + mock backend
- Verify services initialize correctly at startup
- Test that worktree sessions persist across app interactions
- Test error scenarios using mock backend error injection

**Acceptance Criteria:**
- Test launches real macOS app successfully
- External mock backend provides predictable responses
- Real git worktrees are created and verified on disk
- UI interactions work as expected
- Test cleans up temp directories
- Test passes consistently (no API flakiness)
- No Claude API credits consumed

**Running the Test:**
```bash
# Build mock backend first
cd mock-backend && npm install && npm run build

# Run E2E tests with mock backend
cd flutter_app
CLAUDE_MOCK_BACKEND=../mock-backend/dist/index.js \
MOCK_SCENARIO=worktree-test \
flutter test integration_test/worktree_test.dart

# Optional: Run with real backend for production verification
# (requires API credits, use sparingly)
flutter test integration_test/worktree_test.dart
```

**Notes:**
- Default: Uses external mock backend (fast, deterministic, no API credits)
- Optional: Can run with real backend by omitting `CLAUDE_MOCK_BACKEND` env var
- See `docs/features/real-mock-backend-plan.md` for mock backend details
- See `integration_test/README.md` for general E2E test instructions

- [ ] Written
- [ ] Tested
- [ ] Accepted

---

## Summary

| Task | Component | Dependencies | Tests Required |
|------|-----------|--------------|----------------|
| 1 | Data models | None | Unit |
| 2 | ProjectConfigService | Task 1 | Unit |
| 3 | GitWorktreeService (detection) | None | Unit |
| 4 | GitWorktreeService (branch names) | Task 3 | Unit |
| 5 | GitWorktreeService (worktree ops) | Task 3 | Unit |
| 6 | GitWorktreeService (status) | Task 3 | Unit |
| 7 | Session model extension | None | Unit |
| 8 | SessionProvider.createSession | Task 7 | Unit |
| 9 | WorktreeOnboardingDialog | None | Unit + Widget Integration |
| 10 | WorkdoneConfirmationDialog | Task 6 (MergeStatus) | Unit + Widget Integration |
| 11 | /workstart handler | Tasks 2, 3-6, 8, 9 | Unit + Widget Integration |
| 12 | /workdone handler | Tasks 2, 6, 10 | Unit + Widget Integration |
| 13 | /worktrees handler | Task 2 | Unit + Widget Integration |
| 14 | Session list indicator | Task 7 | Unit + Widget Integration |
| 15 | Wire onboarding dialog | Tasks 9, 11 | Widget Integration |
| 16 | Wire workdone dialog | Tasks 10, 12 | Widget Integration |
| 17 | Initialize services | Tasks 2, 3 | Widget Integration |
| 18 | Widget integration test | All tasks | Widget Integration (mock backend + real git) |
| 19 | Real E2E test | Task 18 | E2E (real app + external mock backend + real git) |

**Testing Notes:**
- All UI features and functionality MUST have integration tests
- See `flutter_app/TESTS.md` for testing patterns and mocking infrastructure
- All pre-existing tests must continue to pass
- Task 18 = fast tests with `flutter test`
- Task 19 = slow tests with `flutter test integration_test/`

**Recommended Implementation Order:**
1. Tasks 1-2 (config layer)
2. Tasks 3-6 (git service)
3. Task 7-8 (session model)
4. Tasks 9-10 (dialogs)
5. Tasks 11-13 (commands)
6. Task 14 (UI indicator)
7. Tasks 15-17 (wiring)
8. Task 18 (widget integration test)
9. Task 19 (real E2E test)
