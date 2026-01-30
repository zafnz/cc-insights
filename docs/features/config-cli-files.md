# Configuration System - Config Files, CLI Arguments, and Environment Variables

## Overview

CC Insights uses a layered configuration system that allows settings to be specified through multiple sources with clear precedence rules. This provides flexibility for different use cases: defaults for new users, persistent settings via config files, temporary overrides via environment variables, and explicit control via CLI arguments.

## Configuration Sources (Precedence Order)

Configuration values are resolved in this order (lowest to highest priority):

```
1. Hard-coded defaults (in code)
2. Config file (~/.cc-insights/config.yaml)
3. Environment variables (CC_* prefix)
4. CLI arguments (--flag)
```

**Example:** If you have `model: haiku` in your config file, but run `cc-insights --model sonnet`, the CLI argument wins and Sonnet will be used.

## Configuration File

### Location

**macOS/Linux:** `~/.cc-insights/config.yaml`
**Windows:** `%USERPROFILE%\.cc-insights\config.yaml`

### Format (YAML)

```yaml
# CC Insights Configuration File

# Default working directory for new sessions
cwd: ~/projects

# Backend server port (if running standalone)
backend_port: 8765

# Log level: debug, info, warn, error
log_level: info

# Permission mode: default, acceptEdits, bypassPermissions, plan
permission_mode: default

# Default model: sonnet, opus, haiku
model: sonnet

# Anthropic API key (optional - prefer environment variable)
# api_key: sk-ant-...

# UI preferences
theme: dark  # light, dark, high-contrast-light, high-contrast-dark
autofocus_input: true

# Session defaults
max_output_buffer_lines: 100000
auto_scroll: true
show_timestamps: false
```

### Creating a Config File

The app will look for a config file but won't create one automatically. To create:

```bash
mkdir -p ~/.cc-insights
cat > ~/.cc-insights/config.yaml <<EOF
cwd: ~/projects
model: sonnet
permission_mode: acceptEdits
log_level: info
EOF
```

Or create from the UI (future feature - Settings → Export Config).

## Environment Variables

Environment variables use the `CC_` prefix (or `ANTHROPIC_API_KEY` for API key).

| Variable | Description | Example |
|----------|-------------|---------|
| `CC_CWD` | Default working directory | `CC_CWD=~/projects` |
| `CC_MODEL` | Default model | `CC_MODEL=opus` |
| `CC_PERMISSION_MODE` | Permission mode | `CC_PERMISSION_MODE=acceptEdits` |
| `CC_LOG_LEVEL` | Logging level | `CC_LOG_LEVEL=debug` |
| `CC_BACKEND_PORT` | Backend port | `CC_BACKEND_PORT=9000` |
| `ANTHROPIC_API_KEY` | API key (standard) | `ANTHROPIC_API_KEY=sk-ant-...` |

### Usage Examples

```bash
# Temporary override for single run
CC_MODEL=opus cc-insights ~/my-project

# Set in shell profile for persistent defaults
echo 'export CC_LOG_LEVEL=debug' >> ~/.zshrc

# Use different API key
ANTHROPIC_API_KEY=sk-ant-test-key ccgui

# Combine multiple env vars
CC_MODEL=haiku CC_PERMISSION_MODE=bypassPermissions ccgui
```

## CLI Arguments

Command-line arguments have the highest precedence and override all other sources.

### Syntax

```bash
cc-insights [options] [directory]
```

### Options

| Flag | Short | Description | Example |
|------|-------|-------------|---------|
| `--cwd <path>` | `-c` | Working directory | `--cwd ~/projects/myapp` |
| `--model <name>` | `-m` | Model selection | `--model opus` |
| `--permission-mode <mode>` | | Permission mode | `--permission-mode acceptEdits` |
| `--log-level <level>` | | Logging level | `--log-level debug` |
| `--backend-port <port>` | | Backend port | `--backend-port 9000` |
| `--api-key <key>` | | Anthropic API key | `--api-key sk-ant-...` |
| `--help` | `-h` | Show help | `--help` |
| `--version` | `-v` | Show version | `--version` |

