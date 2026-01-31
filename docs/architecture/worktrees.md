# Git Worktree Creation - Implementation Plan

## Status: COMPLETE ✅

All phases have been implemented and tested. Total: 948 tests passing.

| Phase | Status | Notes |
|-------|--------|-------|
| 1.1 - ProjectInfo defaultWorktreeRoot | ✅ Complete | Added to persistence_models.dart |
| 1.2 - GitService methods | ✅ Complete | listBranches, branchExists, createWorktree |
| 1.3 - WorktreeService | ✅ Complete | New service with validation logic |
| 2.1 - ContentPanelMode | ✅ Complete | Added to selection_state.dart |
| 2.2 - addWorktree method | ✅ Complete | Added to project.dart |
| 3.1 - CreateWorktreePanel | ✅ Complete | New panel widget created |
| 3.2 - ContentPanel switching | ✅ Complete | Mode-based panel switching |
| 3.3 - CreateWorktreeCard wiring | ✅ Complete | Ghost card triggers panel |
| 4 - Testing | ✅ Complete | 27 unit tests + 26 widget tests |

### Test Files Created
- `frontend/test/services/worktree_service_test.dart` - 27 unit tests
- `frontend/test/panels/create_worktree_panel_test.dart` - 26 widget tests
- `frontend/integration_test/worktree_creation_test.dart` - 13 integration tests

### Bug Fixes Applied
- **GitService Provider missing**: Added `GitService` to Provider tree in `main.dart` so `CreateWorktreePanel` can access it via `context.read<GitService>()`

### Documentation Note
Subagents should read `FLUTTER.md` and `TESTING.md` before beginning work on this codebase.

---

## Overview

This document describes the implementation plan for adding git worktree creation support to CC-Insights. Users will be able to create linked worktrees from the UI, with the worktree appearing in the sidebar immediately after creation.

## User Flow

1. User clicks **"New Worktree"** ghost card in the Worktree panel
2. The **Create Worktree panel** replaces the Conversation panel temporarily
3. User fills in:
   - **Branch name** (with autocomplete from existing branches not yet worktrees)
   - **Worktree root directory** (pre-populated from project config, editable)
4. User clicks **"Create Worktree"** button
5. System validates and creates the worktree
6. On success: worktree appears in sidebar, panel returns to conversation view
7. On error: error message shown inline with suggestions

---

## Data Model Changes

### ProjectInfo (persistence_models.dart)

Add a new field to store the default worktree root for the project:

```dart
@immutable
class ProjectInfo {
  final String id;
  final String name;
  final Map<String, WorktreeInfo> worktrees;
  final String? defaultWorktreeRoot;  // NEW: default parent dir for worktrees

  // ...
}
```

**Default value logic:**
- If not set, default to `{project_parent_dir}/.{project_name}-wt`
- Example: Project at `/Users/dev/my-app` → default root is `/Users/dev/.my-app-wt`

### projects.json structure change

```json
{
  "/Users/dev/my-app": {
    "id": "abc123",
    "name": "my-app",
    "defaultWorktreeRoot": "/Users/dev/.my-app-wt",  // NEW
    "worktrees": {
      "/Users/dev/my-app": { "type": "primary", "name": "main", "chats": [] },
      "/Users/dev/.my-app-wt/cci/feature-x": { "type": "linked", "name": "feature-x", "chats": [] }
    }
  }
}
```

---

## Git Service Additions

### New methods in `GitService` (git_service.dart)

```dart
abstract class GitService {
  // Existing methods...

  /// Lists all local branches in the repository.
  Future<List<String>> listBranches(String repoRoot);

  /// Checks if a branch exists in the repository.
  Future<bool> branchExists(String repoRoot, String branchName);

  /// Creates a new worktree at the specified path.
  ///
  /// If [newBranch] is true, creates a new branch with the given name.
  /// If [newBranch] is false, checks out an existing branch.
  ///
  /// Throws [GitException] with actionable message on failure.
  Future<void> createWorktree({
    required String repoRoot,
    required String worktreePath,
    required String branch,
    required bool newBranch,
  });
}
```

