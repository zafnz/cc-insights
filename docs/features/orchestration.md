# Ticket Orchestration

## Overview

Ticket orchestration lets users execute multiple tickets automatically — coordinating agents, managing dependencies, handling code reviews, and merging work — all driven by natural language instructions.

**The core idea**: The orchestrator is itself a Claude agent with a specialized toolset. The user describes their execution strategy in plain English, and the orchestrator agent uses its tools to launch worker agents, monitor progress, coordinate reviews, merge branches, and update tickets. There is no hardcoded workflow — the orchestrator adapts to whatever the user asks for.

**Why this approach**: Different projects need different workflows. Some want strict code review cycles. Some want sequential execution. Some want maximum parallelism. Rather than building a rigid state machine with configuration flags, we give the orchestrator agent tools and let the user describe what they want. The LLM figures out the coordination.

### Design Principles

- **Agent-driven, not state-machine-driven** — the orchestrator is a Claude chat with tools, not a fixed pipeline
- **User describes the strategy** — natural language instructions, not configuration forms
- **Composable primitives** — small, focused tools that compose into any workflow
- **Visible in the main chat screen** — the user watches tool calls and can intervene at any time
- **Built on existing infrastructure** — chats, worktrees, tickets, git operations all exist already
- **Tools are gated** — orchestration tools are only available in orchestrator chats, never in normal chats. This prevents agents from accidentally using orchestration tools when the user just wants a normal conversation.
- **Work stays on branches** — the orchestrator never merges into main. All work happens on feature branches. The user decides when and how to integrate (e.g., via GitHub PR). The orchestrator merges ticket branches into the orchestration's base worktree branch, not into main.

---

## User Stories

### Launching Orchestration

1. **As a user**, I want to select tickets and say "run these", so I can execute a batch of work without manually dispatching each ticket.
2. **As a user**, I want to describe my execution strategy in natural language (e.g., "do them in parallel with code reviews"), so I'm not locked into a predefined workflow.
3. **As a user**, I want to start an orchestrator from the ticket screen via a dedicated button, so orchestration is an explicit action — not something an agent stumbles into.
4. **As a user**, I want the orchestration dialog to create a feature worktree for the whole run (e.g., `feat-auth-system`), with all ticket worktrees branching off of it, so at the end I have one branch with the complete feature ready for a PR.

### Parallel Execution

5. **As a user**, I want the orchestrator to create separate worktrees for independent tickets and run them concurrently, so work completes faster.
6. **As a user**, I want the orchestrator to respect ticket dependencies — only starting a ticket when its dependencies are complete, so work is done in the right order.
7. **As a user**, I want finished ticket branches to be merged back into the orchestration's base worktree before dependent tickets start, so each agent builds on prior work.

### Sequential Execution

8. **As a user**, I want to tell the orchestrator to run tickets one at a time in the base worktree, so I can keep things simple when parallelism isn't needed.
9. **As a user**, I want the orchestrator to pick the next ticket based on dependency order and priority, so I don't have to manually sequence work.

### Code Review Cycles

10. **As a user**, I want to tell the orchestrator "have a different agent review each ticket's work", so code quality is checked before merging.
11. **As a user**, I want review feedback sent back to the implementing agent for fixes, with the cycle repeating until the review passes, so issues are caught and resolved automatically.
12. **As a user**, I want to set a limit on review rounds (e.g., "max 3 rounds"), so the process doesn't loop forever.

### Monitoring & Interaction

13. **As a user**, I want to watch the orchestrator's reasoning and tool calls in real time, so I understand what it's doing and why.
14. **As a user**, I want to click on any managed agent to see its conversation, so I can inspect the work being done.
15. **As a user**, I want to see a progress summary docked at the top of the orchestrator chat showing which tickets are running, waiting, reviewing, or complete.
16. **As a user**, I want to intervene mid-run — skip a review, cancel a ticket, change the strategy — by typing in the orchestrator chat.
17. **As a user**, I want permission requests from worker agents to surface normally (bell notifications), so I can approve them without disrupting the orchestrator.

### Completion & Cleanup

18. **As a user**, I want the orchestrator to update ticket statuses as work progresses (active → in review → completed), so the ticket board stays current.
19. **As a user**, I want the orchestrator to clean up ticket worktrees after merging (optionally), so I don't accumulate stale branches.
20. **As a user**, I want a summary when the run finishes — what completed, what failed, total cost/time — so I can assess the results.
21. **As a user**, I want the orchestration's base worktree to remain after the run completes, containing the merged result of all tickets, ready for me to review or open a PR.

### Error Recovery

