part of 'worktree_panel.dart';

// -----------------------------------------------------------------------------
// Tree indent widgets
// -----------------------------------------------------------------------------

class _IndentGuidePainter extends CustomPainter {
  _IndentGuidePainter({
    required this.color,
    required this.hasTick,
    required this.isLast,
    required this.showLine,
  });

  final Color color;
  final bool hasTick;
  final bool isLast;
  final bool showLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (!showLine && !hasTick) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const lineX = 9.0;

    if (showLine) {
      final bottom = isLast ? size.height / 2 : size.height;
      canvas.drawLine(Offset(lineX, 0), Offset(lineX, bottom), paint);
    }

    if (hasTick) {
      final tickY = size.height / 2;
      canvas.drawLine(Offset(lineX, tickY), Offset(lineX + 8, tickY), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidePainter oldDelegate) =>
      color != oldDelegate.color ||
      hasTick != oldDelegate.hasTick ||
      isLast != oldDelegate.isLast ||
      showLine != oldDelegate.showLine;
}

class _IndentGuide extends StatelessWidget {
  const _IndentGuide({
    this.hasTick = false,
    this.isLast = false,
    this.showLine = true,
  });

  final bool hasTick;
  final bool isLast;
  final bool showLine;

  static const double width = 20.0;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: _IndentGuidePainter(
          color: color,
          hasTick: hasTick,
          isLast: isLast,
          showLine: showLine,
        ),
      ),
    );
  }
}

class _TreeIndentWrapper extends StatelessWidget {
  const _TreeIndentWrapper({
    required this.depth,
    required this.isLast,
    required this.ancestorIsLast,
    required this.child,
  });

  final int depth;
  final bool isLast;
  final List<bool> ancestorIsLast;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (depth == 0) return child;

    Widget result = child;

    // Build inside-out: innermost level first
    for (int i = depth - 1; i >= 0; i--) {
      final isInnermostLevel = (i == depth - 1);
      final isAncestorLast = (i < ancestorIsLast.length) ? ancestorIsLast[i] : false;

      result = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IndentGuide(
            hasTick: isInnermostLevel,
            isLast: isInnermostLevel ? isLast : false,
            showLine: isInnermostLevel || !isAncestorLast,
          ),
          Expanded(child: result),
        ],
      );
    }

    return IntrinsicHeight(child: result);
  }
}

// -----------------------------------------------------------------------------
// Base marker widget
// -----------------------------------------------------------------------------

class _BaseMarker extends StatelessWidget {
  const _BaseMarker({super.key, required this.baseRef});

  final String baseRef;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
      ),
      child: Text(
        baseRef,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}
