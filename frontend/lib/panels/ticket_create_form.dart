import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../state/ticket_board_state.dart';
import '../state/ticket_view_state.dart';
import '../widgets/ticket_visuals.dart';

/// Keys for testing [TicketCreateForm] widgets.
class TicketCreateFormKeys {
  TicketCreateFormKeys._();

  static const Key titleField = Key('ticket-create-title');
  static const Key kindDropdown = Key('ticket-create-kind');
  static const Key priorityDropdown = Key('ticket-create-priority');
  static const Key statusDropdown = Key('ticket-create-status');
  static const Key categoryField = Key('ticket-create-category');
  static const Key descriptionField = Key('ticket-create-description');
  static const Key effortSelector = Key('ticket-create-effort');
  static const Key cancelButton = Key('ticket-create-cancel');
  static const Key createButton = Key('ticket-create-submit');
}

/// Form panel for creating or editing a ticket.
///
/// Follows the same centered, max-width-600 layout as [CreateWorktreePanel].
/// Fields: title, kind, priority, category (with autocomplete), description,
/// estimated effort, dependencies, and tags.
///
/// When [editingTicket] is provided, the form pre-populates all fields with
/// the ticket's existing values, changes the header to "Edit Ticket", and
/// calls [TicketBoardState.updateTicket] on save instead of
/// [TicketBoardState.createTicket].
class TicketCreateForm extends StatefulWidget {
  /// The ticket to edit, or null to create a new ticket.
  final TicketData? editingTicket;

  const TicketCreateForm({super.key, this.editingTicket});

  /// Whether the form is in edit mode.
  bool get isEditing => editingTicket != null;

  @override
  State<TicketCreateForm> createState() => _TicketCreateFormState();
}

class _TicketCreateFormState extends State<TicketCreateForm> {
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagInputController = TextEditingController();

