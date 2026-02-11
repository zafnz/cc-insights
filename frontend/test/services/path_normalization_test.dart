import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Path normalization tests', () {
    test('canonicalize resolves .. correctly', () {
      const path = '/tmp/cc-insights/test-project/frontend/..';
      final canonical = p.canonicalize(path);

      expect(canonical, '/tmp/cc-insights/test-project');
      expect(p.basename(canonical), 'test-project');
    });

    test('canonicalize removes trailing slash', () {
      const path = '/tmp/cc-insights/test-project/frontend/../';
      final dir = Directory(path);
      final canonical = p.canonicalize(dir.absolute.path);

      expect(canonical, '/tmp/cc-insights/test-project');
      expect(p.basename(canonical), 'test-project');
    });

    test('basename handles normal paths', () {
      const path = '/tmp/cc-insights/test-project/frontend';
      final basename = p.basename(path);

      expect(basename, 'frontend');
    });

    test('basename handles paths with trailing slash', () {
      const path = '/tmp/cc-insights/test-project/frontend/';
      final basename = p.basename(path);

      expect(basename, 'frontend');
    });
  });
}
