# Node Backend Implementation

This document describes the implementation of the thin Node.js backend.

## Overview

The backend is a minimal bridge between the Dart SDK and the Claude Agent SDK. It:

1. Reads JSON lines from stdin
2. Routes messages to appropriate handlers
3. Forwards SDK messages to stdout
4. Bridges callbacks (canUseTool, hooks)
5. Proxies Query method calls

**Target size:** ~200 lines of TypeScript

## File Structure

```
backend-node/
├── src/
│   ├── index.ts              # Entry point, stdin/stdout loop
│   ├── session-manager.ts    # Session lifecycle
│   ├── callback-bridge.ts    # Pending callback management
│   └── protocol.ts           # Message type definitions
├── package.json
├── tsconfig.json
└── test/
    └── test-client.js        # Simple test client
```

## Dependencies

```json
{
  "dependencies": {
    "@anthropic-ai/claude-agent-sdk": "^0.x.x",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.x.x",
    "@types/uuid": "^9.x.x",
    "typescript": "^5.x.x"
  }
}
```

## Implementation

### index.ts

Entry point: stdin/stdout JSON line loop.

```typescript
import * as readline from "readline";
import { SessionManager } from "./session-manager.js";

// Create session manager with stdout callback
const sessions = new SessionManager((msg) => {
  console.log(JSON.stringify(msg));
});

// Read JSON lines from stdin
const rl = readline.createInterface({
  input: process.stdin,
  terminal: false,
});

rl.on("line", async (line) => {
  if (!line.trim()) return;

  try {
    const msg = JSON.parse(line);
    await sessions.handleMessage(msg);
  } catch (err) {
    console.log(
      JSON.stringify({
        type: "error",
        payload: {
          code: "INVALID_MESSAGE",
          message: String(err),
        },
      })
    );
  }
});

rl.on("close", () => {
  sessions.dispose();
  process.exit(0);
});

// Handle process signals
process.on("SIGTERM", () => {
  sessions.dispose();
  process.exit(0);
});

process.on("SIGINT", () => {
  sessions.dispose();
  process.exit(0);
});

// Log startup to stderr (not stdout)
console.error("[backend] Started");
```

### session-manager.ts

Manages session lifecycle and message routing.

