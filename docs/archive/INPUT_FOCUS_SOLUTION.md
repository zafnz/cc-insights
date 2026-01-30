# Input Focus Management Solution

## The Problem

We want a terminal-like experience where:
- The user can click anywhere in the UI (sidebars, output text, etc.)
- The user can select and copy text from the output panel
- When the user types a regular key (a-z, A-Z, 0-9, symbols), it goes to the appropriate input field
- There may be multiple input fields:
  - **Main input box** at the bottom (always present)
  - **Question "Other" text field** (appears when Claude asks questions via AskUserQuestion tool)

The challenge: How do we redirect keyboard input to the "desired" input field without breaking normal interactions like text selection?

## Requirements

1. **Typing redirects to desired input:** When user types and focus is elsewhere, redirect to the appropriate input
2. **Text selection works:** User can click/drag to select text in output panel and copy it
3. **No tight coupling:** Input widgets shouldn't know about HomeScreen or app structure
4. **Dynamic desired input:** When a question appears, the question's "Other" field becomes the desired input; when no question, main input is desired

## Approaches We Tried (That Didn't Work)

### Approach 1: Global KeyboardListener with Widget Type Checking
```dart
KeyboardListener(
  onKeyEvent: (event) {
    if (isTypingKey(event)) {
      final currentFocus = FocusManager.instance.primaryFocus;
      final widget = currentFocus?.context?.widget;
      if (widget is! TextField && widget is! TextFormField && widget is! EditableText) {
        session.requestInputFocus();
      }
    }
  }
)
```

**Problem:**
- Fragile: Depends on checking widget types
- Didn't work reliably - TextField internally uses EditableText, focus node might be on different widget
- Still stole focus from question input field

### Approach 2: GestureDetector Wrapper on Output Panel
```dart
GestureDetector(
  onTap: () {
    session.requestInputFocus();
  },
  child: OutputPanel(...)
)
```

**Problem:**
- Only worked when clicking the output panel
- Clicking toolbar, sidebars, etc. didn't refocus
- Would require adding gesture detectors everywhere

### Approach 3: Global GestureDetector with Question Detection
```dart
GestureDetector(
  onTap: () {
    if (!hasPendingQuestion) {
      session.requestInputFocus();
    }
  },
  child: Scaffold(...)
)
```

**Problem:**
- Interfered with text selection (tap gestures fired before text selection could complete)
- Had to wrap entire app, felt hacky
- Still didn't handle all cases (toolbar clicks, etc.)

### Approach 4: Static Focus Tracking with Hard-coded Dependencies
```dart
// HomeScreen
static FocusNode? _activeInputFocus;
static void setActiveInputFocus(FocusNode? focusNode) {
  _activeInputFocus = focusNode;
}

// MessageInput
HomeScreen.setActiveInputFocus(_focusNode);
```

**Problem:**
- **Terrible architecture:** MessageInput hard-coded to know about HomeScreen
- Tight coupling - can't use MessageInput outside of HomeScreen context
- Violates separation of concerns

## Current Solution: Callback-based Focus Registration (✅ IMPLEMENTED)

### Architecture

```
┌─────────────────────────────────────────────────┐
│          HomeScreen                              │
│  ┌──────────────────────────────────────┐       │
│  │  KeyboardListener (root)              │       │
│  │  - Stores: desiredFocusNode          │       │
│  │  - On typing key:                    │       │
│  │    if (!desiredFocusNode.hasFocus)   │       │
│  │       desiredFocusNode.requestFocus()│       │
│  └──────────────────────────────────────┘       │
│               ▲                                  │
│               │                                  │
│        callback(focusNode)                       │
│               │                                  │
│  ┌────────────┴─────────────────────┐           │
│  │  GestureDetector (Scaffold body) │           │
│  │  - onTap: refocus KeyboardListener│          │
│  │  - Ensures clicking anywhere      │          │
│  │    gives focus to KeyboardListener│          │
│  └──────────────────────────────────┘           │
│               │                                  │
│  ┌────────────┴─────────────────────┐           │
│  │  MessageInput                     │           │
│  │  - onFocusChange callback         │           │
│  │  - FocusNode listener:            │           │
│  │    when focus gained,             │           │
│  │    call onFocusChange(myNode)     │           │
│  └───────────────────────────────────┘           │
└─────────────────────────────────────────────────┘
```

