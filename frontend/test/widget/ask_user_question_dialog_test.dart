import 'dart:async';

import 'package:cc_insights_v2/widgets/ask_user_question_dialog.dart';
import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  group('AskUserQuestionDialog', () {
    late sdk.PermissionRequest singleSelectRequest;
    late sdk.PermissionRequest multiSelectRequest;
    late sdk.PermissionRequest multiQuestionRequest;

    /// Creates a fake PermissionRequest for testing.
    sdk.PermissionRequest createFakeRequest({
      required String id,
      required Map<String, dynamic> toolInput,
    }) {
      final completer = Completer<sdk.PermissionResponse>();
      return sdk.PermissionRequest(
        id: id,
        sessionId: 'session-1',
        toolName: 'AskUserQuestion',
        toolInput: toolInput,
        completer: completer,
      );
    }

    setUp(() {
      // Single-select question
      singleSelectRequest = createFakeRequest(
        id: 'req-1',
        toolInput: {
          'questions': [
            {
              'question': 'Which database should we use?',
              'header': 'Database',
              'multiSelect': false,
              'options': [
                {'label': 'PostgreSQL', 'description': 'Relational database'},
                {'label': 'MongoDB', 'description': 'Document database'},
                {'label': 'Redis', 'description': 'In-memory store'},
              ],
            },
          ],
        },
      );

      // Multi-select question
      multiSelectRequest = createFakeRequest(
        id: 'req-2',
        toolInput: {
          'questions': [
            {
              'question': 'Which features do you want?',
              'header': 'Features',
              'multiSelect': true,
              'options': [
                {'label': 'Auth', 'description': 'User authentication'},
                {'label': 'API', 'description': 'REST API'},
                {'label': 'Tests', 'description': 'Unit tests'},
              ],
            },
          ],
        },
      );

      // Multiple questions
      multiQuestionRequest = createFakeRequest(
        id: 'req-3',
        toolInput: {
          'questions': [
            {
              'question': 'Choose a framework',
              'header': 'Framework',
              'multiSelect': false,
              'options': [
                {'label': 'React', 'description': 'Frontend library'},
                {'label': 'Vue', 'description': 'Progressive framework'},
              ],
            },
            {
              'question': 'Choose languages',
              'header': 'Languages',
              'multiSelect': true,
              'options': [
                {'label': 'TypeScript', 'description': 'Typed JavaScript'},
                {'label': 'Python', 'description': 'Backend language'},
              ],
            },
          ],
        },
      );
    });

    Widget buildTestWidget(
      sdk.PermissionRequest request,
      void Function(Map<String, String>) onSubmit, {
      VoidCallback? onCancel,
    }) {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AskUserQuestionDialog(
            request: request,
            onSubmit: onSubmit,
            onCancel: onCancel ?? () {},
          ),
        ),
      );
    }

    testWidgets('renders header with question icon', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      expect(find.byKey(AskUserQuestionDialogKeys.header), findsOneWidget);
      expect(find.text('Claude has a question'), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
    });

    testWidgets('renders question text and header badge', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      expect(find.text('Which database should we use?'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
    });

    testWidgets('renders all options as FilterChips', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      expect(find.text('PostgreSQL'), findsOneWidget);
      expect(find.text('MongoDB'), findsOneWidget);
      expect(find.text('Redis'), findsOneWidget);
      expect(find.text('Other...'), findsOneWidget);
    });

    testWidgets('submit button is disabled initially', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      final submitButton = tester.widget<FilledButton>(
        find.byKey(AskUserQuestionDialogKeys.submitButton),
      );
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('single-select: selecting option enables submit',
        (tester) async {
      Map<String, String>? submittedAnswers;
      await tester.pumpWidget(
        buildTestWidget(singleSelectRequest, (answers) {
          submittedAnswers = answers;
        }),
      );

      // Tap PostgreSQL
      await tester.tap(find.text('PostgreSQL'));
      await tester.pump();

      // In single-select mode, selecting an option auto-submits
      // Wait for the post-frame callback
      await tester.pump();

      expect(submittedAnswers, isNotNull);
      expect(
        submittedAnswers!['Which database should we use?'],
        'PostgreSQL',
      );
    });

    testWidgets('multi-select: can select multiple options', (tester) async {
      await tester.pumpWidget(buildTestWidget(multiSelectRequest, (_) {}));

      // Tap Auth and API
      await tester.tap(find.text('Auth'));
      await tester.pump();
      await tester.tap(find.text('API'));
      await tester.pump();

      // Submit button should be enabled
      final submitButton = tester.widget<FilledButton>(
        find.byKey(AskUserQuestionDialogKeys.submitButton),
      );
      expect(submitButton.onPressed, isNotNull);
    });

    testWidgets('multi-select: submits comma-separated values', (tester) async {
      Map<String, String>? submittedAnswers;
      await tester.pumpWidget(
        buildTestWidget(multiSelectRequest, (answers) {
          submittedAnswers = answers;
        }),
      );

      // Select Auth and Tests
      await tester.tap(find.text('Auth'));
      await tester.pump();
      await tester.tap(find.text('Tests'));
      await tester.pump();

      // Tap submit
      await tester.tap(find.byKey(AskUserQuestionDialogKeys.submitButton));
      await tester.pump();

      expect(submittedAnswers, isNotNull);
      // Order depends on Set iteration, so check both options are present
      final answer = submittedAnswers!['Which features do you want?']!;
      expect(answer.contains('Auth'), isTrue);
      expect(answer.contains('Tests'), isTrue);
    });

    testWidgets('Other option shows text input field', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      // Initially no custom input
      expect(find.byKey(AskUserQuestionDialogKeys.customInput), findsNothing);

      // Tap "Other..."
      await tester.tap(find.byKey(AskUserQuestionDialogKeys.otherOption));
      await tester.pump();

      // Custom input should appear
      expect(find.byKey(AskUserQuestionDialogKeys.customInput), findsOneWidget);
    });

    testWidgets('Other option requires text to submit', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      // Tap "Other..."
      await tester.tap(find.byKey(AskUserQuestionDialogKeys.otherOption));
      await tester.pump();

      // Submit should still be disabled (empty text)
      final submitButton = tester.widget<FilledButton>(
        find.byKey(AskUserQuestionDialogKeys.submitButton),
      );
      expect(submitButton.onPressed, isNull);
    });

    testWidgets('Other option submits custom text', (tester) async {
      Map<String, String>? submittedAnswers;
      await tester.pumpWidget(
        buildTestWidget(singleSelectRequest, (answers) {
          submittedAnswers = answers;
        }),
      );

      // Tap "Other..."
      await tester.tap(find.byKey(AskUserQuestionDialogKeys.otherOption));
      await tester.pump();

      // Enter custom text
      await tester.enterText(
        find.byKey(AskUserQuestionDialogKeys.customInput),
        'SQLite',
      );
      await tester.pump();

      // Submit
      await tester.tap(find.byKey(AskUserQuestionDialogKeys.submitButton));
      await tester.pump();

      expect(submittedAnswers, isNotNull);
      expect(submittedAnswers!['Which database should we use?'], 'SQLite');
    });

    testWidgets('multiple questions: all must be answered', (tester) async {
      await tester.pumpWidget(buildTestWidget(multiQuestionRequest, (_) {}));

      // Answer first question only
      await tester.tap(find.text('React'));
      await tester.pump();

      // Submit should still be disabled (second question unanswered)
      var submitButton = tester.widget<FilledButton>(
        find.byKey(AskUserQuestionDialogKeys.submitButton),
      );
      expect(submitButton.onPressed, isNull);

      // Answer second question
      await tester.tap(find.text('TypeScript'));
      await tester.pump();

      // Now submit should be enabled
      submitButton = tester.widget<FilledButton>(
        find.byKey(AskUserQuestionDialogKeys.submitButton),
      );
      expect(submitButton.onPressed, isNotNull);
    });

    testWidgets('multi-select shows badge indicator', (tester) async {
      await tester.pumpWidget(buildTestWidget(multiSelectRequest, (_) {}));

      expect(find.text('multi-select'), findsOneWidget);
    });

    testWidgets('single-select does not show multi-select badge',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      expect(find.text('multi-select'), findsNothing);
    });

    testWidgets('uses themed color scheme from colorScheme', (tester) async {
      await tester.pumpWidget(buildTestWidget(singleSelectRequest, (_) {}));

      // Check header icon uses onPrimaryContainer from theme
      final icon = tester.widget<Icon>(find.byIcon(Icons.help_outline));
      final colorScheme = ThemeData.dark().colorScheme;
      expect(icon.color, colorScheme.onPrimaryContainer);
    });
  });
}