22. **As a user**, I want the orchestrator to handle agent failures gracefully — mark the ticket as failed, continue with other tickets, and tell me what happened.
23. **As a user**, I want merge conflicts to be handled by launching an agent in the conflicted worktree to resolve them, not just reported as errors.
24. **As a user**, I want to be able to resume an orchestration run after fixing a problem, rather than starting over.

### Custom Workflows

25. **As a user**, I want to ask the orchestrator to run tests after merging all tickets, so I can validate the integrated result.
26. **As a user**, I want to ask for a specific review focus (e.g., "make sure all tickets have tests"), so reviews match my quality bar.
27. **As a user**, I want to mix manual and automated work — e.g., "do TKT-001 through TKT-005 automatically, but wait for me on TKT-006".

---

## How It Works

### The Orchestrator Is a Chat

The orchestrator is a regular chat session with:
- A **system prompt** that describes its role and capabilities
- A set of **internal tools** for managing agents, tickets, and git operations
- Full visibility in the conversation panel — the user sees every tool call and response
- A **progress widget** docked at the top of the conversation panel showing ticket status

There is no special "orchestration mode" or separate UI. The orchestrator lives in a chat, and the user talks to it like any other agent. The difference is that orchestrator chats have the orchestration toolset registered — normal chats do not.

### Tool Gating

Orchestration tools are **only** registered on chats created through the orchestration launch flow. Normal chats never have access to `launch_agent`, `wait_for_agents`, etc. This prevents agents from accidentally invoking orchestration tools during regular conversations.

The existing `create_ticket` tool remains available in normal chats as it is today. If a user wants ad-hoc orchestration without the ticket screen flow, they can enable orchestration tools on any chat via a toggle in the chat settings — but it's an explicit opt-in, never automatic.

### Branching Model

All orchestrated work happens on branches — the orchestrator **never merges into main**.

**When launched from the ticket screen (default flow):**

```
main
└── feat-auth-system          ← orchestration base worktree (created by dialog)
    ├── tkt-008-user-model    ← ticket worktree (created by orchestrator)
    ├── tkt-009-auth-routes   ← ticket worktree (created by orchestrator)
    └── tkt-010-session-mgmt  ← ticket worktree (created by orchestrator)
```

1. The orchestration config dialog creates a **base worktree** (e.g., `feat-auth-system`) branched off the user's chosen base (typically `main`).
2. The orchestrator creates **ticket worktrees** branched off the base worktree's branch.
3. When a ticket is complete, `rebase_and_merge` merges it back into the base worktree's branch.
4. At the end, `feat-auth-system` contains all the work. The user can open a PR from there.
5. Ticket worktrees are cleaned up after merge; the base worktree remains.

**When started ad-hoc (orchestration tools enabled on an existing chat):**

The user is in some worktree already. The orchestrator uses whatever worktree the user tells it to. There's no automatic base worktree creation — the user has full control.

### Starting an Orchestration

**From the ticket screen** (primary flow):
1. User selects tickets (checkboxes) or clicks "Run All Ready..."
2. Clicks "Run..." button → opens orchestration config dialog
3. Dialog shows: ticket summary, base branch selector, feature branch name field, instructions text area with presets
4. User clicks "Launch" → creates the base worktree, creates an orchestrator chat in it, navigates to the main screen
5. The orchestrator chat opens with the user's instructions as the first message, plus a system prompt with the toolset

**Ad-hoc** (advanced users):
- User enables orchestration tools on any existing chat via settings toggle
- Types orchestration instructions directly
- Full flexibility, no guardrails

### Orchestrator System Prompt

```
You are a project orchestrator for CC-Insights. You coordinate ticket
execution by launching agents in worktrees, monitoring their progress,
and managing the workflow the user describes.

You have tools to:
- Launch agents in worktrees with instructions
- Send messages to running agents and wait for responses
- Wait for multiple agents to finish
- Read and update ticket statuses
- Create worktrees and merge branches
- Check on agent status

Follow the user's instructions for how to execute tickets. They may ask
for sequential or parallel execution, code reviews, specific merge
strategies, or any other workflow. Use your tools to implement whatever
they describe.

Always keep the user informed of progress. When you encounter errors or
need decisions, ask the user rather than guessing.

## Important tool usage patterns

### Merge conflicts
When calling rebase_and_merge() and a conflict occurs, launch an agent
in the conflicted worktree to resolve it:
  rebase_and_merge(worktree) → { success: false, conflicts: true }
  launch_agent(worktree, "A rebase conflict occurred merging this
    branch into its base. Please fix the conflicts and commit.")
  wait_for_agents([conflict-agent])
  rebase_and_merge(worktree) → retry after resolution

### Checking if work is complete
After an agent's turn completes, do not assume the ticket is finished.
Ask the agent to confirm:
  wait_for_agents([agent-A]) → [{ agent-A, turn_complete }]
  ask_agent(agent-A, "Is the ticket fully complete? Are all tests
    passing?") → response
If the agent says it's not done, use tell_agent() to ask it to continue.

### Parallel coordination
Use tell_agent() to send messages without blocking, then wait_for_agents()
to wait for multiple agents at once:
  tell_agent(A, "do X")
  tell_agent(B, "do Y")
  wait_for_agents([A, B]) → whichever finishes first

### Worktree creation
All ticket worktrees should branch from the orchestration base worktree.
The base worktree path is provided in the initial context. Never create
worktrees off of main or other branches unless the user explicitly asks.
```

