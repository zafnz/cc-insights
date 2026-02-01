import 'dart:io';
import 'dart:typed_data';

import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/models/file_tree_node.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSystemException', () {
    test('creates exception with message only', () {
      const exception = FileSystemException('Test error');

      check(exception.message).equals('Test error');
      check(exception.path).isNull();
      check(exception.osError).isNull();
      check(exception.toString()).equals('FileSystemException: Test error');
    });

    test('creates exception with message and path', () {
      const exception = FileSystemException(
        'File not found',
        path: '/path/to/file',
      );

      check(exception.message).equals('File not found');
      check(exception.path).equals('/path/to/file');
      check(exception.osError).isNull();
      check(exception.toString())
          .equals('FileSystemException: File not found (path: /path/to/file)');
    });

    test('creates exception with message, path, and osError', () {
      final osError = OSError('Permission denied', 13);
      final exception = FileSystemException(
        'Cannot read',
        path: '/secure/file',
        osError: osError,
      );

      check(exception.message).equals('Cannot read');
      check(exception.path).equals('/secure/file');
      check(exception.osError).isNotNull();
      check(exception.toString()).contains('FileSystemException: Cannot read');
      check(exception.toString()).contains('(path: /secure/file)');
      check(exception.toString()).contains('[Permission denied]');
    });
  });

  group('RealFileSystemService', () {
    late RealFileSystemService service;
    late Directory tempDir;

    setUp(() async {
      service = const RealFileSystemService();
      tempDir = await Directory.systemTemp.createTemp('file_system_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('buildFileTree()', () {
      test('builds tree for simple directory structure', () async {
        // Create simple structure:
        // tempDir/
        //   file1.txt
        //   file2.dart
        await File('${tempDir.path}/file1.txt').writeAsString('content1');
        await File('${tempDir.path}/file2.dart').writeAsString('content2');

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        check(tree.isDirectory).isTrue();
        check(tree.path).equals(tempDir.path);
        check(tree.children.length).equals(2);

        // Files should be sorted alphabetically
        check(tree.children[0].name).equals('file1.txt');
        check(tree.children[0].isFile).isTrue();
        check(tree.children[1].name).equals('file2.dart');
        check(tree.children[1].isFile).isTrue();
      });

      test('builds tree with nested directories', () async {
        // Create nested structure:
        // tempDir/
        //   src/
        //     main.dart
        //     utils/
        //       helper.dart
        //   README.md
        await Directory('${tempDir.path}/src/utils').create(recursive: true);
        await File('${tempDir.path}/src/main.dart').writeAsString('main');
        await File('${tempDir.path}/src/utils/helper.dart')
            .writeAsString('helper');
        await File('${tempDir.path}/README.md').writeAsString('readme');

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        check(tree.children.length).equals(2);

        // Directories first, then files
        final srcDir = tree.children[0];
        check(srcDir.name).equals('src');
        check(srcDir.isDirectory).isTrue();
        check(srcDir.children.length).equals(2);

        // Inside src: utils/ then main.dart
        check(srcDir.children[0].name).equals('utils');
        check(srcDir.children[0].isDirectory).isTrue();
        check(srcDir.children[1].name).equals('main.dart');
        check(srcDir.children[1].isFile).isTrue();

        // Inside utils: helper.dart
        final utilsDir = srcDir.children[0];
        check(utilsDir.children.length).equals(1);
        check(utilsDir.children[0].name).equals('helper.dart');

        // README.md at root
        check(tree.children[1].name).equals('README.md');
        check(tree.children[1].isFile).isTrue();
      });

      test('respects maxDepth limit', () async {
        // Create deep structure:
        // tempDir/
        //   level1/
        //     level2/
        //       level3/
        //         deep.txt
        await Directory('${tempDir.path}/level1/level2/level3')
            .create(recursive: true);
        await File('${tempDir.path}/level1/level2/level3/deep.txt')
            .writeAsString('deep');
        await File('${tempDir.path}/level1/level2/file2.txt')
            .writeAsString('f2');
        await File('${tempDir.path}/level1/file1.txt').writeAsString('f1');

        // maxDepth controls how deep we scan.
        // currentDepth starts at 0 for root.
        // Children are loaded only if currentDepth < maxDepth.
        // With maxDepth=2:
        //   root (depth 0 < 2): children loaded -> level1
        //   level1 (depth 1 < 2): children loaded -> level2, file1.txt
        //   level2 (depth 2 is NOT < 2): children NOT loaded
        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
          maxDepth: 2,
        );

        // At depth 0: tempDir (root)
        final level1 = tree.children[0];
        check(level1.name).equals('level1');

        // At depth 1: level1 has children (level2 dir and file1.txt)
        check(level1.children.length).equals(2);

        final level2 = level1.children[0];
        check(level2.name).equals('level2');

        // At depth 2: level2 should have NO children (depth limit reached)
        check(level2.children.isEmpty).isTrue();
      });

      test('sorts directories first then files alphabetically', () async {
        // Create mixed structure:
        // tempDir/
        //   zebra.txt
        //   alpha/
        //   beta.txt
        //   gamma/
        await Directory('${tempDir.path}/alpha').create();
        await Directory('${tempDir.path}/gamma').create();
        await File('${tempDir.path}/zebra.txt').writeAsString('z');
        await File('${tempDir.path}/beta.txt').writeAsString('b');

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        check(tree.children.length).equals(4);

        // Directories first, alphabetically
        check(tree.children[0].name).equals('alpha');
        check(tree.children[0].isDirectory).isTrue();
        check(tree.children[1].name).equals('gamma');
        check(tree.children[1].isDirectory).isTrue();

        // Then files, alphabetically
        check(tree.children[2].name).equals('beta.txt');
        check(tree.children[2].isFile).isTrue();
        check(tree.children[3].name).equals('zebra.txt');
        check(tree.children[3].isFile).isTrue();
      });

      test('sorting is case-insensitive', () async {
        // Create files with mixed case:
        // tempDir/
        //   Apple.txt
        //   banana.txt
        //   Cherry.txt
        await File('${tempDir.path}/Cherry.txt').writeAsString('c');
        await File('${tempDir.path}/Apple.txt').writeAsString('a');
        await File('${tempDir.path}/banana.txt').writeAsString('b');

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        check(tree.children[0].name).equals('Apple.txt');
        check(tree.children[1].name).equals('banana.txt');
        check(tree.children[2].name).equals('Cherry.txt');
      });

      test('throws exception for non-existent directory', () async {
        final nonExistent = '${tempDir.path}/does_not_exist';

        await expectLater(
          () => service.buildFileTree(nonExistent, respectGitignore: false),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              'Directory does not exist',
            ),
          ),
        );
      });

      test('throws exception when path is a file', () async {
        final filePath = '${tempDir.path}/file.txt';
        await File(filePath).writeAsString('content');

        // The service checks if the path exists as a directory first,
        // so a file path returns "Directory does not exist"
        await expectLater(
          () => service.buildFileTree(filePath, respectGitignore: false),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('handles empty directory', () async {
        final emptyDir = Directory('${tempDir.path}/empty');
        await emptyDir.create();

        final tree = await service.buildFileTree(
          emptyDir.path,
          respectGitignore: false,
        );

        check(tree.isDirectory).isTrue();
        check(tree.children.isEmpty).isTrue();
      });

      test('excludes .git directory', () async {
        // Create structure with .git:
        // tempDir/
        //   .git/
        //     config
        //   src/
        //     main.dart
        await Directory('${tempDir.path}/.git').create();
        await File('${tempDir.path}/.git/config').writeAsString('git config');
        await Directory('${tempDir.path}/src').create();
        await File('${tempDir.path}/src/main.dart').writeAsString('main');

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        // .git should be excluded
        final names = tree.children.map((c) => c.name).toList();
        check(names).not((it) => it.contains('.git'));
        check(names).contains('src');
      });

      test('includes file size and modified time', () async {
        final content = 'Hello, World!';
        final filePath = '${tempDir.path}/test.txt';
        await File(filePath).writeAsString(content);

        final tree = await service.buildFileTree(
          tempDir.path,
          respectGitignore: false,
        );

        final file = tree.children[0];
        check(file.size).isNotNull();
        check(file.size!).equals(content.length);
        check(file.modified).isNotNull();
      });
    });

    group('readFile()', () {
      test('reads text file successfully', () async {
        const content = 'Hello, World!\nLine 2\nLine 3';
        final filePath = '${tempDir.path}/test.txt';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.path).equals(filePath);
        check(result.type).equals(FileContentType.plaintext);
        check(result.isText).isTrue();
        check(result.textContent).equals(content);
        check(result.error).isNull();
      });

      test('reads Dart file with correct type', () async {
        const content = 'void main() {\n  print("Hello");\n}';
        final filePath = '${tempDir.path}/main.dart';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.dart);
        check(result.textContent).equals(content);
      });

      test('reads JSON file with correct type', () async {
        const content = '{"name": "test", "value": 42}';
        final filePath = '${tempDir.path}/config.json';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.json);
        check(result.textContent).equals(content);
      });

      test('reads Markdown file with correct type', () async {
        const content = '# Title\n\nParagraph text.';
        final filePath = '${tempDir.path}/README.md';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.markdown);
        check(result.textContent).equals(content);
      });

      test('detects binary file by content', () async {
        final bytes = Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, // PNG signature start
          0x0D, 0x0A, 0x1A, 0x0A, // PNG signature end
          0x00, 0x00, 0x00, 0x0D, // Contains null bytes
          0x49, 0x48, 0x44, 0x52, // IHDR
        ]);
        final filePath = '${tempDir.path}/binary.dat';
        await File(filePath).writeAsBytes(bytes);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.binary);
        check(result.isBinary).isTrue();
        check(result.binaryContent).isNotNull();
      });

      test('reads image file as image type', () async {
        // Simple PNG file (1x1 transparent pixel)
        final pngBytes = Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, // depth, type
          0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT chunk
          0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // data
          0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, // IEND chunk
          0xAE, 0x42, 0x60, 0x82,
        ]);
        final filePath = '${tempDir.path}/image.png';
        await File(filePath).writeAsBytes(pngBytes);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.image);
        check(result.isBinary).isTrue();
        check(result.binaryContent).isNotNull();
      });

      test('returns error for file not found', () async {
        final filePath = '${tempDir.path}/does_not_exist.txt';

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.error);
        check(result.isError).isTrue();
        check(result.error).equals('File not found');
      });

      test('returns error for file exceeding size limit', () async {
        // Create file larger than 1MB
        final largeContent = 'x' * (1024 * 1024 + 100);
        final filePath = '${tempDir.path}/large.txt';
        await File(filePath).writeAsString(largeContent);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.error);
        check(result.isError).isTrue();
        check(result.error!).contains('File too large');
        check(result.error!).contains('Maximum size');
      });

      test('reads large image file (no size limit for images)', () async {
        // Create a "large" image file (just binary data with .png extension)
        final largeImageData = Uint8List(1024 * 1024 + 100);
        // Add PNG signature at start
        largeImageData[0] = 0x89;
        largeImageData[1] = 0x50;
        largeImageData[2] = 0x4E;
        largeImageData[3] = 0x47;

        final filePath = '${tempDir.path}/large_image.png';
        await File(filePath).writeAsBytes(largeImageData);

        final result = await service.readFile(filePath);

        // Images have no size limit
        check(result.type).equals(FileContentType.image);
        check(result.isError).isFalse();
      });

      test('handles empty file', () async {
        final filePath = '${tempDir.path}/empty.txt';
        await File(filePath).writeAsString('');

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.plaintext);
        check(result.textContent).equals('');
      });

      test('handles file with special characters in content', () async {
        const content = 'Hello\t\nWorld\r\n!@#\$%^&*()';
        final filePath = '${tempDir.path}/special.txt';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.plaintext);
        check(result.textContent).equals(content);
      });

      test('handles UTF-8 content with unicode characters', () async {
        const content = 'Hello World - Emoji \u{1F600} and symbols';
        final filePath = '${tempDir.path}/unicode.txt';
        await File(filePath).writeAsString(content);

        final result = await service.readFile(filePath);

        check(result.type).equals(FileContentType.plaintext);
        check(result.textContent!.contains('Emoji')).isTrue();
      });
    });

    group('isIgnored()', () {
      test('returns false for non-git directory', () async {
        // tempDir is not a git repo
        final filePath = '${tempDir.path}/file.txt';
        await File(filePath).writeAsString('content');

        final result = await service.isIgnored(tempDir.path, filePath);

        check(result).isFalse();
      });

      // Note: Testing actual .gitignore behavior requires a git repository
      // which is more suitable for integration tests. Here we test the
      // fallback behavior when git is not available or fails.
    });
  });

  group('FakeFileSystemService', () {
    late FakeFileSystemService service;

    setUp(() {
      service = FakeFileSystemService();
    });

    group('buildFileTree()', () {
      test('builds tree from in-memory structure', () async {
        service.addDirectory('/root');
        service.addDirectory('/root/src');
        service.addTextFile('/root/src/main.dart', 'void main() {}');
        service.addTextFile('/root/README.md', '# Title');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        check(tree.name).equals('root');
        check(tree.isDirectory).isTrue();
        check(tree.children.length).equals(2);

        // Directories first
        check(tree.children[0].name).equals('src');
        check(tree.children[0].isDirectory).isTrue();
        check(tree.children[0].children.length).equals(1);
        check(tree.children[0].children[0].name).equals('main.dart');

        // Then files
        check(tree.children[1].name).equals('README.md');
        check(tree.children[1].isFile).isTrue();
      });

      test('throws exception for non-existent directory', () async {
        await expectLater(
          () => service.buildFileTree('/nonexistent'),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              'Directory does not exist',
            ),
          ),
        );
      });

      test('throws exception when path is a file', () async {
        service.addTextFile('/root/file.txt', 'content');

        await expectLater(
          () => service.buildFileTree('/root/file.txt'),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.message,
              'message',
              'Path is not a directory',
            ),
          ),
        );
      });

      test('respects maxDepth limit', () async {
        service.addDirectory('/root');
        service.addDirectory('/root/level1');
        service.addDirectory('/root/level1/level2');
        service.addDirectory('/root/level1/level2/level3');
        service.addTextFile('/root/level1/level2/level3/deep.txt', 'content');

        // maxDepth controls how deep we scan.
        // currentDepth starts at 0 for root.
        // Children are loaded only if currentDepth < maxDepth.
        // With maxDepth=2:
        //   root (depth 0 < 2): children loaded -> level1
        //   level1 (depth 1 < 2): children loaded -> level2
        //   level2 (depth 2 is NOT < 2): children NOT loaded
        final tree = await service.buildFileTree(
          '/root',
          maxDepth: 2,
          respectGitignore: false,
        );

        // root at depth 0
        check(tree.children.length).equals(1);

        final level1 = tree.children[0];
        check(level1.name).equals('level1');

        // level1 at depth 1, has children
        check(level1.children.length).equals(1);

        final level2 = level1.children[0];
        check(level2.name).equals('level2');

        // level2 at depth 2: children NOT loaded
        check(level2.children.isEmpty).isTrue();
      });

      test('filters gitignored paths when respectGitignore is true', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/visible.txt', 'visible');
        service.addTextFile('/root/ignored.txt', 'ignored');
        service.addIgnoredPath('/root/ignored.txt');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: true,
        );

        final names = tree.children.map((c) => c.name).toList();
        check(names).contains('visible.txt');
        check(names).not((it) => it.contains('ignored.txt'));
      });

      test('shows all files when respectGitignore is false', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/visible.txt', 'visible');
        service.addTextFile('/root/ignored.txt', 'ignored');
        service.addIgnoredPath('/root/ignored.txt');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        final names = tree.children.map((c) => c.name).toList();
        check(names).contains('visible.txt');
        check(names).contains('ignored.txt');
      });

      test('filters ignored directories', () async {
        service.addDirectory('/root');
        service.addDirectory('/root/node_modules');
        service.addTextFile('/root/node_modules/package.json', '{}');
        service.addDirectory('/root/src');
        service.addTextFile('/root/src/main.dart', 'main');
        service.addIgnoredPath('/root/node_modules');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: true,
        );

        final names = tree.children.map((c) => c.name).toList();
        check(names).contains('src');
        check(names).not((it) => it.contains('node_modules'));
      });

      test('sorts directories before files', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/zebra.txt', 'z');
        service.addDirectory('/root/alpha');
        service.addTextFile('/root/beta.txt', 'b');
        service.addDirectory('/root/gamma');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        check(tree.children.length).equals(4);
        check(tree.children[0].name).equals('alpha');
        check(tree.children[0].isDirectory).isTrue();
        check(tree.children[1].name).equals('gamma');
        check(tree.children[1].isDirectory).isTrue();
        check(tree.children[2].name).equals('beta.txt');
        check(tree.children[2].isFile).isTrue();
        check(tree.children[3].name).equals('zebra.txt');
        check(tree.children[3].isFile).isTrue();
      });

      test('handles empty directory', () async {
        service.addDirectory('/root');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        check(tree.isDirectory).isTrue();
        check(tree.children.isEmpty).isTrue();
      });

      test('calculates file size from content length', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/file.txt', 'Hello');

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        final file = tree.children[0];
        check(file.size).equals(5);
      });

      test('calculates binary file size from bytes length', () async {
        service.addDirectory('/root');
        service.addBinaryFile('/root/data.bin', [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

        final tree = await service.buildFileTree(
          '/root',
          respectGitignore: false,
        );

        final file = tree.children[0];
        check(file.size).equals(10);
      });
    });

    group('readFile()', () {
      test('reads text file with correct type', () async {
        service.addTextFile('/root/main.dart', 'void main() {}');

        final result = await service.readFile('/root/main.dart');

        check(result.type).equals(FileContentType.dart);
        check(result.textContent).equals('void main() {}');
      });

      test('reads JSON file with correct type', () async {
        service.addTextFile('/root/config.json', '{"key": "value"}');

        final result = await service.readFile('/root/config.json');

        check(result.type).equals(FileContentType.json);
        check(result.textContent).equals('{"key": "value"}');
      });

      test('reads Markdown file with correct type', () async {
        service.addTextFile('/root/README.md', '# Title');

        final result = await service.readFile('/root/README.md');

        check(result.type).equals(FileContentType.markdown);
        check(result.textContent).equals('# Title');
      });

      test('reads plaintext file with unknown extension', () async {
        service.addTextFile('/root/file.xyz', 'content');

        final result = await service.readFile('/root/file.xyz');

        check(result.type).equals(FileContentType.plaintext);
        check(result.textContent).equals('content');
      });

      test('reads binary file as binary type', () async {
        service.addBinaryFile('/root/data.bin', [0x00, 0x01, 0x02, 0x03]);

        final result = await service.readFile('/root/data.bin');

        check(result.type).equals(FileContentType.binary);
        check(result.isBinary).isTrue();
        check(result.binaryContent).isNotNull();
        check(result.binaryContent!.length).equals(4);
      });

      test('reads image file as image type', () async {
        service.addBinaryFile('/root/logo.png', [0x89, 0x50, 0x4E, 0x47]);

        final result = await service.readFile('/root/logo.png');

        check(result.type).equals(FileContentType.image);
        check(result.isBinary).isTrue();
      });

      test('returns error for file not found', () async {
        final result = await service.readFile('/nonexistent.txt');

        check(result.type).equals(FileContentType.error);
        check(result.error).equals('File not found');
      });

      test('returns error when reading directory as file', () async {
        service.addDirectory('/root');

        final result = await service.readFile('/root');

        check(result.type).equals(FileContentType.error);
        check(result.error).equals('Cannot read directory as file');
      });
    });

    group('isIgnored()', () {
      test('returns true for added ignored paths', () async {
        service.addIgnoredPath('/root/ignored.txt');

        final result = await service.isIgnored('/root', '/root/ignored.txt');

        check(result).isTrue();
      });

      test('returns false for non-ignored paths', () async {
        service.addTextFile('/root/visible.txt', 'content');

        final result = await service.isIgnored('/root', '/root/visible.txt');

        check(result).isFalse();
      });
    });

    group('configurable delay', () {
      test('simulates delay for buildFileTree', () async {
        service.delay = const Duration(milliseconds: 50);
        service.addDirectory('/root');

        final stopwatch = Stopwatch()..start();
        await service.buildFileTree('/root');
        stopwatch.stop();

        check(stopwatch.elapsedMilliseconds).isGreaterOrEqual(40);
      });

      test('simulates delay for readFile', () async {
        service.delay = const Duration(milliseconds: 50);
        service.addTextFile('/root/file.txt', 'content');

        final stopwatch = Stopwatch()..start();
        await service.readFile('/root/file.txt');
        stopwatch.stop();

        check(stopwatch.elapsedMilliseconds).isGreaterOrEqual(40);
      });

      test('simulates delay for isIgnored', () async {
        service.delay = const Duration(milliseconds: 50);
        service.addIgnoredPath('/root/ignored.txt');

        final stopwatch = Stopwatch()..start();
        await service.isIgnored('/root', '/root/ignored.txt');
        stopwatch.stop();

        check(stopwatch.elapsedMilliseconds).isGreaterOrEqual(40);
      });

      test('no delay when duration is zero', () async {
        service.delay = Duration.zero;
        service.addDirectory('/root');
        service.addTextFile('/root/file.txt', 'content');

        final stopwatch = Stopwatch()..start();
        await service.buildFileTree('/root');
        await service.readFile('/root/file.txt');
        await service.isIgnored('/root', '/root/file.txt');
        stopwatch.stop();

        // Should complete quickly (< 50ms) with no delay
        check(stopwatch.elapsedMilliseconds).isLessThan(50);
      });
    });

    group('clear()', () {
      test('clears all files and directories', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/file.txt', 'content');

        service.clear();

        await expectLater(
          () => service.buildFileTree('/root'),
          throwsA(isA<FileSystemException>()),
        );
        check((await service.readFile('/root/file.txt')).isError).isTrue();
      });

      test('clears ignored paths', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/file.txt', 'content');
        service.addIgnoredPath('/root/file.txt');

        service.clear();

        // Re-add after clear
        service.addDirectory('/root');
        service.addTextFile('/root/file.txt', 'content');

        final result = await service.isIgnored('/root', '/root/file.txt');
        check(result).isFalse();
      });
    });

    group('edge cases', () {
      test('handles nested path not under parent', () async {
        service.addDirectory('/root');
        service.addDirectory('/other');
        service.addTextFile('/other/file.txt', 'content');

        final tree = await service.buildFileTree('/root');

        // /other/file.txt should not appear under /root
        check(tree.children.isEmpty).isTrue();
      });

      test('handles deeply nested structure', () async {
        service.addDirectory('/a');
        service.addDirectory('/a/b');
        service.addDirectory('/a/b/c');
        service.addDirectory('/a/b/c/d');
        service.addDirectory('/a/b/c/d/e');
        service.addTextFile('/a/b/c/d/e/deep.txt', 'deep');

        final tree = await service.buildFileTree('/a', respectGitignore: false);

        var current = tree;
        final path = ['a', 'b', 'c', 'd', 'e', 'deep.txt'];
        for (int i = 0; i < path.length; i++) {
          check(current.name).equals(path[i]);
          if (i < path.length - 1) {
            check(current.children.isNotEmpty).isTrue();
            current = current.children[0];
          }
        }
      });

      test('handles files at multiple levels', () async {
        service.addDirectory('/root');
        service.addTextFile('/root/root.txt', '1');
        service.addDirectory('/root/sub');
        service.addTextFile('/root/sub/sub.txt', '2');
        service.addDirectory('/root/sub/deep');
        service.addTextFile('/root/sub/deep/deep.txt', '3');

        final tree = await service.buildFileTree('/root', respectGitignore: false);

        check(tree.children.length).equals(2);
        check(tree.children[0].name).equals('sub'); // dir first
        check(tree.children[1].name).equals('root.txt');

        final sub = tree.children[0];
        check(sub.children.length).equals(2);
        check(sub.children[0].name).equals('deep'); // dir first
        check(sub.children[1].name).equals('sub.txt');

        final deep = sub.children[0];
        check(deep.children.length).equals(1);
        check(deep.children[0].name).equals('deep.txt');
      });
    });
  });

  group('FileSystemService constants', () {
    test('defaultMaxDepth is 10', () {
      check(FileSystemService.defaultMaxDepth).equals(10);
    });

    test('gitTimeout is 1 second', () {
      check(FileSystemService.gitTimeout)
          .equals(const Duration(seconds: 1));
    });
  });

  group('maxTextFileSize constant', () {
    test('is 1MB', () {
      check(maxTextFileSize).equals(1024 * 1024);
    });
  });
}
