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
  });

  /// Model identifier used by the backend.
  final String id;

  /// Display label for UI.
  final String label;

  /// Backend that provides this model.
  final BackendType backend;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatModel &&
        other.id == id &&
        other.label == label &&
        other.backend == backend;
  }

  @override
  int get hashCode => Object.hash(id, label, backend);
}

/// Catalog of known models per backend.
class ChatModelCatalog {
  static const List<ChatModel> claudeModels = [
    ChatModel(id: 'haiku', label: 'Haiku', backend: BackendType.directCli),
    ChatModel(id: 'sonnet', label: 'Sonnet', backend: BackendType.directCli),
    ChatModel(id: 'opus', label: 'Opus', backend: BackendType.directCli),
  ];

  static const ChatModel _codexDefaultModel = ChatModel(
    id: '',
    label: 'Default (server)',
    backend: BackendType.codex,
  );

  static final List<ChatModel> _defaultCodexModels = [
    _codexDefaultModel,
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
    };
  }

  static BackendType backendFromValue(String? value) {
    switch (value) {
      case 'codex':
        return BackendType.codex;
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
  /// Format: `"last_used"`, `"claude:<id>"`, or `"codex:<id>"`.
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
    final backend =
        prefix == 'codex' ? BackendType.codex : BackendType.directCli;
    return (backend, modelId.isEmpty ? null : modelId);
  }
}
