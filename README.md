# CC Insights - Insights into Claude Code

Yet another Claude Code coordinator desktop GUI application.

## What's different this time?
<img align=right width="500" height="458" alt="appscreen2" src="https://github.com/user-attachments/assets/72535e11-8ec8-4fe6-b261-91046a86bb34" />

- **Worktrees** are the first class and primary method of working (though you can just do multiple chats if you like pain)
- Designed specifically for **Vibe coding** - your almost exclusive focus is on Claude and what it is doing.
- **FULL** context tracking, cost tracking, token reporting. You get to see way more!
- See exactly what **subagents** are doing (each agent gets its own window, or you can have them integrated)
- Works with your **existing Claude subscription** - uses the authorised SDK so won't be blocked by Anthropic.
- This program does not require a subscription or an account beyond what Claude requires.


## More features

- **Multi-agent visualization** - See main agents and subagents in a tree structure
- **Real-time output streaming** - Watch Claude's responses and tool usage as they happen
- **Tool execution monitoring** - View tool inputs, outputs, and results
- **Interactive Q&A** - Answer questions from Claude directly in the UI
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

When you are ready to merge your feature in you can use standard git tools, or the UI to commit all changes, rebase onto main, and then merge into main. Super easy, barely an inconvenience.

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
| ⤵️ Rebase on main | ❌ | Not yet there |
| 🔁 Merge main into branch | ❌ | Needs merge resolution |
| 🧙 Merge resolution wizard | ❌ | |
| ⚙️ Settings Screen | ❌ | |
| 📁 File Manager | ✅ | Basic view only |
| 🖥️ Session Resume | ✅ | Full automatic resume of chat session |
| 👾 Claude Dart SDK | ✅ | Can talk direct to claude cli |
| 🪵 Logging | ❌ | UI not working, file logging is |
| 💰 Cost & token tracking | ✅ | Per-session and per-model breakdown |
| 📊 Context usage monitoring | ✅ | Live context window usage with warnings |
| 🖼️ Message input with image attachments | ✅ | Paste, drag-and-drop, or pick images |
| 🧩 Drag-and-drop panel layout | ✅ | Flexible resizable panels |
| 📦 Auto containerisation | ❌ | |
| 🤖 Z.ai GLM subscription | ❌ | Coming soon |
| 🧠 Codex backend | ❌ | Coming soon |

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

### Architecture

CC-Insights communicates directly with the Claude CLI using the stream-json protocol. No Node.js backend required.

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter Desktop App                        │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │ Session List │  │  Agent Tree  │  │     Output Panel      │  │
│  │              │  │              │  │  - Text output        │  │
│  │ - Sessions   │  │ - Main       │  │  - Tool use/results   │  │
│  │ - Status     │  │ - Subagents  │  │  - Questions          │  │
│  │ - Costs      │  │ - Status     │  │  - Markdown render    │  │
│  └──────────────┘  └──────────────┘  └───────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  Dart SDK (claude_sdk)                   │   │
│  │  - Direct CLI process management                         │   │
│  │  - Type-safe protocol layer                              │   │
│  │  - Session management & streaming                        │   │
│  │  - Permission request handling                           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ stdin/stdout (JSON lines)
                              │ --output-format stream-json
                              │ --input-format stream-json
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Claude CLI (claude)                        │
│  - Spawned directly by Dart SDK                                 │
│  - One process per session                                      │
│  - Handles tool execution, permissions, MCP servers             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Claude API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Anthropic API                              │
└─────────────────────────────────────────────────────────────────┘
```



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
claude-project/
├── claude_dart_sdk/               # Dart SDK for Flutter
│   ├── lib/
│   │   ├── claude_sdk.dart     # Main export
│   │   ├── src/
│   │   │   ├── cli_process.dart    # CLI subprocess management
│   │   │   ├── cli_session.dart    # Direct CLI session
│   │   │   ├── cli_backend.dart    # Direct CLI backend
│   │   │   ├── backend_factory.dart # Backend type selection
│   │   │   ├── backend_interface.dart # Abstract backend interface
│   │   │   ├── protocol.dart       # Protocol implementation
│   │   │   └── types/              # Type definitions
│   │   │       ├── sdk_messages.dart
│   │   │       ├── control_messages.dart
│   │   │       ├── callbacks.dart
│   │   │       ├── content_blocks.dart
│   │   │       ├── session_options.dart
│   │   │       └── usage.dart
│   └── pubspec.yaml
│
├── frontend/               # Flutter desktop UI
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   │   └── session.dart
│   │   ├── providers/
│   │   │   └── session_provider.dart
│   │   ├── services/
│   │   │   └── backend_service.dart  # Uses BackendFactory
│   │   ├── screens/
│   │   │   └── home_screen.dart
│   │   └── widgets/
│   │       ├── session_list.dart
│   │       ├── agent_tree.dart
│   │       ├── output_panel.dart
│   │       ├── input_panel.dart
│   │       ├── log_viewer.dart
│   │       └── message_input.dart
│   └── pubspec.yaml
│
└── docs/
    ├── dart-sdk/           # Dart SDK implementation docs
    └── sdk/                # Claude CLI reference
```

## Protocol

The Dart SDK communicates directly with the Claude CLI using the stream-json protocol over stdin/stdout.

### Dart SDK → Claude CLI (stdin)

| Message Type | Description |
|--------------|-------------|
| `control_request` | Initialize session, configure options |
| `session.create` | Start a new conversation |
| `session.send` | Send user message to session |
| `session.interrupt` | Interrupt running session |
| `callback.response` | Response to permission request |

### Claude CLI → Dart SDK (stdout)

| Message Type | Description |
|--------------|-------------|
| `control_response` | Response to control request |
| `session.created` | Session created successfully |
| `system` | System messages (init, tools, etc.) |
| `assistant` | Assistant responses with content |
| `user` | User messages and tool results |
| `result` | Turn completion status |
| `callback.request` | Permission request (can_use_tool) |
| `error` | Error occurred |

See `docs/dart-sdk/02-protocol.md` for complete protocol specification.

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
