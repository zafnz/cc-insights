import { v4 as uuidv4 } from "uuid";
import {
  SdkMessageMessage,
  SessionOptions,
  SystemInitPayload,
  AssistantPayload,
  ResultPayload,
  UsageInfo,
  UserPayload,
  CallbackRequestMessage,
  ToolUseBlock,
} from "./protocol";

/**
 * Emit function type - used to send messages to stdout
 */
export type EmitFn = (message: SdkMessageMessage) => void;

/**
 * Callback resolver type - used to wait for callback responses
 */
export type CallbackResolver = (callbackId: string) => Promise<unknown>;

/**
 * Scenario interface - all scenarios must implement this
 */
export interface Scenario {
  /**
   * Execute the scenario in response to a prompt
   */
  respond(
    prompt: string,
    emit: EmitFn,
    waitForCallback?: CallbackResolver
  ): Promise<void>;
}

/**
 * Default tools available in the mock
 */
const DEFAULT_TOOLS = [
  "Read",
  "Write",
  "Edit",
  "Bash",
  "Glob",
  "Grep",
  "WebFetch",
  "WebSearch",
  "TodoWrite",
  "Task",
];

/**
 * Helper to create a system init message
 */
export function createSystemInit(
  sessionId: string,
  cwd: string,
  options?: SessionOptions
): SdkMessageMessage {
  const payload: SystemInitPayload = {
    type: "system",
    subtype: "init",
    uuid: uuidv4(),
    session_id: sessionId,
    cwd: cwd,
    model: options?.model || "claude-sonnet-4-5-20250514",
    permissionMode: options?.permission_mode || "default",
    tools: Array.isArray(options?.tools) ? options.tools : DEFAULT_TOOLS,
    mcp_servers: [],
  };

  return {
    type: "sdk.message",
    session_id: sessionId,
    payload,
  };
}

/**
 * Helper to create an assistant text message
 */
export function createAssistantText(
  sessionId: string,
  text: string,
  usage?: Partial<UsageInfo>
): SdkMessageMessage {
  const payload: AssistantPayload = {
    type: "assistant",
    uuid: uuidv4(),
    session_id: sessionId,
    message: {
      role: "assistant",
      content: [{ type: "text", text }],
      usage: {
        input_tokens: usage?.input_tokens ?? 100,
        output_tokens: usage?.output_tokens ?? 50,
        cache_creation_input_tokens: usage?.cache_creation_input_tokens ?? 0,
        cache_read_input_tokens: usage?.cache_read_input_tokens ?? 80,
      },
    },
    parent_tool_use_id: null,
  };

  return {
    type: "sdk.message",
    session_id: sessionId,
    payload,
  };
}

/**
 * Helper to create a result message (marks turn completion)
 */
export function createResult(
  sessionId: string,
  options?: {
    numTurns?: number;
    durationMs?: number;
    totalCostUsd?: number;
    isError?: boolean;
    subtype?: "success" | "error" | "interrupted";
  }
): SdkMessageMessage {
  const payload: ResultPayload = {
    type: "result",
    subtype: options?.subtype ?? "success",
    uuid: uuidv4(),
    session_id: sessionId,
    duration_ms: options?.durationMs ?? 1000,
    duration_api_ms: options?.durationMs ?? 900,
    is_error: options?.isError ?? false,
    num_turns: options?.numTurns ?? 1,
    total_cost_usd: options?.totalCostUsd ?? 0.001,
    usage: {
      input_tokens: 100,
      output_tokens: 50,
    },
  };

  return {
    type: "sdk.message",
    session_id: sessionId,
    payload,
  };
}

/**
 * Helper to create an assistant message with a tool use
 */
export function createAssistantWithToolUse(
  sessionId: string,
  text: string,
  toolUse: ToolUseBlock,
  parentToolUseId?: string | null,
  usage?: Partial<UsageInfo>
): SdkMessageMessage {
  const payload: AssistantPayload = {
    type: "assistant",
    uuid: uuidv4(),
    session_id: sessionId,
    message: {
      role: "assistant",
      content: [
        { type: "text", text },
        toolUse,
      ],
      usage: {
        input_tokens: usage?.input_tokens ?? 100,
        output_tokens: usage?.output_tokens ?? 75,
        cache_creation_input_tokens: usage?.cache_creation_input_tokens ?? 0,
        cache_read_input_tokens: usage?.cache_read_input_tokens ?? 80,
      },
    },
    parent_tool_use_id: parentToolUseId ?? null,
  };

  return {
    type: "sdk.message",
    session_id: sessionId,
    payload,
  };
}

