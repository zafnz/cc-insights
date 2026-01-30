# SuperSliverList Implementation Plan

## Overview

Replace `ListView.builder` in `ConversationPanel` with `SuperListView` from the `super_sliver_list` package to solve scroll position preservation issues when switching between conversations.

**Problem Summary**: With `ListView.builder`, lazy loading prevents accurate scroll position restoration because `maxScrollExtent` is unknown until items are built. This causes scroll positions to reset when switching conversations.

**Solution**: SuperSliverList estimates item extents for unbuilt items and provides a `ListController` with `jumpToItem()` for index-based positioning, making scroll restoration reliable.

---

## Goals

1. **Preserve scroll position** when switching between conversations (primary goal)
2. **Maintain auto-scroll-to-bottom** behavior when new entries arrive (if user was at bottom)
3. **Keep existing scroll behavior** when user scrolls up (content stays in place)
4. **Minimal breaking changes** to existing API and behavior

---

## Implementation Strategy

### 1. Index-Based Position Tracking

Instead of tracking pixel positions or fractions, track:
- **Visible item index** at the top of the viewport when switching away
- **Scroll offset** within that item (for fine positioning)

When switching back:
- Use `ListController.jumpToItem(index)` to restore position
- SuperSliverList handles extent estimation automatically

### 2. State Management

Add to `_ConversationPanelState`:
```dart
/// Map: conversationId -> ScrollPosition
final Map<String, _ScrollPosition> _savedScrollPositions = {};

class _ScrollPosition {
  final int topVisibleIndex;   // Index of item at top of viewport
  final double offsetInItem;   // Pixels scrolled within that item
  final bool wasAtBottom;      // Was user at bottom when switching away

  _ScrollPosition({
    required this.topVisibleIndex,
    required this.offsetInItem,
    required this.wasAtBottom,
  });
}
```

### 3. SuperSliverList Controller

Replace `ScrollController` with both `ScrollController` and `ListController`:
```dart
final ScrollController _scrollController = ScrollController();
final ListController _listController = ListController();
```

The `ListController` provides:
- `jumpToItem(index, scrollController, alignment)`
- `animateToItem(index, scrollController, alignment, duration, curve)`
- Extent estimation for unbuilt items

---

## Implementation Steps

### Phase 1: Add Package Dependency

**File**: `flutter_app_v2/pubspec.yaml`

Add to dependencies:
```yaml
super_sliver_list: ^0.4.1
```

Run: `flutter pub get`

### Phase 2: Update ConversationPanel

**File**: `flutter_app_v2/lib/panels/conversation_panel.dart`

#### 2.1 Add imports and state

```dart
import 'package:super_sliver_list/super_sliver_list.dart';

// Add to _ConversationPanelState:
final ListController _listController = ListController();

/// Saved scroll positions indexed by conversation ID
final Map<String, _ScrollPosition> _savedScrollPositions = {};
```

#### 2.2 Define _ScrollPosition class

```dart
/// Represents a saved scroll position in a conversation list.
class _ScrollPosition {
  final int topVisibleIndex;
  final double offsetInItem;
  final bool wasAtBottom;

  _ScrollPosition({
    required this.topVisibleIndex,
    required this.offsetInItem,
    required this.wasAtBottom,
  });
}
```

#### 2.3 Save scroll position on conversation switch

Update the conversation switch detection block:
```dart
// Handle conversation switching
if (conversation?.id != _previousConversationId) {
  // Save old conversation's scroll position (if any)
  if (_previousConversationId != null && _scrollController.hasClients) {
    _saveScrollPosition(_previousConversationId!);
  }

  _previousConversationId = conversation?.id;
  _lastEntryCount = conversation?.entries.length ?? 0;
  _isAtBottom = true;

  // Restore saved position (if any)
  if (conversation != null && _savedScrollPositions.containsKey(conversation.id)) {
    _scheduleScrollRestore(conversation.id);
  } else {
    _scheduleScrollToBottom();
  }
}
```