### Positional Arguments

```bash
# Directory as first positional argument (shorthand for --cwd)
cc-insights ~/projects/myapp

# Equivalent to:
cc-insights --cwd ~/projects/myapp
```

### Usage Examples

```bash
# Open in current directory
cc-insights .

# Open specific directory
cc-insights ~/projects/my-app

# Override model
cc-insights --model haiku ~/projects

# Multiple options
cc-insights --model opus --permission-mode acceptEdits --cwd ~/work

# Bypass permissions (dangerous - will show warning in UI)
cc-insights --permission-mode bypassPermissions ~/trusted-project

# Debug mode
cc-insights --log-level debug .

# Show help
cc-insights --help

# Show version
cc-insights --version
```

## Precedence Examples

### Example 1: Model Selection

```yaml
# ~/.cc-insights/config.yaml
model: sonnet
```

```bash
# Shell
export CC_MODEL=opus

# Command
cc-insights --model haiku ~/project
```

**Result:** `haiku` (CLI wins over env var and config file)

### Example 2: Working Directory

```yaml
# ~/.cc-insights/config.yaml
cwd: ~/projects
```

```bash
# Command
cc-insights ~/work/specific-project
```

**Result:** `~/work/specific-project` (positional argument wins)

### Example 3: Layered Configuration

```yaml
# ~/.cc-insights/config.yaml
model: sonnet
permission_mode: default
log_level: info
cwd: ~/projects
```

```bash
# Shell
export CC_MODEL=opus
export CC_LOG_LEVEL=debug

# Command
cc-insights ~/work
```

**Result:**
- `model`: `opus` (env var overrides config)
- `permission_mode`: `default` (from config file)
- `log_level`: `debug` (env var overrides config)
- `cwd`: `~/work` (CLI argument overrides env and config)

## Implementation

### Package Dependencies

```yaml
# pubspec.yaml
dependencies:
  args: ^2.4.0        # CLI argument parsing
  yaml: ^3.1.0        # YAML config file parsing
  path: ^1.8.0        # Path manipulation
```

### Code Structure

```
lib/
└── config/
    ├── app_config.dart           # Main config class
    ├── config_loader.dart        # Load from file
    ├── env_loader.dart           # Load from environment
    └── cli_parser.dart           # Parse CLI args
```

### AppConfig Class

```dart
class AppConfig {
  final String cwd;
  final String? apiKey;
  final String backendPort;
  final String logLevel;
  final String permissionMode;
  final String model;
  final String theme;
  final bool autofocusInput;
  final int maxOutputBufferLines;
  final bool autoScroll;
  final bool showTimestamps;

  AppConfig({
    required this.cwd,
    this.apiKey,
    this.backendPort = '8765',
    this.logLevel = 'info',
    this.permissionMode = 'default',
    this.model = 'sonnet',
    this.theme = 'dark',
    this.autofocusInput = true,
    this.maxOutputBufferLines = 100000,
    this.autoScroll = true,
    this.showTimestamps = false,
  });

  /// Load config with full precedence chain
  static Future<AppConfig> load(List<String> args) async {
    // 1. Defaults (constructor defaults)
    var config = AppConfig(cwd: Directory.current.path);

    // 2. Config file
    config = await ConfigLoader.loadFromFile(config);

    // 3. Environment variables
    config = EnvLoader.loadFromEnvironment(config);

    // 4. CLI arguments
    config = CliParser.parseArguments(config, args);

    return config;
  }

  /// Save current config to file
  Future<void> save() async {
    // Write to ~/.cc-insights/config.yaml
  }
}
```

### main.dart Integration

```dart
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load configuration
  final config = await AppConfig.load(args);

  // Validate critical settings
  if (config.permissionMode == 'bypassPermissions') {
    // Show warning in UI
  }

  // Start app with config
  runApp(MyApp(config: config));
}
```

## Validation and Error Handling

### Invalid Values

When invalid configuration values are encountered:

