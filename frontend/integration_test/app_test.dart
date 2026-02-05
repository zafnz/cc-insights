import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cc_insights_v2/main.dart';
import 'package:cc_insights_v2/panels/conversation_panel.dart';
import 'package:cc_insights_v2/panels/create_worktree_panel.dart';
import 'package:cc_insights_v2/panels/panels.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/testing/mock_backend.dart';
import 'package:cc_insights_v2/testing/test_helpers.dart';

/// Quick sanity-check integration tests.
///
/// Covers the essential flows: app launch, new chat, new worktree,
/// send/receive messages, auto-scroll, and backend/model selection.
///
/// Run:
///   flutter test integration_test/app_test.dart -d macos
///
/// For the full test suite see full_test.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    final screenshotsDir = Directory('screenshots');
    if (!screenshotsDir.existsSync()) {
      screenshotsDir.createSync(recursive: true);
    }
    useMockData = true;
    tempDir = await Directory.systemTemp.createTemp('integration_test_');
    PersistenceService.setBaseDir('${tempDir.path}/.ccinsights');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    PersistenceService.setBaseDir(
      '${Platform.environment['HOME']}/.ccinsights',
    );
  });

  group('Quick Sanity Checks', () {
    testWidgets('app loads with all panels visible', (tester) async {
      await _ensureMinimumSize(tester);
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Core panels are present
      expect(find.byType(WorktreePanel), findsOneWidget);
      expect(find.byType(ChatsPanel), findsOneWidget);
      expect(find.byType(AgentsPanel), findsOneWidget);
      expect(find.byType(ContentPanel), findsOneWidget);

      // Panel headers visible
      expect(find.text('Worktrees'), findsOneWidget);
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);

      // Mock worktrees loaded
      expect(find.text('main'), findsWidgets);
      expect(find.text('feat-dark-mode'), findsOneWidget);

      // Mock chats for main worktree loaded
      expect(find.text('Log Replay'), findsOneWidget);
      expect(find.text('Add dark mode'), findsOneWidget);

      // No error widgets
      expect(find.byType(ErrorWidget), findsNothing);

      await _takeScreenshot(tester, 'sanity_01_app_loaded');
    });

    testWidgets('can create a new chat', (tester) async {
      await _ensureMinimumSize(tester);
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Find the "New Chat" card in the chats panel
      final newChatFinder = find.text('New Chat');
      // The "New Chat" card is in the chats panel list
      // It may also appear in the welcome header; scroll to find the one
      // in the chats panel.
      final chatsPanelNewChat = find.descendant(
        of: find.byType(ChatsPanel),
        matching: newChatFinder,
      );

      // Scroll the chats panel to make New Chat visible if needed
      final chatsScrollable = find.descendant(
        of: find.byType(ChatsPanel),
        matching: find.byType(Scrollable),
      );
      if (chatsScrollable.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          chatsPanelNewChat,
          200,
          scrollable: chatsScrollable.first,
        );
        await safePumpAndSettle(tester);
      }

      expect(chatsPanelNewChat, findsOneWidget);

      // Tap "New Chat" - this should show the welcome/new-chat screen
      await tester.tap(chatsPanelNewChat);
      await safePumpAndSettle(tester);

      // The welcome card should be shown with "New Chat" in the header
      // and the welcome message.
      expect(find.text('New Chat'), findsWidgets);
      expect(find.text('Welcome to CC-Insights'), findsOneWidget);

      await _takeScreenshot(tester, 'sanity_02_new_chat_created');
    });

    testWidgets('can navigate to new worktree form', (tester) async {
      await _ensureMinimumSize(tester);
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Scroll worktree panel to find "New Worktree" card
      final worktreeScrollable = find.descendant(
        of: find.byType(WorktreePanel),
        matching: find.byType(Scrollable),
      );
      expect(worktreeScrollable, findsWidgets);

      await tester.scrollUntilVisible(
        find.text('New Worktree'),
        200,
        scrollable: worktreeScrollable.first,
      );
      await safePumpAndSettle(tester);

      // Tap "New Worktree"
      await tester.tap(find.text('New Worktree'));
      await safePumpAndSettle(tester);

      // CreateWorktreePanel should appear
      expect(find.byType(CreateWorktreePanel), findsOneWidget);

      // Wait for loading to complete
      await pumpUntilGone(
        tester,
        find.byType(CircularProgressIndicator),
        timeout: const Duration(seconds: 5),
        debugLabel: 'waiting for CreateWorktreePanel to load',
      );

      // Form elements visible
      expect(find.text('Branch/worktree name:'), findsOneWidget);
      expect(find.text('Worktree base:'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);

      await _takeScreenshot(tester, 'sanity_03_new_worktree_form');

      // Cancel back to conversation view
      await tester.tap(find.byKey(CreateWorktreePanelKeys.cancelButton));
      await safePumpAndSettle(tester);
      expect(find.byType(CreateWorktreePanel), findsNothing);
    });

    testWidgets('can send message and receive reply', (tester) async {
      await _ensureMinimumSize(tester);

      final mockBackend = MockBackendService();
      await mockBackend.start();
      mockBackend.nextSessionConfig = const MockResponseConfig(
        autoReply: true,
        replyDelay: Duration(milliseconds: 100),
        replyText: 'I received your message: {message}',
      );

      await tester.pumpWidget(CCInsightsApp(backendService: mockBackend));
      await safePumpAndSettle(tester);

      // Select existing chat
      await tester.tap(find.text('Log Replay'));
      await safePumpAndSettle(tester);

      // Type and send a message
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await safePumpAndSettle(tester);

      const testMessage = 'Hello from sanity test!';
      await tester.enterText(textField, testMessage);
      await safePumpAndSettle(tester);

      await _takeScreenshot(tester, 'sanity_04_message_typed');

      // Send
      await tester.tap(find.byIcon(Icons.send));
      await safePumpAndSettle(tester);

      // User message appears
      expect(find.text(testMessage), findsOneWidget);

      await _takeScreenshot(tester, 'sanity_05_message_sent');

      // Wait for mock reply
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await safePumpAndSettle(tester);

      // Reply appears
      expect(find.textContaining('I received your message'), findsOneWidget);

      // Input field cleared
      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.controller?.text, isEmpty);

      await _takeScreenshot(tester, 'sanity_06_reply_received');
    });

    testWidgets('conversation auto-scrolls to bottom', (tester) async {
      await _ensureMinimumSize(tester);
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // Select the Long Conversation chat (has lots of content)
      await tester.tap(find.text('Long Conversation'));
      await safePumpAndSettle(tester);

      // Allow scroll animations to settle
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      // Find the conversation scrollable
      final conversationScrollables = find.descendant(
        of: find.byType(ConversationPanel),
        matching: find.byWidgetPredicate((widget) {
          if (widget is Scrollable) {
            return widget.axisDirection == AxisDirection.down;
          }
          return false;
        }),
      );
      expect(conversationScrollables, findsWidgets);

      final scrollableWidget = tester.widget<Scrollable>(
        conversationScrollables.first,
      );
      final scrollController = scrollableWidget.controller;
      expect(scrollController, isNotNull);
      expect(scrollController!.hasClients, isTrue);

      // Content should be scrollable
      final maxExtent = scrollController.position.maxScrollExtent;
      expect(maxExtent, greaterThan(0));

      // Should be scrolled to or near the bottom
      final currentPixels = scrollController.position.pixels;
      expect(
        currentPixels,
        closeTo(maxExtent, 50.0),
        reason: 'Long conversation should auto-scroll to bottom. '
            'Current: $currentPixels, Max: $maxExtent',
      );

      await _takeScreenshot(tester, 'sanity_07_auto_scroll_bottom');
    });

    testWidgets('backend and model dropdowns are accessible', (tester) async {
      await _ensureMinimumSize(tester);
      await tester.pumpWidget(const CCInsightsApp());
      await safePumpAndSettle(tester);

      // With no chat selected, the WelcomeCard is shown with dropdowns.
      // The welcome header has agent dropdown (Claude/Codex), model
      // dropdown (Haiku/Sonnet/Opus), and permission dropdown.

      // Verify "Claude" agent label is visible (default backend)
      expect(find.text('Claude'), findsWidgets);

      // Verify default model label is visible (Opus is the default)
      expect(find.text('Opus'), findsWidgets);

      // Verify default permission label
      expect(find.text('Default'), findsWidgets);

      await _takeScreenshot(tester, 'sanity_08_welcome_dropdowns');

      // Now select a chat and verify conversation header has the same
      // dropdowns.
      await tester.tap(find.text('Log Replay'));
      await safePumpAndSettle(tester);

      // The conversation header should show agent/model/permission
      // dropdowns for the selected chat.
      expect(find.text('Claude'), findsWidgets);

      await _takeScreenshot(tester, 'sanity_09_chat_dropdowns');
    });
  });
}

