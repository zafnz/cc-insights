import 'package:cc_insights_v2/services/menu_action_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MenuActionService', () {
    test('MenuAction.showStats exists in enum', () {
      // Verify the enum value exists and can be referenced
      const action = MenuAction.showStats;
      check(action).equals(MenuAction.showStats);
    });

    test('triggerAction sets showStats as lastAction', () {
      final service = MenuActionService();

      service.triggerAction(MenuAction.showStats);

      check(service.lastAction).equals(MenuAction.showStats);
    });

    test('clearAction removes showStats action', () {
      final service = MenuActionService();

      service.triggerAction(MenuAction.showStats);
      check(service.lastAction).equals(MenuAction.showStats);

      service.clearAction();
      check(service.lastAction).isNull();
    });
  });
}
