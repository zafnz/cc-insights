import * as fs from "fs";
import * as path from "path";
import * as os from "os";

export type LogLevel = "debug" | "info" | "warn" | "error";

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  message: string;
  context?: Record<string, unknown>;
}

class Logger {
  private fileStream?: fs.WriteStream;
  private logFilePath?: string;
  private minLevel: LogLevel = "info";

  constructor() {
    this.setupFileLogging();
  }

  private setupFileLogging(): void {
    try {
      const tmpDir = os.tmpdir();
      const logDir = path.join(tmpDir, "claude-agent-insights");

      console.error(`[LOGGER] Setting up file logging, tmpDir=${tmpDir}, logDir=${logDir}`);

      if (!fs.existsSync(logDir)) {
        console.error(`[LOGGER] Creating log directory: ${logDir}`);
        fs.mkdirSync(logDir, { recursive: true });
      }

      const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
      this.logFilePath = path.join(logDir, `backend-${timestamp}.log`);

      console.error(`[LOGGER] Creating log file: ${this.logFilePath}`);
      this.fileStream = fs.createWriteStream(this.logFilePath, { flags: "a" });

      // Log the file path so we can find it
      this.logToStderr("info", `Logging to file: ${this.logFilePath}`);
      console.error(`[LOGGER] File logging setup complete`);
    } catch (err) {
      // If file logging fails, just continue with stderr only
      console.error(`[LOGGER] FAILED to setup file logging: ${err}`);
      console.error(`[LOGGER] Stack: ${(err as Error).stack}`);
      this.logToStderr("warn", `Failed to setup file logging: ${err}`);
    }
  }

  private shouldLog(level: LogLevel): boolean {
    const levels: LogLevel[] = ["debug", "info", "warn", "error"];
    const minIndex = levels.indexOf(this.minLevel);
    const levelIndex = levels.indexOf(level);
    return levelIndex >= minIndex;
  }

  private formatEntry(entry: LogEntry): string {
    const parts = [
      `[${entry.timestamp}]`,
      `[${entry.level.toUpperCase()}]`,
      entry.message,
    ];

    if (entry.context && Object.keys(entry.context).length > 0) {
      parts.push(JSON.stringify(entry.context));
    }

    return parts.join(" ");
  }

  private logToStderr(level: LogLevel, message: string, context?: Record<string, unknown>): void {
    if (!this.shouldLog(level)) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      context,
    };

    const formatted = this.formatEntry(entry);
    console.error(formatted);

    // Also write to file if available
    if (this.fileStream) {
      this.fileStream.write(formatted + "\n");
    }
  }

  setMinLevel(level: LogLevel): void {
    this.minLevel = level;
  }

  debug(message: string, context?: Record<string, unknown>): void {
    this.logToStderr("debug", message, context);
  }

  info(message: string, context?: Record<string, unknown>): void {
    this.logToStderr("info", message, context);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    this.logToStderr("warn", message, context);
  }

  error(message: string, context?: Record<string, unknown>): void {
    this.logToStderr("error", message, context);
  }

  getLogFilePath(): string | undefined {
    return this.logFilePath;
  }

  dispose(): void {
    if (this.fileStream) {
      this.fileStream.end();
    }
  }
}

// Singleton instance
export const logger = new Logger();
