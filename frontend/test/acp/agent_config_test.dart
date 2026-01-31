import 'package:cc_insights_v2/acp/acp_client_wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentConfig serialization', () {
    test('toJson serializes all fields', () {
      // Arrange
      const config = AgentConfig(
        id: 'test-agent',
        name: 'Test Agent',
        command: '/usr/bin/agent',
        args: ['--acp'],
        env: {'API_KEY': 'secret'},
      );

      // Act
      final json = config.toJson();

      // Assert
      expect(json['id'], equals('test-agent'));
      expect(json['name'], equals('Test Agent'));
      expect(json['command'], equals('/usr/bin/agent'));
      expect(json['args'], equals(['--acp']));
      expect(json['env'], equals({'API_KEY': 'secret'}));
    });

    test('fromJson deserializes correctly', () {
      // Arrange
      final json = {
        'id': 'test-agent',
        'name': 'Test Agent',
        'command': '/usr/bin/agent',
        'args': ['--acp'],
        'env': {'API_KEY': 'secret'},
      };

      // Act
      final config = AgentConfig.fromJson(json);

      // Assert
      expect(config.id, equals('test-agent'));
      expect(config.name, equals('Test Agent'));
      expect(config.command, equals('/usr/bin/agent'));
      expect(config.args, equals(['--acp']));
      expect(config.env, equals({'API_KEY': 'secret'}));
    });

    test('fromJson handles missing optional fields', () {
      // Arrange
      final json = {
        'id': 'test',
        'name': 'Test',
        'command': '/test',
      };

      // Act
      final config = AgentConfig.fromJson(json);

      // Assert
      expect(config.args, isEmpty);
      expect(config.env, isEmpty);
    });

    test('roundtrip toJson/fromJson preserves data', () {
      // Arrange
      const original = AgentConfig(
        id: 'roundtrip',
        name: 'Roundtrip Test',
        command: '/path/to/agent',
        args: ['--arg1', '--arg2'],
        env: {'KEY1': 'value1', 'KEY2': 'value2'},
      );

      // Act
      final roundtripped = AgentConfig.fromJson(original.toJson());

      // Assert
      expect(roundtripped, equals(original));
    });

    test('equality works correctly', () {
      // Arrange
      const config1 = AgentConfig(id: 'a', name: 'A', command: '/a');
      const config2 = AgentConfig(id: 'a', name: 'A', command: '/a');

      // Assert
      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
    });

    test('inequality detected for different values', () {
      // Arrange
      const config1 = AgentConfig(id: 'a', name: 'A', command: '/a');
      const config2 = AgentConfig(id: 'b', name: 'A', command: '/a');

      // Assert
      expect(config1, isNot(equals(config2)));
    });
  });
}