---

## Orchestrator Toolset

### Agent Lifecycle Tools

#### `launch_agent`

Creates a new chat in a worktree, starts a session, and sends initial instructions.

```
Input:
  worktree: string        — worktree path (must exist)
  instructions: string    — the initial message to send
  ticket_id: int?         — optional ticket to link
  name: string?           — optional chat name (default: auto-generated)

Output:
  agent_id: string        — unique ID for this agent
  chat_id: string         — the underlying chat ID
  worktree: string        — the worktree path

Behavior:
  - Creates a chat in the specified worktree
  - Starts a backend session
  - Sends `instructions` as the first message
  - Links to the ticket if ticket_id provided
  - Returns immediately — the agent is now working
  - If ticket_id provided, sets ticket status to active and links it to this worktree/chat

Example:
  launch_agent(
    worktree: "/projects/cci/tkt-008-user-model",
    instructions: "Implement TKT-008: Design user model schema. See the ticket description for full requirements. Make sure all tests pass before finishing.",
    ticket_id: 8
  ) → { agent_id: "agent-A", chat_id: "abc123", worktree: "/projects/cci/tkt-008-user-model" }
```

#### `tell_agent`

Sends a message to an idle agent. The agent begins working on the message. Does not wait for a response.

```
Input:
  agent_id: string        — agent to message
  message: string         — message to send

Output:
  success: bool

Errors:
  - agent_busy: Agent is currently working. Use wait_for_agents first.
  - agent_not_found: No agent with this ID.
  - agent_stopped: Agent session has ended.

Example:
  tell_agent(agent_id: "agent-A", message: "Code review found issues: Missing null check in UserModel.fromJson. Please fix and ensure tests pass.")
```

#### `ask_agent`

Sends a message to an idle agent and blocks until the agent's turn completes. Returns the agent's response.

```
Input:
  agent_id: string        — agent to message
  message: string         — message to send

Output:
  response: string        — the agent's last assistant message
  is_complete: bool       — whether the agent considers itself done

Errors:
  - agent_busy: Agent is currently working. Use wait_for_agents first.
  - agent_not_found: No agent with this ID.
  - agent_stopped: Agent session has ended.

Behavior:
  - Sends the message via chat.sendMessage()
  - Waits for chat.isWorking to transition false
  - Reads the last assistant message from the conversation
  - Returns the text content

Example:
  ask_agent(agent_id: "agent-C", message: "What is your review verdict?")
  → { response: "APPROVED. Tests pass, code is clean.", is_complete: true }
```

#### `wait_for_agents`

Blocks until at least one of the specified agents finishes its current turn. Returns which agents are now idle and why.

```
Input:
  agent_ids: string[]     — agents to wait on

Output:
  ready: [
    {
      agent_id: string,
      reason: "turn_complete" | "error" | "permission_needed" | "stopped"
    }
  ]

Behavior:
  - If any agent is already idle, returns immediately with those
  - Otherwise, listens for isWorking → false transitions
  - When at least one agent becomes idle, returns all currently-idle agents
  - Includes reason so orchestrator knows why the agent stopped

Example:
  wait_for_agents(agent_ids: ["agent-A", "agent-B"])
  → { ready: [{ agent_id: "agent-A", reason: "turn_complete" }] }
```

#### `check_agents`

Non-blocking status check on an agent.

```
Input:
  agent_id: string

Output:
  status: "working" | "idle" | "error" | "stopped" | "permission_needed"
  is_working: bool
  last_message: string?   — last assistant message (truncated)
  turn_count: int         — number of completed turns
  has_pending_permission: bool

Example:
  check_agents(agent_id: "agent-B")
  → { status: "working", is_working: true, turn_count: 0, has_pending_permission: false }
```

### Ticket Tools

#### `list_tickets`

Lists tickets with optional filtering.

