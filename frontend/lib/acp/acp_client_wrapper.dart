import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

import 'acp_session_wrapper.dart';
import 'cc_insights_acp_client.dart';
import 'handlers/terminal_handler.dart';
import 'pending_permission.dart';

/// Configuration for an ACP agent.
///
/// This class holds all the information needed to spawn and connect to
/// an ACP-compatible agent process. Agents are discovered by the
/// [AgentRegistry] or configured manually by the user.
///
/// Example:
/// ```dart
/// final config = AgentConfig(
///   id: 'claude-code',
///   name: 'Claude Code',
///   command: '/usr/local/bin/claude-code-acp',
///   args: [],
///   env: {'ANTHROPIC_API_KEY': 'sk-...'},
/// );
/// ```
class AgentConfig {
  /// Creates an agent configuration.
  ///
  /// The [id] should be a unique identifier for this agent type.
  /// The [name] is a human-readable display name.
  /// The [command] is the path to the agent executable.
  /// Optional [args] are passed to the agent process.
  /// Optional [env] are additional environment variables.
  const AgentConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  /// Unique identifier for this agent type.
  ///
  /// Examples: 'claude-code', 'gemini-cli', 'codex-cli'.
  final String id;

  /// Human-readable display name for the agent.
  ///
  /// Examples: 'Claude Code', 'Gemini CLI', 'Codex CLI'.
  final String name;

  /// Path to the agent executable or command name.
  ///
  /// Can be an absolute path or a command in PATH.
  final String command;

  /// Command-line arguments to pass to the agent.
  final List<String> args;

  /// Additional environment variables for the agent process.
  ///
  /// These are merged with the current environment when spawning
  /// the agent process, with these values taking precedence.
  final Map<String, String> env;

  /// Creates an AgentConfig from a JSON map.
  ///
  /// This is used for deserializing agent configurations from persistent
  /// storage or network responses.
  ///
  /// Example:
  /// ```dart
  /// final json = {
  ///   'id': 'claude-code',
  ///   'name': 'Claude Code',
  ///   'command': '/usr/bin/claude-code-acp',
  ///   'args': ['--mode', 'chat'],
  ///   'env': {'API_KEY': 'xxx'},
  /// };
  /// final config = AgentConfig.fromJson(json);
  /// ```
  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      command: json['command'] as String,
      args: (json['args'] as List<dynamic>?)?.cast<String>() ?? const [],
      env: (json['env'] as Map<String, dynamic>?)?.cast<String, String>() ?? const {},
    );
  }

  /// Converts this config to a JSON map.
  ///
  /// This is used for serializing agent configurations to persistent
  /// storage or network requests.
  ///
  /// Example:
  /// ```dart
  /// final config = AgentConfig(
  ///   id: 'claude-code',
  ///   name: 'Claude Code',
  ///   command: '/usr/bin/claude-code-acp',
  /// );
  /// final json = config.toJson();
  /// // {'id': 'claude-code', 'name': 'Claude Code', ...}
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'command': command,
      'args': args,
      'env': env,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AgentConfig &&
        other.id == id &&
        other.name == name &&
        other.command == command &&
        listEquals(other.args, args) &&
        mapEquals(other.env, env);
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        command,
        Object.hashAll(args),
        Object.hashAll(env.entries),
      );

  @override
  String toString() => 'AgentConfig($id: $name)';
}

/// Provider-compatible wrapper around acp_dart's [ClientSideConnection].
///
/// This class manages the lifecycle of an ACP agent connection, including:
/// - Spawning the agent process
/// - Establishing the NDJSON stream connection
/// - Performing protocol initialization
/// - Exposing streams for session updates and permission requests
/// - Creating sessions for conversation
///
/// The wrapper adapts the callback-based acp_dart API to a stream-based
/// API suitable for Flutter's Provider pattern and widget rebuilding.
///
/// Example usage:
/// ```dart
/// final wrapper = ACPClientWrapper(
///   agentConfig: AgentConfig(
///     id: 'claude-code',
///     name: 'Claude Code',
///     command: 'claude-code-acp',
///   ),
/// );
///
/// await wrapper.connect();
/// print('Connected: ${wrapper.isConnected}');
/// print('Agent: ${wrapper.agentInfo?.name}');
///
/// // Create a session
/// final session = await wrapper.createSession(cwd: '/path/to/project');
///
/// // Listen for updates
/// session.updates.listen((update) {
///   print('Update: $update');
/// });
///
/// // Send a prompt
/// await session.prompt([TextContentBlock(text: 'Hello!')]);
///
/// // Clean up
/// await wrapper.disconnect();
/// ```
class ACPClientWrapper extends ChangeNotifier {
  /// Creates a new ACP client wrapper.
  ///
  /// The [agentConfig] specifies the agent to connect to.
  /// Call [connect] to establish the connection.
  ACPClientWrapper({required this.agentConfig});

