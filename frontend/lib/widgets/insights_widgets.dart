import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Standard [InputDecoration] used across CC-Insights.
///
/// Provides the consistent filled, outlined style with 6px border
/// radius, subtle borders, and primary-color focus highlight.
InputDecoration insightsInputDecoration(
  BuildContext context, {
  String? hintText,
  bool monospace = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return InputDecoration(
    isDense: true,
    hintText: hintText,
    hintStyle: TextStyle(
      fontSize: 13,
      fontFamily: monospace ? 'JetBrains Mono' : null,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: colorScheme.primary),
    ),
  );
}

/// Standard text style for settings text fields.
TextStyle insightsInputTextStyle(
  BuildContext context, {
  bool monospace = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
    fontSize: 13,
    fontFamily: monospace ? 'JetBrains Mono' : null,
    color: colorScheme.onSurface,
  );
}

/// A text field styled for CC-Insights.
///
/// Use [monospace] for command/code inputs (renders in JetBrains Mono).
class InsightsTextField extends StatelessWidget {
  const InsightsTextField({
    super.key,
    this.controller,
    this.hintText,
    this.monospace = false,
    this.onSubmitted,
    this.onTapOutside,
    this.textAlign = TextAlign.start,
    this.prefixIcon,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String? hintText;
  final bool monospace;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final TextAlign textAlign;
  final Widget? prefixIcon;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textAlign: textAlign,
      autofocus: autofocus,
      focusNode: focusNode,
      style: insightsInputTextStyle(context, monospace: monospace),
      decoration: insightsInputDecoration(
        context,
        hintText: hintText,
        monospace: monospace,
      ).copyWith(prefixIcon: prefixIcon),
      onSubmitted: onSubmitted,
      onTapOutside: onTapOutside,
    );
  }
}

/// A number-only text field styled for CC-Insights.
///
/// Clamps the value between [min] and [max] on submit or blur.
class InsightsNumberField extends StatefulWidget {
  const InsightsNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  State<InsightsNumberField> createState() => _InsightsNumberFieldState();
}

class _InsightsNumberFieldState extends State<InsightsNumberField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(InsightsNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final parsed = int.tryParse(text);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _controller.text = clamped.toString();
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: insightsInputTextStyle(context),
        decoration: insightsInputDecoration(context).copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        onSubmitted: _submit,
        onTapOutside: (_) => _submit(_controller.text),
      ),
    );
  }
}

/// A primary action button styled for CC-Insights.
///
/// Renders as a [FilledButton] with 12px font and 8px vertical padding.
/// Use [icon] for a leading icon variant.
class InsightsFilledButton extends StatelessWidget {
  const InsightsFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.backgroundColor,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: const TextStyle(fontSize: 12),
    );

    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
        style: style,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

/// A tonal button with an icon, styled for CC-Insights.
///
/// Renders as [FilledButton.tonalIcon] with 12px font.
class InsightsTonalButton extends StatelessWidget {
  const InsightsTonalButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

/// A secondary action button styled for CC-Insights.
///
/// Renders as an [OutlinedButton] with subtle border and 12px font.
/// Use [icon] for a leading icon variant.
class InsightsOutlinedButton extends StatelessWidget {
  const InsightsOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = OutlinedButton.styleFrom(
      foregroundColor: colorScheme.onSurfaceVariant,
      side: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: const TextStyle(fontSize: 12),
    );

    if (icon != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon!,
        label: child,
        style: style,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

/// A compact inline dropdown styled for CC-Insights.
///
/// Matches the Settings screen style with filled background, 8px border radius,
/// and compact padding. Designed to sit inline in a row layout.
class InsightsDropdown<T> extends StatelessWidget {
  const InsightsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.onSurface,
          ),
          dropdownColor: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Rich text that renders inline \`code\` spans with a highlighted
/// background, matching the CC-Insights description style.
class InsightsDescriptionText extends StatelessWidget {
  const InsightsDescriptionText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
        children: _parseInlineCode(context),
      ),
    );
  }

  List<InlineSpan> _parseInlineCode(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final codePattern = RegExp(r'`([^`]+)`');
    var lastEnd = 0;

    for (final match in codePattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match.group(1)!,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
      );
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans;
  }
}
