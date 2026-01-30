import { v4 as uuidv4 } from "uuid";
import {
  query,
  type Query,
  type Options,
  type PermissionResult,
  type HookJSONOutput,
  type HookEvent,
  type HookCallbackMatcher,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { CallbackBridge } from "./callback-bridge.js";
import { MessageQueue } from "./message-queue.js";
import { logger } from "./logger.js";
import type {
  IncomingMessage,
  OutgoingMessage,
  SessionOptions,
  SessionCreateMessage,
  SessionSendMessage,
  SessionInterruptMessage,
  SessionKillMessage,
  CallbackResponseMessage,
  QueryCallMessage,
  PermissionResponsePayload,
  HookResponsePayload,
} from "./protocol.js";

interface Session {
  id: string;
  query: Query;
  messageQueue: MessageQueue;
  abortController: AbortController;
  callbacks: CallbackBridge;
  sdkSessionId?: string;
  cwd: string;
}

type SendFn = (msg: OutgoingMessage) => void;

export class SessionManager {
  private sessions = new Map<string, Session>();
  private send: SendFn;

  constructor(send: SendFn) {
    this.send = send;
  }

  async handleMessage(msg: IncomingMessage): Promise<void> {
    logger.debug("Handling message", { type: msg.type });

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
        logger.warn("Unknown message type", {
          type: (msg as { type: string }).type,
        });
        this.send({
          type: "error",
          id: (msg as { id?: string }).id,
          payload: {
            code: "INVALID_MESSAGE",
            message: `Unknown message type: ${(msg as { type: string }).type}`,
          },
        });
    }
  }

  private async createSession(msg: SessionCreateMessage): Promise<void> {
    const sessionId = uuidv4();
    const abortController = new AbortController();
    const callbacks = new CallbackBridge(sessionId, this.send);
    const messageQueue = new MessageQueue();

    logger.info("Creating session", {
      sessionId,
      cwd: msg.payload.cwd,
      promptLength: msg.payload.prompt.length,
    });

    try {
      // Build SDK options
      const options: Options = {
        cwd: msg.payload.cwd,
        abortController,
        // Use system claude binary if available to avoid Node v25 compatibility issues
        pathToClaudeCodeExecutable: process.env.CLAUDE_CODE_PATH,
        // Note: Enable these for streaming support:
        // includePartialMessages: true,  // Real-time text updates
        // maxThinkingTokens: 16000,      // Extended thinking
        ...this.buildOptions(msg.payload.options, callbacks),
      };

      logger.info("Starting SDK query with streaming input mode", {
        sessionId,
        cwd: options.cwd,
        model: options.model,
        permissionMode: options.permissionMode,
        maxTurns: options.maxTurns,
        includePartialMessages: options.includePartialMessages,
        hasCanUseTool: !!options.canUseTool,
        hasHooks: !!options.hooks,
      });

      // Log environment variables that might affect Claude spawning
      logger.info("Environment", {
        CLAUDE_CODE_PATH: process.env.CLAUDE_CODE_PATH,
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY ? "***set***" : undefined,
        HOME: process.env.HOME,
      });

      // Push initial prompt to queue only if non-empty
      // Empty prompts (e.g., from /clear command) should wait for user input
      if (msg.payload.prompt.trim() !== "") {
        const initialMessage: SDKUserMessage = {
          type: "user",
          message: {
            role: "user",
            content: msg.payload.prompt,
          },
          parent_tool_use_id: null,
          session_id: sessionId,
        };
        messageQueue.push(initialMessage);
      }

      // Start the query with streaming input (async generator)
      const q = query({
        prompt: messageQueue.generate(),
        options,
      });

      const session: Session = {
        id: sessionId,
        query: q,
        messageQueue,
        abortController,
        callbacks,
        cwd: msg.payload.cwd,
      };

      this.sessions.set(sessionId, session);

      // Send created response
      this.send({
        type: "session.created",
        id: msg.id,
        session_id: sessionId,
        payload: {},
      });

      logger.info("Session created successfully", {
        sessionId,
        totalSessions: this.sessions.size,
      });

      // Process messages in background
      this.processMessages(session);
    } catch (err) {
      logger.error("Failed to create session", {
        sessionId,
        error: String(err),
      });
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

  private buildOptions(
    opts: SessionOptions | undefined,
    callbacks: CallbackBridge
  ): Partial<Options> {
    // Pass through ALL context fields from SDK - don't drop anything!
    // The SDK provides: signal, suggestions, blockedPath, decisionReason, toolUseID, agentID
    const baseCanUseTool = async (
      toolName: string,
      toolInput: Record<string, unknown>,
      context: {
        signal: AbortSignal;
        suggestions?: unknown[];
        blockedPath?: string;
        decisionReason?: string;
        toolUseID: string;
        agentID?: string;
      }
    ): Promise<PermissionResult> => {
      // Pass everything except signal (can't serialize AbortSignal to JSON)
      return callbacks.requestPermission(toolName, toolInput, {
        suggestions: context.suggestions,
        blockedPath: context.blockedPath,
        decisionReason: context.decisionReason,
        toolUseID: context.toolUseID,
        agentID: context.agentID,
      });
    };

    if (!opts) {
      logger.debug("No session options provided, using defaults");
      return { canUseTool: baseCanUseTool };
    }

    logger.debug("Building session options", {
      hasModel: !!opts.model,
      hasPermissionMode: !!opts.permission_mode,
      hasSystemPrompt: !!opts.system_prompt,
      hasHooks: !!opts.hooks,
      hasMcpServers: !!opts.mcp_servers,
    });

    const result: Partial<Options> = {};

    // Simple passthrough options that exist on Options
    if (opts.model) result.model = opts.model;
    if (opts.permission_mode)
      result.permissionMode = opts.permission_mode as Options["permissionMode"];
    if (opts.allow_dangerously_skip_permissions !== undefined) {
      result.allowDangerouslySkipPermissions =
        opts.allow_dangerously_skip_permissions;
    }
    if (opts.permission_prompt_tool_name) {
      result.permissionPromptToolName = opts.permission_prompt_tool_name;
    }
    if (opts.tools) result.tools = opts.tools as Options["tools"];
    if (opts.plugins) result.plugins = opts.plugins as Options["plugins"];
    if (opts.strict_mcp_config !== undefined) {
      result.strictMcpConfig = opts.strict_mcp_config;
    }
    if (opts.resume) result.resume = opts.resume;
    if (opts.resume_session_at) result.resumeSessionAt = opts.resume_session_at;
    if (opts.allowed_tools) result.allowedTools = opts.allowed_tools;
    if (opts.disallowed_tools) result.disallowedTools = opts.disallowed_tools;
    if (opts.max_turns) result.maxTurns = opts.max_turns;
    if (opts.max_budget_usd !== undefined) result.maxBudgetUsd = opts.max_budget_usd;
    if (opts.max_thinking_tokens) result.maxThinkingTokens = opts.max_thinking_tokens;
    if (opts.include_partial_messages)
      result.includePartialMessages = opts.include_partial_messages;
    if (opts.enable_file_checkpointing !== undefined) {
      result.enableFileCheckpointing = opts.enable_file_checkpointing;
    }
    if (opts.additional_directories)
      result.additionalDirectories = opts.additional_directories;
    if (opts.fallback_model) result.fallbackModel = opts.fallback_model;
    if (opts.mcp_servers)
      result.mcpServers = opts.mcp_servers as Options["mcpServers"];
    if (opts.agents) result.agents = opts.agents as Options["agents"];
    if (opts.sandbox) result.sandbox = opts.sandbox as Options["sandbox"];
    if (opts.setting_sources)
      result.settingSources = opts.setting_sources as Options["settingSources"];
    if (opts.betas) result.betas = opts.betas as Options["betas"];
    if (opts.output_format)
      result.outputFormat = opts.output_format as Options["outputFormat"];

    // System prompt
    if (opts.system_prompt !== undefined) {
      result.systemPrompt = opts.system_prompt as Options["systemPrompt"];
    }

    // canUseTool callback - always set up to bridge to Dart
    result.canUseTool = baseCanUseTool;

    // Hooks - bridge each configured hook to Dart
    if (opts.hooks) {
      const hooks: Partial<Record<HookEvent, HookCallbackMatcher[]>> = {};
      for (const [event, configs] of Object.entries(opts.hooks)) {
        const hookEvent = event as HookEvent;
        hooks[hookEvent] = (configs as Array<{ matcher?: string }>).map(
          (config): HookCallbackMatcher => ({
            matcher: config.matcher,
            hooks: [
              async (
                input: unknown,
                toolUseId: string | undefined
              ): Promise<HookJSONOutput> => {
                return callbacks.requestHook(event, input, toolUseId);
              },
            ],
          })
        );
      }
      result.hooks = hooks;
    }

    return result;
  }

  private async processMessages(session: Session): Promise<void> {
    logger.info("Processing SDK messages", { sessionId: session.id });
    let messageCount = 0;

    try {
      for await (const message of session.query) {
        messageCount++;

        // Capture SDK session ID
        if (
          typeof message === "object" &&
          message !== null &&
          "session_id" in message
        ) {
          session.sdkSessionId = message.session_id as string;
          logger.debug("Captured SDK session ID", {
            sessionId: session.id,
            sdkSessionId: session.sdkSessionId,
          });
        }

        logger.debug("SDK message received", {
          sessionId: session.id,
          messageType: typeof message === "object" && message !== null && "type" in message
            ? (message as { type: string }).type
            : typeof message,
          messageCount,
        });

        // Forward raw message to Dart
        this.send({
          type: "sdk.message",
          session_id: session.id,
          payload: message,
        });
      }

      logger.info("SDK message stream completed", {
        sessionId: session.id,
        totalMessages: messageCount,
      });
    } catch (err) {
      const error = err as Error;
      const isAbort = error.name === "AbortError" ||
                      error.message?.includes("aborted by user");

      if (!isAbort) {
        logger.error("SDK error during message processing", {
          sessionId: session.id,
          error: String(err),
          stack: error.stack,
        });
        this.send({
          type: "error",
          session_id: session.id,
          payload: {
            code: "SDK_ERROR",
            message: String(err),
          },
        });
      } else {
        logger.info("Session aborted", { sessionId: session.id });
      }
    }
  }

  private async sendMessage(msg: SessionSendMessage): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      logger.warn("Session not found for send", { sessionId: msg.session_id });
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

    // Build content - use content blocks if provided, otherwise use message string
    const content = msg.payload.content
      ? msg.payload.content
      : msg.payload.message;

    logger.info("Pushing message to session queue", {
      sessionId: msg.session_id,
      messageLength: msg.payload.message.length,
      hasContentBlocks: !!msg.payload.content,
      sdkSessionId: session.sdkSessionId,
    });

    // Push message to the queue - the same Claude process will receive it
    const userMessage: SDKUserMessage = {
      type: "user",
      message: {
        role: "user",
        content: content,
      },
      parent_tool_use_id: null,
      session_id: msg.session_id,
    };

    try {
      session.messageQueue.push(userMessage);
      logger.info("Message pushed to queue successfully", {
        sessionId: msg.session_id,
      });
    } catch (err) {
      logger.error("Failed to push message to queue", {
        sessionId: msg.session_id,
        error: String(err),
      });
      this.send({
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SEND_MESSAGE_FAILED",
          message: String(err),
        },
      });
    }
  }

  private async interruptSession(msg: SessionInterruptMessage): Promise<void> {
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

  private async killSession(msg: SessionKillMessage): Promise<void> {
    const session = this.sessions.get(msg.session_id);
    if (!session) {
      logger.warn("Session not found for kill", { sessionId: msg.session_id });
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

    logger.info("Killing session", { sessionId: msg.session_id });

    session.abortController.abort();
    session.callbacks.cancelAll();
    session.messageQueue.close();
    this.sessions.delete(msg.session_id);

    logger.info("Session killed", {
      sessionId: msg.session_id,
      remainingSessions: this.sessions.size,
    });

    this.send({
      type: "session.killed",
      id: msg.id,
      session_id: msg.session_id,
      payload: {},
    });
  }

  private async handleCallbackResponse(
    msg: CallbackResponseMessage
  ): Promise<void> {
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

    session.callbacks.resolve(
      msg.id,
      msg.payload as PermissionResponsePayload | HookResponsePayload
    );
  }

  private async handleQueryCall(msg: QueryCallMessage): Promise<void> {
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

      let result: unknown;
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
        case "setModel":
          await session.query.setModel(args[0] as string | undefined);
          result = null;
          break;
        case "setPermissionMode":
          await session.query.setPermissionMode(
            args[0] as "default" | "acceptEdits" | "bypassPermissions" | "plan"
          );
          result = null;
          break;
        // Note: accountInfo, setMaxThinkingTokens, rewindFiles are not available
        // in this SDK version - they may be added in future versions
        default:
          throw new Error(`Unknown or unsupported query method: ${method}`);
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
