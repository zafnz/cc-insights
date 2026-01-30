import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Path normalization tests', () {
    test('canonicalize resolves .. correctly', () {
      final path = '/tmp/cc-insights/test-project/flutter_app_v2/..';
      final canonical = p.canonicalize(path);

      expect(canonical, '/tmp/cc-insights/test-project');
      expect(p.basename(canonical), 'test-project');
    });

    test('canonicalize removes trailing slash', () {
      final path = '/tmp/cc-insights/test-project/flutter_app_v2/../';
      final dir = Directory(path);
      final canonical = p.canonicalize(dir.absolute.path);

      expect(canonical, '/tmp/cc-insights/test-project');
      expect(p.basename(canonical), 'test-project');
    });

    test('basename handles normal paths', () {
      final path = '/tmp/cc-insights/test-project/flutter_app_v2';
      final basename = p.basename(path);

      expect(basename, 'flutter_app_v2');
    });

    test('basename handles paths with trailing slash', () {
      final path = '/tmp/cc-insights/test-project/flutter_app_v2/';
      final basename = p.basename(path);

      expect(basename, 'flutter_app_v2');
    });
  });
}
