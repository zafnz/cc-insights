# CC-Insights V2 - Project Guide

---

## ⚠️ CRITICAL: ALL TESTS MUST PASS ⚠️

**There must be NO pre-existing test failures.**

Before completing any task:
1. Run all tests (`flutter test` for unit/widget tests)
2. Run integration tests (`flutter test integration_test -d macos`)
3. **ALL tests must pass** - even if the failure wasn't caused by you, YOU MUST FIX IT

If you encounter a failing test:
- Do NOT ignore it
- Do NOT skip it
- FIX IT before considering your work complete

---

## Project Overview

CC-Insights is a desktop application for monitoring and interacting with AI coding agents via ACP (Agent Client Protocol). It provides real-time visibility into agent hierarchies, tool usage, and conversation flow.

**V2 Goals:**
- Git worktrees as a core concept (not bolt-on)
- Flexible panel-based UI
- Clean hierarchy: Project → Worktree → Chat → Conversation
- Multi-agent support via ACP

**Architecture:**
- **ACP Integration** (`frontend/lib/acp/`): Agent Client Protocol wrappers for Dart/Flutter
- **Frontend** (`frontend/`): Flutter desktop app (macOS) with Provider state management
- **ACP Dart Package** (`packages/acp-dart/`): Dart implementation of ACP protocol

**Communication:** Frontend uses ACP (Agent Client Protocol) to communicate with agents via NDJSON streams. Any ACP-compatible agent (Claude Code, Gemini CLI, etc.) can be used.

---

## Core Concepts

### Terminology

| Term | Definition |
|------|------------|
| **Project** | A git repository. Contains one primary worktree and zero or more linked worktrees. |
| **Worktree** | A git working tree with files. Has a path and a branch. |
| **Primary Worktree** | The worktree at the repository root (where `.git` lives). |
| **Linked Worktree** | A worktree created via `git worktree add`. Points back to the primary's `.git`. |
| **Chat** | A user-facing conversation unit. Belongs to a worktree. Contains conversations and optionally an active SDK session. |
| **Conversation** | A persistent log of messages/output. Survives session lifecycle. Each chat has a primary conversation and zero or more subagent conversations. |
| **Agent** | A runtime SDK entity. Exists only while a session is active. Links to a Conversation for output storage. |
| **Session** | Internal SDK concept. Users see "Chats", not "Sessions". |

### Hierarchy

```
Project: CC-Insights
├── Worktree (primary)
│   ├── Branch: main
│   └── Chats:
│       ├── Chat 1
│       │   ├── Primary Conversation
│       │   └── Subagent Conversations...
│       └── Chat 2
│
└── Worktree (linked)
    ├── Branch: feat-dark-mode
    └── Chats:
        └── Chat 1
```

### Key Rules

- A project has exactly one primary worktree (the repo root)
- Worktree branches are mutable (can change via `git checkout`)
- Conversations are persistent; Agents are runtime-only
- Users interact with the primary conversation; subagent conversations are read-only
- Subagents can still request permissions (routed to their conversation)

---

## Directory Structure

```
cc-insights/
├── packages/
│   ├── acp-dart/               # ACP Dart library
│   ├── agent-client-protocol/  # ACP specification
│   └── claude-code-acp/        # Claude Code ACP adapter
│
├── frontend/
│   └── lib/
│       ├── main.dart
│       ├── acp/                # ACP integration layer
│       │   ├── acp.dart                  # Library export
│       │   ├── acp_client_wrapper.dart   # Main client wrapper
│       │   ├── acp_session_wrapper.dart  # Session wrapper
│       │   ├── cc_insights_acp_client.dart  # Client implementation
│       │   ├── pending_permission.dart   # Permission model
│       │   ├── session_update_handler.dart  # Update routing
│       │   └── handlers/
│       │       ├── fs_handler.dart       # File system handler
│       │       └── terminal_handler.dart # Terminal handler
│       ├── models/
│       │   ├── project.dart
│       │   ├── worktree.dart
│       │   ├── chat.dart
│       │   ├── conversation.dart
│       │   ├── agent.dart
│       │   └── output_entry.dart
│       ├── state/
│       │   └── selection_state.dart
│       ├── services/
│       │   ├── agent_service.dart     # ACP agent management
│       │   ├── agent_registry.dart    # Agent discovery
│       │   ├── git_service.dart
│       │   └── persistence_service.dart
│       ├── panels/
│       │   ├── panel_manager.dart
│       │   ├── worktree_panel.dart
│       │   ├── chat_panel.dart
│       │   ├── conversation_panel.dart
│       │   └── ...
│       └── widgets/
│           ├── display/        # Display components
│           │   ├── tool_card.dart
│           │   ├── output_panel.dart
│           │   └── diff_view.dart
│           └── input/
│               └── message_input.dart
└── docs/
    ├── architecture/          # V2 architecture & implementation plan
    └── sdk/                   # Claude Agent SDK reference
```

---

## ACP (Agent Client Protocol)

ACP is a standardized protocol for communicating with AI coding agents. CC-Insights uses ACP to support multiple agents (Claude Code, Gemini CLI, etc.) through a unified interface.

### Key ACP Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `ACPClientWrapper` | `frontend/lib/acp/` | Manages agent process lifecycle |
| `ACPSessionWrapper` | `frontend/lib/acp/` | Wraps session with filtered streams |
| `CCInsightsACPClient` | `frontend/lib/acp/` | Implements ACP Client interface |
| `AgentService` | `frontend/lib/services/` | Provider-based agent management |
| `AgentRegistry` | `frontend/lib/services/` | Agent discovery and configuration |

### Message Flow

Communication uses ACP over NDJSON streams:

