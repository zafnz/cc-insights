import * as readline from "readline";
import { SessionManager } from "./session-manager";
import { IncomingMessage, OutgoingMessage } from "./protocol";

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
 * Send a message to stdout (to the Dart SDK)
 */
function send(message: OutgoingMessage): void {
  console.log(JSON.stringify(message));
}

/**
 * Main entry point
 */
async function main(): Promise<void> {
  log("Mock backend starting...");
  log("Scenario mode", { scenario: process.env.MOCK_SCENARIO || "echo" });

  const manager = new SessionManager();

  // Set up readline interface for stdin
  const rl = readline.createInterface({
    input: process.stdin,
    terminal: false,
  });

  // Handle each line of input
  rl.on("line", async (line: string) => {
    if (!line.trim()) {
      return;
    }

    try {
      const msg = JSON.parse(line) as IncomingMessage;
      const response = await manager.handleMessage(msg);

      // Some handlers emit messages directly, so response may be null
      if (response) {
        send(response);
      }
    } catch (error) {
      log("Failed to process message", { error: String(error), line });

      send({
        type: "error",
        payload: {
          code: "INVALID_MESSAGE",
          message: `Failed to parse message: ${error}`,
          details: { line },
        },
      });
    }
  });

  // Handle stdin close
  rl.on("close", () => {
    log("stdin closed, exiting...");
    process.exit(0);
  });

  // Handle SIGTERM
  process.on("SIGTERM", () => {
    log("Received SIGTERM, exiting...");
    process.exit(0);
  });

  // Handle SIGINT (Ctrl+C)
  process.on("SIGINT", () => {
    log("Received SIGINT, exiting...");
    process.exit(0);
  });

  // Handle uncaught errors
  process.on("uncaughtException", (error) => {
    log("Uncaught exception", { error: String(error) });
    send({
      type: "error",
      payload: {
        code: "UNCAUGHT_EXCEPTION",
        message: `Uncaught exception: ${error}`,
      },
    });
  });

  process.on("unhandledRejection", (reason) => {
    log("Unhandled rejection", { reason: String(reason) });
    send({
      type: "error",
      payload: {
        code: "UNHANDLED_REJECTION",
        message: `Unhandled rejection: ${reason}`,
      },
    });
  });

  log("Mock backend ready, waiting for input...");
}

// Start the application
main().catch((error) => {
  process.stderr.write(`Fatal error: ${error}\n`);
  process.exit(1);
});
