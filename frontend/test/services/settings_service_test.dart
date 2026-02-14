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
        expect(ids, ['appearance', 'behavior', 'tags', 'agents', 'session', 'logging', 'developer', 'projectMgmt']);
      });

      test('each category has at least one setting', () {
        // Tags and agents categories use custom UI editors, not standard settings.
        final standardCategories = SettingsService.categories
            .where((c) => c.id != 'tags' && c.id != 'agents');
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

      test('returns default true for agentTicketTools', () {
        expect(
          service.getValue<bool>('projectMgmt.agentTicketTools'),
          true,
        );
      });

      test('syncs to RuntimeConfig for agentTicketTools', () async {
        await service.setValue('projectMgmt.agentTicketTools', false);
        expect(RuntimeConfig.instance.agentTicketToolsEnabled, false);
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

    group('legacy window/layout key removal', () {
      test('removeLegacyWindowLayoutKeys removes window and layout keys',
          () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 1920,
          'window.height': 1080,
          'layout.tree': {'id': 'root'},
          'appearance.themeMode': 'dark',
        }));

        await service.load();
        await service.removeLegacyWindowLayoutKeys();

        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json.containsKey('window.width'), isFalse);
        expect(json.containsKey('window.height'), isFalse);
        expect(json.containsKey('layout.tree'), isFalse);
        expect(json['appearance.themeMode'], 'dark');
      });

      test('removeLegacyWindowLayoutKeys is no-op when keys absent', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.themeMode': 'dark',
        }));

        await service.load();
        await service.removeLegacyWindowLayoutKeys();

        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(json['appearance.themeMode'], 'dark');
      });

      test('valuesSnapshot exposes current values', () async {
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'window.width': 1920,
          'window.height': 1080,
          'appearance.themeMode': 'dark',
        }));

        await service.load();

        final snapshot = service.valuesSnapshot;
        expect(snapshot['window.width'], 1920);
        expect(snapshot['window.height'], 1080);
        expect(snapshot['appearance.themeMode'], 'dark');
      });
    });

    group('file watcher', () {
      test('reloads values when file is changed externally', () async {
        await service.load();

        // Set an initial value so the file exists
        await service.setValue('appearance.showTimestamps', false);
        // Wait for the self-write guard to clear (guard is 1000ms)
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        // Simulate an external edit
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.showTimestamps': true,
          'appearance.bashToolSummary': 'command',
        }));

        // Give the file watcher time to fire
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(service.getValue<bool>('appearance.showTimestamps'), true);
        expect(
          service.getValue<String>('appearance.bashToolSummary'),
          'command',
        );
      });

      test('syncs RuntimeConfig on external change', () async {
        await service.load();
        // Wait for self-write guard from load's _startWatching
        await Future<void>.delayed(const Duration(milliseconds: 200));

        // External edit
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.bashToolSummary': 'command',
        }));

        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(
          RuntimeConfig.instance.bashToolSummary,
          BashToolSummary.command,
        );
      });

      test('notifies listeners on external change', () async {
        await service.load();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        var notifyCount = 0;
        service.addListener(() => notifyCount++);

        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.showTimestamps': true,
        }));

        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(notifyCount, greaterThan(0));
      });

      test('does not reload during self-write', () async {
        await service.load();

        // Set a value — this triggers _save with _selfWriting = true
        await service.setValue('appearance.showTimestamps', true);

        // Immediately check — should still be our value, not reverted
        expect(service.getValue<bool>('appearance.showTimestamps'), true);
      });

      test('cleans up watcher on dispose', () async {
        // Create a separate service for this test so we can dispose
        // it without conflicting with tearDown.
        final extraService = SettingsService(configPath: configPath);
        await extraService.load();
        // Dispose should cancel the subscription without error
        extraService.dispose();

        // Writing after dispose should not cause issues
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.showTimestamps': true,
        }));

        await Future<void>.delayed(const Duration(milliseconds: 300));
        // No assertion needed — just verify no crash
      });
    });

    group('CLI overrides', () {
      test('isOverridden delegates to RuntimeConfig', () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--logging.filePath=~/override.log'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        expect(service.isOverridden('logging.filePath'), isTrue);
        expect(service.isOverridden('logging.minimumLevel'), isFalse);
      });

      test('getEffectiveValue returns override when present', () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--logging.filePath=~/override.log'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        // Set a different value in config
        await service.setValue('logging.filePath', '~/config.log');

        // getEffectiveValue should return the CLI override
        expect(
          service.getEffectiveValue<String>('logging.filePath'),
          '~/override.log',
        );

        // getValue should return the config value
        expect(
          service.getValue<String>('logging.filePath'),
          '~/config.log',
        );
      });

      test('getEffectiveValue returns config value when not overridden',
          () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          [],
          settingDefinitions: SettingsService.allDefinitions,
        );

        await service.setValue('logging.filePath', '~/config.log');

        expect(
          service.getEffectiveValue<String>('logging.filePath'),
          '~/config.log',
        );
      });

      test('syncToRuntimeConfig skips overridden keys', () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--logging.filePath=~/override.log'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        // Load config with a different logging.filePath
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'logging.filePath': '~/config.log',
        }));

        await service.load();

        // RuntimeConfig should have the CLI override, not the config value
        expect(
          RuntimeConfig.instance.loggingFilePath,
          '~/override.log',
        );
      });

      test('setValue on overridden key persists to _values but does not '
          'sync to RuntimeConfig', () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--logging.filePath=~/override.log'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        await service.load();

        // Set the value through the normal API
        await service.setValue('logging.filePath', '~/user-value.log');

        // getValue returns the user-set value (for persistence)
        expect(
          service.getValue<String>('logging.filePath'),
          '~/user-value.log',
        );

        // RuntimeConfig still has the CLI override
        expect(
          RuntimeConfig.instance.loggingFilePath,
          '~/override.log',
        );

        // The persisted file should have the user value, not the override
        final file = File(configPath);
        final json = jsonDecode(file.readAsStringSync())
            as Map<String, dynamic>;
        expect(json['logging.filePath'], '~/user-value.log');
      });

      test('_save does not include CLI override values', () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--logging.filePath=~/override.log'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        // Set a non-overridden value and save
        await service.setValue('appearance.showTimestamps', true);

        final file = File(configPath);
        final json = jsonDecode(file.readAsStringSync())
            as Map<String, dynamic>;

        // The override key should not appear in the saved file
        // (unless the user explicitly set it)
        expect(json.containsKey('logging.filePath'), isFalse);
        expect(json['appearance.showTimestamps'], isTrue);
      });

      test('syncAllToRuntimeConfig applies overrides over config values',
          () async {
        RuntimeConfig.resetForTesting();
        RuntimeConfig.initialize(
          ['--appearance.showTimestamps=true'],
          settingDefinitions: SettingsService.allDefinitions,
        );

        // Config file has showTimestamps = false
        final file = File(configPath);
        file.writeAsStringSync(jsonEncode({
          'appearance.showTimestamps': false,
        }));

        await service.load();

        // RuntimeConfig should have the CLI override value
        expect(RuntimeConfig.instance.showTimestamps, isTrue);
      });

      test('allDefinitions returns all setting definitions', () {
        final defs = SettingsService.allDefinitions;
        expect(defs, isNotEmpty);

        // Should contain settings from multiple categories
        final keys = defs.map((d) => d.key).toSet();
        expect(keys.contains('logging.filePath'), isTrue);
        expect(keys.contains('appearance.themeMode'), isTrue);
        expect(keys.contains('developer.debugSdkLogging'), isTrue);
      });
    });

  });
}
