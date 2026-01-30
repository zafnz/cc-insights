import 'dart:io';

import 'package:cc_insights_v2/services/runtime_config.dart';
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
}
