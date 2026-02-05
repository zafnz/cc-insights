import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

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
}
