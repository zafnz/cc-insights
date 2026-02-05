/// Options for creating a Claude session.
class SessionOptions {
  const SessionOptions({
    this.model,
    this.permissionMode,
    this.allowDangerouslySkipPermissions,
    this.permissionPromptToolName,
    this.tools,
    this.plugins,
    this.strictMcpConfig,
    this.resume,
    this.resumeSessionAt,
    this.allowedTools,
    this.disallowedTools,
    this.systemPrompt,
    this.maxTurns,
    this.maxBudgetUsd,
    this.maxThinkingTokens,
    this.includePartialMessages,
    this.enableFileCheckpointing,
    this.additionalDirectories,
    this.mcpServers,
    this.agents,
    this.hooks,
    this.sandbox,
    this.settingSources,
    this.betas,
    this.outputFormat,
    this.fallbackModel,
  });

  /// Model to use (e.g., 'sonnet', 'opus', 'haiku').
  final String? model;

  /// Permission mode for the session.
  final PermissionMode? permissionMode;

  /// Allow bypassing permission checks (required for bypassPermissions mode).
  final bool? allowDangerouslySkipPermissions;

  /// MCP tool name to use for permission prompts.
  final String? permissionPromptToolName;

  /// Tool configuration (list of tool names or preset).
  final ToolsConfig? tools;

  /// Plugin configurations.
  final List<Map<String, dynamic>>? plugins;

  /// Enforce strict MCP validation.
  final bool? strictMcpConfig;

  /// Resume an existing session by session ID.
  final String? resume;

  /// Resume a session at a specific message UUID.
  final String? resumeSessionAt;

  /// List of allowed tool names.
  final List<String>? allowedTools;

  /// List of disallowed tool names.
  final List<String>? disallowedTools;

  /// System prompt configuration.
  final SystemPrompt? systemPrompt;

  /// Maximum conversation turns.
  final int? maxTurns;

  /// Maximum budget in USD.
  final double? maxBudgetUsd;

  /// Maximum tokens for thinking process.
  final int? maxThinkingTokens;

  /// Include partial message events (streaming).
  final bool? includePartialMessages;

  /// Enable file checkpointing for rewind.
  final bool? enableFileCheckpointing;

  /// Additional directories Claude can access.
  final List<String>? additionalDirectories;

  /// MCP server configurations.
  final Map<String, McpServerConfig>? mcpServers;

  /// Subagent configurations.
  final Map<String, dynamic>? agents;

  /// Hook configurations.
  final Map<String, List<HookConfig>>? hooks;

  /// Sandbox settings.
  final Map<String, dynamic>? sandbox;

  /// Settings sources to load.
  final List<String>? settingSources;

  /// Beta feature flags.
  final List<String>? betas;

  /// Structured output configuration.
  final Map<String, dynamic>? outputFormat;

  /// Fallback model if primary fails.
  final String? fallbackModel;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (model != null) json['model'] = model;
    if (permissionMode != null) json['permission_mode'] = permissionMode!.value;
    if (allowDangerouslySkipPermissions != null) {
      json['allow_dangerously_skip_permissions'] = allowDangerouslySkipPermissions;
    }
    if (permissionPromptToolName != null) {
      json['permission_prompt_tool_name'] = permissionPromptToolName;
    }
    if (tools != null) json['tools'] = tools!.toJson();
    if (plugins != null) json['plugins'] = plugins;
    if (strictMcpConfig != null) json['strict_mcp_config'] = strictMcpConfig;
    if (resume != null) json['resume'] = resume;
    if (resumeSessionAt != null) json['resume_session_at'] = resumeSessionAt;
    if (allowedTools != null) json['allowed_tools'] = allowedTools;
    if (disallowedTools != null) json['disallowed_tools'] = disallowedTools;
    if (systemPrompt != null) json['system_prompt'] = systemPrompt!.toJson();
    if (maxTurns != null) json['max_turns'] = maxTurns;
    if (maxBudgetUsd != null) json['max_budget_usd'] = maxBudgetUsd;
    if (maxThinkingTokens != null) json['max_thinking_tokens'] = maxThinkingTokens;
    if (includePartialMessages != null) {
      json['include_partial_messages'] = includePartialMessages;
    }
    if (enableFileCheckpointing != null) {
      json['enable_file_checkpointing'] = enableFileCheckpointing;
    }
    if (additionalDirectories != null) {
      json['additional_directories'] = additionalDirectories;
    }
    if (mcpServers != null) {
      json['mcp_servers'] = mcpServers!.map((k, v) => MapEntry(k, v.toJson()));
    }
    if (agents != null) json['agents'] = agents;
    if (hooks != null) {
      json['hooks'] = hooks!.map(
        (k, v) => MapEntry(k, v.map((h) => h.toJson()).toList()),
      );
    }
    if (sandbox != null) json['sandbox'] = sandbox;
    if (settingSources != null) json['setting_sources'] = settingSources;
    if (betas != null) json['betas'] = betas;
    if (outputFormat != null) json['output_format'] = outputFormat;
    if (fallbackModel != null) json['fallback_model'] = fallbackModel;

