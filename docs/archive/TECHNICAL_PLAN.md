# Claude Agent Insights - Technical Plan

## Overview

This document outlines the implementation plan for Claude Agent Insights, broken into phases with concrete deliverables.

## Technology Stack

### Backend (Container)
- **Language**: Python 3.11+
- **WebSocket**: `websockets` library (async)
- **Claude Integration**: `claude-agent-sdk`
- **Serialization**: JSON (msgpack optional for performance)
- **Container**: Docker with mounted project directories

### Frontend (Host)
- **Framework**: Flutter 3.x
- **State Management**: Riverpod (or Provider)
- **WebSocket**: `web_socket_channel` package
- **Syntax Highlighting**: `flutter_highlight`
- **File Tree**: `flutter_fancy_tree_view`
- **Platform**: macOS desktop first

---

## Phase 1: MVP

**Goal**: Single session, multi-agent tracking with basic UI

### Step 1.1: Backend Foundation
**Files to create:**
```
backend/
├── pyproject.toml
├── src/
│   ├── __init__.py
│   ├── server.py          # WebSocket server entry point
│   ├── agent_manager.py   # Manages agent lifecycle
│   ├── agent_tracker.py   # Tracks agent hierarchy (from our tests)
│   ├── message_types.py   # Pydantic models for WS protocol
│   └── hooks.py           # PreToolUse hooks for Q&A
└── Dockerfile
```

**Deliverables:**
- [ ] WebSocket server listening on port 8765
- [ ] `session.create` → spawns Claude agent
- [ ] Event streaming: agent.output, agent.tool_use, agent.tool_result
- [ ] Agent hierarchy tracking (parent_tool_use_id routing)
- [ ] `user.input` handling via PreToolUse hook
- [ ] `session.kill` to terminate

**Key code (server.py sketch):**
```python
import asyncio
import json
from websockets import serve
from agent_manager import AgentManager

manager = AgentManager()

async def handler(websocket):
    async for raw in websocket:
        msg = json.loads(raw)

        if msg["type"] == "session.create":
            session_id = await manager.create_session(
                prompt=msg["payload"]["prompt"],
                cwd=msg["payload"]["cwd"],
                on_event=lambda e: websocket.send(json.dumps(e))
            )
            await websocket.send(json.dumps({
                "type": "session.created",
                "payload": {"session_id": session_id}
            }))

        elif msg["type"] == "user.input":
            await manager.send_input(
                session_id=msg["payload"]["session_id"],
                agent_id=msg["payload"]["agent_id"],
                text=msg["payload"]["text"]
            )

async def main():
    async with serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()  # run forever

asyncio.run(main())
```

### Step 1.2: Flutter App Shell
**Files to create:**
```
flutter_app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── session.dart
│   │   ├── agent.dart
│   │   └── message.dart
│   ├── services/
│   │   └── websocket_service.dart
│   ├── providers/
│   │   ├── session_provider.dart
│   │   └── agent_provider.dart
│   └── screens/
│       └── home_screen.dart
└── macos/
    └── (Flutter macOS config)
```

**Deliverables:**
- [ ] macOS app builds and runs
- [ ] WebSocket connection to backend
- [ ] Reconnection logic with exponential backoff
- [ ] Message parsing into Dart models

### Step 1.3: Session Panel
**Files:**
```
lib/
├── widgets/
│   └── session_list.dart
└── screens/
    └── home_screen.dart (update)
```

**Deliverables:**
- [ ] List of sessions (just one for MVP)
- [ ] Session status indicator
- [ ] "New Session" button → dialog for prompt input
- [ ] Session selection updates agent/output panels

### Step 1.4: Agent Tree Panel
**Files:**
```
lib/
├── widgets/
│   └── agent_tree.dart
```

**Deliverables:**
- [ ] Tree view showing agent hierarchy
- [ ] Status indicators (working/waiting/completed)
- [ ] Click to select agent
- [ ] Updates in real-time as subagents spawn

### Step 1.5: Output Panel with Smart Scroll
**Files:**
```
lib/
├── widgets/
│   ├── output_panel.dart
│   └── smart_scroll_view.dart
```

**Deliverables:**
- [ ] Streaming text display
- [ ] Smart scroll behavior:
  - Auto-scroll when at bottom
  - Lock position when scrolled up
  - "Jump to bottom" FAB when not at bottom
- [ ] Basic text styling (monospace)

**Smart scroll implementation:**
```dart
class SmartScrollController {
  final ScrollController _controller = ScrollController();
  bool _userScrolledUp = false;

  void onScroll() {
    final atBottom = _controller.position.pixels >=
                     _controller.position.maxScrollExtent - 50;
    _userScrolledUp = !atBottom;
  }

  void onNewContent() {
    if (!_userScrolledUp) {
      _controller.animateTo(
        _controller.position.maxScrollExtent,
        duration: Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  bool get showJumpToBottom => _userScrolledUp;
}
```

### Step 1.6: User Input Panel
**Files:**
```
lib/
├── widgets/
│   ├── input_panel.dart
│   └── question_dialog.dart
```

**Deliverables:**
- [ ] Text input field with send button
- [ ] Question popup when agent asks
- [ ] Option buttons for multi-choice questions
- [ ] Input history (up/down arrow)

### Step 1.7: Integration & Testing
**Deliverables:**
- [ ] End-to-end: Start session → see output → answer question → see result
- [ ] Multi-agent: Main spawns Task → both visible in tree → output routes correctly
- [ ] Dockerfile builds and runs
- [ ] Basic error handling (connection lost, agent crash)

