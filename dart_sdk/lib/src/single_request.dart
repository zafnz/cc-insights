import 'dart:convert';
import 'dart:io';

import 'types/usage.dart';

/// Result from a single Claude CLI request.
class SingleRequestResult {
  const SingleRequestResult({
    required this.result,
    required this.isError,
    required this.durationMs,
    required this.durationApiMs,
    required this.numTurns,
    required this.totalCostUsd,
    required this.usage,
    this.modelUsage,
    this.sessionId,
    this.errors,
  });

  /// The text result from Claude.
  final String result;

  /// Whether the request resulted in an error.
  final bool isError;

  /// Total duration in milliseconds.
  final int durationMs;

  /// API duration in milliseconds.
  final int durationApiMs;

  /// Number of conversation turns.
  final int numTurns;

  /// Total cost in USD.
  final double totalCostUsd;

  /// Token usage statistics.
  final Usage usage;

  /// Per-model usage breakdown.
  final Map<String, ModelUsage>? modelUsage;

  /// The session ID (for reference).
  final String? sessionId;

  /// Error messages if [isError] is true.
  final List<String>? errors;

  factory SingleRequestResult.fromJson(Map<String, dynamic> json) {
    final usageJson = json['usage'] as Map<String, dynamic>? ?? {};

    Map<String, ModelUsage>? modelUsage;
    if (json['modelUsage'] != null) {
      modelUsage = (json['modelUsage'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, ModelUsage.fromJson(v as Map<String, dynamic>)),
      );
    }

    return SingleRequestResult(
      result: json['result'] as String? ?? '',
      isError: json['is_error'] as bool? ?? false,
      durationMs: json['duration_ms'] as int? ?? 0,
      durationApiMs: json['duration_api_ms'] as int? ?? 0,
      numTurns: json['num_turns'] as int? ?? 0,
      totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble() ?? 0.0,
      usage: Usage.fromJson(usageJson),
      modelUsage: modelUsage,
      sessionId: json['session_id'] as String?,
      errors: (json['errors'] as List?)?.cast<String>(),
    );
  }

  @override
  String toString() {
    final truncatedResult =
        result.length > 50 ? '${result.substring(0, 50)}...' : result;
    return 'SingleRequestResult(result: $truncatedResult, '
        'isError: $isError, cost: \$${totalCostUsd.toStringAsFixed(6)}, '
        'tokens: ${usage.inputTokens} in / ${usage.outputTokens} out)';
  }
}

/// Options for a single Claude CLI request.
class SingleRequestOptions {
  const SingleRequestOptions({
    this.model = 'haiku',
    this.allowedTools,
    this.disallowedTools,
    this.permissionMode,
    this.maxTurns,
    this.systemPrompt,
    this.timeoutSeconds = 60,
  });

  /// The model to use (default: 'haiku').
  final String model;

  /// List of allowed tools (e.g., ['Bash(git:*)', 'Read']).
  final List<String>? allowedTools;

  /// List of disallowed tools.
  final List<String>? disallowedTools;

  /// Permission mode ('default', 'acceptEdits', 'bypassPermissions', 'plan').
  final String? permissionMode;

  /// Maximum number of turns.
  final int? maxTurns;

  /// Custom system prompt.
  final String? systemPrompt;

  /// Timeout in seconds (default: 60).
  final int timeoutSeconds;
}

/// Makes single one-shot requests to Claude via the CLI.
///
/// This class runs Claude in one-shot mode using `--print` and
/// `--output-format json` for quick utility tasks. Each request
/// spawns a new process and returns immediately with the result.
///
/// Example usage:
/// ```dart
/// final claude = ClaudeSingleRequest();
///
/// final result = await claude.request(
///   prompt: 'Provide a good commit message for the uncommitted files',
///   workingDirectory: '/path/to/repo',
/// );
///
/// if (result != null && !result.isError) {
///   print('Commit message: ${result.result}');
///   print('Cost: \$${result.totalCostUsd}');
/// }
/// ```
class ClaudeSingleRequest {
  /// Creates a ClaudeSingleRequest instance.
  ///
  /// [claudePath] is the path to the claude CLI executable. If not provided,
  /// it defaults to 'claude' (assuming it's in PATH).
  ///
  /// [onLog] is an optional callback for logging messages.
  ClaudeSingleRequest({
    String? claudePath,
    this.onLog,
  }) : _claudePath = claudePath ?? 'claude';

