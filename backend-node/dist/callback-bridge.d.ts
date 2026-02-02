import type { PermissionResult, HookJSONOutput } from "@anthropic-ai/claude-agent-sdk";
import type { OutgoingMessage, PermissionResponsePayload, HookResponsePayload } from "./protocol.js";
type SendFn = (msg: OutgoingMessage) => void;
export declare class CallbackBridge {
    private pending;
    private sessionId;
    private send;
    constructor(sessionId: string, send: SendFn);
    requestPermission(toolName: string, toolInput: Record<string, unknown>, context: {
        suggestions?: unknown[];
        blockedPath?: string;
        decisionReason?: string;
        toolUseID: string;
        agentID?: string;
    }): Promise<PermissionResult>;
    requestHook(event: string, input: unknown, toolUseId?: string): Promise<HookJSONOutput>;
    resolve(id: string, response: PermissionResponsePayload | HookResponsePayload): void;
    cancelAll(): void;
}
export {};