```typescript
import { v4 as uuidv4 } from "uuid";
import { query, type Query, type Options } from "@anthropic-ai/claude-agent-sdk";
import { CallbackBridge } from "./callback-bridge.js";
import type { IncomingMessage, OutgoingMessage } from "./protocol.js";

interface Session {
  id: string;
  query: Query;
  abortController: AbortController;
  callbacks: CallbackBridge;
  sdkSessionId?: string;
}

type SendFn = (msg: OutgoingMessage) => void;

export class SessionManager {
  private sessions = new Map<string, Session>();
  private send: SendFn;

  constructor(send: SendFn) {
    this.send = send;
  }

  async handleMessage(msg: IncomingMessage): Promise<void> {
    switch (msg.type) {
      case "session.create":
        await this.createSession(msg);
        break;
      case "session.send":
        await this.sendMessage(msg);
        break;
      case "session.interrupt":
        await this.interruptSession(msg);
        break;
      case "session.kill":
        await this.killSession(msg);
        break;
      case "callback.response":
        await this.handleCallbackResponse(msg);
        break;
      case "query.call":
        await this.handleQueryCall(msg);
        break;
      default:
        this.send({
          type: "error",
          id: (msg as any).id,
          payload: {
            code: "INVALID_MESSAGE",
            message: `Unknown message type: ${(msg as any).type}`,
          },
        });
    }
  }

  private async createSession(msg: any): Promise<void> {
    const sessionId = uuidv4();
    const abortController = new AbortController();
    const callbacks = new CallbackBridge(sessionId, this.send);

    try {
      // Build SDK options
      const options: Options = {
        cwd: msg.payload.cwd,
        abortController,
        ...this.buildOptions(msg.payload.options, callbacks),
      };

      // Start the query
      const q = query({
        prompt: msg.payload.prompt,
        options,
      });

      const session: Session = {
        id: sessionId,
        query: q,
        abortController,
        callbacks,
      };

      this.sessions.set(sessionId, session);

      // Send created response
      this.send({
        type: "session.created",
        id: msg.id,
        session_id: sessionId,
        payload: {},
      });

      // Process messages in background
      this.processMessages(session);
    } catch (err) {
      this.send({
        type: "error",
        id: msg.id,
        payload: {
          code: "SESSION_CREATE_FAILED",
          message: String(err),
        },
      });
    }
  }

  private buildOptions(opts: any, callbacks: CallbackBridge): Partial<Options> {
    if (!opts) return {};

    const result: Partial<Options> = {};

    // Simple passthrough options
    if (opts.model) result.model = opts.model;
    if (opts.permission_mode) result.permissionMode = opts.permission_mode;
    if (opts.allowed_tools) result.allowedTools = opts.allowed_tools;
    if (opts.disallowed_tools) result.disallowedTools = opts.disallowed_tools;
    if (opts.max_turns) result.maxTurns = opts.max_turns;
    if (opts.max_budget_usd) result.maxBudgetUsd = opts.max_budget_usd;
    if (opts.max_thinking_tokens) result.maxThinkingTokens = opts.max_thinking_tokens;
    if (opts.include_partial_messages) result.includePartialMessages = opts.include_partial_messages;
    if (opts.enable_file_checkpointing) result.enableFileCheckpointing = opts.enable_file_checkpointing;
    if (opts.additional_directories) result.additionalDirectories = opts.additional_directories;
    if (opts.setting_sources) result.settingSources = opts.setting_sources;
    if (opts.betas) result.betas = opts.betas;
    if (opts.fallback_model) result.fallbackModel = opts.fallback_model;
    if (opts.mcp_servers) result.mcpServers = opts.mcp_servers;
    if (opts.agents) result.agents = opts.agents;
    if (opts.sandbox) result.sandbox = opts.sandbox;
    if (opts.output_format) result.outputFormat = opts.output_format;

    // System prompt
    if (opts.system_prompt) {
      if (typeof opts.system_prompt === "string") {
        result.systemPrompt = opts.system_prompt;
      } else {
        result.systemPrompt = opts.system_prompt;
      }
    }

    // canUseTool callback - always set up to bridge to Dart
    result.canUseTool = async (toolName, toolInput, context) => {
      return callbacks.requestPermission(toolName, toolInput, context.suggestions);
    };

    // Hooks - bridge each configured hook to Dart
    if (opts.hooks) {
      result.hooks = {};
      for (const [event, configs] of Object.entries(opts.hooks)) {
        result.hooks[event as any] = (configs as any[]).map((config) => ({
          matcher: config.matcher,
          hooks: [
            async (input: any, toolUseId: string | undefined) => {
              return callbacks.requestHook(event, input, toolUseId);
            },
          ],
        }));
      }
    }

    return result;
  }

  private async processMessages(session: Session): Promise<void> {
    try {
      for await (const message of session.query) {
        // Capture SDK session ID
        if ("session_id" in message) {
          session.sdkSessionId = message.session_id as string;
        }

        // Forward raw message to Dart
        this.send({
          type: "sdk.message",
          session_id: session.id,
          payload: message,
        });
      }
    } catch (err) {
      if ((err as Error).name !== "AbortError") {
        this.send({
          type: "error",
          session_id: session.id,
          payload: {
            code: "SDK_ERROR",
            message: String(err),
          },
        });
      }
    }
  }

  private async sendMessage(msg: any): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`,
        },
      });
      return;
    }

    // Resume session with new message
    const q = query({
      prompt: msg.payload.message,
      options: {
        resume: session.sdkSessionId,
        abortController: session.abortController,
        canUseTool: async (toolName, toolInput, context) => {
          return session.callbacks.requestPermission(
            toolName,
            toolInput,
            context.suggestions
          );
        },
      },
    });

    session.query = q;
    this.processMessages(session);
  }

  private async interruptSession(msg: any): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`,
        },
      });
      return;
    }

    try {
      await session.query.interrupt();
      this.send({
        type: "session.interrupted",
        id: msg.id,
        session_id: msg.session_id,
        payload: {},
      });
    } catch (err) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "INTERRUPT_FAILED",
          message: String(err),
        },
      });
    }
  }

  private async killSession(msg: any): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`,
        },
      });
      return;
    }

    session.abortController.abort();
    session.callbacks.cancelAll();
    this.sessions.delete(msg.session_id);

    this.send({
      type: "session.killed",
      id: msg.id,
      session_id: msg.session_id,
      payload: {},
    });
  }

  private async handleCallbackResponse(msg: any): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`,
        },
      });
      return;
    }

    session.callbacks.resolve(msg.id, msg.payload);
  }

  private async handleQueryCall(msg: any): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session not found: ${msg.session_id}`,
        },
      });
      return;
    }

    try {
      const method = msg.payload.method;
      const args = msg.payload.args || [];

      let result: any;
      switch (method) {
        case "supportedModels":
          result = await session.query.supportedModels();
          break;
        case "supportedCommands":
          result = await session.query.supportedCommands();
          break;
        case "mcpServerStatus":
          result = await session.query.mcpServerStatus();
          break;
        case "accountInfo":
          result = await session.query.accountInfo();
          break;
        case "setModel":
          await session.query.setModel(args[0]);
          result = null;
          break;
        case "setPermissionMode":
          await session.query.setPermissionMode(args[0]);
          result = null;
          break;
        case "setMaxThinkingTokens":
          await session.query.setMaxThinkingTokens(args[0]);
          result = null;
          break;
        case "rewindFiles":
          await session.query.rewindFiles(args[0]);
          result = null;
          break;
        default:
          throw new Error(`Unknown query method: ${method}`);
      }

      this.send({
        type: "query.result",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          success: true,
          result,
        },
      });
    } catch (err) {
      this.send({
        type: "query.result",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          success: false,
          error: String(err),
        },
      });
    }
  }

  dispose(): void {
    for (const session of this.sessions.values()) {
      session.abortController.abort();
      session.callbacks.cancelAll();
    }
    this.sessions.clear();
  }
}
```

### callback-bridge.ts

Manages pending callback Promises.

```typescript
import { v4 as uuidv4 } from "uuid";
import type { OutgoingMessage } from "./protocol.js";
import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