/**
 * Helper to create a user message with tool result
 */
export function createUserWithToolResult(
  sessionId: string,
  toolUseId: string,
  content: string | unknown[]
): SdkMessageMessage {
  const payload: UserPayload = {
    type: "user",
    uuid: uuidv4(),
    session_id: sessionId,
    message: {
      role: "user",
      content: [
        {
          type: "tool_result",
          tool_use_id: toolUseId,
          content: content,
        },
      ],
    },
    isSynthetic: true,
    tool_use_result: {
      content: content,
    },
  };

  return {
    type: "sdk.message",
    session_id: sessionId,
    payload,
  };
}

/**
 * Helper to create a callback request for tool permission
 */
export function createCallbackRequest(
  callbackId: string,
  sessionId: string,
  toolName: string,
  toolInput: Record<string, unknown>,
  toolUseId: string
): CallbackRequestMessage {
  return {
    type: "callback.request",
    id: callbackId,
    session_id: sessionId,
    payload: {
      callback_type: "can_use_tool",
      tool_name: toolName,
      tool_input: toolInput,
      tool_use_id: toolUseId,
    },
  };
}

/**
 * Helper function to emit a callback request to stdout
 * (Callback requests are different from sdk.message)
 */
export type EmitCallbackFn = (message: CallbackRequestMessage) => void;

/**
 * Echo scenario - responds to any prompt by echoing it back
 */
export class EchoScenario implements Scenario {
  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {}