  TicketStatus _selectedStatus = TicketStatus.ready;
  TicketKind _selectedKind = TicketKind.feature;
  TicketPriority _selectedPriority = TicketPriority.medium;
  TicketEffort _selectedEffort = TicketEffort.medium;
  List<int> _selectedDependencies = [];
  Set<String> _tags = {};
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final ticket = widget.editingTicket;
    if (ticket != null) {
      _titleController.text = ticket.title;
      _categoryController.text = ticket.category ?? '';
      _descriptionController.text = ticket.description;
      _selectedStatus = ticket.status;
      _selectedKind = ticket.kind;
      _selectedPriority = ticket.priority;
      _selectedEffort = ticket.effort;
      _selectedDependencies = List.of(ticket.dependsOn);
      _tags = Set.of(ticket.tags);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _handleCancel() {
    context.read<TicketViewState>().showDetail();
  }

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      setState(() {
        _errorMessage = 'Title is required.';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final ticketBoard = context.read<TicketRepository>();
      final viewState = context.read<TicketViewState>();
      final category = _categoryController.text.trim();
      final description = _descriptionController.text.trim();

      if (widget.isEditing) {
        final editingId = widget.editingTicket!.id;
        ticketBoard.updateTicket(editingId, (ticket) {
          return ticket.copyWith(
            title: title,
            kind: _selectedKind,
            priority: _selectedPriority,
            status: _selectedStatus,
            effort: _selectedEffort,
            category: category.isNotEmpty ? category : null,
            clearCategory: category.isEmpty,
            description: description,
            dependsOn: _selectedDependencies,
            tags: _tags,
          );
        });
        viewState.selectTicket(editingId);
      } else {
        final ticket = ticketBoard.createTicket(
          title: title,
          kind: _selectedKind,
          priority: _selectedPriority,
          effort: _selectedEffort,
          category: category.isNotEmpty ? category : null,
          description: description,
          dependsOn: _selectedDependencies,
          tags: _tags,
        );
        viewState.selectTicket(ticket.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = widget.isEditing
              ? 'Failed to save changes: $e'
              : 'Failed to create ticket: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _addTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _tags.add(trimmed);
    });
    _tagInputController.clear();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  void _addDependency(int ticketId) {
    if (_selectedDependencies.contains(ticketId)) return;
    setState(() {
      _selectedDependencies = [..._selectedDependencies, ticketId];
    });
  }

  void _removeDependency(int ticketId) {
    setState(() {
      _selectedDependencies = _selectedDependencies.where((id) => id != ticketId).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _handleCancel();
        }
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      widget.isEditing ? Icons.edit : Icons.add_task,
                      size: 28,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.isEditing ? 'Edit Ticket' : 'Create Ticket',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isEditing
                      ? 'Update the ticket details.'
                      : 'Add a new task to the project backlog.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                _buildLabel('Title', textTheme),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _titleController,
                  key: TicketCreateFormKeys.titleField,
                  autofocus: true,
                  hintText: 'e.g. Implement user authentication',
                  onSubmitted: (_) => _handleSubmit(),
                ),
                const SizedBox(height: 20),

                // Kind + Priority row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Kind', textTheme),
                          const SizedBox(height: 8),
                          _buildDropdownField<TicketKind>(
                            key: TicketCreateFormKeys.kindDropdown,
                            value: _selectedKind,
                            items: TicketKind.values,
                            labelBuilder: (kind) => kind.label,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedKind = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('Priority', textTheme),
                          const SizedBox(height: 8),
                          _buildDropdownField<TicketPriority>(
                            key: TicketCreateFormKeys.priorityDropdown,
                            value: _selectedPriority,
                            items: TicketPriority.values,
                            labelBuilder: (priority) => priority.label,
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedPriority = value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Status dropdown (edit mode only)
                if (widget.isEditing) ...[
                  _buildLabel('Status', textTheme),
                  const SizedBox(height: 8),
                  _buildDropdownField<TicketStatus>(
                    key: TicketCreateFormKeys.statusDropdown,
                    value: _selectedStatus,
                    items: TicketStatus.values,
                    labelBuilder: (status) => status.label,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // Category with autocomplete
                _buildLabel('Category', textTheme),
                const SizedBox(height: 8),
                _CategoryAutocompleteField(
                  controller: _categoryController,
                ),
                const SizedBox(height: 6),
                Text(
                  'Group related tickets together. Categories are created automatically.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                // Description
                _buildLabel('Description', textTheme),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _descriptionController,
                  key: TicketCreateFormKeys.descriptionField,
                  hintText: 'Describe what needs to be done...\n\nMarkdown supported.',
                  maxLines: 6,
                ),
                const SizedBox(height: 20),

                // Dependencies
                _buildLabel('Depends on', textTheme),
                const SizedBox(height: 8),
                _DependenciesInput(
                  selectedDependencies: _selectedDependencies,
                  onAdd: _addDependency,
                  onRemove: _removeDependency,
                ),
                const SizedBox(height: 20),

                // Estimated effort
                _buildLabel('Estimated effort', textTheme),
                const SizedBox(height: 8),
                _EffortSelector(
                  key: TicketCreateFormKeys.effortSelector,
                  selected: _selectedEffort,
                  onChanged: (effort) {
                    setState(() => _selectedEffort = effort);
                  },
                ),
                const SizedBox(height: 20),

                // Tags
                _buildLabel('Tags', textTheme),
                const SizedBox(height: 8),
                _TagsInput(
                  tags: _tags,
                  controller: _tagInputController,
                  onAdd: _addTag,
                  onRemove: _removeTag,
                ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ErrorCard(message: _errorMessage!),
                ],

                const SizedBox(height: 32),

                // Action buttons
                _ActionBar(
                  isCreating: _isCreating,
                  isEditing: widget.isEditing,
                  onCancel: _handleCancel,
                  onCreate: _handleSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, TextTheme textTheme) {
    return Text(
      text,
      style: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    Key? key,
    bool autofocus = false,
    String? hintText,
    int? maxLines,
    ValueChanged<String>? onSubmitted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      child: TextField(
        key: key,
        controller: controller,
        autofocus: autofocus,
        maxLines: maxLines,
        style: textTheme.bodyMedium,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required Key key,
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonFormField<T>(
        key: key,
        value: value,
        isExpanded: true,
        style: textTheme.bodyMedium,
        dropdownColor: colorScheme.surfaceContainerHigh,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
        ),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(labelBuilder(item)),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}

/// Category text field with autocomplete from existing categories.
class _CategoryAutocompleteField extends StatelessWidget {
  const _CategoryAutocompleteField({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final viewState = context.watch<TicketViewState>();
    final categories = viewState.allCategories;

    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return categories;
        }
        final query = textEditingValue.text.toLowerCase();
        return categories.where((c) => c.toLowerCase().contains(query));
      },
      onSelected: (value) {
        controller.text = value;
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        // Sync the external controller with the autocomplete's internal controller
        textController.addListener(() {
          if (controller.text != textController.text) {
            controller.text = textController.text;
          }
        });
        // Initialize from external controller if it has a value
        if (controller.text.isNotEmpty && textController.text.isEmpty) {
          textController.text = controller.text;
        }

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colorScheme.outline),
          ),
          child: TextField(
            key: TicketCreateFormKeys.categoryField,
            controller: textController,
            focusNode: focusNode,
            style: textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
              hintText: 'e.g. Auth & Permissions',
              hintStyle: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            color: colorScheme.surfaceContainerHigh,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        option,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Effort selector with three radio-style options colored by effort level.
class _EffortSelector extends StatelessWidget {
  const _EffortSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final TicketEffort selected;
  final ValueChanged<TicketEffort> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: TicketEffort.values.map((effort) {
        final isSelected = effort == selected;
        final effortColor = TicketEffortVisuals.color(effort, colorScheme);

        return Padding(
          padding: EdgeInsets.only(right: effort != TicketEffort.large ? 16 : 0),
          child: GestureDetector(
            onTap: () => onChanged(effort),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? effortColor.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? effortColor.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? effortColor : null,
                      border: isSelected ? null : Border.all(color: colorScheme.onSurfaceVariant, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    effort.label.toLowerCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? effortColor : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Chip input for selecting dependency tickets.
class _DependenciesInput extends StatefulWidget {
  const _DependenciesInput({
    required this.selectedDependencies,
    required this.onAdd,
    required this.onRemove,
  });

  final List<int> selectedDependencies;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;

  @override
  State<_DependenciesInput> createState() => _DependenciesInputState();
}

class _DependenciesInputState extends State<_DependenciesInput> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ticketBoard = context.watch<TicketRepository>();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chips for selected dependencies
          if (widget.selectedDependencies.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.selectedDependencies.map((depId) {
                final ticket = ticketBoard.getTicket(depId);
                final label = ticket != null ? '${ticket.displayId} ${ticket.title}' : 'TKT-${depId.toString().padLeft(3, '0')}';

                return _RemovableChip(
                  label: label,
                  onRemove: () => widget.onRemove(depId),
                );
              }).toList(),
            ),
          if (widget.selectedDependencies.isNotEmpty) const SizedBox(height: 6),
          // Search field
          Autocomplete<TicketData>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) return const [];
              final query = textEditingValue.text.toLowerCase();
              return ticketBoard.tickets.where((t) {
                if (widget.selectedDependencies.contains(t.id)) return false;
                return t.displayId.toLowerCase().contains(query) || t.title.toLowerCase().contains(query);
              });
            },
            displayStringForOption: (ticket) => '${ticket.displayId} ${ticket.title}',
            onSelected: (ticket) {
              widget.onAdd(ticket.id);
              _searchController.clear();
            },
            fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                style: textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: InputBorder.none,
                  hintText: 'Search tickets...',
                  hintStyle: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  color: colorScheme.surfaceContainerHigh,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final ticket = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(ticket),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text(
                              '${ticket.displayId} - ${ticket.title}',
                              style: textTheme.bodySmall,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Chip input for adding and removing tags.
class _TagsInput extends StatelessWidget {
  const _TagsInput({
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
  });

  final Set<String> tags;
  final TextEditingController controller;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.outline),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags.map((tag) {
                return _RemovableChip(
                  label: tag,
                  onRemove: () => onRemove(tag),
                );
              }).toList(),
            ),
          if (tags.isNotEmpty) const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: textTheme.bodySmall,
            onSubmitted: (value) {
              onAdd(value);
            },
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              border: InputBorder.none,
              hintText: 'Type to add...',
              hintStyle: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A removable chip with an X button.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 12,
              color: colorScheme.primary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error card showing error message.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Action bar with Cancel and Create/Save buttons.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isCreating,
    required this.isEditing,
    required this.onCancel,
    required this.onCreate,
  });

  final bool isCreating;
  final bool isEditing;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        OutlinedButton(
          key: TicketCreateFormKeys.cancelButton,
          onPressed: isCreating ? null : onCancel,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            side: BorderSide(color: colorScheme.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.close,
                size: 18,
                color: isCreating
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Cancel',
                style: textTheme.labelLarge?.copyWith(
                  color: isCreating
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: TicketCreateFormKeys.createButton,
          onPressed: isCreating ? null : onCreate,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            backgroundColor: colorScheme.primary,
            disabledBackgroundColor: colorScheme.primary.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCreating)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              else
                Icon(
                  isEditing ? Icons.save : Icons.add,
                  size: 18,
                  color: colorScheme.onPrimary,
                ),
              const SizedBox(width: 8),
              Text(
                isCreating
                    ? (isEditing ? 'Saving...' : 'Creating...')
                    : (isEditing ? 'Save Changes' : 'Create Ticket'),
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
