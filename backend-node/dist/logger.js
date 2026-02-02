import * as fs from "fs";
import * as path from "path";
import * as os from "os";
class Logger {
    fileStream;
    logFilePath;
    minLevel = "info";
    constructor() {
        this.setupFileLogging();
    }
    setupFileLogging() {
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
        }
        catch (err) {
            // If file logging fails, just continue with stderr only
            console.error(`[LOGGER] FAILED to setup file logging: ${err}`);
            console.error(`[LOGGER] Stack: ${err.stack}`);
            this.logToStderr("warn", `Failed to setup file logging: ${err}`);
        }
    }
    shouldLog(level) {
        const levels = ["debug", "info", "warn", "error"];
        const minIndex = levels.indexOf(this.minLevel);
        const levelIndex = levels.indexOf(level);
        return levelIndex >= minIndex;
    }
    formatEntry(entry) {
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
    logToStderr(level, message, context) {
        if (!this.shouldLog(level))
            return;
        const entry = {
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
    setMinLevel(level) {
        this.minLevel = level;
    }
    debug(message, context) {
        this.logToStderr("debug", message, context);
    }
    info(message, context) {
        this.logToStderr("info", message, context);
    }
    warn(message, context) {
        this.logToStderr("warn", message, context);
    }
    error(message, context) {
        this.logToStderr("error", message, context);
    }
    getLogFilePath() {
        return this.logFilePath;
    }
    dispose() {
        if (this.fileStream) {
            this.fileStream.end();
        }
    }
}
// Singleton instance
export const logger = new Logger();
