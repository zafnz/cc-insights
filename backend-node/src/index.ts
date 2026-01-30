// IMPORTANT: Set CLAUDE_CODE_PATH before importing SDK to avoid Node v25 compatibility issues
// The bundled CLI in the SDK is incompatible with Node v25, so use the system claude binary
import { execSync } from "child_process";

// IMMEDIATE STARTUP MARKER - This should appear in logs immediately
console.error("========================");
console.error("[BACKEND] Process starting...");
console.error("[BACKEND] PID:", process.pid);
console.error("[BACKEND] Node version:", process.version);
console.error("[BACKEND] CWD:", process.cwd());
console.error("========================");

if (!process.env.CLAUDE_CODE_PATH) {
  // Try to find claude in common locations
  try {
    const which = execSync("which claude", {
      encoding: "utf-8",
    }).trim();
    if (which) {
      process.env.CLAUDE_CODE_PATH = which;
    }
  } catch (err) {
    // claude not found, SDK will use bundled version (may fail on Node v25+)
    console.error("[WARNING] claude binary not found in PATH, SDK will use bundled CLI which may not work on Node v25+");
  }
}

import * as readline from "readline";
import * as fs from "fs";
import { SessionManager } from "./session-manager.js";
import type { IncomingMessage } from "./protocol.js";
import { logger } from "./logger.js";

console.error("[BACKEND] Logger initialized, starting session manager...");

logger.info("Backend process starting", {
  pid: process.pid,
  claudeCodePath: process.env.CLAUDE_CODE_PATH,
});

// Open message log file
const messageLogPath = "/tmp/messages.jsonl";
const messageLogStream = fs.createWriteStream(messageLogPath, { flags: "a" });

function logMessage(direction: "IN" | "OUT", message: unknown): void {
  const entry = {
    timestamp: new Date().toISOString(),
    direction,
    message,
  };
  messageLogStream.write(JSON.stringify(entry) + "\n");
}

logger.info("Logging messages to", { path: messageLogPath });

// Create session manager with stdout callback
const sessions = new SessionManager((msg) => {
  logMessage("OUT", msg);
  console.log(JSON.stringify(msg));
});

// Read JSON lines from stdin
const rl = readline.createInterface({
  input: process.stdin,
  terminal: false,
});

rl.on("line", async (line) => {
  if (!line.trim()) return;

  logger.debug("Received message from stdin", { length: line.length });

  try {
    const msg = JSON.parse(line) as IncomingMessage;
    logMessage("IN", msg);
    logger.debug("Parsed message", { type: msg.type });
    await sessions.handleMessage(msg);
  } catch (err) {
    logger.error("Failed to parse message from stdin", {
      error: String(err),
      line: line.substring(0, 100),
    });
    const errorMsg = {
      type: "error",
      payload: {
        code: "INVALID_MESSAGE",
        message: String(err),
      },
    };
    logMessage("OUT", errorMsg);
    console.log(JSON.stringify(errorMsg));
  }
});

rl.on("close", () => {
  logger.info("Stdin closed, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});

// Handle process signals
process.on("SIGTERM", () => {
  logger.info("Received SIGTERM, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});

process.on("SIGINT", () => {
  logger.info("Received SIGINT, shutting down");
  sessions.dispose();
  messageLogStream.end();
  logger.dispose();
  process.exit(0);
});

logger.info("Backend process ready", {
  logFile: logger.getLogFilePath(),
});