### Implementation in `RealGitService`

```dart
@override
Future<List<String>> listBranches(String repoRoot) async {
  final output = await _runGit(
    ['branch', '--format=%(refname:short)'],
    workingDirectory: repoRoot,
  );
  return output.split('\n').where((b) => b.isNotEmpty).toList();
}

@override
Future<bool> branchExists(String repoRoot, String branchName) async {
  try {
    await _runGit(
      ['rev-parse', '--verify', 'refs/heads/$branchName'],
      workingDirectory: repoRoot,
    );
    return true;
  } on GitException {
    return false;
  }
}

@override
Future<void> createWorktree({
  required String repoRoot,
  required String worktreePath,
  required String branch,
  required bool newBranch,
}) async {
  final args = ['worktree', 'add'];
  if (newBranch) {
    args.addAll(['-b', branch, worktreePath]);
  } else {
    args.addAll([worktreePath, branch]);
  }
  await _runGit(args, workingDirectory: repoRoot);
}
```

---

## UI Components

### 1. SelectionState Additions

Add a mode enum and field to track when we're showing the Create Worktree panel:

```dart
enum ContentPanelMode {
  conversation,      // Normal conversation view
  createWorktree,    // Create worktree form
}

class SelectionState extends ChangeNotifier {
  // Existing fields...

  ContentPanelMode _contentPanelMode = ContentPanelMode.conversation;

  ContentPanelMode get contentPanelMode => _contentPanelMode;

  void showCreateWorktreePanel() {
    _contentPanelMode = ContentPanelMode.createWorktree;
    notifyListeners();
  }

  void showConversationPanel() {
    _contentPanelMode = ContentPanelMode.conversation;
    notifyListeners();
  }
}
```

### 2. ContentPanel Changes (content_panel.dart)

Update to switch between conversation and create worktree views:

```dart
class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();

    return switch (selection.contentPanelMode) {
      ContentPanelMode.conversation => const PanelWrapper(
        title: 'Conversation',
        icon: Icons.chat_bubble_outline,
        child: ConversationPanel(),
      ),
      ContentPanelMode.createWorktree => const PanelWrapper(
        title: 'Create Worktree',
        icon: Icons.account_tree,
        child: CreateWorktreePanel(),
      ),
    };
  }
}
```

### 3. CreateWorktreePanel (new file: create_worktree_panel.dart)

New panel for the worktree creation form:

```dart
class CreateWorktreePanel extends StatefulWidget {
  const CreateWorktreePanel({super.key});

  @override
  State<CreateWorktreePanel> createState() => _CreateWorktreePanelState();
}

class _CreateWorktreePanelState extends State<CreateWorktreePanel> {
  final _branchController = TextEditingController();
  final _rootController = TextEditingController();

  bool _isCreating = false;
  String? _errorMessage;
  List<String>? _errorSuggestions;
  List<String> _availableBranches = [];
  List<String> _existingWorktreeBranches = [];

  @override
  void initState() {
    super.initState();
    _loadBranchesAndDefaults();
  }

  Future<void> _loadBranchesAndDefaults() async {
    // Load available branches, existing worktrees, and default root
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Help text explaining what a worktree is
        _WorktreeHelpCard(),

        // Form fields
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Branch name with autocomplete
                _BranchNameField(
                  controller: _branchController,
                  availableBranches: _availableBranches,
                  existingWorktreeBranches: _existingWorktreeBranches,
                ),
                const SizedBox(height: 16),

                // Worktree root directory
                _WorktreeRootField(
                  controller: _rootController,
                ),
                const SizedBox(height: 8),

                // Note about directory location
                _DirectoryNote(),

                // Error message (if any)
                if (_errorMessage != null)
                  _ErrorCard(
                    message: _errorMessage!,
                    suggestions: _errorSuggestions,
                  ),
              ],
            ),
          ),
        ),

        // Action buttons
        _ActionBar(
          isCreating: _isCreating,
          onCancel: _handleCancel,
          onCreate: _handleCreate,
        ),
      ],
    );
  }

  void _handleCancel() {
    context.read<SelectionState>().showConversationPanel();
  }

  Future<void> _handleCreate() async {
    // Validation and creation logic
  }
}
```

