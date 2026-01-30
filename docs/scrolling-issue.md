## Problem Description

**When switching between conversations (chats), the scroll position is not preserved.** Specifically:

- User is viewing a long conversation and is at the bottom
- User switches to another conversation
- User switches back to the original conversation
- **Expected**: User should still be at the bottom
- **Actual**: User is at the top (position 0)

This is particularly noticeable with long conversations that have many entries.

---

## Root Cause

`ListView.builder` uses **lazy loading** - it only builds widgets that are currently visible. This means:

1. `maxScrollExtent` is not the "true" full extent of the list - it grows as you scroll down and more items are built
2. When you switch away and back, the ListView is rebuilt fresh, starting with a small `maxScrollExtent`
3. Any saved pixel position becomes meaningless because the extent has changed

---

## Attempted Solutions (All Failed)

### Attempt 1: Save absolute pixel position
```dart
_savedScrollPositions[conversationId] = position.pixels;
// Restore:
_scrollController.jumpTo(savedPosition.clamp(0, maxScrollExtent));
```
**Why it failed**: With lazy loading, `maxScrollExtent` starts small when you switch back. If you saved position 5000 but maxScrollExtent is only 500, it clamps to 500.

### Attempt 2: Save pixel position + wasAtBottom flag
```dart
_savedScrollStates[id] = (pixels: position.pixels, wasAtBottom: wasAtBottom);
// Restore: if wasAtBottom, scroll to bottom; else jumpTo(savedPixels)
```
**Why it failed**: Same clamping issue for non-bottom positions.

### Attempt 3: Save as fraction (0.0-1.0) of maxScrollExtent
```dart
final fraction = position.pixels / position.maxScrollExtent;
// Restore:
_scrollController.jumpTo(fraction * newMaxScrollExtent);
```
**Why it failed**: The fraction is relative to the *current* `maxScrollExtent` at save time, which was large (because items were built). But on restore, `maxScrollExtent` starts small, so `0.9 * 500 = 450` instead of `0.9 * 5000 = 4500`.

### Attempt 4: Iterative fraction restoration (multiple frames)
```dart
void _restoreScrollFraction(double fraction, {int attempts = 0}) {
  // Jump to fraction * maxScrollExtent
  // Wait for next frame, check if maxScrollExtent grew
  // If so, try again (up to 10 times)
}
```
**Why it failed**: `maxScrollExtent` only grows when you scroll down (triggering more items to build). Just waiting frames doesn't cause it to grow.

### Attempt 5: Just save wasAtBottom flag, don't try to restore exact position
```dart
_wasAtBottom[id] = wasAtBottom;
// Restore: if wasAtBottom, scroll to bottom; else don't scroll (stay at top)
```
**Why it failed**: `_scheduleScrollToBottom()` uses `jumpTo(maxScrollExtent)`, but `maxScrollExtent` is small initially due to lazy loading, so it doesn't actually scroll to the true bottom.

---

## The Core Issue

The `_scheduleScrollToBottom()` method:
```dart
void _scheduleScrollToBottom() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  });
}
```

This jumps to `maxScrollExtent`, but with lazy loading, `maxScrollExtent` after one frame is NOT the true bottom of a long list - it's just however much has been built so far.
