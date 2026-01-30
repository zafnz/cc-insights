# Standalone Flutter App with TypeScript Backend

## Goal

Create a distributable desktop app that:
- Installs via `brew install cc-insights` (macOS), Scoop/winget (Windows), package managers (Linux)
- Runs from CLI: `cc-insights .` or `cc-insights /path/to/project`
- Ships as a single install with no external dependencies (no Python/Node runtime required)
- Works on macOS, Windows, and Linux

---

## Architecture

```
User runs: cc-insights --cwd /path/to/project
              │
              ▼
     ┌─────────────────┐
     │  Flutter App    │  (the cc-insights binary itself)
     │  (Desktop UI)   │
     └────────┬────────┘
              │ spawns on startup
              ▼
     ┌─────────────────┐
     │ TypeScript      │  (compiled to standalone binary via Bun)
     │ Backend         │
     │ (Claude SDK)    │
     └────────┬────────┘
              │ WebSocket or stdin/stdout
              ▼
     ┌─────────────────┐
     │ Anthropic API   │
     └─────────────────┘
```

---

## Directory Structure (Installed)

### macOS / Linux
```
/usr/local/bin/cc-insights              # Flutter binary (symlink)
~/.local/share/cc-insights/
├── cc-insights                         # Flutter binary (actual)
├── backend                       # Bun-compiled TypeScript backend
└── resources/                    # Icons, etc.
```

### Windows
```
C:\Program Files\CCInsights\
├── cc-insights.exe                     # Flutter binary
├── backend.exe                   # Bun-compiled TypeScript backend
└── resources\
```

---

## Implementation Plan

### Phase 1: TypeScript Backend (1-2 weeks)

Rewrite the Python backend in TypeScript using the official SDK.

**Files to create:**
```
backend-ts/
├── src/
│   ├── index.ts              # Entry point, WebSocket server
│   ├── agent-manager.ts      # Port of agent_manager.py
│   ├── agent-tracker.ts      # Port of agent_tracker.py
│   ├── hooks.ts              # Port of hooks.py
│   └── message-types.ts      # Port of message_types.py
├── package.json
├── tsconfig.json
└── bun.lockb
```

**Key dependencies:**
```json
{
  "dependencies": {
    "@anthropic-ai/claude-code-sdk": "latest",
    "ws": "^8.x"
  }
}
```

**The SDK API is nearly identical to Python:**
```typescript
// Python
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

// TypeScript
import { ClaudeSDKClient, ClaudeAgentOptions } from '@anthropic-ai/claude-code-sdk';
```

### Phase 2: Flutter Changes (3-5 days)

**Update main.dart to:**
1. Accept `--cwd` argument (already done)
2. Find and spawn the backend binary on startup
3. Wait for backend ready signal
4. Connect via WebSocket (existing code works)
5. Kill backend on app exit

**New service:**
```dart
// lib/services/backend_service.dart
class BackendService {
  Process? _process;

  Future<int> start() async {
    final backendPath = _getBackendPath();
    final port = await _findAvailablePort();

    _process = await Process.start(
      backendPath,
      ['--port', port.toString()],
    );

    await _waitForReady(port);
    return port;
  }

  String _getBackendPath() {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isWindows) {
      return path.join(execDir, 'backend.exe');
    }
    return path.join(execDir, '..', 'share', 'cc-insights', 'backend');
  }

  Future<void> stop() async {
    _process?.kill();
  }
}
```

### Phase 3: Build Pipeline (3-5 days)

**Build script structure:**
```
scripts/
├── build-backend.sh          # Compile TS backend for all platforms
├── build-flutter.sh          # Build Flutter for all platforms
├── package-macos.sh          # Create DMG
├── package-windows.sh        # Create MSI/MSIX
├── package-linux.sh          # Create AppImage/deb
└── release.sh                # Full release workflow
```

**Backend build (all platforms from any machine):**
```bash
#!/bin/bash
cd backend-ts

# macOS
bun build ./src/index.ts --compile --target=bun-darwin-arm64 --outfile=../dist/macos-arm64/backend
bun build ./src/index.ts --compile --target=bun-darwin-x64 --outfile=../dist/macos-x64/backend

# Windows
bun build ./src/index.ts --compile --target=bun-windows-x64 --outfile=../dist/windows-x64/backend.exe

# Linux
bun build ./src/index.ts --compile --target=bun-linux-x64 --outfile=../dist/linux-x64/backend
bun build ./src/index.ts --compile --target=bun-linux-arm64 --outfile=../dist/linux-arm64/backend
```

**Flutter build:**
```bash
#!/bin/bash
cd flutter_app

flutter build macos --release
flutter build windows --release
flutter build linux --release
```

**Packaging (macOS example):**
```bash
#!/bin/bash
# Create distribution structure
mkdir -p dist/cc-insights/{bin,share/cc-insights}

# Copy Flutter binary
cp flutter_app/build/macos/Build/Products/Release/CCInsights.app/Contents/MacOS/CCInsights \
   dist/cc-insights/share/cc-insights/cc-insights

# Copy backend
cp dist/macos-arm64/backend dist/cc-insights/share/cc-insights/backend

# Create symlink script for /usr/local/bin
# (Homebrew handles this via the formula)

# Create DMG
hdiutil create -volname "CCInsights" -srcfolder dist/cc-insights -ov CCInsights.dmg

# Sign and notarize
codesign --deep --force --sign "Developer ID" CCInsights.dmg
xcrun notarytool submit CCInsights.dmg --wait
```

### Phase 4: Distribution Setup (2-3 days)

