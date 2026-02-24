import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../services/author_service.dart' hide AuthorType;
import '../state/ticket_board_state.dart';
import '../state/ticket_view_state.dart';
import '../widgets/tag_picker.dart';

/// Keys for testing [TicketCreateForm] widgets.
class TicketCreateFormKeys {
  TicketCreateFormKeys._();

  static const Key titleField = Key('ticket-create-title');
  static const Key bodyField = Key('ticket-create-body');
  static const Key cancelButton = Key('ticket-create-cancel');
  static const Key createButton = Key('ticket-create-submit');
  static const Key tagPicker = Key('ticket-create-tags');
  static const Key imagePickerButton = Key('ticket-create-image-picker');
}

/// Form panel for creating a new ticket.
///
/// Follows the same centered, max-width-600 layout as [CreateWorktreePanel].
/// Fields: title, body (markdown), tags (via [TagPicker]), dependencies,
/// and images (via file picker).
class TicketCreateForm extends StatefulWidget {
  const TicketCreateForm({super.key});

  @override
  State<TicketCreateForm> createState() => _TicketCreateFormState();
}

class _TicketCreateFormState extends State<TicketCreateForm> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  List<int> _selectedDependencies = [];
  final Set<String> _tags = {};
  final List<_PickedImage> _pickedImages = [];
  bool _isCreating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
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
      final repo = context.read<TicketRepository>();
      final viewState = context.read<TicketViewState>();
      final body = _bodyController.text.trim();

      final ticket = repo.createTicket(
        title: title,
        body: body,
        tags: _tags,
        author: AuthorService.currentUser,
        authorType: AuthorType.user,
        dependsOn: _selectedDependencies,
      );

      viewState.selectTicket(ticket.id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to create ticket: $e';
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
    final trimmed = tag.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    setState(() {
      _tags.add(trimmed);
    });
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
      _selectedDependencies =
          _selectedDependencies.where((id) => id != ticketId).toList();
    });
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;

    setState(() {
      for (final file in result.files) {
        if (file.path != null) {
          _pickedImages.add(_PickedImage(
            name: file.name,
            path: file.path!,
          ));
        }
      }
    });
  }

  void _removeImage(int index) {
    setState(() {
      _pickedImages.removeAt(index);
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
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
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
                      Icons.add_task,
                      size: 28,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Create Ticket',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a new task to the project backlog.',
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

                // Body
                _buildLabel('Body', textTheme),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _bodyController,
                  key: TicketCreateFormKeys.bodyField,
                  hintText:
                      'Describe what needs to be done...\n\nMarkdown supported.',
                  maxLines: 6,
                ),
                const SizedBox(height: 20),

                // Tags
                _buildLabel('Tags', textTheme),
                const SizedBox(height: 8),
                _TagsSection(
                  key: TicketCreateFormKeys.tagPicker,
                  tags: _tags,
                  onAddTag: _addTag,
                  onRemoveTag: _removeTag,
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

                // Images
                _buildLabel('Images', textTheme),
                const SizedBox(height: 8),
                _ImagesSection(
                  images: _pickedImages,
                  onPick: _pickImages,
                  onRemove: _removeImage,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// Tags section with inline chips and a TagPicker popover.
class _TagsSection extends StatelessWidget {
  const _TagsSection({
    super.key,
    required this.tags,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  final Set<String> tags;
  final void Function(String) onAddTag;
  final void Function(String) onRemoveTag;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final repo = context.watch<TicketRepository>();

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
                  onRemove: () => onRemoveTag(tag),
                );
              }).toList(),
            ),
          if (tags.isNotEmpty) const SizedBox(height: 6),
          TagPicker(
            currentTags: tags,
            allKnownTags: repo.tagRegistry,
            onAddTag: onAddTag,
            onRemoveTag: onRemoveTag,
          ),
        ],
      ),
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
                final label = ticket != null
                    ? '${ticket.displayId} ${ticket.title}'
                    : 'TKT-${depId.toString().padLeft(3, '0')}';

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
                return t.displayId.toLowerCase().contains(query) ||
                    t.title.toLowerCase().contains(query);
              });
            },
            displayStringForOption: (ticket) =>
                '${ticket.displayId} ${ticket.title}',
            onSelected: (ticket) {
              widget.onAdd(ticket.id);
              _searchController.clear();
            },
            fieldViewBuilder:
                (context, textController, focusNode, onFieldSubmitted) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                style: textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: InputBorder.none,
                  hintText: 'Search tickets...',
                  hintStyle: textTheme.bodySmall?.copyWith(
                    color:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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
                    constraints:
                        const BoxConstraints(maxHeight: 200, maxWidth: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final ticket = options.elementAt(index);
                        return InkWell(
                          onTap: () => onSelected(ticket),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
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

/// Simple data class for a picked image file.
class _PickedImage {
  final String name;
  final String path;

  const _PickedImage({required this.name, required this.path});
}

/// Images section with a file picker button and image list.
class _ImagesSection extends StatelessWidget {
  const _ImagesSection({
    required this.images,
    required this.onPick,
    required this.onRemove,
  });

  final List<_PickedImage> images;
  final VoidCallback onPick;
  final void Function(int index) onRemove;

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
          if (images.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < images.length; i++)
                  _RemovableChip(
                    label: images[i].name,
                    onRemove: () => onRemove(i),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          GestureDetector(
            key: TicketCreateFormKeys.imagePickerButton,
            onTap: onPick,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.attach_file,
                  size: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  'Attach images...',
                  style: textTheme.bodySmall?.copyWith(
                    color:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
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

/// Action bar with Cancel and Create buttons.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isCreating,
    required this.onCancel,
    required this.onCreate,
  });

  final bool isCreating;
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
            disabledBackgroundColor:
                colorScheme.primary.withValues(alpha: 0.5),
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
                  Icons.add,
                  size: 18,
                  color: colorScheme.onPrimary,
                ),
              const SizedBox(width: 8),
              Text(
                isCreating ? 'Creating...' : 'Create',
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
