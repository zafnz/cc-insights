# Feature: Paste Images into Chat

## Overview

Enable users to paste images from the clipboard directly into the chat input, allowing Claude to analyze and respond to visual content.

## SDK Support

The Claude Agent SDK supports images in **Streaming Input Mode** (which we already use). Images are sent as base64-encoded content blocks within user messages.

### Image Content Block Format

```typescript
{
  type: "image",
  source: {
    type: "base64",
    media_type: "image/png",  // or "image/jpeg", "image/gif", "image/webp"
    data: "<base64-encoded-image-data>"
  }
}
```

### Message Structure with Images

Messages with images use an array of content blocks instead of a plain string:

```typescript
{
  type: "user",
  message: {
    role: "user",
    content: [
      { type: "text", text: "What's in this image?" },
      {
        type: "image",
        source: {
          type: "base64",
          media_type: "image/png",
          data: "<base64-data>"
        }
      }
    ]
  }
}
```

---

## Implementation Plan

### Phase 1: Protocol Layer Changes

#### 1.1 Backend Protocol (`backend-node/src/protocol.ts`)

Update `SessionSendMessage` to support content blocks:

```typescript
export interface SessionSendMessage {
  type: "session.send";
  id: string;
  session_id: string;
  payload: {
    message: string;  // Keep for backwards compatibility
    content?: ContentBlock[];  // New: array of content blocks
  };
}

export type ContentBlock = TextContent | ImageContent;

export interface TextContent {
  type: "text";
  text: string;
}

export interface ImageContent {
  type: "image";
  source: {
    type: "base64";
    media_type: "image/png" | "image/jpeg" | "image/gif" | "image/webp";
    data: string;
  };
}
```

#### 1.2 Session Manager (`backend-node/src/session-manager.ts`)

Update `sendMessage()` to construct the proper SDK message:

```typescript
private async sendMessage(msg: SessionSendMessage): Promise<void> {
  // ...

  // Build content - use content blocks if provided, otherwise use message string
  const content = msg.payload.content
    ? msg.payload.content
    : msg.payload.message;

  const userMessage: SDKUserMessage = {
    type: "user",
    message: {
      role: "user",
      content: content,
    },
    parent_tool_use_id: null,
    session_id: msg.session_id,
  };
  // ...
}
```

#### 1.3 Dart SDK Protocol (`claude_dart_sdk/lib/src/protocol.dart`)

Update `SessionSendMessage` to support content blocks:

```dart
class SessionSendMessage extends OutgoingMessage {
  const SessionSendMessage({
    required this.id,
    required this.sessionId,
    this.message,
    this.content,
  }) : assert(message != null || content != null);

  final String id;
  final String sessionId;
  final String? message;  // Simple text message
  final List<ContentBlock>? content;  // Content blocks (text + images)

  @override
  Map<String, dynamic> toJson() => {
    'type': 'session.send',
    'id': id,
    'session_id': sessionId,
    'payload': {
      if (message != null) 'message': message,
      if (content != null) 'content': content.map((c) => c.toJson()).toList(),
    },
  };
}

sealed class ContentBlock {
  Map<String, dynamic> toJson();
}

class TextContent extends ContentBlock {
  TextContent(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

class ImageContent extends ContentBlock {
  ImageContent({required this.mediaType, required this.data});
  final String mediaType;
  final String data;  // base64

  @override
  Map<String, dynamic> toJson() => {
    'type': 'image',
    'source': {
      'type': 'base64',
      'media_type': mediaType,
      'data': data,
    },
  };
}
```

---

### Phase 2: Model Layer Changes

#### 2.1 Output Entry Model (`flutter_app_v2/lib/models/output_entry.dart`)

Update `UserInputEntry` to support images:

```dart
class UserInputEntry extends OutputEntry {
  UserInputEntry({
    required super.id,
    required super.timestamp,
    required this.text,
    this.images = const [],
  });

  final String text;
  final List<AttachedImage> images;
}

class AttachedImage {
  const AttachedImage({
    required this.data,
    required this.mediaType,
  });

  final Uint8List data;
  final String mediaType;

  String get base64 => base64Encode(data);
}
```

---

### Phase 3: UI Layer Changes

#### 3.1 Message Input Widget (`flutter_app_v2/lib/widgets/message_input.dart`)

**Changes needed:**

1. **Handle paste events** - Intercept Cmd+V / Ctrl+V to check for images
2. **Store pending images** - Maintain list of images to send with message
3. **Display image previews** - Show thumbnails above the text input
4. **Remove images** - Allow users to remove images before sending
5. **Update callback signature** - Pass images along with text

```dart
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSubmit,  // Updated signature
    // ...
  });

  /// Called when the user submits a message.
  /// Text is the message text, images are any attached images.
  final void Function(String text, List<AttachedImage> images) onSubmit;
}

class _MessageInputState extends State<MessageInput> {
  final List<AttachedImage> _pendingImages = [];

  Future<void> _handlePaste() async {
    final clipboard = await Clipboard.getData(Clipboard.kBinaryFormat);
    // Check for image data...
  }

  void _removeImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }
}
```

**UI Layout with images:**

```
┌─────────────────────────────────────────────────────┐
│  [img1 ✕] [img2 ✕] [img3 ✕]      <- Image previews  │
├─────────────────────────────────────────────────────┤
│ [+] Type a message...                     [Send]    │
└─────────────────────────────────────────────────────┘
  ^
  Image attachment button
```