**Homebrew (macOS):**
```ruby
# Formula/cc-insights.rb
class Ccgui < Formula
  desc "GUI for Claude Code agents"
  homepage "https://github.com/you/cc-insights"
  version "1.0.0"

  on_macos do
    on_arm do
      url "https://github.com/you/cc-insights/releases/download/v1.0.0/cc-insights-macos-arm64.tar.gz"
      sha256 "..."
    end
    on_intel do
      url "https://github.com/you/cc-insights/releases/download/v1.0.0/cc-insights-macos-x64.tar.gz"
      sha256 "..."
    end
  end

  def install
    libexec.install "share/cc-insights"
    bin.install_symlink libexec/"cc-insights/cc-insights"
  end
end
```

**Scoop (Windows):**
```json
{
  "version": "1.0.0",
  "architecture": {
    "64bit": {
      "url": "https://github.com/you/cc-insights/releases/download/v1.0.0/cc-insights-windows-x64.zip",
      "hash": "..."
    }
  },
  "bin": "cc-insights.exe",
  "shortcuts": [["cc-insights.exe", "CCInsights"]]
}
```

**Linux (AppImage):**
```bash
# Use appimage-builder or linuxdeploy
linuxdeploy --appdir AppDir \
  --executable dist/linux-x64/cc-insights \
  --desktop-file cc-insights.desktop \
  --icon-file icon.png \
  --output appimage
```

---

## GitHub Actions Workflow

```yaml
name: Release

on:
  push:
    tags: ['v*']

jobs:
  build-backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1

      - name: Build backend for all platforms
        run: |
          cd backend-ts
          bun install
          bun build ./src/index.ts --compile --target=bun-darwin-arm64 --outfile=../dist/backend-darwin-arm64
          bun build ./src/index.ts --compile --target=bun-darwin-x64 --outfile=../dist/backend-darwin-x64
          bun build ./src/index.ts --compile --target=bun-windows-x64 --outfile=../dist/backend-windows-x64.exe
          bun build ./src/index.ts --compile --target=bun-linux-x64 --outfile=../dist/backend-linux-x64
          bun build ./src/index.ts --compile --target=bun-linux-arm64 --outfile=../dist/backend-linux-arm64

      - uses: actions/upload-artifact@v4
        with:
          name: backend-binaries
          path: dist/

  build-flutter:
    needs: build-backend
    strategy:
      matrix:
        include:
          - os: macos-latest
            target: macos
            arch: arm64
          - os: macos-13
            target: macos
            arch: x64
          - os: windows-latest
            target: windows
            arch: x64
          - os: ubuntu-latest
            target: linux
            arch: x64

    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - uses: actions/download-artifact@v4
        with:
          name: backend-binaries
          path: dist/

      - name: Build Flutter
        run: |
          cd flutter_app
          flutter build ${{ matrix.target }} --release

      - name: Package
        run: ./scripts/package-${{ matrix.target }}.sh ${{ matrix.arch }}

      - uses: actions/upload-artifact@v4
        with:
          name: cc-insights-${{ matrix.target }}-${{ matrix.arch }}
          path: release/

  release:
    needs: build-flutter
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - uses: softprops/action-gh-release@v1
        with:
          files: |
            cc-insights-*/cc-insights-*
```

---

## CLI Usage (No Wrapper Needed)

The Flutter binary handles arguments directly:

```dart
// lib/main.dart
void main(List<String> args) {
  String? cwd;

  // Parse --cwd flag
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--cwd' && i + 1 < args.length) {
      cwd = args[i + 1];
    }
  }

  // Also support positional: cc-insights /path/to/dir
  if (cwd == null && args.isNotEmpty && !args[0].startsWith('-')) {
    cwd = args[0];
  }

  // Resolve relative paths
  if (cwd != null && !path.isAbsolute(cwd)) {
    cwd = path.absolute(cwd);
  }

  runApp(MyApp(initialCwd: cwd ?? Directory.current.path));
}
```

**User experience:**
```bash
brew install cc-insights        # Install
cc-insights .                   # Open in current directory
cc-insights ~/projects/myapp    # Open in specific directory
cc-insights --cwd /path/to/dir  # Explicit flag form
```

---

## Verification

1. **Backend compiles:** `bun build --compile` produces working binaries
2. **Flutter spawns backend:** App starts, backend process visible in Activity Monitor
3. **WebSocket connects:** Session creation works
4. **CLI works:** `cc-insights .` opens app in correct directory
5. **Cross-platform:** Test on macOS, Windows, Linux

---

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| TypeScript backend rewrite | 1-2 weeks |
| Flutter integration | 3-5 days |
| Build pipeline | 3-5 days |
| Distribution setup | 2-3 days |
| Testing & polish | 1 week |
| **Total** | **4-6 weeks** |

---

## Files to Modify

**Backend (new):**
- `backend-ts/src/index.ts` - WebSocket server entry
- `backend-ts/src/agent-manager.ts` - Port from Python
- `backend-ts/src/agent-tracker.ts` - Port from Python
- `backend-ts/src/hooks.ts` - Port from Python
- `backend-ts/src/message-types.ts` - Port from Python

**Flutter (modify):**
- `flutter_app/lib/main.dart` - CLI arg handling, backend spawning
- `flutter_app/lib/services/backend_service.dart` - New service
- `flutter_app/lib/services/websocket_service.dart` - Use dynamic port

**Build (new):**
- `scripts/build-backend.sh`
- `scripts/build-flutter.sh`
- `scripts/package-*.sh`
- `.github/workflows/release.yml`
