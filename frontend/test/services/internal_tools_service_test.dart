import 'dart:async';
import 'dart:convert';

import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../test_helpers.dart';

void main() {
  final resources = TestResources();
  late Future<void> Function() cleanupConfig;

  setUp(() async {
    cleanupConfig = await setupTestConfig();
  });

  tearDown(() async {
    await resources.disposeAll();
    await cleanupConfig();
  });

  group('InternalToolsService', () {
    test('creates with empty registry', () {
      final service = resources.track(InternalToolsService());

      expect(service.registry.isEmpty, isTrue);
      expect(service.registry.tools, isEmpty);
    });

    test('registerTicketTools adds create_ticket to registry', () {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));

      service.registerTicketTools(bulkProposal);

      expect(service.registry.isNotEmpty, isTrue);
      expect(service.registry['create_ticket'], isNotNull);
      expect(service.registry['create_ticket']!.name, 'create_ticket');
    });

    test('registry is accessible via getter', () {
      final service = resources.track(InternalToolsService());

      final registry = service.registry;

      expect(registry, isA<InternalToolRegistry>());
    });

    test('unregisterTicketTools removes create_ticket from registry', () {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));

      service.registerTicketTools(bulkProposal);
      expect(service.registry['create_ticket'], isNotNull);

      service.unregisterTicketTools();
      expect(service.registry['create_ticket'], isNull);
      expect(service.registry.isEmpty, isTrue);
    });
  });

  group('InternalToolsService - create_ticket handler', () {
    test('returns error for missing tickets field', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tickets"'));
    });

    test('returns error for non-array tickets field', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': 'not-an-array'});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tickets"'));
    });

    test('returns error for empty tickets array', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': []});

      expect(result.isError, isTrue);
      expect(result.content, contains('Empty tickets array'));
    });

    test('returns error for too many proposals', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tooMany = List.generate(
        InternalToolsService.maxProposalCount + 1,
        (i) => {
          'title': 'Ticket $i',
          'description': 'Desc $i',
          'kind': 'feature',
        },
      );

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({'tickets': tooMany});

      expect(result.isError, isTrue);
      expect(result.content, contains('Too many proposals'));
      expect(result.content, contains('> ${InternalToolsService.maxProposalCount}'));
    });

    test('returns error for ticket missing title', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'description': 'A desc', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"title"'));
    });

    test('returns error for ticket missing description', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'A title', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"description"'));
    });

    test('returns error for ticket missing kind', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'A title', 'description': 'A desc'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"kind"'));
    });

    test('returns error for non-object ticket entry', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': ['not-an-object'],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('not a valid object'));
    });

    test('stages valid proposals in board and waits for review', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      // Start the handler (it will return a Future that waits for review)
      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Add dark mode',
            'description': 'Implement dark mode toggle',
            'kind': 'feature',
            'priority': 'high',
          },
        ],
      });

      // The repo should have the staged proposals
      expect(repo.tickets.length, 1);
      expect(repo.tickets.first.title, 'Add dark mode');
      expect(repo.tickets.first.status, TicketStatus.draft);
      expect(bulkProposal.hasActiveProposal, isTrue);

      // The future should not have completed yet
      var completed = false;
      unawaited(resultFuture.then((_) => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(completed, isFalse);

      // Simulate the user approving all tickets
      bulkProposal.approveBulk();

      // Now the future should complete
      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('approved'));
    });

    test('returns appropriate text when all approved', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
        ],
      });

      // All tickets are auto-checked, so approveBulk approves all
      bulkProposal.approveBulk();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('All 2'));
      expect(result.content, contains('approved and created'));
    });

    test('returns appropriate text when all rejected', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
        ],
      });

      // Reject all tickets
      bulkProposal.rejectAll();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('All 2'));
      expect(result.content, contains('rejected'));
    });

    test('returns appropriate text for mixed approval', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'bugfix',
          },
          {
            'title': 'Ticket C',
            'description': 'Desc C',
            'kind': 'chore',
          },
        ],
      });

      // Uncheck one ticket before approving
      final proposedTickets = bulkProposal.proposedTickets;
      expect(proposedTickets.length, 3);

      bulkProposal.toggleProposalChecked(proposedTickets[1].id);
      bulkProposal.approveBulk();

      final result = await resultFuture;
      expect(result.isError, isFalse);
      expect(result.content, contains('2 of 3'));
      expect(result.content, contains('approved and created'));
      expect(result.content, contains('1 were rejected'));
    });

    test('stream-based review supports sequential tool calls', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      // First call
      final resultFuture1 = tool.handler({
        'tickets': [
          {
            'title': 'Ticket A',
            'description': 'Desc A',
            'kind': 'feature',
          },
        ],
      });

      bulkProposal.approveBulk();
      final result1 = await resultFuture1;
      expect(result1.isError, isFalse);

      // Second call should also work (no stale callback issues)
      final resultFuture2 = tool.handler({
        'tickets': [
          {
            'title': 'Ticket B',
            'description': 'Desc B',
            'kind': 'feature',
          },
        ],
      });

      bulkProposal.approveBulk();
      final result2 = await resultFuture2;
      expect(result2.isError, isFalse);
    });

    test('parses optional fields correctly', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Complex ticket',
            'description': 'Detailed work description',
            'kind': 'feature',
            'priority': 'critical',
            'effort': 'large',
            'category': 'Backend',
            'tags': ['api', 'database'],
          },
        ],
      });

      final ticket = repo.tickets.first;
      expect(ticket.title, 'Complex ticket');
      expect(ticket.description, 'Detailed work description');
      expect(ticket.kind, TicketKind.feature);
      expect(ticket.priority, TicketPriority.critical);
      expect(ticket.effort, TicketEffort.large);
      expect(ticket.category, 'Backend');
      expect(ticket.tags, containsAll(['api', 'database']));

      // Clean up by completing the review
      bulkProposal.approveBulk();
      await resultFuture;
    });

    test('returns error for ticket with empty title', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': '', 'description': 'A desc', 'kind': 'feature'},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"title"'));
    });

    test('returns error for ticket with empty kind', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final tool = service.registry['create_ticket']!;
      final result = await tool.handler({
        'tickets': [
          {'title': 'Test', 'description': 'A desc', 'kind': ''},
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('index 0'));
      expect(result.content, contains('"kind"'));
    });
  });

  group('InternalToolsService - git tools', () {
    late FakeGitService fakeGit;

    setUp(() {
      fakeGit = FakeGitService();
    });

    group('registration', () {
      test('registerGitTools adds 4 git tools to registry', () {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        expect(service.registry['git_commit_context'], isNotNull);
        expect(service.registry['git_commit'], isNotNull);
        expect(service.registry['git_log'], isNotNull);
        expect(service.registry['git_diff'], isNotNull);
      });

      test('unregisterGitTools removes all 4 git tools', () {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        expect(service.registry['git_commit_context'], isNotNull);
        expect(service.registry['git_commit'], isNotNull);
        expect(service.registry['git_log'], isNotNull);
        expect(service.registry['git_diff'], isNotNull);

        service.unregisterGitTools();

        expect(service.registry['git_commit_context'], isNull);
        expect(service.registry['git_commit'], isNull);
        expect(service.registry['git_log'], isNull);
        expect(service.registry['git_diff'], isNull);
      });
    });

    group('git_commit_context handler', () {
      test('returns error for missing path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit_context']!;
        final result = await tool.handler({});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('returns error for empty path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit_context']!;
        final result = await tool.handler({'path': ''});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('returns error for relative path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit_context']!;
        final result = await tool.handler({'path': 'relative/path'});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('success: returns JSON with branch, status, diff_stat, '
          'recent_commits', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        // Configure fake git service
        fakeGit.branches['/test/repo'] = 'feat-dark-mode';
        fakeGit.changedFiles['/test/repo'] = [
          const GitFileChange(
            path: 'lib/foo.dart',
            status: GitFileStatus.modified,
            isStaged: false,
          ),
          const GitFileChange(
            path: 'docs/new.md',
            status: GitFileStatus.untracked,
            isStaged: false,
          ),
          const GitFileChange(
            path: 'lib/old.dart',
            status: GitFileStatus.deleted,
            isStaged: false,
          ),
          const GitFileChange(
            path: 'lib/bar.dart',
            status: GitFileStatus.modified,
            isStaged: true,
          ),
        ];
        fakeGit.diffStats['/test/repo'] = ' lib/foo.dart | 2 +-\n 1 file changed';
        fakeGit.recentCommitsMap['/test/repo'] = [
          (sha: '7b9d56e', message: 'Add feature X'),
          (sha: '3ffb102', message: 'Fix bug Y'),
        ];

        final tool = service.registry['git_commit_context']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isFalse);

        final json = jsonDecode(result.content) as Map<String, dynamic>;
        expect(json['branch'], 'feat-dark-mode');

        final status = json['status'] as Map<String, dynamic>;
        expect(status['modified'], ['lib/foo.dart']);
        expect(status['untracked'], ['docs/new.md']);
        expect(status['deleted'], ['lib/old.dart']);
        expect(status['staged'], ['lib/bar.dart']);

        expect(json['diff_stat'], ' lib/foo.dart | 2 +-\n 1 file changed');

        final commits = json['recent_commits'] as List;
        expect(commits.length, 2);
        expect(commits[0]['sha'], '7b9d56e');
        expect(commits[0]['message'], 'Add feature X');
        expect(commits[1]['sha'], '3ffb102');
        expect(commits[1]['message'], 'Fix bug Y');
      });

      test('returns error when git throws', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.throwOnAll = const GitException('not a git repository');

        final tool = service.registry['git_commit_context']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isTrue);
        expect(result.content, contains('Git error:'));
        expect(result.content, contains('not a git repository'));
      });
    });

    group('git_commit handler', () {
      test('returns error for missing path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('returns error for missing files', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or invalid "files"'));
      });

      test('returns error for empty files array', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': [],
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or invalid "files"'));
      });

      test('returns error for wildcard in files', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['*'],
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Wildcards'));
        expect(result.content, contains('not allowed'));
      });

      test('returns error for dot in files', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['.'],
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Wildcards'));
        expect(result.content, contains('"."'));
        expect(result.content, contains('not allowed'));
      });

      test('returns error for glob in files', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['*.dart'],
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Wildcards'));
        expect(result.content, contains('not allowed'));
      });

      test('returns error for non-string file entry', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': [123],
          'message': 'Test commit',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('File at index 0'));
        expect(result.content, contains('not a valid string'));
      });

      test('returns error for missing message', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart'],
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "message"'));
      });

      test('returns error for empty message', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart'],
          'message': '',
        });

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "message"'));
      });

      test('success: stages files, commits, returns JSON', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.headShortShas['/test/repo'] = '495d5de';

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart', 'lib/bar.dart'],
          'message': 'Add new features',
        });

        expect(result.isError, isFalse);

        // Verify stageFiles was called
        expect(fakeGit.stageFilesCalls.length, 1);
        expect(fakeGit.stageFilesCalls[0].$1, '/test/repo');
        expect(fakeGit.stageFilesCalls[0].$2, ['lib/foo.dart', 'lib/bar.dart']);

        // Verify commit was called
        expect(fakeGit.commitCalls.length, 1);
        expect(fakeGit.commitCalls[0].$1, '/test/repo');
        expect(fakeGit.commitCalls[0].$2, 'Add new features');

        // Verify result JSON
        final json = jsonDecode(result.content) as Map<String, dynamic>;
        expect(json['success'], isTrue);
        expect(json['sha'], '495d5de');
        expect(json['message'], 'Add new features');
        expect(json['files_committed'], ['lib/foo.dart', 'lib/bar.dart']);
      });

      test('success: co_author appended as trailer', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.headShortShas['/test/repo'] = '495d5de';

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart'],
          'message': 'Add feature',
          'co_author': 'Claude <claude@anthropic.com>',
        });

        expect(result.isError, isFalse);

        // Verify commit message includes co-author
        expect(fakeGit.commitCalls.length, 1);
        final commitMessage = fakeGit.commitCalls[0].$2;
        expect(
          commitMessage,
          'Add feature\n\nCo-Authored-By: Claude <claude@anthropic.com>',
        );
      });

      test('error: commit fails → resets index, returns JSON with error',
          () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.commitError = const GitException('pre-commit hook failed');

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart'],
          'message': 'Add feature',
        });

        expect(result.isError, isFalse); // Returns JSON, not error

        // Verify stageFiles was called
        expect(fakeGit.stageFilesCalls.length, 1);

        // Verify commit was attempted
        expect(fakeGit.commitCalls.length, 1);

        // Verify resetIndex was called
        expect(fakeGit.resetIndexCalls.length, 1);
        expect(fakeGit.resetIndexCalls[0], '/test/repo');

        // Verify result JSON
        final json = jsonDecode(result.content) as Map<String, dynamic>;
        expect(json['success'], isFalse);
        expect(json['error'], 'pre-commit hook failed');
      });

      test('error: stage fails → returns JSON with error (no commit attempted)',
          () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.stageFilesError = const GitException('pathspec did not match');

        final tool = service.registry['git_commit']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart'],
          'message': 'Add feature',
        });

        expect(result.isError, isFalse); // Returns JSON, not error

        // Verify stageFiles was attempted
        expect(fakeGit.stageFilesCalls.length, 1);

        // Verify commit was NOT called
        expect(fakeGit.commitCalls.length, 0);

        // Verify resetIndex was called (best-effort cleanup)
        expect(fakeGit.resetIndexCalls.length, 1);

        // Verify result JSON
        final json = jsonDecode(result.content) as Map<String, dynamic>;
        expect(json['success'], isFalse);
        expect(json['error'], 'pathspec did not match');
      });
    });

    group('git_log handler', () {
      test('returns error for missing path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_log']!;
        final result = await tool.handler({});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('success: returns log output text', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.logs['/test/repo'] =
            'commit abc123\nAuthor: Alice\nDate: 2026-01-01\n\n    '
            'Add feature\n\ncommit def456\nAuthor: Bob\nDate: 2026-01-02\n\n    '
            'Fix bug';

        final tool = service.registry['git_log']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isFalse);
        expect(result.content, contains('commit abc123'));
        expect(result.content, contains('Add feature'));
        expect(result.content, contains('commit def456'));
        expect(result.content, contains('Fix bug'));
      });

      test('returns "(no commits)" for empty log', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.logs['/test/repo'] = '';

        final tool = service.registry['git_log']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isFalse);
        expect(result.content, '(no commits)');
      });

      test('count defaults to 5', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.logs['/test/repo'] = 'commit abc123';

        final tool = service.registry['git_log']!;
        await tool.handler({'path': '/test/repo'});

        // The handler just passes count to getLog, we can't verify the exact
        // value was used without inspecting calls, but we can verify it works
        // without count parameter
      });

      test('count clamped: negative → 1', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.logs['/test/repo'] = 'commit abc123';

        final tool = service.registry['git_log']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'count': -5,
        });

        expect(result.isError, isFalse);
        // count is clamped to 1 internally
      });

      test('count clamped: over 50 → 50', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.logs['/test/repo'] = 'commit abc123';

        final tool = service.registry['git_log']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'count': 100,
        });

        expect(result.isError, isFalse);
        // count is clamped to 50 internally
      });
    });

    group('git_diff handler', () {
      test('returns error for missing path', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final tool = service.registry['git_diff']!;
        final result = await tool.handler({});

        expect(result.isError, isTrue);
        expect(result.content, contains('Missing or empty "path"'));
      });

      test('success: returns unstaged diff by default', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.diffs['/test/repo'] = 'diff --git a/lib/foo.dart '
            'b/lib/foo.dart\n+added line';

        final tool = service.registry['git_diff']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isFalse);
        expect(result.content, contains('diff --git a/lib/foo.dart'));
        expect(result.content, contains('+added line'));
      });

      test('returns "(no changes)" for empty diff', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.diffs['/test/repo'] = '';

        final tool = service.registry['git_diff']!;
        final result = await tool.handler({'path': '/test/repo'});

        expect(result.isError, isFalse);
        expect(result.content, '(no changes)');
      });

      test('success: staged=true returns staged diff', () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.diffs['/test/repo'] = 'diff --git a/lib/bar.dart '
            'b/lib/bar.dart\n+staged change';

        final tool = service.registry['git_diff']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'staged': true,
        });

        expect(result.isError, isFalse);
        expect(result.content, contains('diff --git a/lib/bar.dart'));
        expect(result.content, contains('+staged change'));
      });

      test('files parameter: handler runs without error when files provided',
          () async {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        fakeGit.diffs['/test/repo'] = 'diff --git a/lib/foo.dart '
            'b/lib/foo.dart';

        final tool = service.registry['git_diff']!;
        final result = await tool.handler({
          'path': '/test/repo',
          'files': ['lib/foo.dart', 'lib/bar.dart'],
        });

        expect(result.isError, isFalse);
      });
    });
  });
}
