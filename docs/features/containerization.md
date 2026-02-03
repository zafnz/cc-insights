# Containerized Claude Execution

## Overview

This feature enables running Claude CLI inside a Docker container with controlled network access via a host-side proxy. The goal is to establish a security boundary where Claude (and any tools/commands it runs) is isolated from the host system, with only the project directory accessible and network traffic filtered through an allowlist.

**Key principle**: The proxy runs on the host, outside the container. This ensures Claude cannot bypass or manipulate it even if container escape were possible.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host (macOS)                             │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                      Flutter App                            │ │
│  │                                                             │ │
│  │  ┌─────────────────┐  ┌──────────────────────────────────┐ │ │
│  │  │   UI Panels     │  │        Services                   │ │ │
│  │  │                 │  │  - GitService (local)             │ │ │
│  │  │  - Chat         │  │  - FileService (local)            │ │ │
│  │  │  - Files        │  │  - ContainerService               │ │ │
│  │  │  - Git Status   │  │  - ProxyService                   │ │ │
│  │  │  - Proxy Panel  │  │                                   │ │ │
│  │  └─────────────────┘  └──────────────────────────────────┘ │ │
│  │           │                         │                       │ │
│  │           │         ┌───────────────┴───────────────┐       │ │
│  │           │         │                               │       │ │
│  │           │         ▼                               ▼       │ │
│  │           │  ┌─────────────┐              ┌──────────────┐  │ │
│  │           │  │ TCP Client  │              │ HTTP Proxy   │  │ │
│  │           │  │ (Claude IO) │              │ (Allowlist)  │  │ │
│  │           │  └──────┬──────┘              └──────┬───────┘  │ │
│  └───────────┼─────────┼───────────────────────────┼──────────┘ │
│              │         │ :9999                      │ :8080      │
│              │         │                            │            │
│  ┌───────────┼─────────▼────────────────────────────┼──────────┐ │
│  │           │   Docker Container                   │          │ │
│  │           │                                      │          │ │
│  │           │   ┌────────────────────────────────┐ │          │ │
│  │           │   │         Claude CLI             │ │          │ │
│  │           │   │                                │ │          │ │
│  │           │   │  HTTP_PROXY=host:8080  ────────┼─┘          │ │
│  │           │   │  stdin/stdout ← TCP :9999      │            │ │
│  │           │   │                                │            │ │
│  │           │   │  /workspace (mounted volume)   │            │ │
│  │           │   └────────────────────────────────┘            │ │
│  │           │                                                 │ │
│  │           │   Volume: /workspace → ~/projects/foo           │ │
│  └───────────┼─────────────────────────────────────────────────┘ │
│              │                                                   │
│              ▼                                                   │
│      ~/projects/foo (project files - read/write)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ (via proxy only)
                              ▼
                          Internet
                    - api.anthropic.com ✓
                    - github.com ✗ (unless allowed)
                    - * ✗ (blocked by default)
```

## Security Model

### What's Isolated (Inside Container)

- Claude CLI process
- All tools Claude executes (bash, npm, etc.)
- Temporary files created by Claude
- Environment variables (except those we explicitly pass)

### What's Accessible to Container

- **Project directory**: Mounted read-write at `/workspace`
- **Network**: Only through host proxy, filtered by allowlist
- **Claude stdin/stdout**: Via TCP socket for communication

### What's Protected (On Host)

- SSH keys (`~/.ssh/`)
- Other projects and personal files
- System configuration
- Direct network access
- The proxy itself (cannot be manipulated from container)

### Network Allowlist

Default allowlist (minimum for Claude to function):

```json
{
  "domains": [
    "api.anthropic.com"
  ],
  "patterns": [
    ".*\\.anthropic\\.com$"
  ]
}
```

Users can extend this via the UI when Claude needs additional access.

## Components

### 1. Transport Abstraction

Abstract the Claude CLI communication to support both local subprocess and TCP:

```dart
/// Base interface for Claude CLI communication
abstract class ClaudeTransport {
  /// Stream of lines from Claude CLI stdout
  Stream<String> get stdout;

  /// Sink for sending lines to Claude CLI stdin
  Sink<String> get stdin;

  /// Whether the transport is connected/running
  bool get isActive;

  /// Clean up resources
  Future<void> dispose();
}

/// Current implementation - direct subprocess
class LocalProcessTransport implements ClaudeTransport {
  final Process _process;
  // ... spawns `claude` directly
}

/// New implementation - TCP to containerized Claude
class TcpTransport implements ClaudeTransport {
  final Socket _socket;

