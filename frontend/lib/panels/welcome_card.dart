import 'dart:developer' as developer;

import 'package:claude_sdk/claude_sdk.dart' as sdk;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat.dart';
import '../models/chat_model.dart';
import '../models/output_entry.dart';
import '../models/project.dart';
import '../models/worktree.dart';
import '../services/backend_service.dart';
import '../services/cli_availability_service.dart';
import '../services/project_restore_service.dart';
import '../services/runtime_config.dart';
import '../services/sdk_message_handler.dart';
import '../state/selection_state.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/message_input.dart';
import 'compact_dropdown.dart';
import 'conversation_header.dart';

/// Welcome card shown when no chat is selected.
///
/// Displays project info and invites the user to start chatting.
/// Includes model/permission selectors and a message input box at the bottom
/// that creates a new chat and sends the first message.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final project = context.watch<ProjectState>();
    final selection = context.watch<SelectionState>();
    final backendService = context.watch<BackendService>();
    final worktree = selection.selectedWorktree;
    final defaultModel = ChatModelCatalog.defaultForBackend(
      RuntimeConfig.instance.defaultBackend,
      RuntimeConfig.instance.defaultModel,
    );
    final defaultPermissionMode = PermissionMode.fromApiName(
      RuntimeConfig.instance.defaultPermissionMode,
    );

    Widget buildHeader() {
      final model = worktree?.welcomeModel ?? defaultModel;
      final caps = backendService.capabilitiesFor(model.backend);
      final isModelLoading =
          caps.supportsModelListing &&
          backendService.isModelListLoadingFor(model.backend);
      return _WelcomeHeader(
        model: model,
        caps: caps,
        permissionMode: worktree?.welcomePermissionMode ?? defaultPermissionMode,
        reasoningEffort: worktree?.welcomeReasoningEffort,
        isModelLoading: isModelLoading,
        onAgentChanged: (backendType) async {
          final backendService = context.read<BackendService>();
          await backendService.start(type: backendType);
          final error = backendService.errorFor(backendType);
          if (error != null) {
            if (context.mounted) showErrorSnackBar(context, error);
            return;
          }

          final model = ChatModelCatalog.defaultForBackend(backendType, null);
          worktree?.welcomeModel = model;
        },
        onModelChanged: (model) => worktree?.welcomeModel = model,
        onPermissionChanged: (mode) =>
            worktree?.welcomePermissionMode = mode,
        onReasoningChanged: (effort) =>
            worktree?.welcomeReasoningEffort = effort,
      );
    }

    return Column(
      children: [
        // Header with model/permission selectors
        if (worktree == null)
          buildHeader()
        else
          ListenableBuilder(
            listenable: worktree,
            builder: (context, _) => buildHeader(),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Project icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.primaryContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        size: 48,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Project name
                    Text(
                      project.data.name,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Worktree path
                    if (worktree != null)
                      Text(
                        worktree.data.worktreeRoot,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 24),
                    // Welcome message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Welcome to CC-Insights',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a new conversation by typing a message below, '
                            'or click "New Chat" in the sidebar to create a '
                            'chat.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Message input - creates a new chat on submit
        // Use worktree path in key so each worktree gets its own input
        MessageInput(
          key: ValueKey(
            'input-welcome-${worktree?.data.worktreeRoot ?? 'none'}',
          ),
          initialText: worktree?.welcomeDraftText ?? '',
          onTextChanged: (text) => worktree?.welcomeDraftText = text,
          onSubmit: (text, images, displayFormat) =>
              _createChatAndSendMessage(
                  context, worktree, text, images, displayFormat),
        ),
      ],
    );
  }

  /// Creates a new chat, selects it, and sends the first message.
  static Future<void> _createChatAndSendMessage(
    BuildContext context,
    WorktreeState? worktree,
    String text,
    List<AttachedImage> images,
    DisplayFormat displayFormat,
  ) async {
    if (text.trim().isEmpty && images.isEmpty) return;

    final selection = context.read<SelectionState>();
    if (worktree == null) return;

    final project = context.read<ProjectState>();
    final backend = context.read<BackendService>();
    final messageHandler = context.read<SdkMessageHandler>();
    final restoreService = context.read<ProjectRestoreService>();

    // Determine the chat name based on AI label setting
    final aiLabelsEnabled = RuntimeConfig.instance.aiChatLabelsEnabled;
    final String chatName;
    final bool isAutoGenerated;
    if (aiLabelsEnabled) {
      // Use message-based name as placeholder for AI-generated title
      chatName = _generateChatName(text);
      isAutoGenerated = true;
    } else {
      // Use sequential "Chat #N" naming
      chatName = 'Chat #${worktree.chats.length + 1}';
      isAutoGenerated = false;
    }

    // Create a new chat in the worktree
    final chat = ChatState.create(
      name: chatName,
      worktreeRoot: worktree.data.worktreeRoot,
      isAutoGeneratedName: isAutoGenerated,
    );

    // Apply the selected model, permission mode, and reasoning effort
    // from the worktree's welcome screen state
    chat.setModel(worktree.welcomeModel);
    chat.setPermissionMode(worktree.welcomePermissionMode);
    chat.setReasoningEffort(worktree.welcomeReasoningEffort);

    // Clear the welcome draft since it's being submitted as a chat
    worktree.welcomeDraftText = '';

    // Add the chat to the worktree and select it
    worktree.addChat(chat, select: true);
    selection.selectChat(chat);

    // Persist the new chat to projects.json (fire-and-forget with error logging)
    restoreService
        .addChatToWorktree(
          project.data.repoRoot,
          worktree.data.worktreeRoot,
          chat,
        )
        .catchError((error) {
      developer.log(
        'Failed to persist chat: $error',
        name: 'ConversationPanel',
        level: 900, // Warning level
      );
    });

    // Add the user's message
    final userEntry = UserInputEntry(
      timestamp: DateTime.now(),
      text: text,
      images: images,
      displayFormat: displayFormat,
    );
    chat.addEntry(userEntry);

    // Generate a better title for the chat (fire-and-forget)
    messageHandler.generateChatTitle(chat, text);

    // Start session with the first message (including images if attached)
    try {
      await chat.startSession(
        backend: backend,
        messageHandler: messageHandler,
        prompt: text,
        images: images,
      );
    } catch (e) {
      // Show error in conversation
      chat.addEntry(TextOutputEntry(
        timestamp: DateTime.now(),
        text: 'Failed to start session: $e',
        contentType: 'error',
      ));
    }
  }

  /// Generates a chat name from the first message.
  static String _generateChatName(String message) {
    // Take first 30 chars, truncate at word boundary if possible
    final trimmed = message.trim();
    if (trimmed.length <= 30) return trimmed;

    final truncated = trimmed.substring(0, 30);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > 15) {
      return '${truncated.substring(0, lastSpace)}...';
    }
    return '$truncated...';
  }
}

