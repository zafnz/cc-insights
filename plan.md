# Implementation Plan: Stage and Commit All Dialog

## Overview

Wire up the "Stage and commit all" button to open a dialog that allows users to stage all files and create a commit with an AI-generated or manually-written commit message.

## Architecture

### New Files to Create

1. **`frontend/lib/widgets/commit_dialog.dart`** - The commit dialog widget
2. **`frontend/lib/widgets/commit_dialog_keys.dart`** - Test keys for the dialog (can be in same file)

### Files to Modify

1. **`frontend/lib/services/git_service.dart`** - Add new git operations
2. **`frontend/lib/panels/information_panel.dart`** - Wire up the button

---

## Phase 1: Extend GitService

Add the following methods to `GitService` abstract class and `RealGitService` implementation:

### New Methods

```dart
/// Gets list of all changed files (staged, unstaged, untracked).
/// Returns list of file paths relative to the worktree root.
Future<List<GitFileChange>> getChangedFiles(String path);

/// Stages all changes in the worktree.
Future<void> stageAll(String path);

/// Creates a commit with the given message.
/// Throws GitException if commit fails.
Future<void> commit(String path, String message);

/// Resets the index (unstages all files).
/// Used to restore state on error.
Future<void> resetIndex(String path);
```

### New Model

```dart
/// Represents a changed file in the git status.
class GitFileChange {
  final String path;
  final GitFileStatus status; // added, modified, deleted, renamed, untracked
  final bool isStaged;
}

enum GitFileStatus { added, modified, deleted, renamed, untracked, copied }
```

### Implementation Details

- `getChangedFiles`: Parse `git status --porcelain=v2` to extract file paths and statuses
- `stageAll`: Run `git add -A`
- `commit`: Run `git commit -m "message"` (using stdin for multiline messages)
- `resetIndex`: Run `git reset HEAD`

---

## Phase 2: Create CommitDialog Widget

### Layout (Column with two sides)

```
┌─────────────────────────────────────────────────────────────────┐
│  Header: "Commit Changes"                     [✨ AI] [Cancel]  │
├────────────────────────────┬────────────────────────────────────┤
│  FILES TO COMMIT           │  COMMIT MESSAGE                    │
│  (scrollable list)         │  ┌─────────────────────────────┐  │
│                            │  │ [Edit] [Preview]            │  │
│  ☑ lib/foo.dart (M)       │  ├─────────────────────────────┤  │
│  ☑ lib/bar.dart (A)       │  │                             │  │
│  ☑ test/test.dart (D)     │  │  Commit message text...     │  │
│                            │  │  (monospace font)           │  │
│                            │  │                             │  │
│                            │  │  [Spinner] Generating...    │  │
│                            │  │                             │  │
│                            │  └─────────────────────────────┘  │
├────────────────────────────┴────────────────────────────────────┤
│                                              [Cancel] [Commit]  │
└─────────────────────────────────────────────────────────────────┘
```

### Components

1. **Header Bar**
   - Title: "Commit Changes"
   - AI regenerate button (magic wand icon `Icons.auto_awesome`)
   - Close/Cancel button

2. **Left Panel: File List**
   - Scrollable list of files to be committed
   - Show file path and status indicator (M/A/D/R/?)
   - Checkboxes (all checked by default, for future selective staging)
   - Uses monospace font (`AppFonts.monoTextStyle()`)

3. **Right Panel: Commit Message Editor**
   - Tab bar: Edit | Preview
   - **Edit tab**: `TextField` with monospace font, multiline, expanding
   - **Preview tab**: Markdown rendered using `GptMarkdown` widget
   - Default placeholder text: "Generating commit message..." with spinner

4. **Footer**
   - Cancel button
   - Commit button (primary action, green)

### State Management

```dart
class _CommitDialogState extends State<CommitDialog> {
  List<GitFileChange> _files = [];
  String _commitMessage = '';
  bool _isGenerating = true;
  bool _userHasEdited = false;
  String? _cachedAiMessage;  // Cache AI response if user types then wants it back
  bool _isEditMode = true;   // true = Edit tab, false = Preview tab
  String? _error;
}
```