1. **Warning logged** to console and log file
2. **Fall back to default** for that specific setting
3. **App continues** to start (don't crash on bad config)

Example:
```yaml
# Bad config
model: invalid-model-name
```

**Behavior:**
```
Warning: Invalid model 'invalid-model-name', using default 'sonnet'
```

### Missing Config File

**Behavior:** Not an error. App uses defaults + env vars + CLI args.

### Malformed YAML

**Behavior:** Log warning, skip config file entirely, use defaults.

### Missing API Key

**Behavior:** App starts, but shows error when trying to create session. User must provide key via env var, config, or settings UI.

## Security Considerations

### API Key Storage

**Best Practice:**
```bash
# Recommended: Use environment variable
export ANTHROPIC_API_KEY=sk-ant-...

# Or: Store in config with restricted permissions
chmod 600 ~/.cc-insights/config.yaml
```

**Warning in UI:**
When detecting API key in config file, show warning:
> "API key found in config file. For better security, use the ANTHROPIC_API_KEY environment variable instead."

### Permission Mode Warnings

When `bypassPermissions` is detected (from any source), show prominent warning:

```
⚠️  DANGER: Bypass Permissions Mode Active
This mode auto-approves ALL operations without asking.
Only use if you fully trust the prompt and understand the risks.

Source: [Config File | Environment Variable | CLI Argument]
```

### File Permissions

On app first run, if creating config directory:
```bash
mkdir -p ~/.cc-insights
chmod 700 ~/.cc-insights  # User-only access
```

## Configuration UI (Future Feature)

### Settings Screen

A UI for managing configuration:

- **Current Values Tab**: Show resolved values with source indicator
  ```
  Model: sonnet [from: Config File]
  Permission Mode: acceptEdits [from: Environment Variable]
  Working Directory: ~/projects [from: CLI Argument]
  ```

- **Edit Config Tab**: Visual editor for config file
  - Validate on save
  - Show diffs before applying
  - Export/Import config

- **CLI Help Tab**: Show available CLI arguments and examples

### Settings Priority

When user changes settings in UI:
- **Runtime changes**: Apply immediately (e.g., theme)
- **Session defaults**: Save to config file for next run
- **CLI/Env overrides**: Show warning that these take precedence

## Testing

### Unit Tests

```dart
// test/config/app_config_test.dart
test('CLI args override environment variables', () async {
  // Mock env vars
  Platform.environment['CC_MODEL'] = 'opus';

  // Parse CLI with different value
  final config = await AppConfig.load(['--model', 'haiku']);

  expect(config.model, equals('haiku'));
});

test('Environment variables override config file', () async {
  // Create temp config with model: sonnet
  // Set env var CC_MODEL=opus
  // Load config
  // Assert model == opus
});

test('Config file values used when no overrides', () async {
  // Create config file
  // Load without env vars or CLI args
  // Assert values from file
});
```

### Integration Tests

```bash
# Test CLI parsing
flutter test test/config/

# Test with actual config file
flutter run --dart-entrypoint-args="--cwd /tmp/test --model haiku"
```

## Migration Notes

### Current Implementation

Currently, the app only supports `--cwd` via `--dart-entrypoint-args`:
```bash
flutter run -d macos --dart-entrypoint-args="--cwd /path/to/project"
```

### After This Feature

Full CLI support:
```bash
cc-insights --cwd /path/to/project --model opus --permission-mode acceptEdits
```

## Related Issues

- Issue #1: Add project configuration options to initial prompt
- Issue #6: Restructure project directories
- Issue #9: Add theme support for light/dark/high-contrast modes

## Future Enhancements

1. **Config Profiles**: Multiple named configs (e.g., `cc-insights --profile work`)
2. **Project-local Config**: `.cc-insights.yaml` in project root
3. **Config Validation**: Schema validation with helpful error messages
4. **Config Migration**: Auto-migrate from old config format versions
5. **Import/Export**: Share configs between machines
6. **Environment Detection**: Auto-detect best defaults (e.g., model based on task complexity)
