/// Domain models for CC-Insights V2.
///
/// This library exports all model classes following the Data/State pattern:
/// - Data classes: Immutable, use copyWith() for mutations
/// - State classes: Extend ChangeNotifier, manage mutations
library;

export 'agent.dart';
export 'chat.dart';
export 'conversation.dart';
export 'output_entry.dart';
export 'project.dart';
export 'worktree.dart';
