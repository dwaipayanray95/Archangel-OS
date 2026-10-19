import 'package:flutter/material.dart';

import '../../theme.dart';
import '../home/home_logic.dart' show usageStatus;
import '../../components/status_badge.dart';

/// A horizontally scrollable segmented control: never overflows on a phone.
class ScrollableSegments<T> extends StatelessWidget {
  const ScrollableSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.icon,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final target = axMinTarget(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(ax.radii.md + 3),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final v in values)
              Semantics(
                button: true,
                selected: v == selected,
                label: label(v),
                excludeSemantics: true,
                child: Material(
                  color: v == selected ? c.accentWash : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ax.radii.md),
                    side: BorderSide(color: v == selected ? c.accent : Colors.transparent),
                  ),
                  child: InkWell(
                    onTap: () => onSelect(v),
                    borderRadius: BorderRadius.circular(ax.radii.md),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: target, minWidth: 64),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (icon != null) ...[
                              Icon(icon!(v), size: 16, color: v == selected ? c.accent : c.textMuted),
                              SizedBox(width: ax.space.xs + 2),
                            ],
                            Text(
                              label(v),
                              style: ax.typo.label.copyWith(color: v == selected ? c.text : c.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChartSeries {
  const ChartSeries({required this.label, required this.values, required this.color});
  final String label;
  final List<double> values;
  final Color color;
}

/// A line chart with a y-axis from 0 to [maxY]. Colours come from the theme
/// (passed in by the caller). Series are told apart by the legend text, not
/// by colour alone.
class LiveChart extends StatelessWidget {
  const LiveChart({
    super.key,
    required this.series,
    required this.maxY,
    required this.formatY,
    required this.semanticsLabel,
    this.height = 180,
  });

  final List<ChartSeries> series;
  final double maxY;
  final String Function(double) formatY;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final hasData = series.any((s) => s.values.length >= 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: semanticsLabel,
          image: true,
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatY(maxY), style: ax.typo.caption.copyWith(color: c.textMuted)),
                      Text(formatY(maxY / 2), style: ax.typo.caption.copyWith(color: c.textMuted)),
                      Text(formatY(0), style: ax.typo.caption.copyWith(color: c.textMuted)),
                    ],
                  ),
                ),
                SizedBox(width: ax.space.sm),
                Expanded(
                  child: hasData
                      ? CustomPaint(
                          painter: _ChartPainter(series: series, maxY: maxY, grid: c.border, axis: c.outline),
                        )
                      : Center(
                          child: Text('Collecting readings...', style: ax.typo.body.copyWith(color: c.textMuted)),
                        ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: ax.space.sm),
        Wrap(
          spacing: ax.space.lg,
          runSpacing: ax.space.xs,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 14, height: 4, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
                  SizedBox(width: ax.space.xs + 2),
                  Text(s.label, style: ax.typo.caption.copyWith(color: c.textMuted)),
                ],
              ),
          ],
        ),
        SizedBox(height: ax.space.xs),
        Text('Live (since you opened this screen)', style: ax.typo.caption.copyWith(color: c.textSubtle)),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.series, required this.maxY, required this.grid, required this.axis});
  final List<ChartSeries> series;
  final double maxY;
  final Color grid;
  final Color axis;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), f == 0 ? (Paint()..color = axis..strokeWidth = 1) : gridPaint);
    }
    final top = maxY <= 0 ? 1.0 : maxY;
    for (final s in series) {
      final n = s.values.length;
      if (n < 2) continue;
      final dx = size.width / (n - 1);
      final path = Path();
      for (var i = 0; i < n; i++) {
        final y = size.height * (1 - (s.values[i] / top).clamp(0.0, 1.0));
        i == 0 ? path.moveTo(0, y) : path.lineTo(i * dx, y);
      }
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.color.withValues(alpha: 0.20), s.color.withValues(alpha: 0.0)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}

/// A labelled horizontal usage bar with its percentage as text.
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.percent, required this.label, this.trailing});
  final double percent;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final p = (percent.isFinite ? percent : 0).clamp(0, 100).toDouble();
    final fill = switch (usageStatus(p)) {
      AxStatus.error => c.danger,
      AxStatus.warning => c.warning,
      _ => c.accent,
    };
    return Semantics(
      label: '$label ${p.round()} percent',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: ax.typo.body.copyWith(color: c.text), overflow: TextOverflow.ellipsis)),
              SizedBox(width: ax.space.sm),
              Text(trailing ?? '${p.round()}%', style: ax.typo.label.copyWith(color: c.textMuted)),
            ],
          ),
          SizedBox(height: ax.space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(ax.radii.pill),
            child: Stack(
              children: [
                Container(height: 8, color: c.surfaceHigh),
                FractionallySizedBox(widthFactor: p / 100, child: Container(height: 8, color: fill)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
