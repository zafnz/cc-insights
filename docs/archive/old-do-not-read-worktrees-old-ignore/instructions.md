## Git Worktrees Feature - Task Implementation Instructions

You are implementing the Git Worktrees feature for CC Insights, a Flutter desktop app for monitoring Claude Code agents.

### Context

**Project Location:** `/tmp/cc-insights/project`

**Key Documentation:**
- Feature Plan: `docs/features/worktrees/plan.md`
- Task List: `docs/features/worktrees/tasks.md`
- Project Guide: `CLAUDE.md`
- Testing Guide: `flutter_app/TESTS.md` - **READ THIS** for test patterns and mocking infrastructure

**Architecture:**
- Flutter app (`flutter_app/`) with Provider state management
- Dart SDK (`claude_dart_sdk/`) wraps Node.js backend
- Configuration patterns in `flutter_app/lib/services/runtime_config.dart`

### Your Mission

1. **Read the task list** at `docs/features/worktrees/tasks.md`
2. **Find the first uncompleted task** (one where not all checkboxes are ticked)
3. **Complete ONLY that single task** - do not proceed to the next task

### Task Completion Process

For your one task, follow these steps in order:

#### Step 1: Understand
- Read the task description thoroughly
- Read any referenced files mentioned in the task
- Understand what needs to be built

#### Step 2: Implement
- Write the code as specified in the task description
- Follow existing patterns in the codebase
- Create or modify only the files specified

#### Step 3: Test
- **Read `flutter_app/TESTS.md`** for testing patterns and mocking infrastructure
- Write all unit tests specified in "Tests Required"
- **All UI features and functionality MUST have integration tests**
- Use the mock infrastructure documented in `flutter_app/TESTS.md`
- Run the tests using `cd flutter_app && flutter test`
- There are pre-existing tests. You are not done until ALL tests are passing again.
- Fix any failing tests

#### Step 4: Acceptance
- Launch a subagent (using the Task tool with `subagent_type: "general-purpose"`) to perform acceptance testing
- The subagent should:
  - Review the implementation against the acceptance criteria
  - Verify tests exist and pass
  - Check code follows project patterns
  - Report pass/fail with reasoning

#### Step 5: Complete
- If acceptance passes, edit `docs/features/worktrees/tasks.md` to tick the checkboxes:
  ```
  - [x] Written
  - [x] Tested
  - [x] Accepted
  ```
- **STOP** - Do not proceed to the next task

### Important Rules

- **ONE TASK ONLY** - Complete exactly one task, then stop
- **NO SKIPPING** - Do tasks in order; don't skip to "more interesting" ones
- **TESTS ARE REQUIRED** - Don't mark as complete without passing tests
- **ALL TESTS MUST PASS** - Pre-existing tests must continue to pass
- **UI MUST HAVE INTEGRATION TESTS** - All UI features require integration tests using the mock infrastructure
- **USE SUBAGENT FOR ACCEPTANCE** - Don't self-certify; use a fresh perspective
- **UPDATE THE TASK FILE** - Tick the checkboxes when done

### When You're Done

After ticking the checkboxes for your completed task, git commit your work with a summary of what you did, and then output a summary:

```
## Task [N] Complete

**Task:** [Task title]
**Files Created/Modified:** [list files]
**Tests:** [X passing, Y total]
**Acceptance:** Passed

Ready for next task in a new session.
```

Then STOP. Do not continue to the next task.
