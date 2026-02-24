import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/services/author_service.dart';
import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/ticket_migration_service.dart';
import 'package:cc_insights_v2/services/ticket_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sample V1 ticket board JSON for testing.
Map<String, dynamic> _sampleV1Data() => {
      'tickets': [
        {
          'id': 1,
          'title': 'Implement auth',
          'description': 'Add login flow with JWT',
          'status': 'open',
          'kind': 'feature',
          'priority': 'high',
          'effort': 'large',
          'category': 'Backend',
          'dependsOn': [2],
          'comments': [
            {
              'text': 'Started working on this',
              'author': 'zaf',
              'createdAt': '2026-01-15T10:00:00.000Z',
            },
            {
              'text': 'Agent picked this up',
              'author': 'agent auth-refactor',
              'createdAt': '2026-01-15T11:00:00.000Z',
            },
          ],
          'createdAt': '2026-01-10T08:00:00.000Z',
          'updatedAt': '2026-01-15T11:00:00.000Z',
        },
        {
          'id': 2,
          'title': 'Setup database',
          'description': 'Configure PostgreSQL',
          'status': 'completed',
          'kind': 'chore',
          'priority': 'critical',
          'effort': 'small',
          'category': 'Infrastructure',
          'dependsOn': <int>[],
          'comments': <dynamic>[],
          'createdAt': '2026-01-05T08:00:00.000Z',
          'updatedAt': '2026-01-08T12:00:00.000Z',
        },
        {
          'id': 3,
          'title': 'Write docs',
          'description': 'API documentation',
          'status': 'cancelled',
          'kind': 'docs',
          'priority': 'low',
          'effort': 'medium',
          'category': '',
          'dependsOn': <int>[],
          'comments': <dynamic>[],
          'createdAt': '2026-01-12T08:00:00.000Z',
          'updatedAt': '2026-01-13T09:00:00.000Z',
        },
        {
          'id': 4,
          'title': 'Fix login bug',
          'description': '',
          'status': 'in_progress',
          'kind': 'bugfix',
          'priority': 'medium',
          'effort': 'small',
          'dependsOn': <int>[],
          'comments': <dynamic>[],
          'createdAt': '2026-01-20T08:00:00.000Z',
          'updatedAt': '2026-01-20T10:00:00.000Z',
        },
        {
          'id': 5,
          'title': 'Split ticket',
          'description': 'Was too big',
          'status': 'split',
          'kind': 'research',
          'priority': 'high',
          'effort': 'large',
          'dependsOn': <int>[],
          'comments': <dynamic>[],
          'createdAt': '2026-01-22T08:00:00.000Z',
          'updatedAt': '2026-01-22T12:00:00.000Z',
        },
      ],
      'nextId': 6,
    };

