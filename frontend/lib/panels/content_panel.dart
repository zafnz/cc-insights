import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/selection_state.dart';
import 'conversation_panel.dart';
import 'create_worktree_panel.dart';
import 'panel_wrapper.dart';
import 'project_settings_panel.dart';

/// Content panel - displays conversation, create worktree form, or settings.
///
/// Uses [SelectionState.contentPanelMode] to determine which view to show.
class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();

    return switch (selection.contentPanelMode) {
      ContentPanelMode.conversation => _buildConversationPanel(context, selection),
      ContentPanelMode.createWorktree => const PanelWrapper(
        title: 'Create Worktree',
        icon: Icons.account_tree,
        child: CreateWorktreePanel(),
      ),
      ContentPanelMode.projectSettings => const PanelWrapper(
        title: 'Project Settings',
        icon: Icons.settings,
        child: ProjectSettingsPanel(),
      ),
    };
  }

  Widget _buildConversationPanel(BuildContext context, SelectionState selection) {
    final chat = selection.selectedChat;

    if (chat == null) {
      return const PanelWrapper(
        title: 'Conversation',
        icon: Icons.chat_bubble_outline,
        child: ConversationPanel(),
      );
    }

    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final conversation = chat.selectedConversation;

        // Build the title: "Conversation" or "Conversation - <name>"
        String title = 'Conversation';
        if (conversation != null) {
          if (conversation.isPrimary) {
            title = 'Conversation - ${chat.data.name}';
          } else {
            final subagentTitle = conversation.taskDescription ??
                'Subagent #${conversation.subagentNumber ?? '?'}';
            title = 'Conversation - $subagentTitle';
          }
        }

        return PanelWrapper(
          title: title,
          icon: Icons.chat_bubble_outline,
          child: const ConversationPanel(),
        );
      },
    );
  }
}
