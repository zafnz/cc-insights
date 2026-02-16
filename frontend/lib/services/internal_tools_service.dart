import 'dart:async';
import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart';
import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import '../state/bulk_proposal_state.dart';

/// Service that manages internal MCP tools for CC-Insights.
///
/// Owns the [InternalToolRegistry] and registers application-level tools
/// that agent backends can invoke via the MCP protocol.
class InternalToolsService extends ChangeNotifier {
  final InternalToolRegistry _registry = InternalToolRegistry();

  /// The tool registry to pass to backend sessions.
  InternalToolRegistry get registry => _registry;

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
}