### Behavior

1. **On Open**:
   - Load list of changed files via `gitService.getChangedFiles()`
   - Start AI generation (async)
   - Show spinner in text box

2. **AI Generation**:
   - Call `AskAiService.ask()` with prompt (see below)
   - On completion: if user hasn't typed, update text field
   - If user has typed, cache the response

3. **User Types in Text Box**:
   - Set `_userHasEdited = true`
   - Hide spinner
   - Keep AI request running in background

4. **AI Button Clicked**:
   - If cached response exists, use it
   - Otherwise trigger new AI request
   - Set `_userHasEdited = false` and show spinner

5. **Commit Button Clicked**:
   - Validate message is not empty
   - Call `gitService.stageAll(path)`
   - Call `gitService.commit(path, message)`
   - On success: close dialog, refresh git status
   - On error: show error, call `gitService.resetIndex()` to restore state

6. **Cancel Button Clicked**:
   - Close dialog without changes

---

## Phase 3: AI Prompt

```
Generate a commit message based on all of the work done in these files, there may be multiple changes reflected in this commit. Refer to other files for context if needed. The commit message should be detailed and contain multiple sections. Reply with ONLY the commit message, no other text, or reply ERROR if there is an error.

Files to commit:
- lib/foo.dart (modified)
- lib/bar.dart (added)
- test/test.dart (deleted)
```

### AI Service Call

```dart
final result = await askAiService.ask(
  prompt: prompt,
  workingDirectory: worktreePath,
  model: 'haiku',
  allowedTools: ['Bash(git:*)', 'Read'],
  maxTurns: 5,  // Allow reading some files for context
  timeoutSeconds: 120,
);
```

---

## Phase 4: Wire Up Button in InformationPanel

1. Add `showCommitDialog()` function
2. Pass required dependencies (GitService, AskAiService, worktree path)
3. Update worktree status after successful commit

```dart
_CompactButton(
  onPressed: data.uncommittedFiles > 0 || data.stagedFiles > 0
      ? () => _showCommitDialog(context, worktreePath)
      : null,
  label: 'Stage and commit all',
  icon: Icons.check_circle_outline,
),
```

---

## Phase 5: Error Handling

### Scenarios

1. **Git operations fail**
   - Log error to stdout
   - Show error message in dialog
   - Call `resetIndex()` to restore previous state

2. **AI generation fails**
   - Show error text instead of spinner
   - Allow user to type manually
   - AI button still available to retry

3. **Empty commit message**
   - Disable Commit button when message is empty

---

## Phase 6: Testing

### Unit Tests

1. **GitService tests** (new methods)
   - `getChangedFiles` parsing
   - `stageAll` command execution
   - `commit` command execution
   - `resetIndex` command execution

2. **CommitDialog widget tests**
   - Dialog renders correctly
   - File list displays properly
   - Tab switching works
   - AI spinner shows/hides correctly
   - User typing hides spinner
   - Commit button enables/disables
   - Error display

### Integration Tests

1. Full commit flow with mock git service
2. AI generation integration

---

## Implementation Order

1. **Phase 1**: Extend GitService with new methods and model
2. **Phase 2**: Create CommitDialog widget (UI only, no integration)
3. **Phase 3**: Integrate AI service for commit message generation
4. **Phase 4**: Wire up button in InformationPanel
5. **Phase 5**: Add error handling and edge cases
6. **Phase 6**: Write tests

---

## Dependencies

- Existing: `AskAiService`, `GitService`, `AppFonts`, `GptMarkdown`
- New: None

## File Changes Summary

| File | Action |
|------|--------|
| `git_service.dart` | Add 4 methods + 2 new types |
| `commit_dialog.dart` | Create new file (~300 lines) |
| `information_panel.dart` | Wire up button (~20 lines) |
| `test/services/git_service_test.dart` | Add tests for new methods |
| `test/widget/commit_dialog_test.dart` | Create new test file |
