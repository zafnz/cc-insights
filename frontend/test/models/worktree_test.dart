import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorktreeData', () {
    group('constructor', () {
      test('creates with required fields', () {
        // Arrange & Act
        const worktree = WorktreeData(
          worktreeRoot: '/path/to/worktree',
          isPrimary: true,
          branch: 'main',
        );

        // Assert
        check(worktree.worktreeRoot).equals('/path/to/worktree');
        check(worktree.isPrimary).isTrue();
        check(worktree.branch).equals('main');
        check(worktree.uncommittedFiles).equals(0);
        check(worktree.stagedFiles).equals(0);
        check(worktree.commitsAhead).equals(0);
        check(worktree.commitsBehind).equals(0);
        check(worktree.hasMergeConflict).isFalse();
        check(worktree.isRemoteBase).isFalse();
        check(worktree.baseRef).isNull();
      });

      test('creates linked worktree', () {
        // Arrange & Act
        const worktree = WorktreeData(
          worktreeRoot: '/path/to/linked',
          isPrimary: false,
          branch: 'feature-branch',
        );

        // Assert
        check(worktree.isPrimary).isFalse();
        check(worktree.branch).equals('feature-branch');
      });

      test('creates with git status fields', () {
        // Arrange & Act
        const worktree = WorktreeData(
          worktreeRoot: '/path/to/worktree',
          isPrimary: true,
          branch: 'main',
          uncommittedFiles: 5,
          stagedFiles: 2,
          commitsAhead: 3,
          commitsBehind: 1,
          hasMergeConflict: true,
        );

        // Assert
        check(worktree.uncommittedFiles).equals(5);
        check(worktree.stagedFiles).equals(2);
        check(worktree.commitsAhead).equals(3);
        check(worktree.commitsBehind).equals(1);
        check(worktree.hasMergeConflict).isTrue();
      });
    });

    group('copyWith()', () {
      test('preserves immutable fields', () {
        // Arrange
        const original = WorktreeData(
          worktreeRoot: '/path/to/worktree',
          isPrimary: true,
          branch: 'main',
        );

        // Act
        final modified = original.copyWith(branch: 'develop');

        // Assert
        check(modified.worktreeRoot).equals('/path/to/worktree');
        check(modified.isPrimary).isTrue();
        check(modified.branch).equals('develop');
      });

      test('preserves unchanged mutable fields', () {
        // Arrange
        const original = WorktreeData(
          worktreeRoot: '/path/to/worktree',
          isPrimary: true,
          branch: 'main',
          uncommittedFiles: 5,
          stagedFiles: 2,
        );

        // Act
        final modified = original.copyWith(branch: 'develop');

        // Assert
        check(modified.uncommittedFiles).equals(5);
        check(modified.stagedFiles).equals(2);
      });

      test('updates multiple fields', () {
        // Arrange
        const original = WorktreeData(
          worktreeRoot: '/path/to/worktree',
          isPrimary: true,
          branch: 'main',
        );

        // Act
        final modified = original.copyWith(
          branch: 'feature',
          uncommittedFiles: 3,
          hasMergeConflict: true,
        );

        // Assert
        check(modified.branch).equals('feature');
        check(modified.uncommittedFiles).equals(3);
        check(modified.hasMergeConflict).isTrue();
      });

      test('updates isRemoteBase and baseRef', () {
        const original = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
        );

        final modified = original.copyWith(
          isRemoteBase: true,
          baseRef: 'origin/main',
        );

        check(modified.isRemoteBase).isTrue();
        check(modified.baseRef).equals('origin/main');
      });

      test('preserves isRemoteBase and baseRef when not specified', () {
        const original = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'feature',
          isRemoteBase: true,
          baseRef: 'origin/main',
        );

        final modified = original.copyWith(branch: 'develop');

        check(modified.isRemoteBase).isTrue();
        check(modified.baseRef).equals('origin/main');
      });

      test('clears baseRef with clearBaseRef', () {
        const original = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'feature',
          baseRef: 'origin/main',
        );

        final modified = original.copyWith(clearBaseRef: true);

        check(modified.baseRef).isNull();
      });
    });

    group('equality', () {
      test('equals returns true for identical values', () {
        // Arrange
        const worktree1 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
        );
        const worktree2 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
        );

        // Act & Assert
        check(worktree1 == worktree2).isTrue();
        check(worktree1.hashCode).equals(worktree2.hashCode);
      });

      test('equals returns false for different branches', () {
        // Arrange
        const worktree1 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
        );
        const worktree2 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'develop',
        );

        // Act & Assert
        check(worktree1 == worktree2).isFalse();
      });

      test('equals returns false for different isRemoteBase', () {
        const worktree1 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
          isRemoteBase: false,
        );
        const worktree2 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
          isRemoteBase: true,
        );

        check(worktree1 == worktree2).isFalse();
      });

      test('equals returns false for different baseRef', () {
        const worktree1 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
          baseRef: 'main',
        );
        const worktree2 = WorktreeData(
          worktreeRoot: '/path',
          isPrimary: true,
          branch: 'main',
          baseRef: 'origin/main',
        );

        check(worktree1 == worktree2).isFalse();
      });
    });
  });

  group('WorktreeState', () {
    WorktreeData createTestData({
      String path = '/path/to/worktree',
      bool isPrimary = true,
      String branch = 'main',
    }) {
      return WorktreeData(
        worktreeRoot: path,
        isPrimary: isPrimary,
        branch: branch,
      );
    }

    group('constructor', () {
      test('creates with empty chats by default', () {
        // Arrange & Act
        final state = WorktreeState(createTestData());

        // Assert
        check(state.chats).isEmpty();
        check(state.selectedChat).isNull();
      });

      test('creates with provided chats', () {
        // Arrange
        final chat1 = ChatState.create(name: 'Chat 1', worktreeRoot: '/path');
        final chat2 = ChatState.create(name: 'Chat 2', worktreeRoot: '/path');

        // Act
        final state = WorktreeState(createTestData(), chats: [chat1, chat2]);

        // Assert
        check(state.chats.length).equals(2);
      });
    });

    group('updateBranch()', () {
      test('updates branch and notifies listeners', () {
        // Arrange
        final state = WorktreeState(createTestData(branch: 'main'));
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.updateBranch('develop');

        // Assert
        check(state.data.branch).equals('develop');
        check(notified).isTrue();
      });
    });

    group('updateData()', () {
      test('replaces entire data and notifies', () {
        // Arrange
        final state = WorktreeState(createTestData(branch: 'main'));
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.updateData(createTestData(branch: 'feature'));

        // Assert
        check(state.data.branch).equals('feature');
        check(notified).isTrue();
      });
    });

    group('updateGitStatus()', () {
      test('updates all status fields', () {
        // Arrange
        final state = WorktreeState(createTestData());
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.updateGitStatus(
          uncommittedFiles: 5,
          stagedFiles: 2,
          commitsAhead: 3,
          commitsBehind: 1,
          hasMergeConflict: true,
        );

        // Assert
        check(state.data.uncommittedFiles).equals(5);
        check(state.data.stagedFiles).equals(2);
        check(state.data.commitsAhead).equals(3);
        check(state.data.commitsBehind).equals(1);
        check(state.data.hasMergeConflict).isTrue();
        check(notified).isTrue();
      });

      test('updates partial status fields', () {
        // Arrange
        final state = WorktreeState(
          createTestData().copyWith(uncommittedFiles: 10, stagedFiles: 5),
        );

        // Act
        state.updateGitStatus(uncommittedFiles: 3);

        // Assert
        check(state.data.uncommittedFiles).equals(3);
        check(state.data.stagedFiles).equals(5);
      });
    });

    group('addChat()', () {
      test('adds chat to list and notifies', () {
        // Arrange
        final state = WorktreeState(createTestData());
        final chat = ChatState.create(name: 'New Chat', worktreeRoot: '/path');
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.addChat(chat);

        // Assert
        check(state.chats.length).equals(1);
        check(state.chats.first.data.name).equals('New Chat');
        check(notified).isTrue();
      });

      test('selects chat when select is true', () {
        // Arrange
        final state = WorktreeState(createTestData());
        final chat = ChatState.create(name: 'New Chat', worktreeRoot: '/path');

        // Act
        state.addChat(chat, select: true);

        // Assert
        check(state.selectedChat).equals(chat);
      });

      test('does not select chat when select is false', () {
        // Arrange
        final state = WorktreeState(createTestData());
        final chat = ChatState.create(name: 'New Chat', worktreeRoot: '/path');

        // Act
        state.addChat(chat, select: false);

        // Assert
        check(state.selectedChat).isNull();
      });
    });

    group('removeChat()', () {
      test('removes chat from list and notifies', () {
        // Arrange
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat]);
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.removeChat(chat);

        // Assert
        check(state.chats).isEmpty();
        check(notified).isTrue();
      });

      test('clears selection when selected chat is removed', () {
        // Arrange
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat]);
        state.selectChat(chat);

        // Act
        state.removeChat(chat);

        // Assert
        check(state.selectedChat).isNull();
      });

      test('preserves selection when different chat is removed', () {
        // Arrange
        final chat1 = ChatState.create(name: 'Chat 1', worktreeRoot: '/path');
        final chat2 = ChatState.create(name: 'Chat 2', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat1, chat2]);
        state.selectChat(chat1);

        // Act
        state.removeChat(chat2);

        // Assert
        check(state.selectedChat).equals(chat1);
      });
    });

    group('selectChat()', () {
      test('sets selected chat and notifies', () {
        // Arrange
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat]);
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.selectChat(chat);

        // Assert
        check(state.selectedChat).equals(chat);
        check(notified).isTrue();
      });

      test('clears selection with null', () {
        // Arrange
        final chat = ChatState.create(name: 'Chat', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat]);
        state.selectChat(chat);

        // Act
        state.selectChat(null);

        // Assert
        check(state.selectedChat).isNull();
      });
    });

    group('baseOverride', () {
      test('defaults to null', () {
        // Arrange & Act
        final state = WorktreeState(createTestData());

        // Assert
        check(state.baseOverride).isNull();
      });

      test('initializes from constructor', () {
        // Arrange & Act
        final state = WorktreeState(
          createTestData(),
          baseOverride: 'develop',
        );

        // Assert
        check(state.baseOverride).equals('develop');
      });

      test('setBaseOverride updates value and notifies listeners', () {
        // Arrange
        final state = WorktreeState(createTestData());
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.setBaseOverride('develop');

        // Assert
        check(state.baseOverride).equals('develop');
        check(notified).isTrue();
      });

      test('setBaseOverride with same value does not notify listeners', () {
        // Arrange
        final state = WorktreeState(
          createTestData(),
          baseOverride: 'develop',
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.setBaseOverride('develop');

        // Assert
        check(state.baseOverride).equals('develop');
        check(notified).isFalse();
      });

      test('setBaseOverride to null clears override and notifies', () {
        // Arrange
        final state = WorktreeState(
          createTestData(),
          baseOverride: 'develop',
        );
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.setBaseOverride(null);

        // Assert
        check(state.baseOverride).isNull();
        check(notified).isTrue();
      });

      test('setBaseOverride null to null does not notify', () {
        // Arrange
        final state = WorktreeState(createTestData());
        var notified = false;
        state.addListener(() => notified = true);

        // Act
        state.setBaseOverride(null);

        // Assert
        check(state.baseOverride).isNull();
        check(notified).isFalse();
      });
    });

    group('dispose()', () {
      test('disposes all chats', () {
        // Arrange
        final chat1 = ChatState.create(name: 'Chat 1', worktreeRoot: '/path');
        final chat2 = ChatState.create(name: 'Chat 2', worktreeRoot: '/path');
        final state = WorktreeState(createTestData(), chats: [chat1, chat2]);

        // Act
        state.dispose();

        // Assert - chats list should be cleared
        check(state.chats).isEmpty();
        check(state.selectedChat).isNull();
      });
    });
  });
}
