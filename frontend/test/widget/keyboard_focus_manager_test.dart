import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cc_insights_v2/widgets/keyboard_focus_manager.dart';

import '../test_helpers.dart';

void main() {
  group('KeyboardFocusManager', () {
    testWidgets('redirects typing keys to registered message input',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusManager(
            child: Scaffold(
              body: Column(
                children: [
                  // Some other widget that can receive focus
                  const TextField(key: Key('other_field')),
                  // The message input
                  Builder(
                    builder: (context) {
                      // Register after build
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        KeyboardFocusManager.maybeOf(context)
                            ?.registerMessageInput(focusNode, controller);
                      });
                      return TextField(
                        key: const Key('message_input'),
                        controller: controller,
                        focusNode: focusNode,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Focus the other field first
      await tester.tap(find.byKey(const Key('other_field')));
      await safePumpAndSettle(tester);

      // Verify message input doesn't have focus
      expect(focusNode.hasFocus, isFalse);

      // Send a key event for 'a'
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await safePumpAndSettle(tester);

      // Verify message input now has focus and contains the character
      expect(focusNode.hasFocus, isTrue);
      expect(controller.text, 'a');

      // Clean up
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('handles backspace when message input is not focused',
        (tester) async {
      final controller = TextEditingController(text: 'hello');
      controller.selection = const TextSelection.collapsed(offset: 5);
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusManager(
            child: Scaffold(
              body: Column(
                children: [
                  const TextField(key: Key('other_field')),
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        KeyboardFocusManager.maybeOf(context)
                            ?.registerMessageInput(focusNode, controller);
                      });
                      return TextField(
                        key: const Key('message_input'),
                        controller: controller,
                        focusNode: focusNode,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Focus the other field
      await tester.tap(find.byKey(const Key('other_field')));
      await safePumpAndSettle(tester);
      expect(focusNode.hasFocus, isFalse);

      // Send backspace
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await safePumpAndSettle(tester);

      // Verify message input has focus and last character was deleted
      expect(focusNode.hasFocus, isTrue);
      expect(controller.text, 'hell');

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('does not intercept keyboard shortcuts (Cmd+key)',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusManager(
            child: Scaffold(
              body: Column(
                children: [
                  const TextField(key: Key('other_field')),
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        KeyboardFocusManager.maybeOf(context)
                            ?.registerMessageInput(focusNode, controller);
                      });
                      return TextField(
                        key: const Key('message_input'),
                        controller: controller,
                        focusNode: focusNode,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Focus the other field
      await tester.tap(find.byKey(const Key('other_field')));
      await safePumpAndSettle(tester);
      expect(focusNode.hasFocus, isFalse);

      // Send Cmd+C (should NOT redirect to message input)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await safePumpAndSettle(tester);

      // Message input should NOT have focus (shortcut was not intercepted)
      expect(focusNode.hasFocus, isFalse);
      expect(controller.text, isEmpty);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('does not intercept arrow keys', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusManager(
            child: Scaffold(
              body: Column(
                children: [
                  const TextField(key: Key('other_field')),
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        KeyboardFocusManager.maybeOf(context)
                            ?.registerMessageInput(focusNode, controller);
                      });
                      return TextField(
                        key: const Key('message_input'),
                        controller: controller,
                        focusNode: focusNode,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Focus the other field
      await tester.tap(find.byKey(const Key('other_field')));
      await safePumpAndSettle(tester);
      expect(focusNode.hasFocus, isFalse);

      // Send arrow key
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await safePumpAndSettle(tester);

      // Message input should NOT have focus
      expect(focusNode.hasFocus, isFalse);

      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('does not intercept when message input already has focus',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardFocusManager(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    KeyboardFocusManager.maybeOf(context)
                        ?.registerMessageInput(focusNode, controller);
                  });
                  return TextField(
                    key: const Key('message_input'),
                    controller: controller,
                    focusNode: focusNode,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await safePumpAndSettle(tester);

      // Focus the message input directly
      await tester.tap(find.byKey(const Key('message_input')));
      await safePumpAndSettle(tester);
      expect(focusNode.hasFocus, isTrue);

      // Type normally - should work without double characters
      await tester.enterText(find.byKey(const Key('message_input')), 'test');
      await safePumpAndSettle(tester);

      expect(controller.text, 'test');

      controller.dispose();
      focusNode.dispose();
    });

    group('suspend/resume', () {
      testWidgets('does not intercept keys when suspended', (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();
        KeyboardFocusManagerState? managerState;

        await tester.pumpWidget(
          MaterialApp(
            home: KeyboardFocusManager(
              child: Scaffold(
                body: Column(
                  children: [
                    const TextField(key: Key('other_field')),
                    Builder(
                      builder: (context) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          managerState = KeyboardFocusManager.maybeOf(context);
                          managerState?.registerMessageInput(
                              focusNode, controller);
                        });
                        return TextField(
                          key: const Key('message_input'),
                          controller: controller,
                          focusNode: focusNode,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await safePumpAndSettle(tester);

        // Focus the other field
        await tester.tap(find.byKey(const Key('other_field')));
        await safePumpAndSettle(tester);
        expect(focusNode.hasFocus, isFalse);

        // Suspend keyboard interception
        final resume = managerState!.suspend();
        expect(managerState!.isSuspended, isTrue);

        // Send a key - should NOT be intercepted
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await safePumpAndSettle(tester);

        // Message input should NOT have focus, text should be empty
        expect(focusNode.hasFocus, isFalse);
        expect(controller.text, isEmpty);

        // Resume
        resume();
        expect(managerState!.isSuspended, isFalse);

        // Now send a key - should be intercepted
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
        await safePumpAndSettle(tester);

        expect(focusNode.hasFocus, isTrue);
        expect(controller.text, 'b');

        controller.dispose();
        focusNode.dispose();
      });

      testWidgets('nested suspensions work correctly', (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();
        KeyboardFocusManagerState? managerState;

        await tester.pumpWidget(
          MaterialApp(
            home: KeyboardFocusManager(
              child: Scaffold(
                body: Column(
                  children: [
                    const TextField(key: Key('other_field')),
                    Builder(
                      builder: (context) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          managerState = KeyboardFocusManager.maybeOf(context);
                          managerState?.registerMessageInput(
                              focusNode, controller);
                        });
                        return TextField(
                          key: const Key('message_input'),
                          controller: controller,
                          focusNode: focusNode,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await safePumpAndSettle(tester);

        expect(managerState!.isSuspended, isFalse);

        // First suspension
        final resume1 = managerState!.suspend();
        expect(managerState!.isSuspended, isTrue);

        // Second (nested) suspension
        final resume2 = managerState!.suspend();
        expect(managerState!.isSuspended, isTrue);

        // Resume first - should still be suspended
        resume1();
        expect(managerState!.isSuspended, isTrue);

        // Resume second - now should be active
        resume2();
        expect(managerState!.isSuspended, isFalse);

        controller.dispose();
        focusNode.dispose();
      });

      testWidgets('resume callback is idempotent', (tester) async {
        final controller = TextEditingController();
        final focusNode = FocusNode();
        KeyboardFocusManagerState? managerState;

        await tester.pumpWidget(
          MaterialApp(
            home: KeyboardFocusManager(
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      managerState = KeyboardFocusManager.maybeOf(context);
                      managerState?.registerMessageInput(focusNode, controller);
                    });
                    return TextField(
                      key: const Key('message_input'),
                      controller: controller,
                      focusNode: focusNode,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await safePumpAndSettle(tester);

        // Suspend and get resume callback
        final resume = managerState!.suspend();
        expect(managerState!.isSuspended, isTrue);

        // Call resume multiple times - should only decrement once
        resume();
        resume();
        resume();

        expect(managerState!.isSuspended, isFalse);

        // Suspend again to verify count is correct
        managerState!.suspend();
        expect(managerState!.isSuspended, isTrue);

        controller.dispose();
        focusNode.dispose();
      });
    });
  });
}
