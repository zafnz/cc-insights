import 'dart:math';

import 'package:cc_insights_v2/services/worktree_name_generator.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateWorktreeName', () {
    test('returns adjective-noun format', () {
      final name = generateWorktreeName(random: Random(42));
      check(name).has((s) => RegExp(r'^[a-z]+-[a-z]+$').hasMatch(s),
          'matches adjective-noun format').isTrue();
    });

    test('returns lowercase hyphen-separated name', () {
      final name = generateWorktreeName(random: Random(0));
      check(name).not((s) => s.contains(' '));
      check(name)
          .has((s) => s == s.toLowerCase(), 'is lowercase')
          .isTrue();
      check(name).has((s) => s.contains('-'), 'contains hyphen').isTrue();
    });

    test('avoids existing branch names', () {
      // Generate a name with a fixed seed to know what it produces
      final firstAttempt = generateWorktreeName(random: Random(0));

      // Now generate again with that name in the existing set
      final name = generateWorktreeName(
        existingBranches: {firstAttempt},
        random: Random(0),
      );

      check(name).not((s) => s.equals(firstAttempt));
    });

    test('throws StateError after max retries exhausted', () {
      // Use a fixed seed and collect all names it would generate
      final names = <String>{};
      for (var i = 0; i < 3; i++) {
        names.add(generateWorktreeName(random: Random(i)));
      }

      // Create a Random subclass that always returns index 0
      // This forces the same name every time
      final alwaysSameRandom = _FixedRandom();
      final alwaysSameName = generateWorktreeName(random: alwaysSameRandom);

      check(
        () => generateWorktreeName(
          existingBranches: {alwaysSameName},
          maxRetries: 3,
          random: _FixedRandom(),
        ),
      ).throws<StateError>();
    });

    test('produces deterministic names with same seed', () {
      final name1 = generateWorktreeName(random: Random(99));
      final name2 = generateWorktreeName(random: Random(99));
      check(name1).equals(name2);
    });

    test('produces different names with different seeds', () {
      final names = <String>{};
      for (var seed = 0; seed < 10; seed++) {
        names.add(generateWorktreeName(random: Random(seed)));
      }
      // At least some variety expected
      check(names.length).isGreaterThan(1);
    });
  });
}

/// A [Random] that always returns 0 for [nextInt], producing the same
/// namer output every call.
class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 0;

  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => false;
}
