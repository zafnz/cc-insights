import 'package:cc_insights_v2/services/cli_launcher_service.dart';
import 'package:cc_insights_v2/widgets/cli_launcher_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const saneLocation = LocationCheck(
    isSane: true,
    appPath: '/Applications/CC Insights.app',
  );

  const badLocation = LocationCheck(
    isSane: false,
    appPath: '/Users/test/Downloads/CC Insights.app',
    reason: 'CC Insights is running from your Downloads folder. '
        'Move it to /Applications first, then try again.',
  );

  const notAppBundle = LocationCheck(
    isSane: false,
    appPath: '/usr/local/bin/cc-insights',
    reason: 'Not running from a macOS app bundle.',
    isAppBundle: false,
  );

  Widget createTestWidget({
    bool isFirstRun = false,
    LocationCheck location = saneLocation,
    bool isInstalled = false,
    Future<String?> Function()? installOverride,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await showCliLauncherDialog(
                context: context,
                isFirstRun: isFirstRun,
                locationCheckOverride: () => location,
                isInstalledOverride: () => isInstalled,
                installOverride: installOverride ?? () async => null,
              );
            },
            child: const Text('Open Dialog'),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
  }

  group('CliLauncherDialog', () {
    testWidgets('shows dialog with install button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await openDialog(tester);

      expect(find.byKey(CliLauncherDialogKeys.dialog), findsOneWidget);
      expect(find.byKey(CliLauncherDialogKeys.installButton), findsOneWidget);
      expect(find.text('CLI Launcher'), findsOneWidget);
    });

    testWidgets('shows Skip button when isFirstRun is true', (tester) async {
      await tester.pumpWidget(createTestWidget(isFirstRun: true));
      await openDialog(tester);

      expect(find.byKey(CliLauncherDialogKeys.skipButton), findsOneWidget);
      expect(find.byKey(CliLauncherDialogKeys.cancelButton), findsNothing);
    });

    testWidgets('shows Cancel button when isFirstRun is false', (tester) async {
      await tester.pumpWidget(createTestWidget(isFirstRun: false));
      await openDialog(tester);

      expect(find.byKey(CliLauncherDialogKeys.cancelButton), findsOneWidget);
      expect(find.byKey(CliLauncherDialogKeys.skipButton), findsNothing);
    });

    testWidgets('shows Reinstall button when already installed',
        (tester) async {
      await tester.pumpWidget(createTestWidget(isInstalled: true));
      await openDialog(tester);

      expect(
        find.byKey(CliLauncherDialogKeys.reinstallButton),
        findsOneWidget,
      );
      expect(find.byKey(CliLauncherDialogKeys.installButton), findsNothing);
    });

    testWidgets('shows location warning for bad locations', (tester) async {
      await tester.pumpWidget(createTestWidget(location: badLocation));
      await openDialog(tester);

      expect(
        find.byKey(CliLauncherDialogKeys.locationWarning),
        findsOneWidget,
      );
      expect(find.textContaining('Downloads folder'), findsOneWidget);
    });

    testWidgets('disables install button for bad app bundle locations',
        (tester) async {
      await tester.pumpWidget(createTestWidget(location: badLocation));
      await openDialog(tester);

      final installButton = tester.widget<FilledButton>(
        find.byKey(CliLauncherDialogKeys.installButton),
      );
      expect(installButton.onPressed, isNull);
    });

    testWidgets('enables install button for non-app-bundle locations',
        (tester) async {
      // When it's not an app bundle (e.g., dev build), install is still allowed
      await tester.pumpWidget(createTestWidget(location: notAppBundle));
      await openDialog(tester);

      final installButton = tester.widget<FilledButton>(
        find.byKey(CliLauncherDialogKeys.installButton),
      );
      expect(installButton.onPressed, isNotNull);
    });

    testWidgets('shows success state after install', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await openDialog(tester);

      await tester.tap(find.byKey(CliLauncherDialogKeys.installButton));
      await tester.pump();

      expect(
        find.byKey(CliLauncherDialogKeys.successMessage),
        findsOneWidget,
      );
      expect(find.byKey(CliLauncherDialogKeys.closeButton), findsOneWidget);
    });

    testWidgets('shows error state on install failure', (tester) async {
      await tester.pumpWidget(
        createTestWidget(
          installOverride: () async => 'Permission denied',
        ),
      );
      await openDialog(tester);

      await tester.tap(find.byKey(CliLauncherDialogKeys.installButton));
      await tester.pump();

      expect(find.byKey(CliLauncherDialogKeys.errorMessage), findsOneWidget);
      expect(find.textContaining('Permission denied'), findsOneWidget);
    });

    testWidgets('no location warning for sane location', (tester) async {
      await tester.pumpWidget(createTestWidget(location: saneLocation));
      await openDialog(tester);

      expect(
        find.byKey(CliLauncherDialogKeys.locationWarning),
        findsNothing,
      );
    });

    testWidgets('Skip button closes dialog with skipped result',
        (tester) async {
      CliLauncherResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showCliLauncherDialog(
                    context: context,
                    isFirstRun: true,
                    locationCheckOverride: () => saneLocation,
                    isInstalledOverride: () => false,
                    installOverride: () async => null,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await openDialog(tester);

      await tester.tap(find.byKey(CliLauncherDialogKeys.skipButton));
      await tester.pump();

      expect(result, CliLauncherResult.skipped);
    });
  });
}