  async respond(prompt: string, emit: EmitFn): Promise<void> {
    // Small delay to simulate processing
    await this.delay(100);

    // Send system init
    emit(createSystemInit(this.sessionId, this.cwd, this.options));

    // Small delay before response
    await this.delay(200);

    // Send assistant response echoing the prompt
    emit(
      createAssistantText(
        this.sessionId,
        `You said: "${prompt}"\n\nThis is a mock response from the echo scenario. The mock backend is working correctly!`
      )
    );

    // Small delay before result
    await this.delay(100);

    // Send result to mark completion
    emit(createResult(this.sessionId, { numTurns: 1 }));
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * ToolUsageScenario - Demonstrates tool calls with permission requests
 *
 * Flow:
 * 1. Assistant says it will read a file
 * 2. Sends a tool_use block for "Read" tool
 * 3. Sends a callback.request for permission
 * 4. After callback.response is received, sends tool result
 * 5. Sends final assistant message with the "file contents"
 * 6. Sends result
 */
export class ToolUsageScenario implements Scenario {
  private isFirstTurn = true;

  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {}

  async respond(
    prompt: string,
    emit: EmitFn,
    waitForCallback?: CallbackResolver
  ): Promise<void> {
    await this.delay(100);

    // Only send system init on first turn
    if (this.isFirstTurn) {
      emit(createSystemInit(this.sessionId, this.cwd, this.options));
      this.isFirstTurn = false;
    }

    await this.delay(150);

    // Create tool use block
    const toolUseId = uuidv4();
    const filePath = `${this.cwd}/example.txt`;
    const toolUse: ToolUseBlock = {
      type: "tool_use",
      id: toolUseId,
      name: "Read",
      input: {
        file_path: filePath,
      },
    };

    // Send assistant message with tool use
    emit(
      createAssistantWithToolUse(
        this.sessionId,
        `I'll read the file to help with your request: "${prompt}"`,
        toolUse
      )
    );

    await this.delay(100);

    // Send callback request for permission
    const callbackId = uuidv4();
    const callbackRequest = createCallbackRequest(
      callbackId,
      this.sessionId,
      "Read",
      { file_path: filePath },
      toolUseId
    );

    // Emit the callback request (needs to go to stdout directly)
    console.log(JSON.stringify(callbackRequest));

    // Wait for callback response
    if (waitForCallback) {
      const response = await waitForCallback(callbackId);
      const permissionResponse = response as { behavior?: string; interrupted?: boolean; killed?: boolean };

      // Check if session was interrupted or killed
      if (permissionResponse.interrupted || permissionResponse.killed) {
        emit(
          createResult(this.sessionId, {
            numTurns: 1,
            subtype: "interrupted",
          })
        );
        return;
      }

      // Check if permission was denied
      if (permissionResponse.behavior === "deny") {
        emit(
          createAssistantText(
            this.sessionId,
            "I understand you've denied permission to read the file. Let me help you another way."
          )
        );
        emit(createResult(this.sessionId, { numTurns: 1 }));
        return;
      }
    }

    await this.delay(100);

    // Send tool result (simulated file contents)
    const mockFileContents = `# Example File\n\nThis is mock file content from ${filePath}.\nLine 2 of the file.\nLine 3 with some data: 42`;

    emit(createUserWithToolResult(this.sessionId, toolUseId, mockFileContents));

    await this.delay(150);

    // Send final assistant message with analysis
    emit(
      createAssistantText(
        this.sessionId,
        `I've read the file. Here's what I found:\n\n\`\`\`\n${mockFileContents}\n\`\`\`\n\nThe file contains 3 lines with example content. Is there anything specific you'd like me to do with this information?`
      )
    );

    await this.delay(100);

    emit(createResult(this.sessionId, { numTurns: 1 }));
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * MultiTurnScenario - Simulates a multi-turn conversation
 *
 * Flow:
 * - First response acknowledges the prompt
 * - Follow-up messages get contextual responses
 * - Tracks turn count
 */
export class MultiTurnScenario implements Scenario {
  private turnCount = 0;
  private conversationHistory: string[] = [];
  private isFirstTurn = true;

  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {}

  async respond(prompt: string, emit: EmitFn): Promise<void> {
    this.turnCount++;
    this.conversationHistory.push(prompt);

    await this.delay(100);

    // Only send system init on first turn
    if (this.isFirstTurn) {
      emit(createSystemInit(this.sessionId, this.cwd, this.options));
      this.isFirstTurn = false;
    }

    await this.delay(200);

    // Generate response based on turn count
    let response: string;
    if (this.turnCount === 1) {
      response = `Thanks for your message! You said: "${prompt}"\n\nThis is turn ${this.turnCount} of our conversation. I'm ready to help you with anything else. Just send a follow-up message!`;
    } else if (this.turnCount === 2) {
      response = `Great follow-up! You said: "${prompt}"\n\nThis is turn ${this.turnCount}. I remember you first asked about: "${this.conversationHistory[0]}"\n\nFeel free to continue our conversation.`;
    } else {
      response = `Turn ${this.turnCount} received! You said: "${prompt}"\n\nConversation summary (${this.turnCount} turns):\n${this.conversationHistory.map((msg, i) => `  ${i + 1}. "${msg.substring(0, 50)}${msg.length > 50 ? '...' : ''}"`).join('\n')}\n\nOur conversation is going well!`;
    }

    emit(createAssistantText(this.sessionId, response));

    await this.delay(100);

    emit(
      createResult(this.sessionId, {
        numTurns: this.turnCount,
        durationMs: 500 * this.turnCount,
      })
    );
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * ErrorScenario - Tests error handling
 *
 * Returns an error result message (is_error: true)
 * Useful for testing error UI
 */
export class ErrorScenario implements Scenario {
  private isFirstTurn = true;

  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {}

  async respond(prompt: string, emit: EmitFn): Promise<void> {
    await this.delay(100);

    // Only send system init on first turn
    if (this.isFirstTurn) {
      emit(createSystemInit(this.sessionId, this.cwd, this.options));
      this.isFirstTurn = false;
    }

    await this.delay(200);

    // Send an assistant message explaining the error is coming
    emit(
      createAssistantText(
        this.sessionId,
        `Processing your request: "${prompt}"\n\nOops! Something went wrong while processing this request.`
      )
    );

    await this.delay(100);

    // Send error result
    emit(
      createResult(this.sessionId, {
        numTurns: 1,
        isError: true,
        subtype: "error",
      })
    );
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * SubagentScenario - Simulates Task tool creating a subagent
 *
 * Flow:
 * 1. Assistant says it will use a specialized agent
 * 2. Sends a Task tool_use
 * 3. Sends messages with parent_tool_use_id set (simulating subagent output)
 * 4. Sends result from subagent
 * 5. Sends main agent's final response
 * 6. Sends final result
 */
export class SubagentScenario implements Scenario {
  private isFirstTurn = true;

  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {}

  async respond(prompt: string, emit: EmitFn): Promise<void> {
    await this.delay(100);

    // Only send system init on first turn
    if (this.isFirstTurn) {
      emit(createSystemInit(this.sessionId, this.cwd, this.options));
      this.isFirstTurn = false;
    }

    await this.delay(150);

    // Create Task tool use for spawning a subagent
    const taskToolUseId = uuidv4();
    const taskToolUse: ToolUseBlock = {
      type: "tool_use",
      id: taskToolUseId,
      name: "Task",
      input: {
        description: `Analyze the following request and provide a detailed response: "${prompt}"`,
        prompt: prompt,
      },
    };

    // Main agent says it will delegate to a subagent
    emit(
      createAssistantWithToolUse(
        this.sessionId,
        "I'll use a specialized agent to help with this task.",
        taskToolUse
      )
    );

    await this.delay(200);

    // Subagent's first message (note: parent_tool_use_id is set)
    const subagentPayload1: AssistantPayload = {
      type: "assistant",
      uuid: uuidv4(),
      session_id: this.sessionId,
      message: {
        role: "assistant",
        content: [
          {
            type: "text",
            text: `[Subagent] Starting analysis of your request: "${prompt}"`,
          },
        ],
        usage: {
          input_tokens: 50,
          output_tokens: 30,
        },
      },
      parent_tool_use_id: taskToolUseId,
    };

    emit({
      type: "sdk.message",
      session_id: this.sessionId,
      payload: subagentPayload1,
    });

    await this.delay(300);

    // Subagent's detailed analysis
    const subagentPayload2: AssistantPayload = {
      type: "assistant",
      uuid: uuidv4(),
      session_id: this.sessionId,
      message: {
        role: "assistant",
        content: [
          {
            type: "text",
            text: `[Subagent] Analysis complete!\n\nKey findings:\n1. Your request has been processed\n2. The mock subagent has analyzed the input\n3. Results are ready for the main agent\n\nReturning control to the main agent.`,
          },
        ],
        usage: {
          input_tokens: 80,
          output_tokens: 60,
        },
      },
      parent_tool_use_id: taskToolUseId,
    };

    emit({
      type: "sdk.message",
      session_id: this.sessionId,
      payload: subagentPayload2,
    });

    await this.delay(150);

    // Tool result from subagent
    emit(
      createUserWithToolResult(
        this.sessionId,
        taskToolUseId,
        "Subagent analysis completed successfully. The request has been processed and key insights have been generated."
      )
    );

    await this.delay(150);

    // Main agent's final response
    emit(
      createAssistantText(
        this.sessionId,
        `The specialized agent has completed its analysis.\n\nBased on the subagent's findings for "${prompt}":\n\n- Your request was successfully processed\n- The analysis identified relevant patterns\n- All subtasks have been completed\n\nIs there anything else you'd like me to help with?`
      )
    );

    await this.delay(100);

    emit(
      createResult(this.sessionId, {
        numTurns: 2,
        durationMs: 1500,
        totalCostUsd: 0.003,
      })
    );
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}

/**
 * Scenario engine - manages scenario selection and execution
 */
export class ScenarioEngine {
  private scenario: Scenario;

  constructor(
    private sessionId: string,
    private cwd: string,
    private options?: SessionOptions
  ) {
    // Select scenario based on environment variable or default to echo
    const scenarioName = process.env.MOCK_SCENARIO || "echo";
    this.scenario = this.loadScenario(scenarioName);
  }

  private loadScenario(name: string): Scenario {
    switch (name) {
      case "echo":
        return new EchoScenario(this.sessionId, this.cwd, this.options);
      case "tool-usage":
        return new ToolUsageScenario(this.sessionId, this.cwd, this.options);
      case "multi-turn":
        return new MultiTurnScenario(this.sessionId, this.cwd, this.options);
      case "error":
        return new ErrorScenario(this.sessionId, this.cwd, this.options);
      case "subagent":
        return new SubagentScenario(this.sessionId, this.cwd, this.options);
      default:
        // Default to echo scenario for unknown names
        return new EchoScenario(this.sessionId, this.cwd, this.options);
    }
  }

  /**
   * Execute the initial prompt scenario
   */
  async executeInitialPrompt(
    prompt: string,
    emit: EmitFn,
    waitForCallback?: CallbackResolver
  ): Promise<void> {
    await this.scenario.respond(prompt, emit, waitForCallback);
  }

  /**
   * Execute a follow-up message
   */
  async executeFollowUp(
    message: string,
    emit: EmitFn,
    waitForCallback?: CallbackResolver
  ): Promise<void> {
    // For now, just re-run the same scenario logic
    // Future: scenarios could track state for multi-turn conversations
    await this.scenario.respond(message, emit, waitForCallback);
  }
}
