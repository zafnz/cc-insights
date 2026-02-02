# CC-Insights V2 - Project Guide

---

## ⚠️ CRITICAL: ALL TESTS MUST PASS ⚠️

**There must be NO pre-existing test failures.**

Before completing any task:
1. Run all tests using `mcp__flutter-test__run_tests`
2. Run integration tests separately: `mcp__flutter-test__run_tests(path: "integration_test/app_test.dart")`
3. **ALL tests must pass** - even if the failure wasn't caused by you, YOU MUST FIX IT

If you encounter a failing test:
- Do NOT ignore it
- Do NOT skip it
- FIX IT before considering your work complete

---

## Project Overview

CC-Insights is a desktop application for monitoring and interacting with Claude Code agents via the SDK. It provides real-time visibility into agent hierarchies, tool usage, and conversation flow.

**V2 Goals:**
- Git worktrees as a core concept (not bolt-on)
- Flexible panel-based UI
- Clean hierarchy: Project → Worktree → Chat → Conversation
- Preserve working components (Dart SDK, display widgets)

**Architecture:**
- **Dart SDK** (`claude_dart_sdk/`): Flutter/Dart SDK that communicates directly with the Claude CLI
- **Frontend** (`frontend/`): Flutter desktop app (macOS) with Provider state management

**Communication:** Dart SDK spawns the Claude CLI directly as a subprocess, communicating via stdin/stdout JSON lines using the CLI's stream-json protocol.

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
claude-project/
├── claude_dart_sdk/
│   └── lib/
│       ├── claude_sdk.dart     # Main export
│       └── src/
│           ├── cli_process.dart    # Claude CLI subprocess management
│           ├── cli_session.dart    # Direct CLI session implementation
│           ├── cli_backend.dart    # Direct CLI backend implementation
│           ├── backend_factory.dart # Backend factory for type selection
│           ├── backend_interface.dart # Abstract backend interface
│           ├── backend.dart        # Node.js backend (implements AgentBackend)
│           ├── session.dart        # Node.js session (used by BackendFactory)
│           ├── protocol.dart       # Protocol implementation (stdin/stdout)
│           └── types/              # Type definitions
│               ├── sdk_messages.dart
│               ├── control_messages.dart  # CLI control protocol types
│               └── ...
├── frontend/
│   └── lib/
│       ├── main.dart
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
│       │   ├── backend_service.dart  # Uses BackendFactory
│       │   ├── git_service.dart
│       │   └── persistence_service.dart
│       ├── panels/
│       │   ├── panel_manager.dart
│       │   ├── worktree_panel.dart
│       │   ├── chat_panel.dart
│       │   ├── conversation_panel.dart
│       │   ├── conversation_viewer_panel.dart
│       │   ├── files_panel.dart
│       │   ├── file_viewer_panel.dart
│       │   └── git_status_panel.dart
│       └── widgets/
│           ├── display/        # Preserved from V1
│           │   ├── tool_card.dart
│           │   ├── output_panel.dart
│           │   └── diff_view.dart
│           └── input/
│               └── message_input.dart
└── docs/
    ├── architecture/          # V2 architecture & implementation plan
    ├── dart-sdk/              # Dart SDK implementation docs
    └── sdk/                   # Claude Agent SDK reference
```

---

## SDK Documentation Reference

Quick reference to SDK documentation in `docs/sdk/`:

- **typescript.md** - Complete TypeScript SDK API reference
- **streaming.md** - Server-sent events streaming, extended thinking, web search
- **user-input.md** - Handling user approvals and clarifying questions
- **permissions.md** - Permission modes, canUseTool callback, tool authorization
- **hooks.md** - Event hooks (PreToolUse, PostToolUse, SessionStart, etc.)
- **sessions.md** - Session lifecycle, resuming conversations
- **subagents.md** - Creating and managing specialized subagents with Task tool
- **mcp.md** - Model Context Protocol (MCP) server integration
- **cost-tracking.md** - Token usage tracking and billing

---

## Message Flow

The Dart SDK communicates directly with the Claude CLI using stream-json format:

```
Claude CLI ← → CliProcess ← → CliSession ← → Chat model → UI
              (stdin/stdout)   (SDK messages)
```

**Initialization:**
1. `CliProcess` spawns Claude CLI with `--output-format stream-json --input-format stream-json`
2. Dart sends `control_request` with `subtype: "initialize"`
3. CLI responds with `control_response` containing available commands, models, etc.
4. CLI sends `system` message with `subtype: "init"` (tools, MCP servers, etc.)
5. Dart sends initial user message via `session.create`

**Message flow:**
```
UI → Chat.sendMessage() → CliSession.send() →
  stdin (JSON lines) → Claude CLI → Claude API
```

**Permission requests:**
```
Claude CLI → callback.request (can_use_tool) → CliSession.permissionRequests →
  UI shows permission dialog → User approves/denies →
  callback.response → Claude CLI
```

### Permission System

The SDK evaluates tool permissions in this order (first match wins):

```
1. Hooks (PreToolUse)     → Can block or modify tool calls
2. Permission Rules       → Explicit allow/deny patterns
3. allowedTools list      → Auto-approves tools
4. Permission Mode        → Mode-based auto-approval
5. canUseTool callback    → Final fallback for user approval
```

**Permission Modes:**
- `default` - Requires permission for most operations
- `acceptEdits` - Auto-approves file operations within project directory
- `plan` - Planning mode with restricted tool access
- `bypassPermissions` - Dangerous: approves everything without asking

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
2. **Not handling streaming messages** - SDK sends messages asynchronously
3. **Message type mismatches** - Always have fallback handling
4. **Widget rebuild issues** - Ensure builders listen to the right object
5. **CLI process disposal** - Always dispose CLI processes on app exit
6. **Callback response ordering** - Responses must match request IDs

---

## Keyboard Focus & Dialogs

The app uses `KeyboardFocusManager` to provide a terminal-like typing experience - users can start typing from anywhere and keystrokes go to the message input. This is implemented via `HardwareKeyboard` interception.

### DialogObserver Integration

Dialogs need keyboard input for their text fields, so the keyboard interception is automatically suspended when dialogs are open. This is handled by `DialogObserver` - a `NavigatorObserver` that tracks modal routes.

**How it works:**
1. `DialogObserver` is created in `main.dart` and registered as both a Provider and a `navigatorObserver` on `MaterialApp`
2. `MainScreen` passes the observer to `KeyboardFocusManager`
3. When a dialog opens (`showDialog`, `showMenu`, `showModalBottomSheet`), keyboard interception suspends
4. When the dialog closes, interception resumes

**For new dialogs:** Standard Flutter dialogs (`showDialog`, `showMenu`, etc.) work automatically - no special handling needed. The `DialogObserver` detects `DialogRoute`, `PopupRoute`, and `RawDialogRoute` automatically.

**For tests using MainScreen:** Include `DialogObserver` in the test providers:
```dart
late DialogObserver dialogObserver;

setUp(() {
  dialogObserver = DialogObserver();
});

Widget createTestApp() {
  return MultiProvider(
    providers: [
      Provider<DialogObserver>.value(value: dialogObserver),
      // ... other providers
    ],
    child: MaterialApp(home: const MainScreen()),
  );
}
```

---

## Debug Tools

- **Dart SDK logs**: Flutter console shows backend stderr
- **Dart DevTools**: Use `dart:developer` `log()` for structured logging
--**Example messages**: examples/*.jsonl 
---

## Architecture Documentation

For detailed V2 architecture, see:
- `docs/architecture/cc-insights-v2-architecture.md` - Data models, selection model, UI architecture
