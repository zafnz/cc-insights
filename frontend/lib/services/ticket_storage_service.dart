import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'persistence_service.dart';

/// Service for persisting and retrieving ticket board data.
///
/// Manages the `tickets.json` file for each project, which stores
/// the ticket board state (tickets, dependencies, metadata).
class TicketStorageService {
  /// Path to a project's tickets file (JSON format).
  static String ticketsPath(String projectId) =>
      '${PersistenceService.projectDir(projectId)}/tickets.json';

  /// Loads tickets from disk.
  ///
  /// Returns null if the file doesn't exist or is invalid.
  Future<Map<String, dynamic>?> loadTickets(String projectId) async {
    final path = ticketsPath(projectId);
    final file = File(path);

    if (!await file.exists()) {
      developer.log(
        'Tickets file not found: $projectId',
        name: 'TicketStorageService',
      );
      return null;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return null;
      }

      final json = jsonDecode(content) as Map<String, dynamic>;
      return json;
    } catch (e) {
      developer.log(
        'Failed to parse tickets for $projectId: $e',
        name: 'TicketStorageService',
        error: e,
      );
      return null;
    }
  }

  /// Saves tickets to disk.
  ///
  /// Creates the project directory if it doesn't exist.
  Future<void> saveTickets(String projectId, Map<String, dynamic> data) async {
    final path = ticketsPath(projectId);

    try {
      // Ensure project directory exists
      final dir = Directory(PersistenceService.projectDir(projectId));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final encoder = const JsonEncoder.withIndent('  ');
      final content = encoder.convert(data);
      await File(path).writeAsString(content);

      developer.log('Saved tickets: $projectId', name: 'TicketStorageService');
    } catch (e) {
      developer.log(
        'Failed to save tickets $projectId: $e',
        name: 'TicketStorageService',
        error: e,
      );
      rethrow;
    }
  }
}
