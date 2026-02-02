export type LogLevel = "debug" | "info" | "warn" | "error";
declare class Logger {
    private fileStream?;
    private logFilePath?;
    private minLevel;
    constructor();
    private setupFileLogging;
    private shouldLog;
    private formatEntry;
    private logToStderr;
    setMinLevel(level: LogLevel): void;
    debug(message: string, context?: Record<string, unknown>): void;
    info(message: string, context?: Record<string, unknown>): void;
    warn(message: string, context?: Record<string, unknown>): void;
    error(message: string, context?: Record<string, unknown>): void;
    getLogFilePath(): string | undefined;
    dispose(): void;
}
export declare const logger: Logger;
export {};
