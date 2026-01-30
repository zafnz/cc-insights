# CC-Insights V2 Architecture

## Overview

CC-Insights is a desktop application for monitoring and interacting with Claude Code agents. This document describes the architecture for V2, a redesign that:

1. Makes git worktrees a core concept rather than a bolt-on
2. Introduces a flexible panel-based UI
3. Preserves working components (Dart SDK, display widgets)
4. Replaces problematic session management with a cleaner hierarchy

---

## Core Concepts

### Terminology

| Term | Definition |
|------|------------|
| **Project** | A git repository. Contains one primary worktree and zero or more linked worktrees. |
| **Worktree** | A git working tree with files. Has a path and a branch. |
| **Primary Worktree** | The worktree at the repository root (where the common `.git` directory lives). |
| **Linked Worktree** | A worktree created via `git worktree add`. Points back to the primary's `.git`. |
| **Chat** | A user-facing conversation unit. Belongs to a worktree. Contains conversations and optionally an active SDK session. |
| **Conversation** | A persistent log of messages/output. Survives session lifecycle. Each chat has a primary conversation and zero or more subagent conversations. |
| **Agent** | A runtime SDK entity. Exists only while a session is active. Created when SDK spawns via Task tool. Links to a Conversation for output storage. |
| **Session** | Internal SDK concept. The active connection to Claude. Users see "Chats", not "Sessions". |

### Hierarchy

```
Project: CC-Insights
├── Worktree (primary)
│   ├── Name: CC-Insights (mutable)
│   ├── worktreeRoot: ~/projects/cc-insights/ (immutable)
│   ├── Branch: main (mutable)
│   └── Chats:
│       ├── Chat 1
│       │   ├── Primary Conversation (persistent)
│       │   ├── Subagent Conversation 1 (persistent)
│       │   └── Subagent Conversation 2 (persistent)
│       ├── Chat 2
│       │   └── Primary Conversation (persistent)
│       └── Chat 3
│           └── Primary Conversation (persistent)
│
├── Worktree (linked)
│   ├── Name: Add Dark Mode (mutable)
│   ├── worktreeRoot: ~/projects/cc-insights-wt/feat-add-darkmode/ (immutable)
│   ├── Branch: feat-add-darkmode (mutable)
│   └── Chats:
│       └── Chat 1
│           └── Primary Conversation (persistent)
│
└── Worktree (linked)
    ├── Name: Fix Broken Code (mutable)
    ├── worktreeRoot: ~/projects/cc-insights-wt/bugfix-broken-code/ (immutable)
    ├── Branch: bugfix-broken-code (mutable)
    └── Chats: (none)
```

### Rules

- A project has exactly one primary worktree (the repo root)
- A project has zero or more linked worktrees
- Each worktree has a branch, but branches must be unique across worktrees (git constraint)
- Worktree branches are mutable (can change via `git checkout`)
- A chat belongs to exactly one worktree
- Each chat has exactly one primary conversation
- Each chat has zero or more subagent conversations (created when SDK spawns subagents via Task tool)
- Conversations are persistent; Agents are runtime-only
- Users interact with the primary conversation (input box); subagent conversations are read-only
- Subagents can still request permissions (routed to their conversation)

---

## Data Model

The data model separates **immutable data classes** from **mutable state holders**:

- **Data classes** (`*Data`): Immutable, contain only data, use `copyWith` for updates
- **State classes** (`*State`): Extend `ChangeNotifier`, hold data and manage mutations

This separation provides clear state transitions, easier debugging, and better testability.

> **Note**: Code examples below are conceptual illustrations of the pattern. Exact implementation details (field names, method signatures, error handling) will be finalized during each phase.

### Pattern Overview

```dart
// Immutable data class
@immutable
class ExampleData {
  final String id;
  final String name;

  const ExampleData({required this.id, required this.name});

  ExampleData copyWith({String? name}) => ExampleData(
    id: id,
    name: name ?? this.name,
  );
}

// Mutable state holder
class ExampleState extends ChangeNotifier {
  ExampleData _data;

  ExampleState(this._data);

  ExampleData get data => _data;

  void updateName(String name) {
    _data = _data.copyWith(name: name);
    notifyListeners();
  }

  @override
  void dispose() {
    // Clean up resources
    super.dispose();
  }
}
```

### Project

