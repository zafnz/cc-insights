import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ticket.dart';
import 'ticket_board_state.dart';

/// Result emitted when a bulk review completes.
typedef BulkReviewResult = ({int approvedCount, int rejectedCount});

/// A ticket proposal submitted by an agent for bulk review.
///
/// Contains the fields needed to create a ticket. Dependency indices refer to
/// other proposals in the same batch (0-based).
@immutable
class TicketProposal {
  /// Short title describing the ticket.
  final String title;

  /// Markdown body content.
  final String body;

  /// Free-form tags for categorization.
  final Set<String> tags;

  /// Indices of other proposals in the same batch that this ticket depends on.
  final List<int> dependsOnIndices;

  /// Creates a [TicketProposal].
  const TicketProposal({
    required this.title,
    this.body = '',
    this.tags = const {},
    this.dependsOnIndices = const [],
  });

  /// Deserializes a [TicketProposal] from a JSON map.
  ///
  /// Accepts both `body` and `description` keys for backwards compatibility
  /// with the MCP tool schema.
  factory TicketProposal.fromJson(Map<String, dynamic> json) {
    final tagsList = json['tags'] as List<dynamic>? ?? [];
    final depsList = json['dependsOnIndices'] as List<dynamic>? ?? [];

    return TicketProposal(
      title: json['title'] as String? ?? '',
      body: (json['body'] as String?) ??
          (json['description'] as String?) ??
          '',
      tags: Set<String>.from(tagsList.map((e) => e.toString())),
      dependsOnIndices: depsList.map((e) => e as int).toList(),
    );
  }
}

/// State management for the bulk proposal review workflow.
///
/// Manages the lifecycle of bulk ticket proposals: receiving them from an
/// agent, allowing user review and editing, and approving/rejecting them.
/// Depends on [TicketRepository] for actual ticket CRUD operations.
class BulkProposalState extends ChangeNotifier {
  final TicketRepository _repo;

  /// The chat ID that proposed the current bulk tickets, if any.
  String? _proposalSourceChatId;

  /// The chat name that proposed the current bulk tickets, if any.
  String? _proposalSourceChatName;

  /// Which proposed tickets are checked for approval.
  Set<int> _proposalCheckedIds = {};

  /// Which proposed ticket is being inline-edited, if any.
  int? _proposalEditingId;

  /// IDs of tickets created by the current proposal batch.
  List<int> _proposalTicketIds = [];

  final StreamController<BulkReviewResult> _bulkReviewCompleteController =
      StreamController<BulkReviewResult>.broadcast(sync: true);

  /// Creates a [BulkProposalState] that depends on the given repository.
  BulkProposalState(this._repo);

  /// Stream that emits when a bulk review completes (approved or rejected).
  ///
  /// Used by [InternalToolsService] to send the tool result back to the agent.
  Stream<BulkReviewResult> get onBulkReviewComplete =>
      _bulkReviewCompleteController.stream;

  /// The chat name that proposed the current bulk tickets.
  String get proposalSourceChatName => _proposalSourceChatName ?? '';

  /// The chat ID that proposed the current bulk tickets.
  String? get proposalSourceChatId => _proposalSourceChatId;

  /// All tickets from the current proposal batch.
  List<TicketData> get proposedTickets {
    return _repo.tickets
        .where((t) => _proposalTicketIds.contains(t.id))
        .toList();
  }

  /// Which proposed tickets are checked for approval.
  Set<int> get proposalCheckedIds => Set.unmodifiable(_proposalCheckedIds);

  /// Which proposed ticket is being inline-edited, if any.
  int? get proposalEditingId => _proposalEditingId;

  /// Whether there is an active proposal workflow in progress.
  bool get hasActiveProposal => _proposalTicketIds.isNotEmpty;

