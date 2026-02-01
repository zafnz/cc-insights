import '../models/file_content.dart';

/// Utility class for detecting file types and syntax highlighting languages.
///
/// Provides static methods for:
/// - Detecting file content type from path and optional bytes
/// - Checking if file content is binary
/// - Mapping file extensions to syntax highlighting languages
/// - Extracting file extensions from paths
///
/// All methods are pure functions with no side effects.
class FileTypeDetector {
  // Private constructor to prevent instantiation.
  FileTypeDetector._();

  /// Number of bytes to check for binary detection.
  static const int _binaryCheckBytes = 8192; // 8KB

  /// Threshold ratio of non-printable chars to consider file binary.
  static const double _binaryThreshold = 0.3;

  /// Extension to FileContentType mapping.
  static const Map<String, FileContentType> _extensionToType = {
    // Dart
    'dart': FileContentType.dart,

    // JSON
    'json': FileContentType.json,

    // Markdown
    'md': FileContentType.markdown,
    'markdown': FileContentType.markdown,

    // Images
    'png': FileContentType.image,
    'jpg': FileContentType.image,
    'jpeg': FileContentType.image,
    'gif': FileContentType.image,
    'webp': FileContentType.image,
    'bmp': FileContentType.image,
    'ico': FileContentType.image,
    'svg': FileContentType.image,

    // Common binary formats
    'pdf': FileContentType.binary,
    'zip': FileContentType.binary,
    'tar': FileContentType.binary,
    'gz': FileContentType.binary,
    'rar': FileContentType.binary,
    '7z': FileContentType.binary,
    'exe': FileContentType.binary,
    'dll': FileContentType.binary,
    'so': FileContentType.binary,
    'dylib': FileContentType.binary,
    'class': FileContentType.binary,
    'jar': FileContentType.binary,
    'war': FileContentType.binary,
    'woff': FileContentType.binary,
    'woff2': FileContentType.binary,
    'ttf': FileContentType.binary,
    'otf': FileContentType.binary,
    'eot': FileContentType.binary,
  };

  /// Extension to syntax highlighting language mapping.
  static const Map<String, String> _extensionToLanguage = {
    // Dart
    'dart': 'dart',

    // JavaScript/TypeScript
    'js': 'javascript',
    'mjs': 'javascript',
    'cjs': 'javascript',
    'jsx': 'jsx',
    'ts': 'typescript',
    'mts': 'typescript',
    'cts': 'typescript',
    'tsx': 'tsx',

    // Web
    'html': 'html',
    'htm': 'html',
    'css': 'css',
    'scss': 'scss',
    'sass': 'sass',
    'less': 'less',

    // Data formats
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'xml': 'xml',
    'toml': 'toml',

    // Shell
    'sh': 'bash',
    'bash': 'bash',
    'zsh': 'zsh',
    'fish': 'fish',
    'ps1': 'powershell',
    'psm1': 'powershell',
    'psd1': 'powershell',

    // Python
    'py': 'python',
    'pyw': 'python',
    'pyi': 'python',

    // Ruby
    'rb': 'ruby',
    'rake': 'ruby',
    'gemspec': 'ruby',

    // Go
    'go': 'go',
    'mod': 'go',

    // Rust
    'rs': 'rust',

    // Java/Kotlin
    'java': 'java',
    'kt': 'kotlin',
    'kts': 'kotlin',

    // Swift/Objective-C
    'swift': 'swift',
    'm': 'objectivec',
    'mm': 'objectivec',
    'h': 'c',

    // C/C++
    'c': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'cxx': 'cpp',
    'hpp': 'cpp',
    'hxx': 'cpp',

    // C#/F#
    'cs': 'csharp',
    'fs': 'fsharp',
    'fsx': 'fsharp',

    // PHP
    'php': 'php',
    'phtml': 'php',

    // Lua
    'lua': 'lua',

    // SQL
    'sql': 'sql',

    // Markdown
    'md': 'markdown',
    'markdown': 'markdown',

    // Config files
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmake': 'cmake',
    'gradle': 'groovy',
    'groovy': 'groovy',

    // Other
    'r': 'r',
    'scala': 'scala',
    'clj': 'clojure',
    'cljs': 'clojure',
    'ex': 'elixir',
    'exs': 'elixir',
    'erl': 'erlang',
    'hrl': 'erlang',
    'hs': 'haskell',
    'lhs': 'haskell',
    'pl': 'perl',
    'pm': 'perl',
    'proto': 'protobuf',
    'graphql': 'graphql',
    'gql': 'graphql',
  };

