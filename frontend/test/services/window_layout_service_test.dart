import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/services/window_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String configPath;
  late WindowLayoutService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('window_layout_test_');
    configPath = '${tempDir.path}/window.json';
    service = WindowLayoutService(configPath: configPath);
  });

  tearDown(() {
    service.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('WindowLayoutService', () {
    group('window size persistence', () {
      test('savedWindowSize returns null when not saved', () {
        expect(service.savedWindowSize, isNull);
      });

      test('saveWindowSize persists to disk', () async {
        await service.saveWindowSize(1920, 1080);

        final file = File(configPath);
        expect(file.existsSync(), isTrue);

        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json['window.width'], 1920);
        expect(json['window.height'], 1080);
      });

      test('savedWindowSize returns saved values', () async {
        await service.saveWindowSize(1920, 1080);

        final size = service.savedWindowSize;
        expect(size, isNotNull);
        expect(size!.width, 1920);
        expect(size.height, 1080);
      });

      test('savedWindowSize loads from disk', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 1280,
          'window.height': 720,
        }));

        await service.load();

        final size = service.savedWindowSize;
        expect(size, isNotNull);
        expect(size!.width, 1280);
        expect(size.height, 720);
      });

      test('savedWindowSize returns null for invalid values', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 'invalid',
          'window.height': 720,
        }));

        await service.load();
        expect(service.savedWindowSize, isNull);
      });

      test('savedWindowSize returns null for zero dimensions', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 0,
          'window.height': 720,
        }));

        await service.load();
        expect(service.savedWindowSize, isNull);
      });
    });

    group('layout tree persistence', () {
      test('savedLayoutTree returns null when not saved', () {
        expect(service.savedLayoutTree, isNull);
      });

      test('saveLayoutTree persists to disk', () async {
        final tree = {
          'id': 'root',
          'axis': 'horizontal',
          'flex': 1.0,
          'children': [
            {'id': 'leaf1', 'flex': 1.0},
            {'id': 'leaf2', 'flex': 2.0},
          ],
        };

        await service.saveLayoutTree(tree);

        final file = File(configPath);
        expect(file.existsSync(), isTrue);

        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json['layout.tree'], isNotNull);
        expect(json['layout.tree']['id'], 'root');
        expect(json['layout.tree']['axis'], 'horizontal');
      });

      test('savedLayoutTree returns saved tree', () async {
        final tree = {
          'id': 'root',
          'axis': 'horizontal',
          'flex': 1.0,
          'children': [
            {'id': 'leaf1', 'flex': 1.0},
          ],
        };

        await service.saveLayoutTree(tree);

        final saved = service.savedLayoutTree;
        expect(saved, isNotNull);
        expect(saved!['id'], 'root');
        expect(saved['axis'], 'horizontal');
        expect((saved['children'] as List).length, 1);
      });

      test('savedLayoutTree loads from disk', () async {
        final tree = {
          'id': 'root',
          'axis': 'vertical',
          'children': [
            {'id': 'left', 'flex': 1.0},
            {'id': 'right', 'flex': 3.0},
          ],
        };

        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({'layout.tree': tree}));

        await service.load();

        final saved = service.savedLayoutTree;
        expect(saved, isNotNull);
        expect(saved!['id'], 'root');
        expect(saved['axis'], 'vertical');
      });

      test('savedLayoutTree returns null for non-map value', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({'layout.tree': 'not a map'}));

        await service.load();
        expect(service.savedLayoutTree, isNull);
      });
    });

    group('migration from config.json', () {
      test('migrates window and layout keys from config source', () async {
        final migrationSource = <String, dynamic>{
          'window.width': 1920.0,
          'window.height': 1080.0,
          'layout.tree': {'id': 'root', 'axis': 'horizontal'},
          'appearance.themeMode': 'dark',
        };

        await service.load(migrationSource: migrationSource);

        // Window and layout should be migrated
        final size = service.savedWindowSize;
        expect(size, isNotNull);
        expect(size!.width, 1920);
        expect(size.height, 1080);

        final layout = service.savedLayoutTree;
        expect(layout, isNotNull);
        expect(layout!['id'], 'root');

        // The file should have been written
        final file = File(configPath);
        expect(file.existsSync(), isTrue);

        // Non-window/layout keys should NOT be migrated
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json.containsKey('appearance.themeMode'), isFalse);
      });

      test('does not migrate if window.json already exists', () async {
        // Pre-create window.json with different values
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 800,
          'window.height': 600,
        }));

        final migrationSource = <String, dynamic>{
          'window.width': 1920.0,
          'window.height': 1080.0,
        };

        await service.load(migrationSource: migrationSource);

        // Should use existing values, not migration source
        final size = service.savedWindowSize;
        expect(size, isNotNull);
        expect(size!.width, 800);
        expect(size.height, 600);
      });

      test('handles empty migration source', () async {
        await service.load(migrationSource: {});

        expect(service.savedWindowSize, isNull);
        expect(service.savedLayoutTree, isNull);
      });

      test('handles null migration source when file absent', () async {
        await service.load();

        expect(service.savedWindowSize, isNull);
        expect(service.savedLayoutTree, isNull);
        expect(service.loaded, isTrue);
      });
    });
  });
}
