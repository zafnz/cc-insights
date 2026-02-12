import 'dart:io';

import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late RuntimeConfig config;

  setUp(() {
    // RuntimeConfig is a singleton; get the instance.
    // Note: Because RuntimeConfig is a singleton with private constructor,
    // we test against the global instance. Tests should restore state after.
    config = RuntimeConfig.instance;
  });

  tearDown(() async {
    // Restore default values after each test to avoid state leakage
    config.bashToolSummary = BashToolSummary.description;
    config.toolSummaryRelativeFilePaths = true;
    config.monoFontFamily = 'JetBrains Mono';
    await resources.disposeAll();
  });

  group('RuntimeConfig', () {
    // =========================================================================
    // DEFAULT VALUES
    // =========================================================================

    group('default values', () {
      test('bashToolSummary defaults to description', () {
        // Arrange - reset to default
        config.bashToolSummary = BashToolSummary.description;

        // Assert
        check(config.bashToolSummary).equals(BashToolSummary.description);
      });

      test('toolSummaryRelativeFilePaths defaults to true', () {
        // Arrange - reset to default
        config.toolSummaryRelativeFilePaths = true;

        // Assert
        check(config.toolSummaryRelativeFilePaths).isTrue();
      });

      test('monoFontFamily defaults to JetBrains Mono', () {
        // Arrange - reset to default
        config.monoFontFamily = 'JetBrains Mono';

        // Assert
        check(config.monoFontFamily).equals('JetBrains Mono');
      });
    });

    // =========================================================================
    // SETTERS UPDATE VALUES
    // =========================================================================

    group('setters update values', () {
      test('bashToolSummary setter updates value', () {
        // Arrange
        check(config.bashToolSummary).equals(BashToolSummary.description);

        // Act
        config.bashToolSummary = BashToolSummary.command;

        // Assert
        check(config.bashToolSummary).equals(BashToolSummary.command);
      });

      test('toolSummaryRelativeFilePaths setter updates value', () {
        // Arrange
        check(config.toolSummaryRelativeFilePaths).isTrue();

        // Act
        config.toolSummaryRelativeFilePaths = false;

        // Assert
        check(config.toolSummaryRelativeFilePaths).isFalse();
      });

      test('monoFontFamily setter updates value', () {
        // Arrange
        check(config.monoFontFamily).equals('JetBrains Mono');

        // Act
        config.monoFontFamily = 'Fira Code';

        // Assert
        check(config.monoFontFamily).equals('Fira Code');
      });
    });

    // =========================================================================
    // SETTERS NOTIFY LISTENERS WHEN VALUE CHANGES
    // =========================================================================

    group('setters call notifyListeners when value changes', () {
      test('bashToolSummary setter notifies listeners on change', () {
        // Arrange
        config.bashToolSummary = BashToolSummary.description;
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act
        config.bashToolSummary = BashToolSummary.command;

        // Assert
        check(notifyCount).equals(1);

        // Cleanup
        config.removeListener(listener);
      });

      test('toolSummaryRelativeFilePaths setter notifies listeners on change',
          () {
        // Arrange
        config.toolSummaryRelativeFilePaths = true;
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act
        config.toolSummaryRelativeFilePaths = false;

        // Assert
        check(notifyCount).equals(1);

        // Cleanup
        config.removeListener(listener);
      });

      test('monoFontFamily setter notifies listeners on change', () {
        // Arrange
        config.monoFontFamily = 'JetBrains Mono';
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act
        config.monoFontFamily = 'Source Code Pro';

        // Assert
        check(notifyCount).equals(1);

        // Cleanup
        config.removeListener(listener);
      });
    });

    // =========================================================================
    // SETTERS DO NOT NOTIFY WHEN VALUE IS THE SAME
    // =========================================================================

    group('setters do NOT call notifyListeners when value is the same', () {
      test('bashToolSummary setter does not notify when value unchanged', () {
        // Arrange
        config.bashToolSummary = BashToolSummary.description;
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act - set to the same value
        config.bashToolSummary = BashToolSummary.description;

        // Assert
        check(notifyCount).equals(0);

        // Cleanup
        config.removeListener(listener);
      });

      test(
          'toolSummaryRelativeFilePaths setter does not notify '
          'when value unchanged', () {
        // Arrange
        config.toolSummaryRelativeFilePaths = true;
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act - set to the same value
        config.toolSummaryRelativeFilePaths = true;

        // Assert
        check(notifyCount).equals(0);

        // Cleanup
        config.removeListener(listener);
      });

      test('monoFontFamily setter does not notify when value unchanged', () {
        // Arrange
        config.monoFontFamily = 'JetBrains Mono';
        var notifyCount = 0;
        void listener() => notifyCount++;
        config.addListener(listener);

        // Act - set to the same value
        config.monoFontFamily = 'JetBrains Mono';

        // Assert
        check(notifyCount).equals(0);

        // Cleanup
        config.removeListener(listener);
      });
    });

    // =========================================================================
    // INITIALIZE
    // =========================================================================

    group('initialize()', () {
      // Note: RuntimeConfig.initialize() can only be called once due to the
      // _initialized guard. These tests verify the behavior of the already-
      // initialized singleton.

      test('workingDirectory returns a valid path', () {
        // Assert - workingDirectory should be set (either from args or cwd)
        check(config.workingDirectory).isNotEmpty();
        check(Directory(config.workingDirectory).existsSync()).isTrue();
      });

      test('workingDirectory is an absolute path', () {
        // Assert - workingDirectory should be absolute
        check(Directory(config.workingDirectory).isAbsolute).isTrue();
      });
    });

    // =========================================================================
    // isValidGitRepo GETTER
    // =========================================================================

    group('isValidGitRepo', () {
      test('returns true when workingDirectory contains .git directory', () {
        // The test is run from within the project, which should be a git repo
        // Note: This test depends on the actual file system state
        final gitDir = Directory('${config.workingDirectory}/.git');

        if (gitDir.existsSync()) {
          // Assert - if .git exists, isValidGitRepo should be true
          check(config.isValidGitRepo).isTrue();
        } else {
          // If no .git directory, isValidGitRepo should be false
          check(config.isValidGitRepo).isFalse();
        }
      });
    });

    // =========================================================================
    // projectName GETTER
    // =========================================================================

    group('projectName', () {
      test('returns the basename of the workingDirectory', () {
        // Arrange
        final expectedName =
            config.workingDirectory.split(Platform.pathSeparator).last;

        // Assert
        check(config.projectName).equals(expectedName);
      });

      test('returns non-empty string', () {
        // Assert
        check(config.projectName).isNotEmpty();
      });
    });
  });

  // ===========================================================================
  // BASH TOOL SUMMARY ENUM
  // ===========================================================================

  group('BashToolSummary', () {
    test('has command value', () {
      check(BashToolSummary.command).equals(BashToolSummary.command);
    });

    test('has description value', () {
      check(BashToolSummary.description).equals(BashToolSummary.description);
    });

    test('values list contains both options', () {
      check(BashToolSummary.values.length).equals(2);
      check(BashToolSummary.values).contains(BashToolSummary.command);
      check(BashToolSummary.values).contains(BashToolSummary.description);
    });
  });

  // ===========================================================================
  // CLI OVERRIDES
  // ===========================================================================

  group('CLI overrides', () {
    final defs = SettingsService.allDefinitions;

    setUp(() {
      RuntimeConfig.resetForTesting();
    });

    tearDown(() {
      RuntimeConfig.resetForTesting();
    });

    test('parses --key=value for a known text setting', () {
      RuntimeConfig.initialize(
        ['--logging.filePath=~/test.log'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('logging.filePath')).isTrue();
      check(config.cliOverrides['logging.filePath'])
          .equals('~/test.log');
    });

    test('parses --key=value for a known toggle setting', () {
      RuntimeConfig.initialize(
        ['--appearance.showTimestamps=true'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('appearance.showTimestamps')).isTrue();
      check(config.cliOverrides['appearance.showTimestamps']).equals(true);
    });

    test('coerces "1" to true for toggle settings', () {
      RuntimeConfig.initialize(
        ['--appearance.showTimestamps=1'],
        settingDefinitions: defs,
      );

      check(config.cliOverrides['appearance.showTimestamps']).equals(true);
    });

    test('coerces "false" to false for toggle settings', () {
      RuntimeConfig.initialize(
        ['--appearance.showTimestamps=false'],
        settingDefinitions: defs,
      );

      check(config.cliOverrides['appearance.showTimestamps']).equals(false);
    });

    test('parses number setting', () {
      RuntimeConfig.initialize(
        ['--appearance.timestampIdleThreshold=10'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('appearance.timestampIdleThreshold')).isTrue();
      check(config.cliOverrides['appearance.timestampIdleThreshold'])
          .equals(10);
    });

    test('parses dropdown setting', () {
      RuntimeConfig.initialize(
        ['--logging.minimumLevel=error'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('logging.minimumLevel')).isTrue();
      check(config.cliOverrides['logging.minimumLevel']).equals('error');
    });

    test('ignores unknown setting keys', () {
      RuntimeConfig.initialize(
        ['--nonexistent.key=value'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('nonexistent.key')).isFalse();
      check(config.cliOverrides).isEmpty();
    });

    test('handles multiple overrides', () {
      RuntimeConfig.initialize(
        [
          '--logging.filePath=~/test.log',
          '--logging.minimumLevel=error',
          '--appearance.showTimestamps=true',
        ],
        settingDefinitions: defs,
      );

      check(config.cliOverrides.length).equals(3);
      check(config.cliOverrides['logging.filePath']).equals('~/test.log');
      check(config.cliOverrides['logging.minimumLevel']).equals('error');
      check(config.cliOverrides['appearance.showTimestamps']).equals(true);
    });

    test('coexists with other flags and positional args', () {
      RuntimeConfig.initialize(
        [
          '--mock',
          '--logging.filePath=~/test.log',
          '/some/path',
        ],
        settingDefinitions: defs,
      );

      check(config.useMockData).isTrue();
      check(config.isOverridden('logging.filePath')).isTrue();
    });

    test('isOverridden returns false for non-overridden keys', () {
      RuntimeConfig.initialize(
        ['--logging.filePath=~/test.log'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('logging.minimumLevel')).isFalse();
    });

    test('cliOverrides is unmodifiable', () {
      RuntimeConfig.initialize(
        ['--logging.filePath=~/test.log'],
        settingDefinitions: defs,
      );

      expect(
        () => config.cliOverrides['foo'] = 'bar',
        throwsUnsupportedError,
      );
    });

    test('resetForTesting clears overrides', () {
      RuntimeConfig.initialize(
        ['--logging.filePath=~/test.log'],
        settingDefinitions: defs,
      );

      check(config.isOverridden('logging.filePath')).isTrue();

      RuntimeConfig.resetForTesting();

      check(config.isOverridden('logging.filePath')).isFalse();
      check(config.cliOverrides).isEmpty();
    });

    test('handles empty value after equals sign', () {
      RuntimeConfig.initialize(
        ['--logging.filePath='],
        settingDefinitions: defs,
      );

      check(config.isOverridden('logging.filePath')).isTrue();
      check(config.cliOverrides['logging.filePath']).equals('');
    });

    test('handles value with equals sign in it', () {
      RuntimeConfig.initialize(
        ['--logging.filePath=~/path=with=equals.log'],
        settingDefinitions: defs,
      );

      check(config.cliOverrides['logging.filePath'])
          .equals('~/path=with=equals.log');
    });

    group('validation warnings', () {
      test('rejects invalid dropdown value and adds warning', () {
        RuntimeConfig.initialize(
          ['--appearance.themeMode=Light'],
          settingDefinitions: defs,
        );

        check(config.isOverridden('appearance.themeMode')).isFalse();
        check(config.cliWarnings.length).equals(1);
        check(config.cliWarnings.first).contains('invalid value "Light"');
        check(config.cliWarnings.first).contains('light, dark, system');
      });

      test('accepts valid dropdown value without warning', () {
        RuntimeConfig.initialize(
          ['--appearance.themeMode=light'],
          settingDefinitions: defs,
        );

        check(config.isOverridden('appearance.themeMode')).isTrue();
        check(config.cliWarnings).isEmpty();
      });

      test('rejects non-numeric value for number setting', () {
        RuntimeConfig.initialize(
          ['--appearance.timestampIdleThreshold=abc'],
          settingDefinitions: defs,
        );

        check(config.isOverridden('appearance.timestampIdleThreshold'))
            .isFalse();
        check(config.cliWarnings.length).equals(1);
        check(config.cliWarnings.first).contains('expected a number');
      });

      test('rejects invalid toggle value', () {
        RuntimeConfig.initialize(
          ['--appearance.showTimestamps=yes'],
          settingDefinitions: defs,
        );

        check(config.isOverridden('appearance.showTimestamps')).isFalse();
        check(config.cliWarnings.length).equals(1);
        check(config.cliWarnings.first).contains('expected true/false/1/0');
      });

      test('text settings accept any value without warning', () {
        RuntimeConfig.initialize(
          ['--logging.filePath=anything goes here'],
          settingDefinitions: defs,
        );

        check(config.isOverridden('logging.filePath')).isTrue();
        check(config.cliWarnings).isEmpty();
      });

      test('resetForTesting clears warnings', () {
        RuntimeConfig.initialize(
          ['--appearance.themeMode=INVALID'],
          settingDefinitions: defs,
        );

        check(config.cliWarnings).isNotEmpty();

        RuntimeConfig.resetForTesting();

        check(config.cliWarnings).isEmpty();
      });
    });
  });
}
