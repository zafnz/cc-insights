# CC Insights - Insights into Claude Code

Yet another Claude Code coordinater desktop GUI application.

## Whats different this time?

- Worktrees are the first class and primary method of working (though you can just do multiple chats if you like pain)
- Designed specifically for Vibe coding, your almost exclusive focus is on Claude and what it is doing. 
- **FULL** context tracking, cost tracking, token reporting. You get to see way more!
- See exactly what subagents are doing (each agent gets its own window, or you can have them integrated)
- Works with your **existing Claude subscription**, uses authorised SDK so won't be blocked by Anthropic.
- This program does not require subscription or an account beyond what Claude requires. 

## More features

- **Multi-agent visualization** - See main agents and subagents in a tree structure
- **Real-time output streaming** - Watch Claude's responses and tool usage as they happen
- **Tool execution monitoring** - View tool inputs, outputs, and results
- **Interactive Q&A** - Answer questions from Claude directly in the UI
- **Session management** - Create, monitor, and terminate multiple sessions
- **Context management** - Continiously keep an eye on context usage, so you can compact or clear when you want, and not be surprised by Claude.
- **Cost tracking** - Monitor token usage and costs per session


## Prerequisites

- **Node** (for now)
- **Flutter 3.10+**
- **Claude account OR Anthropic API key** (so long as the claude cli program works for you, then CC Insights will work for you).

## Installation

In all cases if you are using your Claude Plan (eg Pro) you need to have the CLI installed and logged in at least once. 

### MacOS 

**COMING SOON**
(This isn't yet done, this is pre-alpha release)
```bash
brew install cc-insights
```

### Linux 

TBA

### Windows

TBA

## Usage
```
cc-insights [project_directory]
```


## Troubleshooting

## Developer Setup

### Architecture

Because I've not yet finished the Dart SDK for Claude, I'm using a typescript bridge to handle the direct talking to claude binary.

It's not beautiful, but it works surprisingly well. The Node.js backend will go away soon, hopefully.

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
│  │  - Type-safe protocol layer                              │   │
│  │  - Session management & streaming                        │   │
│  │  - Subprocess spawning & lifecycle                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ stdin/stdout (JSON lines)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│      Node.js Backend (thin subprocess - protocol bridge)        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Session Manager + Callback Bridge                       │   │
│  │  - Forwards SDK messages to Flutter via stdout           │   │
│  │  - Receives commands from Flutter via stdin              │   │
│  │  - Bridges callbacks (canUseTool, askUserQuestion, etc.) │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Claude Agent SDK (TypeScript)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Claude API                                 │
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

Seeing whats happening is exciting. There is inbuilt logging window in the app that shows logs from the backend, but not detailed communications messages.

There is a Man-in-the-Middle script in tools/mitm.py, you use it by copying the actual claude binary (use `which claude` on macOS/Linux to find it) into `tools/_real_claude`, then start the app as:

```bash
CLAUDE_CODE_PATH="<path-to-tools-dir>/claude-mitm.py" flutter run \
     --dart-entrypoint-args="<your-project-dir>" 
```

Those logs go to `~/claude_mitm.log`, and are parsable with `jq`. 


## Project Structure

```
claude-project/
├── backend-node/           # Node.js backend (subprocess)
│   ├── src/
│   │   ├── index.ts        # Entry point (stdin/stdout)
│   │   ├── session-manager.ts  # SDK session lifecycle
│   │   ├── callback-bridge.ts  # SDK callback handling
│   │   ├── protocol.ts     # Type-safe message definitions
│   │   ├── message-queue.ts    # Reliable message delivery
│   │   └── logger.ts       # Structured logging
│   ├── test/
│   │   └── test-client.js  # Protocol testing
│   └── package.json
│
├── dart_sdk/               # Dart SDK for Flutter
│   ├── lib/
│   │   ├── claude_sdk.dart # Main export
│   │   ├── src/
│   │   │   ├── backend.dart    # Subprocess management
│   │   │   ├── session.dart    # Session API
│   │   │   ├── protocol.dart   # Protocol implementation
│   │   │   └── types/          # Type definitions
│   │   │       ├── callbacks.dart
│   │   │       ├── content_blocks.dart
│   │   │       ├── sdk_messages.dart
│   │   │       ├── session_options.dart
│   │   │       └── usage.dart
│   └── pubspec.yaml
│
├── flutter_app/            # Flutter desktop UI
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/
│   │   │   └── session.dart
│   │   ├── providers/
│   │   │   └── session_provider.dart
│   │   ├── services/
│   │   │   └── backend_service.dart  # Backend lifecycle
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
    └── sdk/                # Claude Agent SDK reference
```

## Protocol

Communication between the Dart SDK and Node.js backend uses JSON lines over stdin/stdout.

### Flutter → Backend (stdin)

| Message Type | Description |
|--------------|-------------|
| `session.create` | Create a new Claude session |
| `session.send` | Send user message to session |
| `session.interrupt` | Interrupt running session |
| `session.kill` | Terminate a session |
| `callback.response` | Response to callback request |
| `query.call` | Call query method on session |

### Backend → Flutter (stdout)

| Message Type | Description |
|--------------|-------------|
| `session.created` | Session created successfully |
| `sdk.message` | SDK message (streaming) |
| `callback.request` | Request user permission/input |
| `query.result` | Query method result |
| `session.interrupted` | Session interrupted |
| `session.killed` | Session terminated |
| `error` | Error occurred |

See `docs/dart-sdk/02-protocol.md` for complete protocol specification.

## Development

### Running Tests

```bash
# Backend tests
cd backend-node
npm test

# Dart SDK tests
cd dart_sdk
dart test

# Flutter tests
cd flutter_app
flutter test
```

### Debug Logging

- Backend logs all messages to `/tmp/messages.jsonl`
- Backend structured logs to `/tmp/backend-{timestamp}.log`
- Access logs in the UI via the log viewer (View → Logs)

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Your Anthropic API key (if not using Claude Plan) | Optional |
| `CLAUDE_CODE_PATH` | Path to claude binary (avoids Node v25 compatibility issues) | Auto-detected |

### Model Selection

Available models:
- `sonnet` - Claude Sonnet (fast and capable)
- `opus` - Claude Opus (most powerful)
- `haiku` - Claude Haiku (quick and efficient)

## License

Private project - not for distribution.
