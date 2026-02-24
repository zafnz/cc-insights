import 'dart:convert';
import 'dart:io';

import 'package:cc_insights_v2/services/persistence_service.dart';
import 'package:cc_insights_v2/services/ticket_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late TicketStorageService service;
  const projectId = 'test-proj';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ticket_storage_test_');
    PersistenceService.setBaseDir(tempDir.path);
    service = TicketStorageService();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('TicketStorageService', () {
    group('loadTickets', () {
      test('returns null when file does not exist', () async {
        final result = await service.loadTickets(projectId);
        expect(result, isNull);
      });

      test('returns null for empty file', () async {
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString('   ');

        final result = await service.loadTickets(projectId);
        expect(result, isNull);
      });

      test('returns parsed JSON for valid file', () async {
        final data = {'schemaVersion': 2, 'tickets': [], 'nextId': 1};
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(data));

        final result = await service.loadTickets(projectId);
        expect(result, equals(data));
      });

      test('returns null for invalid JSON', () async {
        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        await file.parent.create(recursive: true);
        await file.writeAsString('not valid json {{{');

        final result = await service.loadTickets(projectId);
        expect(result, isNull);
      });
    });

    group('saveTickets', () {
      test('creates project directory and writes file', () async {
        final data = {'tickets': [], 'version': 1};
        await service.saveTickets(projectId, data);

        final path = TicketStorageService.ticketsPath(projectId);
        final file = File(path);
        expect(file.existsSync(), isTrue);

        final content = await file.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded, equals(data));
      });

      test('writes pretty-printed JSON with 2-space indent', () async {
        final data = {'key': 'value', 'nested': {'a': 1}};
        await service.saveTickets(projectId, data);

        final path = TicketStorageService.ticketsPath(projectId);
        final content = await File(path).readAsString();
        const expected = '{\n  "key": "value",\n  "nested": {\n    "a": 1\n  }\n}';
        expect(content, equals(expected));
      });

      test('overwrites existing file atomically', () async {
        final data1 = {'version': 1};
        final data2 = {'version': 2};

        await service.saveTickets(projectId, data1);
        await service.saveTickets(projectId, data2);

        final path = TicketStorageService.ticketsPath(projectId);
        final content = await File(path).readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        expect(decoded['version'], equals(2));
      });

      test('does not leave temp files on success', () async {
        final data = {'tickets': []};
        await service.saveTickets(projectId, data);

        final dir = Directory(PersistenceService.projectDir(projectId));
        final files = dir.listSync();
        final tempFiles = files.where(
          (f) => f.path.contains('.tmp.'),
        );
        expect(tempFiles, isEmpty);
      });

      test('round-trips through loadTickets', () async {
        final data = {
          'schemaVersion': 2,
          'tickets': [
            {
              'id': 1,
              'title': 'Test ticket',
              'body': 'Some body',
              'author': 'zaf',
              'isOpen': true,
              'tags': ['feature'],
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-01T00:00:00.000Z',
            },
          ],
          'nextId': 2,
        };

        await service.saveTickets(projectId, data);
        final loaded = await service.loadTickets(projectId);
        expect(loaded, equals(data));
      });
    });
  });
}
