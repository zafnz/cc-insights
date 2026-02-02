// Protocol types for mock backend
// Matches the protocol defined in dart_sdk/lib/src/protocol.dart

// ============================================================================
// Incoming messages (Dart/Flutter -> Mock Backend)
// ============================================================================

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
  suppress_output?: boolean;
  stop_reason?: string;
}

export interface PermissionUpdate {
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

// ============================================================================
// Outgoing messages (Mock Backend -> Dart/Flutter)
// ============================================================================

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
  payload: SdkMessagePayload;
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

// ============================================================================
// SDK Message Payload Types
// ============================================================================

export type SdkMessagePayload =
  | SystemInitPayload
  | AssistantPayload
  | UserPayload
  | ResultPayload;

export interface SystemInitPayload {
  type: "system";
  subtype: "init";
  uuid: string;
  session_id: string;
  cwd: string;
  model: string;
  permissionMode: string;
  tools: string[];
  mcp_servers: string[];
}

export interface AssistantPayload {
  type: "assistant";
  uuid: string;
  session_id: string;
  message: {
    role: "assistant";
    content: ContentBlock[];
    usage?: UsageInfo;
  };
  parent_tool_use_id: string | null;
}

export interface UserPayload {
  type: "user";
  uuid: string;
  session_id: string;
  message: {
    role: "user";
    content: ContentBlock[];
  };
  isSynthetic?: boolean;
  tool_use_result?: {
    content: string | unknown[];
  };
}

export interface ResultPayload {
  type: "result";
  subtype: "success" | "error" | "interrupted";
  uuid: string;
  session_id: string;
  duration_ms: number;
  duration_api_ms: number;
  is_error: boolean;
  num_turns: number;
  total_cost_usd: number;
  usage: UsageInfo;
}

// ============================================================================
// Content Block Types
// ============================================================================

export type ContentBlock =
  | TextBlock
  | ToolUseBlock
  | ToolResultBlock;

export interface TextBlock {
  type: "text";
  text: string;
}

export interface ToolUseBlock {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
}

export interface ToolResultBlock {
  type: "tool_result";
  tool_use_id: string;
  content: string | unknown[];
}

export interface UsageInfo {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}
