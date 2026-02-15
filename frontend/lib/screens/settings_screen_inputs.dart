part of 'settings_screen.dart';

// -----------------------------------------------------------------------------
// Generic setting row
// -----------------------------------------------------------------------------

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.definition,
    required this.value,
    required this.onChanged,
    this.isLoading = false,
    this.isOverridden = false,
  });

  final SettingDefinition definition;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool isLoading;
  final bool isOverridden;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Color picker uses a stacked layout (title + description
    // above, picker below) because it needs more width.
    if (definition.type == SettingType.colorPicker) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              definition.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            InsightsDescriptionText(definition.description),
            if (isOverridden) _buildOverrideIndicator(context),
            const SizedBox(height: 12),
            _buildInput(context),
          ],
        ),
      );
    }


    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: title + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  definition.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                InsightsDescriptionText(definition.description),
                if (definition.errorText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    definition.errorText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (isOverridden) _buildOverrideIndicator(context),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right: input widget
          _buildInput(context),
        ],
      ),
    );
  }

  Widget _buildOverrideIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 12,
            color: colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Text(
            'Overridden via CLI',
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    return switch (definition.type) {
      SettingType.toggle => _buildToggle(context),
      SettingType.dropdown => _buildDropdown(context, isLoading),
      SettingType.number => InsightsNumberField(
          value: (value as num).toInt(),
          min: definition.min ?? 0,
          max: definition.max ?? 999,
          onChanged: isOverridden ? null : (v) => onChanged(v),
        ),
      SettingType.colorPicker => isOverridden
          ? _buildDisabledColorPreview(context)
          : _ColorPickerInput(
              value: (value as num).toInt(),
              onChanged: onChanged,
              allowDefault: definition.defaultValue == 0,
            ),
      SettingType.text => _TextSettingInput(
          value: value as String,
          placeholder: definition.placeholder,
          enabled: !isOverridden,
          onChanged: onChanged,
        ),
    };
  }

  Widget _buildToggle(BuildContext context) {
    return Transform.scale(
      scale: 0.75,
      child: Switch(
        value: value as bool,
        onChanged: isOverridden ? null : (v) => onChanged(v),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = definition.options ?? [];

    final dropdown = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOverridden
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value as String,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            color: isOverridden
                ? colorScheme.onSurface.withValues(alpha: 0.5)
                : colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          items: options
              .map(
                (opt) => DropdownMenuItem<String>(
                  value: opt.value,
                  child: Text(opt.label),
                ),
              )
              .toList(),
          onChanged: isOverridden
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
        ),
      ),
    );

    if (!isLoading) return dropdown;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dropdown,
        const SizedBox(width: 8),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildDisabledColorPreview(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colorValue = (value as num).toInt();
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colorValue == 0 ? null : Color(colorValue),
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: colorValue == 0
          ? Icon(Icons.auto_awesome, size: 14, color: colorScheme.onSurfaceVariant)
          : null,
    );
  }
}

// ---------------------------------------------------------------------
// Text input
// ---------------------------------------------------------------------

class _TextSettingInput extends StatefulWidget {
  const _TextSettingInput({
    required this.value,
    this.placeholder,
    this.enabled = true,
    required this.onChanged,
  });

  final String value;
  final String? placeholder;
  final bool enabled;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_TextSettingInput> createState() => _TextSettingInputState();
}

class _TextSettingInputState extends State<_TextSettingInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextSettingInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: InsightsTextField(
        controller: _controller,
        hintText: widget.placeholder,
        monospace: true,
        enabled: widget.enabled,
        onSubmitted: widget.enabled ? _submit : null,
        onTapOutside: widget.enabled ? (_) => _submit(_controller.text) : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------
// CLI path setting row (text input + file picker button)
// ---------------------------------------------------------------------

class _CliPathSettingRow extends StatefulWidget {
  const _CliPathSettingRow({
    required this.definition,
    required this.value,
    required this.onChanged,
    this.isOverridden = false,
  });

  final SettingDefinition definition;
  final String value;
  final ValueChanged<dynamic> onChanged;
  final bool isOverridden;

  @override
  State<_CliPathSettingRow> createState() => _CliPathSettingRowState();
}

class _CliPathSettingRowState extends State<_CliPathSettingRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_CliPathSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    widget.onChanged(text);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select CLI executable',
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path;
      if (path != null) {
        _controller.text = path;
        _submit(path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mono = GoogleFonts.jetBrainsMono(fontSize: 13);
    final enabled = !widget.isOverridden;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: title + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.definition.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                InsightsDescriptionText(widget.definition.description),
                if (widget.definition.errorText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.definition.errorText!,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (widget.isOverridden)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: colorScheme.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Overridden via CLI',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right: text input + file picker icon
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _controller,
                  enabled: enabled,
                  style: mono,
                  decoration: InputDecoration(
                    hintText: widget.definition.placeholder,
                    hintStyle: mono.copyWith(
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: enabled ? _submit : null,
                  onTapOutside: enabled
                      ? (_) => _submit(_controller.text)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.folder_open, size: 18),
                tooltip: 'Browse...',
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
                onPressed: enabled ? _pickFile : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