#### 2.4 Implement _saveScrollPosition()

```dart
/// Saves the current scroll position for the given conversation ID.
void _saveScrollPosition(String conversationId) {
  if (!_scrollController.hasClients) return;

  final position = _scrollController.position;
  final wasAtBottom = position.pixels >= position.maxScrollExtent - 50;

  // Calculate which item is at the top of the viewport
  // This requires knowing the item heights, which SuperSliverList tracks
  final listState = _listController.sliverController;

  // Get the first visible index and its offset
  final firstVisible = listState?.visibleRange?.firstItem ?? 0;
  final offsetInItem = position.pixels - (listState?.offsetForIndex(firstVisible) ?? 0);

  _savedScrollPositions[conversationId] = _ScrollPosition(
    topVisibleIndex: firstVisible,
    offsetInItem: offsetInItem.clamp(0.0, double.infinity),
    wasAtBottom: wasAtBottom,
  );

  developer.log(
    'Saved scroll position for conversation $conversationId: '
    'index=$firstVisible, offset=${offsetInItem.toStringAsFixed(1)}, '
    'wasAtBottom=$wasAtBottom',
    name: 'ConversationPanel',
  );
}
```

#### 2.5 Implement _scheduleScrollRestore()

```dart
/// Schedules restoration of a saved scroll position after layout.
void _scheduleScrollRestore(String conversationId) {
  final saved = _savedScrollPositions[conversationId];
  if (saved == null) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scrollController.hasClients) return;

    if (saved.wasAtBottom) {
      // User was at bottom - scroll to bottom
      _scrollToBottom();
    } else {
      // Restore to saved index + offset
      _listController.jumpToItem(
        index: saved.topVisibleIndex,
        scrollController: _scrollController,
        alignment: 0.0, // Top of viewport
      );

      // Fine-tune with the offset within the item
      if (saved.offsetInItem > 0) {
        _scrollController.jumpTo(
          _scrollController.position.pixels + saved.offsetInItem,
        );
      }
    }

    developer.log(
      'Restored scroll position for conversation $conversationId',
      name: 'ConversationPanel',
    );
  });
}
```

#### 2.6 Replace ListView.builder with SuperListView

Update `_buildEntryList()`:
```dart
Widget _buildEntryList(
  ConversationData conversation, {
  bool showWorkingIndicator = false,
}) {
  final entries = conversation.entries;
  final selection = context.read<SelectionState>();
  final projectDir = selection.selectedChat?.data.worktreeRoot;
  final isSubagent = !conversation.isPrimary;

  final itemCount = entries.length + (showWorkingIndicator ? 1 : 0);

  return SuperListView.builder(
    controller: _scrollController,
    listController: _listController,
    padding: const EdgeInsets.all(8),
    itemCount: itemCount,
    itemBuilder: (context, index) {
      if (showWorkingIndicator && index == entries.length) {
        return const WorkingIndicator();
      }

      final entry = entries[index];
      return OutputEntryWidget(
        entry: entry,
        projectDir: projectDir,
        isSubagent: isSubagent,
      );
    },
  );
}
```

#### 2.7 Update dispose()

```dart
@override
void dispose() {
  _scrollController.removeListener(_onScroll);
  _permissionAnimController.dispose();
  _scrollController.dispose();
  _listController.dispose(); // Add this
  _listeningToChat?.removeListener(_onChatChanged);
  super.dispose();
}
```

### Phase 3: Testing

#### 3.1 Manual Testing Checklist

- [ ] Create a long conversation (100+ entries)
- [ ] Scroll to bottom - verify auto-scroll on new entries works
- [ ] Scroll to middle - verify content stays in place when new entries arrive
- [ ] Scroll to position 50% - switch away - switch back - verify position restored
- [ ] Scroll to bottom - switch away - switch back - verify still at bottom
- [ ] Scroll to top - switch away - switch back - verify still at top
- [ ] Create multiple conversations and switch between them rapidly
- [ ] Verify no crashes or rendering glitches

