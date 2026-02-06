import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/file_content.dart';
import '../models/file_tree_node.dart';
import 'file_type_detector.dart';

/// Maximum file size for text files (1MB).
const int maxTextFileSize = 1024 * 1024;

/// Exception thrown when a file system operation fails.
class FileSystemException implements Exception {
  /// Human-readable error message.
  final String message;

  /// The path that caused the error.
  final String? path;

  /// The underlying OS error, if available.
  final OSError? osError;

  const FileSystemException(
    this.message, {
    this.path,
    this.osError,
  });

  @override
  String toString() {
    final buffer = StringBuffer('FileSystemException: $message');
    if (path != null) buffer.write(' (path: $path)');
    if (osError != null) buffer.write(' [${osError!.message}]');
    return buffer.toString();
  }
}

/// Abstract interface for file system operations.
///
/// Use [RealFileSystemService] for production and [FakeFileSystemService]
/// for testing.
abstract class FileSystemService {
  /// Default maximum depth for file tree scanning.
  static const int defaultMaxDepth = 10;

  /// Default timeout for git operations.
  static const Duration gitTimeout = Duration(seconds: 1);

  /// Builds a file tree for the given directory.
  ///
  /// Returns a [FileTreeNode] representing the directory hierarchy.
  /// Directories are sorted before files, and each group is sorted
  /// alphabetically by name.
  ///
  /// Parameters:
  /// - [rootPath]: Absolute path to the root directory to scan.
  /// - [respectGitignore]: If true, filters out .gitignore'd files.
  /// - [maxDepth]: Maximum depth to scan (default: 10).
  ///
  /// Throws [FileSystemException] if [rootPath] doesn't exist or isn't
  /// a directory.
  Future<FileTreeNode> buildFileTree(
    String rootPath, {
    bool respectGitignore = true,
    int maxDepth = defaultMaxDepth,
  });

  /// Reads file content and determines its type.
  ///
  /// Returns a [FileContent] with the file data and detected type.
  /// For text files, content is decoded as UTF-8.
  /// For binary files, raw bytes are stored.
  ///
  /// Errors are returned as [FileContent.error] rather than thrown:
  /// - File not found
  /// - Permission denied
  /// - File too large (> 1MB for text files)
  Future<FileContent> readFile(String path);

  /// Checks if a path is ignored by .gitignore.
  ///
  /// Uses `git check-ignore` to determine if the path would be ignored.
  /// Returns true if the file is ignored, false otherwise.
  /// Returns false if git is unavailable or the path is not in a repo.
  Future<bool> isIgnored(String repoRoot, String path);
}

/// Real implementation of [FileSystemService] using dart:io.
class RealFileSystemService implements FileSystemService {
  /// Creates a [RealFileSystemService].
  const RealFileSystemService();

  @override
  Future<FileTreeNode> buildFileTree(
    String rootPath, {
    bool respectGitignore = true,
    int maxDepth = FileSystemService.defaultMaxDepth,
  }) async {
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) {
      throw FileSystemException(
        'Directory does not exist',
        path: rootPath,
      );
    }

