import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import '../state/bulk_proposal_state.dart';
import 'git_service.dart';

/// Service that manages internal MCP tools for CC-Insights.
///
/// Owns the [InternalToolRegistry] and registers application-level tools
/// that agent backends can invoke via the MCP protocol.
class InternalToolsService extends ChangeNotifier {
  final InternalToolRegistry _registry = InternalToolRegistry();

  /// The tool registry to pass to backend sessions.
  InternalToolRegistry get registry => _registry;

  /// Returns system prompt text to append when git tools are registered,
  /// or null if no git tools are active.
  String? get systemPromptAppend {
    if (_gitService == null) return null;
    return 'You have access to internal git MCP tools '
        '(git_commit_context, git_commit, git_log, git_diff). '
        'Prefer these over running git commands via the shell — '
        'they are faster and safer. '
        'Fall back to shell git only for operations these tools '
        'do not cover.';
  }

  /// Maximum number of ticket proposals allowed in a single create_ticket call.
  static const int maxProposalCount = 50;

  /// Register the create_ticket tool with the given bulk proposal state.
  ///
  /// The tool handler parses ticket proposals from the input,
  /// stages them for user review, and waits for
  /// the review to complete via [BulkProposalState.onBulkReviewComplete] stream.
  void registerTicketTools(BulkProposalState proposalState) {
    _registry.register(InternalToolDefinition(
      name: 'create_ticket',
      description:
          'Create one or more tickets on the project board. '
          'Each ticket has a title, description, kind '
          '(feature/bugfix/research/question/test/docs/chore), '
          'optional priority, effort, category, tags, '
          'and dependency indices.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'tickets': {
            'type': 'array',
            'description': 'Array of ticket proposals to create',
            'items': {
              'type': 'object',
              'properties': {
                'title': {
                  'type': 'string',
                  'description': 'Short title describing the ticket',
                },
                'description': {
                  'type': 'string',
                  'description': 'Detailed description of the work',
                },
                'kind': {
                  'type': 'string',
                  'enum': [
                    'feature',
                    'bugfix',
                    'research',
                    'question',
                    'test',
                    'docs',
                    'chore',
                  ],
                  'description': 'Type of work',
                },
                'priority': {
                  'type': 'string',
                  'enum': ['critical', 'high', 'medium', 'low'],
                  'description': 'Priority level (defaults to medium)',
                },
                'effort': {
                  'type': 'string',
                  'enum': ['small', 'medium', 'large'],
                  'description': 'Estimated effort (defaults to medium)',
                },
                'category': {
                  'type': 'string',
                  'description': 'Optional category for grouping',
                },
                'tags': {
                  'type': 'array',
                  'items': {'type': 'string'},
                  'description': 'Tags for categorization',
                },
                'dependsOnIndices': {
                  'type': 'array',
                  'items': {'type': 'integer'},
                  'description':
                      'Indices of tickets in this array that '
                      'this ticket depends on',
                },
              },
              'required': ['title', 'description', 'kind'],
            },
          },
        },
        'required': ['tickets'],
      },
      handler: (input) => _handleCreateTicket(proposalState, input),
    ));
  }

  /// Unregister ticket tools (e.g., when board changes).
  void unregisterTicketTools() {
    _registry.unregister('create_ticket');
  }

  Future<InternalToolResult> _handleCreateTicket(
    BulkProposalState proposalState,
    Map<String, dynamic> input,
  ) async {
    // Parse tickets array
    final ticketsInput = input['tickets'];
    if (ticketsInput == null || ticketsInput is! List) {
      return InternalToolResult.error(
        'Missing or invalid "tickets" field. '
        'Expected an array of ticket objects.',
      );
    }

    if (ticketsInput.isEmpty) {
      return InternalToolResult.error('Empty tickets array.');
    }

    if (ticketsInput.length > maxProposalCount) {
      return InternalToolResult.error(
        'Too many proposals '
        '(${ticketsInput.length} > $maxProposalCount).',
      );
    }

    // Parse proposals
    final proposals = <TicketProposal>[];
    for (var i = 0; i < ticketsInput.length; i++) {
      final json = ticketsInput[i];
      if (json is! Map<String, dynamic>) {
        return InternalToolResult.error(
          'Ticket at index $i is not a valid object.',
        );
      }

      final title = json['title'] as String?;
      final description = json['description'] as String?;
      final kind = json['kind'] as String?;

      if (title == null || title.isEmpty) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "title" field.',
        );
      }
      if (description == null) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "description" field.',
        );
      }
      if (kind == null || kind.isEmpty) {
        return InternalToolResult.error(
          'Ticket at index $i missing required "kind" field.',
        );
      }

      try {
        proposals.add(TicketProposal.fromJson(json));
      } catch (e) {
        return InternalToolResult.error(
          'Failed to parse ticket at index $i: $e',
        );
      }
    }

    // Listen for the next bulk review completion event
    final resultFuture = proposalState.onBulkReviewComplete.first.then((result) {
      final total = result.approvedCount + result.rejectedCount;
      final String resultText;
      if (result.approvedCount == 0) {
        resultText =
            'All $total ticket proposals were rejected by the user.';
      } else if (result.rejectedCount == 0) {
        resultText =
            'All ${result.approvedCount} ticket proposals were approved '
            'and created.';
      } else {
        resultText =
            '${result.approvedCount} of $total ticket proposals were approved '
            'and created. ${result.rejectedCount} were rejected.';
      }
      return InternalToolResult.text(resultText);
    });

    // Stage proposals
    proposalState.proposeBulk(
      proposals,
      sourceChatId: 'mcp-tool',
      sourceChatName: 'Agent',
    );

    developer.log(
      'create_ticket: staged ${proposals.length} proposals for bulk review',
      name: 'InternalToolsService',
    );

    return resultFuture;
  }

  // ===========================================================================
  // Git tools
  // ===========================================================================

  GitService? _gitService;

  /// Register git tools (commit_context, commit, log, diff) with the given
  /// git service.
  void registerGitTools(GitService gitService) {
    _gitService = gitService;
    _registry.register(_gitCommitContextTool());
    _registry.register(_gitCommitTool());
    _registry.register(_gitLogTool());
    _registry.register(_gitDiffTool());
  }

  /// Unregister git tools.
  void unregisterGitTools() {
    _registry.unregister('git_commit_context');
    _registry.unregister('git_commit');
    _registry.unregister('git_log');
    _registry.unregister('git_diff');
    _gitService = null;
  }

  // ---------------------------------------------------------------------------
  // git_commit_context
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitCommitContextTool() {
    return InternalToolDefinition(
      name: 'git_commit_context',
      description:
          'Returns git context needed for crafting a commit: '
          'current branch, file status grouped by type, diff stat, '
          'and recent commit messages. Use before making a commit.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitCommitContext,
    );
  }

  Future<InternalToolResult> _handleGitCommitContext(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    try {
      final results = await Future.wait([
        gitService.getCurrentBranch(path),
        gitService.getChangedFiles(path),
        gitService.getDiffStat(path),
        gitService.getRecentCommits(path, count: 5),
      ]);

      final branch = results[0] as String?;
      final changedFiles = results[1] as List<GitFileChange>;
      final diffStat = results[2] as String;
      final recentCommits =
          results[3] as List<({String sha, String message})>;

      // Group files by status
      final modified = <String>[];
      final untracked = <String>[];
      final deleted = <String>[];
      final staged = <String>[];

      for (final file in changedFiles) {
        if (file.status == GitFileStatus.untracked) {
          untracked.add(file.path);
        } else if (file.isStaged) {
          staged.add(file.path);
        } else if (file.status == GitFileStatus.deleted) {
          deleted.add(file.path);
        } else {
          modified.add(file.path);
        }
      }

      final result = jsonEncode({
        'branch': branch,
        'status': {
          'modified': modified,
          'untracked': untracked,
          'deleted': deleted,
          'staged': staged,
        },
        'diff_stat': diffStat.trimRight(),
        'recent_commits': recentCommits
            .map((c) => {'sha': c.sha, 'message': c.message})
            .toList(),
      });

      return InternalToolResult.text(result);
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // git_commit
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitCommitTool() {
    return InternalToolDefinition(
      name: 'git_commit',
      description:
          'Stages specific files and creates a git commit. '
          'Files must be listed explicitly — no wildcards or "." allowed. '
          'Does not support amending.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'files': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'File paths (relative to path) to stage. '
                'No "." or "*" wildcards.',
          },
          'message': {
            'type': 'string',
            'description': 'The commit message',
          },
          'co_author': {
            'type': 'string',
            'description':
                'Optional Co-Authored-By value '
                '(e.g. "Name <email>"). Appended as a trailer.',
          },
        },
        'required': ['path', 'files', 'message'],
      },
      handler: _handleGitCommit,
    );
  }

  Future<InternalToolResult> _handleGitCommit(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    // Validate files
    final filesInput = input['files'];
    if (filesInput == null || filesInput is! List || filesInput.isEmpty) {
      return InternalToolResult.error(
        'Missing or invalid "files" field. '
        'Expected a non-empty array of file paths.',
      );
    }

    final files = <String>[];
    for (var i = 0; i < filesInput.length; i++) {
      final file = filesInput[i];
      if (file is! String || file.isEmpty) {
        return InternalToolResult.error(
          'File at index $i is not a valid string.',
        );
      }
      if (file == '.' || file.contains('*')) {
        return InternalToolResult.error(
          'Wildcards and "." are not allowed. '
          'Specify each file explicitly. Got: "$file"',
        );
      }
      files.add(file);
    }

    // Validate message
    final message = input['message'] as String?;
    if (message == null || message.isEmpty) {
      return InternalToolResult.error(
        'Missing or empty "message" field.',
      );
    }

    // Build full message with optional co-author trailer
    final coAuthor = input['co_author'] as String?;
    final fullMessage = StringBuffer(message);
    if (coAuthor != null && coAuthor.isNotEmpty) {
      fullMessage.write('\n\nCo-Authored-By: $coAuthor');
    }

    try {
      await gitService.stageFiles(path, files);
      await gitService.commit(path, fullMessage.toString());

      // Get the short SHA of the new commit
      final sha = await gitService.getHeadShortSha(path);

      return InternalToolResult.text(jsonEncode({
        'success': true,
        'sha': sha,
        'message': message,
        'files_committed': files,
      }));
    } on GitException catch (e) {
      // Best-effort reset of the index on failure
      try {
        await gitService.resetIndex(path);
      } catch (_) {}

      return InternalToolResult.text(jsonEncode({
        'success': false,
        'error': e.message,
      }));
    }
  }

  // ---------------------------------------------------------------------------
  // git_log
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitLogTool() {
    return InternalToolDefinition(
      name: 'git_log',
      description:
          'Returns the full git log (messages, authors, dates) '
          'for recent commits.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'count': {
            'type': 'integer',
            'description': 'Number of commits to show (default: 5, max: 50)',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitLog,
    );
  }

  Future<InternalToolResult> _handleGitLog(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    var count = (input['count'] as num?)?.toInt() ?? 5;
    if (count < 1) count = 1;
    if (count > 50) count = 50;

    try {
      final log = await gitService.getLog(path, count: count);
      if (log.isEmpty) {
        return InternalToolResult.text('(no commits)');
      }
      return InternalToolResult.text(log.trimRight());
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // git_diff
  // ---------------------------------------------------------------------------

  InternalToolDefinition _gitDiffTool() {
    return InternalToolDefinition(
      name: 'git_diff',
      description:
          'Returns the git diff output for the working directory. '
          'Shows unstaged changes by default, or staged changes '
          'with the staged option.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                'Absolute path to the git repository working directory',
          },
          'staged': {
            'type': 'boolean',
            'description':
                'If true, show staged changes (--cached). Default: false',
          },
          'files': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional list of file paths to limit the diff to',
          },
        },
        'required': ['path'],
      },
      handler: _handleGitDiff,
    );
  }

  Future<InternalToolResult> _handleGitDiff(
    Map<String, dynamic> input,
  ) async {
    final gitService = _gitService;
    if (gitService == null) {
      return InternalToolResult.error('Git service not available');
    }

    final path = _validatePath(input);
    if (path == null) {
      return InternalToolResult.error(
        'Missing or empty "path" field. Must be an absolute path.',
      );
    }

    final staged = input['staged'] as bool? ?? false;

    List<String>? files;
    final filesInput = input['files'];
    if (filesInput is List && filesInput.isNotEmpty) {
      files = filesInput.cast<String>();
    }

    try {
      final diff = await gitService.getDiff(
        path,
        staged: staged,
        files: files,
      );
      if (diff.isEmpty) {
        return InternalToolResult.text('(no changes)');
      }
      return InternalToolResult.text(diff.trimRight());
    } on GitException catch (e) {
      return InternalToolResult.error('Git error: ${e.message}');
    }
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Validates and extracts the path from tool input.
  /// Returns null if path is missing, empty, or not absolute.
  String? _validatePath(Map<String, dynamic> input) {
    final path = input['path'] as String?;
    if (path == null || path.isEmpty || !path.startsWith('/')) {
      return null;
    }
    return path;
  }
}
