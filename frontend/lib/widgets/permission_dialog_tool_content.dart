part of 'permission_dialog.dart';

// =============================================================================
// Tool Content Widgets
// =============================================================================

class _ToolContent extends StatelessWidget {
  const _ToolContent({
    required this.permission,
    required this.provider,
  });

  final sdk.PermissionRequest permission;
  final BackendProvider? provider;

  @override
  Widget build(BuildContext context) {
    final toolInput = permission.toolInput;
    final isCodex = provider == BackendProvider.codex;

    final baseContent = switch (permission.toolName) {
      'Bash' => _BashContent(input: toolInput),
      'Write' => _WriteContent(input: toolInput),
      'FileChange' => _FileChangeContent(input: toolInput),
      'Edit' => _EditContent(input: toolInput),
      _ => _GenericContent(input: toolInput),
    };

    if (isCodex) {
      return Column(
        key: PermissionDialogKeys.content,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          baseContent,
          if (toolInput['commandActions'] != null) ...[
            const SizedBox(height: 8),
            _CommandActionsRow(commandActions: toolInput['commandActions']),
          ],
          if (permission.decisionReason != null) ...[
            const SizedBox(height: 8),
            _ReasonRow(reason: permission.decisionReason!),
          ],
        ],
      );
    }

    return baseContent;
  }
}

class _BashContent extends StatelessWidget {
  const _BashContent({required this.input});

  final Map<String, dynamic> input;

  @override
  Widget build(BuildContext context) {
    final command = input['command'] as String? ?? '';
    final description = input['description'] as String?;

    return Column(
      key: PermissionDialogKeys.content,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null) ...[
          Text(
            description,
            style: textStyle(
              fontSize: PermissionFontSizes.description,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          key: PermissionDialogKeys.bashCommand,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            '\$ $command',
            style: monoStyle(
              fontSize: PermissionFontSizes.commandText,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _WriteContent extends StatelessWidget {
  const _WriteContent({required this.input});

  final Map<String, dynamic> input;

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final content = input['content'] as String? ?? '';
    final lineCount = '\n'.allMatches(content).length + 1;
    final truncatedContent = _truncate(content, 500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'File: $filePath',
          style: monoStyle(fontSize: PermissionFontSizes.filePath),
        ),
        const SizedBox(height: 4),
        _ScrollableCodeBox(
          content: truncatedContent,
          lineCount: lineCount,
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}

class _FileChangeContent extends StatelessWidget {
  const _FileChangeContent({required this.input});

  final Map<String, dynamic> input;

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final paths = (input['paths'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();
    final content = input['content'] as String? ?? '';
    final lineCount =
        content.isEmpty ? 0 : '\n'.allMatches(content).length + 1;
    final truncatedContent = _truncate(content, 500);

    final displayPaths =
        paths != null && paths.length > 1 ? paths : [filePath];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final path in displayPaths)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SelectableText(
              'File: $path',
              style: monoStyle(fontSize: PermissionFontSizes.filePath),
            ),
          ),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 4),
          _ScrollableCodeBox(
            content: truncatedContent,
            lineCount: lineCount,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ],
      ],
    );
  }
}

class _EditContent extends StatelessWidget {
  const _EditContent({required this.input});

  final Map<String, dynamic> input;

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'File: $filePath',
          style: monoStyle(fontSize: PermissionFontSizes.filePath),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  _truncate(oldString, 200),
                  style: monoStyle(fontSize: PermissionFontSizes.diffContent),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  _truncate(newString, 200),
                  style: monoStyle(fontSize: PermissionFontSizes.diffContent),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GenericContent extends StatelessWidget {
  const _GenericContent({required this.input});

  final Map<String, dynamic> input;

  @override
  Widget build(BuildContext context) {
    final details = input.entries
        .map((e) => '${e.key}: ${_truncate(e.value?.toString() ?? '', 100)}')
        .join('\n');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        details,
        style: monoStyle(fontSize: PermissionFontSizes.genericContent),
      ),
    );
  }
}

class _CommandActionsRow extends StatelessWidget {
  const _CommandActionsRow({required this.commandActions});

  final dynamic commandActions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actions = commandActions is List
        ? commandActions.map((a) => a.toString()).join(', ')
        : commandActions.toString();

    return Row(
      key: PermissionDialogKeys.commandActions,
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Text(
          'Actions: ',
          style: textStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          actions,
          style: textStyle(
            fontSize: 11,
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      key: PermissionDialogKeys.reason,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            reason,
            style: textStyle(
              fontSize: 11,
              color: colorScheme.onSurface,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