```
Input:
  status: string[]?       — filter by status(es)
  category: string?       — filter by category
  depends_on: int?        — tickets that depend on this ID
  dependency_of: int?     — tickets that this ID depends on (transitive)
  ids: int[]?             — specific ticket IDs

Output:
  tickets: [
    {
      id: int,
      display_id: string,
      title: string,
      status: string,
      kind: string,
      priority: string,
      effort: string,
      category: string?,
      depends_on: int[],
      blocked_by: int[],    — tickets blocking this one (incomplete deps)
      tags: string[]
    }
  ]
```

#### `get_ticket`

Gets full detail for a single ticket.

```
Input:
  ticket_id: int

Output:
  (all fields from list_tickets, plus:)
  description: string
  linked_worktrees: [{ path: string, branch: string }]
  linked_chats: [{ chat_id: string, name: string, worktree: string }]
  cost_stats: { tokens: int, cost: float, agent_time_ms: int }?
```

#### `update_ticket`

Updates ticket status and/or adds a comment.

```
Input:
  ticket_id: int
  status: string?         — new status
  comment: string?        — comment to add (stored in ticket description or log)

Output:
  success: bool
  previous_status: string
  new_status: string
  unblocked_tickets: int[] — tickets that became ready due to this change
```

#### `create_tickets`

Already exists — the `create_ticket` internal tool. Included in the orchestrator's toolset so it can create new tickets (e.g., splitting work, creating review tickets).

### Git & Worktree Tools

#### `create_worktree`

Creates a new linked worktree. The worktree is branched from the specified base ref.

```
Input:
  branch_name: string     — branch to create
  base_ref: string?       — base branch (default: the orchestrator's base worktree branch)

Output:
  worktree_path: string
  branch: string

Behavior:
  - Delegates to WorktreeService.createWorktree()
  - Adds worktree to the project
  - Returns the path for use in launch_agent
  - The default base_ref is the branch of the worktree the orchestrator chat lives in

Example:
  create_worktree(branch_name: "tkt-008-user-model")
  → { worktree_path: "/projects/cci/tkt-008-user-model", branch: "tkt-008-user-model" }
```

#### `rebase_and_merge`

Rebases a worktree's branch onto its base and fast-forward merges into the base branch. The target is always the worktree's configured base ref (set at creation time) — there is no option to specify a different target, because worktrees always merge back to where they branched from.

```
Input:
  worktree_path: string   — the worktree to merge

Output:
  success: bool
  conflicts: bool
  conflict_files: string[]?
  merged_commits: int     — number of commits merged

Behavior:
  1. Determine the worktree's base branch (from worktree metadata)
  2. Rebase worktree branch onto latest base
  3. If conflicts → return { success: false, conflicts: true, conflict_files }
  4. If clean → fast-forward merge into base branch, return success

Conflict resolution pattern:
  rebase_and_merge(worktree) → { success: false, conflicts: true, conflict_files: ["src/model.dart"] }
  launch_agent(worktree, "A rebase conflict occurred merging this branch into its base. Please resolve the conflicts in: src/model.dart. Then commit the resolution.")
  wait_for_agents([conflict-resolver])
  rebase_and_merge(worktree) → { success: true, merged_commits: 4 }

Example:
  rebase_and_merge(worktree_path: "/projects/cci/tkt-008-user-model")
  → { success: true, conflicts: false, merged_commits: 3 }
```

#### `delete_worktree`

Removes a linked worktree and optionally deletes the branch.

```
Input:
  worktree_path: string
  delete_branch: bool?    — also delete the branch (default: false)

Output:
  success: bool
```

---

## Example Workflows

### Example 1: Parallel Execution with Code Review (launched from ticket screen)

**User selects TKT-008 through TKT-012 in the ticket screen, clicks "Run...", enters feature branch name `feat-auth-system`, and writes:**

> Use separate worktrees for each ticket. Run independent tickets in parallel. After each one finishes, have a different agent do a code review. If there are issues, send them back to the original agent. Keep going until the review passes. Merge each completed ticket into the feature branch.

**The dialog creates worktree `feat-auth-system` off `main`, opens the orchestrator chat in it.**

**Orchestrator behavior:**

