import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectData', () {
    group('constructor', () {
      test('creates with required fields', () {
        // Arrange & Act
        const project = ProjectData(
          name: 'My Project',
          repoRoot: '/path/to/repo/.git',
        );

        // Assert
        check(project.name).equals('My Project');
        check(project.repoRoot).equals('/path/to/repo/.git');
      });
    });

    group('copyWith()', () {
      test('updates name while preserving repoRoot', () {
        // Arrange
        const original = ProjectData(
          name: 'Original Name',
          repoRoot: '/path/to/repo/.git',
        );

        // Act
        final modified = original.copyWith(name: 'New Name');

        // Assert
        check(modified.name).equals('New Name');
        check(modified.repoRoot).equals('/path/to/repo/.git');
      });

      test('preserves all fields when no arguments', () {
        // Arrange
        const original = ProjectData(
          name: 'My Project',
          repoRoot: '/path/to/repo/.git',
        );

        // Act
        final modified = original.copyWith();

        // Assert
        check(modified.name).equals('My Project');
        check(modified.repoRoot).equals('/path/to/repo/.git');
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        const project1 = ProjectData(name: 'Project', repoRoot: '/path');
        const project2 = ProjectData(name: 'Project', repoRoot: '/path');

        // Act & Assert
        check(project1 == project2).isTrue();
        check(project1.hashCode).equals(project2.hashCode);
      });

      test('equals returns false for different names', () {
        // Arrange
        const project1 = ProjectData(name: 'Project A', repoRoot: '/path');
        const project2 = ProjectData(name: 'Project B', repoRoot: '/path');

        // Act & Assert
        check(project1 == project2).isFalse();
      });

      test('equals returns false for different repoRoots', () {
        // Arrange
        const project1 = ProjectData(name: 'Project', repoRoot: '/path/a');
        const project2 = ProjectData(name: 'Project', repoRoot: '/path/b');

        // Act & Assert
        check(project1 == project2).isFalse();
      });
    });

    group('toString()', () {
      test('includes key information', () {
        // Arrange
        const project = ProjectData(
          name: 'My Project',
          repoRoot: '/path/to/repo',
        );

        // Act
        final str = project.toString();

        // Assert
        check(str).contains('My Project');
        check(str).contains('/path/to/repo');
      });
    });
  });

  group('ProjectState', () {
    WorktreeData createWorktreeData({
      required String path,
      required bool isPrimary,
      String branch = 'main',
    }) {
      return WorktreeData(
        worktreeRoot: path,
        isPrimary: isPrimary,
        branch: branch,
      );
    }

    WorktreeState createWorktreeState({
      required String path,
      required bool isPrimary,
      String branch = 'main',
    }) {
      return WorktreeState(
        createWorktreeData(path: path, isPrimary: isPrimary, branch: branch),
      );
    }

    group('constructor', () {
      test('creates with primary worktree selected by default', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );

        // Act
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Assert
        check(state.data.name).equals('Project');
        check(state.primaryWorktree).equals(primaryWorktree);
        check(state.linkedWorktrees).isEmpty();
        check(state.selectedWorktree).equals(primaryWorktree);
      });

      test('creates with linked worktrees', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
          branch: 'feature',
        );

        // Act
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );

        // Assert
        check(state.linkedWorktrees.length).equals(1);
        check(state.linkedWorktrees.first).equals(linkedWorktree);
      });

      test('accepts custom selectedWorktree', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );

        // Act
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          selectedWorktree: linkedWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree);
      });
    });

    group('allWorktrees', () {
      test('returns primary first when no linked worktrees', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Act
        final allWorktrees = state.allWorktrees;

        // Assert
        check(allWorktrees.length).equals(1);
        check(allWorktrees.first).equals(primaryWorktree);
        check(allWorktrees.first.data.isPrimary).isTrue();
      });

      test('returns primary first followed by linked worktrees', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
          branch: 'main',
        );
        final linkedWorktree1 = createWorktreeState(
          path: '/repo-wt1',
          isPrimary: false,
          branch: 'feature-1',
        );
        final linkedWorktree2 = createWorktreeState(
          path: '/repo-wt2',
          isPrimary: false,
          branch: 'feature-2',
        );

        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree1, linkedWorktree2],
          autoValidate: false,
          watchFilesystem: false,
        );

        // Act
        final allWorktrees = state.allWorktrees;

        // Assert
        check(allWorktrees.length).equals(3);
        check(allWorktrees[0].data.isPrimary).isTrue();
        check(allWorktrees[0].data.branch).equals('main');
        check(allWorktrees[1].data.branch).equals('feature-1');
        check(allWorktrees[2].data.branch).equals('feature-2');
      });
    });

    group('rename()', () {
      test('updates name and notifies listeners', () {
        // Arrange
        const projectData = ProjectData(name: 'Original', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.rename('New Name');

        // Assert
        check(state.data.name).equals('New Name');
        check(notified).isTrue();
      });
    });

    group('selectWorktree()', () {
      test('changes selection and notifies listeners', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.selectWorktree(linkedWorktree);

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree);
        check(notified).isTrue();
      });

      test('allows selecting null', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Act
        state.selectWorktree(null);

        // Assert
        check(state.selectedWorktree).isNull();
      });
    });

    group('addLinkedWorktree()', () {
      test('adds worktree to list and notifies', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.addLinkedWorktree(linkedWorktree);

        // Assert
        check(state.linkedWorktrees.length).equals(1);
        check(state.linkedWorktrees.first).equals(linkedWorktree);
        check(notified).isTrue();
      });

      test('selects worktree when select is true', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );

        // Act
        state.addLinkedWorktree(linkedWorktree, select: true);

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree);
      });

      test('does not change selection when select is false', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );

        // Act
        state.addLinkedWorktree(linkedWorktree, select: false);

        // Assert
        check(state.selectedWorktree).equals(primaryWorktree);
      });
    });

    group('removeLinkedWorktree()', () {
      test('removes worktree from list and notifies', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          autoValidate: false,
          watchFilesystem: false,
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.removeLinkedWorktree(linkedWorktree);

        // Assert
        check(state.linkedWorktrees).isEmpty();
        check(notified).isTrue();
      });

      test('falls back to primary when selected worktree is removed', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
          selectedWorktree: linkedWorktree,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Act
        state.removeLinkedWorktree(linkedWorktree);

        // Assert
        check(state.selectedWorktree).equals(primaryWorktree);
      });

      test('preserves selection when different worktree is removed', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree1 = createWorktreeState(
          path: '/repo-linked-1',
          isPrimary: false,
        );
        final linkedWorktree2 = createWorktreeState(
          path: '/repo-linked-2',
          isPrimary: false,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree1, linkedWorktree2],
          selectedWorktree: linkedWorktree1,
          autoValidate: false,
          watchFilesystem: false,
        );

        // Act
        state.removeLinkedWorktree(linkedWorktree2);

        // Assert
        check(state.selectedWorktree).equals(linkedWorktree1);
      });
    });

    group('dispose()', () {
      test('disposes all worktrees', () {
        // Arrange
        const projectData = ProjectData(name: 'Project', repoRoot: '/repo');
        final primaryWorktree = createWorktreeState(
          path: '/repo',
          isPrimary: true,
        );
        final linkedWorktree = createWorktreeState(
          path: '/repo-linked',
          isPrimary: false,
        );
        final state = ProjectState(
          projectData,
          primaryWorktree,
          linkedWorktrees: [linkedWorktree],
        );

        // Act
        state.dispose();

        // Assert - linkedWorktrees list should be cleared
        check(state.linkedWorktrees).isEmpty();
        check(state.selectedWorktree).isNull();
      });
    });
  });
}
