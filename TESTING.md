# Testing Guidelines

## Golden Rules

1. **Never use `pumpAndSettle()` without timeout** - Use `safePumpAndSettle()` instead
2. **Always clean up resources in `tearDown()`** - Use `TestResources` to track them
3. **Prefer `pumpUntil()` over arbitrary delays** - Wait for conditions, not time

---

## Test Helpers

All helpers are in `flutter_app_v2/test/test_helpers.dart`.

### Pump Helpers

```dart
// NEVER do this - can hang indefinitely:
await tester.pumpAndSettle();

// DO this - 3 second default timeout:
await safePumpAndSettle(tester);

// Wait for specific condition:
await pumpUntil(tester, () => find.text('Done').evaluate().isNotEmpty);

// Shorthand for waiting for widget:
await pumpUntilFound(tester, find.text('Done'));

// Wait for widget to disappear:
await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
```

### Resource Tracking

```dart
void main() {
  final resources = TestResources();

  tearDown(() async {
    await resources.disposeAll();
  });

  test('tracks resources automatically', () {
    final state = resources.track(ChatState());
    final controller = resources.trackStream<String>();
    final subscription = resources.trackSubscription(stream.listen((_) {}));
    // All disposed automatically in tearDown
  });
}
```

---

## Test Structure

### Widget Tests (fast, no device needed)

```dart
// test/widget/my_widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../test_helpers.dart';

void main() {
  final resources = TestResources();

  tearDown(() async {
    await resources.disposeAll();
  });

  testWidgets('description', (tester) async {
    await tester.pumpWidget(MyApp());
    await safePumpAndSettle(tester);

    expect(find.text('Hello'), findsOneWidget);
  });
}
```

### Integration Tests (need device/simulator)

```dart
// integration_test/my_test.dart
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('full flow', (tester) async {
    await tester.pumpWidget(MyApp());
    await pumpUntilFound(tester, find.text('Ready'));

    // Test real interactions...
  });
}
```

---

## Common Patterns

### Testing Async State Changes

```dart
testWidgets('loads data', (tester) async {
  await tester.pumpWidget(MyApp());

  // Wait for loading to complete
  await pumpUntilGone(tester, find.byType(CircularProgressIndicator));

  // Now verify loaded state
  expect(find.text('Data loaded'), findsOneWidget);
});
```

### Testing with Mocks/Fakes

```dart
void main() {
  final resources = TestResources();
  late FakeGitService gitService;

  setUp(() {
    gitService = FakeGitService();
  });

  tearDown(() async {
    await resources.disposeAll();
  });

  testWidgets('shows worktrees', (tester) async {
    gitService.worktrees = [mockWorktree('main'), mockWorktree('feature')];

    await tester.pumpWidget(
      Provider<GitService>.value(
        value: gitService,
        child: MyApp(),
      ),
    );
    await safePumpAndSettle(tester);

    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
  });
}
```

### Testing ChangeNotifier State

```dart
test('updates state correctly', () {
  final resources = TestResources();
  addTearDown(() => resources.disposeAll());

  final state = resources.track(ChatState());

  state.addMessage('Hello');

  expect(state.messages.length, 1);
  expect(state.messages.first.text, 'Hello');
});
```

---

## Debugging Hangs

If a test hangs:

1. **Check for missing `await`** - Especially on `pump*` calls
2. **Check for infinite animations** - Use `safePumpAndSettle` with shorter timeout to expose
3. **Check for undisposed resources** - Use `TestResources` and verify `tearDown` runs
4. **Add debug label to pumpUntil** - See what condition is failing:
   ```dart
   await pumpUntil(
     tester,
     () => someCondition,
     debugLabel: 'waiting for someCondition',
   );
   ```

When `pumpUntil` times out, it automatically calls `debugDumpApp()` and `debugDumpRenderTree()` to help diagnose the issue.

---

## Checklist Before Committing

- [ ] All tests pass locally
- [ ] No `tester.pumpAndSettle()` without timeout (use `safePumpAndSettle`)
- [ ] Resources tracked with `TestResources` and disposed in `tearDown`
- [ ] No arbitrary `Future.delayed()` - use `pumpUntil` instead
- [ ] Integration tests run with `flutter test integration_test -d <device>`
