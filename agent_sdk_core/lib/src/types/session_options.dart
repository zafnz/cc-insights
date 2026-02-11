import 'security_config.dart';

/// Result of validating [SessionOptions] against a specific backend.
///
/// Contains a list of [warnings] for options that are set but unsupported
/// by the target backend. These options will be silently ignored at runtime.
class OptionsValidationResult {
  const OptionsValidationResult(this.warnings);

  /// Empty result with no warnings.
  static const empty = OptionsValidationResult([]);

  /// Human-readable warnings for unsupported options.
  final List<String> warnings;

  /// Whether validation passed with no warnings.
  bool get isClean => warnings.isEmpty;
}

/// Options for creating a Claude session.
class SessionOptions {
  const SessionOptions({
    this.model,
    this.permissionMode,
    this.reasoningEffort,
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
    this.codexSecurityConfig,
  });

  /// Model to use (e.g., 'sonnet', 'opus', 'haiku').
  final String? model;

  /// Permission mode for the session.
  final PermissionMode? permissionMode;

  /// Reasoning effort level (Codex only).
  ///
  /// Controls how much reasoning/thinking the model does before responding.
  /// Only applicable to Codex backends with reasoning-capable models.
  final ReasoningEffort? reasoningEffort;

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

  /// Security configuration for Codex backend.
  ///
  /// Used by the Codex backend to pass sandbox/approval settings to thread/start.
  /// This field is NOT serialized in toJson() since it's only used internally.
  final CodexSecurityConfig? codexSecurityConfig;

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

  /// Validate options for the Claude CLI (direct) backend.
  ///
  /// Returns warnings for options that the CLI backend ignores:
  /// reasoningEffort, allowDangerouslySkipPermissions, permissionPromptToolName,
  /// tools, plugins, strictMcpConfig, resumeSessionAt, allowedTools,
  /// disallowedTools, maxThinkingTokens, enableFileCheckpointing,
  /// additionalDirectories, agents, hooks, sandbox, betas,
  /// outputFormat, fallbackModel.
  OptionsValidationResult validateForCli() {
    final warnings = <String>[];
    if (reasoningEffort != null) {
      warnings.add('reasoningEffort is ignored by CLI backend');
    }
    if (allowDangerouslySkipPermissions != null) {
      warnings.add('allowDangerouslySkipPermissions is ignored by CLI backend');
    }
    if (permissionPromptToolName != null) {
      warnings.add('permissionPromptToolName is ignored by CLI backend');
    }
    if (tools != null) {
      warnings.add('tools is ignored by CLI backend');
    }
    if (plugins != null) {
      warnings.add('plugins is ignored by CLI backend');
    }
    if (strictMcpConfig != null) {
      warnings.add('strictMcpConfig is ignored by CLI backend');
    }
    if (resumeSessionAt != null) {
      warnings.add('resumeSessionAt is ignored by CLI backend');
    }
    if (allowedTools != null) {
      warnings.add('allowedTools is ignored by CLI backend');
    }
    if (disallowedTools != null) {
      warnings.add('disallowedTools is ignored by CLI backend');
    }
    if (maxThinkingTokens != null) {
      warnings.add('maxThinkingTokens is ignored by CLI backend');
    }
    if (enableFileCheckpointing != null) {
      warnings.add('enableFileCheckpointing is ignored by CLI backend');
    }
    if (additionalDirectories != null) {
      warnings.add('additionalDirectories is ignored by CLI backend');
    }
    if (agents != null) {
      warnings.add('agents is ignored by CLI backend');
    }
    if (hooks != null) {
      warnings.add('hooks is ignored by CLI backend');
    }
    if (sandbox != null) {
      warnings.add('sandbox is ignored by CLI backend');
    }
    // settingSources IS supported by CLI backend (via --setting-sources flag)
    if (betas != null) {
      warnings.add('betas is ignored by CLI backend');
    }
    if (outputFormat != null) {
      warnings.add('outputFormat is ignored by CLI backend');
    }
    if (fallbackModel != null) {
      warnings.add('fallbackModel is ignored by CLI backend');
    }
    return warnings.isEmpty
        ? OptionsValidationResult.empty
        : OptionsValidationResult(warnings);
  }

