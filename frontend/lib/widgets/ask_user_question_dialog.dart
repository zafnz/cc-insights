import 'package:flutter/material.dart';

import '../legacy/sdk_types.dart' as sdk;

import 'permission_dialog.dart' show PermissionFontSizes, textStyle;

// =============================================================================
// Test Keys for AskUserQuestionDialog
// =============================================================================

/// Keys for testing AskUserQuestionDialog widgets.
class AskUserQuestionDialogKeys {
  AskUserQuestionDialogKeys._();

  /// The root container of the dialog.
  static const dialog = Key('ask_user_question_dialog');

  /// The header.
  static const header = Key('ask_user_question_header');

  /// The submit button.
  static const submitButton = Key('ask_user_question_submit');

  /// The "Other" option chip.
  static const otherOption = Key('ask_user_question_other');

  /// The custom text input field.
  static const customInput = Key('ask_user_question_custom_input');
}

// =============================================================================
// Ask User Question Dialog Widget
// =============================================================================

/// Widget for handling AskUserQuestion tool interactions.
///
/// Displays one or more questions with multiple-choice options.
/// Users can select options or provide custom "Other" responses.
class AskUserQuestionDialog extends StatefulWidget {
  const AskUserQuestionDialog({
    super.key,
    required this.request,
    required this.onSubmit,
  });

  /// The permission request containing the questions.
  final sdk.PermissionRequest request;

  /// Called when the user submits their answers.
  /// The map contains question text as keys and answer text as values.
  final void Function(Map<String, String> answers) onSubmit;

  @override
  State<AskUserQuestionDialog> createState() => _AskUserQuestionDialogState();
}

class _AskUserQuestionDialogState extends State<AskUserQuestionDialog> {
  final Map<String, Set<String>> selectedAnswers = {};
  final Map<String, TextEditingController> customTextControllers = {};

  @override
  void dispose() {
    for (final controller in customTextControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final toolInput = widget.request.toolInput;
    final questions = (toolInput['questions'] as List<dynamic>?) ?? [];

    // Green-tinted background for questions (different from purple permissions)
    const dialogBackground = Color(0xFF1F3D2D);
    const headerGreen = Color(0xFF206644);

    return Container(
      key: AskUserQuestionDialogKeys.dialog,
      decoration: const BoxDecoration(
        color: dialogBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            key: AskUserQuestionDialogKeys.header,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: headerGreen,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.help_outline,
                  color: Colors.greenAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Claude has a question',
                  style: textStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ),
          // Questions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < questions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  _buildQuestion(context, questions[i] as Map<String, dynamic>),
                ],
              ],
            ),
          ),
          // Footer with submit button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  key: AskUserQuestionDialogKeys.submitButton,
                  onPressed: _canSubmit() ? _submitAnswers : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32), // Green 800
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[700],
                    disabledForegroundColor: Colors.grey[400],
                  ),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(BuildContext context, Map<String, dynamic> question) {
    final questionText = question['question'] as String? ?? '';
    final header = question['header'] as String? ?? '';
    final options = (question['options'] as List<dynamic>?) ?? [];
    final multiSelect = question['multiSelect'] as bool? ?? false;

    // Initialize selected answers for this question
    if (!selectedAnswers.containsKey(questionText)) {
      selectedAnswers[questionText] = {};
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header badge and multi-select indicator
        Row(
          children: [
            if (header.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  header,
                  style: textStyle(
                    fontSize: PermissionFontSizes.badge,
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
                child: Text(
                  'multi-select',
                  style: textStyle(
                    fontSize: PermissionFontSizes.smallBadge,
                    color: Colors.blue,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Question text
        Text(
          questionText,
          style: textStyle(
            fontSize: PermissionFontSizes.questionText,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // Options
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              _buildOptionButton(
                context,
                questionText,
                opt as Map<String, dynamic>,
                multiSelect,
              ),
            _buildOtherOptionButton(context, questionText, multiSelect),
          ],
        ),
        // Custom text input when "Other" is selected
        if (selectedAnswers[questionText]!.contains('__OTHER__')) ...[
          const SizedBox(height: 8),
          TextField(
            key: AskUserQuestionDialogKeys.customInput,
            controller: _getTextController(questionText),
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter your custom answer...',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            minLines: 1,
            maxLines: 3,
            onSubmitted: (_) {
              if (_canSubmit()) _submitAnswers();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildOptionButton(
    BuildContext context,
    String questionText,
    Map<String, dynamic> option,
    bool multiSelect,
  ) {
    final label = option['label'] as String? ?? '';
    final description = option['description'] as String? ?? '';
    final isSelected = selectedAnswers[questionText]!.contains(label);

    return Tooltip(
      message: description,
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            if (multiSelect) {
              if (selected) {
                selectedAnswers[questionText]!.add(label);
                selectedAnswers[questionText]!.remove('__OTHER__');
              } else {
                selectedAnswers[questionText]!.remove(label);
              }
            } else {
              selectedAnswers[questionText] = selected ? {label} : {};
            }
          });

          // For single-select questions, auto-submit if all questions answered
          if (!multiSelect && selected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_canSubmit()) {
                _submitAnswers();
              }
            });
          }
        },
        showCheckmark: multiSelect,
      ),
    );
  }

  Widget _buildOtherOptionButton(
    BuildContext context,
    String questionText,
    bool multiSelect,
  ) {
    final isSelected = selectedAnswers[questionText]!.contains('__OTHER__');

    return FilterChip(
      key: AskUserQuestionDialogKeys.otherOption,
      label: const Text('Other...'),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (multiSelect) {
            if (selected) {
              selectedAnswers[questionText]!.add('__OTHER__');
            } else {
              selectedAnswers[questionText]!.remove('__OTHER__');
            }
          } else {
            selectedAnswers[questionText] = selected ? {'__OTHER__'} : {};
          }
        });
      },
      showCheckmark: multiSelect,
    );
  }

  TextEditingController _getTextController(String questionText) {
    if (!customTextControllers.containsKey(questionText)) {
      final controller = TextEditingController();
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      customTextControllers[questionText] = controller;
    }
    return customTextControllers[questionText]!;
  }

  bool _canSubmit() {
    final toolInput = widget.request.toolInput;
    final questions = (toolInput['questions'] as List<dynamic>?) ?? [];

    // All questions must have at least one answer
    for (final q in questions) {
      final question = q as Map<String, dynamic>;
      final questionText = question['question'] as String? ?? '';
      final answers = selectedAnswers[questionText] ?? {};

      if (answers.isEmpty) return false;

      // If "Other" is selected, must have text
      if (answers.contains('__OTHER__')) {
        final controller = customTextControllers[questionText];
        if (controller == null || controller.text.trim().isEmpty) {
          return false;
        }
      }
    }

    return true;
  }

  void _submitAnswers() {
    final toolInput = widget.request.toolInput;
    final questions = (toolInput['questions'] as List<dynamic>?) ?? [];

    // Build answers map
    final Map<String, String> answers = {};
    for (final q in questions) {
      final question = q as Map<String, dynamic>;
      final questionText = question['question'] as String? ?? '';
      final selected = selectedAnswers[questionText] ?? {};

      if (selected.contains('__OTHER__')) {
        // Use custom text
        final controller = customTextControllers[questionText];
        answers[questionText] = controller?.text.trim() ?? '';
      } else {
        // Join selected labels with ", "
        answers[questionText] = selected.join(', ');
      }
    }

    widget.onSubmit(answers);
  }
}