const _screenshotsDir = 'screenshots';

Future<void> _ensureMinimumSize(WidgetTester tester) async {
  const minWidth = 1000.0;
  const minHeight = 800.0;
  final binding = tester.binding;
  final view = binding.platformDispatcher.views.first;
  final currentSize = view.physicalSize / view.devicePixelRatio;

  if (currentSize.width < minWidth || currentSize.height < minHeight) {
    final width = currentSize.width < minWidth ? minWidth : currentSize.width;
    final height =
        currentSize.height < minHeight ? minHeight : currentSize.height;
    await binding.setSurfaceSize(Size(width, height));
  }
}

Future<void> _takeScreenshot(WidgetTester tester, String name) async {
  final element = tester.binding.rootElement!;
  RenderObject? renderObject = element.renderObject;

  while (renderObject != null && renderObject is! RenderRepaintBoundary) {
    renderObject = renderObject.parent;
  }

  if (renderObject == null) {
    void visitor(Element element) {
      if (renderObject != null) return;
      if (element.renderObject is RenderRepaintBoundary) {
        renderObject = element.renderObject;
        return;
      }
      element.visitChildren(visitor);
    }
    element.visitChildren(visitor);
  }

  if (renderObject is! RenderRepaintBoundary) {
    debugPrint('Warning: Could not find RenderRepaintBoundary for screenshot');
    return;
  }

  final boundary = renderObject as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData != null) {
    final file = File('$_screenshotsDir/$name.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    debugPrint('Screenshot saved: $_screenshotsDir/$name.png');
  }
}