  /// Validate options for the Codex backend.
  ///
  /// Returns warnings for options that the Codex backend ignores:
  /// permissionMode, allowDangerouslySkipPermissions, permissionPromptToolName,
  /// tools, plugins, strictMcpConfig, resumeSessionAt, allowedTools,
  /// disallowedTools, maxTurns, maxBudgetUsd, maxThinkingTokens,
  /// includePartialMessages, enableFileCheckpointing, additionalDirectories,
  /// mcpServers, agents, hooks, sandbox, settingSources, betas, outputFormat,
  /// fallbackModel.
  ///
  /// Note: systemPrompt is now supported (mapped to baseInstructions).
  ///
  /// Also warns if codexSecurityConfig is set, as it should be handled
  /// separately by the Codex backend implementation.
  OptionsValidationResult validateForCodex() {
    final warnings = <String>[];
    if (permissionMode != null) {
      warnings.add('permissionMode is ignored by Codex backend (use codexSecurityConfig instead)');
    }
    if (codexSecurityConfig != null) {
      warnings.add('codexSecurityConfig is internal to Codex backend and not serialized in SessionOptions.toJson()');
    }
    if (allowDangerouslySkipPermissions != null) {
      warnings.add('allowDangerouslySkipPermissions is ignored by Codex backend');
    }
    if (permissionPromptToolName != null) {
      warnings.add('permissionPromptToolName is ignored by Codex backend');
    }
    if (tools != null) {
      warnings.add('tools is ignored by Codex backend');
    }
    if (plugins != null) {
      warnings.add('plugins is ignored by Codex backend');
    }
    if (strictMcpConfig != null) {
      warnings.add('strictMcpConfig is ignored by Codex backend');
    }
    if (resumeSessionAt != null) {
      warnings.add('resumeSessionAt is ignored by Codex backend');
    }
    if (allowedTools != null) {
      warnings.add('allowedTools is ignored by Codex backend');
    }
    if (disallowedTools != null) {
      warnings.add('disallowedTools is ignored by Codex backend');
    }
    // systemPrompt is now supported by Codex backend (mapped to baseInstructions)
    if (maxTurns != null) {
      warnings.add('maxTurns is ignored by Codex backend');
    }
    if (maxBudgetUsd != null) {
      warnings.add('maxBudgetUsd is ignored by Codex backend');
    }
    if (maxThinkingTokens != null) {
      warnings.add('maxThinkingTokens is ignored by Codex backend');
    }
    if (includePartialMessages != null) {
      warnings.add('includePartialMessages is ignored by Codex backend');
    }
    if (enableFileCheckpointing != null) {
      warnings.add('enableFileCheckpointing is ignored by Codex backend');
    }
    if (additionalDirectories != null) {
      warnings.add('additionalDirectories is ignored by Codex backend');
    }
    if (mcpServers != null) {
      warnings.add('mcpServers is ignored by Codex backend');
    }
    if (agents != null) {
      warnings.add('agents is ignored by Codex backend');
    }
    if (hooks != null) {
      warnings.add('hooks is ignored by Codex backend');
    }
    if (sandbox != null) {
      warnings.add('sandbox is ignored by Codex backend');
    }
    if (settingSources != null) {
      warnings.add('settingSources is ignored by Codex backend');
    }
    if (betas != null) {
      warnings.add('betas is ignored by Codex backend');
    }
    if (outputFormat != null) {
      warnings.add('outputFormat is ignored by Codex backend');
    }
    if (fallbackModel != null) {
      warnings.add('fallbackModel is ignored by Codex backend');
    }
    return warnings.isEmpty
        ? OptionsValidationResult.empty
        : OptionsValidationResult(warnings);
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

/// Reasoning effort level for Codex models.
///
/// Controls how much reasoning/thinking the model performs before responding.
/// See https://platform.openai.com/docs/guides/reasoning
enum ReasoningEffort {
  /// No reasoning.
  none('none', 'None'),

  /// Minimal reasoning.
  minimal('minimal', 'Minimal'),

  /// Low reasoning effort.
  low('low', 'Low'),

  /// Medium reasoning effort (default for most models).
  medium('medium', 'Medium'),

  /// High reasoning effort.
  high('high', 'High'),

  /// Extra-high reasoning effort.
  xhigh('xhigh', 'Extra High');

  const ReasoningEffort(this.value, this.label);

  /// The value sent to the Codex API.
  final String value;

  /// Human-readable label for UI display.
  final String label;

  static ReasoningEffort? fromString(String? value) {
    if (value == null) return null;
    for (final effort in values) {
      if (effort.value == value) return effort;
    }
    return null;
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
