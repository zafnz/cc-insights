import { v4 as uuidv4 } from "uuid";
import {
  IncomingMessage,
  OutgoingMessage,
  SessionCreateMessage,
  SessionSendMessage,
  SessionInterruptMessage,
  SessionKillMessage,
  CallbackResponseMessage,
  QueryCallMessage,
  SessionOptions,
  SdkMessageMessage,
} from "./protocol";
import { ScenarioEngine, EmitFn } from "./scenario-engine";

/**
 * Represents an active mock session
 */
interface Session {
  id: string;
  cwd: string;
  options: SessionOptions;
  scenario: ScenarioEngine;
  pendingCallbacks: Map<string, (response: unknown) => void>;
  isRunning: boolean;
}

/**
 * Emit function that writes to stdout
 */
function emitToStdout(message: OutgoingMessage | SdkMessageMessage): void {
  console.log(JSON.stringify(message));
}

/**
 * Log to stderr for debugging
 */
function log(message: string, data?: unknown): void {
  const timestamp = new Date().toISOString();
  if (data !== undefined) {
    process.stderr.write(`[${timestamp}] ${message}: ${JSON.stringify(data)}\n`);
  } else {
    process.stderr.write(`[${timestamp}] ${message}\n`);
  }
}

/**
 * Session manager - handles all incoming messages and manages session state
 */
export class SessionManager {
  private sessions = new Map<string, Session>();

  /**
   * Handle an incoming message and return an optional response
   */
  async handleMessage(msg: IncomingMessage): Promise<OutgoingMessage | null> {
    log(`Received message`, { type: msg.type, id: msg.id });

    switch (msg.type) {
      case "session.create":
        return this.handleCreate(msg);
      case "session.send":
        return this.handleSend(msg);
      case "session.interrupt":
        return this.handleInterrupt(msg);
      case "session.kill":
        return this.handleKill(msg);
      case "callback.response":
        return this.handleCallback(msg);
      case "query.call":
        return this.handleQuery(msg);
      default:
        // TypeScript exhaustiveness check
        const unknownMsg = msg as { type: string };
        return {
          type: "error",
          payload: {
            code: "UNKNOWN_MESSAGE_TYPE",
            message: `Unknown message type: ${unknownMsg.type}`,
          },
        };
    }
  }

  /**
   * Handle session.create - create a new session and execute initial prompt
   */
  private async handleCreate(
    msg: SessionCreateMessage
  ): Promise<OutgoingMessage | null> {
    const sessionId = uuidv4();
    const { prompt, cwd, options } = msg.payload;

    log(`Creating session`, { sessionId, cwd, prompt: prompt.substring(0, 50) });

    const scenario = new ScenarioEngine(sessionId, cwd, options);

    const session: Session = {
      id: sessionId,
      cwd,
      options: options || {},
      scenario,
      pendingCallbacks: new Map(),
      isRunning: true,
    };

    this.sessions.set(sessionId, session);

    // Send session.created response
    emitToStdout({
      type: "session.created",
      id: msg.id,
      session_id: sessionId,
      payload: {
        sdk_session_id: `mock-sdk-${sessionId}`,
      },
    });

    // Create emit function for this session
    const emit: EmitFn = (message) => {
      emitToStdout(message);
    };

    // Create callback resolver for this session
    const waitForCallback = (callbackId: string): Promise<unknown> => {
      return new Promise((resolve) => {
        session.pendingCallbacks.set(callbackId, resolve);
      });
    };

    // Execute initial prompt scenario (async, messages emit directly)
    try {
      await scenario.executeInitialPrompt(prompt, emit, waitForCallback);
      session.isRunning = false;
    } catch (error) {
      log(`Error executing scenario`, { error: String(error) });
      session.isRunning = false;
      emitToStdout({
        type: "error",
        session_id: sessionId,
        payload: {
          code: "SCENARIO_ERROR",
          message: `Scenario execution failed: ${error}`,
        },
      });
    }

    // No direct response needed - messages are emitted via emit function
    return null;
  }

