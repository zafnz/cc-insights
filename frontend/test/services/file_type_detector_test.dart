import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/services/file_type_detector.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileTypeDetector', () {
    group('detectType()', () {
      group('common file extensions', () {
        test('detects .dart files as dart', () {
          check(FileTypeDetector.detectType('/path/to/file.dart'))
              .equals(FileContentType.dart);
        });

        test('detects .json files as json', () {
          check(FileTypeDetector.detectType('/path/to/config.json'))
              .equals(FileContentType.json);
        });

        test('detects .md files as markdown', () {
          check(FileTypeDetector.detectType('/docs/README.md'))
              .equals(FileContentType.markdown);
        });

        test('detects .markdown files as markdown', () {
          check(FileTypeDetector.detectType('/docs/guide.markdown'))
              .equals(FileContentType.markdown);
        });

        test('detects .png files as image', () {
          check(FileTypeDetector.detectType('/images/logo.png'))
              .equals(FileContentType.image);
        });

        test('detects .jpg files as image', () {
          check(FileTypeDetector.detectType('/photos/sunset.jpg'))
              .equals(FileContentType.image);
        });

        test('detects .jpeg files as image', () {
          check(FileTypeDetector.detectType('/photos/portrait.jpeg'))
              .equals(FileContentType.image);
        });

        test('detects .gif files as image', () {
          check(FileTypeDetector.detectType('/animations/loading.gif'))
              .equals(FileContentType.image);
        });

        test('detects .webp files as image', () {
          check(FileTypeDetector.detectType('/images/photo.webp'))
              .equals(FileContentType.image);
        });

        test('detects .bmp files as image', () {
          check(FileTypeDetector.detectType('/images/bitmap.bmp'))
              .equals(FileContentType.image);
        });

        test('detects .ico files as image', () {
          check(FileTypeDetector.detectType('/icons/favicon.ico'))
              .equals(FileContentType.image);
        });

        test('detects .svg files as image', () {
          check(FileTypeDetector.detectType('/icons/logo.svg'))
              .equals(FileContentType.image);
        });

        test('detects .pdf files as binary', () {
          check(FileTypeDetector.detectType('/docs/manual.pdf'))
              .equals(FileContentType.binary);
        });

        test('detects .zip files as binary', () {
          check(FileTypeDetector.detectType('/archives/backup.zip'))
              .equals(FileContentType.binary);
        });

        test('detects .exe files as binary', () {
          check(FileTypeDetector.detectType('/bin/app.exe'))
              .equals(FileContentType.binary);
        });
      });

      group('known text-based languages', () {
        test('detects .js files as plaintext', () {
          check(FileTypeDetector.detectType('/src/app.js'))
              .equals(FileContentType.plaintext);
        });

        test('detects .ts files as plaintext', () {
          check(FileTypeDetector.detectType('/src/index.ts'))
              .equals(FileContentType.plaintext);
        });

        test('detects .py files as plaintext', () {
          check(FileTypeDetector.detectType('/scripts/run.py'))
              .equals(FileContentType.plaintext);
        });

        test('detects .rb files as plaintext', () {
          check(FileTypeDetector.detectType('/app/model.rb'))
              .equals(FileContentType.plaintext);
        });

        test('detects .go files as plaintext', () {
          check(FileTypeDetector.detectType('/cmd/main.go'))
              .equals(FileContentType.plaintext);
        });

        test('detects .rs files as plaintext', () {
          check(FileTypeDetector.detectType('/src/lib.rs'))
              .equals(FileContentType.plaintext);
        });

        test('detects .java files as plaintext', () {
          check(FileTypeDetector.detectType('/src/Main.java'))
              .equals(FileContentType.plaintext);
        });

        test('detects .swift files as plaintext', () {
          check(FileTypeDetector.detectType('/Sources/App.swift'))
              .equals(FileContentType.plaintext);
        });

        test('detects .html files as plaintext', () {
          check(FileTypeDetector.detectType('/public/index.html'))
              .equals(FileContentType.plaintext);
        });

        test('detects .css files as plaintext', () {
          check(FileTypeDetector.detectType('/styles/main.css'))
              .equals(FileContentType.plaintext);
        });

        test('detects .yaml files as plaintext', () {
          check(FileTypeDetector.detectType('/config.yaml'))
              .equals(FileContentType.plaintext);
        });

        test('detects .yml files as plaintext', () {
          check(FileTypeDetector.detectType('/docker-compose.yml'))
              .equals(FileContentType.plaintext);
        });

        test('detects .xml files as plaintext', () {
          check(FileTypeDetector.detectType('/resources/strings.xml'))
              .equals(FileContentType.plaintext);
        });

        test('detects .sh files as plaintext', () {
          check(FileTypeDetector.detectType('/scripts/build.sh'))
              .equals(FileContentType.plaintext);
        });

        test('detects .sql files as plaintext', () {
          check(FileTypeDetector.detectType('/migrations/001.sql'))
              .equals(FileContentType.plaintext);
        });
      });

      group('case insensitivity', () {
        test('handles uppercase .DART extension', () {
          check(FileTypeDetector.detectType('/path/to/file.DART'))
              .equals(FileContentType.dart);
        });

        test('handles uppercase .JSON extension', () {
          check(FileTypeDetector.detectType('/path/to/config.JSON'))
              .equals(FileContentType.json);
        });

        test('handles uppercase .MD extension', () {
          check(FileTypeDetector.detectType('/docs/README.MD'))
              .equals(FileContentType.markdown);
        });

        test('handles uppercase .PNG extension', () {
          check(FileTypeDetector.detectType('/images/LOGO.PNG'))
              .equals(FileContentType.image);
        });

        test('handles mixed case .Dart extension', () {
          check(FileTypeDetector.detectType('/path/to/file.Dart'))
              .equals(FileContentType.dart);
        });

        test('handles mixed case .Json extension', () {
          check(FileTypeDetector.detectType('/data/Config.Json'))
              .equals(FileContentType.json);
        });

        test('handles uppercase .JS extension', () {
          check(FileTypeDetector.detectType('/src/app.JS'))
              .equals(FileContentType.plaintext);
        });
      });

      group('multiple dots in filename', () {
        test('handles test.config.json correctly', () {
          check(FileTypeDetector.detectType('/settings/test.config.json'))
              .equals(FileContentType.json);
        });

        test('handles app.module.dart correctly', () {
          check(FileTypeDetector.detectType('/lib/app.module.dart'))
              .equals(FileContentType.dart);
        });

        test('handles style.min.css correctly', () {
          check(FileTypeDetector.detectType('/assets/style.min.css'))
              .equals(FileContentType.plaintext);
        });

        test('handles archive.tar.gz correctly', () {
          check(FileTypeDetector.detectType('/backups/archive.tar.gz'))
              .equals(FileContentType.binary);
        });

        test('handles file.v1.2.3.json correctly', () {
          check(FileTypeDetector.detectType('/data/file.v1.2.3.json'))
              .equals(FileContentType.json);
        });

        test('handles my.long.filename.with.dots.md correctly', () {
          const path = '/docs/my.long.filename.with.dots.md';
          check(FileTypeDetector.detectType(path))
              .equals(FileContentType.markdown);
        });
      });

      group('extension-less files with content analysis', () {
        test('detects binary content with null bytes', () {
          final bytes = [0x00, 0x01, 0x02, 0x03, 0x04];
          check(FileTypeDetector.detectType('Makefile', bytes))
              .equals(FileContentType.binary);
        });

        test('detects text content without null bytes', () {
          final bytes = 'Hello, world!\nThis is text.'.codeUnits;
          check(FileTypeDetector.detectType('Makefile', bytes))
              .equals(FileContentType.plaintext);
        });

        test('returns plaintext when bytes are not provided', () {
          check(FileTypeDetector.detectType('Dockerfile'))
              .equals(FileContentType.plaintext);
        });

        test('returns plaintext for known text file names without extension', () {
          // Known language extensions are checked
          check(FileTypeDetector.detectType('dockerfile'))
              .equals(FileContentType.plaintext);
        });
      });

      group('edge cases', () {
        test('handles empty file name', () {
          check(FileTypeDetector.detectType(''))
              .equals(FileContentType.plaintext);
        });

        test('handles path ending with separator', () {
          check(FileTypeDetector.detectType('/path/to/directory/'))
              .equals(FileContentType.plaintext);
        });

        test('handles dotfiles like .gitignore', () {
          // .gitignore is treated as having extension 'gitignore'
          check(FileTypeDetector.detectType('.gitignore'))
              .equals(FileContentType.plaintext);
        });

        test('handles dotfiles like .env', () {
          check(FileTypeDetector.detectType('.env'))
              .equals(FileContentType.plaintext);
        });

        test('handles .editorconfig', () {
          check(FileTypeDetector.detectType('.editorconfig'))
              .equals(FileContentType.plaintext);
        });

        test('handles file with only dots', () {
          check(FileTypeDetector.detectType('...'))
              .equals(FileContentType.plaintext);
        });

        test('handles single character extension', () {
          check(FileTypeDetector.detectType('/src/main.c'))
              .equals(FileContentType.plaintext);
        });

        test('handles Windows-style paths', () {
          check(FileTypeDetector.detectType('C:\\Users\\test\\file.dart'))
              .equals(FileContentType.dart);
        });

        test('handles mixed path separators', () {
          check(FileTypeDetector.detectType('/path/to\\file.json'))
              .equals(FileContentType.json);
        });
      });
    });

    group('isBinary()', () {
      group('binary detection', () {
        test('returns true when null bytes are present', () {
          final bytes = [0x48, 0x65, 0x6C, 0x00, 0x6C, 0x6F]; // "Hel\0lo"
          check(FileTypeDetector.isBinary(bytes)).isTrue();
        });

        test('returns true for high ratio of non-printable chars', () {
          // Create bytes with >30% non-printable characters
          final bytes = List.generate(100, (i) => i < 40 ? 0x01 : 0x41);
          check(FileTypeDetector.isBinary(bytes)).isTrue();
        });

        test('returns true for typical binary file header', () {
          // PNG file typically has binary data after the header
          // The header alone (89 50 4E 47 0D 0A 1A 0A) is mostly printable
          // Add some typical binary chunk data with null bytes
          final pngData = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, // IHDR length (contains null bytes)
          ];
          check(FileTypeDetector.isBinary(pngData)).isTrue();
        });

        test('returns true for PDF header', () {
          // %PDF-1.4
          final pdfHeader = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34];
          // PDF header is all printable, but let's test with binary content
          final pdfWithBinary = [...pdfHeader, 0x00, 0x01, 0x02];
          check(FileTypeDetector.isBinary(pdfWithBinary)).isTrue();
        });
      });

      group('text detection', () {
        test('returns false for UTF-8 text', () {
          final text = 'Hello, World! This is a test file.\n';
          final bytes = text.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('returns false for text with tabs', () {
          final text = 'Column1\tColumn2\tColumn3\n';
          final bytes = text.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('returns false for text with carriage returns', () {
          final text = 'Line 1\r\nLine 2\r\nLine 3\r\n';
          final bytes = text.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('returns false for source code', () {
          final code = '''
void main() {
  print('Hello, Dart!');
}
''';
          final bytes = code.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('returns false for JSON content', () {
          final json = '{"name": "test", "value": 42, "active": true}';
          final bytes = json.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });
      });

      group('edge cases', () {
        test('returns false for empty bytes', () {
          check(FileTypeDetector.isBinary([])).isFalse();
        });

        test('returns false for very small text files', () {
          final bytes = 'Hi'.codeUnits;
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('returns false for single character', () {
          final bytes = [0x41]; // 'A'
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('handles bytes at printable boundary', () {
          // Space (0x20) is the start of printable range
          final bytes = [0x20, 0x20, 0x20];
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('handles bytes at end of printable range', () {
          // Tilde (0x7E) is the end of printable range
          final bytes = [0x7E, 0x7E, 0x7E];
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('detects non-printable byte just outside range', () {
          // 0x7F (DEL) is just outside printable range
          // Need enough to exceed threshold
          final bytes = List.generate(100, (i) => i < 35 ? 0x7F : 0x41);
          check(FileTypeDetector.isBinary(bytes)).isTrue();
        });

        test('handles large file (only checks first 8KB)', () {
          // Create a file with binary content after 8KB
          final textPart = List.filled(8192, 0x41); // 8KB of 'A'
          final binaryPart = List.filled(1000, 0x00); // Null bytes after
          final bytes = [...textPart, ...binaryPart];
          // Should only check first 8KB, which is all text
          check(FileTypeDetector.isBinary(bytes)).isFalse();
        });

        test('threshold is approximately 30%', () {
          // 29% non-printable should be text
          final almostBinary = List.generate(100, (i) => i < 29 ? 0x01 : 0x41);
          check(FileTypeDetector.isBinary(almostBinary)).isFalse();

          // 31% non-printable should be binary
          final justBinary = List.generate(100, (i) => i < 31 ? 0x01 : 0x41);
          check(FileTypeDetector.isBinary(justBinary)).isTrue();
        });
      });
    });

    group('getLanguageFromExtension()', () {
      group('common languages', () {
        test('returns dart for .dart', () {
          check(FileTypeDetector.getLanguageFromExtension('dart'))
              .equals('dart');
        });

        test('returns javascript for .js', () {
          check(FileTypeDetector.getLanguageFromExtension('js'))
              .equals('javascript');
        });

        test('returns typescript for .ts', () {
          check(FileTypeDetector.getLanguageFromExtension('ts'))
              .equals('typescript');
        });

        test('returns python for .py', () {
          check(FileTypeDetector.getLanguageFromExtension('py'))
              .equals('python');
        });

        test('returns json for .json', () {
          check(FileTypeDetector.getLanguageFromExtension('json'))
              .equals('json');
        });

        test('returns yaml for .yaml', () {
          check(FileTypeDetector.getLanguageFromExtension('yaml'))
              .equals('yaml');
        });

        test('returns yaml for .yml', () {
          check(FileTypeDetector.getLanguageFromExtension('yml'))
              .equals('yaml');
        });

        test('returns markdown for .md', () {
          check(FileTypeDetector.getLanguageFromExtension('md'))
              .equals('markdown');
        });

        test('returns html for .html', () {
          check(FileTypeDetector.getLanguageFromExtension('html'))
              .equals('html');
        });

        test('returns css for .css', () {
          check(FileTypeDetector.getLanguageFromExtension('css'))
              .equals('css');
        });

        test('returns bash for .sh', () {
          check(FileTypeDetector.getLanguageFromExtension('sh'))
              .equals('bash');
        });

        test('returns sql for .sql', () {
          check(FileTypeDetector.getLanguageFromExtension('sql'))
              .equals('sql');
        });
      });

      group('web technologies', () {
        test('returns jsx for .jsx', () {
          check(FileTypeDetector.getLanguageFromExtension('jsx'))
              .equals('jsx');
        });

        test('returns tsx for .tsx', () {
          check(FileTypeDetector.getLanguageFromExtension('tsx'))
              .equals('tsx');
        });

        test('returns scss for .scss', () {
          check(FileTypeDetector.getLanguageFromExtension('scss'))
              .equals('scss');
        });

        test('returns sass for .sass', () {
          check(FileTypeDetector.getLanguageFromExtension('sass'))
              .equals('sass');
        });

        test('returns less for .less', () {
          check(FileTypeDetector.getLanguageFromExtension('less'))
              .equals('less');
        });
      });

      group('systems languages', () {
        test('returns c for .c', () {
          check(FileTypeDetector.getLanguageFromExtension('c'))
              .equals('c');
        });

        test('returns cpp for .cpp', () {
          check(FileTypeDetector.getLanguageFromExtension('cpp'))
              .equals('cpp');
        });

        test('returns rust for .rs', () {
          check(FileTypeDetector.getLanguageFromExtension('rs'))
              .equals('rust');
        });

        test('returns go for .go', () {
          check(FileTypeDetector.getLanguageFromExtension('go'))
              .equals('go');
        });
      });

      group('JVM languages', () {
        test('returns java for .java', () {
          check(FileTypeDetector.getLanguageFromExtension('java'))
              .equals('java');
        });

        test('returns kotlin for .kt', () {
          check(FileTypeDetector.getLanguageFromExtension('kt'))
              .equals('kotlin');
        });

        test('returns scala for .scala', () {
          check(FileTypeDetector.getLanguageFromExtension('scala'))
              .equals('scala');
        });

        test('returns groovy for .groovy', () {
          check(FileTypeDetector.getLanguageFromExtension('groovy'))
              .equals('groovy');
        });
      });

      group('.NET languages', () {
        test('returns csharp for .cs', () {
          check(FileTypeDetector.getLanguageFromExtension('cs'))
              .equals('csharp');
        });

        test('returns fsharp for .fs', () {
          check(FileTypeDetector.getLanguageFromExtension('fs'))
              .equals('fsharp');
        });
      });

      group('Apple languages', () {
        test('returns swift for .swift', () {
          check(FileTypeDetector.getLanguageFromExtension('swift'))
              .equals('swift');
        });

        test('returns objectivec for .m', () {
          check(FileTypeDetector.getLanguageFromExtension('m'))
              .equals('objectivec');
        });
      });

      group('scripting languages', () {
        test('returns ruby for .rb', () {
          check(FileTypeDetector.getLanguageFromExtension('rb'))
              .equals('ruby');
        });

        test('returns perl for .pl', () {
          check(FileTypeDetector.getLanguageFromExtension('pl'))
              .equals('perl');
        });

        test('returns lua for .lua', () {
          check(FileTypeDetector.getLanguageFromExtension('lua'))
              .equals('lua');
        });

        test('returns php for .php', () {
          check(FileTypeDetector.getLanguageFromExtension('php'))
              .equals('php');
        });
      });

      group('functional languages', () {
        test('returns haskell for .hs', () {
          check(FileTypeDetector.getLanguageFromExtension('hs'))
              .equals('haskell');
        });

        test('returns elixir for .ex', () {
          check(FileTypeDetector.getLanguageFromExtension('ex'))
              .equals('elixir');
        });

        test('returns erlang for .erl', () {
          check(FileTypeDetector.getLanguageFromExtension('erl'))
              .equals('erlang');
        });

        test('returns clojure for .clj', () {
          check(FileTypeDetector.getLanguageFromExtension('clj'))
              .equals('clojure');
        });
      });

      group('case insensitivity', () {
        test('handles uppercase DART', () {
          check(FileTypeDetector.getLanguageFromExtension('DART'))
              .equals('dart');
        });

        test('handles uppercase JSON', () {
          check(FileTypeDetector.getLanguageFromExtension('JSON'))
              .equals('json');
        });

        test('handles mixed case Dart', () {
          check(FileTypeDetector.getLanguageFromExtension('Dart'))
              .equals('dart');
        });
      });

      group('edge cases', () {
        test('returns null for unknown extension', () {
          check(FileTypeDetector.getLanguageFromExtension('xyz')).isNull();
        });

        test('returns null for empty extension', () {
          check(FileTypeDetector.getLanguageFromExtension('')).isNull();
        });

        test('handles extension with leading dot', () {
          check(FileTypeDetector.getLanguageFromExtension('.dart'))
              .equals('dart');
        });

        test('handles extension with multiple dots', () {
          check(FileTypeDetector.getLanguageFromExtension('..dart'))
              .equals('dart');
        });

        test('returns null for image extension', () {
          // Images don't have syntax highlighting languages
          check(FileTypeDetector.getLanguageFromExtension('png')).isNull();
        });

        test('returns null for binary extension', () {
          check(FileTypeDetector.getLanguageFromExtension('exe')).isNull();
        });
      });
    });

    group('getFileExtension()', () {
      group('standard file paths', () {
        test('extracts extension from simple path', () {
          check(FileTypeDetector.getFileExtension('/path/to/file.dart'))
              .equals('dart');
        });

        test('extracts extension from file name only', () {
          check(FileTypeDetector.getFileExtension('file.txt'))
              .equals('txt');
        });

        test('extracts extension from root path', () {
          check(FileTypeDetector.getFileExtension('/file.json'))
              .equals('json');
        });

        test('extracts long extension', () {
          check(FileTypeDetector.getFileExtension('/doc.markdown'))
              .equals('markdown');
        });

        test('extracts single character extension', () {
          check(FileTypeDetector.getFileExtension('/src/main.c'))
              .equals('c');
        });
      });

      group('multiple dots in filename', () {
        test('returns last extension for test.config.json', () {
          check(FileTypeDetector.getFileExtension('/test.config.json'))
              .equals('json');
        });

        test('returns last extension for app.module.ts', () {
          check(FileTypeDetector.getFileExtension('/src/app.module.ts'))
              .equals('ts');
        });

        test('returns last extension for archive.tar.gz', () {
          check(FileTypeDetector.getFileExtension('/backups/archive.tar.gz'))
              .equals('gz');
        });

        test('returns last extension for file.test.spec.dart', () {
          check(FileTypeDetector.getFileExtension('/test/file.test.spec.dart'))
              .equals('dart');
        });
      });

      group('dotfiles (hidden files)', () {
        test('returns gitignore for .gitignore', () {
          check(FileTypeDetector.getFileExtension('.gitignore'))
              .equals('gitignore');
        });

        test('returns env for .env', () {
          check(FileTypeDetector.getFileExtension('.env'))
              .equals('env');
        });

        test('returns bashrc for .bashrc', () {
          check(FileTypeDetector.getFileExtension('.bashrc'))
              .equals('bashrc');
        });

        test('returns editorconfig for .editorconfig', () {
          check(FileTypeDetector.getFileExtension('.editorconfig'))
              .equals('editorconfig');
        });

        test('handles dotfile in path', () {
          check(FileTypeDetector.getFileExtension('/home/user/.gitignore'))
              .equals('gitignore');
        });

        test('handles dotfile with extension', () {
          check(FileTypeDetector.getFileExtension('.env.local'))
              .equals('local');
        });

        test('handles .env.development', () {
          check(FileTypeDetector.getFileExtension('/project/.env.development'))
              .equals('development');
        });
      });

      group('edge cases', () {
        test('returns null for no extension', () {
          check(FileTypeDetector.getFileExtension('Makefile')).isNull();
        });

        test('returns null for Dockerfile', () {
          check(FileTypeDetector.getFileExtension('Dockerfile')).isNull();
        });

        test('returns null for file ending with dot', () {
          check(FileTypeDetector.getFileExtension('/path/file.')).equals('');
        });

        test('returns null for empty path', () {
          check(FileTypeDetector.getFileExtension('')).isNull();
        });

        test('returns null for path ending with separator', () {
          check(FileTypeDetector.getFileExtension('/path/to/dir/')).isNull();
        });

        test('handles Windows-style path', () {
          check(FileTypeDetector.getFileExtension('C:\\Users\\test\\file.dart'))
              .equals('dart');
        });

        test('handles mixed path separators', () {
          check(FileTypeDetector.getFileExtension('/path/to\\file.json'))
              .equals('json');
        });

        test('handles path with only dots', () {
          check(FileTypeDetector.getFileExtension('/path/...')).equals('');
        });

        test('handles special characters in filename', () {
          check(FileTypeDetector.getFileExtension('/path/file (1).txt'))
              .equals('txt');
        });

        test('handles spaces in path', () {
          check(FileTypeDetector.getFileExtension('/path with spaces/file.md'))
              .equals('md');
        });

        test('handles unicode in filename', () {
          check(FileTypeDetector.getFileExtension('/docs/readme.dart'))
              .equals('dart');
        });
      });
    });

    group('integration scenarios', () {
      test('detects type for typical Dart project files', () {
        check(FileTypeDetector.detectType('pubspec.yaml'))
            .equals(FileContentType.plaintext);
        check(FileTypeDetector.detectType('analysis_options.yaml'))
            .equals(FileContentType.plaintext);
        check(FileTypeDetector.detectType('lib/main.dart'))
            .equals(FileContentType.dart);
        check(FileTypeDetector.detectType('test/widget_test.dart'))
            .equals(FileContentType.dart);
        check(FileTypeDetector.detectType('README.md'))
            .equals(FileContentType.markdown);
        check(FileTypeDetector.detectType('.gitignore'))
            .equals(FileContentType.plaintext);
      });

      test('detects type for typical web project files', () {
        check(FileTypeDetector.detectType('package.json'))
            .equals(FileContentType.json);
        check(FileTypeDetector.detectType('tsconfig.json'))
            .equals(FileContentType.json);
        check(FileTypeDetector.detectType('src/index.tsx'))
            .equals(FileContentType.plaintext);
        check(FileTypeDetector.detectType('public/index.html'))
            .equals(FileContentType.plaintext);
        check(FileTypeDetector.detectType('styles/app.css'))
            .equals(FileContentType.plaintext);
      });

      test('correctly maps extension to type and language', () {
        // Verify consistency between detectType and getLanguageFromExtension
        final ext = 'dart';
        final type = FileTypeDetector.detectType('file.$ext');
        final lang = FileTypeDetector.getLanguageFromExtension(ext);

        check(type).equals(FileContentType.dart);
        check(lang).equals('dart');
      });

      test('handles full file analysis workflow', () {
        // Simulate reading a file and determining how to display it
        const path = '/project/src/main.dart';
        final bytes = 'void main() {}'.codeUnits;

        final type = FileTypeDetector.detectType(path, bytes);
        final ext = FileTypeDetector.getFileExtension(path);
        final lang = ext != null
            ? FileTypeDetector.getLanguageFromExtension(ext)
            : null;
        final binary = FileTypeDetector.isBinary(bytes);

        check(type).equals(FileContentType.dart);
        check(ext).equals('dart');
        check(lang).equals('dart');
        check(binary).isFalse();
      });
    });
  });
}
