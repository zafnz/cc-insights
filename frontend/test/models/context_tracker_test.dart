import 'package:cc_insights_v2/models/context_tracker.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('ContextTracker', () {
    final resources = TestResources();

    tearDown(() async {
      await resources.disposeAll();
    });

    group('initial state', () {
      test('starts with 0 current tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Assert
        check(tracker.currentTokens).equals(0);
      });

      test('starts with 200000 max tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Assert
        check(tracker.maxTokens).equals(200000);
      });

      test('starts with 0 percent used', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Assert
        check(tracker.percentUsed).equals(0.0);
      });
    });

    group('updateFromUsage', () {
      test('updates current tokens from input_tokens only', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        final usage = {
          'input_tokens': 5000,
        };

        // Act
        tracker.updateFromUsage(usage);

        // Assert
        check(tracker.currentTokens).equals(5000);
      });

      test('updates current tokens including cache_creation_input_tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        final usage = {
          'input_tokens': 5000,
          'cache_creation_input_tokens': 1000,
        };

        // Act
        tracker.updateFromUsage(usage);

        // Assert
        check(tracker.currentTokens).equals(6000);
      });

      test('updates current tokens including cache_read_input_tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        final usage = {
          'input_tokens': 5000,
          'cache_read_input_tokens': 2000,
        };

        // Act
        tracker.updateFromUsage(usage);

        // Assert
        check(tracker.currentTokens).equals(7000);
      });

      test('updates current tokens with all fields combined', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        final usage = {
          'input_tokens': 5000,
          'cache_creation_input_tokens': 1000,
          'cache_read_input_tokens': 2000,
        };

        // Act
        tracker.updateFromUsage(usage);

        // Assert
        check(tracker.currentTokens).equals(8000);
      });

      test('handles missing fields gracefully', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        final usage = <String, dynamic>{};

        // Act
        tracker.updateFromUsage(usage);

        // Assert
        check(tracker.currentTokens).equals(0);
      });

      test('notifies listeners when updated', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        var notified = false;
        tracker.addListener(() => notified = true);

        // Act
        tracker.updateFromUsage({'input_tokens': 5000});

        // Assert
        check(notified).isTrue();
      });
    });

    group('updateMaxTokens', () {
      test('updates max tokens when valid value provided', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act
        tracker.updateMaxTokens(100000);

        // Assert
        check(tracker.maxTokens).equals(100000);
      });

      test('does not update max tokens when zero provided', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act
        tracker.updateMaxTokens(0);

        // Assert
        check(tracker.maxTokens).equals(200000); // unchanged
      });

      test('does not update max tokens when negative provided', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act
        tracker.updateMaxTokens(-100);

        // Assert
        check(tracker.maxTokens).equals(200000); // unchanged
      });

      test('does not notify listeners when value unchanged', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        var notifyCount = 0;
        tracker.addListener(() => notifyCount++);

        // Act
        tracker.updateMaxTokens(200000); // same as default

        // Assert
        check(notifyCount).equals(0);
      });

      test('notifies listeners when value changes', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        var notified = false;
        tracker.addListener(() => notified = true);

        // Act
        tracker.updateMaxTokens(150000);

        // Assert
        check(notified).isTrue();
      });
    });

    group('reset', () {
      test('clears current tokens to 0', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});
        check(tracker.currentTokens).equals(50000); // verify setup

        // Act
        tracker.reset();

        // Assert
        check(tracker.currentTokens).equals(0);
      });

      test('does not change max tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateMaxTokens(150000);
        tracker.updateFromUsage({'input_tokens': 50000});

        // Act
        tracker.reset();

        // Assert
        check(tracker.maxTokens).equals(150000);
      });

      test('notifies listeners when reset', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});
        var notified = false;
        tracker.addListener(() => notified = true);

        // Act
        tracker.reset();

        // Assert
        check(notified).isTrue();
      });
    });

    group('percentUsed', () {
      test('calculates correct percentage', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});

        // Act & Assert (50000 / 200000 = 25%)
        check(tracker.percentUsed).equals(25.0);
      });

      test('returns 0 when current tokens is 0', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act & Assert
        check(tracker.percentUsed).equals(0.0);
      });

      test('calculates correct percentage with custom max tokens', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateMaxTokens(100000);
        tracker.updateFromUsage({'input_tokens': 75000});

        // Act & Assert (75000 / 100000 = 75%)
        check(tracker.percentUsed).equals(75.0);
      });

      test('returns correct percentage when nearly full', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 180000});

        // Act & Assert (180000 / 200000 = 90%)
        check(tracker.percentUsed).equals(90.0);
      });

      test('handles over 100% gracefully', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateMaxTokens(100000);
        tracker.updateFromUsage({'input_tokens': 150000});

        // Act & Assert (150000 / 100000 = 150%)
        check(tracker.percentUsed).equals(150.0);
      });
    });

    group('multiple updates', () {
      test('overwrites previous value on each update', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act
        tracker.updateFromUsage({'input_tokens': 10000});
        check(tracker.currentTokens).equals(10000);

        tracker.updateFromUsage({'input_tokens': 20000});
        check(tracker.currentTokens).equals(20000);

        tracker.updateFromUsage({'input_tokens': 5000});
        check(tracker.currentTokens).equals(5000);
      });

      test('percentUsed updates after token change', () {
        // Arrange
        final tracker = resources.track(ContextTracker());

        // Act & Assert
        tracker.updateFromUsage({'input_tokens': 100000});
        check(tracker.percentUsed).equals(50.0);

        tracker.updateFromUsage({'input_tokens': 150000});
        check(tracker.percentUsed).equals(75.0);
      });

      test('percentUsed updates after max tokens change', () {
        // Arrange
        final tracker = resources.track(ContextTracker());
        tracker.updateFromUsage({'input_tokens': 50000});
        check(tracker.percentUsed).equals(25.0);

        // Act
        tracker.updateMaxTokens(100000);

        // Assert (50000 / 100000 = 50%)
        check(tracker.percentUsed).equals(50.0);
      });
    });
  });
}
