import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_config.dart';
import '../services/cli_availability_service.dart';
import '../services/runtime_config.dart';
import '../services/settings_service.dart';

// =============================================================================
// Data types
// =============================================================================

/// Status of a single onboarding scan target.
enum _ScanStatus { scanning, found, notFound }

/// An onboarding scan target — one row in the scanning/results list.
class _ScanTarget {
  _ScanTarget({
    required this.key,
    required this.name,
    required this.probeExecutable,
    required this.driver,
    required this.color,
    this.autoScan = true,
  });

  /// Unique key (e.g., "claude", "codex", "gemini", "acpCompatible").
  final String key;

  /// Display name.
  final String name;

  /// Executable name to probe (e.g., "claude", "codex", "gemini").
  /// Null for targets that can't be auto-detected (ACP Compatible).
  final String? probeExecutable;

  /// Driver type for creating AgentConfig entries.
  final String driver;

  /// Brand color for the icon background.
  final Color color;

  /// Whether this target should be auto-scanned. False for ACP Compatible.
  final bool autoScan;

  // Mutable scan state
  _ScanStatus status = _ScanStatus.scanning;
  String? resolvedPath;
}

/// Which phase of onboarding is currently displayed.
enum _OnboardingPhase { scanning, results, agentSetup, advanced }

// =============================================================================
// Known scan targets
// =============================================================================

/// The canonical onboarding scan targets, independent of user config.
List<_ScanTarget> _createScanTargets() => [
      _ScanTarget(
        key: 'claude',
        name: 'Claude',
        probeExecutable: 'claude',
        driver: 'claude',
        color: const Color(0xFFD0BCFF), // primary / deep purple
      ),
      _ScanTarget(
        key: 'codex',
        name: 'Codex',
        probeExecutable: 'codex',
        driver: 'codex',
        color: const Color(0xFF4CAF50), // green
      ),
      _ScanTarget(
        key: 'gemini',
        name: 'Gemini CLI',
        probeExecutable: 'gemini',
        driver: 'acp',
        color: const Color(0xFF2196F3), // blue
      ),
      _ScanTarget(
        key: 'acpCompatible',
        name: 'ACP Compatible',
        probeExecutable: null,
        driver: 'acp',
        color: const Color(0xFFFF9800), // orange
        autoScan: false,
      ),
    ];

// =============================================================================
// Install instructions per agent
// =============================================================================

class _InstallInfo {
  const _InstallInfo({
    required this.commands,
    required this.docsLabel,
    required this.docsUrl,
    required this.placeholder,
  });

  final List<String> commands;
  final String docsLabel;
  final String docsUrl;
  final String placeholder;
}

const _installInfoMap = <String, _InstallInfo>{
  'claude': _InstallInfo(
    commands: [
      'brew install --cask claude-code',
      'curl -fsSL https://claude.ai/install.sh | bash',
    ],
    docsLabel: 'Learn more at code.claude.com/docs',
    docsUrl: 'https://code.claude.com/docs/en/overview',
    placeholder: '/usr/local/bin/claude',
  ),
  'codex': _InstallInfo(
    commands: ['npm install -g @openai/codex'],
    docsLabel: 'Learn more at github.com/openai/codex',
    docsUrl: 'https://github.com/openai/codex',
    placeholder: '/usr/local/bin/codex',
  ),
  'gemini': _InstallInfo(
    commands: ['npm install -g @google/gemini-cli'],
    docsLabel: 'Learn more at github.com/google/gemini-cli',
    docsUrl: 'https://github.com/google/gemini-cli',
    placeholder: '/usr/local/bin/gemini',
  ),
  'acpCompatible': _InstallInfo(
    commands: [],
    docsLabel: '',
    docsUrl: '',
    placeholder: '/path/to/acp-compatible-cli',
  ),
};

// =============================================================================
// OnboardingScreen
// =============================================================================

