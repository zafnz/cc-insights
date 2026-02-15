import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../models/file_content.dart';
import '../models/file_tree_node.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/file_system_service.dart';
import 'selection_state.dart';

/// State management for the File Manager feature.
///
/// Manages file tree building and file content loading for the currently
/// selected worktree. The worktree selection is synchronized with
/// [SelectionState] - when the user selects a worktree in either the main
/// screen or file manager, both update together.
///
/// Use [selectFile] to load a file's content for viewing.
///
/// The expanded state of directories is tracked separately from the tree
/// structure in [_expandedPaths] to avoid rebuilding the entire tree on
/// each expand/collapse operation.
class FileManagerState extends ChangeNotifier {
  final ProjectState _project;
  final FileSystemService _fileSystemService;
  final SelectionState _selectionState;

  WorktreeState? _lastKnownWorktree;
  FileTreeNode? _rootNode;
  String? _selectedFilePath;
  FileContent? _fileContent;
  bool _isLoadingTree = false;
  bool _isLoadingFile = false;
  String? _error;

  /// Set of paths that are currently expanded in the UI.
  /// Tracked separately from tree nodes for performance.
  final Set<String> _expandedPaths = {};

  /// Creates a [FileManagerState] with the given project, file service, and
  /// selection state.
  ///
  /// The [project] provides access to worktrees. The [fileSystemService]
  /// handles file tree building and file reading operations. The
  /// [selectionState] is used to synchronize worktree selection with the
  /// main screen.
  FileManagerState(
    this._project,
    this._fileSystemService,
    this._selectionState,
  ) {
    // Listen to selection state changes to sync worktree selection
    _selectionState.addListener(_onSelectionChanged);
    // Initialize with current selection if any
    _syncWithSelectionState();
  }

  /// Called when SelectionState changes.
  void _onSelectionChanged() {
    _syncWithSelectionState();
  }

  /// Syncs our state with the current SelectionState worktree.
  void _syncWithSelectionState() {
    final newWorktree = _selectionState.selectedWorktree;
    if (newWorktree != _lastKnownWorktree) {
      _handleWorktreeChanged(newWorktree);
    }
  }

  /// Handles a worktree change from SelectionState.
  void _handleWorktreeChanged(WorktreeState? worktree) {
    if (worktree == null) {
      // Worktree was deselected
      _lastKnownWorktree = null;
      _rootNode = null;
      _selectedFilePath = null;
      _fileContent = null;
      _error = null;
      _expandedPaths.clear();
      notifyListeners();
      return;
    }

    developer.log(
      'Syncing to worktree: ${worktree.data.worktreeRoot}',
      name: 'FileManagerState',
    );

    _lastKnownWorktree = worktree;
    _rootNode = null;
    _selectedFilePath = null;
    _fileContent = null;
    _error = null;
    _expandedPaths.clear();
    notifyListeners();

    // Trigger async tree build
    refreshFileTree();
  }

  @override
  void dispose() {
    _selectionState.removeListener(_onSelectionChanged);
    super.dispose();
  }

  /// The project this file manager operates on.
  ProjectState get project => _project;

  /// The currently selected worktree, if any.
  ///
  /// This is synchronized with [SelectionState.selectedWorktree].
  WorktreeState? get selectedWorktree => _selectionState.selectedWorktree;

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

  /// Set of directory paths that are currently expanded.
  ///
  /// Use [isExpanded] to check if a specific path is expanded.
  /// Use [toggleExpanded] to change the expanded state.
  Set<String> get expandedPaths => Set.unmodifiable(_expandedPaths);

  /// Returns whether the directory at [path] is expanded.
  bool isExpanded(String path) => _expandedPaths.contains(path);

  /// Selects a worktree and builds its file tree.
  ///
  /// This delegates to [SelectionState.selectWorktree], which will trigger
  /// [_onSelectionChanged] to update our internal state and build the file
  /// tree. This ensures the main screen and file manager stay in sync.
  void selectWorktree(WorktreeState worktree) {
    if (_selectionState.selectedWorktree == worktree) {
      return;
    }

    developer.log(
      'Selecting worktree via SelectionState: ${worktree.data.worktreeRoot}',
      name: 'FileManagerState',
    );

    // Delegate to SelectionState - our listener will handle the rest
    _selectionState.selectWorktree(worktree);
  }

  /// Rebuilds the file tree for the currently selected worktree.
  ///
  /// Sets [isLoadingTree] to true during the operation. If an error occurs,
  /// [error] is set with the error message and [rootNode] remains null.
  ///
  /// Does nothing if no worktree is selected.
  Future<void> refreshFileTree() async {
    final worktree = selectedWorktree;
    if (worktree == null) {
      return;
    }

    final rootPath = worktree.data.worktreeRoot;
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
  /// Updates the [expandedPaths] set without rebuilding the tree structure.
  /// This is much more performant than rebuilding the entire tree.
  ///
  /// Does nothing if [rootNode] is null.
  void toggleExpanded(String path) {
    if (_rootNode == null) {
      return;
    }

    developer.log(
      'Toggling expanded for: $path',
      name: 'FileManagerState',
    );

    if (_expandedPaths.contains(path)) {
      _expandedPaths.remove(path);
    } else {
      _expandedPaths.add(path);
    }
    notifyListeners();
  }

  /// Clears the current file selection.
  void clearFileSelection() {
    _selectedFilePath = null;
    _fileContent = null;
    notifyListeners();
  }

  /// Clears the current worktree selection and all associated state.
  ///
  /// Note: This clears the file manager's internal state but does not
  /// change the SelectionState's worktree selection. Use this for clearing
  /// file-related state only.
  void clearSelection() {
    _lastKnownWorktree = null;
    _rootNode = null;
    _selectedFilePath = null;
    _fileContent = null;
    _error = null;
    _isLoadingTree = false;
    _isLoadingFile = false;
    _expandedPaths.clear();
    notifyListeners();
  }
}
