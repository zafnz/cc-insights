import { v4 as uuidv4 } from "uuid";
import type { PermissionResult, HookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import { logger } from "./logger.js";
import type {
  OutgoingMessage,
  PermissionResponsePayload,
  HookResponsePayload,
} from "./protocol.js";

interface PendingCallback {
  resolve: (value: PermissionResult | HookJSONOutput) => void;
  reject: (error: Error) => void;
  timeout: NodeJS.Timeout;
  meta?:
    | {
        type: "permission";
        toolName: string;
        toolInput: Record<string, unknown>;
        suggestions?: unknown[];
      }
    | {
        type: "hook";
        event: string;
      };
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
    context: {
      suggestions?: unknown[];
      blockedPath?: string;
      decisionReason?: string;
      toolUseID: string;
      agentID?: string;
    }
  ): Promise<PermissionResult> {
    const id = uuidv4();

    logger.info("Requesting permission", {
      sessionId: this.sessionId,
      callbackId: id,
      toolName,
      toolUseID: context.toolUseID,
      agentID: context.agentID,
    });

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        logger.warn("Permission request timed out", {
          sessionId: this.sessionId,
          callbackId: id,
          toolName,
        });
        // Default to deny on timeout
        resolve({
          behavior: "deny",
          message: "Permission request timed out",
        });
      }, CALLBACK_TIMEOUT_MS);

      this.pending.set(id, {
        resolve: resolve as PendingCallback["resolve"],
        reject,
        timeout,
        meta: { type: "permission", toolName, toolInput, suggestions: context.suggestions },
      });

      // Pass through ALL context fields from SDK to Dart - don't drop anything!
      this.send({
        type: "callback.request",
        id,
        session_id: this.sessionId,
        payload: {
          callback_type: "can_use_tool",
          tool_name: toolName,
          tool_input: toolInput,
          suggestions: context.suggestions,
          blocked_path: context.blockedPath,
          decision_reason: context.decisionReason,
          tool_use_id: context.toolUseID,
          agent_id: context.agentID,
        },
      });
    });
  }

  async requestHook(
    event: string,
    input: unknown,
    toolUseId?: string
  ): Promise<HookJSONOutput> {
    const id = uuidv4();

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        // Default to continue on timeout
        resolve({});
      }, CALLBACK_TIMEOUT_MS);

      this.pending.set(id, {
        resolve: resolve as PendingCallback["resolve"],
        reject,
        timeout,
        meta: { type: "hook", event },
      });

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

  resolve(id: string, response: PermissionResponsePayload | HookResponsePayload): void {
    const pending = this.pending.get(id);
    if (!pending) {
      logger.error("Unknown callback ID", {
        sessionId: this.sessionId,
        callbackId: id,
      });
      return;
    }

    clearTimeout(pending.timeout);
    this.pending.delete(id);

    // Transform response based on callback type
    if ("behavior" in response) {
      // Permission response
      const permResponse = response as PermissionResponsePayload;
      logger.info("Permission callback resolved", {
        sessionId: this.sessionId,
        callbackId: id,
        behavior: permResponse.behavior,
      });
      if (permResponse.behavior === "allow") {
        const meta = pending.meta?.type === "permission" ? pending.meta : undefined;
        const updatedInput = permResponse.updated_input;
        if (updatedInput === undefined) {
          logger.warn("Permission allow response missing updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta?.toolName,
          });
        } else if (typeof updatedInput !== "object" || updatedInput === null) {
          logger.warn("Permission allow response has non-object updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta?.toolName,
            updatedInputType: typeof updatedInput,
          });
        } else if (
          meta &&
          Object.keys(updatedInput).length === 0 &&
          Object.keys(meta.toolInput).length > 0
        ) {
          logger.warn("Permission allow response has empty updated_input", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta.toolName,
          });
        }
        if (meta?.suggestions && permResponse.updated_permissions === undefined) {
          logger.warn("Permission allow response missing updated_permissions", {
            sessionId: this.sessionId,
            callbackId: id,
            toolName: meta.toolName,
          });
        }
        // Pass through exactly what Dart sends - thin bridge, no transformations
        const result: any = { behavior: "allow" };
        if (permResponse.updated_input !== undefined) {
          result.updatedInput = permResponse.updated_input;
        }
        if (permResponse.updated_permissions !== undefined) {
          result.updatedPermissions = permResponse.updated_permissions;
        }
        logger.info("Resolving permission callback with result", {
          sessionId: this.sessionId,
          callbackId: id,
          result: JSON.stringify(result),
        });
        pending.resolve(result as PermissionResult);
      } else {
        if (!permResponse.message) {
          logger.warn("Permission deny response missing message", {
            sessionId: this.sessionId,
            callbackId: id,
          });
        }
        const denyResult = {
          behavior: "deny",
          message: permResponse.message ?? "Denied",
          interrupt: permResponse.interrupt,
        } as PermissionResult;
        logger.info("Resolving permission callback with denial", {
          sessionId: this.sessionId,
          callbackId: id,
          result: JSON.stringify(denyResult),
        });
        pending.resolve(denyResult);
      }
    } else {
      // Hook response - map from protocol to SDK format
      const hookResponse = response as HookResponsePayload;
      logger.info("Hook callback resolved", {
        sessionId: this.sessionId,
        callbackId: id,
      });
      pending.resolve({
        continue: hookResponse.continue,
        suppressOutput: hookResponse.suppressOutput ?? hookResponse.suppress_output,
        stopReason: hookResponse.stopReason ?? hookResponse.stop_reason,
        decision: hookResponse.decision,
        systemMessage: hookResponse.system_message ?? hookResponse.systemMessage,
        reason: hookResponse.reason,
        hookSpecificOutput:
          hookResponse.hook_specific_output ?? hookResponse.hookSpecificOutput,
      } as HookJSONOutput);
    }
  }

  cancelAll(): void {
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Session terminated"));
    }
    this.pending.clear();
  }
}
