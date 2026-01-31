import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

import '../acp/acp_client_wrapper.dart';
import '../acp/acp_session_wrapper.dart';
import '../acp/pending_permission.dart';
import 'agent_registry.dart';

/// Service for managing agent connections.
///
/// This service replaces [BackendService] with ACP-based agent management.
/// It uses [ACPClientWrapper] to connect to agents discovered by [AgentRegistry].
///
/// The service extends [ChangeNotifier] for Provider integration, notifying
/// listeners when the connection state changes.
///
/// Example usage:
/// ```dart
/// final agentService = AgentService(agentRegistry: registry);
///
/// // Connect to an agent
/// final config = registry.getAgent('claude-code');
/// await agentService.connect(config!);
///
/// // Create a session
/// final session = await agentService.createSession(cwd: '/path/to/project');
///
/// // Use the session
/// session.updates.listen((update) => print('Update: $update'));
/// await session.prompt([TextContentBlock(text: 'Hello!')]);
///
/// // Disconnect when done
/// await agentService.disconnect();
/// ```
class AgentService extends ChangeNotifier {
  /// Creates an agent service.
  ///
  /// The [agentRegistry] is used for agent discovery and configuration lookup.
  AgentService({required this.agentRegistry});

  /// The agent registry for discovering and managing agents.
  final AgentRegistry agentRegistry;

  ACPClientWrapper? _client;
  AgentConfig? _currentAgent;

  /// Whether the service is currently connected to an agent.
  ///
  /// Returns `true` if a connection has been established and is active.
  bool get isConnected => _client?.isConnected ?? false;

  /// The currently connected agent configuration.
  ///
  /// Returns `null` if not connected to any agent.
  AgentConfig? get currentAgent => _currentAgent;

  /// The capabilities of the connected agent.
  ///
  /// Returns `null` if not connected or if the agent didn't provide
  /// capabilities during initialization.
  AgentCapabilities? get capabilities => _client?.capabilities;

  /// Information about the connected agent.
  ///
  /// Returns `null` if not connected.
  AgentInfo? get agentInfo => _client?.agentInfo;

  /// Stream of session update notifications from the agent.
  ///
  /// This stream receives all updates across all sessions. For session-specific
  /// updates, use [ACPSessionWrapper.updates].
  ///
  /// Returns `null` if not connected.
  Stream<SessionNotification>? get updates => _client?.updates;

  /// Stream of permission requests from the agent.
  ///
  /// Returns `null` if not connected.
  Stream<PendingPermission>? get permissionRequests =>
      _client?.permissionRequests;

  /// Connects to an agent.
  ///
  /// This method disconnects from any existing agent first, then spawns the
  /// new agent process and performs ACP initialization.
  ///
  /// The [config] specifies the agent to connect to, including the command,
  /// arguments, and environment variables.
  ///
  /// Notifies listeners when the connection state changes.
  ///
  /// Throws an exception if the agent process fails to start or if
  /// initialization fails.
  ///
  /// Example:
  /// ```dart
  /// final config = AgentConfig(
  ///   id: 'claude-code',
  ///   name: 'Claude Code',
  ///   command: 'claude-code-acp',
  /// );
  /// await agentService.connect(config);
  /// ```
  Future<void> connect(AgentConfig config) async {
    // Disconnect from any existing agent first
    await disconnect();

    _currentAgent = config;
    _client = ACPClientWrapper(agentConfig: config);

    await _client!.connect();
    notifyListeners();
  }

  /// Creates a session for a chat.
  ///
  /// The [cwd] specifies the working directory for the session, typically
  /// the project or worktree root. Optional [mcpServers] can be provided
  /// to connect to Model Context Protocol servers.
  ///
  /// Returns an [ACPSessionWrapper] that provides session-specific streams
  /// and methods for interacting with the agent.
  ///
  /// Throws [StateError] if not connected to an agent.
  ///
  /// Example:
  /// ```dart
  /// final session = await agentService.createSession(
  ///   cwd: '/path/to/project',
  /// );
  ///
  /// // Listen for updates
  /// session.updates.listen((update) => print('Update: $update'));
  ///
  /// // Send a prompt
  /// await session.prompt([TextContentBlock(text: 'Hello!')]);
  ///
  /// // Clean up
  /// session.dispose();
  /// ```
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServerBase>? mcpServers,
  }) async {
    if (_client == null || !_client!.isConnected) {
      throw StateError('Agent not connected. Call connect() first.');
    }

    return _client!.createSession(
      cwd: cwd,
      mcpServers: mcpServers,
    );
  }

  /// Disconnects from the current agent.
  ///
  /// This method safely disconnects from the current agent, cleaning up
  /// the process and resources. It's safe to call even if not connected.
  ///
  /// Notifies listeners when disconnection completes.
  Future<void> disconnect() async {
    await _client?.disconnect();
    _client = null;
    _currentAgent = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }
}