    return json;
  }
}

/// Permission mode for the session.
enum PermissionMode {
  defaultMode('default'),
  acceptEdits('acceptEdits'),
  bypassPermissions('bypassPermissions'),
  plan('plan');

  const PermissionMode(this.value);
  final String value;

  static PermissionMode fromString(String value) {
    switch (value) {
      case 'acceptEdits':
        return PermissionMode.acceptEdits;
      case 'bypassPermissions':
        return PermissionMode.bypassPermissions;
      case 'plan':
        return PermissionMode.plan;
      case 'default':
      default:
        return PermissionMode.defaultMode;
    }
  }
}

/// Tool configuration for a session.
sealed class ToolsConfig {
  const ToolsConfig();

  dynamic toJson();
}

/// Explicit tool list.
class ToolListConfig extends ToolsConfig {
  const ToolListConfig(this.tools);

  final List<String> tools;

  @override
  List<String> toJson() => tools;
}

/// Preset tool configuration (claude_code).
class PresetToolsConfig extends ToolsConfig {
  const PresetToolsConfig();

  @override
  Map<String, dynamic> toJson() => {
        'type': 'preset',
        'preset': 'claude_code',
      };
}

/// System prompt configuration.
sealed class SystemPrompt {
  const SystemPrompt();

  dynamic toJson();
}

/// Custom string system prompt.
class CustomSystemPrompt extends SystemPrompt {
  const CustomSystemPrompt(this.prompt);

  final String prompt;

  @override
  String toJson() => prompt;
}

/// Preset system prompt (claude_code).
class PresetSystemPrompt extends SystemPrompt {
  const PresetSystemPrompt({this.append});

  /// Additional instructions to append to the preset prompt.
  final String? append;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'preset',
        'preset': 'claude_code',
        if (append != null) 'append': append,
      };
}

/// MCP server configuration.
sealed class McpServerConfig {
  const McpServerConfig();

  Map<String, dynamic> toJson();
}

/// Stdio MCP server configuration.
class McpStdioServerConfig extends McpServerConfig {
  const McpStdioServerConfig({
    required this.command,
    this.args,
    this.env,
  });

  final String command;
  final List<String>? args;
  final Map<String, String>? env;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'stdio',
        'command': command,
        if (args != null) 'args': args,
        if (env != null) 'env': env,
      };
}

/// SSE MCP server configuration.
class McpSseServerConfig extends McpServerConfig {
  const McpSseServerConfig({
    required this.url,
    this.headers,
  });

  final String url;
  final Map<String, String>? headers;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'sse',
        'url': url,
        if (headers != null) 'headers': headers,
      };
}

/// HTTP MCP server configuration.
class McpHttpServerConfig extends McpServerConfig {
  const McpHttpServerConfig({
    required this.url,
    this.headers,
  });

  final String url;
  final Map<String, String>? headers;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'http',
        'url': url,
        if (headers != null) 'headers': headers,
      };
}

/// Hook configuration.
class HookConfig {
  const HookConfig({this.matcher});

  /// Optional matcher pattern for this hook.
  final String? matcher;

  Map<String, dynamic> toJson() => {
        if (matcher != null) 'matcher': matcher,
      };
}