```dart
@immutable
class ProjectData {
  final String name;
  final String repoRoot;  // Path to .git directory

  const ProjectData({required this.name, required this.repoRoot});

  ProjectData copyWith({String? name}) => ProjectData(
    name: name ?? this.name,
    repoRoot: repoRoot,
  );
}

class ProjectState extends ChangeNotifier {
  ProjectData _data;
  WorktreeState _primaryWorktree;
  List<WorktreeState> _linkedWorktrees;
  WorktreeState? _selectedWorktree;

  // ... state management methods

  List<WorktreeState> get allWorktrees => [_primaryWorktree, ..._linkedWorktrees];
}
```

### Worktree

```dart
@immutable
class WorktreeData {
  final String worktreeRoot;  // Immutable path
  final bool isPrimary;
  final String branch;        // Current branch (changes via git checkout)

  // Git status snapshot
  final int uncommittedFiles;
  final int stagedFiles;
  final int commitsAhead;
  final int commitsBehind;
  final bool hasMergeConflict;

  const WorktreeData({...});

  WorktreeData copyWith({String? branch, int? uncommittedFiles, ...}) => ...;
}

class WorktreeState extends ChangeNotifier {
  WorktreeData _data;
  List<ChatState> _chats;
  ChatState? _selectedChat;

  // ... state management methods
}
```

### Conversation

```dart
/// Persistent log of messages/output. Survives session lifecycle.
@immutable
class ConversationData {
  final String id;
  final String? label;           // For subagent conversations (e.g., "Explore", "Plan")
  final String? taskDescription; // For subagent conversations
  final List<OutputEntry> entries;
  final UsageInfo totalUsage;

  bool get isPrimary => label == null;

  const ConversationData({...});

  ConversationData copyWith({List<OutputEntry>? entries, ...}) => ...;
}
```

### Chat

```dart
@immutable
class ChatData {
  final String id;
  final String name;
  final String worktreeRoot;  // Reference to parent worktree
  final ConversationData primaryConversation;
  final Map<String, ConversationData> subagentConversations;

  const ChatData({...});

  ChatData copyWith({String? name, ...}) => ...;
}

class ChatState extends ChangeNotifier {
  ChatData _data;

  // Runtime state (ephemeral - only exists while session active)
  ClaudeSession? _session;
  Map<String, Agent> _activeAgents = {};

  // Selection
  String? _selectedConversationId;  // null = primary

  // Pending permission/question requests
  final Queue<PendingRequest> _pendingRequests = Queue();

  ChatData get data => _data;
  bool get hasActiveSession => _session != null;
  bool get isInputEnabled => _selectedConversationId == null;

  ConversationData get selectedConversation =>
    _selectedConversationId == null
      ? _data.primaryConversation
      : _data.subagentConversations[_selectedConversationId]!;

  void rename(String newName) {
    _data = _data.copyWith(name: newName);
    notifyListeners();
  }

  void addSubagentConversation(String sdkAgentId, String label, String? taskDescription) {
    final conversationId = 'conv-${DateTime.now().millisecondsSinceEpoch}';
    final conversation = ConversationData(
      id: conversationId,
      label: label,
      taskDescription: taskDescription,
      entries: [],
      totalUsage: UsageInfo.zero(),
    );

    _data = _data.copyWith(
      subagentConversations: {..._data.subagentConversations, conversationId: conversation},
    );

    _activeAgents[sdkAgentId] = Agent(
      sdkAgentId: sdkAgentId,
      conversationId: conversationId,
      status: AgentStatus.working,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    _session?.kill();
    super.dispose();
  }
}
```

### Agent

```dart
/// Runtime SDK entity. Exists only while session is active.
/// Links to a Conversation for persistent output storage.
@immutable
class Agent {
  final String sdkAgentId;
  final String conversationId;
  final AgentStatus status;
  final String? result;

  const Agent({...});

  Agent copyWith({AgentStatus? status, String? result}) => ...;
}

enum AgentStatus { working, waitingTool, waitingUser, completed, error }
```

### OutputEntry

