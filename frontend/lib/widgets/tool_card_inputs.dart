import 'package:code_highlight_view/code_highlight_view.dart';
import 'package:code_highlight_view/themes/atom-one-dark.dart';
import 'package:code_highlight_view/themes/atom-one-light.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/output_entry.dart';
import '../services/file_type_detector.dart';
import '../services/runtime_config.dart';
import 'click_to_scroll_container.dart';
import 'diff_view.dart';
import 'tool_card_shared.dart';

// -----------------------------------------------------------------------------
// Tool-specific input widgets
// -----------------------------------------------------------------------------

/// Renders Bash command input.
class BashInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const BashInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final command = input['command'] as String? ?? '';
    final description = input['description'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description != null) ...[
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
        ],
        ClickToScrollContainer(
          maxHeight: 200,
          padding: const EdgeInsets.all(8),
          backgroundColor: Colors.black87,
          borderRadius: BorderRadius.circular(4),
          child: SelectableText(
            '\$ $command',
            style: GoogleFonts.getFont(
              monoFont,
              fontSize: 12,
              color: Colors.greenAccent,
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders Read tool input.
class ReadInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final String? projectDir;

  const ReadInputWidget({super.key, required this.input, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final offset = input['offset'];
    final limit = input['limit'];

    return FilePathWidget(
      filePath: filePath,
      icon: Icons.description,
      projectDir: projectDir,
      extraInfo: [
        if (offset != null) 'from line $offset',
        if (limit != null) '$limit lines',
      ],
    );
  }
}

/// Renders Write tool input with syntax highlighting.
class WriteInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final String? projectDir;

  const WriteInputWidget({super.key, required this.input, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final filePath = input['file_path'] as String? ?? '';
    final content = input['content'] as String? ?? '';
    final ext = FileTypeDetector.getFileExtension(filePath);
    final language = ext != null
        ? FileTypeDetector.getLanguageFromExtension(ext)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilePathWidget(
          filePath: filePath,
          icon: Icons.edit_document,
          projectDir: projectDir,
        ),
        const SizedBox(height: 4),
        ClickToScrollContainer(
          maxHeight: 300,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          child: language != null
              ? _buildHighlightedCode(context, content, language)
              : Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    content,
                    style: GoogleFonts.getFont(
                      RuntimeConfig.instance.monoFontFamily,
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHighlightedCode(
    BuildContext context,
    String content,
    String language,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;
    final theme = Map<String, TextStyle>.from(baseTheme);
    theme['root'] = const TextStyle(backgroundColor: Colors.transparent);

    return CodeHighlightView(
      content,
      language: language,
      theme: theme,
      isSelectable: true,
      padding: const EdgeInsets.all(8),
      textStyle: const TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 11,
        height: 1.4,
      ),
    );
  }
}

/// Renders Edit tool input with diff view.
class EditInputWidget extends StatelessWidget {
  final ToolUseOutputEntry entry;
  final String? projectDir;

  const EditInputWidget({super.key, required this.entry, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final input = entry.toolInput;
    final filePath = input['file_path'] as String? ?? '';
    final oldString = input['old_string'] as String? ?? '';
    final newString = input['new_string'] as String? ?? '';

    // Extract structuredPatch from the result if available
    List<Map<String, dynamic>>? structuredPatch;
    final result = entry.result;
    if (result is Map<String, dynamic>) {
      final patchData = result['structuredPatch'];
      if (patchData is List) {
        structuredPatch = patchData.cast<Map<String, dynamic>>();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilePathWidget(
          filePath: filePath,
          icon: Icons.edit,
          projectDir: projectDir,
        ),
        const SizedBox(height: 8),
        DiffView(
          oldText: oldString,
          newText: newString,
          structuredPatch: structuredPatch,
          maxHeight: 300,
        ),
      ],
    );
  }
}

/// Renders Glob tool input.
class GlobInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const GlobInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Row(
      children: [
        const Icon(Icons.search, size: 14, color: Colors.purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: pattern,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (path != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: path,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders Grep tool input.
class GrepInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const GrepInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final pattern = input['pattern'] as String? ?? '';
    final path = input['path'] as String?;
    final glob = input['glob'] as String?;
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Row(
      children: [
        const Icon(Icons.find_in_page, size: 14, color: Colors.purple),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '/',
                  style: GoogleFonts.getFont(monoFont, fontSize: 12),
                ),
                TextSpan(
                  text: pattern,
                  style: GoogleFonts.getFont(
                    monoFont,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: '/',
                  style: GoogleFonts.getFont(monoFont, fontSize: 12),
                ),
                if (glob != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: glob,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ] else if (path != null) ...[
                  const TextSpan(
                    text: ' in ',
                    style: TextStyle(fontSize: 11),
                  ),
                  TextSpan(
                    text: path,
                    style: GoogleFonts.getFont(
                      monoFont,
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders WebSearch tool input.
class WebSearchInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const WebSearchInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final query = input['query'] as String? ?? '';

    return Row(
      children: [
        const Icon(Icons.search, size: 14, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '"$query"',
            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }
}

/// Renders WebFetch tool input.
class WebFetchInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const WebFetchInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final url = input['url'] as String? ?? '';
    final prompt = input['prompt'] as String? ?? '';
    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.link, size: 14, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                url,
                style: GoogleFonts.getFont(
                  monoFont,
                  fontSize: 11,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        if (prompt.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Prompt: $prompt',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Renders Task tool input (subagent).
class TaskInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const TaskInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final description = input['description'] as String? ?? '';
    final prompt = input['prompt'] as String? ?? '';
    final subagentType = input['subagent_type'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree, size: 14, color: Colors.orange),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                subagentType,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (prompt.isNotEmpty) ...[
          const SizedBox(height: 4),
          ClickToScrollContainer(
            maxHeight: 100,
            padding: const EdgeInsets.all(8),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            child: SelectableText(
              prompt,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Renders AskUserQuestion tool input with optional result showing selected answers.
class AskUserQuestionInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;
  final dynamic result;

  const AskUserQuestionInputWidget({
    super.key,
    required this.input,
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    final questions = input['questions'] as List<dynamic>? ?? [];

    // Extract answers from result if available
    Map<String, String>? answers;
    if (result is Map<String, dynamic>) {
      final answersData = result['answers'];
      if (answersData is Map) {
        answers = Map<String, String>.from(
          answersData.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < questions.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _QuestionItemWidget(
            question: questions[i] as Map<String, dynamic>,
            selectedAnswer: answers?[
                (questions[i] as Map<String, dynamic>)['question'] as String?],
          ),
        ],
      ],
    );
  }
}

/// Renders a single question item with optional selected answer display.
class _QuestionItemWidget extends StatelessWidget {
  final Map<String, dynamic> question;
  final String? selectedAnswer;

  const _QuestionItemWidget({
    required this.question,
    this.selectedAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final questionText = question['question'] as String? ?? '';
    final header = question['header'] as String? ?? '';
    final options = question['options'] as List<dynamic>? ?? [];
    final multiSelect = question['multiSelect'] as bool? ?? false;

    // Parse selected answers (may be comma-separated for multi-select)
    final selectedLabels = selectedAnswer?.split(', ').toSet() ?? <String>{};

    // Check if answer is a custom "Other" response (not matching any option)
    final optionLabels =
        options.map((o) => (o as Map<String, dynamic>)['label'] as String?).toSet();
    final isOtherAnswer = selectedAnswer != null &&
        !selectedLabels.any((s) => optionLabels.contains(s));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.help_outline, size: 14, color: Colors.green),
            const SizedBox(width: 8),
            if (header.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  header,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (multiSelect)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'multi',
                  style: TextStyle(fontSize: 9, color: Colors.blue),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          questionText,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final opt in options)
                _OptionChip(
                  option: opt as Map<String, dynamic>,
                  isSelected: selectedLabels.contains(
                    (opt)['label'] as String?,
                  ),
                ),
              // Show "Other" chip with custom text if answer doesn't match options
              if (isOtherAnswer)
                _OtherAnswerChip(answer: selectedAnswer!),
            ],
          ),
        ],
      ],
    );
  }
}

/// Renders an option chip for question options.
class _OptionChip extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool isSelected;

  const _OptionChip({
    required this.option,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String?;

    return Tooltip(
      message: description ?? '',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? Colors.green
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check, size: 14, color: Colors.green),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.green : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a chip showing the user's custom "Other" answer.
class _OtherAnswerChip extends StatelessWidget {
  final String answer;

  const _OtherAnswerChip({required this.answer});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 14, color: Colors.green),
          const SizedBox(width: 4),
          Text(
            'Other: ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders FileChange tool input (Codex) with per-file diffs.
class FileChangeInputWidget extends StatelessWidget {
  final ToolUseOutputEntry entry;
  final String? projectDir;

  const FileChangeInputWidget({
    super.key,
    required this.entry,
    this.projectDir,
  });

  @override
  Widget build(BuildContext context) {
    final input = entry.toolInput;
    final changes = input['changes'] as List<dynamic>? ?? const [];

    if (changes.isEmpty) {
      // Fallback: show file_path only
      final filePath = input['file_path'] as String? ?? '';
      return FilePathWidget(
        filePath: filePath,
        icon: Icons.edit,
        projectDir: projectDir,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < changes.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _FileChangeEntry(
            change: changes[i] as Map<String, dynamic>,
            projectDir: projectDir,
          ),
        ],
      ],
    );
  }
}

/// A single file change entry showing the path, kind badge, and diff.
class _FileChangeEntry extends StatelessWidget {
  final Map<String, dynamic> change;
  final String? projectDir;

  const _FileChangeEntry({required this.change, this.projectDir});

  @override
  Widget build(BuildContext context) {
    final path = change['path'] as String? ?? '';
    final kind = change['kind'] as String? ?? 'update';
    final diff = change['diff'] as String? ?? '';
    final movePath = change['move_path'] as String?;

    final (icon, badge) = switch (kind) {
      'create' => (Icons.add_circle_outline, 'new'),
      'move' => (Icons.drive_file_move_outline, 'moved'),
      _ => (Icons.edit, 'modified'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilePathWidget(
                filePath: path,
                icon: icon,
                projectDir: projectDir,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _badgeColor(kind).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 9,
                  color: _badgeColor(kind),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        if (movePath != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.arrow_forward, size: 12, color: Colors.amber),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  movePath,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (diff.isNotEmpty) ...[
          const SizedBox(height: 8),
          DiffView(
            oldText: '',
            newText: '',
            structuredPatch: parseUnifiedDiff(diff),
            maxHeight: 300,
          ),
        ],
      ],
    );
  }

  static Color _badgeColor(String kind) {
    return switch (kind) {
      'create' => Colors.green,
      'move' => Colors.amber,
      _ => Colors.blue,
    };
  }
}

/// Renders generic tool input.
class GenericInputWidget extends StatelessWidget {
  final Map<String, dynamic> input;

  const GenericInputWidget({super.key, required this.input});

  @override
  Widget build(BuildContext context) {
    final buffer = StringBuffer();
    input.forEach((key, value) {
      final valueStr = value is String && value.length > 100
          ? '${value.substring(0, 100)}...'
          : value.toString();
      buffer.writeln('$key: $valueStr');
    });

    final monoFont = RuntimeConfig.instance.monoFontFamily;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        buffer.toString().trimRight(),
        style: GoogleFonts.getFont(
          monoFont,
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
