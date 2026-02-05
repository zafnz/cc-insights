# CC-Insights V2 Persistence Architecture

## Overview

CC-Insights persists project, worktree, and chat state to enable session resume after app restarts or crashes. The design prioritizes crash resilience through append-only logging and separates frequently-updated metadata from message history.

## Storage Structure

```
~/.ccinsights/
├── projects.json                           # Master index of all projects/worktrees/chats
└── projects/
    └── <projectId>/                        # Hash of project root path
        └── chats/
            ├── <chatId>.chat.jsonl         # Append-only message history
            └── <chatId>.meta.json          # Model, permission, context, usage
```

## File Formats

### projects.json

The master index containing all known projects, their worktrees, and active chats. This file is the source of truth for what chats exist - we don't scan directories.

```json
{
  "/Users/dev/my-project": {
    "id": "a1b2c3d4",
    "name": "My Project",
    "worktrees": {
      "/Users/dev/my-project": {
        "type": "primary",
        "name": "main",
        "chats": [
          {
            "name": "Fix the login bug",
            "chatId": "chat-1706234567890",
            "lastSessionId": "sdk-session-xyz123"
          },
          {
            "name": "Add dark mode",
            "chatId": "chat-1706234599999",
            "lastSessionId": null
          }
        ]
      },
      "/Users/dev/my-project-feature": {
        "type": "linked",
        "name": "feature-auth",
        "chats": []
      }
    }
  }
}
```

**Fields:**
- `id`: Stable project ID (hash of root path), used for storage directory
- `name`: Human-readable name (defaults to directory name, user-editable)
- `worktrees`: Map of worktree paths to worktree data
  - `type`: `"primary"` (repo root) or `"linked"` (git worktree)
  - `name`: Human-readable name (defaults to branch or directory)
  - `chats`: Array of chat references
    - `name`: User-visible chat name (auto-generated from first message, editable)
    - `chatId`: Unique chat identifier, used for file naming
    - `lastSessionId`: SDK session ID for resume, null if never connected or ended

### <chatId>.meta.json

Metadata for a chat that changes during a session. Overwritten on each update.

```json
{
  "model": "claude-sonnet-4",
  "permissionMode": "default",
  "createdAt": "2024-01-25T10:30:00.000Z",
  "lastActiveAt": "2024-01-25T14:22:15.000Z",
  "context": {
    "currentTokens": 50300,
    "maxTokens": 200000
  },
  "usage": {
    "inputTokens": 35000,
    "outputTokens": 17910,
    "cacheReadTokens": 12000,
    "cacheCreationTokens": 5000,
    "costUsd": 0.4532
  }
}
```

**Fields:**
- `model`: Claude model API name (e.g., `claude-sonnet-4`)
- `permissionMode`: Permission mode API name (`default`, `acceptEdits`, `plan`, `bypassPermissions`)
- `createdAt`: ISO timestamp when chat was created
- `lastActiveAt`: ISO timestamp of last activity
- `context`: Current context window state
  - `currentTokens`: Tokens currently in context
  - `maxTokens`: Maximum context window size
- `usage`: Cumulative token usage and cost for this chat
  - `inputTokens`: Total input tokens
  - `outputTokens`: Total output tokens
  - `cacheReadTokens`: Tokens read from cache
  - `cacheCreationTokens`: Tokens used for cache creation
  - `costUsd`: Total cost in USD

### <chatId>.chat.jsonl

Append-only message history in JSON Lines format. Each line is a self-contained JSON object representing one message or event.

```jsonl
{"type":"user","timestamp":"2024-01-25T10:30:00.000Z","text":"Fix the login bug that's causing users to be logged out"}
{"type":"assistant","timestamp":"2024-01-25T10:30:05.000Z","text":"I'll help you fix the login bug. Let me first look at the authentication code."}
{"type":"tool_use","timestamp":"2024-01-25T10:30:06.000Z","id":"tu_123","tool":"Read","input":{"file_path":"/src/auth.ts"}}
{"type":"tool_result","timestamp":"2024-01-25T10:30:07.000Z","toolUseId":"tu_123","output":"export function authenticate..."}
{"type":"assistant","timestamp":"2024-01-25T10:30:10.000Z","text":"I found the issue. The session token is not being refreshed..."}
```

