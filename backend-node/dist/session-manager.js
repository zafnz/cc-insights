import { v4 as uuidv4 } from "uuid";
import { query, } from "@anthropic-ai/claude-agent-sdk";
import { CallbackBridge } from "./callback-bridge.js";
import { MessageQueue } from "./message-queue.js";
import { logger } from "./logger.js";
export class SessionManager {
    sessions = new Map();
    send;
    constructor(send) {
        this.send = send;
    }
    async handleMessage(msg) {
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
                    type: msg.type,
                });
                this.send({
                    type: "error",
                    id: msg.id,
                    payload: {
                        code: "INVALID_MESSAGE",
                        message: `Unknown message type: ${msg.type}`,
                    },
                });
        }
    }
    async createSession(msg) {
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
            const options = {
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
            if (msg.payload.prompt.trim() !== "" || msg.payload.content?.length) {
                // Use content blocks if provided (supports images), otherwise use prompt string
                const content = msg.payload.content?.length
                    ? msg.payload.content
                    : msg.payload.prompt;
                const initialMessage = {
                    type: "user",
                    message: {
                        role: "user",
                        content,
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
            const session = {
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
        }
        catch (err) {
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
    buildOptions(opts, callbacks) {
        // Pass through ALL context fields from SDK - don't drop anything!
        // The SDK provides: signal, suggestions, blockedPath, decisionReason, toolUseID, agentID
        const baseCanUseTool = async (toolName, toolInput, context) => {
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
        const result = {};
        // Simple passthrough options that exist on Options
        if (opts.model)
            result.model = opts.model;
        if (opts.permission_mode)
            result.permissionMode = opts.permission_mode;
        if (opts.allow_dangerously_skip_permissions !== undefined) {
            result.allowDangerouslySkipPermissions =
                opts.allow_dangerously_skip_permissions;
        }
        if (opts.permission_prompt_tool_name) {
            result.permissionPromptToolName = opts.permission_prompt_tool_name;
        }
        if (opts.tools)
            result.tools = opts.tools;
        if (opts.plugins)
            result.plugins = opts.plugins;
        if (opts.strict_mcp_config !== undefined) {
            result.strictMcpConfig = opts.strict_mcp_config;
        }
        if (opts.resume)
            result.resume = opts.resume;
        if (opts.resume_session_at)
            result.resumeSessionAt = opts.resume_session_at;
        if (opts.allowed_tools)
            result.allowedTools = opts.allowed_tools;
        if (opts.disallowed_tools)
            result.disallowedTools = opts.disallowed_tools;
        if (opts.max_turns)
            result.maxTurns = opts.max_turns;
        if (opts.max_budget_usd !== undefined)
            result.maxBudgetUsd = opts.max_budget_usd;
        if (opts.max_thinking_tokens)
            result.maxThinkingTokens = opts.max_thinking_tokens;
        if (opts.include_partial_messages)
            result.includePartialMessages = opts.include_partial_messages;
        if (opts.enable_file_checkpointing !== undefined) {
            result.enableFileCheckpointing = opts.enable_file_checkpointing;
        }
        if (opts.additional_directories)
            result.additionalDirectories = opts.additional_directories;
        if (opts.fallback_model)
            result.fallbackModel = opts.fallback_model;
        if (opts.mcp_servers)
            result.mcpServers = opts.mcp_servers;
        if (opts.agents)
            result.agents = opts.agents;
        if (opts.sandbox)
            result.sandbox = opts.sandbox;
        if (opts.setting_sources)
            result.settingSources = opts.setting_sources;
        if (opts.betas)
            result.betas = opts.betas;
        if (opts.output_format)
            result.outputFormat = opts.output_format;
        // System prompt
        if (opts.system_prompt !== undefined) {
            result.systemPrompt = opts.system_prompt;
        }
        // canUseTool callback - always set up to bridge to Dart
        result.canUseTool = baseCanUseTool;
        // Hooks - bridge each configured hook to Dart
        if (opts.hooks) {
            const hooks = {};
            for (const [event, configs] of Object.entries(opts.hooks)) {
                const hookEvent = event;
                hooks[hookEvent] = configs.map((config) => ({
                    matcher: config.matcher,
                    hooks: [
                        async (input, toolUseId) => {
                            return callbacks.requestHook(event, input, toolUseId);
                        },
                    ],
                }));
            }
            result.hooks = hooks;
        }
        return result;
    }
    async processMessages(session) {
        logger.info("Processing SDK messages", { sessionId: session.id });
        let messageCount = 0;
        try {
            for await (const message of session.query) {
                messageCount++;
                // Capture SDK session ID
                if (typeof message === "object" &&
                    message !== null &&
                    "session_id" in message) {
                    session.sdkSessionId = message.session_id;
                    logger.debug("Captured SDK session ID", {
                        sessionId: session.id,
                        sdkSessionId: session.sdkSessionId,
                    });
                }
                logger.debug("SDK message received", {
                    sessionId: session.id,
                    messageType: typeof message === "object" && message !== null && "type" in message
                        ? message.type
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
        }
        catch (err) {
            const error = err;
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
            }
            else {
                logger.info("Session aborted", { sessionId: session.id });
            }
        }
    }
    async sendMessage(msg) {
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
            messageLength: msg.payload.message?.length ?? 0,
            contentBlockCount: msg.payload.content?.length ?? 0,
            sdkSessionId: session.sdkSessionId,
        });
        // Push message to the queue - the same Claude process will receive it
        const userMessage = {
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
        }
        catch (err) {
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
    async interruptSession(msg) {
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
        }
        catch (err) {
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
    async killSession(msg) {
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
    async handleCallbackResponse(msg) {
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
    async handleQueryCall(msg) {
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
            let result;
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
                    await session.query.setModel(args[0]);
                    result = null;
                    break;
                case "setPermissionMode":
                    await session.query.setPermissionMode(args[0]);
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
        }
        catch (err) {
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
    dispose() {
        for (const session of this.sessions.values()) {
            session.abortController.abort();
            session.callbacks.cancelAll();
        }
        this.sessions.clear();
    }
}
