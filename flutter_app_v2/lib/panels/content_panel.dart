import 'package:flutter/material.dart';

import 'conversation_panel.dart';
import 'panel_wrapper.dart';

/// Conversation panel - displays the selected conversation's output entries.
///
/// Uses the [ConversationPanel] widget with correct "stick to bottom"
/// scroll behavior and functional message input.
class ContentPanel extends StatelessWidget {
  const ContentPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelWrapper(
      title: 'Conversation',
      icon: Icons.chat_bubble_outline,
      child: ConversationPanel(),
    );
  }
}
