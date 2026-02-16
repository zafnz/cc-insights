part of 'package:cc_insights_v2/models/chat.dart';

class ChatMetricsState extends ChangeNotifier {
  ChatMetricsState._(this._chat);

  final _ChatCore _chat;

  ContextTracker get contextTracker => _chat._contextTracker;
  UsageInfo get cumulativeUsage => _chat._inTurnOutputTokens > 0
      ? _chat._cumulativeUsage.copyWith(
          outputTokens:
              _chat._cumulativeUsage.outputTokens + _chat._inTurnOutputTokens,
        )
      : _chat._cumulativeUsage;
  List<ModelUsageInfo> get modelUsage => List.unmodifiable(_chat._modelUsage);
  TimingStats get timingStats => _chat._timingStats;

  void addInTurnOutputTokens(int outputTokens) {
    if (outputTokens <= 0) return;
    _chat._inTurnOutputTokens += outputTokens;
    notifyListeners();
  }

  void updateContextFromUsage(Map<String, dynamic> usage) {
    _chat._contextTracker.updateFromUsage(usage);
    notifyListeners();
  }

  void addClaudeWorkingTime(Duration elapsed) {
    _chat._timingStats = _chat._timingStats.addClaudeWorkingTime(elapsed);
    _chat._scheduleMetaSave();
    notifyListeners();
  }

  void updateCumulativeUsage({
    required UsageInfo usage,
    required double totalCostUsd,
    List<ModelUsageInfo>? modelUsage,
    int? contextWindow,
  }) {
    if (modelUsage != null && modelUsage.isNotEmpty) {
      _chat._modelUsage = _mergeModelUsage(_chat._baseModelUsage, modelUsage);

      int totalInput = 0;
      int totalOutput = 0;
      int totalCacheRead = 0;
      int totalCacheCreation = 0;
      double totalCost = 0;

      for (final model in _chat._modelUsage) {
        totalInput += model.inputTokens;
        totalOutput += model.outputTokens;
        totalCacheRead += model.cacheReadTokens;
        totalCacheCreation += model.cacheCreationTokens;
        totalCost += model.costUsd;
      }

      _chat._cumulativeUsage = UsageInfo(
        inputTokens: totalInput,
        outputTokens: totalOutput,
        cacheReadTokens: totalCacheRead,
        cacheCreationTokens: totalCacheCreation,
        costUsd: totalCost,
      );
    }

    _chat._inTurnOutputTokens = 0;

    if (contextWindow != null) {
      _chat._contextTracker.updateMaxTokens(contextWindow);
    }

    _chat._scheduleMetaSave();
    notifyListeners();
  }

  void resetContext() {
    _chat._contextTracker.reset();
    notifyListeners();
  }

  void restoreFromMeta(
    ContextInfo context,
    UsageInfo usage, {
    List<ModelUsageInfo> modelUsage = const [],
    TimingStats timing = const TimingStats.zero(),
  }) {
    _chat._contextTracker.updateFromUsage({
      'input_tokens': context.currentTokens,
      'cache_creation_input_tokens': 0,
      'cache_read_input_tokens': 0,
    });
    _chat._contextTracker.updateMaxTokens(context.maxTokens);
    _chat._contextTracker.updateAutocompactBuffer(
      context.autocompactBufferPercent,
    );

    _chat._cumulativeUsage = usage;
    _chat._modelUsage = List.from(modelUsage);
    _chat._baseModelUsage = List.from(modelUsage);
    _chat._timingStats = timing;
    notifyListeners();
  }

  void recordPermissionRequestTime(String? toolUseId) {
    if (toolUseId == null || toolUseId.isEmpty) return;
    _chat._permissionRequestTimes[toolUseId] = DateTime.now();
  }

  void recordPermissionResponseTime(String? toolUseId) {
    if (toolUseId == null) return;
    final startTime = _chat._permissionRequestTimes.remove(toolUseId);
    if (startTime == null) return;
    final elapsed = DateTime.now().difference(startTime);
    _chat._timingStats = _chat._timingStats.addUserResponseTime(elapsed);
    _chat._scheduleMetaSave();
    notifyListeners();
  }

  List<ModelUsageInfo> _mergeModelUsage(
    List<ModelUsageInfo> base,
    List<ModelUsageInfo> session,
  ) {
    final result = <String, ModelUsageInfo>{};

    for (final model in base) {
      result[model.modelName] = model;
    }

    for (final model in session) {
      final existing = result[model.modelName];
      if (existing != null) {
        result[model.modelName] = ModelUsageInfo(
          modelName: model.modelName,
          inputTokens: existing.inputTokens + model.inputTokens,
          outputTokens: existing.outputTokens + model.outputTokens,
          cacheReadTokens: existing.cacheReadTokens + model.cacheReadTokens,
          cacheCreationTokens:
              existing.cacheCreationTokens + model.cacheCreationTokens,
          costUsd: existing.costUsd + model.costUsd,
          contextWindow: model.contextWindow,
        );
      } else {
        result[model.modelName] = model;
      }
    }

    return result.values.toList();
  }
}
