import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The Halo wallpaper: the theme background with three soft glows
/// (violet top-left, teal bottom-right, a faint highlight up top).
///
/// Everything in the app shell sits on this. It is painted once and kept in
/// its own layer, so scrolling content over it costs nothing extra.
class AxBackdrop extends StatelessWidget {
  const AxBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    Widget glow(Alignment at, double radius, Color color) => Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: at, radius: radius, colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: c.bg),
              glow(const Alignment(-1.1, -1.1), 1.25, c.wallA),
              glow(const Alignment(1.1, 1.1), 1.25, c.wallB),
              glow(const Alignment(0.45, -0.55), 0.8, c.wallC),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

/// A frosted-glass surface.
///
/// [strong] uses the denser glass meant for bars, windows and the dock.
/// [blur] adds a real backdrop blur; keep it for surfaces that float over
/// moving content (bottom bar, dock, windows) since every blur is a
/// separate compositing pass, which matters on phones.
class AxGlass extends StatelessWidget {
  const AxGlass({
    super.key,
    required this.child,
    this.padding,
    this.radius,
    this.strong = false,
    this.blur = false,
    this.shadow = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final bool strong;
  final bool blur;
  final bool shadow;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final r = BorderRadius.circular(radius ?? ax.radii.lg);
    final light = ax.brightness == Brightness.light;
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? c.glassStrong : c.glass,
        borderRadius: r,
        border: Border.all(color: borderColor ?? c.glassBorder),
        boxShadow: shadow || (light && !strong)
            ? [
                BoxShadow(
                  color: (light ? const Color(0xFF3C328C) : Colors.black).withValues(alpha: shadow ? (light ? 0.16 : 0.45) : 0.07),
                  blurRadius: shadow ? 40 : 24,
                  offset: Offset(0, shadow ? 14 : 8),
                ),
              ]
            : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (blur) {
      box = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: box),
      );
    }
    return box;
  }
}

/// A status pill that always pairs an icon (or spinner) with words, tinted
/// by [tone]. Used by the connection strip and anywhere a compact status
/// sits inline.
class AxPill extends StatelessWidget {
  const AxPill({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
    this.icon,
    this.busy = false,
    this.trailing,
    this.dense = false,
  });

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool busy;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final size = dense ? 14.0 : 16.0;
    return Container(
      constraints: BoxConstraints(minHeight: dense ? 28 : 36),
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(dense ? ax.radii.pill : ax.radii.md)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: size - 2,
              height: size - 2,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            )
          else if (icon != null)
            Icon(icon, size: size, color: fg),
          SizedBox(width: ax.space.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ax.typo.caption.copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 13),
            ),
          ),
          if (trailing != null) ...[SizedBox(width: ax.space.sm), trailing!],
        ],
      ),
    );
  }
}
