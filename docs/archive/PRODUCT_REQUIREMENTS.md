# Claude Agent Insights

## Product Vision

A desktop application that provides unprecedented visibility into Claude Code agent execution. Watch multiple agents work in parallel, see their thought processes, track tool usage, and interact with agents when they need input—all in a clean, organized interface.

## Problem Statement

When running Claude Code agents (especially with subagents), it's difficult to:
- See what each agent is working on in real-time
- Track the hierarchy of agents and their relationships
- Understand which agent produced which output
- Respond to agent questions without losing context
- Monitor token usage and costs across agents

## Solution

A two-component system:
1. **Python Backend** (runs in container) - Bridges Claude Agent SDK to WebSocket
2. **Flutter Frontend** (runs on host) - Rich GUI for monitoring and interaction

## User Interface

```
+------------------------------------------------------------------+
| Claude Agent Insights                              [_] [□] [X]   |
+------------------------------------------------------------------+
| Sessions      | Agents        | Output                           |
|---------------|---------------|----------------------------------|
| ● Session 1   | ● Main        | [Token: 12.4k | Cost: $0.03]     |
|   2 agents    |   ├─ Sub1     |----------------------------------|
|   active      |   └─ Sub2     | I'll help you implement the      |
|               |               | authentication system. Let me    |
| ○ Session 2   | [Main]        | first explore the codebase...    |
|   completed   |               |                                  |
|   $0.12       |               | > Using Tool: Glob               |
|               |               |   Pattern: **/*.py               |
|               |               |                                  |
|               |               | Found 23 Python files. Now let   |
|               |               | me examine the existing auth...  |
|               |               |                                  |
|               |               |                                  |
|               |               |                                  |
|               |               |----------------------------------|
|               |               | [Ask user input box      ] [Send]|
+------------------------------------------------------------------+
| Status: Session 1 active | Main: working | Sub1: waiting for tool |
+------------------------------------------------------------------+
```

## Core Features

### 1. Session Management
- Create new sessions with configurable options
- View list of active and completed sessions
- Session metadata: agent count, status, total cost, duration
- Kill/restart sessions
- Session persistence (resume after app restart)

### 2. Agent Hierarchy View
- Tree view showing Main agent and all subagents
- Visual indicators for agent state:
  - ● Working (green pulse)
  - ◐ Waiting for tool (yellow)
  - ◇ Waiting for user input (blue)
  - ○ Idle/completed (gray)
- Click agent to view its output
- Show agent's current task/description
- Nested subagents supported (Sub1 spawns Sub1.1, etc.)