**Message Types:**

| Type | Description | Key Fields |
|------|-------------|------------|
| `user` | User input message | `text` |
| `assistant` | Claude's text response | `text` |
| `tool_use` | Tool invocation | `id`, `tool`, `input` |
| `tool_result` | Tool execution result | `toolUseId`, `output`, `isError` |
| `system` | System messages | `text`, `subtype` |

**Design Notes:**
- Format is close to SDK message format for easy session resume
- Each line is independent - partial writes only lose one message
- Subagent conversations are NOT persisted (ephemeral, output in main conversation)

## Operations

### App Launch

1. Load `projects.json`
2. Find project by command-line path argument
3. Restore `ProjectState` and `WorktreeState` objects
4. For each chat in the worktree:
   - Create `ChatState` with metadata from projects.json
   - Do NOT load `.chat.jsonl` yet (lazy load on selection)

### Chat Selected

1. Load `<chatId>.meta.json` for model/permission/usage
2. Load `<chatId>.chat.jsonl` and parse into `OutputEntry` objects
3. Populate `ChatState.data.primaryConversation.entries`

### New Entry Added

1. Serialize entry to JSON
2. Append line to `<chatId>.chat.jsonl` (no rewrite)
3. File handle kept open for performance

### Usage/Context Updated

1. Serialize meta to JSON
2. Overwrite `<chatId>.meta.json`
3. Debounce writes (e.g., max once per second)

### Chat Created

1. Generate `chatId` (e.g., `chat-${timestamp}`)
2. Add chat reference to worktree in `projects.json`
3. Create empty `<chatId>.chat.jsonl`
4. Create `<chatId>.meta.json` with defaults
5. Save `projects.json`

### Chat Deleted/Ended

1. Remove chat from worktree in `projects.json`
2. Save `projects.json`
3. Optionally delete `.chat.jsonl` and `.meta.json` files
   - Could keep for history/recovery
   - User preference or explicit "delete forever" action

### SDK Session Resume

1. Read `lastSessionId` from projects.json
2. If non-null, pass to SDK when creating session
3. SDK handles conversation continuity
4. Update `lastSessionId` if SDK returns new session ID

## Project ID Generation

Project IDs are generated from the project root path to ensure stability:

```dart
String generateProjectId(String projectRoot) {
  // Use first 8 chars of SHA-256 hash
  final bytes = utf8.encode(projectRoot);
  final digest = sha256.convert(bytes);
  return digest.toString().substring(0, 8);
}
```

This ensures:
- Same project always gets same ID
- Different projects get different IDs (with high probability)
- IDs are filesystem-safe

## Error Handling

### Corrupt projects.json
- Keep backup on each successful write
- On parse failure, restore from backup
- If no backup, start fresh (projects can be re-discovered)

### Corrupt .chat.jsonl
- Parse line by line, skip invalid lines
- Log warnings for skipped lines
- Chat still usable with partial history

### Corrupt .meta.json
- Use defaults if parse fails
- Re-fetch from SDK on next connection

### Write Failures
- Log error, retry with backoff
- Don't block UI operations
- Mark chat as "needs sync" for retry

## Not Persisted

The following are intentionally NOT persisted:

- **Subagent conversations**: Ephemeral, output captured in main conversation
- **Active agents**: Runtime-only, rebuilt on SDK connection
- **SDK session object**: Recreated using `lastSessionId`
- **Selection state**: UI concern, reset on app launch
- **Panel layout**: Could add later if needed

## Implementation Notes

### File Handles
- Keep `.chat.jsonl` open for append during active session
- Close on chat deselection or app background
- Reopen on next write

### Concurrency
- Single writer for each file (no concurrent access)
- Read operations can happen anytime
- Use file locks if multi-instance support needed later

### Performance
- Lazy load chat history (only when selected)
- Debounce metadata writes
- Consider memory-mapping for large chat files

### Testing
- Use temp directories for tests
- Mock file system for unit tests
- Integration tests with real files
