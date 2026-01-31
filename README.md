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

CC Insights uses ACP (Agent Client Protocol) to communicate with AI agents like Claude Code.

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
│  │                ACP Client (acp_dart)                     │   │
│  │  - Agent Client Protocol implementation                  │   │
│  │  - Session management & streaming                        │   │
│  │  - Process spawning & lifecycle                          │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ NDJSON streams (ACP)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  ACP-compatible Agent                           │
│              (e.g., Claude Code, Gemini CLI)                    │
└─────────────────────────────────────────────────────────────────┘
```



### Frontend

```bash
cd frontend

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
cc-insights/
├── packages/
│   ├── acp-dart/               # ACP Dart library
│   ├── agent-client-protocol/  # ACP specification
│   └── claude-code-acp/        # Claude Code ACP adapter
│
├── frontend/                   # Flutter desktop UI
│   ├── lib/
│   │   ├── main.dart
│   │   ├── acp/                # ACP integration layer
│   │   │   ├── acp.dart                  # Library export
│   │   │   ├── acp_client_wrapper.dart   # Agent connection wrapper
│   │   │   ├── acp_session_wrapper.dart  # Session wrapper
│   │   │   ├── cc_insights_acp_client.dart
│   │   │   ├── pending_permission.dart
│   │   │   ├── session_update_handler.dart
│   │   │   └── handlers/       # File/terminal handlers
│   │   ├── models/
│   │   ├── services/
│   │   │   ├── agent_service.dart     # ACP agent management
│   │   │   ├── agent_registry.dart    # Agent discovery
│   │   │   └── ...
│   │   ├── screens/
│   │   └── widgets/
│   └── pubspec.yaml
│
└── docs/
    ├── architecture/           # Architecture documentation
    └── sdk/                    # Agent SDK reference
```

## Protocol

Communication uses ACP (Agent Client Protocol) over NDJSON streams.
See `packages/agent-client-protocol/` for the protocol specification.

## Development

### Running Tests

```bash
# Flutter tests
cd frontend
flutter test
```

### Debug Logging

- ACP messages can be logged using the MITM tool (see Logging section above)
- Access logs in the UI via the log viewer (View -> Logs)
- Example ACP messages are in `examples/*.jsonl`

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

GNU GPL v3 
Copyright Nick Clifford
nick@nickclifford.com
