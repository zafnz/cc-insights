import 'package:cc_insights_v2/state/theme_state.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemeState', () {
    test('defaults to deepPurple and system mode', () {
      final state = ThemeState();
      check(state.seedColor.value)
          .equals(Colors.deepPurple.value);
      check(state.themeMode).equals(ThemeMode.system);
    });

    test('setSeedColor updates and notifies', () {
      final state = ThemeState();
      var notified = false;
      state.addListener(() => notified = true);

      state.setSeedColor(Colors.blue);

      check(state.seedColor.value)
          .equals(Colors.blue.value);
      check(notified).isTrue();
    });

    test('setSeedColor skips if same color', () {
      final state = ThemeState();
      var count = 0;
      state.addListener(() => count++);

      state.setSeedColor(Colors.deepPurple);

      check(count).equals(0);
    });

    test('setThemeMode updates and notifies', () {
      final state = ThemeState();
      var notified = false;
      state.addListener(() => notified = true);

      state.setThemeMode(ThemeMode.dark);

      check(state.themeMode).equals(ThemeMode.dark);
      check(notified).isTrue();
    });

    test('setThemeMode skips if same mode', () {
      final state = ThemeState();
      var count = 0;
      state.addListener(() => count++);

      state.setThemeMode(ThemeMode.system);

      check(count).equals(0);
    });

    test('applyLoaded sets both values and notifies once',
        () {
      final state = ThemeState();
      var count = 0;
      state.addListener(() => count++);

      state.applyLoaded(Colors.teal, ThemeMode.light);

      check(state.seedColor.value)
          .equals(Colors.teal.value);
      check(state.themeMode).equals(ThemeMode.light);
      check(count).equals(1);
    });

    group('activePreset', () {
      test('returns matching preset', () {
        final state = ThemeState(
          seedColor: Colors.blue,
        );
        check(state.activePreset)
            .equals(ThemePresetColor.blue);
      });

      test('returns null for custom color', () {
        final state = ThemeState(
          seedColor: const Color(0xFFFF5722),
        );
        check(state.activePreset).isNull();
      });

      test('returns deepPurple for default', () {
        final state = ThemeState();
        check(state.activePreset)
            .equals(ThemePresetColor.deepPurple);
      });
    });

    test('constructor accepts custom values', () {
      final state = ThemeState(
        seedColor: Colors.red,
        themeMode: ThemeMode.dark,
      );
      check(state.seedColor.value)
          .equals(Colors.red.value);
      check(state.themeMode).equals(ThemeMode.dark);
    });
  });
}
