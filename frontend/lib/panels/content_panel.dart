import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/selection_state.dart';
import 'conversation_panel.dart';
import 'create_worktree_panel.dart';
import 'panel_wrapper.dart';

/// Content panel - displays either conversation or create worktree form.
///
/// Uses [SelectionState.contentPanelMode] to determine which view to show.
class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final selection = context.watch<SelectionState>();

    return switch (selection.contentPanelMode) {
      ContentPanelMode.conversation => const PanelWrapper(
        title: 'Conversation',
        icon: Icons.chat_bubble_outline,
        child: ConversationPanel(),
      ),
      ContentPanelMode.createWorktree => const PanelWrapper(
        title: 'Create Worktree',
        icon: Icons.account_tree,
        child: CreateWorktreePanel(),
      ),
    };
  }
}