  final String _claudePath;

  /// Optional logging callback.
  final void Function(String message, {bool isError})? onLog;

  /// Makes a single request to Claude and returns the result.
  ///
  /// Parameters:
  /// - [prompt]: The question or instruction for Claude.
  /// - [workingDirectory]: The directory to run Claude in (for context).
  /// - [options]: Optional configuration for the request.
  ///
  /// Returns the [SingleRequestResult] or null if the process failed to start.
  Future<SingleRequestResult?> request({
    required String prompt,
    required String workingDirectory,
    SingleRequestOptions options = const SingleRequestOptions(),
  }) async {
    _log('Prompt: $prompt');
    _log('Working directory: $workingDirectory');

    final args = _buildArgs(prompt, options);

    _log('Running: $_claudePath ${args.join(' ')}');

    try {
      final process = await Process.start(
        _claudePath,
        args,
        workingDirectory: workingDirectory,
      );

      // Close stdin immediately - Claude CLI waits for EOF before proceeding
      await process.stdin.close();

      // Collect stdout and stderr
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      process.stdout.transform(utf8.decoder).listen(stdoutBuffer.write);
      process.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

      // Wait for completion with timeout
      final exitCode = await process.exitCode.timeout(
        Duration(seconds: options.timeoutSeconds),
        onTimeout: () {
          _log(
            'Process timed out after ${options.timeoutSeconds} seconds',
            isError: true,
          );
          process.kill();
          return -1;
        },
      );

      final stdout = stdoutBuffer.toString();
      final stderr = stderrBuffer.toString();

      if (stderr.isNotEmpty) {
        _log('stderr: $stderr');
      }

      if (exitCode != 0) {
        _log('Process exited with code $exitCode', isError: true);
        return _createErrorResult(
          'Process exited with code $exitCode: $stderr',
        );
      }

      // Parse the JSON output
      final result = _parseResult(stdout);
      if (result != null) {
        _log('Result: ${result.result}');
        _log('Cost: \$${result.totalCostUsd.toStringAsFixed(6)}');
      }

      return result;
    } on ProcessException catch (e) {
      _log('Failed to start process: $e', isError: true);
      return null;
    } catch (e) {
      _log('Error: $e', isError: true);
      return null;
    }
  }

  List<String> _buildArgs(String prompt, SingleRequestOptions options) {
    final args = <String>[];

    // Model
    args.addAll(['--model', options.model]);

    // Output format
    args.addAll(['--output-format', 'json']);

    // Allowed tools
    if (options.allowedTools != null && options.allowedTools!.isNotEmpty) {
      args.addAll(['--allowedTools', options.allowedTools!.join(' ')]);
    }

    // Disallowed tools
    if (options.disallowedTools != null &&
        options.disallowedTools!.isNotEmpty) {
      args.addAll(['--disallowedTools', options.disallowedTools!.join(' ')]);
    }

    // Permission mode
    if (options.permissionMode != null) {
      args.addAll(['--permission-mode', options.permissionMode!]);
    }

    // Max turns
    if (options.maxTurns != null) {
      args.addAll(['--max-turns', options.maxTurns.toString()]);
    }

    // System prompt
    if (options.systemPrompt != null) {
      args.addAll(['--system-prompt', options.systemPrompt!]);
    }

    // The prompt itself (using --print for one-shot mode)
    args.addAll(['--print', prompt]);

    return args;
  }

  SingleRequestResult? _parseResult(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return SingleRequestResult.fromJson(data);
    } catch (e) {
      _log('Failed to parse result JSON: $e', isError: true);
      _log('Raw output: $json');
      return null;
    }
  }

  SingleRequestResult _createErrorResult(String error) {
    return SingleRequestResult(
      result: error,
      isError: true,
      durationMs: 0,
      durationApiMs: 0,
      numTurns: 0,
      totalCostUsd: 0,
      usage: const Usage(inputTokens: 0, outputTokens: 0),
      errors: [error],
    );
  }

  void _log(String message, {bool isError = false}) {
    onLog?.call(message, isError: isError);
  }
}