---

## Phase 2: Polish

### Step 2.1: Tool Visualization
**Files:**
```
lib/
├── widgets/
│   ├── tool_call_widget.dart
│   └── tool_result_widget.dart
```

**Deliverables:**
- [ ] Collapsible tool call blocks
- [ ] Color coding by tool type
- [ ] Show tool duration
- [ ] Syntax highlighting for code in tool results

### Step 2.2: Token & Cost Display
**Files:**
```
lib/
├── widgets/
│   └── usage_bar.dart
```

**Deliverables:**
- [ ] Per-agent token counts in agent tree
- [ ] Session total in header
- [ ] Cost estimate (configurable rates)

### Step 2.3: Multiple Sessions
**Updates to:**
- `session_provider.dart`
- `session_list.dart`
- `agent_manager.py`

**Deliverables:**
- [ ] Multiple concurrent sessions
- [ ] Session switching
- [ ] Kill session button
- [ ] Completed sessions stay visible (grayed)

### Step 2.4: Search in Output
**Deliverables:**
- [ ] Cmd+F opens search bar
- [ ] Highlight matches
- [ ] Navigate between matches

### Step 2.5: Settings Panel
**Files:**
```
lib/
├── screens/
│   └── settings_screen.dart
```

**Deliverables:**
- [ ] Backend URL configuration
- [ ] Default tools selection
- [ ] Theme selection (light/dark)
- [ ] Buffer size limit

---

## Phase 3: Extended Features

### Step 3.1: File Browser
**Files:**
```
lib/
├── widgets/
│   ├── file_tree.dart
│   └── code_editor.dart
```

**Deliverables:**
- [ ] Project file tree
- [ ] Click to view file
- [ ] Syntax highlighting (flutter_code_editor)
- [ ] Basic editing
- [ ] Highlight files touched by agents

### Step 3.2: Session Persistence
**Backend additions:**
- SQLite or JSON file storage
- Resume session on reconnect

**Deliverables:**
- [ ] Sessions survive app restart
- [ ] Output history preserved
- [ ] Reconnect to running sessions

### Step 3.3: Export & Analytics
**Deliverables:**
- [ ] Export session transcript (Markdown)
- [ ] Usage charts (tokens over time)
- [ ] Session comparison

---

## Directory Structure (Final)

```
claude-agent-insights/
├── backend/
│   ├── pyproject.toml
│   ├── Dockerfile
│   ├── src/
│   │   ├── __init__.py
│   │   ├── server.py
│   │   ├── agent_manager.py
│   │   ├── agent_tracker.py
│   │   ├── message_types.py
│   │   ├── hooks.py
│   │   └── session_store.py      # Phase 3
│   └── tests/
│       ├── test_agent_manager.py
│       └── test_hooks.py
│
├── flutter_app/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   │   ├── session.dart
│   │   │   ├── agent.dart
│   │   │   ├── message.dart
│   │   │   └── tool_call.dart
│   │   ├── services/
│   │   │   ├── websocket_service.dart
│   │   │   └── file_service.dart     # Phase 3
│   │   ├── providers/
│   │   │   ├── session_provider.dart
│   │   │   ├── agent_provider.dart
│   │   │   └── settings_provider.dart
│   │   ├── screens/
│   │   │   ├── home_screen.dart
│   │   │   └── settings_screen.dart
│   │   └── widgets/
│   │       ├── session_list.dart
│   │       ├── agent_tree.dart
│   │       ├── output_panel.dart
│   │       ├── smart_scroll_view.dart
│   │       ├── input_panel.dart
│   │       ├── question_dialog.dart
│   │       ├── tool_call_widget.dart
│   │       ├── usage_bar.dart
│   │       ├── file_tree.dart        # Phase 3
│   │       └── code_editor.dart      # Phase 3
│   ├── macos/
│   └── test/
│
├── docker-compose.yml
├── README.md
└── docs/
    ├── PRODUCT_REQUIREMENTS.md
    └── TECHNICAL_PLAN.md
```

---

## Development Order (Recommended)

```
Week 1: Backend Foundation
├── Day 1-2: WebSocket server + basic agent spawning
├── Day 3-4: Agent tracking + event streaming
└── Day 5: PreToolUse hooks for Q&A

Week 2: Flutter Core
├── Day 1: App shell + WebSocket connection
├── Day 2: Session panel + agent tree
├── Day 3-4: Output panel + smart scroll
└── Day 5: Input panel + question handling

Week 3: Integration
├── Day 1-2: End-to-end testing + bug fixes
├── Day 3: Tool visualization
├── Day 4: Token/cost display
└── Day 5: Buffer + polish

Week 4+: Phase 2 & 3 features as needed
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| WebSocket drops | Reconnection with message ID tracking, replay missed messages |
| High output volume | Virtual list rendering, configurable buffer limits |
| Agent crash | Graceful error handling, session stays visible with error state |
| Container networking | Use host.docker.internal or explicit port mapping |
| Flutter macOS quirks | Test early on real hardware, not just simulator |

---

## Getting Started

1. **Backend first**: Get WebSocket server running with mock events
2. **Flutter shell**: Connect to backend, display raw JSON
3. **Iterate**: Add panels one by one, real Claude integration last
4. **Test with simple prompts**: "List 3 colors" before complex multi-agent tasks