```
list_tickets(ids: [8, 9, 10, 11, 12])
  → Dependencies: TKT-012→[TKT-010,TKT-011], TKT-010→[TKT-008], TKT-011→[TKT-008,TKT-009]

"Starting with independent tickets TKT-008 and TKT-009."

create_worktree("tkt-008-user-model")                   → /path/tkt-008  (branches off feat-auth-system)
create_worktree("tkt-009-auth-routes")                   → /path/tkt-009  (branches off feat-auth-system)
launch_agent(tkt-008, "Implement TKT-008...", ticket: 8) → agent-A
launch_agent(tkt-009, "Implement TKT-009...", ticket: 9) → agent-B
update_ticket(8, status: "active")
update_ticket(9, status: "active")

"Both agents working. Waiting..."

wait_for_agents([A, B]) → [{ A, turn_complete }]

"Agent-A finished. Checking if work is complete."

ask_agent(A, "Is TKT-008 fully complete? Tests passing?") → "Yes, all done."

"Launching code review for TKT-008."

launch_agent(tkt-008, "Review the changes for TKT-008...", ticket: 8) → agent-C
wait_for_agents([B, C]) → [{ C, turn_complete }]
ask_agent(C, "What is your verdict?") → "APPROVED. Code is clean, tests pass."

"TKT-008 review passed. Merging into feat-auth-system."

rebase_and_merge(tkt-008) → { success: true, merged: 3 }
update_ticket(8, status: "completed", comment: "Merged. Review passed in 1 round.")
delete_worktree(tkt-008)

"TKT-008 done. TKT-010 is now unblocked — but TKT-011 still needs TKT-009.
 Waiting for agent-B..."

wait_for_agents([B]) → [{ B, turn_complete }]

ask_agent(B, "Is TKT-009 fully complete?") → "Yes."

"Launching review for TKT-009."

launch_agent(tkt-009, "Review changes for TKT-009...", ticket: 9) → agent-D
wait_for_agents([D]) → [{ D, turn_complete }]
ask_agent(D, "Verdict?") → "CHANGES_NEEDED: Missing error handling in /auth/login endpoint."

"Review found issues. Sending feedback to agent-B."

tell_agent(B, "Code review feedback: Missing error handling in /auth/login. Please fix.")
wait_for_agents([B]) → [{ B, turn_complete }]

"Fixes applied. Re-reviewing..."

tell_agent(D, "The implementer has addressed your feedback. Please re-review.")
wait_for_agents([D]) → [{ D, turn_complete }]
ask_agent(D, "Verdict?") → "APPROVED. Error handling added correctly."

rebase_and_merge(tkt-009) → { success: true }
update_ticket(9, status: "completed", comment: "Merged. Review passed in 2 rounds.")

"TKT-008 and TKT-009 both done. TKT-010 and TKT-011 are now unblocked."

(... continues with TKT-010, TKT-011, then TKT-012, all merging into feat-auth-system ...)

"All 5 tickets complete. The feat-auth-system branch now contains all the work.
 You can review it and open a PR when ready."
```

### Example 2: Sequential Execution, No Reviews

**User prompt:**
> Work through all ready tickets in order. Do them one at a time in this worktree. No code reviews needed, just mark each one done when the agent finishes.

**Orchestrator behavior:**

```
list_tickets(status: ["ready"])
  → [TKT-005, TKT-006, TKT-009] (sorted by dependency order, then priority)

"Starting with TKT-005 — no unmet dependencies."

launch_agent(base_worktree, "Implement TKT-005...", ticket: 5)  → agent-A
update_ticket(5, status: "active")
wait_for_agents([A]) → [{ A, turn_complete }]
ask_agent(A, "Is the ticket fully implemented? Tests passing?") → "Yes, all changes committed and tests passing."
update_ticket(5, status: "completed")

"TKT-005 done. Next: TKT-006."

launch_agent(base_worktree, "Implement TKT-006...", ticket: 6)  → agent-B
update_ticket(6, status: "active")
wait_for_agents([B]) → [{ B, turn_complete }]
ask_agent(B, "Is the ticket fully implemented?") → "Yes."
update_ticket(6, status: "completed")

"TKT-006 done. Next: TKT-009."
(... continues ...)
```

### Example 3: Targeted Feature Completion

**User prompt:**
> I need TKT-020 done ASAP. Check what it depends on, do whatever isn't done yet, then do TKT-020 itself. Use parallel worktrees where possible. Skip reviews for small tickets.

**Orchestrator behavior:**

