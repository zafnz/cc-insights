import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:acp_dart/acp_dart.dart';
import 'package:flutter/foundation.dart';

import 'acp_errors.dart';
import 'acp_logger.dart';
import 'acp_session_wrapper.dart';
import 'cc_insights_acp_client.dart';
import 'handlers/terminal_handler.dart';
import 'pending_permission.dart';

/// The connection state of an ACP client.
///
/// This enum tracks the lifecycle of a connection to an ACP agent,
/// from initial state through connection attempts, active connection,
/// and disconnection or error states.
enum ACPConnectionState {
  /// Initial state before any connection attempt.
  disconnected,

  /// Currently attempting to connect to the agent.
  ///
  /// The client is in the process of spawning the agent process
  /// and performing ACP protocol initialization.
  connecting,

  /// Successfully connected to the agent.
  ///
  /// The agent process is running and protocol initialization
  /// is complete. Sessions can be created.
  connected,

  /// Connection failed or the agent process crashed.
  ///
  /// Check [ACPClientWrapper.lastError] for details about the failure.
  /// Call [ACPClientWrapper.connect] to retry.
  error,
}

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
  /// The optional [connectionTimeout] controls how long to wait for
  /// the agent to initialize (default: 30 seconds).
  /// Call [connect] to establish the connection.
  ACPClientWrapper({
    required this.agentConfig,
    this.connectionTimeout = const Duration(seconds: 30),
  });

  /// Configuration for the agent to connect to.
  final AgentConfig agentConfig;

  /// Timeout for connection initialization.
  final Duration connectionTimeout;

  Process? _process;
  ClientSideConnection? _connection;
  ACPConnectionState _connectionState = ACPConnectionState.disconnected;
  InitializeResponse? _initResult;
  ACPError? _lastError;
  StreamSubscription<int>? _exitCodeSubscription;
  StreamSubscription<String>? _stderrSubscription;

  // Stream controllers for bridging callbacks to streams
  final _updateController = StreamController<SessionNotification>.broadcast();
  final _permissionController = StreamController<PendingPermission>.broadcast();
  final _terminalHandler = TerminalHandler();

  /// The current connection state.
  ///
  /// Use this to track connection lifecycle and show appropriate UI.
  ACPConnectionState get connectionState => _connectionState;

  /// Whether the client is connected to the agent.
  ///
  /// This is a convenience getter equivalent to
  /// `connectionState == ACPConnectionState.connected`.
  bool get isConnected => _connectionState == ACPConnectionState.connected;

  /// The last error that occurred, if any.
  ///
  /// This is set when [connectionState] is [ACPConnectionState.error].
  /// It is cleared when [connect] is called again.
  ACPError? get lastError => _lastError;

  /// The agent's capabilities, available after [connect] completes.
  ///
  /// Returns `null` if not connected or if the agent didn't provide
  /// capabilities during initialization.
  AgentCapabilities? get capabilities => _initResult?.agentCapabilities;

  /// Information about the connected agent, if available.
  ///
  /// Note: The current ACP spec's [InitializeResponse] does not include
  /// agent info directly. This is derived from [agentConfig].
  AgentInfo? get agentInfo => isConnected
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
  /// Throws [ACPStateError] if already connected.
  /// Throws [ACPConnectionError] if the agent process fails to start.
  /// Throws [ACPTimeoutError] if initialization takes too long.
  Future<void> connect() async {
    debugPrint('[ACPClientWrapper] connect() called');
    debugPrint('[ACPClientWrapper] Current state: $_connectionState');

    if (_connectionState == ACPConnectionState.connected) {
      debugPrint('[ACPClientWrapper] Already connected, throwing error');
      throw ACPStateError.alreadyConnected();
    }
    if (_connectionState == ACPConnectionState.connecting) {
      debugPrint('[ACPClientWrapper] Already connecting, throwing error');
      throw const ACPStateError(
        'Connection already in progress',
        currentState: 'connecting',
      );
    }

    // Clear any previous error and set connecting state
    _lastError = null;
    _connectionState = ACPConnectionState.connecting;
    debugPrint('[ACPClientWrapper] State set to connecting, notifying...');
    notifyListeners();

    developer.log(
      'Connecting to agent: ${agentConfig.name} (${agentConfig.command})',
      name: 'ACPClientWrapper',
    );
    debugPrint('[ACPClientWrapper] Connecting to: ${agentConfig.command} '
        '${agentConfig.args.join(" ")}');

    try {
      // Spawn the agent process with merged environment
      debugPrint('[ACPClientWrapper] Spawning agent process...');
      try {
        _process = await Process.start(
          agentConfig.command,
          agentConfig.args,
          environment: {...Platform.environment, ...agentConfig.env},
        );
        debugPrint('[ACPClientWrapper] Process started, pid: ${_process!.pid}');
      } on ProcessException catch (e) {
        debugPrint('[ACPClientWrapper] Process failed to start: ${e.message}');
        throw ACPConnectionError.failedToStart(
          e.message,
          command: agentConfig.command,
        );
      }

      // Monitor for unexpected process exit
      _exitCodeSubscription = _process!.exitCode.asStream().listen(
        (exitCode) {
          _handleProcessExit(exitCode);
        },
      );

      // Log stderr for debugging - track subscription for cleanup
      _stderrSubscription =
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
      debugPrint('[ACPClientWrapper] Creating NDJSON stream...');
      var stream = ndJsonStream(_process!.stdout, _process!.stdin);

      // Wrap with logger if enabled
      if (ACPLogger.instance.isEnabled) {
        debugPrint('[ACPClientWrapper] Wrapping stream with logger...');
        stream = ACPLogger.instance.wrapStream(stream);
      }

      // Create our Client implementation that bridges to streams
      debugPrint('[ACPClientWrapper] Creating CCInsightsACPClient...');
      final client = CCInsightsACPClient(
        updateController: _updateController,
        permissionController: _permissionController,
        terminalHandler: _terminalHandler,
      );

      // Create connection with our client handler
      debugPrint('[ACPClientWrapper] Creating ClientSideConnection...');
      _connection = ClientSideConnection((_) => client, stream);

      // Initialize the connection with our capabilities (with timeout)
      debugPrint('[ACPClientWrapper] Calling initialize() with '
          '${connectionTimeout.inSeconds}s timeout...');
      try {
        _initResult = await _connection!
            .initialize(
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
            )
            .timeout(connectionTimeout);
        debugPrint('[ACPClientWrapper] Initialize completed successfully');
      } on TimeoutException {
        debugPrint('[ACPClientWrapper] Initialize timed out after '
            '${connectionTimeout.inSeconds}s');
        throw ACPTimeoutError.connectionTimeout(connectionTimeout);
      }

      developer.log(
        'Connected to agent. Protocol version: ${_initResult!.protocolVersion}',
        name: 'ACPClientWrapper',
      );
      debugPrint('[ACPClientWrapper] Protocol version: '
          '${_initResult!.protocolVersion}');

      _connectionState = ACPConnectionState.connected;
      debugPrint('[ACPClientWrapper] Connection complete, notifying listeners');
      notifyListeners();
    } on ACPError catch (e) {
      _setError(e);
      rethrow;
    } catch (e) {
      final error = ACPConnectionError.failedToStart(
        e.toString(),
        command: agentConfig.command,
      );
      _setError(error);
      throw error;
    }
  }

  /// Handles unexpected process exit.
  void _handleProcessExit(int exitCode) {
    // Only handle if we're still supposed to be connected
    if (_connectionState == ACPConnectionState.connected ||
        _connectionState == ACPConnectionState.connecting) {
      developer.log(
        'Agent process exited unexpectedly with code $exitCode',
        name: 'ACPClientWrapper',
        level: 1000, // SEVERE level
      );

      final error = ACPConnectionError.processCrashed(
        exitCode,
        command: agentConfig.command,
      );
      _setError(error);
    }
  }

  /// Sets the error state and cleans up.
  void _setError(ACPError error) {
    _lastError = error;
    _connectionState = ACPConnectionState.error;
    _cleanup();
    notifyListeners();
  }

  /// Cleans up resources without changing state.
  void _cleanup() {
    _exitCodeSubscription?.cancel();
    _exitCodeSubscription = null;
    _stderrSubscription?.cancel();
    _stderrSubscription = null;
    _process?.kill();
    _process = null;
    _connection = null;
    _initResult = null;
  }

  /// Creates a new session with the agent.
  ///
  /// The [cwd] specifies the working directory for the session, typically
  /// the project root. Optional [mcpServers] can be provided to connect
  /// to Model Context Protocol servers.
  ///
  /// Set [includePartialMessages] to `false` to disable streaming text updates.
  /// When disabled, only complete messages are sent instead of character-by-character
  /// streaming. This can be useful for clients that don't handle partial messages well.
  /// Defaults to `true`.
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
  /// Throws [ACPStateError] if not connected.
  Future<ACPSessionWrapper> createSession({
    required String cwd,
    List<McpServerBase>? mcpServers,
    bool includePartialMessages = true,
  }) async {
    if (_connectionState != ACPConnectionState.connected ||
        _connection == null) {
      throw ACPStateError.notConnected();
    }

    developer.log(
      'Creating session in: $cwd (partial messages: $includePartialMessages)',
      name: 'ACPClientWrapper',
    );

    final result = await _connection!.newSession(
      NewSessionRequest(
        cwd: cwd,
        mcpServers: mcpServers ?? [],
        meta: {
          'claudeCode': {
            'includePartialMessages': includePartialMessages,
          },
        },
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
    if (_connectionState == ACPConnectionState.disconnected &&
        _process == null) {
      return; // Already disconnected
    }

    developer.log(
      'Disconnecting from agent',
      name: 'ACPClientWrapper',
    );

    // Cancel subscriptions first
    await _exitCodeSubscription?.cancel();
    _exitCodeSubscription = null;
    await _stderrSubscription?.cancel();
    _stderrSubscription = null;

    _connectionState = ACPConnectionState.disconnected;
    _lastError = null;

    // Kill the process and wait for it to exit
    final process = _process;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Force kill if it doesn't exit gracefully
        process.kill(ProcessSignal.sigkill);
      }
    }

    _process = null;
    _connection = null;
    _initResult = null;

    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel subscriptions
    _exitCodeSubscription?.cancel();
    _exitCodeSubscription = null;
    _stderrSubscription?.cancel();
    _stderrSubscription = null;

    // Clean up process without calling notifyListeners
    // (since we're being disposed, listeners shouldn't be notified)
    _connectionState = ACPConnectionState.disconnected;
    _process?.kill();
    _process = null;
    _connection = null;
    _initResult = null;

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
