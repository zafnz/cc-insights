import 'package:agent_sdk_core/agent_sdk_core.dart'
    show BackendCapabilities, BackendType, PermissionMode;
import 'package:cc_insights_v2/models/chat_model.dart';
import 'package:cc_insights_v2/widgets/model_permission_selector.dart';
import 'package:checks/checks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  const testModels = [
    ChatModel(id: 'default', label: 'Default', backend: BackendType.directCli),
    ChatModel(id: 'haiku', label: 'Haiku', backend: BackendType.directCli),
    ChatModel(id: 'sonnet', label: 'Sonnet', backend: BackendType.directCli),
    ChatModel(id: 'opus', label: 'Opus', backend: BackendType.directCli),
  ];

  const allPermissionModes = [
    PermissionMode.defaultMode,
    PermissionMode.acceptEdits,
    PermissionMode.plan,
    PermissionMode.bypassPermissions,
  ];

  const fullCapabilities = BackendCapabilities(
    supportsModelChange: true,
    supportsPermissionModeChange: true,
    supportsModelListing: true,
  );

  Widget createTestApp({
    List<ChatModel> models = testModels,
    String? selectedModelId = 'sonnet',
    ValueChanged<String>? onModelChanged,
    List<PermissionMode> permissionModes = allPermissionModes,
    PermissionMode selectedPermissionMode = PermissionMode.defaultMode,
    ValueChanged<PermissionMode>? onPermissionModeChanged,
    BackendCapabilities capabilities = fullCapabilities,
    Axis direction = Axis.horizontal,
    bool compact = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 500,
            child: ModelPermissionSelector(
              models: models,
              selectedModelId: selectedModelId,
              onModelChanged: onModelChanged ?? (_) {},
              permissionModes: permissionModes,
              selectedPermissionMode: selectedPermissionMode,
              onPermissionModeChanged: onPermissionModeChanged ?? (_) {},
              capabilities: capabilities,
              direction: direction,
              compact: compact,
            ),
          ),
        ),
      ),
    );
  }

  group('ModelPermissionSelector', () {
    group('rendering', () {
      testWidgets('renders both dropdowns', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        expect(
          find.byKey(ModelPermissionSelectorKeys.container),
          findsOneWidget,
        );
        expect(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
          findsOneWidget,
        );
        expect(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
          findsOneWidget,
        );
      });

      testWidgets('shows selected model', (tester) async {
        await tester.pumpWidget(createTestApp(selectedModelId: 'sonnet'));
        await safePumpAndSettle(tester);

        expect(find.text('Sonnet'), findsOneWidget);
      });

      testWidgets('shows selected permission mode', (tester) async {
        await tester.pumpWidget(createTestApp(
          selectedPermissionMode: PermissionMode.acceptEdits,
        ));
        await safePumpAndSettle(tester);

        expect(find.text('Accept Edits'), findsOneWidget);
      });

      testWidgets('shows labels in non-compact mode', (tester) async {
        await tester.pumpWidget(createTestApp(compact: false));
        await safePumpAndSettle(tester);

        expect(find.text('Model'), findsOneWidget);
        expect(find.text('Permission Mode'), findsOneWidget);
      });

      testWidgets('hides labels in compact mode', (tester) async {
        await tester.pumpWidget(createTestApp(compact: true));
        await safePumpAndSettle(tester);

        expect(find.text('Model'), findsNothing);
        expect(find.text('Permission Mode'), findsNothing);
      });

      testWidgets('renders in vertical layout', (tester) async {
        await tester.pumpWidget(createTestApp(direction: Axis.vertical));
        await safePumpAndSettle(tester);

        expect(
          find.byKey(ModelPermissionSelectorKeys.container),
          findsOneWidget,
        );
        // Verify it's a Column
        final container = tester.widget<Column>(
          find.byKey(ModelPermissionSelectorKeys.container),
        );
        check(container.mainAxisSize).equals(MainAxisSize.min);
      });

      testWidgets('renders in horizontal layout', (tester) async {
        await tester.pumpWidget(createTestApp(direction: Axis.horizontal));
        await safePumpAndSettle(tester);

        // Verify it's a Row
        final container = tester.widget<Row>(
          find.byKey(ModelPermissionSelectorKeys.container),
        );
        check(container.mainAxisSize).equals(MainAxisSize.min);
      });
    });

    group('model selection', () {
      testWidgets('calls onModelChanged when model selected', (tester) async {
        String? changedTo;

        await tester.pumpWidget(createTestApp(
          selectedModelId: 'sonnet',
          onModelChanged: (value) => changedTo = value,
        ));
        await safePumpAndSettle(tester);

        // Open model dropdown
        await tester.tap(find.byKey(ModelPermissionSelectorKeys.modelDropdown));
        await tester.pump();

        // Select Opus - find the one in the dropdown overlay (last in list)
        await tester.tap(find.text('Opus').last);
        await safePumpAndSettle(tester);

        check(changedTo).equals('opus');
      });

      testWidgets('falls back to first model when selectedModelId not found',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          selectedModelId: 'nonexistent',
        ));
        await safePumpAndSettle(tester);

        // Should show the first model (Default) since 'nonexistent' isn't found.
        // "Default" appears in both the model and permission dropdowns, so
        // verify the model dropdown's value via its DropdownButtonFormField.
        final modelDropdown = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
        );
        check(modelDropdown.initialValue).equals('default');
      });
    });

    group('permission mode selection', () {
      testWidgets('calls onPermissionModeChanged when mode selected',
          (tester) async {
        PermissionMode? changedTo;

        await tester.pumpWidget(createTestApp(
          selectedPermissionMode: PermissionMode.defaultMode,
          onPermissionModeChanged: (value) => changedTo = value,
        ));
        await safePumpAndSettle(tester);

        // Open permission dropdown
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();

        // Select Accept Edits
        await tester.tap(find.text('Accept Edits').last);
        await safePumpAndSettle(tester);

        check(changedTo).equals(PermissionMode.acceptEdits);
      });

      testWidgets('displays all permission mode labels', (tester) async {
        await tester.pumpWidget(createTestApp());
        await safePumpAndSettle(tester);

        // Open permission dropdown to see all options
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();

        expect(find.text('Default'), findsWidgets);
        expect(find.text('Accept Edits'), findsWidgets);
        expect(find.text('Plan'), findsWidgets);
        expect(find.text('Bypass Permissions'), findsWidgets);
      });

      testWidgets('falls back to first mode when selectedMode not in list',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          permissionModes: const [
            PermissionMode.defaultMode,
            PermissionMode.acceptEdits,
          ],
          selectedPermissionMode: PermissionMode.bypassPermissions,
        ));
        await safePumpAndSettle(tester);

        // Should show Default since bypassPermissions is not in the list
        expect(find.text('Default'), findsOneWidget);
      });
    });

    group('backend capabilities', () {
      testWidgets('disables model dropdown when backend lacks support',
          (tester) async {
        String? changedTo;

        await tester.pumpWidget(createTestApp(
          capabilities: const BackendCapabilities(
            supportsModelChange: false,
            supportsPermissionModeChange: true,
          ),
          onModelChanged: (value) => changedTo = value,
        ));
        await safePumpAndSettle(tester);

        // Model dropdown should exist but be disabled
        expect(
          find.byKey(ModelPermissionSelectorKeys.modelDropdown),
          findsOneWidget,
        );

        // Should have a tooltip explaining why it's disabled
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        final disabledTooltip = tooltips.where(
          (t) => t.message == 'Model selection not supported by this backend',
        );
        check(disabledTooltip).isNotEmpty();

        // Tap should not trigger callback
        await tester.tap(find.byKey(ModelPermissionSelectorKeys.modelDropdown));
        await tester.pump();

        check(changedTo).isNull();
      });

      testWidgets('disables permission dropdown when backend lacks support',
          (tester) async {
        PermissionMode? changedTo;

        await tester.pumpWidget(createTestApp(
          capabilities: const BackendCapabilities(
            supportsModelChange: true,
            supportsPermissionModeChange: false,
          ),
          onPermissionModeChanged: (value) => changedTo = value,
        ));
        await safePumpAndSettle(tester);

        // Permission dropdown should exist but be disabled
        expect(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
          findsOneWidget,
        );

        // Should have a tooltip explaining why it's disabled
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        final disabledTooltip = tooltips.where(
          (t) =>
              t.message ==
              'Permission mode changes not supported by this backend',
        );
        check(disabledTooltip).isNotEmpty();

        // Tap should not trigger callback
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();

        check(changedTo).isNull();
      });

      testWidgets('both dropdowns enabled with full capabilities',
          (tester) async {
        String? modelChanged;
        PermissionMode? permChanged;

        await tester.pumpWidget(createTestApp(
          capabilities: fullCapabilities,
          onModelChanged: (value) => modelChanged = value,
          onPermissionModeChanged: (value) => permChanged = value,
        ));
        await safePumpAndSettle(tester);

        // Change model
        await tester.tap(find.byKey(ModelPermissionSelectorKeys.modelDropdown));
        await tester.pump();
        await tester.tap(find.text('Opus').last);
        await safePumpAndSettle(tester);
        check(modelChanged).equals('opus');

        // Change permission
        await tester.tap(
          find.byKey(ModelPermissionSelectorKeys.permissionDropdown),
        );
        await tester.pump();
        await tester.tap(find.text('Plan').last);
        await safePumpAndSettle(tester);
        check(permChanged).equals(PermissionMode.plan);
      });

      testWidgets('both dropdowns disabled with no capabilities',
          (tester) async {
        await tester.pumpWidget(createTestApp(
          capabilities: const BackendCapabilities(),
        ));
        await safePumpAndSettle(tester);

        // Both should have disabled tooltips
        final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
        check(tooltips.length).isGreaterOrEqual(2);
      });
    });

    group('different backends', () {
      testWidgets('works with Codex models', (tester) async {
        const codexModels = [
          ChatModel(
            id: '',
            label: 'Default (server)',
            backend: BackendType.codex,
          ),
          ChatModel(
            id: 'gpt-5.2',
            label: 'GPT-5.2',
            backend: BackendType.codex,
          ),
        ];

        await tester.pumpWidget(createTestApp(
          models: codexModels,
          selectedModelId: '',
          permissionModes: const [PermissionMode.defaultMode],
        ));
        await safePumpAndSettle(tester);

        expect(find.text('Default (server)'), findsOneWidget);
      });

      testWidgets('works with single permission mode', (tester) async {
        await tester.pumpWidget(createTestApp(
          permissionModes: const [PermissionMode.defaultMode],
          selectedPermissionMode: PermissionMode.defaultMode,
        ));
        await safePumpAndSettle(tester);

        expect(find.text('Default'), findsWidgets);
      });
    });
  });
}
