import 'package:flutter/foundation.dart';

import 'worktree.dart';

/// Immutable data representing a project (git repository).
///
/// A project is a git repository containing one primary worktree and zero or
/// more linked worktrees. The [repoRoot] is the path to the `.git` directory
/// and is immutable once created. Only the [name] can be changed.
///
/// Use [copyWith] to create modified copies with an updated name.
@immutable
class ProjectData {
  /// The user-friendly name for this project.
  ///
  /// This can be changed by the user and defaults to the repository
  /// directory name when first created.
  final String name;

  /// The filesystem path to the `.git` directory. Immutable once created.
  ///
  /// For a standard git repository, this is typically the repository root
  /// with `/.git` appended. For bare repositories, this is the repository
  /// root itself.
  final String repoRoot;

  /// Creates a new [ProjectData] instance.
  const ProjectData({required this.name, required this.repoRoot});

  /// Creates a copy with the given name replaced.
  ///
  /// [repoRoot] is immutable and cannot be changed.
  ProjectData copyWith({String? name}) {
    return ProjectData(name: name ?? this.name, repoRoot: repoRoot);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectData &&
        other.name == name &&
        other.repoRoot == repoRoot;
  }

  @override
  int get hashCode => Object.hash(name, repoRoot);

  @override
  String toString() => 'ProjectData(name: $name, repoRoot: $repoRoot)';
}

/// Mutable state holder for a project, extending [ChangeNotifier].
///
/// Holds a [ProjectData] instance and manages the worktrees within this
/// project. Every project has exactly one primary worktree (at the repository
/// root) and zero or more linked worktrees.
///
/// The project remembers which worktree was last selected, allowing users to
/// switch projects and return to their previous context.
///
/// Call [notifyListeners] after mutations to update the UI.
class ProjectState extends ChangeNotifier {
  ProjectData _data;
  final WorktreeState _primaryWorktree;
  final List<WorktreeState> _linkedWorktrees;
  WorktreeState? _selectedWorktree;

  /// Creates a [ProjectState] with the given initial data and primary
  /// worktree.
  ///
  /// [linkedWorktrees] defaults to an empty list if not provided.
  /// [selectedWorktree] defaults to the primary worktree if not provided.
  ProjectState(
    this._data,
    this._primaryWorktree, {
    List<WorktreeState>? linkedWorktrees,
    WorktreeState? selectedWorktree,
  }) : _linkedWorktrees = linkedWorktrees ?? [] {
    _selectedWorktree = selectedWorktree ?? _primaryWorktree;
  }

  /// The immutable data for this project.
  ProjectData get data => _data;

  /// The primary worktree (at the repository root where `.git` lives).
  ///
  /// Every project has exactly one primary worktree.
  WorktreeState get primaryWorktree => _primaryWorktree;

  /// The linked worktrees created via `git worktree add`.
  ///
  /// Returns an unmodifiable view of the linked worktrees list.
  List<WorktreeState> get linkedWorktrees =>
      List.unmodifiable(_linkedWorktrees);

  /// All worktrees in this project, with the primary worktree first.
  ///
  /// Returns a new list containing the primary worktree followed by all
  /// linked worktrees.
  List<WorktreeState> get allWorktrees => [
    _primaryWorktree,
    ..._linkedWorktrees,
  ];

  /// The currently selected worktree in this project, if any.
  ///
  /// When switching projects, the selection is preserved so users can
  /// return to their previous context.
  WorktreeState? get selectedWorktree => _selectedWorktree;

  /// Renames this project.
  ///
  /// Updates the project name and notifies listeners.
  void rename(String newName) {
    _data = _data.copyWith(name: newName);
    notifyListeners();
  }

  /// Sets the selected worktree.
  ///
  /// The [worktree] should be either the primary worktree, one of the linked
  /// worktrees, or null to deselect.
  void selectWorktree(WorktreeState? worktree) {
    _selectedWorktree = worktree;
    notifyListeners();
  }

  /// Adds a linked worktree to this project.
  ///
  /// The worktree must be a linked worktree (not primary). Optionally selects
  /// the newly added worktree if [select] is true.
  void addLinkedWorktree(WorktreeState worktree, {bool select = false}) {
    assert(
      !worktree.data.isPrimary,
      'Cannot add a primary worktree as a linked worktree',
    );
    _linkedWorktrees.add(worktree);
    if (select) {
      _selectedWorktree = worktree;
    }
    notifyListeners();
  }

  /// Removes a linked worktree from this project.
  ///
  /// If the removed worktree was selected, the selection falls back to the
  /// primary worktree. The primary worktree cannot be removed.
  void removeLinkedWorktree(WorktreeState worktree) {
    assert(!worktree.data.isPrimary, 'Cannot remove the primary worktree');
    _linkedWorktrees.remove(worktree);
    if (_selectedWorktree == worktree) {
      _selectedWorktree = _primaryWorktree;
    }
    worktree.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    // Dispose all worktree states.
    _primaryWorktree.dispose();
    for (final worktree in _linkedWorktrees) {
      worktree.dispose();
    }
    _linkedWorktrees.clear();
    _selectedWorktree = null;
    super.dispose();
  }
}
