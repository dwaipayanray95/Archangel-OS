import 'package:flutter/material.dart';

/// A small animated line+area sparkline, matching the mockup's inline SVG
/// polylines/paths. Values are normalized 0..1 by the caller.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final bool filled;

  const Sparkline({super.key, required this.values, required this.color, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder:
          (context, t, _) =>
              CustomPaint(painter: _SparkPainter(values: values, color: color, filled: filled, progress: t), size: Size.infinite),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final bool filled;
  final double progress;

  _SparkPainter({required this.values, required this.color, required this.filled, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final n = values.length;
    final dx = size.width / (n - 1);
    final points = <Offset>[for (var i = 0; i < n; i++) Offset(i * dx, size.height * (1 - values[i].clamp(0, 1)))];

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }

    if (filled) {
      final areaPath =
          Path.from(linePath)
            ..lineTo(points.last.dx, size.height)
            ..lineTo(points.first.dx, size.height)
            ..close();
      final areaPaint =
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
            ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      canvas.drawPath(areaPath, areaPaint);
      canvas.restore();
    }

    final linePaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final metric = linePath.computeMetrics().first;
    final extracted = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(extracted, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color || oldDelegate.progress != progress;
}