```
get_ticket(20)
  → TKT-020: "Implement search API", depends_on: [15, 17, 18]

get_ticket(15) → status: completed ✓
get_ticket(17) → status: ready, effort: small
get_ticket(18) → status: ready, effort: medium, depends_on: [16]
get_ticket(16) → status: ready, effort: small

"TKT-020 depends on TKT-015 (done), TKT-017 (ready), and TKT-018 (ready,
 depends on TKT-016). Starting TKT-016 and TKT-017 in parallel."

create_worktree("tkt-016-index-config") → wt-016
create_worktree("tkt-017-query-parser") → wt-017
launch_agent(wt-016, "...", ticket: 16) → agent-A
launch_agent(wt-017, "...", ticket: 17) → agent-B

wait_for_agents([A, B]) → [{ A, turn_complete }, { B, turn_complete }]

"Both done. TKT-016 and TKT-017 are small — skipping reviews per your instructions."

rebase_and_merge(wt-016) → success
rebase_and_merge(wt-017) → success
update_ticket(16, status: "completed")
update_ticket(17, status: "completed")

"TKT-018 unblocked. Starting it now."

create_worktree("tkt-018-search-index") → wt-018
launch_agent(wt-018, "...", ticket: 18) → agent-A

wait_for_agents([A]) → [{ A, turn_complete }]
ask_agent(A, "Fully complete?") → "Yes."

"TKT-018 is medium effort. Launching review."

launch_agent(wt-018, "Review changes for TKT-018...", ticket: 18) → agent-B
wait_for_agents([B]) → [{ B, turn_complete }]
ask_agent(B, "Verdict?") → "APPROVED."

rebase_and_merge(wt-018) → success
update_ticket(18, status: "completed")

"All dependencies met. Starting TKT-020."

create_worktree("tkt-020-search-api") → wt-020
launch_agent(wt-020, "...", ticket: 20) → agent-A

(... implement, review, merge ...)
```

### Example 4: Mixed Manual and Automated

**User prompt:**
> Run TKT-010 through TKT-014 automatically with reviews. But for TKT-012 (the database migration), don't let the agent run it — just have it write the migration file and stop. I'll review that one manually.

**Orchestrator behavior:**

```
(runs TKT-010, TKT-011, TKT-013, TKT-014 with full review cycles)

(for TKT-012:)
launch_agent(wt-012, "Write the database migration for TKT-012.
  Create the migration file but do NOT run it. Stop after writing
  the file and tell me what you created.", ticket: 12)

wait_for_agents([agent-012]) → turn_complete
ask_agent(agent-012, "What migration file did you create?")
  → "Created migrations/002_add_search_index.sql with..."

update_ticket(12, status: "needsInput", comment: "Migration file created. Waiting for manual review.")

"TKT-012: Migration file written. I've paused this ticket for your manual
 review. Let me know when you're ready to continue."
```

### Example 5: Merge Conflict Resolution

**Orchestrator merging a ticket branch and hitting a conflict:**

```
rebase_and_merge(wt-009) → { success: false, conflicts: true, conflict_files: ["src/auth/routes.dart", "test/auth_test.dart"] }

"Merge conflict in TKT-009. Launching an agent to resolve it."

launch_agent(wt-009, "A rebase conflict occurred merging this branch into its base. Please resolve the conflicts in: src/auth/routes.dart, test/auth_test.dart. Examine both versions, resolve correctly, and commit.") → agent-E

wait_for_agents([E]) → [{ E, turn_complete }]
ask_agent(E, "Are the conflicts resolved?") → "Yes, resolved and committed."

rebase_and_merge(wt-009) → { success: true, merged_commits: 5 }

"Conflict resolved. TKT-009 merged successfully."
```

### Example 6: Resume After Failure

**User prompt:**
> The merge for TKT-009 failed with conflicts last time. I've resolved them manually. Continue the run — pick up where we left off.

**Orchestrator behavior:**

```
list_tickets(status: ["active", "inReview"])
  → TKT-009 (active, linked to wt-009)

"I see TKT-009 is still active in worktree wt-009. Let me check the status."

check_agents(agent-for-009) → stopped (previous session ended)

"Previous agent has stopped. Let me verify the conflict is resolved and merge."

rebase_and_merge(wt-009) → { success: true }
update_ticket(9, status: "completed")

"TKT-009 merged successfully. Checking what's next..."

list_tickets(status: ["ready", "blocked"])
  → TKT-011 now ready (was blocked on TKT-009)

(... continues ...)
```

---

## UI Components

### Orchestrator Launch Button

Added to the ticket list panel toolbar — a "Run..." button (or play icon). Appears next to the existing "Start Next" button.

**Behavior:**
1. If tickets are selected (via checkboxes), the button label is "Run N Tickets..."
2. If no selection, the button label is "Run All Ready..."
3. Clicking opens the orchestration configuration dialog

### Orchestration Configuration Dialog

A dialog that sets up the orchestration run — creating a feature worktree, collecting instructions, and launching the orchestrator chat.

**Contents:**
- **Ticket summary**: List of tickets that will be included (with dependency info, status icons, effort badges)
- **Feature branch name**: Text field for the base worktree branch name (e.g., `feat-auth-system`). Auto-suggested from the ticket titles/category.
- **Base branch**: Selector for what the feature branch is created from (default: `main`)
- **Instructions text field**: Large text area where the user describes their strategy. Pre-populated with a sensible default based on the selected tickets.
- **Quick presets** (optional shortcuts that populate the instructions field):
  - "Parallel with reviews" → fills in standard parallel + review instructions
  - "Sequential, no reviews" → fills in sequential instructions
  - "Parallel, no reviews" → fills in parallel-only instructions