    final stat = await rootDir.stat();
    if (stat.type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Path is not a directory',
        path: rootPath,
      );
    }

    // Build set of ignored paths upfront if gitignore is enabled
    Set<String>? ignoredPaths;
    if (respectGitignore) {
      // First collect all paths in the tree
      final allPaths = await _collectAllPaths(rootDir, maxDepth, 0);
      // Then batch check all paths for gitignore in a single git call
      ignoredPaths = await _getIgnoredPaths(rootPath, allPaths);
    }

    return _buildTree(
      rootDir,
      rootPath,
      ignoredPaths: ignoredPaths,
      maxDepth: maxDepth,
      currentDepth: 0,
    );
  }

  /// Collects all paths in the directory tree for batch gitignore checking.
  Future<List<String>> _collectAllPaths(
    Directory dir,
    int maxDepth,
    int currentDepth,
  ) async {
    final paths = <String>[];
    if (currentDepth >= maxDepth) {
      return paths;
    }

    try {
      final entities = await dir.list().toList();
      for (final entity in entities) {
        final name = _getFileName(entity.path);
        if (name == '.git') continue;

        paths.add(entity.path);
        if (entity is Directory) {
          paths.addAll(await _collectAllPaths(
            entity,
            maxDepth,
            currentDepth + 1,
          ));
        }
      }
    } on FileSystemException {
      // Skip directories we can't read
    }
    return paths;
  }

  /// Gets all ignored paths using a single batched git check-ignore call.
  ///
  /// This is much faster than calling git check-ignore per file because
  /// it spawns only one process and passes all paths via stdin.
  Future<Set<String>> _getIgnoredPaths(
    String repoRoot,
    List<String> allPaths,
  ) async {
    // SIGPIPE: disabled — stdin pipe to git check-ignore causes SIGPIPE crash
    return {};

    // ignore: dead_code
    if (allPaths.isEmpty) {
      return {};
    }

    try {
      // Use git check-ignore with --stdin to batch check all paths at once
      // --stdin: read paths from stdin (one per line)
      // -z: NUL-terminated input/output for safe handling of special chars
      final process = await Process.start(
        'git',
        ['check-ignore', '--stdin', '-z'],
        workingDirectory: repoRoot,
      );

      // Start reading stdout immediately to prevent pipe deadlock
      final outputFuture = process.stdout
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      // Write all paths to stdin (NUL-separated)
      // Use try-catch to handle broken pipe if git exits early
      try {
        process.stdin.write(allPaths.join('\x00'));
        process.stdin.write('\x00');
        await process.stdin.close();
      } on SocketException {
        // Git process may have exited, continue to read any output
      } on IOException {
        // Handle other I/O errors gracefully
      }

      final output = await outputFuture;
      await process.exitCode;

      if (output.isEmpty) {
        return {};
      }

      // Parse NUL-separated ignored paths
      return output.split('\x00').where((p) => p.isNotEmpty).toSet();
    } on TimeoutException {
      return {};
    } on ProcessException {
      return {};
    } catch (e) {
      // Catch any other errors (SocketException, etc.) and return empty set
      // to fall back to showing all files
      return {};
    }
  }

  Future<FileTreeNode> _buildTree(
    Directory dir,
    String repoRoot, {
    required Set<String>? ignoredPaths,
    required int maxDepth,
    required int currentDepth,
  }) async {
    final name = _getFileName(dir.path);
    final children = <FileTreeNode>[];

    if (currentDepth < maxDepth) {
      try {
        final entities = await dir.list().toList();

        // Separate directories and files
        final dirs = <FileSystemEntity>[];
        final files = <FileSystemEntity>[];

        for (final entity in entities) {
          // Skip hidden git directory at root level
          if (_getFileName(entity.path) == '.git') {
            continue;
          }

          // Check gitignore if needed (O(1) set lookup)
          if (ignoredPaths != null && ignoredPaths.contains(entity.path)) {
            continue;
          }

          if (entity is Directory) {
            dirs.add(entity);
          } else if (entity is File) {
            files.add(entity);
          }
          // Skip symlinks and other types for now
        }

        // Sort directories and files alphabetically (case-insensitive)
        dirs.sort((a, b) => _getFileName(a.path)
            .toLowerCase()
            .compareTo(_getFileName(b.path).toLowerCase()));
        files.sort((a, b) => _getFileName(a.path)
            .toLowerCase()
            .compareTo(_getFileName(b.path).toLowerCase()));

        // Process directories first
        for (final subDir in dirs) {
          try {
            final childNode = await _buildTree(
              subDir as Directory,
              repoRoot,
              ignoredPaths: ignoredPaths,
              maxDepth: maxDepth,
              currentDepth: currentDepth + 1,
            );
            children.add(childNode);
          } on FileSystemException {
            // Skip directories we can't read (permission denied, etc.)
          }
        }

        // Then process files
        for (final file in files) {
          try {
            final stat = await file.stat();
            children.add(FileTreeNode.file(
              name: _getFileName(file.path),
              path: file.path,
              size: stat.size,
              modified: stat.modified,
            ));
          } on FileSystemException {
            // Skip files we can't stat
          }
        }
      } on FileSystemException catch (e) {
        throw FileSystemException(
          'Failed to list directory',
          path: dir.path,
          osError: e.osError,
        );
      }
    }

    final stat = await dir.stat();
    return FileTreeNode.directory(
      name: name,
      path: dir.path,
      modified: stat.modified,
      children: children,
      isExpanded: false,
    );
  }

  @override
  Future<FileContent> readFile(String path) async {
    final file = File(path);

    // Check if file exists
    if (!await file.exists()) {
      return FileContent.error(
        path: path,
        message: 'File not found',
      );
    }

    // Get file stats
    final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException catch (e) {
      return FileContent.error(
        path: path,
        message: 'Cannot access file: ${e.message}',
      );
    }

    // Check file type
    final type = FileTypeDetector.detectType(path);

    // Handle images - read as bytes regardless of size
    if (type == FileContentType.image) {
      try {
        final bytes = await file.readAsBytes();
        return FileContent.image(path: path, bytes: bytes);
      } on FileSystemException catch (e) {
        return FileContent.error(
          path: path,
          message: 'Failed to read image: ${e.message}',
        );
      }
    }

    // For text files, check size limit
    if (stat.size > maxTextFileSize) {
      // Read first bytes to check if binary
      try {
        final sample = await _readFirstBytes(file, 8192);
        if (FileTypeDetector.isBinary(sample)) {
          return FileContent.binary(
            path: path,
            bytes: Uint8List.fromList(sample),
          );
        }
      } on FileSystemException {
        // Continue with size error
      }

      return FileContent.error(
        path: path,
        message: 'File too large (${_formatSize(stat.size)}). '
            'Maximum size is ${_formatSize(maxTextFileSize)}.',
      );
    }

    // Read file bytes
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      return FileContent.error(
        path: path,
        message: 'Permission denied: ${e.message}',
      );
    }

    // Check if binary using content analysis if type wasn't clear
    if (type == FileContentType.plaintext ||
        type == FileContentType.binary) {
      if (FileTypeDetector.isBinary(bytes)) {
        return FileContent.binary(
          path: path,
          bytes: Uint8List.fromList(bytes),
        );
      }
    }

    // Decode as UTF-8 text
    final String content;
    try {
      content = utf8.decode(bytes, allowMalformed: true);
    } on FormatException {
      // If UTF-8 decode fails, treat as binary
      return FileContent.binary(
        path: path,
        bytes: Uint8List.fromList(bytes),
      );
    }

    // Return appropriate type
    return switch (type) {
      FileContentType.dart => FileContent.dart(path: path, content: content),
      FileContentType.json => FileContent.json(path: path, content: content),
      FileContentType.markdown =>
        FileContent.markdown(path: path, content: content),
      _ => FileContent.plaintext(path: path, content: content),
    };
  }

  Future<List<int>> _readFirstBytes(File file, int count) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      return await raf.read(count);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<bool> isIgnored(String repoRoot, String path) async {
    try {
      final result = await Process.run(
        'git',
        ['check-ignore', '-q', path],
        workingDirectory: repoRoot,
      ).timeout(FileSystemService.gitTimeout);

      // Exit code 0 = ignored, 1 = not ignored
      return result.exitCode == 0;
    } on TimeoutException {
      // Git timed out, assume not ignored
      return false;
    } on ProcessException {
      // Git not available or failed
      return false;
    }
  }

  /// Extracts file name from a path.
  String _getFileName(String path) {
    // Handle trailing slashes
    var normalized = path;
    while (normalized.endsWith('/') || normalized.endsWith('\\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    final lastSlash = normalized.lastIndexOf('/');
    final lastBackslash = normalized.lastIndexOf('\\');
    final lastSeparator =
        lastSlash > lastBackslash ? lastSlash : lastBackslash;

    if (lastSeparator == -1) {
      return normalized;
    }
    return normalized.substring(lastSeparator + 1);
  }

  /// Formats a file size in human-readable form.
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Fake implementation of [FileSystemService] for testing.
///
/// Provides an in-memory file system with configurable contents.
class FakeFileSystemService implements FileSystemService {
  /// In-memory file tree structure.
  ///
  /// Keys are absolute paths, values are either:
  /// - `null` for directories
  /// - `String` for text files
  /// - `List<int>` for binary files
  final Map<String, dynamic> _files = {};

  /// Set of paths that are "ignored" by gitignore.
  final Set<String> _ignoredPaths = {};

  /// Simulated delay for async operations.
  Duration delay;

  /// Creates a [FakeFileSystemService] with optional delay.
  FakeFileSystemService({this.delay = Duration.zero});

  /// Adds a directory to the fake file system.
  void addDirectory(String path) {
    _files[path] = null;
  }

  /// Adds a text file to the fake file system.
  void addTextFile(String path, String content) {
    _files[path] = content;
  }

  /// Adds a binary file to the fake file system.
  void addBinaryFile(String path, List<int> bytes) {
    _files[path] = bytes;
  }

  /// Marks a path as ignored by .gitignore.
  void addIgnoredPath(String path) {
    _ignoredPaths.add(path);
  }

  /// Clears all files and ignored paths.
  void clear() {
    _files.clear();
    _ignoredPaths.clear();
  }

  Future<void> _simulateDelay() async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  @override
  Future<FileTreeNode> buildFileTree(
    String rootPath, {
    bool respectGitignore = true,
    int maxDepth = FileSystemService.defaultMaxDepth,
  }) async {
    await _simulateDelay();

    if (!_files.containsKey(rootPath)) {
      throw FileSystemException(
        'Directory does not exist',
        path: rootPath,
      );
    }

    if (_files[rootPath] != null) {
      throw FileSystemException(
        'Path is not a directory',
        path: rootPath,
      );
    }

    return _buildFakeTree(
      rootPath,
      respectGitignore: respectGitignore,
      maxDepth: maxDepth,
      currentDepth: 0,
    );
  }

  FileTreeNode _buildFakeTree(
    String dirPath, {
    required bool respectGitignore,
    required int maxDepth,
    required int currentDepth,
  }) {
    final name = _getFileName(dirPath);
    final children = <FileTreeNode>[];

    if (currentDepth < maxDepth) {
      // Find all direct children
      final childPaths = _files.keys.where((path) {
        if (path == dirPath) return false;
        if (!path.startsWith('$dirPath/')) return false;

        // Check if it's a direct child (no more slashes after the parent path)
        final relative = path.substring(dirPath.length + 1);
        return !relative.contains('/');
      }).toList();

      // Separate dirs and files
      final dirs = <String>[];
      final files = <String>[];

      for (final path in childPaths) {
        // Check gitignore
        if (respectGitignore && _ignoredPaths.contains(path)) {
          continue;
        }

        if (_files[path] == null) {
          dirs.add(path);
        } else {
          files.add(path);
        }
      }

      // Sort alphabetically (case-insensitive)
      dirs.sort((a, b) =>
          _getFileName(a).toLowerCase().compareTo(
              _getFileName(b).toLowerCase()));
      files.sort((a, b) =>
          _getFileName(a).toLowerCase().compareTo(
              _getFileName(b).toLowerCase()));

      // Process directories
      for (final dir in dirs) {
        children.add(_buildFakeTree(
          dir,
          respectGitignore: respectGitignore,
          maxDepth: maxDepth,
          currentDepth: currentDepth + 1,
        ));
      }

      // Process files
      for (final file in files) {
        final content = _files[file];
        final size = content is String
            ? content.length
            : (content is List<int> ? content.length : 0);

        children.add(FileTreeNode.file(
          name: _getFileName(file),
          path: file,
          size: size,
          modified: DateTime.now(),
        ));
      }
    }

    return FileTreeNode.directory(
      name: name,
      path: dirPath,
      modified: DateTime.now(),
      children: children,
      isExpanded: false,
    );
  }

  @override
  Future<FileContent> readFile(String path) async {
    await _simulateDelay();

    if (!_files.containsKey(path)) {
      return FileContent.error(
        path: path,
        message: 'File not found',
      );
    }

    final content = _files[path];

    if (content == null) {
      return FileContent.error(
        path: path,
        message: 'Cannot read directory as file',
      );
    }

    // Determine type from extension
    final type = FileTypeDetector.detectType(path);

    if (content is List<int>) {
      // Binary content
      if (type == FileContentType.image) {
        return FileContent.image(
          path: path,
          bytes: Uint8List.fromList(content),
        );
      }
      return FileContent.binary(
        path: path,
        bytes: Uint8List.fromList(content),
      );
    }

    // Text content
    final text = content as String;

    return switch (type) {
      FileContentType.dart => FileContent.dart(path: path, content: text),
      FileContentType.json => FileContent.json(path: path, content: text),
      FileContentType.markdown =>
        FileContent.markdown(path: path, content: text),
      _ => FileContent.plaintext(path: path, content: text),
    };
  }

  @override
  Future<bool> isIgnored(String repoRoot, String path) async {
    await _simulateDelay();
    return _ignoredPaths.contains(path);
  }

  String _getFileName(String path) {
    var normalized = path;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    final lastSlash = normalized.lastIndexOf('/');
    if (lastSlash == -1) return normalized;
    return normalized.substring(lastSlash + 1);
  }
}
