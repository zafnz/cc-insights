import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

import '../acp/acp_client_wrapper.dart';
import '../acp/acp_errors.dart';
import '../acp/acp_session_wrapper.dart';
import '../acp/pending_permission.dart';
import 'agent_registry.dart';

/// Service for managing agent connections.
///
/// This service provides ACP-based agent management.
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

  /// The current connection state.
  ///
  /// Returns [ACPConnectionState.disconnected] if no connection attempt
  /// has been made.
  ACPConnectionState get connectionState =>
      _client?.connectionState ?? ACPConnectionState.disconnected;

  /// The last error that occurred during connection.
  ///
  /// Returns `null` if no error has occurred or if the connection
  /// was successful.
  ACPError? get lastError => _client?.lastError;

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
  /// Throws [ACPConnectionError] if the agent process fails to start.
  /// Throws [ACPTimeoutError] if connection takes too long.
  /// Throws [ACPStateError] if already connected.
  ///
  /// Example:
  /// ```dart
  /// final config = AgentConfig(
  ///   id: 'claude-code',
  ///   name: 'Claude Code',
  ///   command: 'claude-code-acp',
  /// );
  /// try {
  ///   await agentService.connect(config);
  /// } on ACPConnectionError catch (e) {
  ///   print('Failed to connect: ${e.message}');
  /// }
  /// ```
  Future<void> connect(AgentConfig config) async {
    debugPrint('[AgentService] connect() called for: ${config.name}');
    debugPrint('[AgentService] command: ${config.command}, args: ${config.args}');

    // Disconnect from any existing agent first
    debugPrint('[AgentService] Disconnecting from any existing agent...');
    await disconnect();
    debugPrint('[AgentService] Disconnected. Creating new client wrapper...');

    _currentAgent = config;
    _client = ACPClientWrapper(agentConfig: config);

    // Listen for client state changes (e.g., process crash)
    _client!.addListener(_onClientStateChanged);

    try {
      debugPrint('[AgentService] Calling _client.connect()...');
      await _client!.connect();
      debugPrint('[AgentService] Connection successful!');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[AgentService] Connection failed: $e');
      debugPrint('[AgentService] Stack trace: $stackTrace');
      // Notify listeners about the failed connection
      notifyListeners();
      rethrow;
    }
  }

  /// Called when the client state changes (e.g., process crash).
  void _onClientStateChanged() {
    // Propagate state changes to our listeners
    notifyListeners();
  }

  /// Creates a session for a chat.
  ///
  /// The [cwd] specifies the working directory for the session, typically
  /// the project or worktree root. Optional [mcpServers] can be provided
  /// to connect to Model Context Protocol servers.
  ///
  /// Set [includePartialMessages] to `false` to disable streaming text updates.
  /// When disabled, only complete messages are sent instead of character-by-character
  /// streaming. Defaults to `true`.
  ///
  /// Returns an [ACPSessionWrapper] that provides session-specific streams
  /// and methods for interacting with the agent.
  ///
  /// Throws [ACPStateError] if not connected to an agent.
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
    bool includePartialMessages = true,
  }) async {
    if (_client == null || !_client!.isConnected) {
      throw ACPStateError.notConnected();
    }

    return _client!.createSession(
      cwd: cwd,
      mcpServers: mcpServers,
      includePartialMessages: includePartialMessages,
    );
  }

  /// Disconnects from the current agent.
  ///
  /// This method safely disconnects from the current agent, cleaning up
  /// the process and resources. It's safe to call even if not connected.
  ///
  /// Notifies listeners when disconnection completes.
  Future<void> disconnect() async {
    _client?.removeListener(_onClientStateChanged);
    await _client?.disconnect();
    _client = null;
    _currentAgent = null;
    notifyListeners();
  }

  /// Attempts to reconnect to the current agent.
  ///
  /// This is useful after a connection failure or process crash.
  /// If no agent was previously connected, this method does nothing.
  ///
  /// Returns `true` if reconnection was attempted, `false` if there
  /// was no previous agent to reconnect to.
  ///
  /// Throws [ACPConnectionError] if the reconnection fails.
  Future<bool> reconnect() async {
    final agent = _currentAgent;
    if (agent == null) {
      return false;
    }

    await disconnect();
    await connect(agent);
    return true;
  }

  @override
  void dispose() {
    _client?.removeListener(_onClientStateChanged);
    _client?.dispose();
    super.dispose();
  }
}
