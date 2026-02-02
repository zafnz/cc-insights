import 'package:cc_insights_v2/services/persistence_models.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';

/// Fake implementation of [PersistenceService] for testing.
class FakePersistenceService extends PersistenceService {
  /// Tracks calls to [removeWorktreeFromIndex].
  final List<({String projectRoot, String worktreePath, String projectId})>
      removeWorktreeFromIndexCalls = [];

  /// The chat IDs to return from [removeWorktreeFromIndex].
  List<String>? lastRemovedChatIds;

  /// If set, [removeWorktreeFromIndex] will throw this exception.
  Exception? removeWorktreeFromIndexError;

  @override
  Future<List<String>> removeWorktreeFromIndex({
    required String projectRoot,
    required String worktreePath,
    required String projectId,
  }) async {
    removeWorktreeFromIndexCalls.add((
      projectRoot: projectRoot,
      worktreePath: worktreePath,
      projectId: projectId,
    ));
    if (removeWorktreeFromIndexError != null) {
      throw removeWorktreeFromIndexError!;
    }
    return lastRemovedChatIds ?? [];
  }

  /// In-memory projects index for testing.
  ProjectsIndex? _projectsIndex;

  @override
  Future<ProjectsIndex> loadProjectsIndex() async {
    return _projectsIndex ?? const ProjectsIndex.empty();
  }

  @override
  Future<void> saveProjectsIndex(ProjectsIndex index) async {
    _projectsIndex = index;
  }

  /// Resets all state.
  void reset() {
    removeWorktreeFromIndexCalls.clear();
    lastRemovedChatIds = null;
    removeWorktreeFromIndexError = null;
    _projectsIndex = null;
  }
}