```dart
/// Base class for conversation log entries. All entries are immutable.
@immutable
abstract class OutputEntry {
  final DateTime timestamp;
  const OutputEntry({required this.timestamp});
}

class TextOutputEntry extends OutputEntry {
  final String text;
  final String contentType;  // 'text' or 'thinking'
  const TextOutputEntry({...});
}

class ToolUseOutputEntry extends OutputEntry {
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String toolUseId;
  final String? model;
  final dynamic result;
  final bool isError;
  const ToolUseOutputEntry({...});
}

class UserInputEntry extends OutputEntry {
  final String text;
  const UserInputEntry({...});
}

class ContextSummaryEntry extends OutputEntry {
  final String summary;
  const ContextSummaryEntry({...});
}

class ContextClearedEntry extends OutputEntry {
  const ContextClearedEntry({required super.timestamp});
}
```

### Disposal Strategy

State classes that extend `ChangeNotifier` must be properly disposed:

- **App-level state** (ProjectState): Disposed when app closes
- **Worktree state**: Disposed when worktree is removed from project
- **Chat state**: Disposed when chat is deleted; kills any active session
- **Provider integration**: Use `ChangeNotifierProvider` which auto-disposes

Each state class's `dispose()` method must clean up:
- Active SDK sessions
- Stream subscriptions
- Any other resources

---

## Selection Model

### MVP: Single Worktree Focus

Everything follows the currently selected worktree. When you select a different worktree, all panels update to show that worktree's context.

### Hierarchical Selection

Each level in the hierarchy remembers its own selection. This allows switching worktrees to restore the previous chat/conversation selection for that worktree.

> **Note**: The examples below show the conceptual approach. Each state class manages its own selection and exposes methods for changing it - no class directly accesses another's private fields.

```dart
// Selection is managed within each state class
class ProjectState extends ChangeNotifier {
  WorktreeState? _selectedWorktree;

  WorktreeState? get selectedWorktree => _selectedWorktree;

  void selectWorktree(WorktreeState? wt) {
    _selectedWorktree = wt;
    notifyListeners();
  }
}

class WorktreeState extends ChangeNotifier {
  ChatState? _selectedChat;

  ChatState? get selectedChat => _selectedChat;

  void selectChat(ChatState? chat) {
    _selectedChat = chat;
    notifyListeners();
  }
}

class ChatState extends ChangeNotifier {
  String? _selectedConversationId;  // null = primary

  void selectConversation(String? conversationId) {
    _selectedConversationId = conversationId;
    notifyListeners();
  }
}
```

### SelectionState (Convenience Accessor)

`SelectionState` provides a unified view of the current selection, delegating to the hierarchy via public methods:

```dart
class SelectionState extends ChangeNotifier {
  final ProjectState project;

  // File selection is separate (doesn't belong to entity hierarchy)
  String? _selectedFilePath;

  // Getters follow the hierarchy
  WorktreeState? get selectedWorktree => project.selectedWorktree;
  ChatState? get selectedChat => selectedWorktree?.selectedChat;
  ConversationData? get selectedConversation => selectedChat?.selectedConversation;
  String? get selectedFilePath => _selectedFilePath;

  /// Select a worktree. Restores that worktree's previous chat/conversation.
  void selectWorktree(WorktreeState wt) {
    project.selectWorktree(wt);
    notifyListeners();
  }

  /// Select a chat within the current worktree.
  void selectChat(ChatState chat) {
    selectedWorktree?.selectChat(chat);
    notifyListeners();
  }

  /// Select a conversation within the current chat.
  void selectConversation(ConversationData conv) {
    selectedChat?.selectConversation(conv.isPrimary ? null : conv.id);
    notifyListeners();
  }

  /// Select a file to view.
  void selectFile(String? path) {
    _selectedFilePath = path;
    notifyListeners();
  }
}
```

This design means:
- Switching from worktree A to B, then back to A restores your previous chat/conversation in A
- Each worktree "remembers" what you were working on
- Panels just ask `selectionState.selectedX` and render accordingly
- Encapsulation is preserved - each class manages its own state via public methods

### Future Considerations

The MVP's single-focus model may evolve to support:

- **Panel pinning**: Lock a panel to a specific worktree while browsing others
- **Workspaces**: Multiple panel arrangements, each bound to a worktree
- **Split context**: "Working on" vs "browsing" distinction

The key architectural principle: **panels don't manage their own context**. They receive context from a selection layer. This allows the selection logic to change without modifying panel implementations.

---

## UI Architecture

### Panel System

The UI is built around a flexible panel manager inspired by VS Code and `drag_split_layout`. Panels can be:

