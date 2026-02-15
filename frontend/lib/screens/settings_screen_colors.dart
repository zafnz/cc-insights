part of 'settings_screen.dart';

// ---------------------------------------------------------------------
// Color picker input
// ---------------------------------------------------------------------

class _ColorPickerInput extends StatefulWidget {
  const _ColorPickerInput({
    required this.value,
    required this.onChanged,
    this.allowDefault = false,
  });

  final int value;
  final ValueChanged<dynamic> onChanged;

  /// When true, shows a "Default" swatch that sets the value
  /// to 0 (meaning "use the accent color").
  final bool allowDefault;

  @override
  State<_ColorPickerInput> createState() =>
      _ColorPickerInputState();
}

class _ColorPickerInputState extends State<_ColorPickerInput> {
  bool _showHexInput = false;
  late TextEditingController _hexController;
  Color? _previewColor;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _onHexChanged(String value) {
    final color = _parseHex(value);
    setState(() => _previewColor = color);
  }

  void _applyHex() {
    if (_previewColor != null) {
      widget.onChanged(_previewColor!.toARGB32());
      setState(() => _showHexInput = false);
    }
  }

  static Color? _parseHex(String input) {
    final hex = input.trim().replaceFirst('#', '');
    if (hex.length == 6 &&
        RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        Theme.of(context).colorScheme.outline;
    final currentColor = Color(widget.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.allowDefault)
              _DefaultColorSwatch(
                isSelected: widget.value == 0,
                onTap: () {
                  widget.onChanged(0);
                  setState(() => _showHexInput = false);
                },
              ),
            for (final preset in ThemePresetColor.values)
              _ColorSwatch(
                color: preset.color,
                tooltip: preset.label,
                isSelected:
                    widget.value != 0 &&
                    preset.color.toARGB32() == widget.value,
                onTap: () {
                  widget.onChanged(preset.color.toARGB32());
                  setState(() => _showHexInput = false);
                },
              ),
            // Custom color button
            Tooltip(
              message: 'Custom color',
              child: InkWell(
                onTap: () => setState(
                  () => _showHexInput = !_showHexInput,
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const SweepGradient(
                      colors: [
                        Colors.red,
                        Colors.orange,
                        Colors.yellow,
                        Colors.green,
                        Colors.blue,
                        Colors.purple,
                        Colors.red,
                      ],
                    ),
                    border: _isCustomColor(currentColor)
                        ? Border.all(
                            color: borderColor,
                            width: 2.5,
                          )
                        : Border.all(
                            color: borderColor
                                .withValues(alpha: 0.3),
                          ),
                  ),
                  child: _isCustomColor(currentColor)
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (_showHexInput) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_previewColor != null)
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _previewColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: borderColor
                          .withValues(alpha: 0.3),
                    ),
                  ),
                ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _hexController,
                  decoration: const InputDecoration(
                    hintText: '#FF5722',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(7),
                  ],
                  onChanged: _onHexChanged,
                  onSubmitted: (_) => _applyHex(),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed:
                    _previewColor != null
                        ? _applyHex
                        : null,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  bool _isCustomColor(Color color) {
    if (widget.value == 0) return false;
    return ThemePresetColor.values
        .every((p) => p.color.toARGB32() != color.toARGB32());
  }
}

// ---------------------------------------------------------------------
// Color swatch circle
// ---------------------------------------------------------------------

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        Theme.of(context).colorScheme.outline;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: borderColor,
                    width: 2.5,
                  )
                : Border.all(
                    color: borderColor
                        .withValues(alpha: 0.3),
                  ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// "Default" swatch (uses accent color)
// ---------------------------------------------------------------------

class _DefaultColorSwatch extends StatelessWidget {
  const _DefaultColorSwatch({
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = colorScheme.outline;

    return Tooltip(
      message: 'Default (accent color)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: borderColor,
                    width: 2.5,
                  )
                : Border.all(
                    color: borderColor
                        .withValues(alpha: 0.3),
                  ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 16,
                  color: colorScheme.onSurface,
                )
              : Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