interface PendingCallback {
  resolve: (value: any) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
}

type SendFn = (msg: OutgoingMessage) => void;

const CALLBACK_TIMEOUT_MS = 300000; // 5 minutes

export class CallbackBridge {
  private pending = new Map<string, PendingCallback>();
  private sessionId: string;
  private send: SendFn;

  constructor(sessionId: string, send: SendFn) {
    this.sessionId = sessionId;
    this.send = send;
  }

  async requestPermission(
    toolName: string,
    toolInput: Record<string, unknown>,
    suggestions?: any[]
  ): Promise<PermissionResult> {
    const id = uuidv4();

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        // Default to deny on timeout
        resolve({
          behavior: "deny",
          message: "Permission request timed out",
        });
      }, CALLBACK_TIMEOUT_MS);

      this.pending.set(id, { resolve, reject, timeout });

      this.send({
        type: "callback.request",
        id,
        session_id: this.sessionId,
        payload: {
          callback_type: "can_use_tool",
          tool_name: toolName,
          tool_input: toolInput,
          suggestions,
        },
      });
    });
  }

  async requestHook(
    event: string,
    input: any,
    toolUseId?: string
  ): Promise<any> {
    const id = uuidv4();

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        // Default to continue on timeout
        resolve({});
      }, CALLBACK_TIMEOUT_MS);

      this.pending.set(id, { resolve, reject, timeout });

      this.send({
        type: "callback.request",
        id,
        session_id: this.sessionId,
        payload: {
          callback_type: "hook",
          hook_event: event,
          hook_input: input,
          tool_use_id: toolUseId,
        },
      });
    });
  }

  resolve(id: string, response: any): void {
    const pending = this.pending.get(id);
    if (!pending) {
      console.error(`[callback-bridge] Unknown callback ID: ${id}`);
      return;
    }

    clearTimeout(pending.timeout);
    this.pending.delete(id);

    // Transform response based on callback type
    if (response.behavior) {
      // Permission response
      if (response.behavior === "allow") {
        pending.resolve({
          behavior: "allow",
          updatedInput: response.updated_input ?? {},
          updatedPermissions: response.updated_permissions,
        });
      } else {
        pending.resolve({
          behavior: "deny",
          message: response.message ?? "Denied",
          interrupt: response.interrupt,
        });
      }
    } else {
      // Hook response
      pending.resolve(response);
    }
  }

  cancelAll(): void {
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Session terminated"));
    }
    this.pending.clear();
  }
}
```

### protocol.ts

TypeScript types for the protocol.

```typescript
// Incoming messages (Dart → Backend)
export type IncomingMessage =
  | SessionCreateMessage
  | SessionSendMessage
  | SessionInterruptMessage
  | SessionKillMessage
  | CallbackResponseMessage
  | QueryCallMessage;

