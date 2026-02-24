import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/author_service.dart' hide AuthorType;
import 'package:cc_insights_v2/services/runtime_config.dart';
import 'package:cc_insights_v2/widgets/markdown_renderer.dart';
import 'package:cc_insights_v2/widgets/ticket_comment_block.dart';
import 'package:cc_insights_v2/widgets/ticket_comment_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in MaterialApp > Scaffold for testing.
Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

/// Creates a minimal [TicketData] for TicketCommentInput tests.
TicketData _ticket({bool isOpen = true}) {
  final now = DateTime(2024, 6, 15, 12, 0);
  return TicketData(
    id: 1,
    title: 'Test ticket',
    body: 'Body',
    author: 'zaf',
    isOpen: isOpen,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUp(() {
    RuntimeConfig.resetForTesting();
    AuthorService.setForTesting('testuser');
  });

  tearDown(() {
    AuthorService.resetForTesting();
  });

  // =========================================================================
  // TicketCommentBlock tests
  // =========================================================================
  group('TicketCommentBlock', () {
    group('author display', () {
      testWidgets('shows author name', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'alice',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('alice'), findsOneWidget);
      });

      testWidgets('shows avatar with first letter of author name',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'bob',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        // Avatar shows uppercase first letter.
        expect(find.text('B'), findsOneWidget);
      });

      testWidgets('avatar shows "?" for empty author', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: '',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('?'), findsOneWidget);
      });

      testWidgets('avatar uses CircleAvatar', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.byType(CircleAvatar), findsOneWidget);
      });
    });

    group('badges', () {
      testWidgets('shows agent badge for agent authors', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'agent auth-bot',
          authorType: AuthorType.agent,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'I fixed the bug.',
        )));

        expect(find.text('agent'), findsOneWidget);
      });

      testWidgets('does not show agent badge for user authors',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('agent'), findsNothing);
      });

      testWidgets('shows Owner badge when author matches ticketAuthor',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          ticketAuthor: 'zaf',
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('Owner'), findsOneWidget);
      });

      testWidgets('does not show Owner badge when author differs from ticketAuthor',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'alice',
          authorType: AuthorType.user,
          ticketAuthor: 'zaf',
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('Owner'), findsNothing);
      });

      testWidgets('does not show Owner badge when ticketAuthor is null',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('Owner'), findsNothing);
      });

      testWidgets('agent author can also be ticket owner', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'agent auth-bot',
          authorType: AuthorType.agent,
          ticketAuthor: 'agent auth-bot',
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Auto-fix applied.',
        )));

        expect(find.text('agent'), findsOneWidget);
        expect(find.text('Owner'), findsOneWidget);
      });
    });

    group('markdown content', () {
      testWidgets('renders MarkdownRenderer with content', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Hello world',
        )));

        final renderer = tester.widget<MarkdownRenderer>(
          find.byType(MarkdownRenderer),
        );
        expect(renderer.data, 'Hello world');
      });

      testWidgets('empty markdown content hides MarkdownRenderer',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: '',
        )));

        expect(find.byType(MarkdownRenderer), findsNothing);
      });
    });

    group('images', () {
      testWidgets('shows broken image icon for non-existent image files',
          (tester) async {
        final images = [
          TicketImage(
            id: 'img1',
            fileName: 'screenshot.png',
            relativePath: '/non/existent/path/screenshot.png',
            mimeType: 'image/png',
            createdAt: DateTime(2024, 6, 15),
          ),
        ];

        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'See attached',
          images: images,
        )));

        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      });

      testWidgets('renders multiple image thumbnails', (tester) async {
        final images = [
          TicketImage(
            id: 'img1',
            fileName: 'a.png',
            relativePath: '/no/a.png',
            mimeType: 'image/png',
            createdAt: DateTime(2024, 6, 15),
          ),
          TicketImage(
            id: 'img2',
            fileName: 'b.png',
            relativePath: '/no/b.png',
            mimeType: 'image/png',
            createdAt: DateTime(2024, 6, 15),
          ),
        ];

        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Screenshots',
          images: images,
        )));

        expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(2));
      });

      testWidgets('no image section when images list is empty',
          (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'No images',
        )));

        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      });

      testWidgets('image thumbnail has correct size', (tester) async {
        final images = [
          TicketImage(
            id: 'img1',
            fileName: 'a.png',
            relativePath: '/no/a.png',
            mimeType: 'image/png',
            createdAt: DateTime(2024, 6, 15),
          ),
        ];

        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 15, 14, 30),
          markdownContent: 'Image',
          images: images,
        )));

        // Thumbnail containers are 120x90.
        final containers = tester.widgetList<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.constraints?.maxWidth == 120 &&
                w.constraints?.maxHeight == 90,
          ),
        );
        expect(containers, isNotEmpty);
      });
    });

    group('timestamp formatting', () {
      testWidgets('different year shows "d MMM yyyy"', (tester) async {
        await tester.pumpWidget(_wrap(TicketCommentBlock(
          author: 'zaf',
          authorType: AuthorType.user,
          timestamp: DateTime(2024, 6, 22, 14, 30),
          markdownContent: 'Hello',
        )));

        expect(find.text('22 Jun 2024'), findsOneWidget);
      });

      testWidgets('different month/day same year shows "d MMM"',
          (tester) async {
        // Use a date in the current year but far enough in the future to not be today.
        final now = DateTime.now();
        // Pick a date in the same year but a different month (at least 2 months ahead).
        final ts = DateTime(now.year, (now.month + 6 - 1) % 12 + 1, 15, 14, 30);

        // Only test if this date is not today.
        if (ts.day != now.day || ts.month != now.month) {
          await tester.pumpWidget(_wrap(TicketCommentBlock(
            author: 'zaf',
            authorType: AuthorType.user,
            timestamp: ts,
            markdownContent: 'Hello',
          )));

          // Should NOT contain the year.
          expect(find.textContaining('${ts.year}'), findsNothing);
          // Should contain the day number.
          expect(find.textContaining('15'), findsWidgets);
        }
      });
    });
  });

  // =========================================================================
  // TicketCommentInput tests
  // =========================================================================
  group('TicketCommentInput', () {
    testWidgets('renders text field with hint', (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Leave a comment...'), findsOneWidget);
    });

    testWidgets('shows "Add a comment" header', (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      expect(find.text('Add a comment'), findsOneWidget);
    });

    testWidgets('Comment button is disabled when text is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('Comment button enables after typing text', (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      await tester.enterText(find.byType(TextField), 'my comment');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Comment button calls onComment with trimmed text',
        (tester) async {
      String? captured;
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (text) => captured = text,
        onToggleStatus: () {},
      )));

      await tester.enterText(find.byType(TextField), '  hello world  ');
      await tester.pump();
      await tester.tap(find.text('Comment'));
      await tester.pump();

      expect(captured, 'hello world');
    });

    testWidgets('Comment button clears text field after submission',
        (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      await tester.enterText(find.byType(TextField), 'my comment');
      await tester.pump();
      await tester.tap(find.text('Comment'));
      await tester.pump();

      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text, isEmpty);
    });

    testWidgets('shows "Close ticket" for open tickets', (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: true),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      expect(find.text('Close ticket'), findsOneWidget);
      expect(find.text('Reopen ticket'), findsNothing);
    });

    testWidgets('shows "Reopen ticket" for closed tickets', (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: false),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      expect(find.text('Reopen ticket'), findsOneWidget);
      expect(find.text('Close ticket'), findsNothing);
    });

    testWidgets('Close ticket calls onToggleStatus', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: true),
        onComment: (_) {},
        onToggleStatus: () => toggled = true,
      )));

      await tester.tap(find.text('Close ticket'));
      await tester.pump();

      expect(toggled, isTrue);
    });

    testWidgets('Reopen ticket calls onToggleStatus', (tester) async {
      var toggled = false;
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: false),
        onComment: (_) {},
        onToggleStatus: () => toggled = true,
      )));

      await tester.tap(find.text('Reopen ticket'));
      await tester.pump();

      expect(toggled, isTrue);
    });

    testWidgets(
        'Close with comment: sends comment text then toggles status',
        (tester) async {
      String? capturedText;
      var toggled = false;

      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: true),
        onComment: (text) => capturedText = text,
        onToggleStatus: () => toggled = true,
      )));

      // Type a comment, then tap Close ticket.
      await tester.enterText(find.byType(TextField), 'closing note');
      await tester.pump();
      await tester.tap(find.text('Close ticket'));
      await tester.pump();

      // Both callbacks should fire.
      expect(capturedText, 'closing note');
      expect(toggled, isTrue);
    });

    testWidgets(
        'Close without comment: only toggles status, no comment callback',
        (tester) async {
      String? capturedText;
      var toggled = false;

      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(isOpen: true),
        onComment: (text) => capturedText = text,
        onToggleStatus: () => toggled = true,
      )));

      // Don't type anything, just close.
      await tester.tap(find.text('Close ticket'));
      await tester.pump();

      expect(capturedText, isNull);
      expect(toggled, isTrue);
    });

    testWidgets('shows user avatar initial in header', (tester) async {
      AuthorService.setForTesting('alice');

      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      // Avatar shows 'A' for 'alice'.
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('Comment button is disabled for whitespace-only input',
        (tester) async {
      await tester.pumpWidget(_wrap(TicketCommentInput(
        ticket: _ticket(),
        onComment: (_) {},
        onToggleStatus: () {},
      )));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