  /**
   * Handle session.send - send a follow-up message to an existing session
   */
  private async handleSend(
    msg: SessionSendMessage
  ): Promise<OutgoingMessage | null> {
    const session = this.sessions.get(msg.session_id);

    if (!session) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session ${msg.session_id} not found`,
        },
      };
    }

    if (session.isRunning) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_BUSY",
          message: `Session ${msg.session_id} is currently running`,
        },
      };
    }

    log(`Sending follow-up message`, {
      sessionId: msg.session_id,
      message: msg.payload.message.substring(0, 50),
    });

    session.isRunning = true;

    const emit: EmitFn = (message) => {
      emitToStdout(message);
    };

    const waitForCallback = (callbackId: string): Promise<unknown> => {
      return new Promise((resolve) => {
        session.pendingCallbacks.set(callbackId, resolve);
      });
    };

    try {
      await session.scenario.executeFollowUp(
        msg.payload.message,
        emit,
        waitForCallback
      );
      session.isRunning = false;
    } catch (error) {
      log(`Error executing follow-up`, { error: String(error) });
      session.isRunning = false;
      emitToStdout({
        type: "error",
        session_id: msg.session_id,
        payload: {
          code: "SCENARIO_ERROR",
          message: `Follow-up execution failed: ${error}`,
        },
      });
    }

    return null;
  }

  /**
   * Handle session.interrupt - interrupt a running session
   */
  private async handleInterrupt(
    msg: SessionInterruptMessage
  ): Promise<OutgoingMessage> {
    const session = this.sessions.get(msg.session_id);

    if (!session) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session ${msg.session_id} not found`,
        },
      };
    }

    log(`Interrupting session`, { sessionId: msg.session_id });

    // Mark session as not running
    session.isRunning = false;

    // Resolve any pending callbacks with interrupt
    for (const [callbackId, resolve] of session.pendingCallbacks) {
      resolve({ interrupted: true });
    }
    session.pendingCallbacks.clear();

    return {
      type: "session.interrupted",
      id: msg.id,
      session_id: msg.session_id,
      payload: {},
    };
  }

  /**
   * Handle session.kill - terminate a session completely
   */
  private async handleKill(
    msg: SessionKillMessage
  ): Promise<OutgoingMessage> {
    const session = this.sessions.get(msg.session_id);

    if (!session) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session ${msg.session_id} not found`,
        },
      };
    }

    log(`Killing session`, { sessionId: msg.session_id });

    // Resolve any pending callbacks with kill signal
    for (const [callbackId, resolve] of session.pendingCallbacks) {
      resolve({ killed: true });
    }
    session.pendingCallbacks.clear();

    // Remove session from map
    this.sessions.delete(msg.session_id);

    return {
      type: "session.killed",
      id: msg.id,
      session_id: msg.session_id,
      payload: {},
    };
  }

  /**
   * Handle callback.response - resolve a pending callback
   */
  private async handleCallback(
    msg: CallbackResponseMessage
  ): Promise<OutgoingMessage | null> {
    const session = this.sessions.get(msg.session_id);

    if (!session) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session ${msg.session_id} not found`,
        },
      };
    }

    const resolver = session.pendingCallbacks.get(msg.id);

    if (!resolver) {
      log(`No pending callback found`, { callbackId: msg.id });
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "CALLBACK_NOT_FOUND",
          message: `No pending callback with id ${msg.id}`,
        },
      };
    }

    log(`Resolving callback`, { callbackId: msg.id });

    // Remove from pending and resolve
    session.pendingCallbacks.delete(msg.id);
    resolver(msg.payload);

    return null;
  }

  /**
   * Handle query.call - handle SDK method queries
   */
  private async handleQuery(
    msg: QueryCallMessage
  ): Promise<OutgoingMessage> {
    const session = this.sessions.get(msg.session_id);

    if (!session) {
      return {
        type: "error",
        id: msg.id,
        session_id: msg.session_id,
        payload: {
          code: "SESSION_NOT_FOUND",
          message: `Session ${msg.session_id} not found`,
        },
      };
    }

    const { method, args } = msg.payload;

    log(`Handling query`, { method, args });

    // Handle known query methods
    switch (method) {
      case "supportedModels":
        return {
          type: "query.result",
          id: msg.id,
          session_id: msg.session_id,
          payload: {
            success: true,
            result: [
              "claude-sonnet-4-5-20250514",
              "claude-opus-4-5-20251101",
              "claude-3-5-haiku-20241022",
            ],
          },
        };

      case "getSessionInfo":
        return {
          type: "query.result",
          id: msg.id,
          session_id: msg.session_id,
          payload: {
            success: true,
            result: {
              sessionId: session.id,
              cwd: session.cwd,
              model: session.options.model || "claude-sonnet-4-5-20250514",
              isRunning: session.isRunning,
            },
          },
        };

      default:
        return {
          type: "query.result",
          id: msg.id,
          session_id: msg.session_id,
          payload: {
            success: false,
            error: `Unknown query method: ${method}`,
          },
        };
    }
  }
}