- Resized via draggable dividers
- Rearranged via drag-and-drop with ghost targets
- Collapsed/expanded
- Merged into tree views (e.g., Chats panel merged into Worktrees panel)

### Panel Types

| Panel | Purpose | Follows Selection |
|-------|---------|-------------------|
| **Worktrees** | List worktrees with branch, path, and status icons | Project-level (always visible) |
| **Chats** | List chats for selected worktree | selectedWorktree |
| **Conversations** | Conversation tree for selected chat (primary + subagents) | selectedChat |
| **Conversation Viewer** | Output display + input (if primary conversation) | selectedConversation |
| **Files** | File tree navigator | selectedWorktree |
| **File Viewer** | Read-only file display with syntax highlighting | selectedFilePath |
| **Git Status** | Branch info, uncommitted files, commit history | selectedWorktree |

### Panel Merging

Panels with hierarchical relationships can merge:

**Conversations merged into Chats:**
```
Chats
============
○ Chat 1
├─ Subagent: Explore
└─ Subagent: Plan
○ Chat 2
○ Chat 3
└── Subagent: Explore
```

**Chats merged into Worktrees:**
```
Worktrees
├── ○ main
│   ├── ○ Chat 1
│   │   ├── Primary
│   │   ├── Subagent: Explore
│   │   └── Subagent: Plan
│   ├── - Chat 2
│   └── - Chat 3
├── ○ feat-dark-mode
│   ├── ○ Chat 1
│   └── ○ Chat 2
└── - feat-autosave
    └── ○ Chat 1
```

Icons indicate: `○` has new/unread messages, `-` no new messages.

### Worktree Panel Entry

Each worktree entry displays:

```
┌────────────────────┐
│ branch-name        │  ← Current git branch
│ worktree-path      │  ← Relative path (or full for primary)
│ ↑2 ↓1 ~3 ⚠         │  ← Ahead, behind, uncommitted, conflict
└────────────────────┘
```

- **branch-name**: Current branch (e.g., `main`, `feat-add-darkmode`)
- **worktree-path**: Relative from repo root for linked, full path for primary
- **Status icons**: Commits ahead/behind, uncommitted files, merge conflict indicator

### Conversation Viewer Panel

The conversation viewer panel adapts based on context:

**New chat (no active session):**
```
┌─────────────────────────────────────┐
│ main                                │
│ ~/projects/cc-insights              │
├─────────────────────────────────────┤
│                                     │
│   Start a conversation...           │
│                                     │
├─────────────────────────────────────┤
│ [Type a message...]          [Send] │
└─────────────────────────────────────┘
```

**Active chat, viewing primary conversation:**
```
┌─────────────────────────────────────┐
│ Chat 1                              │
├─────────────────────────────────────┤
│ [Tool cards, messages, output...]   │
│                                     │
├─────────────────────────────────────┤
│ [Type a message...]          [Send] │
└─────────────────────────────────────┘
```

**Viewing subagent conversation (read-only):**
```
┌─────────────────────────────────────┐
│ Subagent: Explore                   │
├─────────────────────────────────────┤
│ [Tool cards, messages, output...]   │
│                                     │
│                                     │  ← No input box
└─────────────────────────────────────┘
```

### Git Status Panel

```
┌─────────────────────────────────────────┐
│ Git: feat-dark-mode                     │
├─────────────────────────────────────────┤
│ Branch: feat-dark-mode                  │
│ Forked from: main (3 commits ago)       │
│                                         │
│ Uncommitted Changes:                    │
│   M lib/main.dart                       │
│   A lib/theme.dart                      │
│   ? lib/temp.dart (untracked)           │
│                                         │
│ Commits since fork:                     │
│   abc1234 Add dark theme toggle         │
│   def5678 Create theme provider         │
│   ghi9012 WIP: color palette            │
│                                         │
│ [Stage All] [Commit...] [Merge...]      │
└─────────────────────────────────────────┘
```

Future: Merge operations may involve cross-chat coordination (one Claude session consulting another). Not in scope for MVP but architecture should not preclude it.

---

## Component Preservation

### Fully Preserved (Copy As-Is)