export interface SessionCreateMessage {
  type: "session.create";
  id: string;
  payload: {
    prompt: string;
    cwd: string;
    options?: SessionOptions;
  };
}

export interface SessionSendMessage {
  type: "session.send";
  id: string;
  session_id: string;
  payload: {
    message: string;
  };
}

export interface SessionInterruptMessage {
  type: "session.interrupt";
  id: string;
  session_id: string;
  payload: {};
}

export interface SessionKillMessage {
  type: "session.kill";
  id: string;
  session_id: string;
  payload: {};
}

export interface CallbackResponseMessage {
  type: "callback.response";
  id: string;
  session_id: string;
  payload: any;
}

export interface QueryCallMessage {
  type: "query.call";
  id: string;
  session_id: string;
  payload: {
    method: string;
    args?: any[];
  };
}

export interface SessionOptions {
  model?: string;
  permission_mode?: string;
  allowed_tools?: string[];
  disallowed_tools?: string[];
  system_prompt?: string | { type: "preset"; preset: "claude_code"; append?: string };
  max_turns?: number;
  max_budget_usd?: number;
  max_thinking_tokens?: number;
  include_partial_messages?: boolean;
  enable_file_checkpointing?: boolean;
  additional_directories?: string[];
  mcp_servers?: Record<string, any>;
  agents?: Record<string, any>;
  hooks?: Record<string, any[]>;
  sandbox?: any;
  setting_sources?: string[];
  betas?: string[];
  output_format?: any;
  fallback_model?: string;
}

// Outgoing messages (Backend → Dart)
export type OutgoingMessage =
  | SessionCreatedMessage
  | SdkMessageMessage
  | CallbackRequestMessage
  | QueryResultMessage
  | SessionInterruptedMessage
  | SessionKilledMessage
  | ErrorMessage;

export interface SessionCreatedMessage {
  type: "session.created";
  id: string;
  session_id: string;
  payload: {};
}

export interface SdkMessageMessage {
  type: "sdk.message";
  session_id: string;
  payload: any; // Raw SDK message
}

export interface CallbackRequestMessage {
  type: "callback.request";
  id: string;
  session_id: string;
  payload: {
    callback_type: "can_use_tool" | "hook";
    tool_name?: string;
    tool_input?: any;
    suggestions?: any[];
    hook_event?: string;
    hook_input?: any;
    tool_use_id?: string;
  };
}

export interface QueryResultMessage {
  type: "query.result";
  id: string;
  session_id: string;
  payload: {
    success: boolean;
    result?: any;
    error?: string;
  };
}

export interface SessionInterruptedMessage {
  type: "session.interrupted";
  id: string;
  session_id: string;
  payload: {};
}

export interface SessionKilledMessage {
  type: "session.killed";
  id: string;
  session_id: string;
  payload: {};
}

export interface ErrorMessage {
  type: "error";
  id?: string;
  session_id?: string;
  payload: {
    code: string;
    message: string;
    details?: any;
  };
}
```

## Testing

### test-client.js

Simple test client for manual testing.

```javascript
#!/usr/bin/env node

const { spawn } = require("child_process");
const readline = require("readline");

const backend = spawn("node", ["dist/index.js"], {
  stdio: ["pipe", "pipe", "inherit"],
});

// Read responses
const rl = readline.createInterface({ input: backend.stdout });
rl.on("line", (line) => {
  const msg = JSON.parse(line);
  console.log("<<<", JSON.stringify(msg, null, 2));

  // Auto-approve permissions
  if (msg.type === "callback.request" && msg.payload.callback_type === "can_use_tool") {
    send({
      type: "callback.response",
      id: msg.id,
      session_id: msg.session_id,
      payload: { behavior: "allow" },
    });
  }
});

// Send helper
function send(msg) {
  console.log(">>>", JSON.stringify(msg));
  backend.stdin.write(JSON.stringify(msg) + "\n");
}

// Create session
send({
  type: "session.create",
  id: "test-1",
  payload: {
    prompt: "What is 2+2?",
    cwd: process.cwd(),
    options: {
      model: "sonnet",
    },
  },
});

// Handle Ctrl+C
process.on("SIGINT", () => {
  backend.kill();
  process.exit(0);
});
```

## Build & Run

```bash
# Install dependencies
npm install

# Build
npm run build

# Run
node dist/index.js

# Test
node test/test-client.js
```