### 4. CreateWorktreeCard Update (worktree_panel.dart)

Wire up the ghost card to trigger the panel:

```dart
class CreateWorktreeCard extends StatelessWidget {
  const CreateWorktreeCard({super.key});

  @override
  Widget build(BuildContext context) {
    // ... existing styling ...

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<SelectionState>().showCreateWorktreePanel();
        },
        child: // ... existing child ...
      ),
    );
  }
}
```

---

## Validation Logic

### Pre-creation Validation

When user clicks "Create Worktree", perform these checks in order:

#### 1. Validate worktree root is outside project repo

```dart
bool _isPathInsideRepo(String worktreePath, String repoRoot) {
  final normalizedWorktree = path.normalize(path.absolute(worktreePath));
  final normalizedRepo = path.normalize(path.absolute(repoRoot));
  return normalizedWorktree.startsWith(normalizedRepo);
}
```

**Error if inside:**
> "Worktree directory cannot be inside the project repository. Please choose a location outside of `{repoRoot}`."

#### 2. Sanitize branch name

```dart
String _sanitizeBranchName(String input) {
  return input
    .trim()
    .replaceAll(RegExp(r'\s+'), '-')      // spaces → hyphens
    .replaceAll(RegExp(r'[^\w\-/]'), '')  // remove invalid chars
    .replaceAll(RegExp(r'^-+|-+$'), '')   // trim leading/trailing hyphens
    .replaceAll(RegExp(r'\.\.'), '.')     // no consecutive dots
    .replaceAll(RegExp(r'//+'), '/');     // no consecutive slashes
}
```

#### 3. Check if branch exists and is already a worktree

```dart
Future<(bool exists, bool isWorktree, String? worktreePath)> _checkBranch(
  String branchName,
) async {
  final gitService = context.read<GitService>();
  final project = context.read<ProjectState>();

  final exists = await gitService.branchExists(project.data.repoRoot, branchName);
  if (!exists) {
    return (false, false, null);
  }

  // Branch exists - check if it's already a worktree
  final worktrees = await gitService.discoverWorktrees(project.data.repoRoot);
  final existingWorktree = worktrees.firstWhereOrNull(
    (wt) => wt.branch == branchName,
  );

  if (existingWorktree != null) {
    return (true, true, existingWorktree.path);
  }

  return (true, false, null);
}
```

**Error if already a worktree:**
> "Branch `{branch}` already exists and is a worktree at: `{path}`"
>
> **Suggestions:**
> - Select the existing worktree from the sidebar
> - Choose a different branch name

---

## Creation Logic

### Worktree Service (new file: worktree_service.dart)

Create a service to encapsulate worktree creation logic:

