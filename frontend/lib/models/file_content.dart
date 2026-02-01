import 'package:flutter/foundation.dart';

/// The detected content type of a file.
///
/// Used to determine how to render the file in the viewer panel.
enum FileContentType {
  /// Generic text file with no special formatting.
  plaintext,

  /// Dart source code file.
  dart,

  /// JSON data file.
  json,

  /// Markdown document.
  markdown,

  /// Image file (PNG, JPG, GIF, etc.).
  image,

  /// Binary file that cannot be displayed as text.
  binary,

  /// Error state when file could not be read.
  error,
}

/// Immutable data representing loaded file content.
///
/// A [FileContent] holds the content of a file that has been read from disk.
/// The [type] determines how the content should be displayed:
/// - Text types ([plaintext], [dart], [json], [markdown]): [data] is a String
/// - Image/binary types: [data] is a Uint8List
/// - Error type: [data] is null and [error] contains the error message
///
/// Use factory constructors for type-safe creation of different content types.
@immutable
class FileContent {
  /// The absolute path to the file.
  final String path;

  /// The detected content type of the file.
  final FileContentType type;

  /// The file content data.
  ///
  /// Type depends on [type]:
  /// - Text types: String
  /// - Image/binary: Uint8List
  /// - Error: null
  final dynamic data;

  /// Error message if the file could not be read.
  ///
  /// Only set when [type] is [FileContentType.error].
  final String? error;

  /// Creates a new [FileContent].
  ///
  /// Prefer using the factory constructors for type-safe creation.
  const FileContent({
    required this.path,
    required this.type,
    this.data,
    this.error,
  });

  /// Creates a text file content.
  ///
  /// Use for plaintext files without special formatting.
  factory FileContent.plaintext({
    required String path,
    required String content,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.plaintext,
      data: content,
    );
  }

  /// Creates a Dart source file content.
  factory FileContent.dart({
    required String path,
    required String content,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.dart,
      data: content,
    );
  }

  /// Creates a JSON file content.
  factory FileContent.json({
    required String path,
    required String content,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.json,
      data: content,
    );
  }

  /// Creates a Markdown file content.
  factory FileContent.markdown({
    required String path,
    required String content,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.markdown,
      data: content,
    );
  }

  /// Creates an image file content.
  factory FileContent.image({
    required String path,
    required Uint8List bytes,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.image,
      data: bytes,
    );
  }

  /// Creates a binary file content.
  ///
  /// Used for non-displayable binary files.
  factory FileContent.binary({
    required String path,
    required Uint8List bytes,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.binary,
      data: bytes,
    );
  }

  /// Creates an error content when file reading fails.
  factory FileContent.error({
    required String path,
    required String message,
  }) {
    return FileContent(
      path: path,
      type: FileContentType.error,
      error: message,
    );
  }

  /// Whether this content represents a text file.
  ///
  /// Returns true for plaintext, dart, json, and markdown types.
  bool get isText {
    return type == FileContentType.plaintext ||
        type == FileContentType.dart ||
        type == FileContentType.json ||
        type == FileContentType.markdown;
  }

  /// Whether this content represents a binary file.
  ///
  /// Returns true for image and binary types.
  bool get isBinary {
    return type == FileContentType.image || type == FileContentType.binary;
  }

  /// Whether this content represents an error state.
  bool get isError => type == FileContentType.error;

  /// Gets the text content if this is a text file.
  ///
  /// Returns null for non-text types.
  String? get textContent => isText ? data as String? : null;

  /// Gets the binary content if this is a binary file.
  ///
  /// Returns null for non-binary types.
  Uint8List? get binaryContent => isBinary ? data as Uint8List? : null;

  /// Gets the file name from the path.
  String get fileName {
    final lastSeparator = path.lastIndexOf('/');
    if (lastSeparator == -1) return path;
    return path.substring(lastSeparator + 1);
  }

  /// Creates a copy with the given fields replaced.
  FileContent copyWith({
    String? path,
    FileContentType? type,
    dynamic data,
    bool clearData = false,
    String? error,
    bool clearError = false,
  }) {
    return FileContent(
      path: path ?? this.path,
      type: type ?? this.type,
      data: clearData ? null : (data ?? this.data),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FileContent) return false;

    // Compare data based on type
    bool dataEquals;
    if (data == null && other.data == null) {
      dataEquals = true;
    } else if (data is Uint8List && other.data is Uint8List) {
      dataEquals = listEquals(data as Uint8List, other.data as Uint8List);
    } else {
      dataEquals = data == other.data;
    }

    return other.path == path &&
        other.type == type &&
        dataEquals &&
        other.error == error;
  }

  @override
  int get hashCode {
    // Handle Uint8List hashing specially
    final dataHash = data is Uint8List
        ? Object.hashAll(data as Uint8List)
        : data.hashCode;

    return Object.hash(path, type, dataHash, error);
  }

  @override
  String toString() {
    final dataDesc = data == null
        ? 'null'
        : (data is Uint8List
            ? '${(data as Uint8List).length} bytes'
            : '${(data as String).length} chars');

    return 'FileContent(path: $path, type: $type, '
        'data: $dataDesc, error: $error)';
  }
}
