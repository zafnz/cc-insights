# Image Pasting Support

## Overview

Add support for pasting images into the input panel and sending them to Claude along with text messages.

## How Images Work in Claude Agent SDK

The SDK supports images via the Anthropic Messages API. User messages can contain either a plain string or an array of content blocks:

```typescript
// SDKUserMessage.message uses APIUserMessage from @anthropic-ai/sdk
{
  role: 'user',
  content: string | ContentBlock[]  // Can be text OR array of blocks
}

// Image content block structure
{
  type: 'image',
  source: {
    type: 'base64',
    media_type: 'image/png',  // Also: image/jpeg, image/gif, image/webp
    data: 'base64-encoded-image-data...'
  }
}
```

**Reference:** Python SDK docs show `UserMessage.content: str | list[ContentBlock]` (docs/sdk/python-sdk.md:907-909). The TypeScript SDK references `APIUserMessage` from the base Anthropic SDK.

**Note:** Streaming input mode is required for sending images - single message mode doesn't support them. Our backend already uses streaming input mode via `MessageQueue`.

## Current State

The Dart SDK already has types for images in `dart_sdk/lib/src/types/content_blocks.dart`:

```dart
class ImageBlock extends ContentBlock {
  final ImageSource source;
}

class ImageSource {
  final String type;       // 'base64' or 'url'
  final String? mediaType; // e.g., 'image/png'
  final String? data;      // Base64 encoded image data
  final String? url;       // Image URL (alternative to base64)
}
```

**Gap:** The protocol only supports string messages:

```typescript
// backend-node/src/protocol.ts
export interface SessionSendMessage {
  payload: {
    message: string;  // ← Only string, not content blocks
  };
}
```

## Implementation Plan

### 1. Backend Protocol (backend-node/src/protocol.ts)

Extend `SessionSendMessage` to support content blocks:

```typescript
// Define content block types
export interface TextContentBlock {
  type: 'text';
  text: string;
}

export interface ImageContentBlock {
  type: 'image';
  source: {
    type: 'base64' | 'url';
    media_type?: string;
    data?: string;
    url?: string;
  };
}

export type ContentBlock = TextContentBlock | ImageContentBlock;

export interface SessionSendMessage {
  type: "session.send";
  id: string;
  session_id: string;
  payload: {
    message: string | ContentBlock[];  // Allow array of content blocks
  };
}
```

### 2. Session Manager (backend-node/src/session-manager.ts)

Update `sendMessage()` to handle content blocks (minimal change - just pass through):

```typescript
private async sendMessage(msg: SessionSendMessage): Promise<void> {
  // ... existing validation ...

  const userMessage: SDKUserMessage = {
    type: "user",
    message: {
      role: "user",
      content: msg.payload.message,  // Already works if array is passed
    },
    parent_tool_use_id: null,
    session_id: msg.session_id,
  };

  session.messageQueue.push(userMessage);
}
```

### 3. Dart SDK Protocol (dart_sdk/lib/src/protocol.dart)

Add method to send content blocks:

```dart
Future<void> _sendContentToSession(
  String sessionId,
  List<ContentBlock> content,
) async {
  final message = {
    'type': 'session.send',
    'id': _generateId(),
    'session_id': sessionId,
    'payload': {
      'message': content.map((b) => b.toJson()).toList(),
    },
  };
  _sendMessage(message);
}
```

### 4. Dart SDK Session (dart_sdk/lib/src/session.dart)

Add public method:

```dart
/// Send a message with mixed content (text and images).
Future<void> sendContent(List<ContentBlock> content) async {
  if (_disposed) return;
  await _backend._sendContentToSession(sessionId, content);
}
```

### 5. Flutter App - Input Panel (flutter_app/lib/widgets/input_panel.dart)

Add paste handling for images:

```dart
// In the input widget, handle paste events
KeyboardListener(
  onKeyEvent: (event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isMetaPressed) {
      _handlePaste();
    }
  },
  child: // ... existing input field
)

Future<void> _handlePaste() async {
  // Check for image in clipboard
  final imageBytes = await _getClipboardImage();
  if (imageBytes != null) {
    setState(() {
      _pendingImages.add(imageBytes);
    });
  }
}

Future<void> _sendMessage() async {
  final text = _controller.text;

  if (_pendingImages.isEmpty) {
    // Text only - use existing send()
    await session.send(text);
  } else {
    // Mixed content - use sendContent()
    final content = <ContentBlock>[
      if (text.isNotEmpty) TextBlock(text: text),
      for (final imageBytes in _pendingImages)
        ImageBlock(
          source: ImageSource(
            type: 'base64',
            mediaType: 'image/png',
            data: base64Encode(imageBytes),
          ),
        ),
    ];
    await session.sendContent(content);
    _pendingImages.clear();
  }

  _controller.clear();
}
```

### 6. Clipboard Image Access

Flutter doesn't have built-in image clipboard support. Options:

1. **Platform channels** - Write native macOS code to read NSPasteboard
2. **Package** - Use `pasteboard` or `super_clipboard` package
3. **File drop** - Support drag-and-drop as alternative/addition

Example with `super_clipboard` package:

```dart
import 'package:super_clipboard/super_clipboard.dart';

Future<Uint8List?> _getClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  final reader = await clipboard.read();

  if (reader.canProvide(Formats.png)) {
    final data = await reader.readValue(Formats.png);
    return data;
  }
  return null;
}
```

### 7. UI for Pending Images

Show thumbnails of pasted images before sending:

```dart
// In input panel build method
Column(
  children: [
    if (_pendingImages.isNotEmpty)
      _buildImagePreviewRow(),
    _buildTextInput(),
  ],
)

Widget _buildImagePreviewRow() {
  return SizedBox(
    height: 60,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _pendingImages.length,
      itemBuilder: (context, index) {
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                _pendingImages[index],
                height: 52,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => _removeImage(index),
              ),
            ),
          ],
        );
      },
    ),
  );
}
```

## Testing

1. Paste an image with `Cmd+V` - should show thumbnail preview
2. Paste multiple images - should show all thumbnails
3. Remove image from preview with X button
4. Send text only - should use string format
5. Send image only - should use content blocks
6. Send text + images - should use content blocks with both
7. Verify images appear in Claude's response context

## Dependencies

Add to `flutter_app/pubspec.yaml`:

```yaml
dependencies:
  super_clipboard: ^0.8.0  # Or latest version
```

## API Limits

From Anthropic API documentation:
- Maximum image size: 20MB per image
- Supported formats: PNG, JPEG, GIF, WebP
- Images are counted in input tokens based on their dimensions
