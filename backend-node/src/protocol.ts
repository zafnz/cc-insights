// Incoming messages (Dart → Backend)
export type IncomingMessage =
  | SessionCreateMessage
  | SessionSendMessage
  | SessionInterruptMessage
  | SessionKillMessage
  | CallbackResponseMessage
  | QueryCallMessage;

export interface SessionCreateMessage {
  type: "session.create";
  id: string;
  payload: {
    prompt: string;
    cwd: string;
    options?: SessionOptions;
  };
}

export interface SessionSendMessage {
  type: "session.send";
  id: string;
  session_id: string;
  payload: {
    message: string;
    content?: ContentBlock[];
  };
}

export type ContentBlock = TextContent | ImageContent;

export interface TextContent {
  type: "text";
  text: string;
}

export interface ImageContent {
  type: "image";
  source: {
    type: "base64";
    media_type: "image/png" | "image/jpeg" | "image/gif" | "image/webp";
    data: string;
  };
}

export interface SessionInterruptMessage {
  type: "session.interrupt";
  id: string;
  session_id: string;
  payload: Record<string, never>;
}

export interface SessionKillMessage {
  type: "session.kill";
  id: string;
  session_id: string;
  payload: Record<string, never>;
}

export interface CallbackResponseMessage {
  type: "callback.response";
  id: string;
  session_id: string;
  payload: PermissionResponsePayload | HookResponsePayload;
}

export interface PermissionResponsePayload {
  behavior: "allow" | "deny";
  updated_input?: Record<string, unknown>;
  message?: string;
  updated_permissions?: PermissionUpdate[];
  interrupt?: boolean;
}

export interface HookResponsePayload {
  continue?: boolean;
  decision?: "approve" | "block";
  system_message?: string;
  systemMessage?: string;
  reason?: string;
  hook_specific_output?: Record<string, unknown>;
  hookSpecificOutput?: Record<string, unknown>;
  suppressOutput?: boolean;
  stopReason?: string;
  // Accept snake_case variants for flexibility.
  suppress_output?: boolean;
  stop_reason?: string;
}

export interface PermissionUpdate {
  // Permission rule structure from SDK
  [key: string]: unknown;
}

export interface QueryCallMessage {
  type: "query.call";
  id: string;
  session_id: string;
  payload: {
    method: string;
    args?: unknown[];
  };
}

export interface SessionOptions {
  model?: string;
  permission_mode?: string;
  allow_dangerously_skip_permissions?: boolean;
  permission_prompt_tool_name?: string;
  tools?: string[] | { type: "preset"; preset: "claude_code" };
  plugins?: unknown[];
  strict_mcp_config?: boolean;
  resume?: string;
  resume_session_at?: string;
  allowed_tools?: string[];
  disallowed_tools?: string[];
  system_prompt?: string | { type: "preset"; preset: "claude_code"; append?: string };
  max_turns?: number;
  max_budget_usd?: number;
  max_thinking_tokens?: number;
  include_partial_messages?: boolean;
  enable_file_checkpointing?: boolean;
  additional_directories?: string[];
  mcp_servers?: Record<string, unknown>;
  agents?: Record<string, unknown>;
  hooks?: Record<string, unknown[]>;
  sandbox?: unknown;
  setting_sources?: string[];
  betas?: string[];
  output_format?: unknown;
  fallback_model?: string;
}

// Outgoing messages (Backend → Dart)
export type OutgoingMessage =
  | SessionCreatedMessage
  | SdkMessageMessage
  | CallbackRequestMessage
  | QueryResultMessage
  | SessionInterruptedMessage
  | SessionKilledMessage
  | ErrorMessage;

export interface SessionCreatedMessage {
  type: "session.created";
  id: string;
  session_id: string;
  payload: {
    sdk_session_id?: string;
  };
}

export interface SdkMessageMessage {
  type: "sdk.message";
  session_id: string;
  payload: unknown; // Raw SDK message
}

export interface CallbackRequestMessage {
  type: "callback.request";
  id: string;
  session_id: string;
  payload: {
    callback_type: "can_use_tool" | "hook";
    tool_name?: string;
    tool_input?: Record<string, unknown>;
    suggestions?: unknown[];
    hook_event?: string;
    hook_input?: unknown;
    // Permission context from SDK (for can_use_tool callbacks)
    tool_use_id?: string;
    agent_id?: string;
    blocked_path?: string;
    decision_reason?: string;
  };
}

export interface QueryResultMessage {
  type: "query.result";
  id: string;
  session_id: string;
  payload: {
    success: boolean;
    result?: unknown;
    error?: string;
  };
}

export interface SessionInterruptedMessage {
  type: "session.interrupted";
  id: string;
  session_id: string;
  payload: Record<string, never>;
}

export interface SessionKilledMessage {
  type: "session.killed";
  id: string;
  session_id: string;
  payload: Record<string, never>;
}

export interface ErrorMessage {
  type: "error";
  id?: string;
  session_id?: string;
  payload: {
    code: string;
    message: string;
    details?: unknown;
  };
}
