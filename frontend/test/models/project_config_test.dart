import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/models/user_action.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectConfig', () {
    group('constructor', () {
      test('creates with defaults', () {
        // Arrange & Act
        const config = ProjectConfig();

        // Assert
        check(config.actions).isEmpty();
        check(config.userActions).isNull();
        check(config.defaultBase).isNull();
      });

      test('creates with all fields', () {
        // Arrange & Act
        const config = ProjectConfig(
          actions: {'worktree-post-create': 'npm install'},
          userActions: [CommandAction(name: 'Test', command: './test.sh')],
          defaultBase: 'origin/main',
        );

        // Assert
        check(
          config.actions,
        ).deepEquals({'worktree-post-create': 'npm install'});
        check(config.userActions).isNotNull().deepEquals([
          const CommandAction(name: 'Test', command: './test.sh'),
        ]);
        check(config.defaultBase).isNotNull().equals('origin/main');
      });
    });

    group('ProjectConfig.empty()', () {
      test('creates with null defaults', () {
        // Arrange & Act
        const config = ProjectConfig.empty();

        // Assert
        check(config.actions).isEmpty();
        check(config.userActions).isNull();
        check(config.defaultBase).isNull();
      });
    });

    group('copyWith()', () {
      test('updates defaultBase while preserving other fields', () {
        // Arrange
        const original = ProjectConfig(
          actions: {'worktree-post-create': 'npm install'},
          userActions: [CommandAction(name: 'Test', command: './test.sh')],
        );

        // Act
        final modified = original.copyWith(defaultBase: 'main');

        // Assert
        check(modified.defaultBase).isNotNull().equals('main');
        check(modified.actions).deepEquals(original.actions);
        check(
          modified.userActions,
        ).isNotNull().deepEquals(original.userActions!);
      });

      test('preserves defaultBase when not specified', () {
        // Arrange
        const original = ProjectConfig(defaultBase: 'origin/main');

        // Act
        final modified = original.copyWith(actions: {'hook': 'cmd'});

        // Assert
        check(modified.defaultBase).isNotNull().equals('origin/main');
        check(modified.actions).deepEquals({'hook': 'cmd'});
      });

      test('clears defaultBase with clearDefaultBase flag', () {
        // Arrange
        const original = ProjectConfig(defaultBase: 'main');

        // Act
        final modified = original.copyWith(clearDefaultBase: true);

        // Assert
        check(modified.defaultBase).isNull();
      });

      test('clearDefaultBase takes precedence over defaultBase value', () {
        // Arrange
        const original = ProjectConfig(defaultBase: 'main');

        // Act
        final modified = original.copyWith(
          defaultBase: 'develop',
          clearDefaultBase: true,
        );

        // Assert
        check(modified.defaultBase).isNull();
      });

      test('preserves all fields when no arguments', () {
        // Arrange
        const original = ProjectConfig(
          actions: {'hook': 'cmd'},
          userActions: [CommandAction(name: 'Test', command: './test.sh')],
          defaultBase: 'auto',
        );

        // Act
        final modified = original.copyWith();

        // Assert
        check(modified).equals(original);
      });
    });

    group('toJson()', () {
      test('omits defaultBase when null', () {
        // Arrange
        const config = ProjectConfig();

        // Act
        final json = config.toJson();

        // Assert
        check(json.containsKey('default-base')).isFalse();
      });

      test('includes defaultBase when set', () {
        // Arrange
        const config = ProjectConfig(defaultBase: 'origin/main');

        // Act
        final json = config.toJson();

        // Assert
        check(json['default-base']).equals('origin/main');
      });

      test('includes all fields when populated', () {
        // Arrange
        const config = ProjectConfig(
          actions: {'worktree-post-create': 'npm install'},
          userActions: [CommandAction(name: 'Test', command: './test.sh')],
          defaultBase: 'main',
        );

        // Act
        final json = config.toJson();

        // Assert
        check(
          json['actions'] as Map,
        ).deepEquals({'worktree-post-create': 'npm install'});
        check(json['user-actions'] as Map).deepEquals({'Test': './test.sh'});
        check(json['default-base']).equals('main');
      });

      test('serializes start-chat macros as typed objects', () {
        const config = ProjectConfig(
          userActions: [
            StartChatMacro(
              name: 'Codex Review',
              agentId: 'codex-default',
              model: 'o3-mini',
              instruction: 'Review this branch',
            ),
          ],
        );

        final json = config.toJson();

        check(json['user-actions'] as Map).deepEquals({
          'Codex Review': {
            'type': 'start-chat',
            'agent-id': 'codex-default',
            'model': 'o3-mini',
            'instruction': 'Review this branch',
          },
        });
      });

      test('serializes empty command using typed command object', () {
        const config = ProjectConfig(
          userActions: [CommandAction(name: 'Empty', command: '')],
        );

        final json = config.toJson();

        check(json['user-actions'] as Map).deepEquals({
          'Empty': {'type': 'command', 'command': ''},
        });
      });

      test('empty config produces empty JSON', () {
        // Arrange
        const config = ProjectConfig.empty();

        // Act
        final json = config.toJson();

        // Assert
        check(json).isEmpty();
      });
    });

    group('fromJson()', () {
      test('parses defaultBase from JSON', () {
        // Arrange
        final json = <String, dynamic>{'default-base': 'origin/main'};

        // Act
        final config = ProjectConfig.fromJson(json);

        // Assert
        check(config.defaultBase).isNotNull().equals('origin/main');
      });

      test('handles missing defaultBase as null', () {
        // Arrange
        final json = <String, dynamic>{
          'actions': {'hook': 'cmd'},
        };

        // Act
        final config = ProjectConfig.fromJson(json);

        // Assert
        check(config.defaultBase).isNull();
      });

      test('handles non-string defaultBase as null', () {
        // Arrange
        final json = <String, dynamic>{'default-base': 42};

        // Act
        final config = ProjectConfig.fromJson(json);

        // Assert
        check(config.defaultBase).isNull();
      });

      test('parses all fields from JSON', () {
        // Arrange
        final json = <String, dynamic>{
          'actions': {'worktree-post-create': 'npm install'},
          'user-actions': {'Test': './test.sh'},
          'default-base': 'auto',
        };

        // Act
        final config = ProjectConfig.fromJson(json);

        // Assert
        check(
          config.actions,
        ).deepEquals({'worktree-post-create': 'npm install'});
        check(config.userActions).isNotNull().deepEquals([
          const CommandAction(name: 'Test', command: './test.sh'),
        ]);
        check(config.defaultBase).isNotNull().equals('auto');
      });

      test('parses start-chat macro objects from JSON', () {
        final json = <String, dynamic>{
          'user-actions': {
            'Codex Review': {
              'type': 'start-chat',
              'agent-id': 'codex-default',
              'model': 'o3-mini',
              'instruction': 'Review this branch',
            },
          },
        };

        final config = ProjectConfig.fromJson(json);

        check(config.userActions).isNotNull().deepEquals(const [
          StartChatMacro(
            name: 'Codex Review',
            agentId: 'codex-default',
            model: 'o3-mini',
            instruction: 'Review this branch',
          ),
        ]);
      });

      test('parses empty JSON as empty config', () {
        // Arrange
        final json = <String, dynamic>{};

        // Act
        final config = ProjectConfig.fromJson(json);

        // Assert
        check(config.actions).isEmpty();
        check(config.userActions).isNull();
        check(config.defaultBase).isNull();
      });
    });

    group('toJson/fromJson round-trip', () {
      test('round-trips config with defaultBase', () {
        // Arrange
        const original = ProjectConfig(
          actions: {'worktree-post-create': 'npm install'},
          userActions: [CommandAction(name: 'Build', command: 'make build')],
          defaultBase: 'origin/main',
        );

        // Act
        final json = original.toJson();
        final restored = ProjectConfig.fromJson(json);

        // Assert
        check(restored).equals(original);
      });

      test('round-trips config without defaultBase', () {
        // Arrange
        const original = ProjectConfig(
          actions: {'hook': 'cmd'},
          userActions: [CommandAction(name: 'Test', command: './test.sh')],
        );

        // Act
        final json = original.toJson();
        final restored = ProjectConfig.fromJson(json);

        // Assert
        check(restored).equals(original);
      });

      test('round-trips empty config', () {
        // Arrange
        const original = ProjectConfig.empty();

        // Act
        final json = original.toJson();
        final restored = ProjectConfig.fromJson(json);

        // Assert
        check(restored).equals(original);
      });

      test('round-trips config with only defaultBase', () {
        // Arrange
        const original = ProjectConfig(defaultBase: 'develop');

        // Act
        final json = original.toJson();
        final restored = ProjectConfig.fromJson(json);

        // Assert
        check(restored).equals(original);
        check(restored.defaultBase).isNotNull().equals('develop');
      });
    });

    group('equality', () {
      test('equal when both have same defaultBase', () {
        // Arrange
        const config1 = ProjectConfig(defaultBase: 'main');
        const config2 = ProjectConfig(defaultBase: 'main');

        // Act & Assert
        check(config1 == config2).isTrue();
        check(config1.hashCode).equals(config2.hashCode);
      });

      test('equal when both have null defaultBase', () {
        // Arrange
        const config1 = ProjectConfig();
        const config2 = ProjectConfig();

        // Act & Assert
        check(config1 == config2).isTrue();
        check(config1.hashCode).equals(config2.hashCode);
      });

      test('not equal when defaultBase differs', () {
        // Arrange
        const config1 = ProjectConfig(defaultBase: 'main');
        const config2 = ProjectConfig(defaultBase: 'develop');

        // Act & Assert
        check(config1 == config2).isFalse();
      });

      test('not equal when one has defaultBase and other is null', () {
        // Arrange
        const config1 = ProjectConfig(defaultBase: 'main');
        const config2 = ProjectConfig();

        // Act & Assert
        check(config1 == config2).isFalse();
      });
    });

    group('toString()', () {
      test('includes defaultBase', () {
        // Arrange
        const config = ProjectConfig(defaultBase: 'origin/main');

        // Act
        final str = config.toString();

        // Assert
        check(str).contains('defaultBase: origin/main');
      });

      test('includes null defaultBase', () {
        // Arrange
        const config = ProjectConfig();

        // Act
        final str = config.toString();

        // Assert
        check(str).contains('defaultBase: null');
      });
    });
  });

  group('copyWith patterns used by updateDefaultBase', () {
    test('sets defaultBase via copyWith', () async {
      // Arrange: start with a config that has no defaultBase
      const initial = ProjectConfig(actions: {'hook': 'cmd'});

      // Act: simulate what updateDefaultBase does
      final updated = initial.copyWith(defaultBase: 'origin/main');

      // Assert
      check(updated.defaultBase).isNotNull().equals('origin/main');
      check(updated.actions).deepEquals(initial.actions);
    });

    test('clears defaultBase via copyWith', () async {
      // Arrange: start with a config that has a defaultBase
      const initial = ProjectConfig(defaultBase: 'main');

      // Act: simulate clearing (value == null path)
      final updated = initial.copyWith(clearDefaultBase: true);

      // Assert
      check(updated.defaultBase).isNull();
    });
  });
}
