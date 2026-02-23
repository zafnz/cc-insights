import 'dart:math';

import 'package:namer/namer.dart' as namer;

/// Generates a random adjective-noun worktree name (e.g., "clever-fox")
/// that doesn't conflict with any [existingBranches].
///
/// Retries up to [maxRetries] times if a conflict is detected.
/// Accepts an optional [random] for deterministic testing.
/// Throws [StateError] if unable to generate a unique name.
String generateWorktreeName({
  Set<String> existingBranches = const {},
  int maxRetries = 10,
  Random? random,
}) {
  for (var i = 0; i < maxRetries; i++) {
    final raw = namer.generic(verbs: 0, adjectives: 1, random: random);
    final name = raw.toLowerCase().replaceAll(' ', '-');
    if (!existingBranches.contains(name)) {
      return name;
    }
  }
  throw StateError(
    'Failed to generate unique worktree name after $maxRetries attempts',
  );
}
