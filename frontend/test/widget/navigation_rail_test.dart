import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:cc_insights_v2/widgets/navigation_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late TicketBoardState ticketBoardState;

  setUp(() {
    ticketBoardState = TicketBoardState('test-project');
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  Widget createTestApp({
    int selectedIndex = 0,
    required ValueChanged<int> onDestinationSelected,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<TicketBoardState>.value(
          value: ticketBoardState,
          child: AppNavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
          ),
        ),
      ),
    );
  }

  testWidgets('Tickets button exists in nav rail', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        onDestinationSelected: (_) {},
      ),
    );
    await safePumpAndSettle(tester);

    final ticketsButton = find.byTooltip('Tickets');
    expect(ticketsButton, findsOneWidget);
  });

  testWidgets('tapping Tickets button calls onDestinationSelected with index 4', (tester) async {
    int? selectedIndex;

    await tester.pumpWidget(
      createTestApp(
        onDestinationSelected: (index) {
          selectedIndex = index;
        },
      ),
    );
    await safePumpAndSettle(tester);

    final ticketsButton = find.byTooltip('Tickets');
    expect(ticketsButton, findsOneWidget);

    await tester.tap(ticketsButton);
    await safePumpAndSettle(tester);

    expect(selectedIndex, equals(4));
  });

  testWidgets('renders project stats button at index 5', (tester) async {
    await tester.pumpWidget(
      createTestApp(
        onDestinationSelected: (_) {},
      ),
    );
    await safePumpAndSettle(tester);

    final statsButton = find.byTooltip('Project Stats');
    expect(statsButton, findsOneWidget);
  });

  testWidgets('tapping stats button calls onDestinationSelected with 5',
      (tester) async {
    int? selectedIndex;

    await tester.pumpWidget(
      createTestApp(
        onDestinationSelected: (index) {
          selectedIndex = index;
        },
      ),
    );
    await safePumpAndSettle(tester);

    await tester.tap(find.byTooltip('Project Stats'));
    await tester.pump();

    expect(selectedIndex, equals(5));
  });

  testWidgets('stats button shows selected state when index is 5',
      (tester) async {
    await tester.pumpWidget(
      createTestApp(
        selectedIndex: 5,
        onDestinationSelected: (_) {},
      ),
    );
    await safePumpAndSettle(tester);

    final statsButton = find.byTooltip('Project Stats');
    expect(statsButton, findsOneWidget);
  });
}