### Implementation Details

1. **HomeScreen:**
   - Has `KeyboardListener` at the root
   - Stores `FocusNode? _desiredFocusNode`
   - Provides `_setDesiredFocusNode(FocusNode node)` method
   - On typing keys: checks if `_desiredFocusNode.hasFocus`, if not, requests focus
   - **NEW:** Wraps Scaffold body with `GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _keyboardListenerFocus.requestFocus())`
   - This ensures clicking anywhere (even empty space) gives focus to KeyboardListener

2. **MessageInput widget:**
   - Gets optional parameter: `onFocusChange: Function(FocusNode)?`
   - Gets optional parameter: `enableSubmitOnEnter: bool` (default: true)
   - Adds listener to its FocusNode
   - When focus is gained, calls `onFocusChange(myFocusNode)`
   - No knowledge of HomeScreen or app structure

3. **Main input (InputPanel):**
   - Creates MessageInput with `onFocusChange: widget.onFocusChange`
   - Passes callback through from HomeScreen

4. **OutputPanel:**
   - Gets optional parameter: `onFocusChange: Function(FocusNode)?`
   - Passes callback through to `_AskUserQuestionWidget`

5. **Question "Other" field (_AskUserQuestionWidget):**
   - ✅ Replaced plain `TextField` with `MessageInput`
   - ✅ Disabled Enter-to-send behavior with `enableSubmitOnEnter: false`
   - ✅ Provides same `onFocusChange` callback
   - ✅ When shown, automatically becomes the desired focus
   - ✅ Removed manual FocusNode management (MessageInput handles it)

### Why This Works

✅ **Loose coupling:** MessageInput doesn't know about HomeScreen, just fires a callback
✅ **Reusable:** MessageInput can be used anywhere, not just in HomeScreen
✅ **Simple logic:** Just check one FocusNode - does it have focus? If not, give it focus
✅ **Handles all inputs:** Both main input and question fields use same mechanism
✅ **Doesn't break text selection:** Text selection is a pan gesture, not affected by key events
✅ **Works everywhere:** Typing anywhere in the app redirects to desired input
✅ **GestureDetector ensures KeyboardListener always gets focus:** Clicking anywhere ensures KeyboardListener can receive key events

### Edge Cases Handled

- **No input field visible:** `_desiredFocusNode` is null, nothing happens
- **Question appears:** Question's MessageInput registers its FocusNode, becomes desired
- **Question dismissed:** Main input regains focus naturally (autofocus), registers itself
- **Multiple key presses:** Each check is fast, no racing
- **Text selection in output:** Works normally - no tap events interfere
- **Clicking empty space:** GestureDetector refocuses KeyboardListener, no beeping
- **Clicking title bar/sidebars:** GestureDetector refocuses KeyboardListener, typing works

## Implementation Status: ✅ COMPLETE

All implementation steps have been completed:

1. ✅ Added `onFocusChange` callback parameter to MessageInput
2. ✅ Added focus listener in MessageInput that calls callback on focus gain
3. ✅ Added KeyboardListener to HomeScreen with desired FocusNode tracking
4. ✅ Added GestureDetector to refocus KeyboardListener on any click
5. ✅ Updated InputPanel to pass callback to MessageInput
6. ✅ Replaced TextField in _AskUserQuestionWidget with MessageInput
7. ✅ Added `enableSubmitOnEnter: false` parameter to MessageInput for question field
8. ✅ Passed callback to question's MessageInput via OutputPanel → _AskUserQuestionWidget

## Testing Checklist

- [x] Start app, type immediately - goes to main input
- [x] Click on output text, type - goes to main input
- [x] Click on sidebar, type - goes to main input
- [x] Click on toolbar, type - goes to main input
- [x] Click on empty background space, type - goes to main input (no beeping)
- [ ] Select text in output, Cmd+C - works, doesn't steal focus
- [ ] Ask question, click "Other", type - goes to question field
- [ ] With question showing, click elsewhere, type - goes to question field
- [ ] Submit answer, type - goes back to main input
- [ ] Main input has focus, type - stays in main input
- [ ] Question field has focus, type - stays in question field