- **Launch button**: Creates the base worktree, creates an orchestrator chat in it, navigates to the main screen

The presets are convenience — the user can always edit the instructions or write their own from scratch.

### Orchestrator Chat

Visually identical to a normal chat. The orchestrator's tool calls appear as tool cards in the conversation, just like any other agent's tool usage. The user can:

- Read the orchestrator's reasoning between tool calls
- See tool inputs and outputs
- Type messages to intervene or adjust the strategy
- Use the interrupt button to pause the orchestrator

### Progress Summary Widget

A compact, collapsible widget **docked at the top of the orchestrator's conversation panel**. It is always visible when viewing the orchestrator chat. Provides at-a-glance status for the ticket set being orchestrated.

**The widget knows about all the tickets in the orchestration run** (the set passed from the config dialog). It reads ticket status from `TicketBoardState` and agent status from `OrchestratorState` to show live progress without the orchestrator agent needing to explicitly update it.

**Contents:**
- **Progress bar**: N/M tickets complete (segmented: done/reviewing/implementing/pending)
- **Ticket pipeline**: Small pills/chips showing each ticket's current phase
  - Color-coded: grey (pending), blue (implementing), purple (reviewing), orange (needs input), green (done), red (failed)
  - Clicking a pill navigates to that ticket's worker chat
- **Stats**: Elapsed time, total cost so far
- **Active agents**: Count of currently-running agents
- **Collapsed mode**: Shows mini dots + summary count + cost on a single line

### Ticket List Integration

- **Multi-select mode**: Checkboxes appear on ticket items when the "Run..." flow is active
- **Running indicator**: Tickets being managed by an orchestrator show a distinct icon or badge (e.g., a small orchestrator icon overlay) so the user knows they're part of an automated run
- **Status updates**: As the orchestrator updates ticket statuses via `update_ticket`, the ticket list reflects changes in real time (already works via ChangeNotifier)

---

## Implementation Plan

### Phase 1: Orchestrator Tools (Core)

**Goal**: Implement the internal tools that the orchestrator agent will use.

#### 1a. Agent Tracking Infrastructure

- Create `OrchestratorState` (ChangeNotifier) to track managed agents and the ticket set
  - Map of agent ID → `ManagedAgent` (chat reference, ticket ID, status)
  - Set of ticket IDs being orchestrated (for the progress widget)
  - Methods: `registerAgent()`, `unregisterAgent()`, `getAgent()`
- Agent IDs are orchestrator-scoped strings (e.g., "agent-A", "agent-1")
- State is per-orchestrator-chat (each orchestrator manages its own agents)
- Stores the base worktree path (for default base_ref in create_worktree)

**Files:**
- `frontend/lib/state/orchestrator_state.dart` (new)

#### 1b. Agent Lifecycle Tools

Implement `launch_agent`, `tell_agent`, `ask_agent`, `wait_for_agents`, `check_agents` as internal tool handlers.

- `launch_agent`: Uses `TicketDispatchService` patterns (create chat, start session, send message)
- `tell_agent`: Calls `chat.sendMessage()`, returns immediately. Errors if `chat.isWorking`.
- `ask_agent`: Calls `chat.sendMessage()`, awaits `isWorking → false`, reads last message. Errors if `chat.isWorking`.
- `wait_for_agents`: Listens to chat `isWorking` changes via ChangeNotifier, resolves when any becomes idle. Also checks for pending permissions and errors. Returns reasons.
- `check_agents`: Reads current chat state, returns status snapshot

Each tool returns a `Future<InternalToolResult>` — long-running tools (ask_agent, wait_for_agents) use Completers that resolve when the condition is met, same pattern as `create_ticket`.

**Files:**
- `frontend/lib/services/internal_tools_service.dart` (extend with new tools)

#### 1c. Ticket & Git Tools

Implement `list_tickets`, `get_ticket`, `update_ticket`, `create_worktree`, `rebase_and_merge`, `delete_worktree` as internal tool handlers.

- Ticket tools: Thin wrappers around `TicketBoardState` methods
- `create_worktree`: Wrapper around `WorktreeService.createWorktree()`. Default base_ref from orchestrator's base worktree branch.
- `rebase_and_merge`: Uses the worktree's base ref (no target parameter). Orchestrates `GitService.rebase()` → fast-forward merge.
- `delete_worktree`: Wrapper around `WorktreeService.removeWorktree()`

**Files:**
- `frontend/lib/services/internal_tools_service.dart` (extend)

### Phase 2: Orchestrator Chat Setup

**Goal**: Wire up the orchestrator as a special chat with the right system prompt and tools.

