import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import 'author_service.dart';

const _uuid = Uuid();

/// Current schema version for the ticket board data.
const int currentTicketSchemaVersion = 2;

/// Migrates V1 ticket board JSON to V2 format.
///
/// V1 used typed enums (status, kind, priority, effort, category) and
/// a `description` field. V2 uses an open/closed model with free-form tags,
/// a `body` field, proper comment attribution, and an activity log.
///
/// The migration is pure: it transforms a JSON map and returns a new one.
/// Side effects (reading/writing files) are handled by [TicketStorageService].
class TicketMigrationService {
  /// Returns `true` if the given ticket board JSON needs migration.
  static bool needsMigration(Map<String, dynamic> data) {
    final version = data['schemaVersion'] as int?;
    return version == null || version < currentTicketSchemaVersion;
  }

  /// Migrates a V1 ticket board JSON map to V2 format.
  ///
  /// Returns a new map with:
  /// - Each ticket transformed via [migrateTicket]
  /// - A `tagRegistry` built from all tags found across tickets
  /// - `schemaVersion` set to [currentTicketSchemaVersion]
  ///
  /// The [author] parameter defaults to [AuthorService.currentUser].
  static Map<String, dynamic> migrate(
    Map<String, dynamic> data, {
    String? author,
  }) {
    final resolvedAuthor = author ?? AuthorService.currentUser;
    final ticketsList = data['tickets'] as List<dynamic>? ?? [];

    final allTags = <String>{};
    final migratedTickets = <Map<String, dynamic>>[];

    for (final raw in ticketsList) {
      final ticket = raw as Map<String, dynamic>;
      final migrated = migrateTicket(ticket, author: resolvedAuthor);
      migratedTickets.add(migrated);

      // Collect tags for the registry
      final tags = migrated['tags'] as List<dynamic>? ?? [];
      allTags.addAll(tags.cast<String>());
    }

    // Build tag registry from all discovered tags
    final tagRegistry = allTags.map((t) => {'name': t}).toList();

    final result = <String, dynamic>{
      'schemaVersion': currentTicketSchemaVersion,
      'tickets': migratedTickets,
      'tagRegistry': tagRegistry,
    };

    // Preserve nextId if present
    if (data.containsKey('nextId')) {
      result['nextId'] = data['nextId'];
    }

    developer.log(
      'Migrated ${migratedTickets.length} tickets, '
      '${allTags.length} tags in registry',
      name: 'TicketMigrationService',
    );

    return result;
  }

  /// Migrates a single V1 ticket JSON map to V2 format.
  ///
  /// Transformations:
  /// 1. `status` → `isOpen` + `closedAt`
  /// 2. `kind`, `priority`, `effort`, `category` → `tags`
  /// 3. `description` → `body`
  /// 4. Sets `author` to [author]
  /// 5. Converts comments: adds `id`, `authorType`, `images`
  /// 6. Adds empty `activityLog` and `bodyImages`
  static Map<String, dynamic> migrateTicket(
    Map<String, dynamic> v1, {
    required String author,
  }) {
    final v2 = Map<String, dynamic>.from(v1);

    // 1. Map status → isOpen + closedAt
    _migrateStatus(v2);

    // 2. Map enums → tags
    _migrateToTags(v2);

    // 3. Rename description → body
    if (v2.containsKey('description') && !v2.containsKey('body')) {
      v2['body'] = v2.remove('description');
    }

    // 4. Set author if missing
    if (!v2.containsKey('author') || (v2['author'] as String?)?.isEmpty == true) {
      v2['author'] = author;
    }

    // 5. Convert comments
    _migrateComments(v2, author);

    // 6. Add missing V2 fields
    v2['activityLog'] ??= <dynamic>[];
    v2['bodyImages'] ??= <dynamic>[];

    return v2;
  }

  /// Maps V1 `status` to V2 `isOpen` and `closedAt`.
  ///
  /// Closed statuses: completed, cancelled, split.
  /// All others (open, in_progress, blocked, etc.) map to open.
  static void _migrateStatus(Map<String, dynamic> ticket) {
    final status = ticket.remove('status') as String?;
    if (status == null && ticket.containsKey('isOpen')) {
      // Already V2 format
      return;
    }

    const closedStatuses = {'completed', 'cancelled', 'split'};
    final isClosed = closedStatuses.contains(status);

    ticket['isOpen'] = !isClosed;

    if (isClosed && !ticket.containsKey('closedAt')) {
      // Use updatedAt as closedAt for closed tickets
      ticket['closedAt'] = ticket['updatedAt'] ?? ticket['createdAt'];
    }
  }

  /// Converts V1 enum fields (kind, priority, effort, category) to V2 tags.
  static void _migrateToTags(Map<String, dynamic> ticket) {
    final tags = <String>{};

    // Preserve any existing tags
    final existingTags = ticket['tags'] as List<dynamic>?;
    if (existingTags != null) {
      tags.addAll(existingTags.cast<String>());
    }

    // kind → tag (as-is, lowercase)
    final kind = ticket.remove('kind') as String?;
    if (kind != null && kind.isNotEmpty) {
      tags.add(kind.toLowerCase());
    }

    // priority → tag (high→"high-priority", critical→"critical",
    //                  low→"low-priority"; medium is default, skip)
    final priority = ticket.remove('priority') as String?;
    if (priority != null) {
      switch (priority.toLowerCase()) {
        case 'critical':
          tags.add('critical');
        case 'high':
          tags.add('high-priority');
        case 'low':
          tags.add('low-priority');
        // medium is default → no tag
      }
    }

    // effort → tag (small→"small", large→"large"; medium is default, skip)
    final effort = ticket.remove('effort') as String?;
    if (effort != null) {
      switch (effort.toLowerCase()) {
        case 'small':
          tags.add('small');
        case 'large':
          tags.add('large');
        // medium is default → no tag
      }
    }

    // category → lowercase tag
    final category = ticket.remove('category') as String?;
    if (category != null && category.isNotEmpty) {
      tags.add(category.toLowerCase());
    }

    ticket['tags'] = tags.toList();
  }

  /// Converts V1 comments to V2 format.
  ///
  /// V1 comments may lack `id`, `authorType`, and `images`.
  /// V2 requires all three.
  static void _migrateComments(
    Map<String, dynamic> ticket,
    String defaultAuthor,
  ) {
    final comments = ticket['comments'] as List<dynamic>?;
    if (comments == null || comments.isEmpty) return;

    final migrated = <Map<String, dynamic>>[];
    for (final raw in comments) {
      final comment = Map<String, dynamic>.from(raw as Map<String, dynamic>);

      // Ensure id
      comment['id'] ??= _uuid.v4();

      // Ensure authorType
      if (!comment.containsKey('authorType')) {
        final author = comment['author'] as String? ?? defaultAuthor;
        comment['authorType'] =
            author.startsWith('agent ') ? 'agent' : 'user';
      }

      // Ensure images list
      comment['images'] ??= <dynamic>[];

      migrated.add(comment);
    }

    ticket['comments'] = migrated;
  }
}