**Additional input features:**

1. **Paste handling** (Cmd+V) - Detect image data in clipboard
2. **Drag and drop** - Accept dropped images from Finder or other apps
3. **Image button** - Click to open file picker for images
4. **Image limit** - Maximum 5 images per message (show warning if exceeded)
5. **Compression** - Auto-compress images > 1MB before sending

#### 3.2 User Input Entry Widget (`flutter_app_v2/lib/widgets/output_entries/user_input_entry.dart`)

Update to display images alongside text:

```dart
class UserInputEntryWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      // ...
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Text content
          if (entry.text.isNotEmpty)
            SelectableText(entry.text),

          // Image thumbnails
          if (entry.images.isNotEmpty)
            Wrap(
              spacing: 8,
              children: entry.images.map((img) =>
                _ImageThumbnail(image: img)
              ).toList(),
            ),
        ],
      ),
    );
  }
}
```

---

### Phase 4: Integration

#### 4.1 Chat Model Updates

Update `Chat.sendMessage()` to handle images:

```dart
Future<void> sendMessage(String text, {List<AttachedImage>? images}) async {
  // Create output entry with images
  final entry = UserInputEntry(
    id: uuid(),
    timestamp: DateTime.now(),
    text: text,
    images: images ?? [],
  );

  // Send via SDK with content blocks if images present
  if (images != null && images.isNotEmpty) {
    await _session.sendWithContent([
      TextContent(text),
      ...images.map((img) => ImageContent(
        mediaType: img.mediaType,
        data: img.base64,
      )),
    ]);
  } else {
    await _session.send(text);
  }
}
```

---

## Platform Considerations

### macOS Clipboard Access

Flutter on macOS can access clipboard images via:

```dart
import 'package:pasteboard/pasteboard.dart';  // Consider this package

// Or using platform channels with NSPasteboard
```

**Options:**
1. **`pasteboard` package** - Cross-platform clipboard with image support
2. **`super_clipboard` package** - Modern clipboard API with image support
3. **Custom platform channel** - Direct NSPasteboard access

**Recommendation:** Use `super_clipboard` as it has good macOS support and handles various image formats.

### Image Size Limits

Implementing:
- Maximum **5 images** per message
- Auto-compress images **> 1MB** (resize to reduce dimensions while maintaining aspect ratio)
- Maximum compressed size: **5MB** per image (reject if still too large after compression)

### Image Compression Strategy

```dart
Future<Uint8List> compressImage(Uint8List data, String mediaType) async {
  // If under 1MB, return as-is
  if (data.length < 1024 * 1024) return data;

  // Decode image
  final image = img.decodeImage(data);
  if (image == null) return data;

  // Calculate new dimensions (max 2048px on longest side)
  final maxDimension = 2048;
  final scale = min(1.0, maxDimension / max(image.width, image.height));
  final newWidth = (image.width * scale).round();
  final newHeight = (image.height * scale).round();

  // Resize
  final resized = img.copyResize(image, width: newWidth, height: newHeight);

  // Re-encode as JPEG with quality 85
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}
```

**Package:** Use `image` package for compression/resizing.

### Drag and Drop Implementation

Use the `desktop_drop` package for cross-platform drag-and-drop support:

```dart
import 'package:desktop_drop/desktop_drop.dart';

class _MessageInputState extends State<MessageInput> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        for (final file in details.files) {
          await _addImageFromPath(file.path);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          border: _isDragging
            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
            : null,
        ),
        child: _buildInput(),
      ),
    );
  }
}
```

### File Picker Implementation

Use the `file_picker` package:

```dart
import 'package:file_picker/file_picker.dart';

Future<void> _pickImages() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: true,
    withData: true,  // Read file bytes
  );

  if (result != null) {
    for (final file in result.files) {
      if (file.bytes != null) {
        await _addImage(file.bytes!, _getMimeType(file.extension));
      }
    }
  }
}
```

---

## Requirements (Confirmed)

| Requirement | Decision |
|-------------|----------|
| Drag and drop | Yes - support dragging images from Finder/apps |
| File picker button | Yes - add image attachment button |
| Maximum images | 5 per message |
| Image compression | Yes - compress images > 1MB |
| Supported formats | PNG, JPEG, GIF, WebP (SDK supported formats)

---

## File Changes Summary

| File | Change |
|------|--------|
| `backend-node/src/protocol.ts` | Add ContentBlock types |
| `backend-node/src/session-manager.ts` | Handle content blocks in sendMessage |
| `claude_dart_sdk/lib/src/protocol.dart` | Add ContentBlock types and update SessionSendMessage |
| `flutter_app_v2/lib/models/output_entry.dart` | Add images to UserInputEntry |
| `flutter_app_v2/lib/widgets/message_input.dart` | Add paste handling and image previews |
| `flutter_app_v2/lib/widgets/output_entries/user_input_entry.dart` | Display images |
| `flutter_app_v2/lib/models/chat.dart` | Update sendMessage to handle images |
| `pubspec.yaml` | Add `super_clipboard`, `desktop_drop`, `file_picker`, `image` dependencies |

---

## Testing Plan

1. **Unit tests** - ContentBlock serialization
2. **Widget tests** - Image preview display and removal
3. **Integration tests** - Full paste-to-send flow
4. **Manual testing** - Various image formats, large images, multiple images