| Component | Location | Notes |
|-----------|----------|-------|
| Dart SDK | `dart_sdk/` | ClaudeBackend, ClaudeSession, Protocol, all types |
| Session Model | `flutter_app/lib/models/session.dart` | Agent, OutputEntry classes (rename file) |
| Tool Card | `flutter_app/lib/widgets/tool_card.dart` | Tool rendering with expandable cards |
| Output Panel | `flutter_app/lib/widgets/output_panel.dart` | Smart scrolling behavior |
| Output Entries | `flutter_app/lib/widgets/output_entries.dart` | Polymorphic entry rendering |
| Diff View | `flutter_app/lib/widgets/diff_view.dart` | Visual diff display |
| Permission Widgets | `flutter_app/lib/widgets/permission_widgets.dart` | Permission request UI |
| SDK Message Handler | `flutter_app/lib/services/sdk_message_handler.dart` | Message routing |
| Backend Service | `flutter_app/lib/services/backend_service.dart` | Process lifecycle |

### Redesigned

| Component | Current Issue | New Approach |
|-----------|---------------|--------------|
| SessionProvider | Worktree logic entangled | Split into ChatProvider (SDK ops) + SelectionState |
| Session terminology | Confusing (SDK vs UI) | "Chat" for UI, "Session" internal only |
| App initialization | Heavy worktree service setup | Simplified, project-focused |
| Home screen | Worktree-specific layout | Panel-based, flexible |

### Not Preserved (Rewrite)

| Component | Reason |
|-----------|--------|
| Worktree services | Need redesign for new hierarchy |
| Worktree dialogs | Shell-specific UI |
| Project config service | New persistence model |

---

## Persistence

### Location

All persistence in user's home directory:

```
~/.cc-insights/
├── config.json           # App settings, recent projects
├── projects.json         # Project metadata
├── projects/
│   └── <project-hash>/
│       ├── project.json  # _MAYBE_ More project metadata
│       └── chats/
│           └── <chat-id>.json  # Chat metadata (future: conversation logs)
```

### projects.json (Table of Contents)

All project metadata in one file for easy discovery:

```json
{
  "projects": [
    {
      "id": "abc123",
      "name": "CC-Insights",
      "repoRoot": "/tmp/cc-insights",
      "lastOpened": "2025-01-27T10:30:00Z"
    },
    {
      "id": "def456",
      "name": "Other Project",
      "repoRoot": "/tmp/cc-insights/other",
      "lastOpened": "2025-01-26T15:00:00Z"
    }
  ]
}
```

### Chat Metadata

Per-chat JSON file with conversation data:

```json
{
  "id": "chat-abc123",
  "name": "Add dark mode feature",
  "worktreeRoot": "/tmp/cc-insights-wt/feat-dark",
  "createdAt": "2025-01-27T10:30:00Z",
  "lastMessageAt": "2025-01-27T11:45:00Z",
  "primaryConversation": {
    "id": "conv-primary",
    "entries": []
  },
  "subagentConversations": [
    {
      "id": "conv-123",
      "label": "Explore",
      "taskDescription": "Find all theme-related files",
      "entries": []
    }
  ]
}
```

Future: Full conversation logs for session resumption (entries populated with OutputEntry data).

---

## Communication Flow

```
Claude API
    ↓
Node.js Backend (session-manager.ts)
    ↓ stdout (JSON lines)
Dart SDK (Protocol → ClaudeSession)
    ↓ Stream<SDKMessage>
SDK Message Handler
    ↓ Updates
Chat Model (agents, output, usage)
    ↓ notifyListeners()
UI Widgets
```

User input flows reverse:

```
UI Input
    ↓
ChatProvider.sendMessage()
    ↓
Chat.ensureSession() → ClaudeSession.send()
    ↓ stdin (JSON lines)
Node.js Backend
    ↓
Claude API
```

---

## Architectural Principles

### 1. Panels Are Context-Agnostic

Panels receive their context from SelectionState. They don't manage which worktree/chat/agent they display. This allows:

- Easy testing (inject mock selection)
- Future multi-context support without panel changes
- Consistent behavior across all panels

### 2. Chat Owns Session Lifecycle

The Chat model manages its ClaudeSession internally:

- Creates session on first message
- Destroys session on `/clear`
- Recreates session on next message after `/clear`
- UI never directly touches ClaudeSession

### 3. SDK Concepts Stay Internal

Users see:
- **Chat** (not "Session")
- **Agent** (not "SDK Agent")
- **Worktree** (not "Working Directory")

SDK terminology is implementation detail.

### 4. Worktree Branch Is Mutable

Unlike path (immutable), branch can change. The UI must handle:

