import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
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
                            Text(label(v), style: ax.typo.label.copyWith(color: v == selected ? c.text : c.textMuted)),
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
/// by colour alone. Powered by fl_chart with interactive tooltips and smooth curves.
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
    final top = maxY <= 0 ? 1.0 : maxY;
    final maxPoints = series.fold<int>(0, (prev, s) => math.max(prev, s.values.length));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: semanticsLabel,
          image: true,
          child: SizedBox(
            height: height,
            child:
                hasData
                    ? Padding(
                      padding: const EdgeInsets.only(right: 12, top: 4),
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          maxY: top,
                          minX: 0,
                          maxX: math.max(1, (maxPoints - 1)).toDouble(),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: top / 2,
                            getDrawingHorizontalLine:
                                (val) => FlLine(color: c.border.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [4, 4]),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 64,
                                interval: top / 2,
                                getTitlesWidget: (value, meta) {
                                  if (value > top * 1.02 || value < -0.02) return const SizedBox.shrink();
                                  return SideTitleWidget(
                                    meta: meta,
                                    child: Text(formatY(value), style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 11)),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border(bottom: BorderSide(color: c.outline.withValues(alpha: 0.5), width: 1)),
                          ),
                          lineBarsData: [
                            for (final s in series)
                              if (s.values.length >= 2)
                                LineChartBarData(
                                  spots: [
                                    for (int i = 0; i < s.values.length; i++) FlSpot(i.toDouble(), s.values[i].clamp(0.0, top * 1.5)),
                                  ],
                                  isCurved: true,
                                  curveSmoothness: 0.28,
                                  preventCurveOverShooting: true,
                                  color: s.color,
                                  barWidth: 2.2,
                                  isStrokeCapRound: true,
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [s.color.withValues(alpha: 0.22), s.color.withValues(alpha: 0.01)],
                                    ),
                                  ),
                                ),
                          ],
                          lineTouchData: LineTouchData(
                            enabled: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => c.glassStrong,
                              tooltipBorder: BorderSide(color: c.glassBorder),
                              tooltipBorderRadius: BorderRadius.circular(8),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (touchedSpots) {
                                final validSeries = series.where((s) => s.values.length >= 2).toList();
                                return touchedSpots.map((spot) {
                                  if (spot.barIndex >= validSeries.length) return null;
                                  final s = validSeries[spot.barIndex];
                                  return LineTooltipItem(
                                    '${s.label}: ${formatY(spot.y)}',
                                    ax.typo.caption.copyWith(color: s.color, fontWeight: FontWeight.w600, fontSize: 11.5),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                        ),
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOutCubic,
                      ),
                    )
                    : Center(child: Text('Collecting readings...', style: ax.typo.body.copyWith(color: c.textMuted))),
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
