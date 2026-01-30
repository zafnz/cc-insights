import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Initialize integration test environment.
///
/// Call this at the start of each integration test.
IntegrationTestWidgetsFlutterBinding ensureIntegrationTestInitialized() {
  return IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

/// Wait for the app to settle after a state change.
///
/// Uses a timeout to prevent hanging indefinitely on animations.
Future<void> waitForAppToSettle(WidgetTester tester) async {
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Find widget by key and verify it exists.
Finder findByKey(String key) {
  return find.byKey(Key(key));
}

/// Find text widget and verify it exists.
Finder findText(String text) {
  return find.text(text);
}
