import 'package:flutter/material.dart';

/// A ListView that caches item heights for stable scrollbar behavior.
///
/// Standard ListView.builder estimates heights for items not yet rendered,
/// causing scrollbar jumping when items have varying heights. This widget
/// measures and caches heights as items are built, then uses a large
/// cacheExtent to pre-render more items for better scroll estimation.
class MeasuredListView extends StatefulWidget {
  const MeasuredListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.estimatedItemHeight = 100.0,
  });

  /// Number of items in the list.
  final int itemCount;

  /// Builder for individual items.
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Optional scroll controller.
  final ScrollController? controller;

  /// Padding around the list content.
  final EdgeInsetsGeometry? padding;

  /// Estimated height for items that haven't been measured yet.
  final double estimatedItemHeight;

  @override
  State<MeasuredListView> createState() => _MeasuredListViewState();
}

class _MeasuredListViewState extends State<MeasuredListView> {
  /// Cache of measured heights keyed by item index.
  final Map<int, double> _heightCache = {};

  /// Report a measured height for an item.
  void _onItemMeasured(int index, double height) {
    final cached = _heightCache[index];
    // Only update if significantly different (avoid floating point noise)
    if (cached == null || (cached - height).abs() > 1.0) {
      _heightCache[index] = height;
    }
  }

  @override
  void didUpdateWidget(MeasuredListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear cache entries beyond the new item count
    if (widget.itemCount < oldWidget.itemCount) {
      _heightCache.removeWhere((key, _) => key >= widget.itemCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a large cacheExtent to pre-render more items off-screen.
    // This helps the scrollbar be more accurate by actually measuring
    // more items before the user scrolls to them.
    return ListView.builder(
      controller: widget.controller,
      padding: widget.padding,
      itemCount: widget.itemCount,
      // Render 2000 pixels of content above and below the viewport
      cacheExtent: 2000,
      itemBuilder: (context, index) {
        return _MeasuredItem(
          index: index,
          onMeasured: _onItemMeasured,
          child: widget.itemBuilder(context, index),
        );
      },
    );
  }
}

/// Wrapper widget that measures its child and reports the height.
class _MeasuredItem extends StatefulWidget {
  const _MeasuredItem({
    required this.index,
    required this.onMeasured,
    required this.child,
  });

  final int index;
  final void Function(int index, double height) onMeasured;
  final Widget child;

  @override
  State<_MeasuredItem> createState() => _MeasuredItemState();
}

class _MeasuredItemState extends State<_MeasuredItem> {
  @override
  void initState() {
    super.initState();
    _scheduleHeightMeasurement();
  }

  @override
  void didUpdateWidget(_MeasuredItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _scheduleHeightMeasurement();
    }
  }

  void _scheduleHeightMeasurement() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          widget.onMeasured(widget.index, renderBox.size.height);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
