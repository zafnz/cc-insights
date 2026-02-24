import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ticket.dart';
import 'tag_colors.dart';

/// A popover widget for picking tags with autocomplete.
///
/// Shows a text input for typing tag names with a filtered list of known tags
/// below. Tags already on the ticket are shown with a checkmark and can be
/// toggled off. Free-form text can be submitted with Enter to add custom tags.
class TagPicker extends StatefulWidget {
  /// Tags currently assigned to the ticket.
  final Set<String> currentTags;

  /// All known tag definitions for autocomplete suggestions.
  final List<TagDefinition> allKnownTags;

  /// Called when a tag should be added.
  final void Function(String tag) onAddTag;

  /// Called when a tag should be removed.
  final void Function(String tag) onRemoveTag;

  const TagPicker({
    super.key,
    required this.currentTags,
    required this.allKnownTags,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  final _controller = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<TagDefinition> get _filteredTags {
    if (_filter.isEmpty) return widget.allKnownTags;
    return widget.allKnownTags
        .where((t) => t.name.contains(_filter.toLowerCase()))
        .toList();
  }

  void _submitCustomTag() {
    final text = _controller.text.trim().toLowerCase();
    if (text.isEmpty) return;
    widget.onAddTag(text);
    _controller.clear();
    setState(() => _filter = '');
  }

  void _onSuggestionTap(TagDefinition tag) {
    if (widget.currentTags.contains(tag.name)) {
      widget.onRemoveTag(tag.name);
    } else {
      widget.onAddTag(tag.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredTags;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Type tag name...',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (value) => setState(() => _filter = value),
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'\s')),
          ],
          onSubmitted: (_) => _submitCustomTag(),
        ),
        if (filtered.isNotEmpty) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final tag = filtered[index];
                final isSelected = widget.currentTags.contains(tag.name);
                final color = tagColor(tag.name, customHex: tag.color);

                return InkWell(
                  onTap: () => _onSuggestionTap(tag),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tag.name,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
