/// Services for CC-Insights V2.
///
/// This library exports all service classes that handle external
/// interactions (git, backend, persistence, etc.).
library;

export 'agent_registry.dart';
export 'agent_service.dart';
export 'ask_ai_service.dart';
// Hide WorktreeInfo from git_service to avoid conflict with persistence_models
export 'git_service.dart' hide WorktreeInfo;
export 'persistence_models.dart';
export 'persistence_service.dart';
export 'project_restore_service.dart';
export 'runtime_config.dart';