#### 2a. Orchestrator Chat Creation

- Add method to create an orchestrator chat in a worktree
- Set the system prompt for orchestration
- Register orchestrator-specific tools on the session
- Create and attach `OrchestratorState` to the chat
- Pass the ticket set to `OrchestratorState` (for the progress widget)
- Pass the base worktree path (for default create_worktree base)

**Files:**
- `frontend/lib/services/ticket_dispatch_service.dart` (extend)
- `frontend/lib/state/orchestrator_state.dart` (extend)

#### 2b. Tool Registration & Gating

- Define which tools are available to orchestrator chats vs. normal chats
- Orchestrator tools are only registered when a chat is created as an orchestrator
- Normal chats continue to have only `create_ticket` (and any other existing tools)
- Add a toggle in chat settings for advanced users to enable orchestration tools on any chat

**Files:**
- `frontend/lib/services/internal_tools_service.dart` (tool registration logic)

### Phase 3: UI — Launch Flow

**Goal**: Let users initiate orchestration from the ticket screen.

#### 3a. Ticket Multi-Select

- Add checkbox mode to `TicketListPanel`
- Track selected ticket IDs in `TicketBoardState`
- "Run..." button in toolbar that opens the config dialog

**Files:**
- `frontend/lib/panels/ticket_list_panel.dart` (extend)
- `frontend/lib/state/ticket_board_state.dart` (extend)

#### 3b. Orchestration Config Dialog

- Build the configuration dialog
- Ticket summary, feature branch name, base branch selector, instructions text area, presets
- On launch: creates base worktree via WorktreeService, creates orchestrator chat, navigates to main screen

**Files:**
- `frontend/lib/widgets/orchestration_config_dialog.dart` (new)

### Phase 4: UI — Progress & Monitoring

**Goal**: Give users visibility into the orchestration run.

#### 4a. Progress Summary Widget

- Compact widget docked at top of orchestrator's conversation panel
- Reads ticket set from `OrchestratorState`, ticket status from `TicketBoardState`
- Shows progress bar, pipeline pills, agent count, cost, elapsed time
- Clickable pills navigate to worker chats
- Collapsible/expandable

**Files:**
- `frontend/lib/widgets/orchestration_progress.dart` (new)
- `frontend/lib/panels/conversation_panel.dart` (extend to show widget when orchestrator chat)

#### 4b. Ticket List Running Indicators

- Show orchestrator badge on tickets being managed
- Distinguish "active (manual)" from "active (orchestrated)"

**Files:**
- `frontend/lib/panels/ticket_list_panel.dart` (extend)
- `frontend/lib/widgets/ticket_visuals.dart` (extend)

### Phase 5: Polish & Edge Cases

- Handle orchestrator chat interrupted/closed (graceful cleanup of managed agents)
- Handle worker agent crashes (detect via check_agents, report to orchestrator)
- Resume support (orchestrator chat can be resumed, re-discovers managed agents)
- Cost aggregation across all managed agents
- Orchestrator-level permission handling (if a worker needs permission, wait_for_agents reports it)
- System prompt iteration based on real-world testing (will need tuning)

---

## Mockups

See `docs/mocks/` for interactive HTML mockups:

| File | Description |
|------|-------------|
| `orchestration-config-mock.html` | Configuration dialog with ticket summary, feature branch name, instructions, and presets |
| `orchestration-progress-mock.html` | Progress summary widget showing ticket pipeline and stats |
| `orchestrator-conversation-mock.html` | Orchestrator chat showing tool calls and reasoning |

---

## Open Questions

1. **Orchestrator model**: Should the orchestrator use the same model as worker agents, or a cheaper/faster model? It mostly does tool calls and coordination, not heavy coding.

2. **Concurrent orchestrators**: Can the user run multiple orchestrations simultaneously? Probably yes (each is just a chat), but need to handle ticket contention (two orchestrators trying to work on the same ticket).

3. **Cost limits**: Should the orchestrator have a cost budget? Users might want to say "spend no more than $10 on this run." The orchestrator could track cumulative cost via `check_agents` and stop when the budget is hit.

4. **Worker model selection**: Should the orchestrator be able to choose different models for different tickets? E.g., use a cheaper model for small/chore tickets and a more capable model for complex features.

5. **Worktree reuse**: In parallel mode, after a ticket is merged and its worktree deleted, should the orchestrator reuse that worktree's disk location for the next ticket, or always create fresh? Fresh is simpler; reuse saves disk space.

6. **System prompt tuning**: The orchestrator system prompt will need iteration based on real-world testing. The examples in this doc represent ideal behavior — actual LLM behavior may need additional guidance, guardrails, or tool usage hints. This should be expected and budgeted for.
