import 'package:cc_insights_v2/models/setting_definition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingDefinition', () {
    test('toggle setting has correct properties', () {
      const def = SettingDefinition(
        key: 'test.toggle',
        title: 'Test Toggle',
        description: 'A test toggle setting',
        type: SettingType.toggle,
        defaultValue: true,
      );

      expect(def.key, 'test.toggle');
      expect(def.title, 'Test Toggle');
      expect(def.type, SettingType.toggle);
      expect(def.defaultValue, true);
      expect(def.options, isNull);
      expect(def.min, isNull);
      expect(def.max, isNull);
    });

    test('dropdown setting has options', () {
      const def = SettingDefinition(
        key: 'test.dropdown',
        title: 'Test Dropdown',
        description: 'A test dropdown',
        type: SettingType.dropdown,
        defaultValue: 'a',
        options: [
          SettingOption(value: 'a', label: 'Option A'),
          SettingOption(value: 'b', label: 'Option B'),
        ],
      );

      expect(def.options, hasLength(2));
      expect(def.options![0].value, 'a');
      expect(def.options![0].label, 'Option A');
      expect(def.defaultValue, 'a');
    });

    test('number setting has min and max', () {
      const def = SettingDefinition(
        key: 'test.number',
        title: 'Test Number',
        description: 'A test number',
        type: SettingType.number,
        defaultValue: 5,
        min: 0,
        max: 60,
      );

      expect(def.min, 0);
      expect(def.max, 60);
      expect(def.defaultValue, 5);
    });
  });

  group('SettingCategory', () {
    test('holds settings list', () {
      const category = SettingCategory(
        id: 'test',
        label: 'Test',
        description: 'Test category',
        icon: Icons.settings,
        settings: [
          SettingDefinition(
            key: 'test.a',
            title: 'A',
            description: 'Setting A',
            type: SettingType.toggle,
            defaultValue: false,
          ),
          SettingDefinition(
            key: 'test.b',
            title: 'B',
            description: 'Setting B',
            type: SettingType.number,
            defaultValue: 10,
          ),
        ],
      );

      expect(category.id, 'test');
      expect(category.label, 'Test');
      expect(category.settings, hasLength(2));
    });
  });

  group('SettingType', () {
    test('has all expected values', () {
      expect(SettingType.values, containsAll([
        SettingType.toggle,
        SettingType.dropdown,
        SettingType.number,
      ]));
    });
  });
}
