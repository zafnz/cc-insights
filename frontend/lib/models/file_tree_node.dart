import 'package:flutter/foundation.dart';

/// The type of a file tree node.
enum FileTreeNodeType {
  /// A regular file.
  file,

  /// A directory that may contain children.
  directory,
}

/// Immutable data representing a node in a file tree.
///
/// A [FileTreeNode] can be either a file or a directory. Directories can
/// contain children and track their expansion state in the UI. Files have
/// a size and modification time.
///
/// Use [copyWith] to create modified copies with updated fields, typically
/// used for toggling [isExpanded] state or updating children.
@immutable
class FileTreeNode {
  /// The file or directory name (last path component).
  final String name;

  /// The absolute path to this file or directory.
  final String path;

  /// Whether this node is a file or directory.
  final FileTreeNodeType type;

  /// The file size in bytes. Null for directories.
  final int? size;

  /// The last modified time. May be null if unavailable.
  final DateTime? modified;

  /// The children of this directory. Empty list for files.
  final List<FileTreeNode> children;

  /// Whether this directory is expanded in the UI.
  ///
  /// Only meaningful for directories; ignored for files.
  final bool isExpanded;

  /// Creates a new [FileTreeNode].
  ///
  /// For files, [children] should be empty and [isExpanded] is ignored.
  /// For directories, [size] is typically null.
  const FileTreeNode({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.modified,
    this.children = const [],
    this.isExpanded = false,
  });

  /// Creates a file node.
  ///
  /// Convenience factory for creating file nodes with appropriate defaults.
  factory FileTreeNode.file({
    required String name,
    required String path,
    int? size,
    DateTime? modified,
  }) {
    return FileTreeNode(
      name: name,
      path: path,
      type: FileTreeNodeType.file,
      size: size,
      modified: modified,
      children: const [],
      isExpanded: false,
    );
  }

  /// Creates a directory node.
  ///
  /// Convenience factory for creating directory nodes with children.
  factory FileTreeNode.directory({
    required String name,
    required String path,
    DateTime? modified,
    List<FileTreeNode> children = const [],
    bool isExpanded = false,
  }) {
    return FileTreeNode(
      name: name,
      path: path,
      type: FileTreeNodeType.directory,
      size: null,
      modified: modified,
      children: children,
      isExpanded: isExpanded,
    );
  }

  /// Whether this node represents a file.
  bool get isFile => type == FileTreeNodeType.file;

  /// Whether this node represents a directory.
  bool get isDirectory => type == FileTreeNodeType.directory;

  /// Whether this directory has children.
  ///
  /// Always returns false for files.
  bool get hasChildren => isDirectory && children.isNotEmpty;

  /// Creates a copy with the given fields replaced.
  ///
  /// Useful for updating expansion state or children without mutating
  /// the original node.
  FileTreeNode copyWith({
    String? name,
    String? path,
    FileTreeNodeType? type,
    int? size,
    bool clearSize = false,
    DateTime? modified,
    bool clearModified = false,
    List<FileTreeNode>? children,
    bool? isExpanded,
  }) {
    return FileTreeNode(
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      size: clearSize ? null : (size ?? this.size),
      modified: clearModified ? null : (modified ?? this.modified),
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileTreeNode &&
        other.name == name &&
        other.path == path &&
        other.type == type &&
        other.size == size &&
        other.modified == modified &&
        listEquals(other.children, children) &&
        other.isExpanded == isExpanded;
  }

  @override
  int get hashCode {
    return Object.hash(
      name,
      path,
      type,
      size,
      modified,
      Object.hashAll(children),
      isExpanded,
    );
  }

  @override
  String toString() {
    return 'FileTreeNode(name: $name, path: $path, type: $type, '
        'size: $size, modified: $modified, '
        'children: ${children.length}, isExpanded: $isExpanded)';
  }
}
