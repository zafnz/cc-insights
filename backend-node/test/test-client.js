#!/usr/bin/env node

/**
 * Simple test client for manual testing of the backend.
 *
 * Usage:
 *   # After building the backend:
 *   node test/test-client.js
 *
 * This client:
 * - Spawns the backend as a subprocess
 * - Creates a simple test session
 * - Auto-approves all permission requests
 * - Logs all messages
 */

import { spawn } from "child_process";
import * as readline from "readline";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const backend = spawn("node", [join(__dirname, "../dist/index.js")], {
  stdio: ["pipe", "pipe", "inherit"],
});

// Read responses from backend stdout
const rl = readline.createInterface({ input: backend.stdout });

rl.on("line", (line) => {
  try {
    const msg = JSON.parse(line);
    console.log("<<<", JSON.stringify(msg, null, 2));

    // Auto-approve permissions
    if (
      msg.type === "callback.request" &&
      msg.payload.callback_type === "can_use_tool"
    ) {
      console.log(`\n[auto-approving ${msg.payload.tool_name}]\n`);
      send({
        type: "callback.response",
        id: msg.id,
        session_id: msg.session_id,
        payload: { behavior: "allow" },
      });
    }
  } catch (err) {
    console.log("<<< (raw)", line);
  }
});

// Send helper
function send(msg) {
  console.log(">>>", JSON.stringify(msg));
  backend.stdin.write(JSON.stringify(msg) + "\n");
}

// Wait for backend to start
setTimeout(() => {
  // Create a simple test session
  send({
    type: "session.create",
    id: "test-1",
    payload: {
      prompt: "What is 2+2? Reply with just the number.",
      cwd: process.cwd(),
      options: {
        model: "sonnet",
        permission_mode: "default",
      },
    },
  });
}, 500);

// Handle Ctrl+C
process.on("SIGINT", () => {
  console.log("\n[killing backend]");
  backend.kill();
  process.exit(0);
});

// Handle backend exit
backend.on("exit", (code) => {
  console.log(`[backend exited with code ${code}]`);
  process.exit(code ?? 0);
});
