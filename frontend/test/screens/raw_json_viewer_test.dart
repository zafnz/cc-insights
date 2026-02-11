import 'package:cc_insights_v2/screens/raw_json_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RawJsonViewer', () {
    late List<Map<String, dynamic>> testMessages;

    setUp(() {
      testMessages = [
        {'type': 'assistant', 'content': 'Hello'},
        {'type': 'user', 'text': 'Hi there'},
        {'type': 'result', 'data': {'key': 'value'}},
      ];
    });

    Widget buildTestWidget({List<Map<String, dynamic>>? messages}) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: RawJsonViewer(
          rawMessages: messages ?? testMessages,
          title: 'Test JSON',
        ),
      );
    }

    testWidgets('renders app bar with title', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Test JSON'), findsOneWidget);
    });

    testWidgets('renders copy all button in app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(RawJsonViewerKeys.copyAllButton), findsOneWidget);
    });

    testWidgets('shows empty state when no messages', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: []));

      expect(find.byKey(RawJsonViewerKeys.emptyState), findsOneWidget);
      expect(find.text('No raw messages available'), findsOneWidget);
    });

    testWidgets('renders message list when messages exist', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(RawJsonViewerKeys.messageList), findsOneWidget);
    });

    testWidgets('renders correct number of message items', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Should find all 3 message items
      expect(find.byKey(RawJsonViewerKeys.messageItem(0)), findsOneWidget);
      expect(find.byKey(RawJsonViewerKeys.messageItem(1)), findsOneWidget);
      expect(find.byKey(RawJsonViewerKeys.messageItem(2)), findsOneWidget);
    });

    testWidgets('renders type badges with correct text', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('ASSISTANT'), findsOneWidget);
      expect(find.text('USER'), findsOneWidget);
      expect(find.text('RESULT'), findsOneWidget);
    });

    testWidgets('renders copy button for each message', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byKey(RawJsonViewerKeys.copyButton(0)), findsOneWidget);
      expect(find.byKey(RawJsonViewerKeys.copyButton(1)), findsOneWidget);
      expect(find.byKey(RawJsonViewerKeys.copyButton(2)), findsOneWidget);
    });

    testWidgets('renders pretty-printed JSON content', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Should find formatted JSON with indentation
      expect(find.textContaining('"type": "assistant"'), findsOneWidget);
      expect(find.textContaining('"content": "Hello"'), findsOneWidget);
    });

    testWidgets('copy all button copies all messages to clipboard',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Tap the copy all button
      await tester.tap(find.byKey(RawJsonViewerKeys.copyAllButton));
      await tester.pumpAndSettle();

      // Should show snackbar
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('individual copy button copies single message', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Tap the copy button for the first message
      await tester.tap(find.byKey(RawJsonViewerKeys.copyButton(0)));
      await tester.pumpAndSettle();

      // Should show snackbar
      expect(find.text('Copied to clipboard'), findsOneWidget);
    });

    testWidgets('handles unknown message type gracefully', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: [
        {'type': 'custom_type', 'data': 'test'},
      ]));

      // Should still render with UNKNOWN type badge
      expect(find.text('CUSTOM_TYPE'), findsOneWidget);
    });

    testWidgets('handles message without type field', (tester) async {
      await tester.pumpWidget(buildTestWidget(messages: [
        {'data': 'no type field'},
      ]));

      // Should render with UNKNOWN type badge
      expect(find.text('UNKNOWN'), findsOneWidget);
    });

    testWidgets('back button navigates back', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => RawJsonViewer(
                      rawMessages: testMessages,
                      title: 'Test JSON',
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      // Navigate to the JSON viewer
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Test JSON'), findsOneWidget);

      // Tap the back button
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Should be back on the original screen
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