void main() {
  setUp(() {
    AuthorService.setForTesting('testuser');
  });

  tearDown(() {
    AuthorService.resetForTesting();
  });

  group('TicketMigrationService', () {
    group('needsMigration', () {
      test('returns true when schemaVersion is missing', () {
        expect(
          TicketMigrationService.needsMigration({'tickets': []}),
          isTrue,
        );
      });

      test('returns true when schemaVersion < 2', () {
        expect(
          TicketMigrationService.needsMigration(
            {'schemaVersion': 1, 'tickets': []},
          ),
          isTrue,
        );
      });

      test('returns false when schemaVersion is 2', () {
        expect(
          TicketMigrationService.needsMigration(
            {'schemaVersion': 2, 'tickets': []},
          ),
          isFalse,
        );
      });

      test('returns false when schemaVersion > 2', () {
        expect(
          TicketMigrationService.needsMigration(
            {'schemaVersion': 3, 'tickets': []},
          ),
          isFalse,
        );
      });
    });

    group('migrate', () {
      test('sets schemaVersion to 2', () {
        final result = TicketMigrationService.migrate({'tickets': []});
        expect(result['schemaVersion'], equals(2));
      });

      test('preserves nextId', () {
        final result = TicketMigrationService.migrate(
          {'tickets': [], 'nextId': 42},
        );
        expect(result['nextId'], equals(42));
      });

      test('builds tag registry from all tickets', () {
        final result = TicketMigrationService.migrate(_sampleV1Data());
        final registry = result['tagRegistry'] as List<dynamic>;
        final tagNames =
            registry.map((r) => (r as Map<String, dynamic>)['name']).toSet();

        // From ticket 1: feature, high-priority, large, backend
        // From ticket 2: chore, critical, small, infrastructure
        // From ticket 3: docs, low-priority
        // From ticket 4: bugfix, small
        // From ticket 5: research, high-priority, large
        expect(tagNames, contains('feature'));
        expect(tagNames, contains('high-priority'));
        expect(tagNames, contains('large'));
        expect(tagNames, contains('backend'));
        expect(tagNames, contains('chore'));
        expect(tagNames, contains('critical'));
        expect(tagNames, contains('small'));
        expect(tagNames, contains('infrastructure'));
        expect(tagNames, contains('docs'));
        expect(tagNames, contains('low-priority'));
        expect(tagNames, contains('bugfix'));
        expect(tagNames, contains('research'));
      });

      test('migrates full V1 data end-to-end', () {
        final result = TicketMigrationService.migrate(_sampleV1Data());
        final tickets = result['tickets'] as List<dynamic>;
        expect(tickets, hasLength(5));
        expect(result['schemaVersion'], equals(2));
        expect(result['nextId'], equals(6));
        expect(result['tagRegistry'], isNotNull);
      });
    });

    group('migrateTicket', () {
      group('status → isOpen + closedAt', () {
        test('open status maps to isOpen: true', () {
          final result = TicketMigrationService.migrateTicket(
            {'status': 'open', 'createdAt': '2026-01-01T00:00:00.000Z'},
            author: 'testuser',
          );
          expect(result['isOpen'], isTrue);
          expect(result['closedAt'], isNull);
          expect(result.containsKey('status'), isFalse);
        });

        test('in_progress status maps to isOpen: true', () {
          final result = TicketMigrationService.migrateTicket(
            {'status': 'in_progress'},
            author: 'testuser',
          );
          expect(result['isOpen'], isTrue);
          expect(result['closedAt'], isNull);
        });

        test('completed status maps to isOpen: false with closedAt', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'status': 'completed',
              'updatedAt': '2026-01-10T12:00:00.000Z',
            },
            author: 'testuser',
          );
          expect(result['isOpen'], isFalse);
          expect(result['closedAt'], equals('2026-01-10T12:00:00.000Z'));
        });

        test('cancelled status maps to isOpen: false with closedAt', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'status': 'cancelled',
              'updatedAt': '2026-01-10T12:00:00.000Z',
            },
            author: 'testuser',
          );
          expect(result['isOpen'], isFalse);
          expect(result['closedAt'], equals('2026-01-10T12:00:00.000Z'));
        });

        test('split status maps to isOpen: false with closedAt', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'status': 'split',
              'updatedAt': '2026-01-10T12:00:00.000Z',
            },
            author: 'testuser',
          );
          expect(result['isOpen'], isFalse);
          expect(result['closedAt'], equals('2026-01-10T12:00:00.000Z'));
        });

        test('closedAt falls back to createdAt when updatedAt is missing', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'status': 'completed',
              'createdAt': '2026-01-05T08:00:00.000Z',
            },
            author: 'testuser',
          );
          expect(result['closedAt'], equals('2026-01-05T08:00:00.000Z'));
        });

        test('preserves existing isOpen when no status field', () {
          final result = TicketMigrationService.migrateTicket(
            {'isOpen': false, 'closedAt': '2026-01-10T12:00:00.000Z'},
            author: 'testuser',
          );
          expect(result['isOpen'], isFalse);
          expect(result['closedAt'], equals('2026-01-10T12:00:00.000Z'));
        });
      });

      group('enum fields → tags', () {
        test('kind becomes a tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'kind': 'feature'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('feature'));
          expect(result.containsKey('kind'), isFalse);
        });

        test('priority high becomes high-priority tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'priority': 'high'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('high-priority'));
          expect(result.containsKey('priority'), isFalse);
        });

        test('priority critical becomes critical tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'priority': 'critical'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('critical'));
        });

        test('priority low becomes low-priority tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'priority': 'low'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('low-priority'));
        });

        test('priority medium produces no tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'priority': 'medium'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, isNot(contains('medium')));
          expect(tags, isNot(contains('medium-priority')));
        });

        test('effort small becomes small tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'effort': 'small'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('small'));
          expect(result.containsKey('effort'), isFalse);
        });

        test('effort large becomes large tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'effort': 'large'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('large'));
        });

        test('effort medium produces no tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'effort': 'medium'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, isNot(contains('medium')));
        });

        test('category becomes lowercase tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'category': 'Backend'},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, contains('backend'));
          expect(result.containsKey('category'), isFalse);
        });

        test('empty category produces no tag', () {
          final result = TicketMigrationService.migrateTicket(
            {'category': ''},
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>();
          expect(tags, isEmpty);
        });

        test('all enum fields combine into tags', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'kind': 'feature',
              'priority': 'critical',
              'effort': 'large',
              'category': 'UI',
            },
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>().toSet();
          expect(tags, equals({'feature', 'critical', 'large', 'ui'}));
        });

        test('preserves existing tags alongside migrated ones', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'kind': 'feature',
              'tags': ['custom-tag'],
            },
            author: 'testuser',
          );
          final tags = (result['tags'] as List<dynamic>).cast<String>().toSet();
          expect(tags, contains('custom-tag'));
          expect(tags, contains('feature'));
        });
      });

      group('description → body', () {
        test('renames description to body', () {
          final result = TicketMigrationService.migrateTicket(
            {'description': 'Some description text'},
            author: 'testuser',
          );
          expect(result['body'], equals('Some description text'));
          expect(result.containsKey('description'), isFalse);
        });

        test('does not overwrite existing body', () {
          final result = TicketMigrationService.migrateTicket(
            {'description': 'old', 'body': 'already set'},
            author: 'testuser',
          );
          expect(result['body'], equals('already set'));
          // description is kept since body was already present
          expect(result['description'], equals('old'));
        });
      });

      group('author', () {
        test('sets author when missing', () {
          final result = TicketMigrationService.migrateTicket(
            {},
            author: 'testuser',
          );
          expect(result['author'], equals('testuser'));
        });

        test('sets author when empty', () {
          final result = TicketMigrationService.migrateTicket(
            {'author': ''},
            author: 'testuser',
          );
          expect(result['author'], equals('testuser'));
        });

        test('preserves existing author', () {
          final result = TicketMigrationService.migrateTicket(
            {'author': 'existinguser'},
            author: 'testuser',
          );
          expect(result['author'], equals('existinguser'));
        });
      });

      group('comments', () {
        test('adds id to comments without one', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'text': 'Hello', 'author': 'zaf'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['id'], isA<String>());
          expect((comment['id'] as String).length, greaterThan(0));
        });

        test('preserves existing comment id', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'id': 'existing-id', 'text': 'Hello', 'author': 'zaf'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['id'], equals('existing-id'));
        });

        test('adds authorType user for regular author', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'text': 'Hello', 'author': 'zaf'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['authorType'], equals('user'));
        });

        test('adds authorType agent for agent author', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'text': 'Done', 'author': 'agent auth-refactor'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['authorType'], equals('agent'));
        });

        test('preserves existing authorType', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'text': 'Hello', 'author': 'bot', 'authorType': 'agent'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['authorType'], equals('agent'));
        });

        test('adds empty images list', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {'text': 'Hello', 'author': 'zaf'},
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['images'], equals([]));
        });

        test('preserves existing images', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'comments': [
                {
                  'text': 'Hello',
                  'author': 'zaf',
                  'images': [
                    {'id': 'img-1'},
                  ],
                },
              ],
            },
            author: 'testuser',
          );
          final comments = result['comments'] as List<dynamic>;
          final comment = comments[0] as Map<String, dynamic>;
          expect(comment['images'], hasLength(1));
        });

        test('handles null comments', () {
          final result = TicketMigrationService.migrateTicket(
            {},
            author: 'testuser',
          );
          expect(result.containsKey('comments'), isFalse);
        });

        test('handles empty comments', () {
          final result = TicketMigrationService.migrateTicket(
            {'comments': <dynamic>[]},
            author: 'testuser',
          );
          expect(result['comments'], isEmpty);
        });
      });

      group('new V2 fields', () {
        test('adds empty activityLog', () {
          final result = TicketMigrationService.migrateTicket(
            {},
            author: 'testuser',
          );
          expect(result['activityLog'], equals([]));
        });

        test('adds empty bodyImages', () {
          final result = TicketMigrationService.migrateTicket(
            {},
            author: 'testuser',
          );
          expect(result['bodyImages'], equals([]));
        });

        test('preserves existing activityLog', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'activityLog': [
                {'type': 'closed'},
              ],
            },
            author: 'testuser',
          );
          expect(result['activityLog'], hasLength(1));
        });
      });

      group('preserves existing V2 fields', () {
        test('preserves id, title, dependsOn, timestamps', () {
          final result = TicketMigrationService.migrateTicket(
            {
              'id': 42,
              'title': 'My ticket',
              'dependsOn': [1, 2],
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-02T00:00:00.000Z',
              'sourceConversationId': 'conv-abc',
            },
            author: 'testuser',
          );
          expect(result['id'], equals(42));
          expect(result['title'], equals('My ticket'));
          expect(result['dependsOn'], equals([1, 2]));
          expect(result['createdAt'], equals('2026-01-01T00:00:00.000Z'));
          expect(result['updatedAt'], equals('2026-01-02T00:00:00.000Z'));
          expect(result['sourceConversationId'], equals('conv-abc'));
        });
      });
    });

    group('integration with TicketStorageService', () {
      late Directory tempDir;
      late TicketStorageService service;
      const projectId = 'migration-test-proj';

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('ticket_migration_');
        PersistenceService.setBaseDir(tempDir.path);
        service = TicketStorageService();
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('migrates V1 data on load and persists V2', () async {
        // Write V1 data to disk
        final v1Data = _sampleV1Data();
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(v1Data));

        // Load should trigger migration
        final loaded = await service.loadTickets(projectId);
        expect(loaded, isNotNull);
        expect(loaded!['schemaVersion'], equals(2));

        // Verify tickets were migrated
        final tickets = loaded['tickets'] as List<dynamic>;
        expect(tickets, hasLength(5));

        final ticket1 = tickets[0] as Map<String, dynamic>;
        expect(ticket1['isOpen'], isTrue);
        expect(ticket1['body'], equals('Add login flow with JWT'));
        expect(ticket1.containsKey('description'), isFalse);
        expect(ticket1.containsKey('status'), isFalse);

        final ticket2 = tickets[1] as Map<String, dynamic>;
        expect(ticket2['isOpen'], isFalse);
        expect(ticket2['closedAt'], isNotNull);

        // Verify tag registry was built
        expect(loaded['tagRegistry'], isNotNull);

        // Verify persisted to disk
        final persisted = await file.readAsString();
        final decoded = jsonDecode(persisted) as Map<String, dynamic>;
        expect(decoded['schemaVersion'], equals(2));
      });

      test('does not re-migrate V2 data', () async {
        // Write V2 data to disk
        final v2Data = {
          'schemaVersion': 2,
          'tickets': [
            {
              'id': 1,
              'title': 'Already V2',
              'body': 'V2 body',
              'author': 'zaf',
              'isOpen': true,
              'tags': ['feature'],
            },
          ],
          'nextId': 2,
        };
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(v2Data));

        final loaded = await service.loadTickets(projectId);
        expect(loaded, isNotNull);
        expect(loaded!['schemaVersion'], equals(2));

        // Verify data was NOT modified
        final tickets = loaded['tickets'] as List<dynamic>;
        final ticket = tickets[0] as Map<String, dynamic>;
        expect(ticket['title'], equals('Already V2'));
        expect(ticket['body'], equals('V2 body'));
        // No tagRegistry was added since migration didn't run
        expect(loaded.containsKey('tagRegistry'), isFalse);
      });

      test('uses AuthorService.currentUser as default author', () async {
        AuthorService.setForTesting('migrator');

        final v1Data = {
          'tickets': [
            {
              'id': 1,
              'title': 'No author ticket',
              'description': 'Test',
              'status': 'open',
            },
          ],
          'nextId': 2,
        };
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(v1Data));

        final loaded = await service.loadTickets(projectId);
        final tickets = loaded!['tickets'] as List<dynamic>;
        final ticket = tickets[0] as Map<String, dynamic>;
        expect(ticket['author'], equals('migrator'));
      });
    });
  });
}
