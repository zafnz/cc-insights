import 'package:agent_sdk_core/agent_sdk_core.dart' show AccountInfo;
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

import 'setting_definition.dart';

/// Model definition for a chat session.
@immutable
class ChatModel {
  const ChatModel({
    required this.id,
    required this.label,
    required this.backend,
    this.description = '',
  });

  /// Model identifier used by the backend.
  final String id;

  /// Display label for UI.
  final String label;

  /// Backend that provides this model.
  final BackendType backend;

  /// Description from the backend (e.g. "Opus 4.6 · Most capable for complex work").
  final String description;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatModel &&
        other.id == id &&
        other.label == label &&
        other.backend == backend &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(id, label, backend, description);
}

/// Catalog of known models per backend.
class ChatModelCatalog {
  static const ChatModel _claudeDefaultModel = ChatModel(
    id: 'default',
    label: 'Default',
    backend: BackendType.directCli,
  );

  static final List<ChatModel> _defaultClaudeModels = [
    _claudeDefaultModel,
    const ChatModel(
        id: 'haiku', label: 'Haiku', backend: BackendType.directCli),
    const ChatModel(
        id: 'sonnet', label: 'Sonnet', backend: BackendType.directCli),
    const ChatModel(
        id: 'opus', label: 'Opus', backend: BackendType.directCli),
  ];

  static List<ChatModel> _claudeModels = List.of(_defaultClaudeModels);

  static List<ChatModel> get claudeModels => List.unmodifiable(_claudeModels);

  static void updateClaudeModels(List<ChatModel> models) {
    if (models.isEmpty) return;
    final updated = <ChatModel>[];
    final seen = <String>{};
    for (final model in models) {
      if (seen.contains(model.id)) continue;
      seen.add(model.id);
      updated.add(model);
    }
    _claudeModels = updated;
  }

  /// Account information from the Claude CLI (set during model discovery).
  static AccountInfo? _accountInfo;
  static AccountInfo? get accountInfo => _accountInfo;
  static void updateAccountInfo(AccountInfo? info) => _accountInfo = info;

  static const ChatModel _codexDefaultModel = ChatModel(
    id: '',
    label: 'Default (server)',
    backend: BackendType.codex,
  );

  static const ChatModel _acpDefaultModel = ChatModel(
    id: '',
    label: 'Default (agent)',
    backend: BackendType.acp,
  );

  static final List<ChatModel> _defaultCodexModels = [
    _codexDefaultModel,
  ];

  static const List<ChatModel> acpModels = [
    _acpDefaultModel,
  ];

  static List<ChatModel> _codexModels = List.of(_defaultCodexModels);

  static List<ChatModel> get codexModels => List.unmodifiable(_codexModels);

  static void updateCodexModels(List<ChatModel> models) {
    if (models.isEmpty) return;

    final updated = <ChatModel>[];
    final seen = <String>{};

    updated.add(_codexDefaultModel);
    seen.add(_codexDefaultModel.id);

    for (final model in models) {
      if (model.id.isEmpty || seen.contains(model.id)) continue;
      seen.add(model.id);
      updated.add(model);
    }

    _codexModels = updated;
  }

  static List<ChatModel> forBackend(BackendType backend) {
    return switch (backend) {
      BackendType.codex => codexModels,
      BackendType.directCli => claudeModels,
      BackendType.acp => acpModels,
    };
  }

  static BackendType backendFromValue(String? value) {
    switch (value) {
      case 'codex':
        return BackendType.codex;
      case 'acp':
        return BackendType.acp;
      case 'direct':
      case 'directcli':
      case 'cli':
      case 'claude':
      default:
        return BackendType.directCli;
    }
  }

  static ChatModel defaultForBackend(
    BackendType backend,
    String? preferredId,
  ) {
    final models = forBackend(backend);
    if (preferredId != null) {
      final match = models.where((m) => m.id == preferredId).toList();
      if (match.isNotEmpty) return match.first;
    }
    return models.first;
  }

  /// Resolves a composite setting value (e.g. `"claude:opus"`,
  /// `"codex:gpt-5.2"`, `"last_used"`) to a [ChatModel].
  ///
  /// For `"last_used"` or unrecognised values, falls back to the first
  /// model of [fallbackBackend] (defaults to [BackendType.directCli]).
  static ChatModel defaultFromComposite(
    String composite, {
    BackendType fallbackBackend = BackendType.directCli,
  }) {
    final parsed = parseCompositeModel(composite);
    if (parsed != null) {
      return defaultForBackend(parsed.$1, parsed.$2);
    }
    return defaultForBackend(fallbackBackend, null);
  }

  /// Returns all available models as composite setting options.
  ///
  /// Format: `"last_used"`, `"claude:<id>"`, `"codex:<id>"`, or `"acp:<id>"`.
  static List<SettingOption> allModelOptions() {
    final options = <SettingOption>[
      const SettingOption(value: 'last_used', label: 'Last used'),
    ];
    for (final m in claudeModels) {
      options.add(SettingOption(
        value: 'claude:${m.id}',
        label: 'Claude: ${m.label}',
      ));
    }
    for (final m in codexModels) {
      final label =
          m.id.isEmpty ? 'Codex: Default (server)' : 'Codex: ${m.label}';
      options.add(SettingOption(value: 'codex:${m.id}', label: label));
    }
    for (final m in acpModels) {
      final label =
          m.id.isEmpty ? 'ACP: Default (agent)' : 'ACP: ${m.label}';
      options.add(SettingOption(value: 'acp:${m.id}', label: label));
    }
    return options;
  }

  /// Parses a composite model value into backend type and model ID.
  ///
  /// Returns `null` for `"last_used"` or unrecognised values.
  static (BackendType, String?)? parseCompositeModel(String value) {
    if (value == 'last_used') return null;
    final colon = value.indexOf(':');
    if (colon < 0) return null;
    final prefix = value.substring(0, colon);
    final modelId = value.substring(colon + 1);
    final backend = switch (prefix) {
      'codex' => BackendType.codex,
      'acp' => BackendType.acp,
      _ => BackendType.directCli,
    };
    return (backend, modelId.isEmpty ? null : modelId);
  }
}