  static Future<TcpTransport> connect(String host, int port) async {
    final socket = await Socket.connect(host, port);
    return TcpTransport._(socket);
  }

  @override
  Stream<String> get stdout => _socket
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  @override
  Sink<String> get stdin => _SocketLineSink(_socket);

  @override
  Future<void> dispose() async {
    await _socket.close();
  }
}
```

### 2. Container Service

Manages Docker container lifecycle:

```dart
class ContainerService extends ChangeNotifier {
  ContainerState _state = ContainerState.stopped;
  String? _containerId;
  int _claudePort = 9999;
  int _proxyPort = 8080;

  ContainerState get state => _state;
  int get claudePort => _claudePort;

  /// Launch containerized Claude for a project
  Future<void> launch({
    required String projectPath,
    int claudePort = 9999,
  }) async {
    _state = ContainerState.starting;
    notifyListeners();

    // Ensure proxy is running first
    await _proxyService.ensureRunning();

    final result = await Process.run('docker', [
      'run',
      '-d',
      '--rm',
      '-p', '$claudePort:9999',
      '-v', '$projectPath:/workspace:rw',
      '-e', 'HTTP_PROXY=http://host.docker.internal:$_proxyPort',
      '-e', 'HTTPS_PROXY=http://host.docker.internal:$_proxyPort',
      '-e', 'ANTHROPIC_API_KEY',  // Pass through from host
      '--name', 'claude-sandbox-${DateTime.now().millisecondsSinceEpoch}',
      'claude-sandbox:latest',
    ]);

    if (result.exitCode == 0) {
      _containerId = result.stdout.toString().trim();
      _claudePort = claudePort;
      _state = ContainerState.running;
    } else {
      _state = ContainerState.error;
    }
    notifyListeners();
  }

  /// Stop the container
  Future<void> stop() async {
    if (_containerId != null) {
      await Process.run('docker', ['stop', _containerId!]);
      _containerId = null;
    }
    _state = ContainerState.stopped;
    notifyListeners();
  }

  /// Get transport for communicating with containerized Claude
  Future<ClaudeTransport> getTransport() async {
    if (_state != ContainerState.running) {
      throw StateError('Container not running');
    }
    return TcpTransport.connect('localhost', _claudePort);
  }
}

enum ContainerState {
  stopped,
  starting,
  running,
  stopping,
  error,
}
```

### 3. Proxy Service

Manages the HTTP proxy for network filtering:

```dart
class ProxyService extends ChangeNotifier {
  Process? _proxyProcess;
  ProxyState _state = ProxyState.stopped;

  final List<String> _allowedDomains = ['api.anthropic.com'];
  final List<ProxyLogEntry> _trafficLog = [];

  List<String> get allowedDomains => List.unmodifiable(_allowedDomains);
  List<ProxyLogEntry> get trafficLog => List.unmodifiable(_trafficLog);
  ProxyState get state => _state;

  /// Start the proxy server
  Future<void> start({int port = 8080}) async {
    _state = ProxyState.starting;
    notifyListeners();

    await _writeAllowlist();

    _proxyProcess = await Process.start('mitmproxy', [
      '--listen-port', '$port',
      '--scripts', _allowlistScriptPath,
      '--set', 'confdir=${_configDir}',
      '--quiet',
    ]);

    // Monitor proxy output for traffic logging
    _proxyProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleProxyOutput);

    _state = ProxyState.running;
    notifyListeners();
  }

  /// Add a domain to the allowlist
  Future<void> allowDomain(String domain) async {
    if (!_allowedDomains.contains(domain)) {
      _allowedDomains.add(domain);
      await _writeAllowlist();
      notifyListeners();
    }
  }

  /// Remove a domain from the allowlist
  Future<void> blockDomain(String domain) async {
    // Don't allow removing required domains
    if (domain == 'api.anthropic.com') return;

    _allowedDomains.remove(domain);
    await _writeAllowlist();
    notifyListeners();
  }

  /// Stop the proxy
  Future<void> stop() async {
    _proxyProcess?.kill();
    _proxyProcess = null;
    _state = ProxyState.stopped;
    notifyListeners();
  }

  void _handleProxyOutput(String line) {
    // Parse mitmproxy output to build traffic log
    final entry = ProxyLogEntry.tryParse(line);
    if (entry != null) {
      _trafficLog.add(entry);
      notifyListeners();
    }
  }

  Future<void> _writeAllowlist() async {
    final config = jsonEncode({
      'domains': _allowedDomains,
      'patterns': _allowedDomains
          .where((d) => d.startsWith('*.'))
          .map((d) => '.*${RegExp.escape(d.substring(1))}\$')
          .toList(),
    });
    await File(_allowlistPath).writeAsString(config);
  }
}

