import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late String configPath;
  late SettingsService service;

  setUp(() {
    RuntimeConfig.resetForTesting();
    RuntimeConfig.initialize([]);
    tempDir = Directory.systemTemp.createTempSync('settings_test_');
    configPath = '${tempDir.path}/config.json';
    service = SettingsService(configPath: configPath);
  });

  tearDown(() {
    service.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SettingsService', () {
    group('categories', () {
      test('has all expected categories', () {
        final ids = SettingsService.categories.map((c) => c.id).toList();
        expect(ids, ['appearance', 'behavior', 'tags', 'session', 'logging', 'developer']);
      });

      test('each category has at least one setting', () {
        // The 'tags' category uses a custom UI editor, not standard settings.
        final standardCategories = SettingsService.categories
            .where((c) => c.id != 'tags');
        for (final category in standardCategories) {
          expect(
            category.settings.isNotEmpty,
            isTrue,
            reason: '${category.id} should have settings',
          );
        }
      });

      test('all setting keys are unique', () {
        final keys = <String>{};
        for (final category in SettingsService.categories) {
          for (final setting in category.settings) {
            expect(
              keys.add(setting.key),
              isTrue,
              reason: 'Duplicate key: ${setting.key}',
            );
          }
        }
      });
    });

    group('getValue', () {
      test('returns default value for unset key', () {
        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
      });

      test('returns default bool for toggle', () {
        expect(
          service.getValue<bool>('appearance.relativeFilePaths'),
          true,
        );
      });

      test('returns default int for number', () {
        expect(
          service.getValue<int>('appearance.timestampIdleThreshold'),
          5,
        );
      });

      test('throws for unknown key', () {
        expect(
          () => service.getValue<String>('nonexistent.key'),
          throwsArgumentError,
        );
      });
    });

    group('setValue', () {
      test('updates value and notifies listeners', () async {
        var notified = false;
        service.addListener(() => notified = true);

        await service.setValue('appearance.bashToolSummary', 'command');

        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'command',
        );
        expect(notified, isTrue);
      });

      test('persists to disk', () async {
        await service.setValue('appearance.relativeFilePaths', false);

        final file = File(configPath);
        expect(file.existsSync(), isTrue);

        final json = jsonDecode(file.readAsStringSync())
            as Map<String, dynamic>;
        expect(json['appearance.relativeFilePaths'], false);
      });

      test('syncs to RuntimeConfig for bashToolSummary', () async {
        await service.setValue('appearance.bashToolSummary', 'command');
        expect(
          RuntimeConfig.instance.bashToolSummary,
          BashToolSummary.command,
        );
      });

      test('syncs to RuntimeConfig for relativeFilePaths', () async {
        await service.setValue('appearance.relativeFilePaths', false);
        expect(
          RuntimeConfig.instance.toolSummaryRelativeFilePaths,
          false,
        );
      });

      test('syncs to RuntimeConfig for showTimestamps', () async {
        await service.setValue('appearance.showTimestamps', true);
        expect(RuntimeConfig.instance.showTimestamps, true);
      });

      test('syncs to RuntimeConfig for showRawMessages', () async {
        await service.setValue('developer.showRawMessages', false);
        expect(RuntimeConfig.instance.showRawMessages, false);
      });
    });

    group('load', () {
      test('loads values from disk', () async {
        // Write a config file first
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.bashToolSummary': 'command',
          'appearance.showTimestamps': true,
        }));

        await service.load();

        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'command',
        );
        expect(service.getValue<bool>('appearance.showTimestamps'), true);
        expect(service.loaded, isTrue);
      });

      test('handles missing file gracefully', () async {
        await service.load();
        expect(service.loaded, isTrue);
        // Should still return defaults
        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
      });

      test('handles corrupt file gracefully', () async {
        final file = File(configPath);
        file.writeAsStringSync('not valid json {{{');

        await service.load();
        expect(service.loaded, isTrue);
        // Should fall back to defaults
        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
      });

      test('syncs all values to RuntimeConfig after load', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.bashToolSummary': 'command',
          'appearance.relativeFilePaths': false,
        }));

        await service.load();

        expect(
          RuntimeConfig.instance.bashToolSummary,
          BashToolSummary.command,
        );
        expect(
          RuntimeConfig.instance.toolSummaryRelativeFilePaths,
          false,
        );
      });
    });

    group('resetToDefaults', () {
      test('clears all values', () async {
        await service.setValue('appearance.bashToolSummary', 'command');
        await service.setValue('appearance.relativeFilePaths', false);

        await service.resetToDefaults();

        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'description',
        );
        expect(
          service.getValue<bool>('appearance.relativeFilePaths'),
          true,
        );
      });

      test('syncs defaults to RuntimeConfig', () async {
        await service.setValue('appearance.bashToolSummary', 'command');
        await service.resetToDefaults();

        expect(
          RuntimeConfig.instance.bashToolSummary,
          BashToolSummary.description,
        );
      });

      test('persists empty state to disk', () async {
        await service.setValue('appearance.bashToolSummary', 'command');
        await service.resetToDefaults();

        final file = File(configPath);
        expect(file.existsSync(), isTrue);

        final json = jsonDecode(file.readAsStringSync())
            as Map<String, dynamic>;
        expect(json, isEmpty);
      });

      test('notifies listeners', () async {
        var notified = false;
        service.addListener(() => notified = true);

        await service.resetToDefaults();

        expect(notified, isTrue);
      });
    });

    group('findDefinition', () {
      test('finds existing definition', () {
        final def = SettingsService.findDefinition(
          'appearance.bashToolSummary',
        );
        expect(def, isNotNull);
        expect(def!.title, 'Bash Tool Summary');
      });

      test('returns null for unknown key', () {
        final def = SettingsService.findDefinition('nonexistent');
        expect(def, isNull);
      });
    });
  });
}
