/// ACP (Agent Client Protocol) integration layer for CC-Insights.
///
/// This library provides wrapper classes around the acp_dart package,
/// adapting the callback-based API to a stream-based API suitable for
/// Flutter's Provider pattern.
library;

export 'acp_client_wrapper.dart';
export 'acp_session_wrapper.dart';
export 'cc_insights_acp_client.dart';
export 'pending_permission.dart';
export 'session_update_handler.dart';
export 'handlers/handlers.dart';
