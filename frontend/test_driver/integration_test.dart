import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Test driver for integration tests with screenshot support.
///
/// Run with:
/// ```bash
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/app_test.dart \
///   -d macos
/// ```
///
/// Screenshots are saved to the `screenshots/` directory.
Future<void> main() async {
  // Ensure screenshots directory exists
  final screenshotsDir = Directory('screenshots');
  if (!screenshotsDir.existsSync()) {
    screenshotsDir.createSync(recursive: true);
  }

  await integrationDriver(
    onScreenshot: (String screenshotName, List<int> screenshotBytes, [args]) async {
      final file = File('screenshots/$screenshotName.png');
      await file.writeAsBytes(screenshotBytes);
      // ignore: avoid_print
      print('Screenshot saved: screenshots/$screenshotName.png');
      return true;
    },
  );
}
