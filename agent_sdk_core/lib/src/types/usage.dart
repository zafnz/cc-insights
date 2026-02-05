/// Token usage information.
class Usage {
  const Usage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  int get totalTokens => inputTokens + outputTokens;

  factory Usage.fromJson(Map<String, dynamic> json) {
    return Usage(
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      cacheCreationInputTokens: json['cache_creation_input_tokens'] as int?,
      cacheReadInputTokens: json['cache_read_input_tokens'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        if (cacheCreationInputTokens != null)
          'cache_creation_input_tokens': cacheCreationInputTokens,
        if (cacheReadInputTokens != null)
          'cache_read_input_tokens': cacheReadInputTokens,
      };
}

/// Per-model usage breakdown.
class ModelUsage {
  const ModelUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadInputTokens,
    required this.cacheCreationInputTokens,
    required this.webSearchRequests,
    required this.costUsd,
    required this.contextWindow,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadInputTokens;
  final int cacheCreationInputTokens;
  final int webSearchRequests;
  final double costUsd;
  final int contextWindow;

  factory ModelUsage.fromJson(Map<String, dynamic> json) {
    return ModelUsage(
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      cacheReadInputTokens: json['cacheReadInputTokens'] as int? ?? 0,
      cacheCreationInputTokens: json['cacheCreationInputTokens'] as int? ?? 0,
      webSearchRequests: json['webSearchRequests'] as int? ?? 0,
      costUsd: (json['costUSD'] as num?)?.toDouble() ?? 0.0,
      contextWindow: json['contextWindow'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cacheReadInputTokens': cacheReadInputTokens,
        'cacheCreationInputTokens': cacheCreationInputTokens,
        'webSearchRequests': webSearchRequests,
        'costUSD': costUsd,
        'contextWindow': contextWindow,
      };
}

/// Information about an available model.
class ModelInfo {
  const ModelInfo({
    required this.value,
    required this.displayName,
    required this.description,
  });

  final String value;
  final String displayName;
  final String description;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      value: json['value'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'displayName': displayName,
        'description': description,
      };
}

/// Information about a slash command.
class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.argumentHint,
  });

  final String name;
  final String description;
  final String argumentHint;

  factory SlashCommand.fromJson(Map<String, dynamic> json) {
    return SlashCommand(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      argumentHint: json['argumentHint'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'argumentHint': argumentHint,
      };
}

/// MCP server status.
class McpServerStatus {
  const McpServerStatus({
    required this.name,
    required this.status,
    this.serverInfo,
  });

  final String name;
  final McpStatus status;
  final McpServerInfo? serverInfo;

  factory McpServerStatus.fromJson(Map<String, dynamic> json) {
    return McpServerStatus(
      name: json['name'] as String? ?? '',
      status: McpStatus.fromString(json['status'] as String? ?? 'pending'),
      serverInfo: json['serverInfo'] != null
          ? McpServerInfo.fromJson(json['serverInfo'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// MCP server connection status.
enum McpStatus {
  connected,
  failed,
  needsAuth,
  pending;

  static McpStatus fromString(String value) {
    switch (value) {
      case 'connected':
        return McpStatus.connected;
      case 'failed':
        return McpStatus.failed;
      case 'needs-auth':
        return McpStatus.needsAuth;
      case 'pending':
      default:
        return McpStatus.pending;
    }
  }
}

/// MCP server info.
class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.version,
  });

  final String name;
  final String version;

  factory McpServerInfo.fromJson(Map<String, dynamic> json) {
    return McpServerInfo(
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }
}

/// Account information.
class AccountInfo {
  const AccountInfo({
    this.email,
    this.organization,
    this.subscriptionType,
    this.tokenSource,
    this.apiKeySource,
  });

  final String? email;
  final String? organization;
  final String? subscriptionType;
  final String? tokenSource;
  final String? apiKeySource;

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      email: json['email'] as String?,
      organization: json['organization'] as String?,
      subscriptionType: json['subscriptionType'] as String?,
      tokenSource: json['tokenSource'] as String?,
      apiKeySource: json['apiKeySource'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (email != null) 'email': email,
        if (organization != null) 'organization': organization,
        if (subscriptionType != null) 'subscriptionType': subscriptionType,
        if (tokenSource != null) 'tokenSource': tokenSource,
        if (apiKeySource != null) 'apiKeySource': apiKeySource,
      };
}

/// Per-message usage data from assistant messages.
class MessageUsage {
  const MessageUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  factory MessageUsage.fromJson(Map<String, dynamic> json) {
    return MessageUsage(
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      cacheCreationInputTokens: json['cache_creation_input_tokens'] as int? ?? 0,
      cacheReadInputTokens: json['cache_read_input_tokens'] as int? ?? 0,
    );
  }

  /// Total tokens currently in context window.
  int get contextTokens =>
      inputTokens + cacheCreationInputTokens + cacheReadInputTokens;
}

/// Context window tracking state.
class ContextUsage {
  const ContextUsage({
    required this.currentTokens,
    required this.maxTokens,
  });

  final int currentTokens;
  final int maxTokens;

  double get percentUsed => maxTokens > 0
      ? (currentTokens / maxTokens) * 100
      : 0;

  int get remainingTokens => maxTokens - currentTokens;

  bool get isNearLimit => percentUsed > 80;
}