```dart
class WorktreeService {
  final GitService _gitService;
  final PersistenceService _persistenceService;

  WorktreeService({
    GitService? gitService,
    PersistenceService? persistenceService,
  }) : _gitService = gitService ?? const RealGitService(),
       _persistenceService = persistenceService ?? PersistenceService();

  /// Creates a new worktree and persists it.
  ///
  /// Returns the created WorktreeState on success.
  /// Throws [WorktreeCreationException] on failure with actionable message.
  Future<WorktreeState> createWorktree({
    required ProjectState project,
    required String branch,
    required String worktreeRoot,
  }) async {
    final repoRoot = project.data.repoRoot;

    // 1. Validate path is outside repo
    if (_isPathInsideRepo(worktreeRoot, repoRoot)) {
      throw WorktreeCreationException(
        'Worktree directory cannot be inside the project repository.',
        suggestions: ['Choose a location outside of $repoRoot'],
      );
    }

    // 2. Sanitize branch name
    final sanitizedBranch = _sanitizeBranchName(branch);
    if (sanitizedBranch.isEmpty) {
      throw WorktreeCreationException(
        'Invalid branch name. Please enter a valid branch name.',
      );
    }

    // 3. Check branch status
    final branchExists = await _gitService.branchExists(repoRoot, sanitizedBranch);
    final worktrees = await _gitService.discoverWorktrees(repoRoot);
    final existingWorktree = worktrees.firstWhereOrNull(
      (wt) => wt.branch == sanitizedBranch,
    );

    if (existingWorktree != null) {
      throw WorktreeCreationException(
        'Branch "$sanitizedBranch" is already a worktree at: ${existingWorktree.path}',
        suggestions: [
          'Select the existing worktree from the sidebar',
          'Choose a different branch name',
        ],
      );
    }

    // 4. Construct the full worktree path
    final worktreePath = path.join(worktreeRoot, 'cci', sanitizedBranch);

    // 5. Ensure parent directory exists
    final parentDir = Directory(path.dirname(worktreePath));
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    // 6. Create the git worktree
    try {
      await _gitService.createWorktree(
        repoRoot: repoRoot,
        worktreePath: worktreePath,
        branch: sanitizedBranch,
        newBranch: !branchExists,
      );
    } on GitException catch (e) {
      throw WorktreeCreationException(
        'Failed to create worktree: ${e.message}',
        suggestions: _suggestionsForGitError(e),
      );
    }

    // 7. Get git status for the new worktree
    final status = await _gitService.getStatus(worktreePath);

    // 8. Create WorktreeData and WorktreeState
    final worktreeData = WorktreeData(
      worktreeRoot: worktreePath,
      isPrimary: false,
      branch: sanitizedBranch,
      uncommittedFiles: status.uncommittedFiles,
      stagedFiles: status.staged,
      commitsAhead: status.ahead,
      commitsBehind: status.behind,
      hasMergeConflict: status.hasConflicts,
    );
    final worktreeState = WorktreeState(worktreeData);

    // 9. Persist to projects.json
    await _persistWorktree(project, worktreeState);

    return worktreeState;
  }

  Future<void> _persistWorktree(
    ProjectState project,
    WorktreeState worktree,
  ) async {
    final index = await _persistenceService.loadProjectsIndex();
    final projectInfo = index.projects[project.data.repoRoot];

    if (projectInfo == null) {
      throw WorktreeCreationException(
        'Project not found in persistence. This is unexpected.',
      );
    }

    // Add the new worktree to the project
    final updatedWorktrees = Map<String, WorktreeInfo>.from(projectInfo.worktrees);
    updatedWorktrees[worktree.data.worktreeRoot] = WorktreeInfo.linked(
      name: worktree.data.branch,
    );

    final updatedProjectInfo = projectInfo.copyWith(worktrees: updatedWorktrees);
    final updatedProjects = Map<String, ProjectInfo>.from(index.projects);
    updatedProjects[project.data.repoRoot] = updatedProjectInfo;

    await _persistenceService.saveProjectsIndex(
      index.copyWith(projects: updatedProjects),
    );
  }

  List<String> _suggestionsForGitError(GitException e) {
    final stderr = e.stderr?.toLowerCase() ?? '';

    if (stderr.contains('already exists')) {
      return [
        'The worktree directory already exists',
        'Choose a different branch name or delete the existing directory',
      ];
    }

    if (stderr.contains('is already checked out')) {
      return [
        'This branch is checked out in another worktree',
        'Use a different branch name',
      ];
    }

    return ['Check the git error message above for details'];
  }
}

class WorktreeCreationException implements Exception {
  final String message;
  final List<String> suggestions;

  WorktreeCreationException(this.message, {this.suggestions = const []});

  @override
  String toString() => message;
}
```

---

## Integration with ProjectState

### Add worktree to project

```dart
class ProjectState extends ChangeNotifier {
  // Existing code...

  /// Adds a linked worktree to this project.
  void addWorktree(WorktreeState worktree) {
    _linkedWorktrees.add(worktree);
    notifyListeners();
  }
}
```

---

## File Structure

New/modified files:

