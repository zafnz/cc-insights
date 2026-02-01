import 'dart:typed_data';

import 'package:cc_insights_v2/models/file_content.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileContentType', () {
    test('has all expected values', () {
      check(FileContentType.values).length.equals(7);
      check(FileContentType.values).contains(FileContentType.plaintext);
      check(FileContentType.values).contains(FileContentType.dart);
      check(FileContentType.values).contains(FileContentType.json);
      check(FileContentType.values).contains(FileContentType.markdown);
      check(FileContentType.values).contains(FileContentType.image);
      check(FileContentType.values).contains(FileContentType.binary);
      check(FileContentType.values).contains(FileContentType.error);
    });
  });

  group('FileContent', () {
    group('constructor', () {
      test('creates content with required fields', () {
        // Arrange & Act
        final content = FileContent(
          path: '/path/to/file.txt',
          type: FileContentType.plaintext,
        );

        // Assert
        check(content.path).equals('/path/to/file.txt');
        check(content.type).equals(FileContentType.plaintext);
        check(content.data).isNull();
        check(content.error).isNull();
      });

      test('creates content with all fields', () {
        // Act
        final content = FileContent(
          path: '/path/to/file.txt',
          type: FileContentType.error,
          data: 'some data',
          error: 'File not found',
        );

        // Assert
        check(content.path).equals('/path/to/file.txt');
        check(content.type).equals(FileContentType.error);
        check(content.data).equals('some data');
        check(content.error).equals('File not found');
      });
    });

    group('FileContent.plaintext()', () {
      test('creates plaintext content correctly', () {
        // Act
        final content = FileContent.plaintext(
          path: '/data/readme.txt',
          content: 'Hello, world!',
        );

        // Assert
        check(content.path).equals('/data/readme.txt');
        check(content.type).equals(FileContentType.plaintext);
        check(content.data).equals('Hello, world!');
        check(content.error).isNull();
      });

      test('handles empty content', () {
        final content = FileContent.plaintext(
          path: '/empty.txt',
          content: '',
        );
        check(content.data).equals('');
      });

      test('handles multiline content', () {
        final multiline = 'Line 1\nLine 2\nLine 3';
        final content = FileContent.plaintext(
          path: '/multi.txt',
          content: multiline,
        );
        check(content.data).equals(multiline);
      });
    });

    group('FileContent.dart()', () {
      test('creates Dart content correctly', () {
        // Arrange
        const dartCode = '''
void main() {
  print('Hello, Dart!');
}
''';

        // Act
        final content = FileContent.dart(
          path: '/app/main.dart',
          content: dartCode,
        );

        // Assert
        check(content.path).equals('/app/main.dart');
        check(content.type).equals(FileContentType.dart);
        check(content.data).equals(dartCode);
      });
    });

    group('FileContent.json()', () {
      test('creates JSON content correctly', () {
        // Arrange
        const jsonContent = '{"name": "test", "value": 42}';

        // Act
        final content = FileContent.json(
          path: '/data/config.json',
          content: jsonContent,
        );

        // Assert
        check(content.path).equals('/data/config.json');
        check(content.type).equals(FileContentType.json);
        check(content.data).equals(jsonContent);
      });
    });

    group('FileContent.markdown()', () {
      test('creates Markdown content correctly', () {
        // Arrange
        const mdContent = '''
# Heading

This is **bold** and *italic*.

- Item 1
- Item 2
''';

        // Act
        final content = FileContent.markdown(
          path: '/docs/README.md',
          content: mdContent,
        );

        // Assert
        check(content.path).equals('/docs/README.md');
        check(content.type).equals(FileContentType.markdown);
        check(content.data).equals(mdContent);
      });
    });

    group('FileContent.image()', () {
      test('creates image content correctly', () {
        // Arrange
        final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

        // Act
        final content = FileContent.image(
          path: '/images/logo.png',
          bytes: bytes,
        );

        // Assert
        check(content.path).equals('/images/logo.png');
        check(content.type).equals(FileContentType.image);
        check(content.data).isA<Uint8List>();
        check((content.data as Uint8List).length).equals(8);
      });

      test('handles empty image bytes', () {
        final content = FileContent.image(
          path: '/empty.png',
          bytes: Uint8List(0),
        );
        check((content.data as Uint8List).length).equals(0);
      });
    });

    group('FileContent.binary()', () {
      test('creates binary content correctly', () {
        // Arrange
        final bytes = Uint8List.fromList([0x00, 0xFF, 0x7F, 0x80]);

        // Act
        final content = FileContent.binary(
          path: '/data/file.bin',
          bytes: bytes,
        );

        // Assert
        check(content.path).equals('/data/file.bin');
        check(content.type).equals(FileContentType.binary);
        check(content.data).isA<Uint8List>();
      });
    });

    group('FileContent.error()', () {
      test('creates error content correctly', () {
        // Act
        final content = FileContent.error(
          path: '/nonexistent/file.txt',
          message: 'File not found',
        );

        // Assert
        check(content.path).equals('/nonexistent/file.txt');
        check(content.type).equals(FileContentType.error);
        check(content.data).isNull();
        check(content.error).equals('File not found');
      });

      test('handles empty error message', () {
        final content = FileContent.error(
          path: '/file.txt',
          message: '',
        );
        check(content.error).equals('');
      });

      test('handles detailed error message', () {
        const errorMsg = 'Permission denied: User does not have read access '
            'to /protected/secret.txt';
        final content = FileContent.error(
          path: '/protected/secret.txt',
          message: errorMsg,
        );
        check(content.error).equals(errorMsg);
      });
    });

    group('helper getters', () {
      group('isText', () {
        test('returns true for plaintext', () {
          final content = FileContent.plaintext(
            path: '/test.txt',
            content: 'text',
          );
          check(content.isText).isTrue();
        });

        test('returns true for dart', () {
          final content = FileContent.dart(
            path: '/test.dart',
            content: 'void main() {}',
          );
          check(content.isText).isTrue();
        });

        test('returns true for json', () {
          final content = FileContent.json(
            path: '/test.json',
            content: '{}',
          );
          check(content.isText).isTrue();
        });

        test('returns true for markdown', () {
          final content = FileContent.markdown(
            path: '/test.md',
            content: '# Heading',
          );
          check(content.isText).isTrue();
        });

        test('returns false for image', () {
          final content = FileContent.image(
            path: '/test.png',
            bytes: Uint8List(0),
          );
          check(content.isText).isFalse();
        });

        test('returns false for binary', () {
          final content = FileContent.binary(
            path: '/test.bin',
            bytes: Uint8List(0),
          );
          check(content.isText).isFalse();
        });

        test('returns false for error', () {
          final content = FileContent.error(
            path: '/test.txt',
            message: 'error',
          );
          check(content.isText).isFalse();
        });
      });

      group('isBinary', () {
        test('returns true for image', () {
          final content = FileContent.image(
            path: '/test.png',
            bytes: Uint8List(0),
          );
          check(content.isBinary).isTrue();
        });

        test('returns true for binary', () {
          final content = FileContent.binary(
            path: '/test.bin',
            bytes: Uint8List(0),
          );
          check(content.isBinary).isTrue();
        });

        test('returns false for text types', () {
          final content = FileContent.plaintext(
            path: '/test.txt',
            content: 'text',
          );
          check(content.isBinary).isFalse();
        });

        test('returns false for error', () {
          final content = FileContent.error(
            path: '/test.txt',
            message: 'error',
          );
          check(content.isBinary).isFalse();
        });
      });

      group('isError', () {
        test('returns true for error type', () {
          final content = FileContent.error(
            path: '/test.txt',
            message: 'error',
          );
          check(content.isError).isTrue();
        });

        test('returns false for non-error types', () {
          final content = FileContent.plaintext(
            path: '/test.txt',
            content: 'text',
          );
          check(content.isError).isFalse();
        });
      });

      group('textContent', () {
        test('returns string for text types', () {
          final content = FileContent.plaintext(
            path: '/test.txt',
            content: 'Hello, world!',
          );
          check(content.textContent).equals('Hello, world!');
        });

        test('returns null for binary types', () {
          final content = FileContent.binary(
            path: '/test.bin',
            bytes: Uint8List(0),
          );
          check(content.textContent).isNull();
        });

        test('returns null for error type', () {
          final content = FileContent.error(
            path: '/test.txt',
            message: 'error',
          );
          check(content.textContent).isNull();
        });
      });

      group('binaryContent', () {
        test('returns Uint8List for binary types', () {
          final bytes = Uint8List.fromList([1, 2, 3]);
          final content = FileContent.binary(
            path: '/test.bin',
            bytes: bytes,
          );
          check(content.binaryContent).isNotNull();
          check(content.binaryContent!.length).equals(3);
        });

        test('returns Uint8List for image type', () {
          final bytes = Uint8List.fromList([1, 2, 3]);
          final content = FileContent.image(
            path: '/test.png',
            bytes: bytes,
          );
          check(content.binaryContent).isNotNull();
        });

        test('returns null for text types', () {
          final content = FileContent.plaintext(
            path: '/test.txt',
            content: 'text',
          );
          check(content.binaryContent).isNull();
        });

        test('returns null for error type', () {
          final content = FileContent.error(
            path: '/test.txt',
            message: 'error',
          );
          check(content.binaryContent).isNull();
        });
      });

      group('fileName', () {
        test('extracts file name from path', () {
          final content = FileContent.plaintext(
            path: '/path/to/file.txt',
            content: '',
          );
          check(content.fileName).equals('file.txt');
        });

        test('handles root path', () {
          final content = FileContent.plaintext(
            path: '/file.txt',
            content: '',
          );
          check(content.fileName).equals('file.txt');
        });

        test('handles path without separator', () {
          final content = FileContent.plaintext(
            path: 'file.txt',
            content: '',
          );
          check(content.fileName).equals('file.txt');
        });

        test('handles path ending with separator', () {
          final content = FileContent.plaintext(
            path: '/path/to/dir/',
            content: '',
          );
          check(content.fileName).equals('');
        });
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        // Arrange
        final original = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello',
        );

        // Act
        final copy = original.copyWith(path: '/new.txt');

        // Assert
        check(copy.path).equals('/new.txt');
        check(copy.type).equals(FileContentType.plaintext);
        check(copy.data).equals('Hello');
        check(copy.error).isNull();
      });

      test('updates type', () {
        final original = FileContent.plaintext(
          path: '/test.txt',
          content: 'code',
        );
        final updated = original.copyWith(type: FileContentType.dart);
        check(updated.type).equals(FileContentType.dart);
      });

      test('updates data', () {
        final original = FileContent.plaintext(
          path: '/test.txt',
          content: 'old',
        );
        final updated = original.copyWith(data: 'new');
        check(updated.data).equals('new');
      });

      test('clearData sets data to null', () {
        final original = FileContent.plaintext(
          path: '/test.txt',
          content: 'content',
        );
        final cleared = original.copyWith(clearData: true);
        check(cleared.data).isNull();
      });

      test('updates error', () {
        final original = FileContent.error(
          path: '/test.txt',
          message: 'old error',
        );
        final updated = original.copyWith(error: 'new error');
        check(updated.error).equals('new error');
      });

      test('clearError sets error to null', () {
        final original = FileContent.error(
          path: '/test.txt',
          message: 'error',
        );
        final cleared = original.copyWith(clearError: true);
        check(cleared.error).isNull();
      });

      test('updates multiple fields at once', () {
        final original = FileContent.plaintext(
          path: '/old.txt',
          content: 'old content',
        );
        final updated = original.copyWith(
          path: '/new.dart',
          type: FileContentType.dart,
          data: 'new code',
        );
        check(updated.path).equals('/new.dart');
        check(updated.type).equals(FileContentType.dart);
        check(updated.data).equals('new code');
      });
    });

    group('equality', () {
      test('equals returns true for identical text content', () {
        final content1 = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello',
        );
        final content2 = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello',
        );
        check(content1 == content2).isTrue();
        check(content1.hashCode).equals(content2.hashCode);
      });

      test('equals returns true for identical binary content', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final content1 = FileContent.binary(
          path: '/test.bin',
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        );
        final content2 = FileContent.binary(
          path: '/test.bin',
          bytes: bytes,
        );
        check(content1 == content2).isTrue();
      });

      test('equals returns true for identical error content', () {
        final content1 = FileContent.error(
          path: '/test.txt',
          message: 'Not found',
        );
        final content2 = FileContent.error(
          path: '/test.txt',
          message: 'Not found',
        );
        check(content1 == content2).isTrue();
        check(content1.hashCode).equals(content2.hashCode);
      });

      test('equals returns false for different paths', () {
        final content1 = FileContent.plaintext(
          path: '/path1/test.txt',
          content: 'Hello',
        );
        final content2 = FileContent.plaintext(
          path: '/path2/test.txt',
          content: 'Hello',
        );
        check(content1 == content2).isFalse();
      });

      test('equals returns false for different types', () {
        final content1 = FileContent.plaintext(
          path: '/test.txt',
          content: 'code',
        );
        final content2 = FileContent.dart(
          path: '/test.txt',
          content: 'code',
        );
        check(content1 == content2).isFalse();
      });

      test('equals returns false for different data', () {
        final content1 = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello',
        );
        final content2 = FileContent.plaintext(
          path: '/test.txt',
          content: 'World',
        );
        check(content1 == content2).isFalse();
      });

      test('equals returns false for different binary data', () {
        final content1 = FileContent.binary(
          path: '/test.bin',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        final content2 = FileContent.binary(
          path: '/test.bin',
          bytes: Uint8List.fromList([4, 5, 6]),
        );
        check(content1 == content2).isFalse();
      });

      test('equals returns false for different error messages', () {
        final content1 = FileContent.error(
          path: '/test.txt',
          message: 'Error 1',
        );
        final content2 = FileContent.error(
          path: '/test.txt',
          message: 'Error 2',
        );
        check(content1 == content2).isFalse();
      });

      test('identical instances are equal', () {
        final content = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello',
        );
        check(content == content).isTrue();
      });

      test('equals handles null data correctly', () {
        const content1 = FileContent(
          path: '/test.txt',
          type: FileContentType.error,
          data: null,
        );
        const content2 = FileContent(
          path: '/test.txt',
          type: FileContentType.error,
          data: null,
        );
        check(content1 == content2).isTrue();
      });
    });

    group('edge cases', () {
      test('handles unicode content', () {
        final content = FileContent.plaintext(
          path: '/unicode.txt',
          content: 'Hello, 世界! 🌍 Привет мир',
        );
        check(content.data).equals('Hello, 世界! 🌍 Привет мир');
      });

      test('handles very large text content', () {
        final largeText = 'a' * 1000000; // 1MB of text
        final content = FileContent.plaintext(
          path: '/large.txt',
          content: largeText,
        );
        check((content.data as String).length).equals(1000000);
      });

      test('handles large binary content', () {
        final largeBytes = Uint8List(1000000); // 1MB of bytes
        final content = FileContent.binary(
          path: '/large.bin',
          bytes: largeBytes,
        );
        check((content.data as Uint8List).length).equals(1000000);
      });

      test('handles special characters in path', () {
        final content = FileContent.plaintext(
          path: '/path/with spaces/and (special) chars!/file.txt',
          content: '',
        );
        check(content.path)
            .equals('/path/with spaces/and (special) chars!/file.txt');
        check(content.fileName).equals('file.txt');
      });

      test('handles empty path', () {
        final content = FileContent.plaintext(
          path: '',
          content: 'content',
        );
        check(content.path).equals('');
        check(content.fileName).equals('');
      });
    });

    group('toString()', () {
      test('returns descriptive string for text content', () {
        final content = FileContent.plaintext(
          path: '/test.txt',
          content: 'Hello, world!',
        );
        final str = content.toString();
        check(str).contains('/test.txt');
        check(str).contains('plaintext');
        check(str).contains('13 chars');
      });

      test('returns descriptive string for binary content', () {
        final content = FileContent.binary(
          path: '/test.bin',
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
        );
        final str = content.toString();
        check(str).contains('/test.bin');
        check(str).contains('binary');
        check(str).contains('5 bytes');
      });

      test('returns descriptive string for error content', () {
        final content = FileContent.error(
          path: '/test.txt',
          message: 'File not found',
        );
        final str = content.toString();
        check(str).contains('/test.txt');
        check(str).contains('error');
        check(str).contains('File not found');
      });

      test('handles null data in toString', () {
        const content = FileContent(
          path: '/test.txt',
          type: FileContentType.error,
          data: null,
        );
        final str = content.toString();
        check(str).contains('null');
      });
    });
  });
}
