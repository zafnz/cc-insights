/**
 * A message queue for controlling async generators.
 * Allows external code to push messages that an async generator yields.
 */
export class MessageQueue {
    messages = [];
    waiters = [];
    closed = false;
    /**
     * Push a message into the queue.
     * If there's a waiting consumer, it will be notified immediately.
     */
    push(message) {
        if (this.closed) {
            throw new Error("Cannot push to a closed queue");
        }
        if (this.waiters.length > 0) {
            // There's a consumer waiting, give it the message directly
            const resolve = this.waiters.shift();
            resolve(message);
        }
        else {
            // No consumer waiting, queue the message
            this.messages.push(message);
        }
    }
    /**
     * Close the queue. No more messages can be pushed.
     * All waiting consumers will receive null.
     */
    close() {
        this.closed = true;
        // Resolve all waiting consumers with null
        while (this.waiters.length > 0) {
            const resolve = this.waiters.shift();
            resolve(null);
        }
    }
    /**
     * Async generator that yields messages as they arrive.
     */
    async *generate() {
        while (!this.closed) {
            let message;
            if (this.messages.length > 0) {
                // We have a queued message, yield it
                message = this.messages.shift();
            }
            else {
                // Wait for a message to be pushed
                message = await new Promise((resolve) => {
                    this.waiters.push(resolve);
                });
            }
            // If we got null, the queue was closed
            if (message === null) {
                break;
            }
            yield message;
        }
    }
}