  /// Configuration for the agent to connect to.
  final AgentConfig agentConfig;

  Process? _process;
  ClientSideConnection? _connection;
  bool _isConnected = false;
  InitializeResponse? _initResult;

  // Stream controllers for bridging callbacks to streams
  final _updateController = StreamController<SessionNotification>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();
  final _terminalHandler = TerminalHandler();

  /// Whether the client is connected to the agent.
  bool get isConnected => _isConnected;

  /// The agent's capabilities, available after [connect] completes.
  ///
  /// Returns `null` if not connected or if the agent didn't provide
  /// capabilities during initialization.
  AgentCapabilities? get capabilities => _initResult?.agentCapabilities;

  /// Information about the connected agent, if available.
  ///
  /// Note: The current ACP spec's [InitializeResponse] does not include
  /// agent info directly. This is derived from [agentConfig].
  AgentInfo? get agentInfo => _isConnected
      ? AgentInfo(
          id: agentConfig.id,
          name: agentConfig.name,
        )
      : null;

  /// The protocol version negotiated with the agent.
  ///
  /// Returns `null` if not connected.
  int? get protocolVersion => _initResult?.protocolVersion;

  /// Available authentication methods from the agent.
  ///
  /// Returns an empty list if not connected or if the agent requires
  /// no authentication.
  List<AuthMethod> get authMethods => _initResult?.authMethods ?? const [];

  /// Stream of session update notifications from the agent.
  ///
  /// This stream receives all updates across all sessions. Use
  /// [ACPSessionWrapper.updates] for session-specific updates.
  Stream<SessionNotification> get updates => _updateController.stream;

  /// Stream of permission requests from the agent.
  ///
  /// When the agent needs authorization for a tool operation, a
  /// [PendingPermission] is added to this stream. The UI should
  /// display the request and call [PendingPermission.allow] or
  /// [PendingPermission.cancel] to resolve it.
  Stream<PendingPermission> get permissionRequests =>
      _permissionController.stream;

  /// Connects to the agent and performs protocol initialization.
  ///
  /// This method:
  /// 1. Spawns the agent process with the configured command and arguments
  /// 2. Creates an NDJSON stream for communication
  /// 3. Creates the [ClientSideConnection] with our [CCInsightsACPClient]
  /// 4. Calls the `initialize` method to negotiate protocol version
  ///
  /// After successful connection, [isConnected] is `true` and [capabilities]
  /// is available.
  ///
  /// Throws an exception if the agent process fails to start or if
  /// initialization fails.
  Future<void> connect() async {
    if (_isConnected) {
      throw StateError('Already connected. Call disconnect() first.');
    }

    developer.log(
      'Connecting to agent: ${agentConfig.name} (${agentConfig.command})',
      name: 'ACPClientWrapper',
    );

    // Spawn the agent process with merged environment
    _process = await Process.start(
      agentConfig.command,
      agentConfig.args,
      environment: {...Platform.environment, ...agentConfig.env},
    );

    // Log stderr for debugging
    _process!.stderr.transform(const SystemEncoding().decoder).listen(
      (data) {
        developer.log(
          'Agent stderr: $data',
          name: 'ACPClientWrapper',
          level: 800, // WARNING level
        );
      },
      onError: (Object error) {
        developer.log(
          'Agent stderr error: $error',
          name: 'ACPClientWrapper',
          level: 1000, // SEVERE level
          error: error,
        );
      },
    );

    // Create NDJSON stream for communication
    final stream = ndJsonStream(_process!.stdout, _process!.stdin);

    // Create our Client implementation that bridges to streams
    final client = CCInsightsACPClient(
      updateController: _updateController,
      permissionController: _permissionController,
      terminalHandler: _terminalHandler,
    );

    // Create connection with our client handler
    _connection = ClientSideConnection((_) => client, stream);

    // Initialize the connection with our capabilities
    _initResult = await _connection!.initialize(
      InitializeRequest(
        protocolVersion: 1,
        clientCapabilities: ClientCapabilities(
          fs: FileSystemCapability(
            readTextFile: true,
            writeTextFile: true,
          ),
          terminal: true,
        ),
      ),
    );

    developer.log(
      'Connected to agent. Protocol version: ${_initResult!.protocolVersion}',
      name: 'ACPClientWrapper',
    );

    _isConnected = true;
    notifyListeners();
  }

