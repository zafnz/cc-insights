import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../models/ticket.dart';
import '../services/author_service.dart' hide AuthorType;
import '../state/ticket_board_state.dart';
import 'ticket_image_widgets.dart';
import 'ticket_tag_chip.dart';

/// A form for editing an existing ticket's title, body, tags, dependencies,
/// and images.
///
/// Pre-populated with the current ticket data. On save, generates appropriate
/// activity events via [TicketRepository] methods for each changed field.
class TicketEditForm extends StatefulWidget {
  const TicketEditForm({
    super.key,
    required this.ticket,
    required this.repository,
    required this.onSave,
    required this.onCancel,
    this.resolveImagePath,
  });

  /// The ticket being edited.
  final TicketData ticket;

  /// The repository used to persist changes.
  final TicketRepository repository;

  /// Called after all changes have been saved.
  final VoidCallback onSave;

  /// Called when the user cancels editing.
  final VoidCallback onCancel;

  /// Resolves a [TicketImage.relativePath] to an absolute path.
  /// If null, images are not displayed.
  final String Function(String relativePath)? resolveImagePath;

  @override
  State<TicketEditForm> createState() => _TicketEditFormState();
}

class _TicketEditFormState extends State<TicketEditForm> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagInputController;
  late final TextEditingController _depInputController;
  late Set<String> _tags;
  late List<int> _dependsOn;
  late List<TicketImage> _bodyImages;
  String? _depError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.ticket.title);
    _bodyController = TextEditingController(text: widget.ticket.body);
    _tagInputController = TextEditingController();
    _depInputController = TextEditingController();
    _tags = Set<String>.from(widget.ticket.tags);
    _dependsOn = List<int>.from(widget.ticket.dependsOn);
    _bodyImages = List<TicketImage>.from(widget.ticket.bodyImages);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagInputController.dispose();
    _depInputController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagInputController.text.trim().toLowerCase();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  void _addDependency() {
    final text = _depInputController.text.trim();
    final id = int.tryParse(text);
    if (id == null) {
      setState(() => _depError = 'Enter a valid ticket number');
      return;
    }
    if (id == widget.ticket.id) {
      setState(() => _depError = 'A ticket cannot depend on itself');
      return;
    }
    if (_dependsOn.contains(id)) {
      setState(() => _depError = 'Already a dependency');
      return;
    }
    if (widget.repository.getTicket(id) == null) {
      setState(() => _depError = 'Ticket #$id does not exist');
      return;
    }
    if (widget.repository.wouldCreateCycle(widget.ticket.id, id)) {
      setState(() => _depError = 'Would create a dependency cycle');
      return;
    }
    setState(() {
      _dependsOn.add(id);
      _depInputController.clear();
      _depError = null;
    });
  }

  void _removeDependency(int id) {
    setState(() => _dependsOn.remove(id));
  }

  void _removeImage(TicketImage image) {
    setState(() => _bodyImages.remove(image));
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final body = _bodyController.text;
    final repo = widget.repository;
    final ticketId = widget.ticket.id;
    final actor = AuthorService.currentUser;
    const actorType = AuthorType.user;

    // Title and body changes via updateTicket (generates activity events).
    final titleChanged = title != widget.ticket.title;
    final bodyChanged = body != widget.ticket.body;
    if (titleChanged || bodyChanged) {
      repo.updateTicket(
        ticketId,
        title: titleChanged ? title : null,
        body: bodyChanged ? body : null,
        actor: actor,
        actorType: actorType,
      );
    }

    // Tags — bulk set generates tagAdded/tagRemoved events.
    if (!setEquals(_tags, widget.ticket.tags)) {
      repo.setTags(ticketId, _tags, actor, actorType);
    }

    // Dependencies — diff and add/remove individually.
    final oldDeps = widget.ticket.dependsOn.toSet();
    final newDeps = _dependsOn.toSet();
    for (final added in newDeps.difference(oldDeps)) {
      repo.addDependency(ticketId, added, actor: actor, actorType: actorType);
    }
    for (final removed in oldDeps.difference(newDeps)) {
      repo.removeDependency(ticketId, removed,
          actor: actor, actorType: actorType);
    }

    widget.onSave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title field
          Text('Title', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Ticket title',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: 16),

          // Body field
          Text('Body', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          TextField(
            controller: _bodyController,
            maxLines: null,
            minLines: 6,
            decoration: const InputDecoration(
              hintText: 'Markdown body...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: theme.textTheme.bodyMedium,
          ),

          const SizedBox(height: 16),

          // Tags section
          Text('Tags', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in _tags)
                TicketTagChip(
                  tag: tag,
                  removable: true,
                  onRemove: () => _removeTag(tag),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagInputController,
                  decoration: const InputDecoration(
                    hintText: 'Add a tag...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: theme.textTheme.bodySmall,
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: _addTag,
                tooltip: 'Add tag',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Dependencies section
          Text('Dependencies', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (_dependsOn.isNotEmpty)
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final depId in _dependsOn)
                  Chip(
                    label: Text(
                      '#$depId',
                      style: theme.textTheme.bodySmall,
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _removeDependency(depId),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _depInputController,
                  decoration: InputDecoration(
                    hintText: 'Ticket # to depend on...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _depError,
                  ),
                  style: theme.textTheme.bodySmall,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _addDependency(),
                  onChanged: (_) {
                    if (_depError != null) {
                      setState(() => _depError = null);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: _addDependency,
                tooltip: 'Add dependency',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Images section
          if (_bodyImages.isNotEmpty) ...[
            Text('Images', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in _bodyImages)
                  TicketImageThumbnail(
                    image: image,
                    resolvedPath: widget.resolveImagePath != null
                        ? widget.resolveImagePath!(image.relativePath)
                        : image.relativePath,
                    onRemove: () => _removeImage(image),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          Divider(color: colorScheme.outlineVariant),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
