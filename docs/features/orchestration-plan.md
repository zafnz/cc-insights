# Ticket Orchestration — Implementation Plan

This document breaks down the orchestration feature into granular, independently-completable tasks. Each task is designed to be implemented by one agent, reviewed by another, and iterated until approved.

## Overview

The orchestration system requires:
1. **Agent tracking infrastructure** — maintain state of managed agents
2. **Internal tools** — 11 tools for agent lifecycle, tickets, and git operations
3. **Tool gating** — ensure orchestration tools only exist on orchestrator chats
4. **Orchestrator chat setup** — system prompt, tool registration, special treatment
5. **UI launch flow** — dialog, multi-select, base worktree creation
6. **Progress widget** — docked display of orchestration status
7. **Polish & integration** — error handling, resume support, edge cases

---

## Phase 1: Infrastructure & Core Tools

### Task 1.1: Create OrchestratorState

**Objective**: Build the state class that tracks managed agents and the ticket set being orchestrated.

**Implementation**:
- Create `frontend/lib/state/orchestrator_state.dart`
- Extends `ChangeNotifier`
- Fields:
  - `_agents`: Map<String, ManagedAgent> — agent ID → chat + ticket
  - `_ticketIds`: Set<int> — full set of tickets being orchestrated
  - `_baseWorktreePath`: String — path to the orchestration base worktree
  - `_orchestrationStartTime`: DateTime
- Methods:
  - `registerAgent(agentId, ChatState, int? ticketId)` → registers and notifies
  - `unregisterAgent(agentId)` → removes and notifies
  - `getAgent(agentId)` → looks up agent
  - `getElapsedTime()` → Duration since start
  - `getProgress()` → (completed, total) tuple computed from ticket status

**Tests**:
- Test agent registration/unregistration with notification
- Test duplicate registration errors
- Test lookup of non-existent agent returns null
- Test elapsed time increases correctly
- Test progress computation reflects ticket board changes

**Definition of Success**:
- ✅ All methods implemented
- ✅ Unit tests pass
- ✅ ChangeNotifier properly notifies on state changes
- ✅ No memory leaks (agents removed when unregistered)

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.2: Implement Agent Lifecycle Tools — `launch_agent`

**Objective**: Create the tool that launches a new agent in a worktree with initial instructions.

