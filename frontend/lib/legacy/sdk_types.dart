/// Legacy SDK types for backwards compatibility.
///
/// These types were previously provided by the dart_sdk package (claude_sdk).
/// They are kept here for backwards compatibility with deprecated code paths
/// that still use the legacy SDK types.
///
/// For new code, use the ACP-based types from the acp_dart package and
/// the custom ACP wrappers in `lib/acp/`.
library;

export 'types/callbacks.dart';
export 'types/content_blocks.dart';
export 'types/errors.dart';
export 'types/permission_suggestion.dart';
export 'types/sdk_messages.dart';
export 'types/session_options.dart';
export 'types/usage.dart';
export 'types/single_request.dart';
export 'types/session.dart';