class ProxyLogEntry {
  final DateTime timestamp;
  final String method;
  final String host;
  final String path;
  final bool allowed;
  final int? statusCode;

  // ...
}

enum ProxyState {
  stopped,
  starting,
  running,
  error,
}
```

### 4. Docker Image

Minimal image with Claude CLI and TCP bridge:

```dockerfile
# docker/claude-sandbox/Dockerfile
FROM node:20-slim

# Install Claude CLI
RUN npm install -g @anthropic-ai/claude-code

# Install socat for TCP-to-stdio bridging
RUN apt-get update && \
    apt-get install -y --no-install-recommends socat ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# TCP port for Claude CLI communication
EXPOSE 9999

# Bridge TCP to Claude CLI stdin/stdout
# The pty allocation ensures proper line buffering
ENTRYPOINT ["socat", \
    "TCP-LISTEN:9999,reuseaddr,fork", \
    "EXEC:'claude --output-format stream-json --input-format stream-json',pty,stderr"]
```

Build script:

```bash
#!/bin/bash
# docker/build.sh
docker build -t claude-sandbox:latest docker/claude-sandbox/
```

### 5. Proxy Allowlist Script

mitmproxy addon for filtering requests:

```python
# docker/proxy/allowlist.py
from mitmproxy import http, ctx
import json
import os
import re

ALLOWLIST_FILE = os.environ.get('ALLOWLIST_FILE', '/tmp/proxy-allowlist.json')

def load_allowlist():
    try:
        with open(ALLOWLIST_FILE) as f:
            return json.load(f)
    except Exception as e:
        ctx.log.warn(f"Failed to load allowlist: {e}")
        return {"domains": ["api.anthropic.com"], "patterns": []}

class AllowlistAddon:
    def request(self, flow: http.HTTPFlow) -> None:
        allowlist = load_allowlist()
        host = flow.request.host

        # Check exact domain match
        if host in allowlist.get("domains", []):
            ctx.log.info(f"ALLOWED: {flow.request.method} {host}{flow.request.path}")
            return

        # Check pattern match
        for pattern in allowlist.get("patterns", []):
            if re.match(pattern, host):
                ctx.log.info(f"ALLOWED (pattern): {flow.request.method} {host}{flow.request.path}")
                return

        # Block and log
        ctx.log.warn(f"BLOCKED: {flow.request.method} {host}{flow.request.path}")
        flow.response = http.Response.make(
            403,
            b"Blocked by CC-Insights proxy allowlist.\n"
            b"Domain not in allowlist. Add it via the Proxy panel.",
            {"Content-Type": "text/plain"}
        )

addons = [AllowlistAddon()]
```

### 6. UI Components

#### Container Status Widget

```dart
class ContainerStatusWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final container = context.watch<ContainerService>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusIndicator(state: container.state),
        const SizedBox(width: 8),
        Text(_stateLabel(container.state)),
        const SizedBox(width: 8),
        if (container.state == ContainerState.stopped)
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Launch sandboxed Claude',
            onPressed: () => _launchContainer(context),
          )
        else if (container.state == ContainerState.running)
          IconButton(
            icon: const Icon(Icons.stop),
            tooltip: 'Stop container',
            onPressed: container.stop,
          ),
      ],
    );
  }
}
```

#### Proxy Panel

```dart
class ProxyPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final proxy = context.watch<ProxyService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.security),
            const SizedBox(width: 8),
            Text('Network Proxy', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            _ProxyStatusChip(state: proxy.state),
          ],
        ),
        const Divider(),

        // Allowed domains
        Text('Allowed Domains', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final domain in proxy.allowedDomains)
              Chip(
                label: Text(domain),
                deleteIcon: domain == 'api.anthropic.com'
                    ? null
                    : const Icon(Icons.close, size: 16),
                onDeleted: domain == 'api.anthropic.com'
                    ? null
                    : () => proxy.blockDomain(domain),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              onPressed: () => _showAddDomainDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Traffic log
        Text('Recent Traffic', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: proxy.trafficLog.length,
            reverse: true,  // Most recent first
            itemBuilder: (context, index) {
              final entry = proxy.trafficLog[proxy.trafficLog.length - 1 - index];
              return _TrafficLogTile(entry: entry, onAllow: proxy.allowDomain);
            },
          ),
        ),
      ],
    );
  }
}

