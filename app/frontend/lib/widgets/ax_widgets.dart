import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Card surface matching --ax-s1 panels with a hairline border, used for
/// tiles, panels, and rows throughout every section.
class AxCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const AxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = AxRadius.xl,
    this.onTap,
  });

  @override
  State<AxCard> createState() => _AxCardState();
}

class _AxCardState extends State<AxCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return MouseRegion(
      cursor: w.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: w.onTap,
        child: AnimatedContainer(
          duration: AxMotion.base,
          curve: AxMotion.easeOutSoft,
          transform: _hover && w.onTap != null ? (Matrix4.identity()..translate(0.0, -2.0)) : Matrix4.identity(),
          padding: w.padding,
          decoration: BoxDecoration(
            color: _hover ? AxColors.s2 : AxColors.s1,
            borderRadius: BorderRadius.circular(w.radius),
            border: Border.all(color: _hover ? AxColors.line2 : AxColors.line),
          ),
          child: w.child,
        ),
      ),
    );
  }
}

/// Small filled/outline pill used for status labels (e.g. container state).
class AxPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? background;

  const AxPill({super.key, required this.text, required this.color, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AxRadius.pill),
      ),
      child: Text(
        text,
        style: AxTextStyles.mono.copyWith(fontSize: 9.5, fontWeight: FontWeight.w500, color: color),
      ),
    );
  }
}

/// A live status dot with an optional pulsing halo animation.
class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool pulse;

  const StatusDot({super.key, required this.color, this.size = 7, this.pulse = false});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!pulse) return dot;
    return _Pulse(color: color, size: size, child: dot);
  }
}

class _Pulse extends StatefulWidget {
  final Widget child;
  final Color color;
  final double size;
  const _Pulse({required this.child, required this.color, required this.size});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final scale = 1 - 0.22 * (1 - (t - 0.5).abs() * 2).clamp(0, 1);
        final opacity = 1 - 0.65 * (1 - (t - 0.5).abs() * 2).clamp(0, 1);
        return Opacity(
          opacity: opacity.toDouble(),
          child: Transform.scale(scale: scale.toDouble(), child: widget.child),
        );
      },
    );
  }
}

/// Pill-shaped segmented control (used for device switch, monitoring tabs,
/// containers cards/table toggle).
class AxSegmented<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final void Function(T) onSelect;

  const AxSegmented({super.key, required this.values, required this.selected, required this.label, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AxColors.s1,
        borderRadius: BorderRadius.circular(AxRadius.pill),
        border: Border.all(color: AxColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            _SegButton(
              label: label(v),
              selected: v == selected,
              onTap: () => onSelect(v),
            ),
        ],
      ),
    );
    // On narrow (phone-width) parents the segments can be wider than the
    // screen - scroll sideways instead of overflowing. Unbounded parents
    // (e.g. inside a Row) keep the plain intrinsic-width bar.
    return LayoutBuilder(
      builder: (context, constraints) => constraints.hasBoundedWidth
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: bar)
          : bar,
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AxMotion.base,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AxRadius.pill),
        ),
        child: Text(
          label,
          style: AxTextStyles.sans.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AxColors.bg : AxColors.fg2,
          ),
        ),
      ),
    );
  }
}

/// A hairline-outlined pill button (renice/restart/etc row actions).
class AxGhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;

  const AxGhostButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = AxColors.fg2,
    this.borderColor = AxColors.line,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverGhost(label: label, onTap: onTap, color: color, borderColor: borderColor);
  }
}

class _HoverGhost extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color borderColor;
  const _HoverGhost({required this.label, required this.onTap, required this.color, required this.borderColor});

  @override
  State<_HoverGhost> createState() => _HoverGhostState();
}

class _HoverGhostState extends State<_HoverGhost> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AxMotion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: _hover ? AxColors.s3 : Colors.transparent,
            borderRadius: BorderRadius.circular(AxRadius.pill),
            border: Border.all(color: widget.borderColor),
          ),
          child: Text(
            widget.label,
            style: AxTextStyles.sans.copyWith(fontSize: 10.5, fontWeight: FontWeight.w600, color: _hover ? AxColors.fg : widget.color),
          ),
        ),
      ),
    );
  }
}

/// Thin capsule progress meter (cpu/mem bars on container cards).
class AxMeter extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  const AxMeter({super.key, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AxRadius.pill),
      child: Container(
        height: 3,
        color: AxColors.s3,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0, 1),
          child: AnimatedContainer(duration: AxMotion.pop, curve: AxMotion.easeOutSnap, color: color),
        ),
      ),
    );
  }
}

/// Multi-segment progress meter (used for unified memory and disk breakdown).
class AxSegmentMeter extends StatelessWidget {
  final List<(double, Color)> segments; // ratio (0..1), color
  final double height;

  const AxSegmentMeter({super.key, required this.segments, this.height = 6});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AxRadius.pill),
      child: Container(
        height: height,
        color: AxColors.s3,
        child: Row(
          children: [
            for (final s in segments)
              if (s.$1 > 0.001)
                Flexible(
                  flex: (s.$1 * 1000).round(),
                  child: Container(color: s.$2),
                ),
            // Remaining unallocated
            () {
              final total = segments.fold(0.0, (acc, e) => acc + e.$1);
              final remaining = (1.0 - total).clamp(0.0, 1.0);
              if (remaining > 0.001) {
                return Flexible(
                  flex: (remaining * 1000).round(),
                  child: Container(color: AxColors.s3),
                );
              }
              return const SizedBox.shrink();
            }(),
          ],
        ),
      ),
    );
  }
}