```
frontend/lib/
├── panels/
│   ├── content_panel.dart          # MODIFIED: switch between modes
│   ├── create_worktree_panel.dart  # NEW: worktree creation form
│   └── worktree_panel.dart         # MODIFIED: wire up ghost card
├── services/
│   ├── git_service.dart            # MODIFIED: add branch/worktree methods
│   ├── persistence_models.dart     # MODIFIED: add defaultWorktreeRoot
│   └── worktree_service.dart       # NEW: worktree creation logic
├── state/
│   └── selection_state.dart        # MODIFIED: add content panel mode
└── models/
    └── project.dart                # MODIFIED: add addWorktree method
```

---

## UI Design Details

### Help Card Text

> **What is a Git Worktree?**
>
> A worktree lets you work on multiple branches simultaneously without switching. Each worktree is a separate directory with its own branch checked out, sharing the same repository history.
>
> This is useful for:
> - Working on a feature while keeping main available for quick fixes
> - Reviewing PRs without disrupting your current work
> - Running tests on one branch while developing on another

### Form Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Create Worktree                                      [×]   │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ℹ️ What is a Git Worktree?                            │  │
│  │                                                        │  │
│  │ A worktree lets you work on multiple branches...      │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  Branch Name                                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ feature/new-ui                              ▼       │   │
│  └─────────────────────────────────────────────────────┘   │
│  Suggestions: feature/login, bugfix/auth, develop          │
│                                                             │
│  Worktree Root Directory                                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ /Users/dev/.my-app-wt                      [📁]     │   │
│  └─────────────────────────────────────────────────────┘   │
│  ⚠️ This directory must be outside the project repository  │
│                                                             │
│  Full path: /Users/dev/.my-app-wt/cci/feature/new-ui       │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ ❌ Error: Branch "feature/new-ui" is already a        │  │
│  │    worktree at: /Users/dev/.my-app-wt/cci/feature-ui  │  │
│  │                                                        │  │
│  │    • Select the existing worktree from the sidebar    │  │
│  │    • Choose a different branch name                   │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                              [Cancel]  [Create Worktree]    │
└─────────────────────────────────────────────────────────────┘
```

---

## Testing Plan

### Unit Tests

1. **Branch name sanitization**
   - Spaces converted to hyphens
   - Invalid characters removed
   - Empty input handled

2. **Path validation**
   - Detect paths inside repo
   - Handle symlinks correctly
   - Handle relative vs absolute paths

3. **WorktreeService**
   - Mock GitService for testing
   - Verify correct git commands called
   - Test error handling and suggestions

### Widget Tests

1. **CreateWorktreePanel**
   - Form validation errors shown
   - Branch autocomplete works
   - Cancel returns to conversation
   - Create button disabled when invalid

2. **Content panel switching**
   - Mode switching works correctly
   - State preserved on switch back

### Integration Tests

1. **Full worktree creation flow**
   - Create worktree end-to-end
   - Verify appears in sidebar
   - Verify persisted to projects.json

2. **Error scenarios**
   - Existing branch worktree
   - Path inside repo
   - Git command failure

---

## Implementation Order

1. **Phase 1: Data layer**
   - Add `defaultWorktreeRoot` to `ProjectInfo`
   - Add git methods to `GitService`
   - Create `WorktreeService`

2. **Phase 2: State layer**
   - Add `ContentPanelMode` to `SelectionState`
   - Add `addWorktree` to `ProjectState`

3. **Phase 3: UI layer**
   - Create `CreateWorktreePanel`
   - Update `ContentPanel` for mode switching
   - Wire up `CreateWorktreeCard`

4. **Phase 4: Testing**
   - Unit tests for services
   - Widget tests for panels
   - Integration tests for full flow

---

## Open Questions (Resolved)

| Question | Decision |
|----------|----------|
| Per-project or per-worktree root setting? | **Per-project** - stored in `projects.json`, can override per-creation |
| Error handling approach? | **Inline with suggestions** - show errors in panel with actionable suggestions |
| Branch autocomplete? | **Yes** - show dropdown of existing branches not yet worktrees |
