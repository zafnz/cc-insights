import 'package:cc_insights_v2/services/cli_launcher_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CliLauncherService', () {
    group('resolveAppBundlePath', () {
      test('finds .app directory from executable path', () {
        final result = CliLauncherService.resolveAppBundlePath(
          '/Applications/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(result, '/Applications/CC Insights.app');
      });

      test('finds .app directory from nested path', () {
        final result = CliLauncherService.resolveAppBundlePath(
          '/Users/test/Applications/MyApp.app/Contents/Frameworks/thing',
        );
        expect(result, '/Users/test/Applications/MyApp.app');
      });

      test('returns null when no .app in path', () {
        final result = CliLauncherService.resolveAppBundlePath(
          '/usr/local/bin/cc-insights',
        );
        expect(result, isNull);
      });

      test('returns null for root path', () {
        final result = CliLauncherService.resolveAppBundlePath('/');
        expect(result, isNull);
      });
    });

    group('checkAppLocation', () {
      test('returns sane for /Applications', () {
        final result = CliLauncherService.checkAppLocation(
          '/Applications/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(result.isSane, isTrue);
        expect(result.isAppBundle, isTrue);
        expect(result.appPath, '/Applications/CC Insights.app');
      });

      test('returns not sane for /Volumes', () {
        final result = CliLauncherService.checkAppLocation(
          '/Volumes/CC Insights/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(result.isSane, isFalse);
        expect(result.reason, contains('disk image'));
      });

      test('returns not sane for /tmp', () {
        final result = CliLauncherService.checkAppLocation(
          '/tmp/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(result.isSane, isFalse);
        expect(result.reason, contains('temporary'));
      });

      test('returns not app bundle when no .app in path', () {
        final result = CliLauncherService.checkAppLocation(
          '/usr/local/bin/cc-insights',
        );
        expect(result.isSane, isFalse);
        expect(result.isAppBundle, isFalse);
      });

      test('returns sane for neutral locations', () {
        final result = CliLauncherService.checkAppLocation(
          '/opt/apps/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(result.isSane, isTrue);
      });
    });

    group('generateScript', () {
      test('generates script with exec and argument passthrough', () {
        final script = CliLauncherService.generateScript(
          '/Applications/CC Insights.app/Contents/MacOS/CC Insights',
        );
        expect(script, contains('#!/bin/bash'));
        expect(script, contains('exec'));
        expect(
          script,
          contains(
            '"/Applications/CC Insights.app/Contents/MacOS/CC Insights"',
          ),
        );
        expect(script, contains(r'"$@"'));
      });

      test('handles paths with spaces', () {
        final script = CliLauncherService.generateScript(
          '/Applications/My App.app/Contents/MacOS/My App',
        );
        expect(
          script,
          contains('"/Applications/My App.app/Contents/MacOS/My App"'),
        );
      });
    });
  });
}