class _TrafficLogTile extends StatelessWidget {
  final ProxyLogEntry entry;
  final Function(String) onAllow;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(
        entry.allowed ? Icons.check_circle : Icons.block,
        color: entry.allowed ? Colors.green : Colors.red,
        size: 20,
      ),
      title: Text(entry.host, style: const TextStyle(fontFamily: 'JetBrains Mono')),
      subtitle: Text('${entry.method} ${entry.path}'),
      trailing: entry.allowed ? null : TextButton(
        onPressed: () => onAllow(entry.host),
        child: const Text('Allow'),
      ),
    );
  }
}
```

## User Experience

### Launching Sandboxed Mode

1. User clicks "Launch Sandboxed" button in toolbar (or chat panel)
2. App checks Docker is available, prompts to install if not
3. App starts proxy service (if not running)
4. App launches Claude container with project mounted
5. Status indicator shows container running
6. User can now chat with Claude as normal

### Network Access Workflow

1. Claude tries to access a blocked domain (e.g., `github.com` for cloning)
2. Proxy blocks request, logs it
3. Proxy panel shows blocked request with "Allow" button
4. User clicks "Allow" to add domain to allowlist
5. Claude retries and succeeds

### Stopping

1. User clicks "Stop" button
2. Container is stopped and removed
3. Proxy continues running (for next session)
4. User can stop proxy separately if desired

## Implementation Plan

### Phase 1: Transport Abstraction

1. Create `ClaudeTransport` interface
2. Refactor `CliProcess` to use `LocalProcessTransport`
3. Implement `TcpTransport`
4. Add transport selection to `CliSession`

No behavior change for existing users - just internal refactoring.

### Phase 2: Container Infrastructure

1. Create Docker image with Claude CLI
2. Implement `ContainerService`
3. Add container launch/stop UI
4. Test TCP communication to containerized Claude

### Phase 3: Proxy Integration

1. Implement `ProxyService` using mitmproxy
2. Create allowlist addon script
3. Add Proxy panel to UI
4. Wire container to use host proxy

### Phase 4: Polish

1. Docker availability detection and installation prompts
2. Persist proxy allowlist to settings
3. Container resource limits (memory, CPU)
4. Error handling and recovery
5. Documentation and user guide

## Dependencies

### Required on Host

- **Docker Desktop**: For running containers
- **mitmproxy**: For HTTP proxy (`brew install mitmproxy`)

### Container Image

- Node.js 20 (for Claude CLI)
- socat (for TCP bridging)
- Claude CLI (`@anthropic-ai/claude-code`)

## Security Considerations

### Container Hardening

```bash
docker run \
  --read-only \                      # Read-only root filesystem
  --tmpfs /tmp \                     # Writable /tmp
  --security-opt no-new-privileges \ # No privilege escalation
  --cap-drop ALL \                   # Drop all capabilities
  --memory 4g \                      # Memory limit
  --cpus 2 \                         # CPU limit
  -v "$PROJECT:/workspace:rw" \      # Only project is writable
  ...
```

### Proxy Security

- Proxy runs on host, outside container security boundary
- HTTPS traffic is not inspected (MITM would break certificate validation)
- Allowlist is domain-based, not content-based
- Traffic log is for visibility, not deep inspection

### Limitations

- Container escape vulnerabilities (rare but possible)
- DNS can leak information even with proxy
- Project files are fully accessible to Claude within container
- If a domain is allowed, all traffic to that domain is allowed

## Alternatives Considered

### Proxy Inside Container

Rejected because:
- Proxy would be inside the security boundary
- Claude could potentially manipulate proxy if container escape occurred
- Defeats the purpose of having a security boundary

### VPN-based Isolation

Rejected because:
- More complex setup
- Requires elevated privileges
- Harder to allowlist specific domains

### macOS Sandbox (sandbox-exec)

Could be used instead of Docker:
- Lighter weight, no Docker dependency
- But: Less portable, complex S-expression profiles
- Could be added as alternative mode later

## Future Enhancements

### Per-Session Allowlist

Track which domains were allowed per chat session, allow clearing on new session.

### Allowlist Presets

Pre-configured allowlists for common workflows:
- "Web Development": npm registry, jsdelivr, etc.
- "Python Development": pypi.org, etc.
- "Minimal": Only Anthropic API

### Container Snapshots

Save/restore container state for faster startup or reproducibility.

### Remote Container Execution

Run container on remote Docker host for additional isolation or resource access.
