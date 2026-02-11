import 'package:agent_sdk_core/agent_sdk_core.dart';
import 'package:cc_insights_v2/widgets/workspace_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();

  tearDown(() async {
    await resources.disposeAll();
  });

  group('WorkspaceSettingsPanel', () {
    testWidgets('renders all toggle states correctly from initial options',
        (tester) async {
      const options = CodexWorkspaceWriteOptions(
        networkAccess: true,
        excludeSlashTmp: false,
        excludeTmpdirEnvVar: true,
        writableRoots: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Panel should be visible
      expect(find.byKey(WorkspaceSettingsPanelKeys.panel), findsOneWidget);

      // Header
      expect(find.text('Workspace Write Settings'), findsOneWidget);

      // Section labels
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Temp directories'), findsOneWidget);
      expect(find.text('Additional writable paths'), findsOneWidget);
      expect(find.text('Web search'), findsOneWidget);

      // Network access should show as enabled
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('toggling network access calls onOptionsChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        networkAccess: false,
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap the network access toggle
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.networkAccessToggle));
      await safePumpAndSettle(tester);

      // Should call onOptionsChanged with updated networkAccess
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.networkAccess, true);
    });

    testWidgets('toggling excludeSlashTmp calls onOptionsChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        excludeSlashTmp: false,
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap the exclude /tmp toggle
      await tester
          .tap(find.byKey(WorkspaceSettingsPanelKeys.excludeSlashTmpToggle));
      await safePumpAndSettle(tester);

      // Should call onOptionsChanged with updated excludeSlashTmp
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.excludeSlashTmp, true);
    });

    testWidgets('toggling excludeTmpdir calls onOptionsChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        excludeTmpdirEnvVar: false,
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap the exclude TMPDIR toggle
      await tester
          .tap(find.byKey(WorkspaceSettingsPanelKeys.excludeTmpdirToggle));
      await safePumpAndSettle(tester);

      // Should call onOptionsChanged with updated excludeTmpdirEnvVar
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.excludeTmpdirEnvVar, true);
    });

    testWidgets('adding a writable path calls onOptionsChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: [],
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap "Add path..." button
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.addPathButton));
      await safePumpAndSettle(tester);

      // Should show dialog
      expect(find.text('Add writable path'), findsOneWidget);

      // Enter a path
      await tester.enterText(find.byType(TextField), '/test/path');
      await safePumpAndSettle(tester);

      // Tap Add button
      await tester.tap(find.text('Add'));
      await safePumpAndSettle(tester);

      // Should call onOptionsChanged with new path
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.writableRoots, ['/test/path']);
    });

    testWidgets('removing a writable path calls onOptionsChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: ['/path1', '/path2'],
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Both paths should be visible
      expect(find.text('/path1'), findsOneWidget);
      expect(find.text('/path2'), findsOneWidget);

      // Tap remove button for /path1
      await tester
          .tap(find.byKey(WorkspaceSettingsPanelKeys.removePath('/path1')));
      await safePumpAndSettle(tester);

      // Should call onOptionsChanged with path removed
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.writableRoots, ['/path2']);
    });

    testWidgets('changing web search mode calls onWebSearchChanged',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions();
      CodexWebSearchMode? capturedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (mode) => capturedMode = mode,
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap the dropdown
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.webSearchDropdown));
      await safePumpAndSettle(tester);

      // Select Live
      await tester.tap(find.text('Live').last);
      await safePumpAndSettle(tester);

      // Should call onWebSearchChanged
      expect(capturedMode, CodexWebSearchMode.live);
    });

    testWidgets('displays existing writable paths', (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: ['/users/test', '/var/data'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Both paths should be visible
      expect(find.text('/users/test'), findsOneWidget);
      expect(find.text('/var/data'), findsOneWidget);

      // Remove buttons should be present
      expect(
          find.byKey(WorkspaceSettingsPanelKeys.removePath('/users/test')),
          findsOneWidget);
      expect(find.byKey(WorkspaceSettingsPanelKeys.removePath('/var/data')),
          findsOneWidget);
    });

    testWidgets('web search dropdown displays correct initial value',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Should show "Cached (default)"
      expect(find.text('Cached (default)'), findsOneWidget);
    });

    testWidgets('cancel button in add path dialog dismisses without changes',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: [],
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap "Add path..." button
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.addPathButton));
      await safePumpAndSettle(tester);

      // Should show dialog
      expect(find.text('Add writable path'), findsOneWidget);

      // Enter a path
      await tester.enterText(find.byType(TextField), '/test/path');
      await safePumpAndSettle(tester);

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await safePumpAndSettle(tester);

      // Should not call onOptionsChanged
      expect(capturedOptions, isNull);
    });

    testWidgets('adding empty path does not update options', (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: [],
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap "Add path..." button
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.addPathButton));
      await safePumpAndSettle(tester);

      // Don't enter anything, just tap Add
      await tester.tap(find.text('Add'));
      await safePumpAndSettle(tester);

      // Should not call onOptionsChanged
      expect(capturedOptions, isNull);
    });

    testWidgets('network access disabled state shows "Disabled" label',
        (tester) async {
      const options = CodexWorkspaceWriteOptions(
        networkAccess: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Should show "Disabled"
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('header contains tune icon and title', (tester) async {
      const options = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Should have tune icon
      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.text('Workspace Write Settings'), findsOneWidget);
    });

    testWidgets('all sections have proper labels', (tester) async {
      const options = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // All section labels
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Temp directories'), findsOneWidget);
      expect(find.text('Additional writable paths'), findsOneWidget);
      expect(find.text('Web search'), findsOneWidget);

      // Toggle labels
      expect(find.text('Network access'), findsOneWidget);
      expect(find.text('Exclude /tmp'), findsOneWidget);
      expect(find.text('Exclude \$TMPDIR'), findsOneWidget);
      expect(find.text('Search mode'), findsOneWidget);
    });

    testWidgets('displays hint text for network access', (tester) async {
      const options = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      expect(find.text('Allow commands to access the network'),
          findsOneWidget);
    });

    testWidgets('web search dropdown has all options', (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Tap the dropdown
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.webSearchDropdown));
      await safePumpAndSettle(tester);

      // Should show all three options
      expect(find.text('Disabled').hitTestable(), findsWidgets);
      expect(find.text('Cached (default)').hitTestable(), findsOneWidget);
      expect(find.text('Live').hitTestable(), findsOneWidget);
    });

    testWidgets('multiple paths can be added sequentially', (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        writableRoots: [],
      );
      final capturedOptionsList = <CodexWorkspaceWriteOptions>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptionsList.add(options),
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Add first path
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.addPathButton));
      await safePumpAndSettle(tester);
      await tester.enterText(find.byType(TextField), '/path1');
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Add'));
      await safePumpAndSettle(tester);

      // Add second path
      await tester.tap(find.byKey(WorkspaceSettingsPanelKeys.addPathButton));
      await safePumpAndSettle(tester);
      await tester.enterText(find.byType(TextField), '/path2');
      await safePumpAndSettle(tester);
      await tester.tap(find.text('Add'));
      await safePumpAndSettle(tester);

      // Should have called onOptionsChanged twice
      expect(capturedOptionsList.length, 2);
      expect(capturedOptionsList[0].writableRoots, ['/path1']);
      expect(capturedOptionsList[1].writableRoots, ['/path1', '/path2']);
    });

    testWidgets('toggles maintain state while other options change',
        (tester) async {
      const initialOptions = CodexWorkspaceWriteOptions(
        networkAccess: true,
        excludeSlashTmp: true,
      );
      CodexWorkspaceWriteOptions? capturedOptions;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: initialOptions,
              webSearch: CodexWebSearchMode.disabled,
              onOptionsChanged: (options) => capturedOptions = options,
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      // Toggle excludeTmpdirEnvVar
      await tester
          .tap(find.byKey(WorkspaceSettingsPanelKeys.excludeTmpdirToggle));
      await safePumpAndSettle(tester);

      // Should preserve other options
      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.networkAccess, true);
      expect(capturedOptions!.excludeSlashTmp, true);
      expect(capturedOptions!.excludeTmpdirEnvVar, true);
    });

    testWidgets('panel has correct width', (tester) async {
      const options = CodexWorkspaceWriteOptions();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceSettingsPanel(
              options: options,
              webSearch: CodexWebSearchMode.cached,
              onOptionsChanged: (_) {},
              onWebSearchChanged: (_) {},
            ),
          ),
        ),
      );

      await safePumpAndSettle(tester);

      final panel = tester.widget<SizedBox>(
        find.byKey(WorkspaceSettingsPanelKeys.panel),
      );
      expect(panel.width, 400);
    });
  });
}