  /// Detects the content type of a file based on its path and optional bytes.
  ///
  /// Detection priority:
  /// 1. Check file extension for known types
  /// 2. If no extension match and [bytes] provided, check if binary
  /// 3. Default to [FileContentType.plaintext] for text files
  ///
  /// Example:
  /// ```dart
  /// final type = FileTypeDetector.detectType('/path/to/file.dart');
  /// // Returns FileContentType.dart
  ///
  /// final bytes = await File('unknown').readAsBytes();
  /// final type = FileTypeDetector.detectType('unknown', bytes);
  /// // Returns plaintext or binary based on content
  /// ```
  static FileContentType detectType(String path, [List<int>? bytes]) {
    final ext = getFileExtension(path);

    if (ext != null) {
      final normalizedExt = ext.toLowerCase();
      final type = _extensionToType[normalizedExt];
      if (type != null) {
        return type;
      }

      // Check if it's a known text-based language
      if (_extensionToLanguage.containsKey(normalizedExt)) {
        return FileContentType.plaintext;
      }
    }

    // No extension match - check bytes if provided
    if (bytes != null && bytes.isNotEmpty) {
      if (isBinary(bytes)) {
        return FileContentType.binary;
      }
    }

    // Default to plaintext for unknown text files
    return FileContentType.plaintext;
  }

  /// Checks if the given bytes represent binary (non-text) content.
  ///
  /// A file is considered binary if:
  /// - It contains null bytes (0x00) in the first 8KB
  /// - More than 30% of bytes in the first 8KB are non-printable
  ///
  /// Non-printable bytes are those outside the ASCII printable range
  /// (0x20-0x7E) and common whitespace (tab, newline, carriage return).
  ///
  /// Returns false for empty byte arrays.
  static bool isBinary(List<int> bytes) {
    if (bytes.isEmpty) {
      return false;
    }

    // Check only first 8KB
    final checkLength =
        bytes.length < _binaryCheckBytes ? bytes.length : _binaryCheckBytes;

    int nonPrintableCount = 0;

    for (int i = 0; i < checkLength; i++) {
      final byte = bytes[i];

      // Null byte is a strong binary indicator
      if (byte == 0x00) {
        return true;
      }

      // Check if byte is non-printable
      if (!_isPrintable(byte)) {
        nonPrintableCount++;
      }
    }

    // If more than threshold of bytes are non-printable, it's binary
    final ratio = nonPrintableCount / checkLength;
    return ratio > _binaryThreshold;
  }

  /// Returns true if the byte is a printable ASCII character or whitespace.
  static bool _isPrintable(int byte) {
    // Tab (0x09), newline (0x0A), carriage return (0x0D)
    if (byte == 0x09 || byte == 0x0A || byte == 0x0D) {
      return true;
    }

    // Printable ASCII range: 0x20 (space) to 0x7E (~)
    return byte >= 0x20 && byte <= 0x7E;
  }

  /// Gets the syntax highlighting language identifier for a file extension.
  ///
  /// Returns null if the extension is not recognized.
  /// The extension should not include the leading dot.
  ///
  /// Example:
  /// ```dart
  /// FileTypeDetector.getLanguageFromExtension('dart'); // Returns 'dart'
  /// FileTypeDetector.getLanguageFromExtension('ts');   // Returns 'typescript'
  /// FileTypeDetector.getLanguageFromExtension('xyz');  // Returns null
  /// ```
  static String? getLanguageFromExtension(String ext) {
    final normalizedExt = ext.toLowerCase().replaceAll('.', '');
    return _extensionToLanguage[normalizedExt];
  }

  /// Extracts the file extension from a path.
  ///
  /// Returns the extension without the leading dot, or null if no extension.
  /// Handles edge cases:
  /// - Hidden files (.gitignore) - returns 'gitignore'
  /// - Multiple dots (file.config.json) - returns 'json'
  /// - No extension - returns null
  ///
  /// Example:
  /// ```dart
  /// FileTypeDetector.getFileExtension('/path/to/file.dart');    // 'dart'
  /// FileTypeDetector.getFileExtension('.gitignore');            // 'gitignore'
  /// FileTypeDetector.getFileExtension('config.local.json');     // 'json'
  /// FileTypeDetector.getFileExtension('Makefile');              // null
  /// ```
  static String? getFileExtension(String path) {
    // Get just the file name from the path
    final fileName = _getFileName(path);

    if (fileName.isEmpty) {
      return null;
    }

    // Handle hidden files that are just extensions (e.g., .gitignore)
    if (fileName.startsWith('.') && !fileName.substring(1).contains('.')) {
      // This is a dotfile without a real extension
      // Return the name after the dot as the "extension"
      return fileName.substring(1);
    }

    // Find the last dot
    final lastDotIndex = fileName.lastIndexOf('.');

    // No dot, or dot is at the start (hidden file with no extension)
    if (lastDotIndex == -1 || lastDotIndex == 0) {
      return null;
    }

    // Return everything after the last dot
    return fileName.substring(lastDotIndex + 1);
  }

  /// Extracts the file name from a path.
  static String _getFileName(String path) {
    // Handle both forward and backward slashes
    int lastSeparator = path.lastIndexOf('/');
    final backslashIndex = path.lastIndexOf('\\');

    if (backslashIndex > lastSeparator) {
      lastSeparator = backslashIndex;
    }

    if (lastSeparator == -1) {
      return path;
    }

    return path.substring(lastSeparator + 1);
  }
}
