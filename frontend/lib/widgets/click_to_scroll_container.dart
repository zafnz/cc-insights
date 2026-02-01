import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A container that requires a click to enable scrolling of its child.
///
/// This widget solves the "nested scroll" UX problem where scrollable content
/// inside a scrollable parent captures scroll events unexpectedly. The inner
/// scrollable area is inert for scrolling until explicitly activated (clicked).
///
/// When inactive:
/// - Scroll events pass through to the parent scrollable
/// - A subtle visual indicator shows the content is scrollable
///
/// When active:
/// - Normal scrolling behavior within the container
/// - Clicking outside or pressing Escape deactivates it
///
/// Example:
/// ```dart
/// ClickToScrollContainer(
///   maxHeight: 300,
///   child: SelectableText(longText),
/// )
/// ```
class ClickToScrollContainer extends StatefulWidget {
  /// The child widget to wrap in a scrollable container.
  final Widget child;

  /// Maximum height before scrolling is enabled.
  final double maxHeight;

  /// Padding inside the scrollable area.
  final EdgeInsetsGeometry? padding;

  /// Background color of the container.
  final Color? backgroundColor;

  /// Border radius for the container.
  final BorderRadius? borderRadius;

  const ClickToScrollContainer({
    super.key,
    required this.child,
    required this.maxHeight,
    this.padding,
    this.backgroundColor,
    this.borderRadius,
  });

  @override
  State<ClickToScrollContainer> createState() =>
      _ClickToScrollContainerState();
}

class _ClickToScrollContainerState extends State<ClickToScrollContainer> {
  bool _isActive = false;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    // Check if content needs scrolling after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfNeedsScroll();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isActive) {
      setState(() => _isActive = false);
    }
  }

  void _checkIfNeedsScroll() {
    if (!mounted) return;
    if (_scrollController.hasClients) {
      final needsScroll =
          _scrollController.position.maxScrollExtent > 0;
      if (needsScroll != _needsScroll) {
        setState(() => _needsScroll = needsScroll);
      }
    }
  }

  void _activate() {
    if (!_needsScroll) return;
    setState(() => _isActive = true);
    _focusNode.requestFocus();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_isActive || !_needsScroll) return;

    if (event is PointerScrollEvent) {
      final delta = event.scrollDelta.dy;
      final currentOffset = _scrollController.offset;
      final maxOffset = _scrollController.position.maxScrollExtent;

      // Calculate new offset, clamped to valid range
      final newOffset = (currentOffset + delta).clamp(0.0, maxOffset);
      _scrollController.jumpTo(newOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        // Deactivate on Escape
        if (event.logicalKey == LogicalKeyboardKey.escape && _isActive) {
          setState(() => _isActive = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _activate,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: _needsScroll && !_isActive
              ? SystemMouseCursors.click
              : SystemMouseCursors.text,
          child: Listener(
            // Intercept scroll events directly when active
            onPointerSignal: _handlePointerSignal,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Update _needsScroll when scroll metrics change
                if (notification is ScrollMetricsNotification) {
                  _checkIfNeedsScroll();
                }
                return false;
              },
              child: Container(
                constraints: BoxConstraints(maxHeight: widget.maxHeight),
                decoration: BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: widget.borderRadius,
                  border: _needsScroll && !_isActive
                      ? Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                          width: 1,
                        )
                      : _isActive
                          ? Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.5),
                              width: 1,
                            )
                          : null,
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: widget.padding ?? EdgeInsets.zero,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const NeverScrollableScrollPhysics(),
                        child: widget.child,
                      ),
                    ),
                    // Scroll indicator when inactive and scrollable
                    if (_needsScroll && !_isActive)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: _ScrollIndicator(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual indicator showing that content is scrollable.
class _ScrollIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.unfold_more,
            size: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 2),
          Text(
            'click to scroll',
            style: TextStyle(
              fontSize: 9,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
