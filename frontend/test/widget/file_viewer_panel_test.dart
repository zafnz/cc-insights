import 'dart:typed_data';

import 'package:cc_insights_v2/models/file_content.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/panels/file_viewer_panel.dart';
import 'package:cc_insights_v2/services/file_system_service.dart';
import 'package:cc_insights_v2/state/file_manager_state.dart';
import 'package:cc_insights_v2/widgets/file_viewers/binary_file_message.dart';
import 'package:cc_insights_v2/widgets/file_viewers/image_viewer.dart';
import 'package:cc_insights_v2/widgets/file_viewers/markdown_viewer.dart';
import 'package:cc_insights_v2/widgets/file_viewers/plaintext_viewer.dart';
import 'package:cc_insights_v2/widgets/file_viewers/source_code_viewer.dart';
import 'package:code_highlight_view/code_highlight_view.dart';
import 'package:drag_split_layout/drag_split_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:provider/provider.dart';

import '../test_helpers.dart';

/// Testable subclass of [FileManagerState] that allows setting loading
/// state without actual async operations.
///
/// This allows us to test loading UI directly without waiting for async
/// operations to complete.
class _TestableFileManagerState extends FileManagerState {
  bool _testIsLoadingFile = false;
  FileContent? _testFileContent;

  _TestableFileManagerState(super.project, super.fileSystemService);

  @override
  bool get isLoadingFile => _testIsLoadingFile || super.isLoadingFile;

  @override
  FileContent? get fileContent => _testFileContent ?? super.fileContent;

  /// Sets the loading file state for testing purposes.
  void setLoadingFile(bool value) {
    _testIsLoadingFile = value;
    notifyListeners();
  }

  /// Sets the file content for testing purposes.
  void setFileContent(FileContent? content) {
    _testFileContent = content;
    notifyListeners();
  }
}

