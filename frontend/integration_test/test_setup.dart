import 'dart:io';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';

/// Shared test setup for all integration tests to ensure isolation.
///
/// Call this in your test file's main() before any test groups:
/// ```dart
/// void main() {
///   setupIntegrationTestIsolation();
///
///   group('My Tests', () { ... });
/// }
/// ```
void setupIntegrationTestIsolation() {
  late Directory tempDir;

  setUpAll(() async {
    // Enable mock data for all integration tests
    useMockData = true;

    // Create temp directory for test isolation
    tempDir = await Directory.systemTemp.createTemp('integration_test_');
    PersistenceService.setBaseDir('${tempDir.path}/.ccinsights');
  });

  tearDownAll(() async {
    // Clean up temp directory
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    // Reset to default
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
  });
}
