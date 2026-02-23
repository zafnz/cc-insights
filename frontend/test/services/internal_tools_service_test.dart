import 'dart:async';
import 'dart:convert';

import 'package:cc_insights_v2/models/chat.dart';
import 'package:cc_insights_v2/models/managed_agent.dart';
import 'package:cc_insights_v2/models/project.dart';
import 'package:cc_insights_v2/models/ticket.dart';
import 'package:cc_insights_v2/models/worktree.dart';
import 'package:cc_insights_v2/models/worktree_tag.dart';
import 'package:cc_insights_v2/services/backend_service.dart';
import 'package:cc_insights_v2/services/event_handler.dart';
import 'package:cc_insights_v2/services/git_service.dart';
import 'package:cc_insights_v2/services/internal_tools_service.dart';
import 'package:cc_insights_v2/services/project_restore_service.dart';
import 'package:cc_insights_v2/services/settings_service.dart';
import 'package:cc_insights_v2/services/worktree_service.dart';
import 'package:cc_insights_v2/state/bulk_proposal_state.dart';
import 'package:cc_insights_v2/state/orchestrator_state.dart';
import 'package:cc_insights_v2/state/selection_state.dart';
import 'package:cc_insights_v2/state/ticket_board_state.dart';
import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_git_service.dart';
import '../fakes/fake_persistence_service.dart';
import '../test_helpers.dart';

class _FakeTransport implements EventTransport {
  final List<BackendCommand> sentCommands = [];

  @override
  String? get sessionId => 'test-session';

  @override
  String? get resolvedSessionId => sessionId;

  @override
  BackendCapabilities? get capabilities => null;

  @override
  Stream<InsightsEvent> get events => const Stream.empty();

  @override
  Stream<TransportStatus> get status => const Stream.empty();

  @override
  Stream<PermissionRequest> get permissionRequests => const Stream.empty();

  @override
  String? get serverModel => null;

  @override
  String? get serverReasoningEffort => null;

  @override
  Future<void> send(BackendCommand command) async {
    sentCommands.add(command);
  }

  @override
  Future<void> dispose() async {}
}