void main() {
  group('FileViewerPanel', () {
    final resources = TestResources();
    late ProjectState project;
    late FakeFileSystemService fakeFileSystem;

    /// Creates a project with a primary worktree.
    ProjectState createProject() {
      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/Users/test/my-project',
          isPrimary: true,
          branch: 'main',
        ),
      );

      return ProjectState(
        const ProjectData(
          name: 'My Project',
          repoRoot: '/Users/test/my-project',
        ),
        primaryWorktree,
        autoValidate: false,
        watchFilesystem: false,
      );
    }

    /// Creates a test app with all required providers.
    Widget createTestApp(FileManagerState fileManagerState) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProjectState>.value(value: project),
          ChangeNotifierProvider<FileManagerState>.value(
            value: fileManagerState,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DragHandleProvider(
              dragHandle: const Icon(Icons.drag_indicator),
              child: const FileViewerPanel(),
            ),
          ),
        ),
      );
    }

    setUp(() {
      project = createProject();
      fakeFileSystem = FakeFileSystemService();
    });

    tearDown(() async {
      await resources.disposeAll();
    });

    group('Initial State', () {
      testWidgets('renders "Select a file" when no file', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show the no file selected message
        expect(find.text('Select a file to view'), findsOneWidget);
        expect(find.byIcon(Icons.description_outlined), findsOneWidget);

        // Should NOT show other states
        expect(find.text('Loading file...'), findsNothing);
        expect(find.text('Failed to load file'), findsNothing);
      });
    });

    group('Loading State', () {
      testWidgets('shows loading indicator during load', (tester) async {
        // Use testable state to control loading state
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Manually set loading state to test the loading UI
        state.setLoadingFile(true);
        await tester.pump();

        // Should show loading indicator and text
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Loading file...'), findsOneWidget);

        // Should NOT show other states
        expect(find.text('Select a file to view'), findsNothing);
        expect(find.text('Failed to load file'), findsNothing);
      });

      testWidgets(
        'loading indicator disappears after load completes',
        (tester) async {
          // Set up fake file system
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/test.txt',
            'Hello World',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Select a file (triggers async load)
          state.selectFile('/Users/test/my-project/test.txt');

          // Wait for load to complete
          await safePumpAndSettle(tester);

          // Loading indicator should be gone after load completes
          expect(find.text('Loading file...'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);

          // Content should be shown instead
          expect(find.byType(PlaintextFileViewer), findsOneWidget);
          expect(find.text('Hello World'), findsOneWidget);
        },
      );
    });

    group('Error State', () {
      testWidgets('shows error message on error', (tester) async {
        // Use testable state to manually set error content
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set error content
        state.setFileContent(
          FileContent.error(
            path: '/Users/test/my-project/missing.txt',
            message: 'File not found',
          ),
        );
        await tester.pump();

        // Should show error message
        expect(find.text('Failed to load file'), findsOneWidget);
        expect(find.text('File not found'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // Should NOT show other states
        expect(find.text('Select a file to view'), findsNothing);
        expect(find.text('Loading file...'), findsNothing);
      });

      testWidgets('shows full error message', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set error with longer message
        state.setFileContent(
          FileContent.error(
            path: '/Users/test/my-project/file.txt',
            message: 'Permission denied: insufficient privileges',
          ),
        );
        await tester.pump();

        // Should show the full error message
        expect(
          find.text('Permission denied: insufficient privileges'),
          findsOneWidget,
        );
      });
    });

    group('Content Type Switching', () {
      testWidgets('renders PlaintextFileViewer for plaintext',
          (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set plaintext content
        state.setFileContent(
          FileContent.plaintext(
            path: '/Users/test/my-project/notes.txt',
            content: 'Some plain text content',
          ),
        );
        await tester.pump();

        // Should show PlaintextFileViewer with content
        expect(
          find.byType(PlaintextFileViewer),
          findsOneWidget,
        );
        expect(find.text('Some plain text content'), findsOneWidget);
      });

      testWidgets('renders SourceCodeViewer for dart', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set dart content
        state.setFileContent(
          FileContent.dart(
            path: '/Users/test/my-project/main.dart',
            content: 'void main() {}',
          ),
        );
        await tester.pump();

        // Should show SourceCodeViewer with CodeHighlightView
        expect(find.byType(SourceCodeViewer), findsOneWidget);
        expect(find.byType(CodeHighlightView), findsOneWidget);
      });

      testWidgets('renders SourceCodeViewer for json', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set json content
        state.setFileContent(
          FileContent.json(
            path: '/Users/test/my-project/config.json',
            content: '{"key": "value"}',
          ),
        );
        await tester.pump();

        // Should show SourceCodeViewer with CodeHighlightView
        expect(find.byType(SourceCodeViewer), findsOneWidget);
        expect(find.byType(CodeHighlightView), findsOneWidget);
      });

      testWidgets('renders MarkdownViewer for markdown', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set markdown content
        state.setFileContent(
          FileContent.markdown(
            path: '/Users/test/my-project/README.md',
            content: '# Title\n\nContent',
          ),
        );
        await tester.pump();

        // Should show MarkdownViewer
        expect(find.byType(MarkdownViewer), findsOneWidget);
        expect(find.byType(GptMarkdown), findsOneWidget);
      });

      testWidgets('renders ImageViewer for image', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set image content (empty bytes for testing)
        state.setFileContent(
          FileContent.image(
            path: '/Users/test/my-project/logo.png',
            bytes: Uint8List(0),
          ),
        );
        await tester.pump();

        // Should show ImageViewer
        expect(find.byType(ImageViewer), findsOneWidget);
      });

      testWidgets(
        'renders BinaryFileMessage for binary',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Set binary content
          state.setFileContent(
            FileContent.binary(
              path: '/Users/test/my-project/app.exe',
              bytes: Uint8List.fromList([0x4D, 0x5A, 0x90, 0x00]),
            ),
          );
          await tester.pump();

          // Should show BinaryFileMessage
          expect(find.byType(BinaryFileMessage), findsOneWidget);
          expect(
            find.text('Cannot display binary file'),
            findsOneWidget,
          );
        },
      );
    });

    group('Header', () {
      testWidgets('displays file name and type in header', (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set content with a specific file name
        state.setFileContent(
          FileContent.plaintext(
            path: '/Users/test/my-project/notes/important.txt',
            content: 'Important notes',
          ),
        );
        await tester.pump();

        // Header should show the file name and type
        expect(find.text('important.txt (Text)'), findsOneWidget);
      });

      testWidgets('shows default title when no file', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show default title
        expect(find.text('File Viewer'), findsOneWidget);
      });

      testWidgets('has file icon in header', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Should show file/description icon in header
        expect(find.byIcon(Icons.description), findsOneWidget);
      });

      testWidgets(
        'header title updates when file changes',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Set first file
          state.setFileContent(
            FileContent.plaintext(
              path: '/Users/test/my-project/file1.txt',
              content: 'Content 1',
            ),
          );
          await tester.pump();

          expect(find.text('file1.txt (Text)'), findsOneWidget);

          // Change to different file
          state.setFileContent(
            FileContent.plaintext(
              path: '/Users/test/my-project/file2.txt',
              content: 'Content 2',
            ),
          );
          await tester.pump();

          // Header should update
          expect(find.text('file2.txt (Text)'), findsOneWidget);
          expect(find.text('file1.txt (Text)'), findsNothing);
        },
      );
    });

    group('Markdown Toggle', () {
      testWidgets(
        'toggle button appears for markdown files',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Set markdown content
          state.setFileContent(
            FileContent.markdown(
              path: '/Users/test/my-project/README.md',
              content: '# Title\n\nContent',
            ),
          );
          await tester.pump();

          // Toggle button should appear
          expect(find.byIcon(Icons.preview), findsOneWidget);
          expect(
            find.widgetWithIcon(IconButton, Icons.preview),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'no toggle button for non-markdown files',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Set plaintext content
          state.setFileContent(
            FileContent.plaintext(
              path: '/Users/test/my-project/notes.txt',
              content: 'Some text',
            ),
          );
          await tester.pump();

          // No toggle button for plaintext
          expect(find.byIcon(Icons.preview), findsNothing);
        },
      );

      testWidgets('toggle switches between preview and raw mode',
          (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Set markdown content with recognizable text
        state.setFileContent(
          FileContent.markdown(
            path: '/Users/test/my-project/README.md',
            content: '# My Title',
          ),
        );
        await tester.pump();

        // Initially in preview mode (GptMarkdown widget present)
        expect(find.byType(GptMarkdown), findsOneWidget);

        // Tap the toggle button
        await tester.tap(find.byIcon(Icons.preview));
        await tester.pump();

        // Now in raw mode - should show Text widget with raw content
        // GptMarkdown should be gone
        expect(find.byType(GptMarkdown), findsNothing);
        expect(find.text('# My Title'), findsOneWidget);

        // Tap again to go back to preview
        await tester.tap(find.byIcon(Icons.preview));
        await tester.pump();

        // Back to preview mode
        expect(find.byType(GptMarkdown), findsOneWidget);
      });
    });

    group('Error Handling - Missing Content', () {
      testWidgets('shows error when plaintext has no textContent',
          (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Create plaintext content with null textContent
        // (this shouldn't happen in normal use but we test it)
        state.setFileContent(
          FileContent(
            path: '/Users/test/my-project/test.txt',
            type: FileContentType.plaintext,
            data: null,
          ),
        );
        await tester.pump();

        // Should show error message
        expect(find.text('No content available'), findsOneWidget);
      });

      testWidgets('shows error when dart has no textContent',
          (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Create dart content with null textContent
        state.setFileContent(
          FileContent(
            path: '/Users/test/my-project/main.dart',
            type: FileContentType.dart,
            data: null,
          ),
        );
        await tester.pump();

        // Should show error message
        expect(find.text('No content available'), findsOneWidget);
      });

      testWidgets('shows error when json has no textContent',
          (tester) async {
        final state = resources.track(
          _TestableFileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Create json content with null textContent
        state.setFileContent(
          FileContent(
            path: '/Users/test/my-project/config.json',
            type: FileContentType.json,
            data: null,
          ),
        );
        await tester.pump();

        // Should show error message
        expect(find.text('No content available'), findsOneWidget);
      });

      testWidgets(
        'shows error when markdown has no textContent',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Create markdown content with null textContent
          state.setFileContent(
            FileContent(
              path: '/Users/test/my-project/README.md',
              type: FileContentType.markdown,
              data: null,
            ),
          );
          await tester.pump();

          // Should show error message
          expect(find.text('No content available'), findsOneWidget);
        },
      );
    });

    group('PanelWrapper Integration', () {
      testWidgets('renders with drag handle from provider', (tester) async {
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // The drag handle icon should be present
        // (provided by DragHandleProvider)
        expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      });
    });

    group('State Transitions', () {
      testWidgets(
        'transitions from no selection to content',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Initially shows no file selected
          expect(find.text('Select a file to view'), findsOneWidget);

          // Set file content
          state.setFileContent(
            FileContent.plaintext(
              path: '/Users/test/my-project/file.txt',
              content: 'Hello',
            ),
          );
          await tester.pump();

          // Now shows actual viewer
          expect(find.byType(PlaintextFileViewer), findsOneWidget);
          expect(find.text('Hello'), findsOneWidget);
          expect(find.text('Select a file to view'), findsNothing);
        },
      );

      testWidgets(
        'transitions from loading to content',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Set loading state
          state.setLoadingFile(true);
          await tester.pump();

          expect(find.text('Loading file...'), findsOneWidget);

          // Complete loading with content
          state.setLoadingFile(false);
          state.setFileContent(
            FileContent.dart(
              path: '/Users/test/my-project/main.dart',
              content: 'void main() {}',
            ),
          );
          await tester.pump();

          // Now shows actual viewer
          expect(find.byType(SourceCodeViewer), findsOneWidget);
          expect(find.text('Loading file...'), findsNothing);
        },
      );

      testWidgets(
        'transitions from content to error',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Start with content
          state.setFileContent(
            FileContent.plaintext(
              path: '/Users/test/my-project/file.txt',
              content: 'Content',
            ),
          );
          await tester.pump();

          expect(find.byType(PlaintextFileViewer), findsOneWidget);

          // Transition to error
          state.setFileContent(
            FileContent.error(
              path: '/Users/test/my-project/file.txt',
              message: 'File was deleted',
            ),
          );
          await tester.pump();

          // Now shows error
          expect(find.text('Failed to load file'), findsOneWidget);
          expect(find.text('File was deleted'), findsOneWidget);
          expect(find.byType(PlaintextFileViewer), findsNothing);
        },
      );

      testWidgets(
        'transitions between different content types',
        (tester) async {
          final state = resources.track(
            _TestableFileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Show dart file
          state.setFileContent(
            FileContent.dart(
              path: '/Users/test/my-project/main.dart',
              content: 'void main() {}',
            ),
          );
          await tester.pump();

          expect(find.byType(SourceCodeViewer), findsOneWidget);

          // Switch to markdown
          state.setFileContent(
            FileContent.markdown(
              path: '/Users/test/my-project/README.md',
              content: '# Readme',
            ),
          );
          await tester.pump();

          // Should show markdown now
          expect(find.byType(MarkdownViewer), findsOneWidget);
          expect(find.byType(SourceCodeViewer), findsNothing);

          // Switch to image
          state.setFileContent(
            FileContent.image(
              path: '/Users/test/my-project/logo.png',
              bytes: Uint8List(0),
            ),
          );
          await tester.pump();

          // Should show image now
          expect(find.byType(ImageViewer), findsOneWidget);
          expect(find.byType(MarkdownViewer), findsNothing);
        },
      );
    });

    group('Real File Loading Integration', () {
      testWidgets(
        'loads and displays real file from fake filesystem',
        (tester) async {
          // Set up fake file system with a real file
          fakeFileSystem.addDirectory('/Users/test/my-project');
          fakeFileSystem.addTextFile(
            '/Users/test/my-project/test.txt',
            'This is test content',
          );

          final state = resources.track(
            FileManagerState(project, fakeFileSystem),
          );

          await tester.pumpWidget(createTestApp(state));
          await safePumpAndSettle(tester);

          // Select the file (triggers async load)
          state.selectFile('/Users/test/my-project/test.txt');

          // Wait for loading to complete
          await safePumpAndSettle(tester);

          // Should show actual viewer with content
          expect(find.byType(PlaintextFileViewer), findsOneWidget);
          expect(find.text('This is test content'), findsOneWidget);

          // Header should show file name and type
          expect(find.text('test.txt (Text)'), findsOneWidget);
        },
      );

      testWidgets('handles file read error', (tester) async {
        // Don't add the file to the fake filesystem - read will fail
        final state = resources.track(
          FileManagerState(project, fakeFileSystem),
        );

        await tester.pumpWidget(createTestApp(state));
        await safePumpAndSettle(tester);

        // Select a non-existent file
        state.selectFile('/Users/test/my-project/nonexistent.txt');

        // Wait for loading to complete
        await safePumpAndSettle(tester);

        // Should show error
        expect(find.text('Failed to load file'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });
    });
  });
}