- Branch changes from external git operations
- Refreshing status when branch changes
- Unique branch constraint across worktrees

### 5. Conversations Are Persistent, Agents Are Runtime

- **Conversation**: Persistent log of output. Survives session lifecycle. Can be resumed (future).
- **Agent**: Runtime SDK entity. Exists only while session is active. Links to a Conversation.

When a session ends (or `/clear` is called):
- Agents are discarded
- Conversations persist with their output history

When a session resumes (future):
- New Agents are created
- They link to existing Conversations

### 6. Subagent Conversations Are Read-Only

Users cannot send input to subagent conversations. They can:

- View subagent conversation output
- Respond to subagent permission requests
- See subagent conversations in the tree

Only the primary conversation has an input box.

### 7. Future-Proof Without Over-Engineering

The MVP is simple (single worktree focus), but the architecture supports future enhancements:

- Panel pinning
- Multi-workspace
- Cross-chat coordination (for merge operations)
- Session resumption

Don't implement these now, but don't preclude them.

---

## Directory Structure (New Shell)

```
frontend/
├── lib/
│   ├── main.dart
│   │
│   ├── models/
│   │   ├── project.dart
│   │   ├── worktree.dart
│   │   ├── chat.dart
│   │   ├── conversation.dart         # Persistent log
│   │   ├── agent.dart                # Runtime entity
│   │   └── output_entry.dart
│   │
│   ├── state/
│   │   ├── selection_state.dart
│   │   ├── project_state.dart
│   │   └── chat_state.dart
│   │
│   ├── services/
│   │   ├── backend_service.dart      # Preserved
│   │   ├── sdk_message_handler.dart  # Preserved
│   │   ├── git_service.dart          # New
│   │   └── persistence_service.dart  # New
│   │
│   ├── panels/
│   │   ├── panel_manager.dart        # Drag/drop/resize infrastructure
│   │   ├── worktree_panel.dart
│   │   ├── chat_panel.dart
│   │   ├── conversation_panel.dart   # List of conversations in chat
│   │   ├── conversation_viewer_panel.dart  # Output display + input
│   │   ├── files_panel.dart
│   │   ├── file_viewer_panel.dart
│   │   └── git_status_panel.dart
│   │
│   ├── widgets/
│   │   ├── display/                  # Preserved
│   │   │   ├── tool_card.dart
│   │   │   ├── output_panel.dart
│   │   │   ├── output_entries.dart
│   │   │   ├── diff_view.dart
│   │   │   └── permission_widgets.dart
│   │   └── input/
│   │       └── message_input.dart
│   │
│   └── screens/
│       └── main_screen.dart
│
└── test/
    ├── models/
    ├── state/
    ├── panels/
    └── integration/
```

---

## Decisions Summary

| Decision | Choice |
|----------|--------|
| Core hierarchy | Project → Worktrees → Chats → Conversations |
| Conversation vs Agent | Conversation = persistent log; Agent = runtime entity |
| Multi-project support | One project at a time |
| Persistence location | JSON files in `~/.cc-insights/` |
| User-facing terminology | "Chat" (not "Session") |
| Worktree.branch | Mutable state |
| Subagent conversations | Read-only (no input) |
| Selection model | Hierarchical - each level remembers its selection |
| MVP panel binding | Everything follows selected worktree |
| File viewer | Read-only with syntax highlighting |
| Panel manager approach | Adapt from `drag_split_layout` concepts |
| Existing code | Preserve SDK, display widgets; redesign providers |

---

## Appendix: Existing Package Research

### Panel/Docking Packages Evaluated

| Package | Version | Pub Points | Notes |
|---------|---------|------------|-------|
| `drag_split_layout` | 0.1.1 | 155 | Most aligned - has drag-drop, visual previews, edge splitting |
| `panes` | 1.1.0 | 160 | IDE-focused, resizing only, no drag-drop |
| `panels` | 0.0.3 | 80 | Conceptually close but unmaintained (4 years old) |
| `fl_advanced_tab_manager` | 0.4.4 | 110 | Feature-rich but zero downloads, unproven |

### Gap Analysis

No existing package provides:
- Comprehensive ghost targets showing all valid drop positions
- Dynamic target generation based on layout structure
- "Between panels" docking to create new rows/columns

The panel manager will likely need custom implementation, potentially using `drag_split_layout` as reference.