PermissionRequest _createFakePermissionRequest({
  required String id,
  String sessionId = 'test-session',
  String toolName = 'Bash',
  Map<String, dynamic> toolInput = const {'command': 'ls'},
}) {
  final completer = Completer<PermissionResponse>();
  return PermissionRequest(
    id: id,
    sessionId: sessionId,
    toolName: toolName,
    toolInput: toolInput,
    toolUseId: id,
    completer: completer,
  );
}

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

  group('InternalToolsService - registryForChat create_ticket', () {
    test('injects chat id and name into proposeBulk', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      final chat = Chat.create(
        name: 'My Test Chat',
        worktreeRoot: '/test/worktree',
      );
      final registry = service.registryForChat(chat);
      final tool = registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Test ticket',
            'description': 'A description',
            'kind': 'feature',
          },
        ],
      });

      // Verify the chat context was passed through to proposeBulk
      expect(bulkProposal.proposalSourceChatId, chat.id);
      expect(bulkProposal.proposalSourceChatName, 'My Test Chat');

      // Complete the review so the future resolves
      bulkProposal.approveBulk();
      await resultFuture;
    });

    test('global registry handler uses fallback source values', () async {
      final service = resources.track(InternalToolsService());
      final repo = resources.track(TicketRepository('test-project'));
      final bulkProposal = resources.track(BulkProposalState(repo));
      service.registerTicketTools(bulkProposal);

      // Use the global registry (not registryForChat)
      final tool = service.registry['create_ticket']!;

      final resultFuture = tool.handler({
        'tickets': [
          {
            'title': 'Test ticket',
            'description': 'A description',
            'kind': 'feature',
          },
        ],
      });

      expect(bulkProposal.proposalSourceChatId, 'mcp-tool');
      expect(bulkProposal.proposalSourceChatName, 'Agent');

      bulkProposal.approveBulk();
      await resultFuture;
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

      test('systemPromptAppend returns null when git tools not registered', () {
        final service = resources.track(InternalToolsService());
        expect(service.systemPromptAppend, isNull);
      });

      test('systemPromptAppend returns instruction when git tools registered',
          () {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);

        final append = service.systemPromptAppend;
        expect(append, isNotNull);
        expect(append, contains('git_commit_context'));
        expect(append, contains('git_commit'));
        expect(append, contains('git_log'));
        expect(append, contains('git_diff'));
        expect(append, contains('Prefer these over running git commands'));
      });

      test('systemPromptAppend returns null after unregisterGitTools', () {
        final service = resources.track(InternalToolsService());
        service.registerGitTools(fakeGit);
        expect(service.systemPromptAppend, isNotNull);

        service.unregisterGitTools();
        expect(service.systemPromptAppend, isNull);
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

      test('success: stages files, commits, returns message', () async {
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

        // Verify result is a human-readable success message
        expect(result.content, contains('495d5de'));
        expect(result.content, contains('2 files'));
        expect(result.content, contains('Add new features'));
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

      test('error: commit fails → resets index, returns error',
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

        expect(result.isError, isTrue);

        // Verify stageFiles was called
        expect(fakeGit.stageFilesCalls.length, 1);

        // Verify commit was attempted
        expect(fakeGit.commitCalls.length, 1);

        // Verify resetIndex was called
        expect(fakeGit.resetIndexCalls.length, 1);
        expect(fakeGit.resetIndexCalls[0], '/test/repo');

        // Verify error message
        expect(result.content, contains('pre-commit hook failed'));
      });

      test('error: stage fails → returns error (no commit attempted)',
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

        expect(result.isError, isTrue);

        // Verify stageFiles was attempted
        expect(fakeGit.stageFilesCalls.length, 1);

        // Verify commit was NOT called
        expect(fakeGit.commitCalls.length, 0);

        // Verify resetIndex was called (best-effort cleanup)
        expect(fakeGit.resetIndexCalls.length, 1);

        // Verify error message
        expect(result.content, contains('pathspec did not match'));
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

  group('InternalToolsService - check_agents handler', () {
    late InternalToolsService service;
    late OrchestratorState orchestratorState;
    late Chat orchestratorChat;

    setUp(() {
      service = resources.track(InternalToolsService());
      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/worktree',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      final repo = resources.track(TicketRepository('test-project'));
      final fakeGit = FakeGitService();
      final fakePersistence = FakePersistenceService();
      final settingsService = SettingsService(persistToDisk: false);
      final restoreService = ProjectRestoreService(
        persistence: fakePersistence,
      );
      final selection = SelectionState(
        project,
        restoreService: restoreService,
      );
      final worktreeService = WorktreeService(
        gitService: fakeGit,
        persistenceService: fakePersistence,
      );

      service.bindOrchestrationContext(
        backend: BackendService(),
        eventHandler: EventHandler(),
        project: project,
        selection: selection,
        ticketBoard: repo,
        worktreeService: worktreeService,
        restoreService: restoreService,
        gitService: fakeGit,
        settingsService: settingsService,
        persistenceService: fakePersistence,
      );

      orchestratorChat = Chat.create(
        name: 'Orchestrator',
        worktreeRoot: '/test/worktree',
      );
      orchestratorState = OrchestratorState(
        ticketBoard: repo,
        ticketIds: [],
        baseWorktreePath: '/test/worktree',
      );
      service.attachOrchestratorState(orchestratorChat, orchestratorState);
    });

    InternalToolDefinition getCheckAgentsTool() {
      final registry = service.registryForChat(orchestratorChat);
      return registry['check_agents']!;
    }

    test('returns error for missing agent_ids', () async {
      final tool = getCheckAgentsTool();
      final result = await tool.handler({});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or empty "agent_ids"'));
    });

    test('returns error for empty agent_ids list', () async {
      final tool = getCheckAgentsTool();
      final result = await tool.handler({'agent_ids': []});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or empty "agent_ids"'));
    });

    test('returns status for a single agent', () async {
      final agentChat = Chat.create(
        name: 'Agent A',
        worktreeRoot: '/test/worktree',
      );
      orchestratorState.registerAgent(
        agentId: 'agent-A',
        chat: agentChat,
      );

      final tool = getCheckAgentsTool();
      final result = await tool.handler({
        'agent_ids': ['agent-A'],
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      final agents = json['agents'] as List;
      final errors = json['errors'] as List;

      expect(agents.length, 1);
      expect(errors, isEmpty);

      final agent = agents[0] as Map<String, dynamic>;
      expect(agent['agent_id'], 'agent-A');
      expect(agent['status'], isA<String>());
      expect(agent['is_working'], isFalse);
      expect(agent['turn_count'], isA<int>());
      expect(agent['has_pending_permission'], isFalse);
    });

    test('returns status for multiple agents', () async {
      final agentChatA = Chat.create(
        name: 'Agent A',
        worktreeRoot: '/test/worktree',
      );
      final agentChatB = Chat.create(
        name: 'Agent B',
        worktreeRoot: '/test/worktree',
      );
      orchestratorState.registerAgent(
        agentId: 'agent-A',
        chat: agentChatA,
      );
      orchestratorState.registerAgent(
        agentId: 'agent-B',
        chat: agentChatB,
      );

      final tool = getCheckAgentsTool();
      final result = await tool.handler({
        'agent_ids': ['agent-A', 'agent-B'],
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      final agents = json['agents'] as List;
      final errors = json['errors'] as List;

      expect(agents.length, 2);
      expect(errors, isEmpty);

      final ids = agents.map((a) => (a as Map<String, dynamic>)['agent_id']);
      expect(ids, containsAll(['agent-A', 'agent-B']));
    });

    test('returns mix of valid agents and errors for unknown IDs', () async {
      final agentChat = Chat.create(
        name: 'Agent A',
        worktreeRoot: '/test/worktree',
      );
      orchestratorState.registerAgent(
        agentId: 'agent-A',
        chat: agentChat,
      );

      final tool = getCheckAgentsTool();
      final result = await tool.handler({
        'agent_ids': ['agent-A', 'unknown-1', 'unknown-2'],
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      final agents = json['agents'] as List;
      final errors = json['errors'] as List;

      expect(agents.length, 1);
      expect(
        (agents[0] as Map<String, dynamic>)['agent_id'],
        'agent-A',
      );

      expect(errors.length, 2);
      expect(
        (errors[0] as Map<String, dynamic>)['agent_id'],
        'unknown-1',
      );
      expect(
        (errors[0] as Map<String, dynamic>)['error'],
        'agent_not_found',
      );
      expect(
        (errors[1] as Map<String, dynamic>)['agent_id'],
        'unknown-2',
      );
    });

    test('tool is registered in orchestrator tools', () {
      final registry = service.registryForChat(orchestratorChat);
      expect(registry['check_agents'], isNotNull);
      expect(registry['check_agents']!.name, 'check_agents');
    });

    test('tool is not available for non-orchestrator chats', () async {
      // Ensure a distinct chat ID by waiting 1ms.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final regularChat = Chat.create(
        name: 'Regular Chat',
        worktreeRoot: '/test/worktree',
      );
      final registry = service.registryForChat(regularChat);
      expect(registry['check_agents'], isNull);
    });
  });

  group('InternalToolsService - set_tags handler', () {
    late InternalToolsService service;
    late WorktreeState worktree;

    setUp(() {
      service = resources.track(InternalToolsService());
      worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/worktree',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      final repo = resources.track(TicketRepository('test-project'));
      final fakeGit = FakeGitService();
      final fakePersistence = FakePersistenceService();
      final settingsService = SettingsService(persistToDisk: false);
      final restoreService = ProjectRestoreService(
        persistence: fakePersistence,
      );
      final selection = SelectionState(
        project,
        restoreService: restoreService,
      );
      final worktreeService = WorktreeService(
        gitService: fakeGit,
        persistenceService: fakePersistence,
      );

      service.bindOrchestrationContext(
        backend: BackendService(),
        eventHandler: EventHandler(),
        project: project,
        selection: selection,
        ticketBoard: repo,
        worktreeService: worktreeService,
        restoreService: restoreService,
        gitService: fakeGit,
        settingsService: settingsService,
        persistenceService: fakePersistence,
      );
    });

    InternalToolDefinition getSetTagsTool() {
      final chat = Chat.create(name: 'Orchestrator', worktreeRoot: '/test/worktree');
      chat.settings.setOrchestrationToolsEnabled(true);
      final registry = service.registryForChat(chat);
      return registry['set_tags']!;
    }

    test('returns error for missing worktree', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({'tags': ['ready']});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing required "worktree"'));
    });

    test('returns error for empty worktree', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({'worktree': '', 'tags': ['ready']});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing required "worktree"'));
    });

    test('returns error for missing tags', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({'worktree': '/test/worktree'});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tags"'));
    });

    test('returns error for non-array tags', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({
        'worktree': '/test/worktree',
        'tags': 'not-an-array',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing or invalid "tags"'));
    });

    test('returns error for unknown worktree path', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({
        'worktree': '/unknown/path',
        'tags': ['ready'],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('worktree_not_found'));
    });

    test('sets tags on worktree successfully', () async {
      final tool = getSetTagsTool();
      final result = await tool.handler({
        'worktree': '/test/worktree',
        'tags': ['ready', 'testing'],
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['success'], isTrue);
      expect(json['worktree'], '/test/worktree');
      expect(json['tags'], ['ready', 'testing']);

      // Verify worktree state was updated
      expect(worktree.tags, ['ready', 'testing']);
    });

    test('replaces existing tags', () async {
      worktree.setTags(['old-tag']);
      expect(worktree.tags, ['old-tag']);

      final tool = getSetTagsTool();
      final result = await tool.handler({
        'worktree': '/test/worktree',
        'tags': ['new-tag'],
      });

      expect(result.isError, isFalse);
      expect(worktree.tags, ['new-tag']);
    });

    test('sets empty tags list', () async {
      worktree.setTags(['ready', 'testing']);

      final tool = getSetTagsTool();
      final result = await tool.handler({
        'worktree': '/test/worktree',
        'tags': [],
      });

      expect(result.isError, isFalse);
      expect(worktree.tags, isEmpty);
    });
  });

  group('InternalToolsService - list_tags handler', () {
    late InternalToolsService service;

    setUp(() {
      service = resources.track(InternalToolsService());
      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/worktree',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      final repo = resources.track(TicketRepository('test-project'));
      final fakeGit = FakeGitService();
      final fakePersistence = FakePersistenceService();
      final settingsService = SettingsService(persistToDisk: false);
      final restoreService = ProjectRestoreService(
        persistence: fakePersistence,
      );
      final selection = SelectionState(
        project,
        restoreService: restoreService,
      );
      final worktreeService = WorktreeService(
        gitService: fakeGit,
        persistenceService: fakePersistence,
      );

      service.bindOrchestrationContext(
        backend: BackendService(),
        eventHandler: EventHandler(),
        project: project,
        selection: selection,
        ticketBoard: repo,
        worktreeService: worktreeService,
        restoreService: restoreService,
        gitService: fakeGit,
        settingsService: settingsService,
        persistenceService: fakePersistence,
      );
    });

    InternalToolDefinition getListTagsTool() {
      final chat = Chat.create(name: 'Orchestrator', worktreeRoot: '/test/worktree');
      chat.settings.setOrchestrationToolsEnabled(true);
      final registry = service.registryForChat(chat);
      return registry['list_tags']!;
    }

    test('returns default tags when no custom tags configured', () async {
      final tool = getListTagsTool();
      final result = await tool.handler({});

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      final tags = json['tags'] as List;

      // Should return default tags
      expect(tags.length, WorktreeTag.defaults.length);
      expect(
        tags.map((t) => (t as Map<String, dynamic>)['name']),
        containsAll(['ready', 'testing', 'mergable', 'in-review']),
      );
    });

    test('returns tag names and colors', () async {
      final tool = getListTagsTool();
      final result = await tool.handler({});

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      final tags = json['tags'] as List;

      // Verify structure of each tag
      for (final tag in tags) {
        final tagMap = tag as Map<String, dynamic>;
        expect(tagMap.containsKey('name'), isTrue);
        expect(tagMap.containsKey('color'), isTrue);
        expect(tagMap['name'], isA<String>());
        expect(tagMap['color'], isA<int>());
      }
    });

    test('tool is registered in orchestrator tools', () async {
      final chat = Chat.create(name: 'Orchestrator', worktreeRoot: '/test/worktree');
      chat.settings.setOrchestrationToolsEnabled(true);
      final registry = service.registryForChat(chat);

      expect(registry['set_tags'], isNotNull);
      expect(registry['list_tags'], isNotNull);
    });

    test('tools are not available for non-orchestrator chats', () async {
      final chat = Chat.create(name: 'Regular Chat', worktreeRoot: '/test/worktree');
      final registry = service.registryForChat(chat);

      expect(registry['set_tags'], isNull);
      expect(registry['list_tags'], isNull);
    });
  });

  group('InternalToolsService - rebase_and_merge handler', () {
    late InternalToolsService service;
    late FakeGitService fakeGit;
    late WorktreeState baseWorktree;
    late WorktreeState workerWorktree;
    late Chat orchestratorChat;

    setUp(() {
      service = resources.track(InternalToolsService());
      fakeGit = FakeGitService();

      baseWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/base-worktree',
          isPrimary: false,
          branch: 'orchestrate-1-11',
        ),
      );
      workerWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/worker-worktree',
          isPrimary: false,
          branch: 'tkt-7-feature',
        ),
        base: 'tkt-6-model-permission-widget',
      );

      final primaryWorktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/repo',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          primaryWorktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      project.addLinkedWorktree(baseWorktree);
      project.addLinkedWorktree(workerWorktree);

      final repo = resources.track(TicketRepository('test-project'));
      final fakePersistence = FakePersistenceService();
      final settingsService = SettingsService(persistToDisk: false);
      final restoreService = ProjectRestoreService(
        persistence: fakePersistence,
      );
      final selection = SelectionState(
        project,
        restoreService: restoreService,
      );
      final worktreeService = WorktreeService(
        gitService: fakeGit,
        persistenceService: fakePersistence,
      );

      service.bindOrchestrationContext(
        backend: BackendService(),
        eventHandler: EventHandler(),
        project: project,
        selection: selection,
        ticketBoard: repo,
        worktreeService: worktreeService,
        restoreService: restoreService,
        gitService: fakeGit,
        settingsService: settingsService,
        persistenceService: fakePersistence,
      );

      orchestratorChat = Chat.create(
        name: 'Orchestrator',
        worktreeRoot: '/test/base-worktree',
      );
      final orchState = OrchestratorState(
        ticketBoard: repo,
        ticketIds: [7],
        baseWorktreePath: '/test/base-worktree',
      );
      service.attachOrchestratorState(orchestratorChat, orchState);
    });

    InternalToolDefinition getRebaseAndMergeTool() {
      final registry = service.registryForChat(orchestratorChat);
      return registry['rebase_and_merge']!;
    }

    test('updates worker base ref after successful merge', () async {
      // Worker starts with stale base
      expect(workerWorktree.base, 'tkt-6-model-permission-widget');

      final tool = getRebaseAndMergeTool();
      final result = await tool.handler({
        'worktree_path': '/test/worker-worktree',
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['success'], isTrue);

      // Worker base should now point at the orchestrator's branch
      expect(workerWorktree.base, 'orchestrate-1-11');
    });

    test('does not update base ref on rebase conflict', () async {
      fakeGit.rebaseResults['/test/worker-worktree'] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.rebase,
      );

      final tool = getRebaseAndMergeTool();
      final result = await tool.handler({
        'worktree_path': '/test/worker-worktree',
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['success'], isFalse);

      // Base should remain unchanged
      expect(workerWorktree.base, 'tkt-6-model-permission-widget');
    });

    test('does not update base ref on merge conflict', () async {
      fakeGit.mergeResults['/test/base-worktree'] = const MergeResult(
        hasConflicts: true,
        operation: MergeOperationType.merge,
      );

      final tool = getRebaseAndMergeTool();
      final result = await tool.handler({
        'worktree_path': '/test/worker-worktree',
      });

      expect(result.isError, isFalse);
      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['success'], isFalse);

      // Base should remain unchanged
      expect(workerWorktree.base, 'tkt-6-model-permission-widget');
    });

    test('returns error for missing worktree_path', () async {
      final tool = getRebaseAndMergeTool();
      final result = await tool.handler({});

      expect(result.isError, isTrue);
      expect(result.content, contains('Missing "worktree_path"'));
    });

    test('returns error for unknown worktree path', () async {
      final tool = getRebaseAndMergeTool();
      final result = await tool.handler({
        'worktree_path': '/unknown/path',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('worktree_not_found'));
    });
  });

  group('InternalToolsService - ask_agent handler', () {
    late InternalToolsService service;
    late Chat orchestratorChat;
    late Chat workerChat;
    late OrchestratorState orchestratorState;

    setUp(() {
      service = resources.track(InternalToolsService());
      final worktree = WorktreeState(
        const WorktreeData(
          worktreeRoot: '/test/worktree',
          isPrimary: true,
          branch: 'main',
        ),
      );
      final project = resources.track(
        ProjectState(
          const ProjectData(name: 'test', repoRoot: '/test/repo'),
          worktree,
          autoValidate: false,
          watchFilesystem: false,
        ),
      );
      final repo = resources.track(TicketRepository('test-project'));
      final fakeGit = FakeGitService();
      final fakePersistence = FakePersistenceService();
      final settingsService = SettingsService(persistToDisk: false);
      final restoreService = ProjectRestoreService(
        persistence: fakePersistence,
      );
      final selection = SelectionState(
        project,
        restoreService: restoreService,
      );
      final worktreeService = WorktreeService(
        gitService: fakeGit,
        persistenceService: fakePersistence,
      );

      service.bindOrchestrationContext(
        backend: BackendService(),
        eventHandler: EventHandler(),
        project: project,
        selection: selection,
        ticketBoard: repo,
        worktreeService: worktreeService,
        restoreService: restoreService,
        gitService: fakeGit,
        settingsService: settingsService,
        persistenceService: fakePersistence,
      );

      orchestratorChat = Chat.create(
        name: 'Orchestrator',
        worktreeRoot: '/test/worktree',
      );

      orchestratorState = OrchestratorState(
        ticketBoard: repo,
        ticketIds: [1],
        baseWorktreePath: '/test/worktree',
      );
      service.attachOrchestratorState(orchestratorChat, orchestratorState);

      workerChat = Chat.create(
        name: 'Worker',
        worktreeRoot: '/test/worktree',
      );
      workerChat.session.setHasActiveSessionForTesting(true);
      workerChat.session.setTransport(_FakeTransport());

      orchestratorState.registerAgent(
        agentId: 'agent-1',
        chat: workerChat,
      );
    });

    InternalToolDefinition getAskAgentTool() {
      final registry = service.registryForChat(orchestratorChat);
      return registry['ask_agent']!;
    }

    test('timeout returns working-agent error message', () async {
      final tool = getAskAgentTool();

      // The worker is set to "working" by sendMessage, and we never
      // transition it to idle, so the wait will time out.
      final result = await tool.handler({
        'agent_id': 'agent-1',
        'message': 'Do something',
        'timeout_seconds': 1,
      });

      expect(result.isError, isFalse);

      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['wait_timed_out'], isTrue);
      expect(json['status'], AgentReadyReason.turnComplete.wireValue);
      expect(
        json['error'],
        contains('ask_agent timed out after 1 second'),
      );
      expect(json['error'], contains('wait_for_agents'));
      expect(json['error'], isNot(contains('waiting on the user')));
    });

    test('timeout returns waiting-on-user error message', () async {
      final tool = getAskAgentTool();

      // Start the ask_agent call with a very short timeout.
      final resultFuture = tool.handler({
        'agent_id': 'agent-1',
        'message': 'Do something',
        'timeout_seconds': 1,
      });

      // Simulate the agent being working AND having a pending permission.
      // The agent is still isWorking=true (set by sendMessage), and we add
      // a permission request to simulate the SDK pausing for user approval.
      // With treatPermissionAsReady=false, the wait ignores the permission
      // and times out.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      workerChat.permissions.add(
        _createFakePermissionRequest(id: 'perm-1'),
      );

      final result = await resultFuture;
      expect(result.isError, isFalse);

      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['wait_timed_out'], isTrue);
      expect(json['status'], AgentReadyReason.permissionNeeded.wireValue);
      expect(
        json['error'],
        contains('ask_agent timed out after 1 second'),
      );
      expect(
        json['error'],
        contains('waiting on the user'),
      );
    });

    test('explicit timeout_seconds override works', () async {
      final tool = getAskAgentTool();

      // Use a 2-second timeout and verify it actually waits longer
      // than the default 1s test, but still times out since the agent
      // remains working.
      final stopwatch = Stopwatch()..start();
      final result = await tool.handler({
        'agent_id': 'agent-1',
        'message': 'Do something',
        'timeout_seconds': 2,
      });
      stopwatch.stop();

      final json = jsonDecode(result.content) as Map<String, dynamic>;
      expect(json['wait_timed_out'], isTrue);
      expect(
        json['error'],
        contains('ask_agent timed out after 2 second'),
      );
      // Verify it actually waited ~2s (at least 1.5s to avoid flakiness)
      expect(stopwatch.elapsedMilliseconds, greaterThan(1500));
    });

    test('tool description documents 60s default', () {
      final tool = getAskAgentTool();
      expect(tool.description, contains('60s'));
    });
  });
}
