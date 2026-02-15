part of 'settings_screen.dart';

// -----------------------------------------------------------------------------
// Tags settings content
// -----------------------------------------------------------------------------

class _TagsSettingsContent extends StatefulWidget {
  const _TagsSettingsContent({required this.settings});

  final SettingsService settings;

  @override
  State<_TagsSettingsContent> createState() => _TagsSettingsContentState();
}

class _TagsSettingsContentState extends State<_TagsSettingsContent> {
  final _newTagController = TextEditingController();
  int _newTagColor = WorktreeTag.presetColors.first;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final name = _newTagController.text.trim().toLowerCase();
    if (name.isEmpty) return;

    final existing = widget.settings.availableTags;
    if (existing.any((t) => t.name == name)) return;

    widget.settings.addTag(WorktreeTag(name: name, colorValue: _newTagColor));
    _newTagController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tags = widget.settings.availableTags;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tags',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage worktree tags and their colors',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              // Existing tags
              for (final tag in tags) ...[
                _TagRow(
                  tag: tag,
                  onColorChanged: (color) {
                    widget.settings.updateTag(
                      tag.name,
                      tag.copyWith(colorValue: color),
                    );
                  },
                  onDelete: () => widget.settings.removeTag(tag.name),
                ),
                const SizedBox(height: 8),
              ],
              if (tags.isNotEmpty)
                Divider(
                  height: 32,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              // Add new tag row
              Row(
                children: [
                  _ColorDot(
                    colorValue: _newTagColor,
                    size: 24,
                    onTap: () async {
                      final picked = await _showColorPicker(
                        context,
                        _newTagColor,
                      );
                      if (picked != null) {
                        setState(() => _newTagColor = picked);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: InsightsTextField(
                        controller: _newTagController,
                        hintText: 'New tag name...',
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: InsightsTonalButton(
                      onPressed: _addTag,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.onColorChanged,
    required this.onDelete,
  });

  final WorktreeTag tag;
  final ValueChanged<int> onColorChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _ColorDot(
          colorValue: tag.colorValue,
          size: 24,
          onTap: () async {
            final picked = await _showColorPicker(
              context,
              tag.colorValue,
            );
            if (picked != null) {
              onColorChanged(picked);
            }
          },
        ),
        const SizedBox(width: 12),
        // Tag pill preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: tag.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: tag.color.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            tag.name,
            style: TextStyle(
              fontSize: 12,
              color: tag.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: onDelete,
          icon: Icon(
            Icons.close,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          constraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          padding: EdgeInsets.zero,
          tooltip: 'Remove tag',
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.colorValue,
    required this.size,
    required this.onTap,
  });

  final int colorValue;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: 'Change color',
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Color(colorValue),
            shape: BoxShape.circle,
            border: Border.all(
              color: Color(colorValue).withValues(alpha: 0.6),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a color picker popup and returns the chosen color, or null.
Future<int?> _showColorPicker(BuildContext context, int currentColor) async {
  final colorScheme = Theme.of(context).colorScheme;
  final renderBox = context.findRenderObject() as RenderBox?;
  if (renderBox == null) return null;

  final position = renderBox.localToGlobal(Offset.zero);

  return showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy + renderBox.size.height + 4,
      position.dx + 1,
      position.dy + renderBox.size.height + 5,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: colorScheme.primary.withValues(alpha: 0.5),
      ),
    ),
    color: colorScheme.surfaceContainerHigh,
    menuPadding: const EdgeInsets.all(8),
    items: [
      PopupMenuItem<int>(
        enabled: false,
        height: 0,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 160,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: WorktreeTag.presetColors.map((c) {
              final isSelected = c == currentColor;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Color(c).withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    ],
  );
}