/// First-run onboarding screen that scans for AI agent CLIs.
///
/// Replaces the old [CliRequiredScreen]. Shows a scanning phase, then results
/// with found/not-found status, and allows the user to set up missing agents.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.cliAvailability,
    required this.settingsService,
    required this.onComplete,
    this.onCancel,
  });

  final CliAvailabilityService cliAvailability;
  final SettingsService settingsService;

  /// Called when the user clicks Continue after onboarding.
  final VoidCallback onComplete;

  /// Called when the user cancels during scanning.
  final VoidCallback? onCancel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _OnboardingPhase _phase = _OnboardingPhase.scanning;
  late List<_ScanTarget> _targets;

  /// Which target is selected for the agent setup sub-screen.
  _ScanTarget? _setupTarget;

  @override
  void initState() {
    super.initState();
    _targets = _createScanTargets();
    _startScanning();
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  Future<void> _startScanning() async {
    // Mark non-scannable targets immediately
    for (final target in _targets) {
      if (!target.autoScan) {
        target.status = _ScanStatus.notFound;
      }
    }

    // Run all probes in parallel
    final futures = <Future<void>>[];
    for (final target in _targets) {
      if (!target.autoScan) continue;
      futures.add(_probeTarget(target));
    }

    await Future.wait(futures);

    if (mounted) {
      setState(() => _phase = _OnboardingPhase.results);
    }
  }

  Future<void> _probeTarget(_ScanTarget target) async {
    final (found, resolvedPath) = await widget.cliAvailability.probeExecutable(
      target.probeExecutable!,
    );

    if (mounted) {
      setState(() {
        target.status = found ? _ScanStatus.found : _ScanStatus.notFound;
        target.resolvedPath = resolvedPath;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Results helpers
  // ---------------------------------------------------------------------------

  bool get _anyFound => _targets.any((t) => t.status == _ScanStatus.found);
  bool get _allScannableFound =>
      _targets.where((t) => t.autoScan).every((t) => t.status == _ScanStatus.found);
  bool get _claudeFound =>
      _targets.firstWhere((t) => t.key == 'claude').status == _ScanStatus.found;

  /// Whether at least one agent is available (found or manually configured).
  bool get _canContinue {
    // Any found via scan
    if (_anyFound) return true;
    // Any explicitly configured agents already in settings
    if (widget.settingsService.hasExplicitlyConfiguredAgents) return true;
    return false;
  }

  // ---------------------------------------------------------------------------
  // Continue action
  // ---------------------------------------------------------------------------

  Future<void> _handleContinue() async {
    // 1. Mark onboarding complete
    await widget.settingsService.setOnboardingCompleted(true);

    // 2. Always build the agent list from scan results so that agents whose
    //    CLI was not found never appear in Settings. If the user configured
    //    agents via the Advanced view, merge their customizations into the
    //    scan-based list.
    final agents = <AgentConfig>[];
    final existingAgents = widget.settingsService.hasExplicitlyConfiguredAgents
        ? widget.settingsService.availableAgents
        : <AgentConfig>[];

    for (final target in _targets) {
      if (target.status != _ScanStatus.found) continue;

      // Prefer any existing config for this driver (preserves user
      // customizations like custom CLI paths/args from the Advanced view).
      final existing = existingAgents
          .where((a) => a.driver == target.driver)
          .firstOrNull;
      if (existing != null) {
        // Update the resolved path from the scan if the user didn't
        // provide a custom one.
        final agentToAdd = existing.cliPath.isEmpty && target.resolvedPath != null
            ? existing.copyWith(cliPath: target.resolvedPath)
            : existing;
        agents.add(agentToAdd);
      } else {
        agents.add(_agentConfigForTarget(target));
      }
    }

    // Also include any agents that were explicitly added via Advanced but
    // don't match any standard scan target (e.g., custom ACP compatible).
    final scanDrivers = _targets.map((t) => t.driver).toSet();
    for (final existing in existingAgents) {
      if (!scanDrivers.contains(existing.driver) &&
          !agents.any((a) => a.id == existing.id)) {
        agents.add(existing);
      }
    }

    // If nothing was found via scan, use defaults so the user has something.
    if (agents.isEmpty) {
      agents.addAll(AgentConfig.defaults);
    }
    await widget.settingsService.setAvailableAgents(agents);

    // 3. Refresh configured-agent availability
    await widget.cliAvailability
        .checkAgents(RuntimeConfig.instance.agents);

    // 4. Notify parent
    widget.onComplete();
  }

  AgentConfig _agentConfigForTarget(_ScanTarget target) {
    // Try to match an existing default config for this driver
    final defaults = AgentConfig.defaults;
    final match = defaults.where((a) => a.driver == target.driver).firstOrNull;
    if (match != null) {
      return match.copyWith(
        cliPath: target.resolvedPath ?? '',
      );
    }
    return AgentConfig(
      id: AgentConfig.generateId(),
      name: target.name,
      driver: target.driver,
      cliPath: target.resolvedPath ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: switch (_phase) {
            _OnboardingPhase.scanning => _ScanningView(
                targets: _targets,
                onCancel: widget.onCancel,
              ),
            _OnboardingPhase.results => _ResultsView(
                targets: _targets,
                anyFound: _anyFound,
                allScannableFound: _allScannableFound,
                claudeFound: _claudeFound,
                canContinue: _canContinue,
                onContinue: _handleContinue,
                onSetupAgent: (target) {
                  setState(() {
                    _setupTarget = target;
                    _phase = _OnboardingPhase.agentSetup;
                  });
                },
                onAdvanced: () {
                  setState(() => _phase = _OnboardingPhase.advanced);
                },
              ),
            _OnboardingPhase.agentSetup => _AgentSetupView(
                target: _setupTarget!,
                cliAvailability: widget.cliAvailability,
                settingsService: widget.settingsService,
                onBack: () {
                  setState(() => _phase = _OnboardingPhase.results);
                },
              ),
            _OnboardingPhase.advanced => _AdvancedSetupView(
                settingsService: widget.settingsService,
                cliAvailability: widget.cliAvailability,
                targets: _targets,
                onDone: () async {
                  // Re-probe onboarding targets to update results
                  for (final target in _targets) {
                    if (!target.autoScan) continue;
                    await _probeTarget(target);
                  }
                  if (mounted) {
                    setState(() => _phase = _OnboardingPhase.results);
                  }
                },
              ),
          },
        ),
      ),
    );
  }
}

// =============================================================================
// Phase 1: Scanning View
// =============================================================================

class _ScanningView extends StatelessWidget {
  const _ScanningView({
    required this.targets,
    this.onCancel,
  });

  final List<_ScanTarget> targets;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 56,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Setting up for the first time',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Looking for AI agents on your system...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            // Agent rows (only scannable ones during scanning)
            ...targets
                .where((t) => t.autoScan)
                .map((t) => _AgentRow(target: t)),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Phase 2: Results View
// =============================================================================

class _ResultsView extends StatelessWidget {
  const _ResultsView({
    required this.targets,
    required this.anyFound,
    required this.allScannableFound,
    required this.claudeFound,
    required this.canContinue,
    required this.onContinue,
    required this.onSetupAgent,
    required this.onAdvanced,
  });

  final List<_ScanTarget> targets;
  final bool anyFound;
  final bool allScannableFound;
  final bool claudeFound;
  final bool canContinue;
  final VoidCallback onContinue;
  final void Function(_ScanTarget) onSetupAgent;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Determine variant
    final IconData headerIcon;
    final Color headerColor;
    final String title;
    final String subtitle;

    if (!anyFound) {
      // Variant A: None found
      headerIcon = Icons.search_off;
      headerColor = Colors.orange;
      title = 'No AI agents found';
      subtitle = 'Select one or more to set up:';
    } else if (!claudeFound) {
      // Variant B: Some found, Claude missing
      headerIcon = Icons.manage_search;
      headerColor = Colors.orange;
      title = 'Found some AI agents';
      subtitle =
          'Agents with a tick were found on your system. Click others to set them up.';
    } else if (allScannableFound) {
      // All scannable found
      headerIcon = Icons.check_circle;
      headerColor = Colors.green;
      title = 'Found some AI agents';
      subtitle = 'All known agents were found on your system.';
    } else {
      // Variant C: Some/all found, Claude present
      headerIcon = Icons.check_circle;
      headerColor = Colors.green;
      title = 'Found some AI agents';
      subtitle =
          'Agents with a tick were found on your system. Click others to set them up.';
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(headerIcon, size: 56, color: headerColor),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            // All agent rows including ACP Compatible
            ...targets.map(
              (t) => _AgentRow(
                target: t,
                onTap: t.status != _ScanStatus.found
                    ? () => onSetupAgent(t)
                    : null,
              ),
            ),
            // Warning banner when Claude is missing but others found
            if (anyFound && !claudeFound) ...[
              const SizedBox(height: 24),
              _WarningBanner(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Claude has not been found',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text:
                          ', but other agents have. You can run this app without Claude, '
                          "but currently it's recommended to have Claude as the app "
                          'works best with Claude.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onAdvanced,
                  child: const Text('Advanced...'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: canContinue ? onContinue : null,
                  child: const Text('Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Warning Banner
// =============================================================================

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final InlineSpan text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber, size: 20, color: Colors.orange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Agent Row (shared by scanning & results)
// =============================================================================

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.target,
    this.onTap,
  });

  final _ScanTarget target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isFound = target.status == _ScanStatus.found;
    final isScanning = target.status == _ScanStatus.scanning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isFound
                    ? Colors.green.withValues(alpha: 0.3)
                    : colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                // Agent icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: target.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    size: 18,
                    color: target.color,
                  ),
                ),
                const SizedBox(width: 12),
                // Name and status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isFound
                              ? Colors.green
                              : colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                // Trailing indicator
                if (isScanning)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else if (isFound)
                  const Icon(Icons.check_circle, color: Colors.green, size: 22)
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusText {
    return switch (target.status) {
      _ScanStatus.scanning => 'Scanning...',
      _ScanStatus.found => 'Found at ${target.resolvedPath ?? 'system PATH'}',
      _ScanStatus.notFound =>
        target.key == 'acpCompatible' ? 'Not configured' : 'Not found',
    };
  }
}

// =============================================================================
// Phase 3: Agent Setup View
// =============================================================================

class _AgentSetupView extends StatefulWidget {
  const _AgentSetupView({
    required this.target,
    required this.cliAvailability,
    required this.settingsService,
    required this.onBack,
  });

  final _ScanTarget target;
  final CliAvailabilityService cliAvailability;
  final SettingsService settingsService;
  final VoidCallback onBack;

  @override
  State<_AgentSetupView> createState() => _AgentSetupViewState();
}

class _AgentSetupViewState extends State<_AgentSetupView> {
  final _pathController = TextEditingController();
  String? _error;
  bool _verifying = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select ${widget.target.name} CLI executable',
      type: FileType.any,
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        _pathController.text = path;
      }
    }
  }

  /// Parses a command-like string into (executable, args).
  (String, String) _parsePathAndArgs(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return ('', '');

    // Handle quoted executable path
    if (trimmed.startsWith('"') || trimmed.startsWith("'")) {
      final quote = trimmed[0];
      final endQuote = trimmed.indexOf(quote, 1);
      if (endQuote > 0) {
        final path = trimmed.substring(1, endQuote);
        final rest = trimmed.substring(endQuote + 1).trim();
        return (path, rest);
      }
    }

    // Split on first space
    final spaceIndex = trimmed.indexOf(' ');
    if (spaceIndex < 0) return (trimmed, '');
    return (trimmed.substring(0, spaceIndex), trimmed.substring(spaceIndex + 1).trim());
  }

  Future<void> _verifyAndContinue() async {
    final rawInput = _pathController.text.trim();
    if (rawInput.isEmpty) {
      setState(() => _error = 'Please enter a path to the ${widget.target.name} CLI.');
      return;
    }

    setState(() {
      _error = null;
      _verifying = true;
    });

    final (path, args) = _parsePathAndArgs(rawInput);

    // Save the custom path to an agent config for this target
    final agents = widget.settingsService.availableAgents;
    var agent = agents.where((a) => a.driver == widget.target.driver).firstOrNull;
    if (agent != null) {
      await widget.settingsService.updateAgent(
        agent.copyWith(cliPath: path, cliArgs: args.isNotEmpty ? args : null),
      );
    } else {
      agent = AgentConfig(
        id: AgentConfig.generateId(),
        name: widget.target.name,
        driver: widget.target.driver,
        cliPath: path,
        cliArgs: args,
      );
      await widget.settingsService.addAgent(agent);
    }

    // Probe with the custom path
    final (found, resolvedPath) =
        await widget.cliAvailability.probeExecutable(
      widget.target.probeExecutable ?? path,
      customPath: path,
    );

    if (!mounted) return;

    if (found) {
      widget.target.status = _ScanStatus.found;
      widget.target.resolvedPath = resolvedPath ?? path;
      widget.onBack();
    } else {
      setState(() {
        _error = 'Could not find a valid ${widget.target.name} CLI at "$path".';
        _verifying = false;
      });
    }
  }

  Future<void> _retryDetection() async {
    setState(() {
      _error = null;
      _verifying = true;
    });

    final execName = widget.target.probeExecutable;
    if (execName == null) {
      setState(() {
        _error = 'No standard executable for ${widget.target.name}. Please provide a path.';
        _verifying = false;
      });
      return;
    }

    final (found, resolvedPath) =
        await widget.cliAvailability.probeExecutable(execName);

    if (!mounted) return;

    if (found) {
      widget.target.status = _ScanStatus.found;
      widget.target.resolvedPath = resolvedPath;
      widget.onBack();
    } else {
      setState(() {
        _error = '${widget.target.name} CLI still not found in PATH.';
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);
    final info = _installInfoMap[widget.target.key];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Back button
            InkWell(
              onTap: widget.onBack,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back to agent selection',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Agent header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.target.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    size: 24,
                    color: widget.target.color,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Set Up ${widget.target.name}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Install the ${widget.target.name} CLI or provide the path to an existing installation.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Install instructions (if any)
            if (info != null && info.commands.isNotEmpty) ...[
              Text(
                'Install ${widget.target.name} CLI',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < info.commands.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'or',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _CommandBlock(
                  command: info.commands[i],
                  mono: mono,
                  colorScheme: colorScheme,
                ),
              ],
              if (info.docsUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => launchUrl(Uri.parse(info.docsUrl)),
                  child: Text(
                    info.docsLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],

            // Manual path entry
            Text(
              'Or specify the path manually',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    style: mono,
                    decoration: InputDecoration(
                      hintText: info?.placeholder ?? '/path/to/executable',
                      hintStyle: mono.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _verifyAndContinue(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Browse...',
                  onPressed: _pickFile,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tip: If you include arguments (e.g., "${info?.placeholder ?? '/usr/bin/cli'} --model X"), '
              "they'll be separated automatically.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                fontFamily: mono.fontFamily,
                fontSize: 11,
              ),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],

            // Actions
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _verifying ? null : _retryDetection,
                  child: const Text('Retry Detection'),
                ),
                FilledButton(
                  onPressed: _verifying ? null : _verifyAndContinue,
                  child: _verifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Phase 4: Advanced Setup View
// =============================================================================

class _AdvancedSetupView extends StatefulWidget {
  const _AdvancedSetupView({
    required this.settingsService,
    required this.cliAvailability,
    required this.targets,
    required this.onDone,
  });

  final SettingsService settingsService;
  final CliAvailabilityService cliAvailability;
  final List<_ScanTarget> targets;
  final VoidCallback onDone;

  @override
  State<_AdvancedSetupView> createState() => _AdvancedSetupViewState();
}

class _AdvancedSetupViewState extends State<_AdvancedSetupView> {
  String? _selectedAgentId;

  // Form controllers
  final _nameController = TextEditingController();
  final _cliPathController = TextEditingController();
  final _cliArgsController = TextEditingController();
  final _envController = TextEditingController();
  String _driver = 'claude';
  String _defaultModel = '';
  String _defaultPermissions = 'default';

  List<AgentConfig> get _agents => widget.settingsService.availableAgents;

  @override
  void initState() {
    super.initState();
    if (_agents.isNotEmpty) {
      _selectedAgentId = _agents.first.id;
      _loadAgent(_agents.first);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cliPathController.dispose();
    _cliArgsController.dispose();
    _envController.dispose();
    super.dispose();
  }

  void _loadAgent(AgentConfig agent) {
    _nameController.text = agent.name;
    _cliPathController.text = agent.cliPath;
    _cliArgsController.text = agent.cliArgs;
    _envController.text = agent.environment;
    _driver = agent.driver;
    _defaultModel = agent.defaultModel;
    _defaultPermissions = agent.defaultPermissions;
  }

  Future<void> _saveCurrentAgent() async {
    if (_selectedAgentId == null) return;
    final agent = widget.settingsService.agentById(_selectedAgentId!);
    if (agent == null) return;

    final updated = agent.copyWith(
      name: _nameController.text.trim(),
      driver: _driver,
      cliPath: _cliPathController.text.trim(),
      cliArgs: _cliArgsController.text.trim(),
      environment: _envController.text,
      defaultModel: _defaultModel,
      defaultPermissions: _defaultPermissions,
    );
    await widget.settingsService.updateAgent(updated);
  }

  Future<void> _addAgent() async {
    final agent = AgentConfig(
      id: AgentConfig.generateId(),
      name: 'New Agent',
      driver: 'claude',
    );
    await widget.settingsService.addAgent(agent);
    setState(() {
      _selectedAgentId = agent.id;
      _loadAgent(agent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final agents = _agents;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: Container(
        height: 550,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            // Sidebar
            Container(
              width: 180,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Row(
                      children: [
                        Icon(Icons.smart_toy, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Agents',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  // Agent list
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8),
                      children: [
                        for (final agent in agents)
                          _SidebarAgentItem(
                            agent: agent,
                            selected: agent.id == _selectedAgentId,
                            onTap: () async {
                              await _saveCurrentAgent();
                              setState(() {
                                _selectedAgentId = agent.id;
                                _loadAgent(agent);
                              });
                            },
                          ),
                        // Add New button
                        InkWell(
                          onTap: _addAgent,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 14, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Add New',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Done button
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await _saveCurrentAgent();
                          widget.onDone();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content: agent config form
            Expanded(
              child: _selectedAgentId == null
                  ? const Center(child: Text('Select an agent'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildForm(context),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _nameController.text.isEmpty ? 'Agent' : _nameController.text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Configure the ${_nameController.text} agent backend',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // Name
        _FormRow(
          label: 'Name',
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),

        // Driver
        _FormRow(
          label: 'Driver',
          child: DropdownButtonFormField<String>(
            initialValue: _driver,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'claude', child: Text('claude')),
              DropdownMenuItem(value: 'codex', child: Text('codex')),
              DropdownMenuItem(value: 'acp', child: Text('acp')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _driver = v);
            },
          ),
        ),

        // CLI Path
        _FormRow(
          label: 'CLI Path',
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cliPathController,
                  style: mono,
                  decoration: InputDecoration(
                    hintText: 'Auto-detect',
                    hintStyle: mono.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18),
                tooltip: 'Browse...',
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    dialogTitle: 'Select CLI executable',
                    type: FileType.any,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final path = result.files.first.path;
                    if (path != null) {
                      _cliPathController.text = path;
                    }
                  }
                },
              ),
            ],
          ),
        ),

        // Args
        _FormRow(
          label: 'Args',
          child: TextField(
            controller: _cliArgsController,
            decoration: const InputDecoration(
              hintText: 'Optional',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
        ),

        // Environment
        _FormRow(
          label: 'Environment',
          child: TextField(
            controller: _envController,
            maxLines: 3,
            style: mono.copyWith(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'KEY=VALUE\nONE_PER_LINE',
              hintStyle: mono.copyWith(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),

        // Model
        _FormRow(
          label: 'Model',
          child: DropdownButtonFormField<String>(
            initialValue: _defaultModel.isEmpty ? '' : _defaultModel,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Default')),
              DropdownMenuItem(value: 'haiku', child: Text('Haiku 4.5')),
              DropdownMenuItem(value: 'sonnet', child: Text('Sonnet 4.5')),
              DropdownMenuItem(value: 'opus', child: Text('Opus 4.6')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _defaultModel = v);
            },
          ),
        ),

        // Permissions
        _FormRow(
          label: 'Permissions',
          child: DropdownButtonFormField<String>(
            initialValue: _defaultPermissions,
            isDense: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'default', child: Text('Default')),
              DropdownMenuItem(value: 'acceptEdits', child: Text('Accept Edits')),
              DropdownMenuItem(value: 'plan', child: Text('Plan')),
              DropdownMenuItem(value: 'bypassPermissions', child: Text('Bypass All')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _defaultPermissions = v);
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Sidebar Agent Item
// =============================================================================

class _SidebarAgentItem extends StatelessWidget {
  const _SidebarAgentItem({
    required this.agent,
    required this.selected,
    required this.onTap,
  });

  final AgentConfig agent;
  final bool selected;
  final VoidCallback onTap;

  Color get _dotColor {
    return switch (agent.driver) {
      'claude' => const Color(0xFFD0BCFF),
      'codex' => const Color(0xFF4CAF50),
      'acp' => const Color(0xFF2196F3),
      _ => const Color(0xFF9E9E9E),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary.withValues(alpha: 0.1) : null,
          border: Border(
            left: BorderSide(
              width: 2,
              color: selected ? colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                agent.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Form Row (label + input)
// =============================================================================

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// =============================================================================
// Command Block (reused from CliRequiredScreen pattern)
// =============================================================================

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({
    required this.command,
    required this.mono,
    required this.colorScheme,
  });

  final String command;
  final TextStyle mono;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(command, style: mono),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: 'Copy to clipboard',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
