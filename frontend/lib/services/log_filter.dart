import 'log_service.dart';

/// Operator for filter comparisons.
enum FilterOperator {
  eq,
  neq,
  contains,
}

/// A parsed log filter that can test entries against a simple query.
///
/// Supports basic jq-style field access:
/// - `.source == "App"` — exact match on source
/// - `.level == "error"` — match by level name
/// - `.message contains "timeout"` — substring search in message
/// - `.meta.worktree == "main"` — nested metadata field access
/// - `.meta.worktree != "main"` — negated match
class LogFilter {
  LogFilter._(this._accessorPath, this._operator, this._value);

  final List<String> _accessorPath;
  final FilterOperator _operator;
  final String _value;

  /// Parses a query string into a [LogFilter].
  ///
  /// Returns `null` if the query is empty or cannot be parsed.
  static LogFilter? parse(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    // Find the operator
    FilterOperator? op;
    int opStart = -1;
    int opEnd = -1;

    // Check for "contains" first (before == and !=)
    final containsIdx = trimmed.indexOf(' contains ');
    if (containsIdx > 0) {
      op = FilterOperator.contains;
      opStart = containsIdx;
      opEnd = containsIdx + ' contains '.length;
    }

    // Check for != (before == to avoid partial match)
    if (op == null) {
      final neqIdx = trimmed.indexOf(' != ');
      if (neqIdx > 0) {
        op = FilterOperator.neq;
        opStart = neqIdx;
        opEnd = neqIdx + ' != '.length;
      }
    }

    // Check for ==
    if (op == null) {
      final eqIdx = trimmed.indexOf(' == ');
      if (eqIdx > 0) {
        op = FilterOperator.eq;
        opStart = eqIdx;
        opEnd = eqIdx + ' == '.length;
      }
    }

    if (op == null || opStart < 0) return null;

    // Parse accessor path (e.g., ".source" or ".meta.worktree")
    final accessorStr = trimmed.substring(0, opStart).trim();
    if (!accessorStr.startsWith('.')) return null;

    final path = accessorStr.substring(1).split('.');
    if (path.isEmpty || path.any((p) => p.isEmpty)) return null;

    // Parse value (strip quotes if present)
    var valueStr = trimmed.substring(opEnd).trim();
    if (valueStr.length >= 2 &&
        ((valueStr.startsWith('"') && valueStr.endsWith('"')) ||
            (valueStr.startsWith("'") && valueStr.endsWith("'")))) {
      valueStr = valueStr.substring(1, valueStr.length - 1);
    }
    if (valueStr.isEmpty) return null;

    return LogFilter._(path, op, valueStr);
  }

  /// Returns true if the given [entry] matches this filter.
  bool matches(LogEntry entry) {
    final resolved = _resolve(entry);
    if (resolved == null) {
      // Field not found — only != matches
      return _operator == FilterOperator.neq;
    }

    return switch (_operator) {
      FilterOperator.eq => resolved == _value,
      FilterOperator.neq => resolved != _value,
      FilterOperator.contains =>
        resolved.toLowerCase().contains(_value.toLowerCase()),
    };
  }

  /// Resolves the accessor path against a [LogEntry] to get a string value.
  String? _resolve(LogEntry entry) {
    if (_accessorPath.isEmpty) return null;
    final first = _accessorPath[0];

    switch (first) {
      case 'source':
        return entry.source;
      case 'level':
        return entry.level.name;
      case 'message':
        return entry.message;
      case 'meta':
        if (entry.meta == null) return null;
        dynamic current = entry.meta;
        for (var i = 1; i < _accessorPath.length; i++) {
          if (current is Map) {
            current = current[_accessorPath[i]];
          } else {
            return null;
          }
        }
        return current?.toString();
      default:
        return null;
    }
  }
}