### 3. Output Panel
- Real-time streaming output from selected agent
- **Smart scrolling**:
  - Auto-scroll when user is at bottom
  - Lock view when user scrolls up (new content doesn't disrupt)
  - "Jump to bottom" button appears when not at bottom
- Syntax highlighting for code blocks
- Collapsible tool calls (show tool name, expand for details)
- Timestamps (optional, toggle in settings)
- Search within output (Cmd+F)

### 4. Tool Visualization
- Inline display of tool usage:
  ```
  > Using Tool: Read
    Path: /src/auth/login.py
    [Expand to see file contents]
  ```
- Color coding by tool type:
  - File ops (Read, Write, Edit): blue
  - Search (Glob, Grep): purple
  - Execution (Bash, Task): orange
  - Web (WebFetch, WebSearch): green
- Tool duration timing
- Error highlighting for failed tools

### 5. User Interaction
- Input box for responding to agent questions
- When agent asks question:
  - Panel highlights/pulses
  - Question displayed with options (if provided)
  - Text input for custom answers
- Support for multiple pending questions (queue)
- Input history (up arrow for previous inputs)

### 6. Token & Cost Tracking
- Per-agent token counts (input/output/cache)
- Per-session totals
- Running cost estimate
- Visual breakdown (pie chart or bar)
- Export usage report

### 7. File Browser (Phase 2)
- Tree view of project files
- Click to view file with syntax highlighting
- Basic editing capability
- See which files agents have read/modified (highlights)

## Non-Functional Requirements

### Performance
- Handle 10+ concurrent agents without UI lag
- Smooth 60fps scrolling even with rapid output
- Output buffer: retain last 100k lines per agent (configurable)
- WebSocket reconnection with message replay

### Platform Support
- Primary: macOS (Apple Silicon + Intel)
- Secondary: Linux, Windows (Phase 2)

### Security
- WebSocket connection localhost only by default
- Optional: authentication token for remote connections
- No sensitive data persistence (API keys stay in container)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host Machine                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Flutter GUI                           │    │
│  │  ┌──────────┐ ┌──────────┐ ┌────────────────────────┐   │    │
│  │  │ Sessions │ │ Agents   │ │ Output Panel           │   │    │
│  │  │ Provider │ │ Provider │ │ (StreamBuilder)        │   │    │
│  │  └────┬─────┘ └────┬─────┘ └────────────┬───────────┘   │    │
│  │       │            │                     │               │    │
│  │       └────────────┴─────────────────────┘               │    │
│  │                          │                               │    │
│  │              ┌───────────┴───────────┐                   │    │
│  │              │   WebSocket Client    │                   │    │
│  │              └───────────┬───────────┘                   │    │
│  └──────────────────────────┼───────────────────────────────┘    │
│                             │ ws://localhost:8765                │
│  ┌──────────────────────────┼───────────────────────────────┐    │
│  │         Docker Container │                               │    │
│  │              ┌───────────┴───────────┐                   │    │
│  │              │   WebSocket Server    │                   │    │
│  │              │   (Python/asyncio)    │                   │    │
│  │              └───────────┬───────────┘                   │    │
│  │                          │                               │    │
│  │              ┌───────────┴───────────┐                   │    │
│  │              │    Agent Manager      │                   │    │
│  │              │  (session tracking)   │                   │    │
│  │              └───────────┬───────────┘                   │    │
│  │                          │                               │    │
│  │              ┌───────────┴───────────┐                   │    │
│  │              │   Claude Agent SDK    │                   │    │
│  │              │   (with PreToolUse    │                   │    │
│  │              │    hooks for Q&A)     │                   │    │
│  │              └───────────────────────┘                   │    │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## WebSocket Protocol

### Client → Server Messages

```json
// Start new session
{
  "type": "session.create",
  "id": "msg-uuid",
  "payload": {
    "prompt": "Help me build an auth system",
    "cwd": "/projects/myapp",
    "allowed_tools": ["Task", "Read", "Write", "Edit", "Bash"],
    "permission_mode": "acceptEdits"
  }
}

// Send user input (answer to question)
{
  "type": "user.input",
  "id": "msg-uuid",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",  // or null for main
    "text": "Use JWT tokens"
  }
}

// Kill session
{
  "type": "session.kill",
  "id": "msg-uuid",
  "payload": {
    "session_id": "session-uuid"
  }
}
```

### Server → Client Messages

```json
// Session created
{
  "type": "session.created",
  "payload": {
    "session_id": "session-uuid"
  }
}

// Agent spawned
{
  "type": "agent.spawned",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "parent_id": null,  // or parent agent's ID
    "label": "Main",
    "task_description": "Help me build an auth system"
  }
}

// Agent output (streaming text)
{
  "type": "agent.output",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "content": "I'll help you build...",
    "content_type": "text"
  }
}

// Tool use
{
  "type": "agent.tool_use",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "tool_name": "Read",
    "tool_input": {"file_path": "/src/auth.py"},
    "tool_use_id": "tool-uuid"
  }
}

// Tool result
{
  "type": "agent.tool_result",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "tool_use_id": "tool-uuid",
    "result": "file contents...",
    "is_error": false
  }
}

// Question for user
{
  "type": "agent.question",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "question": "Which auth method do you prefer?",
    "options": [
      {"label": "JWT", "description": "Stateless tokens"},
      {"label": "Sessions", "description": "Server-side sessions"}
    ]
  }
}

// Agent completed
{
  "type": "agent.completed",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "result": "Summary of what was done...",
    "usage": {
      "input_tokens": 15000,
      "output_tokens": 3000,
      "cost_usd": 0.05
    }
  }
}

// Session completed
{
  "type": "session.completed",
  "payload": {
    "session_id": "session-uuid",
    "total_usage": {...}
  }
}

// Error
{
  "type": "error",
  "payload": {
    "session_id": "session-uuid",
    "agent_id": "agent-uuid",
    "message": "Something went wrong",
    "code": "TOOL_FAILED"
  }
}
```

## Success Metrics

- User can monitor 5+ parallel agents without confusion
- Output latency < 100ms from SDK to UI
- Zero dropped messages during normal operation
- Smooth scrolling at 60fps with 10k+ lines of output

## Milestones

### Phase 1: MVP (Core Functionality)
- Single session support
- Agent hierarchy view
- Streaming output with smart scroll
- User input handling
- Basic token/cost display

### Phase 2: Polish
- Multiple sessions
- Tool visualization (collapsible, colored)
- Search within output
- Session persistence
- Settings panel

### Phase 3: Extended Features
- File browser with syntax highlighting
- Usage analytics/charts
- Export session transcripts
- Custom themes
