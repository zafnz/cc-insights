import 'package:flutter_test/flutter_test.dart';
import 'package:acp_dart/acp_dart.dart';

void main() {
  group('acp_dart package', () {
    test('key types are importable and accessible', () {
      // Verify core connection types exist
      expect(ClientSideConnection, isNotNull);

      // Verify request/response types exist
      expect(InitializeRequest, isNotNull);
      expect(InitializeResponse, isNotNull);
      expect(NewSessionRequest, isNotNull);
      expect(PromptRequest, isNotNull);

      // Verify session update types exist
      expect(SessionNotification, isNotNull);

      // Verify content block types exist
      expect(TextContentBlock, isNotNull);

      // Verify capability types exist
      expect(ClientCapabilities, isNotNull);
    });
  });
}