  /// Creates a new session with the agent.
  ///
  /// The [cwd] specifies the working directory for the session, typically
  /// the project root. Optional [mcpServers] can be provided to connect
  /// to Model Context Protocol servers.
  ///
  /// Returns an [ACPSessionWrapper] that provides session-specific streams
  /// and methods for interacting with the agent.
  ///
  /// Example:
  /// ```dart
  /// final session = await wrapper.createSession(cwd: '/path/to/project');
  ///
  /// // Listen for updates
  /// session.updates.listen((update) => print('Update: $update'));
  ///
  /// // Send a prompt
  /// final response = await session.prompt([TextContentBlock(text: 'Hello!')]);
  ///
  /// // Clean up
  /// session.dispose();
  /// ```
  ///
  /// Throws [StateError] if not connected.
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServerBase>? mcpServers,
  }) async {
    if (!_isConnected || _connection == null) {
      throw StateError('Not connected. Call connect() first.');
    }

    developer.log(
      'Creating session in: $cwd',
      name: 'ACPClientWrapper',
    );

    final result = await _connection!.newSession(
      NewSessionRequest(
        cwd: cwd,
        mcpServers: mcpServers ?? [],
      ),
    );

    developer.log(
      'Session created: ${result.sessionId}',
      name: 'ACPClientWrapper',
    );

    return ACPSessionWrapper(
      connection: _connection!,
      sessionId: result.sessionId,
      updates: _updateController.stream,
      permissionRequests: _permissionController.stream,
      modes: result.modes,
    );
  }

  /// Gets the underlying [ClientSideConnection].
  ///
  /// This is exposed for [ACPSessionWrapper] to use when sending
  /// requests. Returns `null` if not connected.
  ClientSideConnection? get connection => _connection;

  /// Disconnects from the agent and cleans up resources.
  ///
  /// This method:
  /// 1. Marks the connection as disconnected
  /// 2. Kills the agent process
  /// 3. Waits for the process to exit
  /// 4. Clears internal state
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  Future<void> disconnect() async {
    if (!_isConnected && _process == null) {
      return; // Already disconnected
    }

    developer.log(
      'Disconnecting from agent',
      name: 'ACPClientWrapper',
    );

    _isConnected = false;

    // Kill the process and wait for it to exit
    _process?.kill();
    try {
      await _process?.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Force kill if it doesn't exit gracefully
      _process?.kill(ProcessSignal.sigkill);
    }

    _process = null;
    _connection = null;
    _initResult = null;

    notifyListeners();
  }

  @override
  void dispose() {
    // Start disconnection but don't await it
    disconnect();

    // Close stream controllers
    _updateController.close();
    _permissionController.close();

    // Dispose terminal handler
    _terminalHandler.disposeAll();

    super.dispose();
  }
}

/// Information about an ACP agent.
///
/// This class provides basic metadata about the connected agent.
class AgentInfo {
  /// Creates agent information.
  const AgentInfo({
    required this.id,
    required this.name,
  });

  /// Unique identifier for this agent type.
  final String id;

  /// Human-readable display name for the agent.
  final String name;

  @override
  String toString() => 'AgentInfo($id: $name)';
}