  /// Creates tickets from a list of proposals.
  ///
  /// Converts [TicketProposal] objects into [TicketData]. Dependency indices
  /// are mapped to the actual IDs of the newly created tickets. Out-of-range
  /// indices are silently dropped.
  ///
  /// All newly created tickets are auto-checked for approval.
  List<TicketData> proposeBulk(
    List<TicketProposal> proposals, {
    required String sourceChatId,
    required String sourceChatName,
  }) {
    _proposalSourceChatId = sourceChatId;
    _proposalSourceChatName = sourceChatName;
    _proposalTicketIds = [];
    _proposalCheckedIds = {};
    _proposalEditingId = null;

    final createdTickets = <TicketData>[];

    // First pass: create all tickets without dependencies
    for (final proposal in proposals) {
      final ticket = _repo.createTicket(
        title: proposal.title,
        body: proposal.body,
        tags: proposal.tags,
      );
      createdTickets.add(ticket);
      _proposalTicketIds.add(ticket.id);
      _proposalCheckedIds.add(ticket.id);
    }

    // Second pass: resolve dependency indices to actual ticket IDs
    for (var i = 0; i < proposals.length; i++) {
      final proposal = proposals[i];
      if (proposal.dependsOnIndices.isEmpty) continue;

      for (final index in proposal.dependsOnIndices) {
        if (index >= 0 && index < createdTickets.length) {
          _repo.addDependency(createdTickets[i].id, createdTickets[index].id);
        }
      }

      // Refresh the local reference
      createdTickets[i] = _repo.getTicket(createdTickets[i].id)!;
    }

    notifyListeners();
    return createdTickets;
  }

  /// Toggles the checked state of a proposed ticket.
  void toggleProposalChecked(int ticketId) {
    if (_proposalCheckedIds.contains(ticketId)) {
      _proposalCheckedIds.remove(ticketId);
    } else {
      _proposalCheckedIds.add(ticketId);
    }
    notifyListeners();
  }

  /// Checks or unchecks all proposed tickets.
  void setProposalAllChecked(bool checked) {
    if (checked) {
      _proposalCheckedIds = Set.from(_proposalTicketIds);
    } else {
      _proposalCheckedIds = {};
    }
    notifyListeners();
  }

  /// Sets the ticket being inline-edited during bulk review.
  void setProposalEditing(int? ticketId) {
    _proposalEditingId = ticketId;
    notifyListeners();
  }

  /// Approves checked proposals and deletes unchecked ones.
  ///
  /// Checked tickets are kept as-is (already open).
  /// Unchecked tickets are deleted.
  ///
  /// Emits a [BulkReviewResult] on [onBulkReviewComplete] with the counts of
  /// approved and rejected tickets.
  void approveBulk() {
    final approvedCount = _proposalCheckedIds.length;
    final rejectedCount = _proposalTicketIds.length - approvedCount;

    for (final ticketId in _proposalTicketIds) {
      if (!_proposalCheckedIds.contains(ticketId)) {
        _repo.deleteTicket(ticketId);
      }
    }

    _clearProposalState();
    notifyListeners();

    _bulkReviewCompleteController.add((
      approvedCount: approvedCount,
      rejectedCount: rejectedCount,
    ));
  }

  /// Rejects all proposed tickets by deleting them.
  ///
  /// All tickets from the current proposal are deleted.
  ///
  /// Emits a [BulkReviewResult] on [onBulkReviewComplete] with all tickets
  /// counted as rejected.
  void rejectAll() {
    final rejectedCount = _proposalTicketIds.length;

    for (final id in _proposalTicketIds) {
      _repo.deleteTicket(id);
    }

    _clearProposalState();
    notifyListeners();

    _bulkReviewCompleteController.add((
      approvedCount: 0,
      rejectedCount: rejectedCount,
    ));
  }

  /// Clears all proposal state fields.
  void _clearProposalState() {
    _proposalTicketIds = [];
    _proposalCheckedIds = {};
    _proposalEditingId = null;
    _proposalSourceChatId = null;
    _proposalSourceChatName = null;
  }

  @override
  void dispose() {
    _bulkReviewCompleteController.close();
    super.dispose();
  }
}
