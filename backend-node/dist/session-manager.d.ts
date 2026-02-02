import type { IncomingMessage, OutgoingMessage } from "./protocol.js";
type SendFn = (msg: OutgoingMessage) => void;
export declare class SessionManager {
    private sessions;
    private send;
    constructor(send: SendFn);
    handleMessage(msg: IncomingMessage): Promise<void>;
    private createSession;
    private buildOptions;
    private processMessages;
    private sendMessage;
    private interruptSession;
    private killSession;
    private handleCallbackResponse;
    private handleQueryCall;
    dispose(): void;
}
export {};
