![GitHub Release](https://img.shields.io/github/v/release/zafnz/cc-insights)
![Static Badge](https://img.shields.io/badge/Vibe_Coded-100%25-blue)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/zafnz/cc-insights/build-desktop.yml)
![GitHub License](https://img.shields.io/github/license/zafnz/cc-insights)

# CC Insights - Insights into Claude & Codex

Yet another AI coordinator desktop GUI application.

## What's different this time?
<img align=right width="600" height="500" src="https://github.com/user-attachments/assets/f3b14f67-d1a1-4863-b125-15dda89609f2" />

- Uses agents local CLI, so uses your subscription _without_ breaking terms-of-service. 
- **Worktrees** are the first class and primary method of working (though you can just do multiple chats if you like pain)
- Designed specifically for **Vibe coding** - your almost exclusive focus is on the AI agents and what they are doing.
- **FULL** context tracking, cost tracking, token reporting. You get to see way more!
- See exactly what **subagents** are doing (each agent gets its own window, or you can have them integrated)
- Works with your **existing Claude/Codex subscriptions** - uses the authorised methods to communicate with no hacks or workarounds.
- This program does not require a subscription or an account beyond what Claude/Codex requires.

## Claude & Codex

This application primarily works with Claude, and Codex support is rapidly evolving. Gemini and other ACP clients works but work is still needed.

Authentication is entirely handled by the claude, codex, gemini clis, using your own subscription. All costs shown are estimated based on token usage.

## More features
<img align=right width="400" height="450" alt="Screenshot 2026-02-24 at 15 28 11" src="https://github.com/user-attachments/assets/d323190b-9bdb-4bbf-89a6-668352bc8d24" />

- **Multi-agent visualization** - See main agents and subagents of claude in a tree structure
- **Cost and Token Statistics** - A breakdown of agent usage and equivalent cost (how much you'd pay if you were paying direct API costs).
- **Real-time output streaming** - Watch the agents' responses and tool usage as they happen
- **Tool execution monitoring** - View tool inputs, outputs, and results
- **Session management** - Create, monitor, and terminate multiple sessions
- **Context management** - Continuously keep an eye on context usage, so you can compact or clear when you want, and not be surprised by Claude.
- **Cost tracking** - Monitor token usage and costs per session

<table>
  <tr>
     <td>Token cost tracking</td>
     <td>Context tracking</td>
    <td>Context output</td>
  </tr>
  <tr>
    <td valign="top">
      <img width="180" height="252" alt="token-cost-tracking" src="https://github.com/user-attachments/assets/c1ed42e4-606c-418b-bbf3-20b1c6f27515" />
    </td>
    <td valign="top">
      <img width="200" height="171" alt="context-tracking" src="https://github.com/user-attachments/assets/a90d483a-5d5c-4508-8b08-3fc9de8335f2" />
    </td>
    <td valign="top">
      <img width="200" height="193" alt="Screenshot 2026-02-03 at 16 59 33" src="https://github.com/user-attachments/assets/735f3c86-ad83-43cb-ab07-70af5ce97458" />
    </td>
    
  </tr>
</table>

## 30 second HOWTO

Open up the app, either from whatever menu you have (Start Menu/App menu/etc) or from a terminal as `cc-insights`. Select a git repo. You can immediately start chatting in the middle. When you're ready to work on a feature branch, click "New Worktree" on the top left and everything you develop in there will not interfere with your main branch until you are ready. You can also wire up the Run/Test action buttons by right-clicking on them so you can run your app from the worktree directly.

When you are ready you can create a PR on origin/main, or work locally and merge your work into main. In all cases there is Claude who will help you through any merge conflicts you may encounter. 

## Installation

Note: This is still in very early development, if you find something doesn't work PLEASE [file an issue](https://github.com/zafnz/cc-insights/issues) ticket.

**MacOS**
```bash
brew tap zafnz/cc-insights
brew install --cask cc-insights
```
Or download the .dmg from the [latest releases](https://github.com/zafnz/cc-insights/releases/latest/download/cc-insights-macos.dmg)

**Linux**
```bash
wget https://github.com/zafnz/cc-insights/releases/latest/download/cc-insights-linux-x64.AppImage
chmod +x cc-insights-linux-x64.AppImage
./cc-insights-linux-x64.AppImage
```
Or download the tarball from [latest release](https://github.com/zafnz/cc-insights/releases/latest/download/cc-insights-linux-x64.tar.gz)

**Windows**

Apparently with an unsigned application the installer is problematic, so the easiest way is to download the [latest zip release](https://github.com/zafnz/cc-insights/releases/latest/download/cc-insights-windows-portable.zip) and extract it.

If you want there is the [installer here](https://github.com/zafnz/cc-insights/releases/latest/download//CC-Insights-Setup.msix) but apparently it presents code sign warnings.

## Feature readiness

This is in serious pre-alpha release. It's only for those who really want to see what is going on - lots of features aren't actually there or barely work:
| Feature | Status | Notes |
|---------|--------|-------|
| 🌳 Create git worktree | ✅ | |
| ␡ Delete git worktree | ✅ | |
| 📝 Commit all | ✅ | |
| ⤵️ Rebase on main | ✅ |  |
| 🔁 Merge main into branch | ✅ |  |
| 🧙 Merge resolution wizard | ✅ | |
| ⚙️ Settings Screen | ✅ | |
| 📁 File Manager | ✅ | Basic view only |
| 🖥️ Session Resume | ✅ | Full automatic resume of chat session |
| 👾 Claude Dart SDK | ✅ | Can talk direct to claude cli |
| 🪵 Logging | ✅ | Fully working |
| 💰 Cost & token tracking | ✅ | Per-session and per-model breakdown |
| 📊 Context usage monitoring | ✅ | Live context window usage with warnings |
| 🖼️ Message input with image attachments | ✅ | Paste, drag-and-drop, or pick images |
| 🧩 Drag-and-drop panel layout | ✅ | Flexible resizable panels |
| 📦 Auto containerisation | ❌ | |
| 📊 Statistics | ✅ | Full stats of usage by backend, worktree, chat, etc |
| 📋 Task management | ❌ | Basics in place now |
| 🤖 Z.ai GLM subscription | ❌ | With remapper this now essentially works, but is manual |
| 🧠 Codex backend | ✅ | 1st class citizen |
| 🧠 ACP(Gemini) backend | 🫤 | Works, but not well |

## Proudly Self Hoisted

Only the first day or so involved running the claude cli. As soon as a functioning window was established ALL of the development was done using itself. What's more is this app is entirely vibe coded. I have made zero code changes by hand. It probably shows -- I'm good at many languages, but Dart isn't one of them.

### Development methodology 

As noted, this application was entirely vibe coded and done using this app from very early days. Bug fixes are done with a new chat window, but large feature work has a more in-depth process:

#### Bigger features

The majority of the large feature work was done with a multi-agent approach, telling one chat it is an architect and getting the plan developed, telling another it is the project planner and dividing all the work into a detailed plan broken down into discrete chunks, specifying goals.

Finally another chat session I tell it that it is a project manager, and that its workflow is as follows:

For each task:
1) Create a flutter programming expert subagent, and have that agent read FLUTTER.md and TESTING.md. 
2) Give that agent the task and tell them to work until they have produced all deliverables.
3) Have a _different_ subagent perform the tests and validate they work. Ensure this agent also reads TESTING.md. There are no pre-existing issues, all test failures must be reported.
4) Any test failures go to step 1. after they are fixed go to step 2 again.
5) Once all tests pass have a code reviewer agent inspect the code and ensure that it meets all the deliverables and meets the FLUTTER.md style guide.
6) If there are any issues go back to step 1.
7) Once all issues are fixed commit the code.

At the end of each phase, have an architect review the plan and implementation and confirm they still make sense. Stop if the plan should be altered.

And that's it. That's how most of this app was produced. Once worktrees were functional things went MUCH faster. Having multiple features being worked on at once made things very fast.

And once the merge assist was working it was easy.

I hope you too can use Claude to its maximum potential.
(Btw -- I might be adding a new backend soon.)



## Development

If you wish to contribute, this section is for you.

### Prerequisites

- **Flutter 3.10+**
- **Claude CLI** - Install with `npm install -g @anthropic-ai/claude-code` or via your package manager
- **Claude account OR Anthropic API key** - As long as the `claude` CLI works for you, CC-Insights will work for you
- **Codex CLI** (Optional)

### Architecture

CC-Insights uses a **multi-backend architecture** with a unified event protocol. Each backend SDK converts its native wire format into typed `InsightsEvent` objects, which the frontend consumes through an `EventTransport` abstraction. No Node.js backend required.
<img width="1536" height="1024" alt="flutter-app-diagram" src="https://github.com/user-attachments/assets/1bdf1d2c-5db5-4a2b-82c1-b2d8582ae6f5" />

### Frontend

```bash
cd flutter_app

# Get dependencies
flutter pub get

# Run the app (macOS)
flutter run -d macos

# If you want to start it in a different directory (eg your project dir)
flutter run --dart-entrypoint-args="<your-project-dir>" 
```

### Logging

Seeing what's happening is exciting. There is an inbuilt logging window in the app that shows logs from the backend, but not detailed communication messages.

There is a man-in-the-middle script in tools/mitm.py. You use it by copying the actual claude binary (use `which claude` on macOS/Linux to find it) into `tools/_real_claude`, then start the app as:

```bash
CLAUDE_CODE_PATH="<path-to-tools-dir>/claude-mitm.py" flutter run \
     --dart-entrypoint-args="<your-project-dir>" 
```

Those logs go to `~/claude_mitm.log` and are parsable with `jq`.


## Project Structure

```
cc-insights/
├── agent_sdk_core/                   # Shared SDK types and interfaces
│   ├── lib/
│   │   ├── agent_sdk_core.dart       # Main export
│   │   └── src/
│   │       ├── backend_interface.dart # AgentSession/AgentBackend interfaces
│   │       ├── transport/            # Transport abstraction layer
│   │       │   ├── event_transport.dart  # EventTransport interface
│   │       │   └── in_process_transport.dart
│   │       └── types/                # Shared type definitions
│   │           ├── insights_events.dart   # InsightsEvent sealed hierarchy
│   │           ├── backend_commands.dart  # BackendCommand sealed hierarchy
│   │           ├── backend_provider.dart  # Provider enum (claude, codex, etc.)
│   │           ├── tool_kind.dart         # ACP-aligned tool categories
│   │           ├── callbacks.dart
│   │           ├── content_blocks.dart
│   │           ├── control_messages.dart
│   │           ├── session_options.dart
│   │           └── usage.dart
│
├── claude_dart_sdk/                  # Claude CLI backend
│   ├── lib/
│   │   ├── claude_sdk.dart           # Main export (re-exports agent_sdk_core)
│   │   └── src/
│   │       ├── cli_process.dart      # CLI subprocess management
│   │       ├── cli_session.dart      # Session impl (emits InsightsEvents)
│   │       ├── cli_backend.dart      # Backend implementation
│   │       ├── backend_factory.dart  # Backend type selection
│   │       └── sdk_logger.dart       # SDK logging
│   └── docs/                         # SDK documentation
│
├── codex_dart_sdk/                   # OpenAI Codex backend
│   ├── lib/
│   │   └── src/
│   │       ├── codex_process.dart    # Codex CLI subprocess
│   │       ├── codex_session.dart    # Session impl (emits InsightsEvents)
│   │       ├── codex_backend.dart    # Backend implementation
│   │       └── json_rpc.dart         # JSON-RPC 2.0 protocol
│
├── frontend/                         # Flutter desktop app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── config/
│   │   │   └── fonts.dart            # Font configuration
│   │   ├── models/                   # Data models
│   │   │   ├── project.dart
│   │   │   ├── worktree.dart
│   │   │   ├── chat.dart
│   │   │   ├── conversation.dart
│   │   │   ├── agent.dart
│   │   │   ├── output_entry.dart
│   │   │   ├── cost_tracking.dart
│   │   │   └── context_tracker.dart
│   │   ├── state/                    # State management
│   │   │   ├── selection_state.dart
│   │   │   ├── file_manager_state.dart
│   │   │   └── theme_state.dart
│   │   ├── services/                 # Business logic
│   │   │   ├── backend_service.dart  # SDK integration + transport creation
│   │   │   ├── event_handler.dart    # InsightsEvent → OutputEntry processing
│   │   │   ├── git_service.dart
│   │   │   ├── worktree_service.dart
│   │   │   ├── persistence_service.dart
│   │   │   └── settings_service.dart
│   │   ├── screens/                  # Full-screen views
│   │   ├── panels/                   # UI panels
│   │   ├── widgets/                  # Reusable widgets
│   │   │   ├── output_entries/       # Output entry widgets
│   │   │   └── file_viewers/         # File viewer widgets
│   │   └── testing/                  # Test utilities
│   └── test/                         # Tests
│
├── examples/                         # Example JSONL message logs
├── tools/                            # Development utilities
│
├── docs/
│   ├── anthropic-agent-cli-sdk/      # Claude SDK reference
│   ├── dart-sdk/                     # Dart SDK implementation docs
│   ├── architecture/                 # Architecture documentation
│   ├── features/                     # Feature documentation
│   └── insights-protocol/            # InsightsEvent protocol docs
│
├── CLAUDE.md                         # Claude agent instructions
├── AGENTS.md                         # Agent definitions
├── TESTING.md                        # Testing guidelines
├── FLUTTER.md                        # Flutter standards
└── README.md
```

## Protocol

CC-Insights uses the **InsightsEvent protocol** - a provider-neutral event model that unifies communication across multiple AI coding agent backends.

### InsightsEvent (Backend → Frontend)

All backends emit typed `InsightsEvent` objects:

| Event Type | Description |
|------------|-------------|
| `SessionInitEvent` | Session established (model, tools, capabilities) |
| `TextEvent` | Text output (regular, thinking, plan, error) |
| `ToolInvocationEvent` | Tool invoked (with ACP-aligned `ToolKind`) |
| `ToolCompletionEvent` | Tool completed (with result/error) |
| `TurnCompleteEvent` | Turn finished (cost, usage, duration) |
| `PermissionRequestEvent` | Backend needs user permission |
| `StreamDeltaEvent` | Partial content during streaming |
| `SubagentSpawnEvent` | Subagent was spawned |
| `ContextCompactionEvent` | Context was compacted |
| `SessionStatusEvent` | Backend status change |

### BackendCommand (Frontend → Backend)

| Command Type | Description |
|--------------|-------------|
| `SendMessageCommand` | Send user message |
| `PermissionResponseCommand` | Allow/deny permission request |
| `InterruptCommand` | Interrupt running session |
| `KillCommand` | Terminate session |
| `SetModelCommand` | Change model mid-session |
| `SetPermissionModeCommand` | Change permission mode |

See `docs/insights-protocol/` for the complete protocol specification including backend-specific mappings.

## Development

### Running Tests

```bash
# Dart SDK tests
cd claude_dart_sdk
dart test

# Flutter tests
cd frontend
flutter test

# Integration tests (requires Claude CLI and CLAUDE_INTEGRATION_TESTS=true)
cd claude_dart_sdk
CLAUDE_INTEGRATION_TESTS=true dart test test/integration/
```

### Debug Logging

- Use the MITM proxy (see Logging section) to capture CLI communication
- Access logs in the UI via the log viewer (View -> Logs)

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key (if not using Claude Plan) | Optional |
| `CLAUDE_CODE_PATH` | Path to the Claude CLI executable | Auto-detected (`claude` in PATH) |

### Model Selection

Available models:
- `sonnet` - Claude Sonnet (fast and capable)
- `opus` - Claude Opus (most powerful)
- `haiku` - Claude Haiku (quick and efficient)

## License

GNU GPL v3
Copyright Nick Clifford
nick@nickclifford.com
