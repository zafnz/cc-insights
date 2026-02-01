import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/file_content.dart';
import '../models/file_tree_node.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/file_system_service.dart';

/// State management for the File Manager feature.
///
/// Manages worktree selection, file tree building, and file content loading.
/// This state is separate from [SelectionState] to avoid cross-contamination
/// between the main screen and file manager screen.
///
/// Use [selectWorktree] to choose a worktree, which triggers file tree
/// building. Use [selectFile] to load a file's content for viewing.
class FileManagerState extends ChangeNotifier {
  final ProjectState _project;
  final FileSystemService _fileSystemService;

  WorktreeState? _selectedWorktree;
  FileTreeNode? _rootNode;
  String? _selectedFilePath;
  FileContent? _fileContent;
  bool _isLoadingTree = false;
  bool _isLoadingFile = false;
  String? _error;

  /// Creates a [FileManagerState] with the given project and file service.
  ///
  /// The [project] provides access to worktrees. The [fileSystemService]
  /// handles file tree building and file reading operations.
  FileManagerState(this._project, this._fileSystemService);

  /// The project this file manager operates on.
  ProjectState get project => _project;

  /// The currently selected worktree, if any.
  WorktreeState? get selectedWorktree => _selectedWorktree;

  /// The root node of the file tree for the selected worktree.
  ///
  /// Null if no worktree is selected or if tree building is in progress.
  FileTreeNode? get rootNode => _rootNode;

  /// The path of the currently selected file, if any.
  String? get selectedFilePath => _selectedFilePath;

  /// The content of the currently selected file, if any.
  ///
  /// Null if no file is selected or if file loading is in progress.
  FileContent? get fileContent => _fileContent;

  /// Whether the file tree is currently being built.
  bool get isLoadingTree => _isLoadingTree;

  /// Whether a file is currently being loaded.
  bool get isLoadingFile => _isLoadingFile;

  /// The last error message, if any.
  ///
  /// Cleared when a new operation succeeds.
  String? get error => _error;

  /// Selects a worktree and builds its file tree.
  ///
  /// Clears the previous tree and file selection, then triggers an async
  /// file tree build. Listeners are notified immediately when selection
  /// changes, and again when the tree build completes.
  void selectWorktree(WorktreeState worktree) {
    if (_selectedWorktree == worktree) {
      return;
    }

    developer.log(
      'Selecting worktree: ${worktree.data.worktreeRoot}',
      name: 'FileManagerState',
    );

    _selectedWorktree = worktree;
    _rootNode = null;
    _selectedFilePath = null;
    _fileContent = null;
    _error = null;
    notifyListeners();

    // Trigger async tree build
    refreshFileTree();
  }

  /// Rebuilds the file tree for the currently selected worktree.
  ///
  /// Sets [isLoadingTree] to true during the operation. If an error occurs,
  /// [error] is set with the error message and [rootNode] remains null.
  ///
  /// Does nothing if no worktree is selected.
  Future<void> refreshFileTree() async {
    if (_selectedWorktree == null) {
      return;
    }

    final rootPath = _selectedWorktree!.data.worktreeRoot;
    developer.log(
      'Building file tree for: $rootPath',
      name: 'FileManagerState',
    );

    _isLoadingTree = true;
    _error = null;
    notifyListeners();

    try {
      final tree = await _fileSystemService.buildFileTree(rootPath);
      _rootNode = tree;
      _error = null;
      developer.log(
        'File tree built: ${tree.children.length} top-level items',
        name: 'FileManagerState',
      );
    } on FileSystemException catch (e) {
      developer.log(
        'Failed to build file tree: ${e.message}',
        name: 'FileManagerState',
        error: e,
      );
      _rootNode = null;
      _error = e.message;
    } catch (e) {
      developer.log(
        'Unexpected error building file tree: $e',
        name: 'FileManagerState',
        error: e,
      );
      _rootNode = null;
      _error = 'Failed to build file tree: $e';
    } finally {
      _isLoadingTree = false;
      notifyListeners();
    }
  }

  /// Selects a file and loads its content.
  ///
  /// Sets [selectedFilePath] immediately and triggers an async content load.
  /// Listeners are notified when the selection changes and again when
  /// loading completes.
  void selectFile(String path) {
    if (_selectedFilePath == path) {
      return;
    }

    developer.log(
      'Selecting file: $path',
      name: 'FileManagerState',
    );

    _selectedFilePath = path;
    _fileContent = null;
    notifyListeners();

    // Trigger async file load
    loadFileContent(path);
  }

  /// Loads the content of a file.
  ///
  /// Sets [isLoadingFile] to true during the operation. The result is stored
  /// in [fileContent], which may be an error content if the file couldn't
  /// be read.
  ///
  /// This method is typically called automatically by [selectFile], but can
  /// be called directly to reload the current file.
  Future<void> loadFileContent(String path) async {
    developer.log(
      'Loading file content: $path',
      name: 'FileManagerState',
    );

    _isLoadingFile = true;
    notifyListeners();

    try {
      final content = await _fileSystemService.readFile(path);
      // Only update if this is still the selected file
      if (_selectedFilePath == path) {
        _fileContent = content;
        if (content.isError) {
          developer.log(
            'File load error: ${content.error}',
            name: 'FileManagerState',
          );
        } else {
          developer.log(
            'File loaded: ${content.type.name}',
            name: 'FileManagerState',
          );
        }
      }
    } catch (e) {
      developer.log(
        'Unexpected error loading file: $e',
        name: 'FileManagerState',
        error: e,
      );
      if (_selectedFilePath == path) {
        _fileContent = FileContent.error(
          path: path,
          message: 'Failed to load file: $e',
        );
      }
    } finally {
      _isLoadingFile = false;
      notifyListeners();
    }
  }

  /// Toggles the expanded state of a directory node.
  ///
  /// Finds the node at [path] in the current tree and toggles its
  /// [isExpanded] property. The entire tree is rebuilt immutably to
  /// reflect the change.
  ///
  /// Does nothing if [rootNode] is null or if the path isn't found.
  void toggleExpanded(String path) {
    if (_rootNode == null) {
      return;
    }

    developer.log(
      'Toggling expanded for: $path',
      name: 'FileManagerState',
    );

    _rootNode = _toggleNodeExpanded(_rootNode!, path);
    notifyListeners();
  }

  /// Recursively finds and toggles the expanded state of a node.
  ///
  /// Returns a new tree with the specified node toggled.
  FileTreeNode _toggleNodeExpanded(FileTreeNode node, String targetPath) {
    if (node.path == targetPath) {
      // Found the target node - toggle its expanded state
      return node.copyWith(isExpanded: !node.isExpanded);
    }

    if (!node.isDirectory || node.children.isEmpty) {
      // Not a directory or no children - return unchanged
      return node;
    }

    // Check if target might be in this node's children
    if (!targetPath.startsWith('${node.path}/')) {
      return node;
    }

    // Recursively process children
    final newChildren = node.children.map((child) {
      return _toggleNodeExpanded(child, targetPath);
    }).toList();

    return node.copyWith(children: newChildren);
  }

  /// Clears the current file selection.
  void clearFileSelection() {
    _selectedFilePath = null;
    _fileContent = null;
    notifyListeners();
  }

  /// Clears the current worktree selection and all associated state.
  void clearSelection() {
    _selectedWorktree = null;
    _rootNode = null;
    _selectedFilePath = null;
    _fileContent = null;
    _error = null;
    _isLoadingTree = false;
    _isLoadingFile = false;
    notifyListeners();
  }
}
