/// System prompt text describing internal git MCP tools.
///
/// Appended to the system prompt when git tools are registered so that
/// agents know to prefer the built-in tools over shell git commands.
const String gitToolsSystemPrompt =
    'You have access to internal git MCP tools '
    '(git_commit_context, git_commit, git_log, git_diff). '
    'Prefer these over running git commands via the shell — '
    'they are faster and safer. '
    'Fall back to shell git only for operations these tools '
    'do not cover.';

/// Guidance for resolving merge conflicts during orchestrated rebase-and-merge.
///
/// Extracted from the orchestrator system prompt so it can be reused
/// independently (e.g. when launching a conflict-resolution agent).
const String mergeConflictGuidance = '''
When calling rebase_and_merge() and a conflict occurs, launch an agent
in the conflicted worktree to resolve it:
  rebase_and_merge(worktree) → { success: false, conflicts: true }
  launch_agent(worktree, "A rebase conflict occurred merging this
    branch into its base. Please fix the conflicts and commit.")
  wait_for_agents([conflict-agent])
  rebase_and_merge(worktree) → retry after resolution

**Note:** The example instruction above is simplified. In practice,
you should provide the agent with more context about the ticket, the
branches involved, and any relevant information to help them resolve
the conflict effectively. As well as remind the agent to ask the user
if the merge is complex or they are unsure about how to proceed.''';
