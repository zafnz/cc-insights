# Claude Code Bug Report: Infinite Loop After Interrupted Tool Call

## Summary

When a user interrupts a tool call (particularly Bash commands) and then attempts to resume the conversation, Claude Code enters an infinite loop where it repeatedly attempts the same interrupted command and immediately receives an "aborted" error, making the session unusable.

## Steps to Reproduce

1. Start a Claude Code session and trigger a tool call (e.g., `npm run build`)
2. Interrupt the tool call while it's executing
3. Send a new message to resume work (e.g., "ok, yeah, continue, i just wanted to read your ideas. i think that'll work.")
4. Observe that every subsequent user message results in the same response pattern

## Expected Behavior

After interrupting a tool call, the next user message should:
- Start a fresh conversation turn
- Respond to the actual user input
- Not replay the interrupted tool call

## Actual Behavior

After interrupting a tool call, every subsequent user message triggers:
1. Claude attempting to execute the same interrupted tool call
2. System immediately injecting a "Request was aborted" error
3. Session completing without actually processing the user's new message
4. This pattern repeats infinitely for all future messages

## Technical Analysis

From the JSONL logs, the repeating pattern is:

```
1. User sends message (session_id: f03ed3a3-4568-4abe-b5fd-92213e133461)
2. System reinitializes (session_id: 923704a3-af1f-4fc8-a37a-79c593d7ba02)
3. Claude responds with cached response from interrupted session
4. System injects tool_result error: "Request was aborted"
5. Session completes "successfully"
6. Repeat for next user message
```

## Workaround

Get your session id and restart claude with -r. It keeps context but 
doesn't have the bug.

### Root Cause

**Session ID Mismatch**: The user's messages arrive with a new session ID (`f03ed3a3-4568-4abe-b5fd-92213e133461`), but the system continues using the old interrupted session ID (`923704a3-af1f-4fc8-a37a-79c593d7ba02`).

**State Contamination**: The interrupted tool call and its "aborted" error are persisted in the conversation state and replayed on every turn, preventing new interactions from being processed.

### Evidence from Logs

Example from `broken.jsonl`:

```json
// User's new message with new session ID
{
  "time": "2026-01-23T17:46:19.138",
  "type": "user",
  "session_id": "f03ed3a3-4568-4abe-b5fd-92213e133461",
  "message": {
    "content": "ok, yeah, continue, i just wanted to read your ideas. i think that'll work."
  }
}

// System reinitializes with OLD session ID
{
  "time": "2026-01-23T17:46:19.155",
  "type": "system",
  "subtype": "init",
  "session_id": "923704a3-af1f-4fc8-a37a-79c593d7ba02"
}

// Claude tries to run the same build command again
{
  "time": "2026-01-23T17:46:24.540",
  "type": "assistant",
  "message": {
    "content": [{
      "type": "tool_use",
      "id": "toolu_011JfjWEMGuqWrhmwQshsHsb",
      "name": "Bash",
      "input": {
        "command": "cd /tmp/cc-insights/project/backend-node && npm run build"
      }
    }]
  }
}

// System immediately injects abort error
{
  "time": "2026-01-23T17:46:24.566",
  "type": "user",
  "message": {
    "content": [{
      "type": "tool_result",
      "content": "<tool_use_error>Error calling tool (Bash): Request was aborted.</tool_use_error>",
      "is_error": true,
      "tool_use_id": "toolu_011JfjWEMGuqWrhmwQshsHsb"
    }]
  }
}
```

This pattern repeats identically for every subsequent user message.

## Impact

- **Severity**: High - Session becomes completely unusable
- **Workaround**: User must `/clear` the conversation or start a new session entirely
- **Data Loss**: Any context or work in progress is lost when forced to clear

## Proposed Fix

The system should:
1. Properly clear interrupted tool call state when a new user message arrives
2. Respect session ID changes and start fresh when the session ID differs
3. Not inject aborted tool results into subsequent conversation turns
4. Allow the conversation to proceed normally after an interruption

## Environment

- **Claude Code Version**: 2.1.17
- **Model**: claude-opus-4-5-20251101
- **Permission Mode**: acceptEdits
- **Date**: 2026-01-23

## Additional Notes

This bug appears to be a state management issue in the conversation/session handling layer. The conversation state is not being properly reset or cleaned up after tool call interruptions, causing stale tool calls and their errors to persist across turns.

The session ID mismatch suggests the system may be confusing user session context with internal agent session management.