/// Header for the welcome card with model/permission selectors.
///
/// Similar layout to ConversationHeader but for the welcome state.
class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({
    required this.model,
    required this.caps,
    required this.permissionMode,
    required this.reasoningEffort,
    required this.onModelChanged,
    required this.onPermissionChanged,
    required this.onAgentChanged,
    required this.onReasoningChanged,
    required this.isModelLoading,
  });

  final ChatModel model;
  final sdk.BackendCapabilities caps;
  final PermissionMode permissionMode;
  final sdk.ReasoningEffort? reasoningEffort;
  final ValueChanged<ChatModel> onModelChanged;
  final ValueChanged<PermissionMode> onPermissionChanged;
  final ValueChanged<sdk.BackendType> onAgentChanged;
  final ValueChanged<sdk.ReasoningEffort?> onReasoningChanged;
  final bool isModelLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          // Left side: "New Chat" label and dropdowns
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_comment_outlined,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'New Chat',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Builder(
                    builder: (context) {
                      final cliAvailability =
                          context.watch<CliAvailabilityService>();
                      final agentItems = cliAvailability.codexAvailable
                          ? const ['Claude', 'Codex']
                          : const ['Claude'];
                      return CompactDropdown(
                        value: agentLabel(model.backend),
                        items: agentItems,
                        tooltip: 'Agent',
                        isEnabled: agentItems.length > 1,
                        onChanged: (value) {
                          onAgentChanged(backendFromAgent(value));
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  Builder(
                    builder: (context) {
                      final models = ChatModelCatalog.forBackend(model.backend);
                      final selected = models.firstWhere(
                        (m) => m.id == model.id,
                        orElse: () => model,
                      );
                      return CompactDropdown(
                        value: selected.label,
                        items: models.map((m) => m.label).toList(),
                        isLoading: isModelLoading,
                        tooltip: 'Model',
                        onChanged: (value) {
                          final next = models.firstWhere(
                            (m) => m.label == value,
                            orElse: () => selected,
                          );
                          onModelChanged(next);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  CompactDropdown(
                    value: permissionMode.label,
                    items: PermissionMode.values.map((m) => m.label).toList(),
                    tooltip: 'Permissions',
                    onChanged: (value) {
                      final selected = PermissionMode.values.firstWhere(
                        (m) => m.label == value,
                        orElse: () => PermissionMode.defaultMode,
                      );
                      onPermissionChanged(selected);
                    },
                  ),
                  // Reasoning effort dropdown (capability-gated)
                  if (caps.supportsReasoningEffort) ...[
                    const SizedBox(width: 8),
                    CompactDropdown(
                      value: reasoningEffort?.label ?? 'Default',
                      items: reasoningEffortItems,
                      tooltip: 'Reasoning',
                      onChanged: (value) {
                        final effort = reasoningEffortFromLabel(value);
                        onReasoningChanged(effort);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Right side: empty for new chat (no usage data yet)
        ],
      ),
    );
  }
}