**Implementation**:
- Add handler in `frontend/lib/services/internal_tools_service.dart`
- Tool definition with input schema (worktree, instructions, ticket_id?, name?)
- Handler implementation:
  1. Validate worktree exists
  2. Use `TicketDispatchService.beginInWorktree()` pattern (but don't dispatch a ticket — just create chat)
  3. Create chat in worktree (or reuse existing if sequential mode)
  4. Start session
  5. Send instructions as first message
  6. Register agent in OrchestratorState
  7. If ticket_id provided: set ticket status to active, link worktree + chat
  8. Return agent_id, chat_id, worktree

**Tests**:
- Test successful launch with all parameters
- Test launch with missing optional parameters
- Test worktree doesn't exist error
- Test chat creation and session start
- Test ticket linking when ticket_id provided
- Test proper agent_id generation

**Definition of Success**:
- ✅ Agent launches and begins working
- ✅ Chat appears in the worktree's chat list
- ✅ Ticket is marked active and linked
- ✅ First message (instructions) is in the chat history

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.3: Implement Agent Lifecycle Tools — `tell_agent`

**Objective**: Fire-and-forget message sending to an idle agent.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: agent_id, message
- Output: success bool
- Handler:
  1. Look up agent from OrchestratorState
  2. Error if agent not found or already working (`chat.isWorking == true`)
  3. Call `chat.sendMessage(message)`
  4. Return success
  5. Return immediately (don't wait)

**Tests**:
- Test successful message send to idle agent
- Test error when agent is busy
- Test error when agent not found
- Test error when agent stopped (session ended)

**Definition of Success**:
- ✅ Message delivered to correct agent
- ✅ Proper error handling for all failure cases
- ✅ Doesn't block

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.4: Implement Agent Lifecycle Tools — `ask_agent`

**Objective**: Blocking message send with response collection.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: agent_id, message
- Output: response (string), is_complete (bool)
- Handler:
  1. Look up agent
  2. Error if agent busy or not found
  3. Call `chat.sendMessage(message)`
  4. Create Completer that waits for `chat.isWorking` to become false
  5. Return immediately with Future
  6. When turn completes, read last assistant message
  7. Resolve with response text
- Handle message parsing: assume the last assistant content block is the response

**Tests**:
- Test successful message + response cycle
- Test error when agent busy
- Test response extraction from conversation
- Test long-running agent (waits for turn completion)
- Test partial messages streaming doesn't prematurely complete

**Definition of Success**:
- ✅ Blocks until agent's turn completes
- ✅ Returns agent's full response
- ✅ Proper error handling

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.5: Implement Agent Lifecycle Tools — `wait_for_agents`

**Objective**: Wait for any of multiple agents to finish.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: agent_ids (string[])
- Output: ready ([{ agent_id, reason }])
  - reason: "turn_complete" | "error" | "permission_needed" | "stopped"
- Handler:
  1. Look up all agents
  2. Check which are already idle (not isWorking) → add to ready list
  3. If any ready, return immediately
  4. Otherwise, create listeners on all agent chat's `isWorking` changes
  5. Create Completer that fires when any agent stops working
  6. When fires, collect all currently-idle agents + reasons
  7. Return list

**Tests**:
- Test returns immediately if any agent already idle
- Test waits and returns when agent becomes idle
- Test multiple agents — returns first one(s) to finish
- Test collects all idle agents at that moment
- Test reason detection (turn_complete vs permission vs error)

**Definition of Success**:
- ✅ Blocks until at least one agent idle
- ✅ Returns all currently-idle agents
- ✅ Includes accurate reasons

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.6: Implement Agent Lifecycle Tools — `check_agents`

**Objective**: Non-blocking status snapshot of an agent.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: agent_id
- Output: { status, is_working, last_message?, turn_count, has_pending_permission }
- Handler:
  1. Look up agent
  2. Read chat state:
     - is_working = chat.isWorking
     - status = working | idle | error | stopped | permission_needed
     - last_message = last assistant message (truncated to 100 chars)
     - turn_count = chat conversation entries count / 2 (rough)
     - has_pending_permission = chat.pendingPermission != null
  3. Return snapshot

**Tests**:
- Test working agent shows correct status
- Test idle agent status
- Test permission pending detected
- Test last message extraction
- Test agent not found error

**Definition of Success**:
- ✅ Accurate status snapshot
- ✅ No blocking
- ✅ Proper error handling

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.7: Implement Ticket Tools — `list_tickets` & `get_ticket`

**Objective**: Thin wrappers around TicketBoardState for agent to query tickets.

**Implementation**:
- Add handlers in `internal_tools_service.dart`
- `list_tickets`:
  - Input: status[]?, category?, depends_on?, dependency_of?, ids[]?
  - Output: tickets (array of ticket summaries)
  - Filter TicketBoardState.tickets by criteria
- `get_ticket`:
  - Input: ticket_id
  - Output: full TicketData + computed fields (unblocked_by)
  - Look up single ticket

**Tests**:
- Test list with no filters returns all tickets
- Test filter by status
- Test filter by category
- Test filter by dependency relationships
- Test get_ticket returns full data
- Test get_ticket not found error

**Definition of Success**:
- ✅ Agent can query current ticket state
- ✅ Filters work correctly
- ✅ Computed dependency info accurate

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.8: Implement Ticket Tools — `update_ticket`

**Objective**: Allow orchestrator to update ticket status and add comments.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: ticket_id, status?, comment?
- Output: { success, previous_status, new_status, unblocked_tickets[] }
- Handler:
  1. Look up ticket
  2. If status provided: call TicketBoardState.updateTicketStatus()
  3. This triggers auto-unblocking logic (existing)
  4. If comment: append to ticket description or add a comment field
  5. Return previous/new status + list of tickets that became ready

**Tests**:
- Test status update to each valid state
- Test comment addition
- Test auto-unblocking triggers correctly
- Test invalid status error
- Test ticket not found error

**Definition of Success**:
- ✅ Ticket status changes atomically
- ✅ Dependents auto-unblock
- ✅ Comments recorded
- ✅ Accurate feedback on what changed

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.9: Implement Git Tools — `create_worktree`

**Objective**: Wrapper for WorktreeService with orchestrator-aware defaults.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: branch_name, base_ref?
- Output: { worktree_path, branch }
- Handler:
  1. If base_ref not provided: use OrchestratorState.baseWorktreePath's branch as default
  2. Call WorktreeService.createWorktree(branch_name, base_ref)
  3. Return path and branch
- If orchestrator has no base worktree (ad-hoc mode): error or use project main

**Tests**:
- Test successful worktree creation
- Test default base_ref from orchestrator state
- Test custom base_ref
- Test invalid branch name error
- Test ad-hoc mode (no orchestrator base)

**Definition of Success**:
- ✅ Worktree created with correct branch
- ✅ Default base_ref sensible
- ✅ Integrated with existing WorktreeService

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.10: Implement Git Tools — `rebase_and_merge`

**Objective**: Rebase worktree onto its base and merge, with conflict detection.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: worktree_path
- Output: { success, conflicts, conflict_files[]?, merged_commits }
- Handler:
  1. Get worktree from project by path
  2. Get its base_ref from WorktreeData
  3. Call GitService.fetch(base_ref) to get latest
  4. Call GitService.rebase(worktree, base_ref)
  5. If conflicts returned:
     - Return { success: false, conflicts: true, conflict_files: [...] }
  6. If clean:
     - Checkout base_ref in worktree
     - Fast-forward merge (or regular merge if not FF)
     - Return success with commit count

**Tests**:
- Test successful clean rebase + merge
- Test conflict detection
- Test conflict_files extracted correctly
- Test merged_commits counted
- Test worktree not found error
- Test base branch not found error

**Definition of Success**:
- ✅ Clean merges work end-to-end
- ✅ Conflicts detected and reported
- ✅ Commit count accurate
- ✅ Orchestrator can handle conflict response pattern

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 1.11: Implement Git Tools — `delete_worktree`

**Objective**: Clean up a worktree after merge.

**Implementation**:
- Add handler in `internal_tools_service.dart`
- Input: worktree_path, delete_branch?
- Output: { success }
- Handler:
  1. Call WorktreeService.removeWorktree(worktree_path, delete_branch)
  2. Return success

**Tests**:
- Test successful worktree deletion
- Test branch preserved by default
- Test branch deleted when requested
- Test worktree not found error

**Definition of Success**:
- ✅ Worktree removed
- ✅ Branch handling correct

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Phase 2: Tool Registration & Gating

### Task 2.1: Define Tool Gating in InternalToolsService

**Objective**: Separate orchestration tools from normal tools so agents can't accidentally use them.

**Implementation**:
- In `internal_tools_service.dart`, define two sets of tools:
  - `normalTools` — includes create_ticket only
  - `orchestratorTools` — includes all 11 tools + create_ticket
- Add method: `getToolsForChat(ChatState) → List<InternalToolDefinition>`
  - If chat is orchestrator → return orchestratorTools
  - Else → return normalTools
- Add method: `isOrchestratorChat(ChatState) → bool`
  - Check if chat has a linked OrchestratorState

**Tests**:
- Test normal chat gets only create_ticket
- Test orchestrator chat gets all tools
- Test tool registration respects the set

**Definition of Success**:
- ✅ Normal agents can't access orchestration tools
- ✅ Orchestrator has full toolset
- ✅ No tool leakage

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 2.2: Add Orchestration Tools Toggle to Chat Settings

**Objective**: Advanced users can enable orchestration tools on any chat.

**Implementation**:
- Add toggle in chat settings: "Enable orchestration tools"
- When enabled: mark chat as "manually orchestration-enabled"
- Modify `getToolsForChat()` to check this flag too
- Warning: remind user this is for advanced use

**Tests**:
- Test toggle enables tools
- Test toggle persists
- Test toggle can be disabled
- Test warning shown

**Definition of Success**:
- ✅ Toggle works
- ✅ Tools available when enabled
- ✅ User understands implications

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Phase 3: Orchestrator Chat Setup

### Task 3.1: Create Orchestrator Chat Creation Method

**Objective**: Set up the orchestrator chat with system prompt and tools.

**Implementation**:
- Add method to `TicketDispatchService`: `createOrchestratorChat(worktreeState, ticketIds[], initialInstructions) → ChatState`
- Handler:
  1. Create a new ChatState in the worktree
  2. Set name to "Orchestrator" or similar
  3. Create and attach OrchestratorState (with ticketIds set)
  4. Store base worktree path in OrchestratorState
  5. Register orchestration tools on the session (during backend setup)
  6. Set system prompt to orchestrator prompt (from feature doc)
  7. Set draft text to initialInstructions
  8. Return ChatState

**Tests**:
- Test chat created correctly
- Test OrchestratorState attached
- Test tools registered
- Test system prompt set
- Test draft text set

**Definition of Success**:
- ✅ Orchestrator chat ready to launch
- ✅ Tools available
- ✅ System prompt in place

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 3.2: Orchestrator System Prompt Implementation

**Objective**: Define and store the orchestrator system prompt.

**Implementation**:
- Create constant in `orchestration_prompts.dart` or similar
- System prompt as documented in `docs/features/orchestration.md`
- Include tool usage patterns section
- Pass to backend session on creation

**Tests**:
- Test prompt contains all required sections
- Test prompt is used when creating orchestrator chat
- Test prompt doesn't interfere with normal chats

**Definition of Success**:
- ✅ Prompt defined
- ✅ Used in orchestrator chats
- ✅ Not leaked to normal chats

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Phase 4: UI — Launch Flow

### Task 4.1: Add Multi-Select to TicketListPanel

**Objective**: Users can select multiple tickets before launching orchestration.

**Implementation**:
- Add checkbox mode toggle to TicketListPanel
- When enabled: show checkboxes on ticket items
- Track selected IDs in TicketBoardState
- Update "Run..." button to reflect selected count
- Add context menu option: "Select all", "Deselect all"

**Tests**:
- Test individual ticket selection
- Test select/deselect all
- Test selection persists during scrolling
- Test selected count displayed

**Definition of Success**:
- ✅ Users can select multiple tickets
- ✅ Selection UI clear
- ✅ Count shown in button

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 4.2: Build Orchestration Config Dialog

**Objective**: Dialog to set up base worktree, branch name, and instructions.

**Implementation**:
- Create `OrchestrationConfigDialog` widget
- Shows ticket summary (as designed in mock)
- Base branch selector
- Feature branch name field (auto-suggested from tickets)
- Instructions text area with presets
- Launch button
- On launch:
  1. Create base worktree with branch name
  2. Create orchestrator chat in that worktree
  3. Pass ticketIds + instructions to orchestrator
  4. Navigate to main screen + open chat

**Tests**:
- Test dialog displays tickets
- Test base branch selector works
- Test branch name field accepts input
- Test presets populate instructions
- Test launch creates worktree + chat
- Test navigation to main screen

**Definition of Success**:
- ✅ Dialog UI functional and polished
- ✅ Base worktree created
- ✅ Orchestrator chat opened
- ✅ User can interact immediately

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 4.3: Add "Run..." Button to Ticket List Toolbar

**Objective**: Entry point for orchestration from ticket screen.

**Implementation**:
- Add button to TicketListPanel toolbar
- Label: "Run N Tickets..." or "Run All Ready..."
- Clicking opens OrchestrationConfigDialog
- Pass selected tickets to dialog

**Tests**:
- Test button shows correct label
- Test button enables/disables based on selection
- Test clicking opens dialog
- Test selected tickets shown in dialog

**Definition of Success**:
- ✅ Button discoverable
- ✅ Dialog opens with correct tickets

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Phase 5: Progress Widget & Monitoring

### Task 5.1: Build OrchestrationProgressWidget

**Objective**: Docked widget at top of orchestrator chat showing live progress.

**Implementation**:
- Create `OrchestrationProgressWidget` widget
- Reads from OrchestratorState + TicketBoardState
- Displays:
  - Progress bar (N/M tickets complete, segmented by phase)
  - Ticket pipeline pills (color-coded by phase)
  - Elapsed time
  - Cost summary
  - Active agent count
- Collapsible/expandable
- Clicking ticket pill navigates to that ticket's worker chat
- Updates reactively as orchestrator makes progress

**Tests**:
- Test progress bar reflects ticket status
- Test pills are color-coded correctly
- Test stats (time, cost, agents) update
- Test collapse/expand
- Test navigation on pill click

**Definition of Success**:
- ✅ Widget displays accurate progress
- ✅ Looks polished
- ✅ Responsive to state changes

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 5.2: Dock Progress Widget in ConversationPanel

**Objective**: Show progress widget at top of orchestrator chat.

**Implementation**:
- In ConversationPanel, detect if viewing orchestrator chat
- If yes: add OrchestrationProgressWidget above messages
- If no: don't show
- Pass OrchestratorState to widget

**Tests**:
- Test widget appears for orchestrator chat
- Test widget hidden for normal chat
- Test widget positioned correctly

**Definition of Success**:
- ✅ Progress visible to user
- ✅ Doesn't interfere with normal chats

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 5.3: Add Orchestrator Badge to Ticket List

**Objective**: Show which tickets are being managed by an orchestrator.

**Implementation**:
- Detect if ticket is in any OrchestratorState's ticketIds set
- If yes: show small "orchestrator" badge on ticket item
- Badge distinguishes "active (orchestrated)" from "active (manual)"

**Tests**:
- Test orchestrated tickets show badge
- Test badge distinguishes from manual active
- Test badge cleared when orchestration ends

**Definition of Success**:
- ✅ Users know which tickets are orchestrated
- ✅ Badge unobtrusive

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Phase 6: Edge Cases & Polish

### Task 6.1: Error Handling in Tools

**Objective**: All tools gracefully handle errors and edge cases.

**Implementation**:
- For each tool: comprehensive error checking
  - Missing/invalid input
  - Resources not found
  - Permission issues
  - Git operation failures
- Return error responses with clear messages
- Don't crash the orchestrator

**Tests**:
- Test each tool with invalid input
- Test resources not found
- Test permission errors
- Test git failures (e.g., conflicts on rebase_and_merge)

**Definition of Success**:
- ✅ No unhandled exceptions in tools
- ✅ Errors reported clearly to orchestrator
- ✅ Orchestrator can adapt

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 6.2: Orchestrator Chat Resume Support

**Objective**: User can resume an orchestration after closing the app.

**Implementation**:
- OrchestratorState persists managed agent IDs to chat metadata
- On app restart: when orchestrator chat is selected
  - Recover OrchestratorState from metadata
  - Re-attach agents by looking up ChatStates by ID
  - Resume listening to agent state changes

**Tests**:
- Test orchestration state persisted
- Test orchestrator recovers agents on resume
- Test agents can be queried after resume

**Definition of Success**:
- ✅ Orchestration survives app restart
- ✅ Agent state accurate on resume

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 6.3: Orchestrator Cleanup on Exit

**Objective**: Clean up resources if orchestrator chat is closed.

**Implementation**:
- When orchestrator chat is disposed
  - Unregister all agents
  - Clear OrchestratorState
  - Optionally: offer to clean up worker chats and worktrees
- Add dialog: "Orchestration in progress. Clean up worker chats?" (Yes/No/Cancel)

**Tests**:
- Test cleanup dialog shows when needed
- Test cleanup removes agents
- Test cancel preserves state

**Definition of Success**:
- ✅ No orphaned agents
- ✅ User has control over cleanup

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 6.4: Permission Request Passthrough

**Objective**: Worker agent permission requests surface to user without disrupting orchestrator.

**Implementation**:
- When worker agent requests permission (e.g., via tool use):
  - ChatState handles normally (shows bell notification)
  - Orchestrator doesn't need to know
  - `wait_for_agents` detects "permission_needed" reason
  - Orchestrator can pause that agent or skip to others
- Test workflow: orchestrator sees permission_needed, tells user, waits for user decision

**Tests**:
- Test permission request detected by wait_for_agents
- Test worker agent can respond after permission granted
- Test orchestrator can continue with other agents

**Definition of Success**:
- ✅ Permissions don't break orchestration
- ✅ User can approve/deny as usual
- ✅ Orchestrator aware of permission state

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 6.5: Cost Aggregation Across Agents

**Objective**: Track total cost of orchestration run.

**Implementation**:
- OrchestratorState listens to agent ChatStates' usage changes
- Aggregates cumulative cost: sum of all agents' usage
- Exposes via `getTotalCost()` method
- ProgressWidget displays this in summary

**Tests**:
- Test cost aggregates correctly
- Test cost updates as agents work
- Test cost accurate after multiple agents

**Definition of Success**:
- ✅ Total orchestration cost visible
- ✅ Accurate aggregation

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

### Task 6.6: System Prompt Tuning & Documentation

**Objective**: Based on real testing, refine system prompt for best orchestrator behavior.

**Implementation**:
- After Phase 1-5 complete: run manual tests with orchestrator
- Observe LLM behavior: does it use tools correctly? Follow patterns from doc?
- Adjust system prompt based on issues found
- Document lessons learned in ORCHESTRATION_TUNING.md
- Add examples of common pitfalls and how prompt handles them

**Tests**:
- Manual orchestration runs (not automated)
- Verify orchestrator:
  - Respects dependencies
  - Handles merge conflicts correctly
  - Doesn't accidentally merge to wrong branch
  - Asks for clarification when ambiguous
  - Recovers from agent errors

**Definition of Success**:
- ✅ Orchestrator behaves as designed in docs
- ✅ No surprising LLM behaviors
- ✅ Tuning notes for future iterations

**Completion Checklist**:
- [ ] Code written
- [ ] Tests written
- [ ] Independent code review passed
- [ ] Completed

---

## Rollout Criteria

### End of Phase 1
- All 11 tools implemented and tested
- Tool gating in place
- Orchestrator can be created and given instructions manually

### End of Phase 2
- Normal chats can't access orchestration tools
- Orchestration-enabled chat toggle works

### End of Phase 3
- Orchestrator chat creation tested
- System prompt verified
- Manual test: user can type orchestration instructions

### End of Phase 4
- UI launch flow works end-to-end
- User can select tickets, create base worktree, launch orchestrator

### End of Phase 5
- Progress widget visible and accurate
- User can monitor orchestration live

### End of Phase 6
- Edge cases handled
- Resume works
- Cost tracking accurate
- System prompt tuned
- Ready for beta users

---

## Success Criteria for Feature Launch

✅ All tasks completed with code, tests, and review
✅ Orchestrator successfully executes sample ticket sets in parallel with code reviews
✅ Merge conflicts detected and resolved via conflict-resolution agents
✅ Progress visible throughout orchestration
✅ No tool leakage to normal chats
✅ User can interrupt/resume orchestration
✅ Cost tracking accurate
✅ Documentation complete with examples
