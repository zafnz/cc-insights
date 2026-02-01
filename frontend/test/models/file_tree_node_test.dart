import 'package:cc_insights_v2/models/file_tree_node.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileTreeNodeType', () {
    test('has file and directory values', () {
      check(FileTreeNodeType.values).length.equals(2);
      check(FileTreeNodeType.values).contains(FileTreeNodeType.file);
      check(FileTreeNodeType.values).contains(FileTreeNodeType.directory);
    });
  });

  group('FileTreeNode', () {
    group('constructor', () {
      test('creates node with required fields', () {
        // Arrange & Act
        final node = FileTreeNode(
          name: 'test.dart',
          path: '/path/to/test.dart',
          type: FileTreeNodeType.file,
        );

        // Assert
        check(node.name).equals('test.dart');
        check(node.path).equals('/path/to/test.dart');
        check(node.type).equals(FileTreeNodeType.file);
        check(node.size).isNull();
        check(node.modified).isNull();
        check(node.children).isEmpty();
        check(node.isExpanded).isFalse();
      });

      test('creates node with all optional fields', () {
        // Arrange
        final modified = DateTime(2025, 1, 27, 10, 30);
        final children = [
          FileTreeNode.file(name: 'child.dart', path: '/path/child.dart'),
        ];

        // Act
        final node = FileTreeNode(
          name: 'src',
          path: '/path/src',
          type: FileTreeNodeType.directory,
          size: 1024,
          modified: modified,
          children: children,
          isExpanded: true,
        );

        // Assert
        check(node.name).equals('src');
        check(node.path).equals('/path/src');
        check(node.type).equals(FileTreeNodeType.directory);
        check(node.size).equals(1024);
        check(node.modified).equals(modified);
        check(node.children).length.equals(1);
        check(node.isExpanded).isTrue();
      });
    });

    group('FileTreeNode.file()', () {
      test('creates file node with appropriate defaults', () {
        // Act
        final node = FileTreeNode.file(
          name: 'main.dart',
          path: '/app/main.dart',
        );

        // Assert
        check(node.name).equals('main.dart');
        check(node.path).equals('/app/main.dart');
        check(node.type).equals(FileTreeNodeType.file);
        check(node.size).isNull();
        check(node.modified).isNull();
        check(node.children).isEmpty();
        check(node.isExpanded).isFalse();
      });

      test('creates file node with size and modified', () {
        // Arrange
        final modified = DateTime(2025, 1, 27);

        // Act
        final node = FileTreeNode.file(
          name: 'data.json',
          path: '/data/data.json',
          size: 2048,
          modified: modified,
        );

        // Assert
        check(node.size).equals(2048);
        check(node.modified).equals(modified);
      });
    });

    group('FileTreeNode.directory()', () {
      test('creates directory node with appropriate defaults', () {
        // Act
        final node = FileTreeNode.directory(
          name: 'lib',
          path: '/project/lib',
        );

        // Assert
        check(node.name).equals('lib');
        check(node.path).equals('/project/lib');
        check(node.type).equals(FileTreeNodeType.directory);
        check(node.size).isNull();
        check(node.modified).isNull();
        check(node.children).isEmpty();
        check(node.isExpanded).isFalse();
      });

      test('creates directory node with children', () {
        // Arrange
        final children = [
          FileTreeNode.file(name: 'a.dart', path: '/lib/a.dart'),
          FileTreeNode.file(name: 'b.dart', path: '/lib/b.dart'),
        ];

        // Act
        final node = FileTreeNode.directory(
          name: 'lib',
          path: '/project/lib',
          children: children,
          isExpanded: true,
        );

        // Assert
        check(node.children).length.equals(2);
        check(node.isExpanded).isTrue();
      });

      test('creates directory node with modified time', () {
        // Arrange
        final modified = DateTime(2025, 6, 15);

        // Act
        final node = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          modified: modified,
        );

        // Assert
        check(node.modified).equals(modified);
      });
    });

    group('helper getters', () {
      test('isFile returns true for file nodes', () {
        final node = FileTreeNode.file(name: 'test.dart', path: '/test.dart');
        check(node.isFile).isTrue();
        check(node.isDirectory).isFalse();
      });

      test('isDirectory returns true for directory nodes', () {
        final node = FileTreeNode.directory(name: 'src', path: '/src');
        check(node.isDirectory).isTrue();
        check(node.isFile).isFalse();
      });

      test('hasChildren returns true for directory with children', () {
        final node = FileTreeNode.directory(
          name: 'lib',
          path: '/lib',
          children: [
            FileTreeNode.file(name: 'main.dart', path: '/lib/main.dart'),
          ],
        );
        check(node.hasChildren).isTrue();
      });

      test('hasChildren returns false for empty directory', () {
        final node = FileTreeNode.directory(name: 'empty', path: '/empty');
        check(node.hasChildren).isFalse();
      });

      test('hasChildren returns false for file', () {
        final node = FileTreeNode.file(name: 'test.dart', path: '/test.dart');
        check(node.hasChildren).isFalse();
      });
    });

    group('copyWith()', () {
      test('preserves unchanged fields', () {
        // Arrange
        final modified = DateTime(2025, 1, 27);
        final original = FileTreeNode(
          name: 'test.dart',
          path: '/path/test.dart',
          type: FileTreeNodeType.file,
          size: 1024,
          modified: modified,
          children: const [],
          isExpanded: false,
        );

        // Act
        final copy = original.copyWith(name: 'renamed.dart');

        // Assert
        check(copy.name).equals('renamed.dart');
        check(copy.path).equals('/path/test.dart');
        check(copy.type).equals(FileTreeNodeType.file);
        check(copy.size).equals(1024);
        check(copy.modified).equals(modified);
        check(copy.children).isEmpty();
        check(copy.isExpanded).isFalse();
      });

      test('updates isExpanded for directory expansion', () {
        // Arrange
        final original = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          isExpanded: false,
        );

        // Act
        final expanded = original.copyWith(isExpanded: true);
        final collapsed = expanded.copyWith(isExpanded: false);

        // Assert
        check(original.isExpanded).isFalse();
        check(expanded.isExpanded).isTrue();
        check(collapsed.isExpanded).isFalse();
      });

      test('updates children', () {
        // Arrange
        final original = FileTreeNode.directory(name: 'src', path: '/src');
        final newChildren = [
          FileTreeNode.file(name: 'main.dart', path: '/src/main.dart'),
        ];

        // Act
        final updated = original.copyWith(children: newChildren);

        // Assert
        check(original.children).isEmpty();
        check(updated.children).length.equals(1);
      });

      test('clearSize sets size to null', () {
        // Arrange
        final original = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          size: 1024,
        );

        // Act
        final cleared = original.copyWith(clearSize: true);

        // Assert
        check(original.size).equals(1024);
        check(cleared.size).isNull();
      });

      test('clearModified sets modified to null', () {
        // Arrange
        final original = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          modified: DateTime(2025, 1, 27),
        );

        // Act
        final cleared = original.copyWith(clearModified: true);

        // Assert
        check(original.modified).isNotNull();
        check(cleared.modified).isNull();
      });

      test('updates multiple fields at once', () {
        // Arrange
        final original = FileTreeNode.file(
          name: 'old.txt',
          path: '/old.txt',
          size: 100,
        );

        // Act
        final updated = original.copyWith(
          name: 'new.txt',
          path: '/new.txt',
          size: 200,
        );

        // Assert
        check(updated.name).equals('new.txt');
        check(updated.path).equals('/new.txt');
        check(updated.size).equals(200);
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        final modified = DateTime(2025, 1, 27);
        final node1 = FileTreeNode(
          name: 'test.dart',
          path: '/path/test.dart',
          type: FileTreeNodeType.file,
          size: 1024,
          modified: modified,
        );
        final node2 = FileTreeNode(
          name: 'test.dart',
          path: '/path/test.dart',
          type: FileTreeNodeType.file,
          size: 1024,
          modified: modified,
        );

        // Assert
        check(node1 == node2).isTrue();
        check(node1.hashCode).equals(node2.hashCode);
      });

      test('equals returns false for different names', () {
        final node1 = FileTreeNode.file(name: 'a.dart', path: '/a.dart');
        final node2 = FileTreeNode.file(name: 'b.dart', path: '/a.dart');
        check(node1 == node2).isFalse();
      });

      test('equals returns false for different paths', () {
        final node1 = FileTreeNode.file(name: 'a.dart', path: '/path1/a.dart');
        final node2 = FileTreeNode.file(name: 'a.dart', path: '/path2/a.dart');
        check(node1 == node2).isFalse();
      });

      test('equals returns false for different types', () {
        final file = FileTreeNode.file(name: 'src', path: '/src');
        final dir = FileTreeNode.directory(name: 'src', path: '/src');
        check(file == dir).isFalse();
      });

      test('equals returns false for different sizes', () {
        final node1 = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          size: 100,
        );
        final node2 = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          size: 200,
        );
        check(node1 == node2).isFalse();
      });

      test('equals returns false for different modified times', () {
        final node1 = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          modified: DateTime(2025, 1, 1),
        );
        final node2 = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          modified: DateTime(2025, 1, 2),
        );
        check(node1 == node2).isFalse();
      });

      test('equals returns false for different children', () {
        final node1 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          children: [FileTreeNode.file(name: 'a.dart', path: '/src/a.dart')],
        );
        final node2 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          children: [FileTreeNode.file(name: 'b.dart', path: '/src/b.dart')],
        );
        check(node1 == node2).isFalse();
      });

      test('equals returns false for different isExpanded', () {
        final node1 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          isExpanded: false,
        );
        final node2 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          isExpanded: true,
        );
        check(node1 == node2).isFalse();
      });

      test('identical nodes are equal', () {
        final node = FileTreeNode.file(name: 'test.dart', path: '/test.dart');
        check(node == node).isTrue();
      });

      test('deep equality works with nested children', () {
        final child = FileTreeNode.file(name: 'main.dart', path: '/src/main.dart');
        final node1 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          children: [child],
        );
        final node2 = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          children: [
            FileTreeNode.file(name: 'main.dart', path: '/src/main.dart'),
          ],
        );
        check(node1 == node2).isTrue();
        check(node1.hashCode).equals(node2.hashCode);
      });
    });

    group('edge cases', () {
      test('empty name is allowed', () {
        final node = FileTreeNode.file(name: '', path: '/');
        check(node.name).equals('');
      });

      test('very long name is allowed', () {
        final longName = 'a' * 1000;
        final node = FileTreeNode.file(name: longName, path: '/$longName');
        check(node.name).equals(longName);
      });

      test('path with special characters is allowed', () {
        final path = '/path/to/file with spaces & (symbols).dart';
        final node = FileTreeNode.file(
          name: 'file with spaces & (symbols).dart',
          path: path,
        );
        check(node.path).equals(path);
      });

      test('deeply nested children work correctly', () {
        // Create a deeply nested structure
        FileTreeNode createNested(int depth, String prefix) {
          if (depth == 0) {
            return FileTreeNode.file(
              name: 'leaf.dart',
              path: '$prefix/leaf.dart',
            );
          }
          return FileTreeNode.directory(
            name: 'level$depth',
            path: '$prefix/level$depth',
            children: [createNested(depth - 1, '$prefix/level$depth')],
          );
        }

        final root = createNested(5, '');
        check(root.isDirectory).isTrue();
        check(root.hasChildren).isTrue();
      });

      test('null size and modified are handled correctly', () {
        final node = FileTreeNode(
          name: 'test.dart',
          path: '/test.dart',
          type: FileTreeNodeType.file,
          size: null,
          modified: null,
        );
        check(node.size).isNull();
        check(node.modified).isNull();
      });
    });

    group('toString()', () {
      test('returns descriptive string for file', () {
        final node = FileTreeNode.file(
          name: 'test.dart',
          path: '/test.dart',
          size: 1024,
        );
        final str = node.toString();
        check(str).contains('test.dart');
        check(str).contains('/test.dart');
        check(str).contains('file');
        check(str).contains('1024');
      });

      test('returns descriptive string for directory with children', () {
        final node = FileTreeNode.directory(
          name: 'src',
          path: '/src',
          children: [
            FileTreeNode.file(name: 'a.dart', path: '/src/a.dart'),
            FileTreeNode.file(name: 'b.dart', path: '/src/b.dart'),
          ],
          isExpanded: true,
        );
        final str = node.toString();
        check(str).contains('src');
        check(str).contains('directory');
        check(str).contains('children: 2');
        check(str).contains('isExpanded: true');
      });
    });
  });
}