```
ACP Agent (Claude Code, etc.)
        ↕ NDJSON (stdin/stdout)
ACPClientWrapper
        ↕ Dart Streams
ACPSessionWrapper → SessionUpdateHandler → ChatState
        ↕
      UI
```

User input flows through the ACP session:
```
UI → ChatState.sendMessage() → ACPSessionWrapper.prompt() → Agent
```

### Permission System

Agents request permissions through ACP. CC-Insights handles:
- `requestPermission` - Agent asks for tool permission
- User responds via `AcpPermissionDialog`
- Response sent back through `PendingPermission.allow()` or `cancel()`

Permission options can include:
- Allow once
- Allow for session
- Deny
- Custom options provided by agent

---

## Programming Standards

### Code Quality Principles

**1. Keep It Simple**
- Solve the current problem, not hypothetical future ones
- Three similar lines are better than a premature abstraction
- Don't add features beyond what was requested

**2. Read Before Write**
- Always read existing code before modifying
- Understand the patterns already in use
- Match existing style and conventions

**3. Minimal Changes**
- Only modify what's necessary
- Don't refactor unrelated code
- Don't add comments to code you didn't change

**4. No Dead Code**
- Delete unused code completely
- No `// removed` comments or `_unusedVar` renames
- No backwards-compatibility shims for removed features

---

## Flutter/Dart Standards

### Project Structure
- Standard Flutter structure with `lib/main.dart` as entry point
- Organize by feature for larger projects
- Logical layers: Presentation (widgets/panels), Domain (business logic), Data (models/services)

### Code Quality
- **SOLID principles** throughout the codebase
- **Composition over inheritance** for widgets and logic
- **Immutability** - prefer immutable data structures
- **Concise and declarative** - functional patterns where appropriate
- **80 character line length**
- **Naming**: `PascalCase` for classes, `camelCase` for members/functions, `snake_case` for files

### State Management
- Use `ChangeNotifier` for state classes that need to notify listeners
- Use the `provider` package to make state accessible throughout the widget tree
- Use `context.watch<T>()` to listen and rebuild, `context.read<T>()` for one-time access
- Use `ValueNotifier` with `ValueListenableBuilder` for simple local state
- Call `notifyListeners()` after state changes
- Separate ephemeral state from app state
- Avoid prop drilling - let widgets access state via Provider

### Widget Best Practices
- Prefer composition over inheritance
- Use small, private Widget classes instead of helper methods returning Widget
- Use `const` constructors whenever possible
- Use `ListView.builder` for long lists (lazy loading)
- Avoid expensive operations in `build()` methods

### Null Safety & Async
- Write soundly null-safe code
- Avoid `!` unless value is guaranteed non-null
- Use `async`/`await` for asynchronous operations
- Use `Stream`s for sequences of async events
- Proper error handling with `try-catch`

### Theming
- Material 3 with `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`
- Support both light and dark themes
- Use `ThemeExtension` for custom design tokens
- JetBrains Mono for code/monospace text

---

## Testing Requirements

**See `TESTING.md` for comprehensive testing guidelines, helpers, and patterns.**

### Critical Rules

1. **Never use `pumpAndSettle()` without timeout** - Use `safePumpAndSettle()` from `test/test_helpers.dart`
2. **Always clean up resources in `tearDown()`** - Use `TestResources` to track them
3. **Prefer `pumpUntil()` over arbitrary delays** - Wait for conditions, not time

### Test Helpers (frontend/test/test_helpers.dart)

```dart
// Safe pump with 3s default timeout
await safePumpAndSettle(tester);

// Wait for condition
await pumpUntil(tester, () => find.text('Done').evaluate().isNotEmpty);
await pumpUntilFound(tester, find.text('Done'));
await pumpUntilGone(tester, find.byType(CircularProgressIndicator));

// Resource tracking
final resources = TestResources();
tearDown(() async => await resources.disposeAll());
final state = resources.track(MyState());
final controller = resources.trackStream<String>();
```

### Test Organization
```
frontend/test/
├── test_helpers.dart          # Shared helpers - USE THESE
├── widget/                    # Widget tests (fast, no device)
├── models/                    # Unit tests for models
└── integration/               # Integration tests (need device)
```

### Running Tests

**CRITICAL FOR CLAUDE: Always use Flutter-Test MCP tools for testing. Never use Bash commands like `flutter test`.**

- **`mcp__flutter-test__run_tests`** - Run tests (NOT `flutter test`)
- **`mcp__flutter-test__get_test_result`** - Fetch detailed test results for a specific test ID

**IMPORTANT: When a test fails, use `get_test_result` with the test ID from `run_tests` output.
DO NOT try to read the output file directly with Read, Grep, or Bash commands.
The `get_test_result` tool is specifically designed to parse and return the relevant test output.**

---

## Common Pitfalls

1. **Forgetting to notify listeners** - State changes without `notifyListeners()` won't update UI
2. **Not handling streaming messages** - ACP sends messages asynchronously via streams
3. **Message type mismatches** - Always handle unknown ACP update types gracefully
4. **Widget rebuild issues** - Ensure builders listen to the right object
5. **Agent disposal** - Always dispose AgentService on app exit
6. **Permission response ordering** - Permission responses must match request IDs

---

## Debug Tools

- **Flutter console**: Shows agent stderr and ACP communication errors
- **Dart DevTools**: Use `dart:developer` `log()` for structured logging
- **MITM logging**: Use `tools/mitm.py` to log all ACP messages (see README.md)
- **Example messages**: `examples/*.jsonl` contains sample ACP message flows

---

## Architecture Documentation

For detailed V2 architecture, see:
- `docs/architecture/cc-insights-v2-architecture.md` - Data models, selection model, UI architecture
- `docs/architecture/acp-implementation-plan.md` - ACP integration implementation plan
