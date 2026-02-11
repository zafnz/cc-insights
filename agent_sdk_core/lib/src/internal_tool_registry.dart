import 'dart:async';
import 'types/internal_tools.dart';

/// Registry for internal MCP tools provided by CC-Insights.
///
/// This registry manages tool definitions and implements the JSON-RPC MCP
/// protocol handling. Backends route MCP messages to this registry for
/// processing.
///
/// Supported MCP methods:
/// - initialize: Returns server info and capabilities
/// - notifications/initialized: No-op notification
/// - tools/list: Returns registered tool definitions
/// - tools/call: Invokes tool handler
/// - ping: Health check
class InternalToolRegistry {
  /// The MCP server name identifier.
  static const String serverName = 'cci';

  final Map<String, InternalToolDefinition> _tools = {};

  /// Register a tool with this registry.
  void register(InternalToolDefinition tool) {
    _tools[tool.name] = tool;
  }

  /// Unregister a tool by name.
  void unregister(String name) {
    _tools.remove(name);
  }

  /// Get a tool by name, or null if not found.
  InternalToolDefinition? operator [](String name) => _tools[name];

  /// Get all registered tools.
  List<InternalToolDefinition> get tools => _tools.values.toList();

  /// Check if the registry has no tools.
  bool get isEmpty => _tools.isEmpty;

  /// Check if the registry has any tools.
  bool get isNotEmpty => _tools.isNotEmpty;

  /// Handle a JSON-RPC MCP message and return the response.
  ///
  /// Returns null for notifications (no response needed).
  ///
  /// Routes:
  /// - initialize → server info + capabilities
  /// - notifications/initialized → null (no response)
  /// - tools/list → tool definitions
  /// - tools/call → handler invocation
  /// - ping → empty result
  /// - unknown → JSON-RPC error -32601
  Future<Map<String, dynamic>?> handleMcpMessage(
    Map<String, dynamic> message,
  ) async {
    final method = message['method'] as String?;
    final id = message['id']; // Can be int or String
    final params = (message['params'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {};

    switch (method) {
      case 'initialize':
        return _jsonRpcResult(id, {
          'protocolVersion': '2024-11-05',
          'serverInfo': {'name': serverName, 'version': '1.0.0'},
          'capabilities': {
            'tools': {'listChanged': false},
          },
        });

      case 'notifications/initialized':
        return null; // Notification, no response

      case 'tools/list':
        return _jsonRpcResult(id, {
          'tools': _tools.values.map((t) {
            return {
              'name': t.name,
              'description': t.description,
              'inputSchema': t.inputSchema,
            };
          }).toList(),
        });

      case 'tools/call':
        final toolName = params['name'] as String?;
        final arguments = (params['arguments'] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {};
        final tool = _tools[toolName];

        if (tool == null) {
          return _jsonRpcResult(id, {
            'content': [
              {'type': 'text', 'text': 'Unknown tool: $toolName'},
            ],
            'isError': true,
          });
        }

        try {
          final result = await tool.handler(arguments);
          return _jsonRpcResult(id, {
            'content': [
              {'type': 'text', 'text': result.content},
            ],
            if (result.isError) 'isError': true,
          });
        } catch (e) {
          return _jsonRpcResult(id, {
            'content': [
              {'type': 'text', 'text': 'Tool error: $e'},
            ],
            'isError': true,
          });
        }

      case 'ping':
        return _jsonRpcResult(id, {});

      default:
        return {
          'jsonrpc': '2.0',
          'id': id,
          'error': {
            'code': -32601,
            'message': 'Unknown method: $method',
          },
        };
    }
  }

  /// Build a JSON-RPC success result response.
  Map<String, dynamic> _jsonRpcResult(
    dynamic id,
    Map<String, dynamic> result,
  ) {
    return {
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };
  }
}