#### 3.2 Unit Tests

Add tests to `flutter_app_v2/test/widget/conversation_panel_test.dart`:

```dart
testWidgets('preserves scroll position when switching conversations', (tester) async {
  // Create two conversations with many entries
  // Scroll first conversation to middle
  // Switch to second conversation
  // Switch back to first conversation
  // Verify scroll position is at middle
});

testWidgets('restores to bottom when user was at bottom', (tester) async {
  // Create conversation, scroll to bottom
  // Switch away and back
  // Verify still at bottom
});

testWidgets('uses index-based restoration for middle positions', (tester) async {
  // Create conversation with 100 entries
  // Scroll to entry #42
  // Switch away and back
  // Verify entry #42 is still visible at same position
});
```

### Phase 4: Extent Estimation (Optional Enhancement)

If default extent estimation is inaccurate, provide a custom estimator:

```dart
SuperListView.builder(
  controller: _scrollController,
  listController: _listController,
  padding: const EdgeInsets.all(8),
  itemCount: itemCount,
  itemBuilder: (context, index) { /* ... */ },
  extentEstimation: (index, dimensions) {
    // Estimate height based on entry type
    final entry = entries[index];
    if (entry is UserInputEntry) {
      return 80.0; // Typical user input height
    } else if (entry is ToolUseEntry) {
      return 120.0; // Typical tool card height
    } else if (entry is TextOutputEntry) {
      // Estimate based on text length
      return 60.0 + (entry.text.length / 80) * 20;
    }
    return 100.0; // Default
  },
);
```

---

## Edge Cases & Considerations

### 1. Empty Conversations
- When conversation has 0 entries, no position to save
- Handle gracefully by checking `itemCount > 0` before saving

### 2. Conversation Growth
- Saved index might be > new item count if entries were deleted
- Clamp index: `saved.topVisibleIndex.clamp(0, itemCount - 1)`

### 3. Fast Switching
- User switches conversations rapidly before layout completes
- Cancel pending scroll restoration if conversation changes again
- Use `mounted` check in postFrameCallback

### 4. Memory Management
- `_savedScrollPositions` grows unbounded as conversations are viewed
- Consider LRU cache with max size (e.g., 20 conversations)
- Or clear positions when chat is closed/deleted

### 5. Animation Conflicts
- Auto-scroll animation might conflict with position restoration
- Ensure only one scroll operation happens per frame

---

## Rollback Plan

If SuperSliverList causes issues:

1. Remove `super_sliver_list` from `pubspec.yaml`
2. Revert `conversation_panel.dart` to use `ListView.builder`
3. Fallback to saving `wasAtBottom` flag only (existing behavior)

The changes are localized to one file, making rollback straightforward.

---

## Success Criteria

1. ✅ Scroll position preserved when switching between conversations
2. ✅ Auto-scroll to bottom still works when user is at bottom
3. ✅ Content stays in place when user scrolls up (no jumps)
4. ✅ No performance degradation (SuperSliverList should improve performance)
5. ✅ No visual glitches or crashes
6. ✅ All existing tests pass
7. ✅ New tests added for scroll restoration behavior

---

## Timeline Estimate

- **Phase 1** (Add dependency): 5 minutes
- **Phase 2** (Update ConversationPanel): 1-2 hours
- **Phase 3** (Testing): 30-60 minutes
- **Phase 4** (Optional tuning): 30 minutes

**Total**: ~2-3 hours for core implementation + testing

---

## References

- **Package**: https://github.com/superlistapp/super_sliver_list
- **API Docs**: https://pub.dev/documentation/super_sliver_list/latest/
- **Issue**: `docs/scrolling-issue.md`
- **Current Code**: `flutter_app_v2/lib/panels/conversation_panel.dart:331-349`
