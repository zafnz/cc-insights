import 'package:cc_insights_v2/services/ask_ai_service.dart';
import 'package:claude_sdk/claude_sdk.dart';

/// Fake implementation of [AskAiService] for testing.
class FakeAskAiService implements AskAiService {
  /// The result to return from [ask].
  SingleRequestResult? nextResult;

  /// If set, [ask] will throw this exception.
  Exception? askError;

  /// Tracks calls to [ask].
  final List<({
    String prompt,
    String workingDirectory,
    String? model,
    List<String>? allowedTools,
    int? maxTurns,
    int? timeoutSeconds,
  })> askCalls = [];

  @override
  final AskAiUsageStats usageStats = AskAiUsageStats();

  @override
  Future<SingleRequestResult?> ask({
    required String prompt,
    required String workingDirectory,
    String model = 'haiku',
    List<String>? allowedTools,
    int? maxTurns,
    int timeoutSeconds = 60,
  }) async {
    askCalls.add((
      prompt: prompt,
      workingDirectory: workingDirectory,
      model: model,
      allowedTools: allowedTools,
      maxTurns: maxTurns,
      timeoutSeconds: timeoutSeconds,
    ));

    if (askError != null) {
      throw askError!;
    }

    return nextResult;
  }

  /// Resets all state.
  void reset() {
    nextResult = null;
    askError = null;
    askCalls.clear();
    usageStats.reset();
  }
}
