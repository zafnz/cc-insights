import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cc_insights_v2/widgets/tag_colors.dart';

void main() {
  group('tagColor', () {
    group('well-known defaults', () {
      test('bug returns red', () {
        expect(tagColor('bug'), const Color(0xFFEF5350));
      });

      test('bugfix returns red', () {
        expect(tagColor('bugfix'), const Color(0xFFEF5350));
      });

      test('feature returns purple', () {
        expect(tagColor('feature'), const Color(0xFFBA68C8));
      });

      test('todo returns orange', () {
        expect(tagColor('todo'), const Color(0xFFFFA726));
      });

      test('inprogress returns blue', () {
        expect(tagColor('inprogress'), const Color(0xFF42A5F5));
      });

      test('in-progress returns blue', () {
        expect(tagColor('in-progress'), const Color(0xFF42A5F5));
      });

      test('done returns green', () {
        expect(tagColor('done'), const Color(0xFF4CAF50));
      });

      test('completed returns green', () {
        expect(tagColor('completed'), const Color(0xFF4CAF50));
      });

      test('high-priority returns red', () {
        expect(tagColor('high-priority'), const Color(0xFFEF5350));
      });

      test('critical returns red', () {
        expect(tagColor('critical'), const Color(0xFFEF5350));
      });

      test('docs returns grey', () {
        expect(tagColor('docs'), const Color(0xFF9E9E9E));
      });

      test('documentation returns grey', () {
        expect(tagColor('documentation'), const Color(0xFF9E9E9E));
      });

      test('test returns teal', () {
        expect(tagColor('test'), const Color(0xFF4DB6AC));
      });

      test('testing returns teal', () {
        expect(tagColor('testing'), const Color(0xFF4DB6AC));
      });
    });

    group('custom colour override', () {
      test('customHex overrides well-known default', () {
        final color = tagColor('bug', customHex: '#42a5f5');
        expect(color, const Color(0xFF42A5F5));
      });

      test('customHex without # prefix works', () {
        final color = tagColor('bug', customHex: 'ba68c8');
        expect(color, const Color(0xFFBA68C8));
      });

      test('customHex overrides hash fallback', () {
        final color = tagColor('unknown-tag', customHex: '#4caf50');
        expect(color, const Color(0xFF4CAF50));
      });

      test('invalid customHex falls back to well-known', () {
        final color = tagColor('bug', customHex: 'nope');
        expect(color, const Color(0xFFEF5350));
      });

      test('invalid customHex falls back to hash', () {
        final color = tagColor('unknown-tag', customHex: 'xyz');
        // Should produce a valid color from hash fallback
        expect(color.a, 1.0);
      });
    });

    group('deterministic hash fallback', () {
      test('unknown tag returns a valid colour', () {
        final color = tagColor('my-custom-tag');
        expect(color.a, 1.0);
      });

      test('same name always returns same colour', () {
        final a = tagColor('some-random-tag');
        final b = tagColor('some-random-tag');
        expect(a, b);
      });

      test('different names can produce different colours', () {
        // With enough different names, at least some should differ
        final colors = <Color>{};
        for (final name in ['aaa', 'bbb', 'ccc', 'ddd', 'eee', 'fff']) {
          colors.add(tagColor(name));
        }
        expect(colors.length, greaterThan(1));
      });

      test('hash fallback is not used when well-known matches', () {
        // Well-known 'feature' is purple, hash might give something else
        expect(tagColor('feature'), const Color(0xFFBA68C8));
      });
    });

    group('all tags produce valid colours', () {
      test('well-known tags have full opacity', () {
        for (final name in [
          'bug',
          'bugfix',
          'feature',
          'todo',
          'inprogress',
          'in-progress',
          'done',
          'completed',
          'high-priority',
          'critical',
          'docs',
          'documentation',
          'test',
          'testing',
        ]) {
          final color = tagColor(name);
          expect(color.a, 1.0, reason: '$name should have full opacity');
        }
      });

      test('arbitrary tags have full opacity', () {
        for (final name in ['x', 'hello-world', 'release-v2', '123']) {
          final color = tagColor(name);
          expect(color.a, 1.0, reason: '$name should have full opacity');
        }
      });
    });
  });
}
