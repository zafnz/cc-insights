# Escape from Merge Hell

When working with multiple worktrees, merging branches back into main can become complicated. This document describes the graduated approach for handling `/worktree merge main`.

## Overview

The merge process tries the simplest approach first and escalates only when necessary:

1. **Trivial merge** → automatic
2. **Conflicts, but main is clean** → resolve locally, then fast-forward
3. **Uncommitted work in main** → ask main's Claude to commit first
4. **Complex merge required** → spawn a fresh Claude to do the merge work

All merge conflict resolution happens in the feature branch, not in main. This keeps main clean and makes the final merge trivial.

## The `/worktree merge main` Command

When a user runs `/worktree merge main` from a feature branch worktree:

### Step 1: Check Main's Status

First, check if main has uncommitted changes:

```bash
git worktree list  # Find main worktree path
git -C <main-worktree-path> status --porcelain
```

**If main has uncommitted changes**, go to Step 3 first.

**If main is clean**, continue to Step 2.

### Step 2: Merge Main into Feature Branch

Merge main INTO the current feature branch:

```bash
git merge main --no-edit
```

**If successful (no conflicts):**
- The branch is now up-to-date with main
- Fast-forward main:
  ```bash
  git -C <main-worktree-path> merge <feature-branch> --no-edit
  ```
- Report success: "✅ Branch merged into main."
- Done.

**If there are conflicts:**
- Assess complexity (number of files, size of changes)
- If simple: resolve conflicts, test, commit, then fast-forward main
- If complex: go to Step 4

### Step 3: Handle Uncommitted Work in Main

**If main has uncommitted changes in conflicting files:**

Prompt the user:
> "It looks like there's unfinished work in main (`session_provider.dart`, `input_panel.dart`). Can I ask the Claude session working on main for help?"

**If user agrees**, send a message to main's Claude:
> "The user wants to merge `<branch>` into main, but I see uncommitted changes:
> - `session_provider.dart` (modified)
> - `input_panel.dart` (modified)
>
> Has your session been working on this? If so, can you commit your work?"

Wait for main's Claude to:
- Commit the work (if complete)
- Or explain what's WIP and needs user attention

Once main is clean, go back to Step 2.

### Step 4: Spawn Fresh Claude for Complex Merges

**If the merge is complex** (many conflicts, structural changes on both sides, extensive testing needed):

The current Claude may have a full context buffer from feature work. A fresh Claude dedicated to merge resolution is more effective.

Prompt the user:
> "This merge requires significant work to resolve. Should I hand this off to a fresh Claude session to handle the merge? I'll stay available for follow-up questions about the feature."

**If user agrees:**

1. Spawn a new Claude session in the same feature branch worktree with context:
   > "You're here to resolve a merge conflict.
   >
   > **Current branch:** `<feature-branch>`
   > **Target:** merge into `main`
   > **Situation:** `git merge main` was attempted but has conflicts
   >
   > Your job:
   > 1. Resolve all merge conflicts
   > 2. Ensure the code compiles and tests pass
   > 3. Commit the merge
   > 4. Once clean, fast-forward main:
   >    ```bash
   >    git -C <main-worktree-path> merge <feature-branch> --no-edit
   >    ```
   > 5. Report back: "✅ Merge complete. `<feature-branch>` has been merged into main."
   >
   > Take your time. Ask the user if you need clarification on intent."

2. The merge Claude works in the feature branch:
   - Resolves conflicts
   - Runs tests
   - May need multiple commits
   - Can ask user questions if needed

3. Once complete, merge Claude:
   - Fast-forwards main
   - Reports success
   - Optionally notifies the original Claude: "Merge complete. Here's what was resolved: [summary]"

## Why Merge Work Happens in the Feature Branch

The feature branch is the right place for merge resolution because:

1. **Main stays clean** - no half-finished merges in main
2. **Feature branch can't progress anyway** - if it can't merge, new work just makes it worse
3. **Fast-forward is trivial** - once feature contains main + resolution, merging to main is clean
4. **No extra branches** - no `merge/<branch>-into-main` branches to manage

```
main ─────────────────────────●─────────────────────● (fast-forward)
                               \                   /
feature-1 ────────────────────●───●───●───●───●───●
                                  ↑       ↑
                            merge main    resolve conflicts,
                            into feature  test, commit
```

## Why Spawn a Fresh Claude

The original Claude working on the feature branch may have:
- A full context buffer from extensive feature work
- Deep knowledge of the feature's intent (valuable for follow-ups)

A fresh Claude for merge resolution:
- Has clean context dedicated to the merge problem
- Can read both branches' changes without prior assumptions
- Lets the original Claude stay available for "why did you do X?" questions

## Example Scenarios

### Scenario A: Clean Fast-Forward
```
User: /worktree merge main
Claude: ✅ Branch merged into main. No conflicts.
```

### Scenario B: Simple Conflict Resolution
```
User: /worktree merge main
Claude: There are a few conflicts. Resolving...
Claude: [resolves conflicts, runs tests]
Claude: ✅ Conflicts resolved. Branch merged into main.
```

### Scenario C: Main Has Uncommitted Work
```
User: /worktree merge main
Claude: Main has uncommitted changes in session_provider.dart.
        Can I ask the Claude session in main to commit first?
User: Yes
Claude: [messages main's Claude]
Main Claude: Done, I've committed my changes.
Claude: Thanks! Merging now...
Claude: ✅ Branch merged into main.
```

### Scenario D: Complex Merge
```
User: /worktree merge main
Claude: This merge has conflicts in 5 files with significant changes
        on both sides. Should I hand this off to a fresh Claude session?
        I'll stay here if you have questions about the feature.
User: Yes
Claude: Spawning merge session...

[New Claude session]
Merge Claude: I'm resolving the merge. Found conflicts in:
              - session_provider.dart (both sides refactored)
              - input_panel.dart (new features vs. restructure)
              Working on it...
[... time passes ...]
Merge Claude: ✅ Merge complete. All conflicts resolved, tests pass.
              Branch has been merged into main.
```

## Implementation Notes

### Finding the Main Worktree Path
```bash
git worktree list
# Parse output to find the worktree on [main] or [master]
```

### Assessing Merge Complexity
After `git merge main` with conflicts, check:
```bash
git diff --name-only --diff-filter=U  # List conflicted files
```

Heuristics for "complex":
- More than 3 conflicted files
- Conflicted files have 100+ lines of changes on both sides
- Same functions/classes modified differently on both sides

### Checking for Conflicts Before Merging
Preview conflicts without modifying working tree:
```bash
git merge-tree $(git merge-base main HEAD) main HEAD
```

### Cross-Claude Communication
When messaging another Claude:
- Include specific file names
- Include the branch name and its purpose
- Be clear about what action you need (commit, explain, defer)
- Keep it concise - the other Claude has its own context to manage
