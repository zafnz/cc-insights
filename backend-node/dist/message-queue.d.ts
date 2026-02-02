import type { SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
/**
 * A message queue for controlling async generators.
 * Allows external code to push messages that an async generator yields.
 */
export declare class MessageQueue {
    private messages;
    private waiters;
    private closed;
    /**
     * Push a message into the queue.
     * If there's a waiting consumer, it will be notified immediately.
     */
    push(message: SDKUserMessage): void;
    /**
     * Close the queue. No more messages can be pushed.
     * All waiting consumers will receive null.
     */
    close(): void;
    /**
     * Async generator that yields messages as they arrive.
     */
    generate(): AsyncGenerator<SDKUserMessage, void>;
}
