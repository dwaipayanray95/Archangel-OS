import 'package:flutter/material.dart';

import '../theme.dart';

/// A surface that groups related content. With [onTap] it becomes one
/// keyboard-focusable button (with [semanticsLabel] as its spoken name,
/// otherwise its text content is read).
class AxCard extends StatelessWidget {
  const AxCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.selected = false,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool selected;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final radius = BorderRadius.circular(ax.radii.lg);
    final inner = Padding(padding: padding ?? EdgeInsets.all(ax.space.lg), child: child);
    final card = Material(
      color: selected ? c.accentWash : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: selected ? c.accent : c.border, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? inner
          : InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: axMinTarget(context)),
                child: inner,
              ),
            ),
    );
    if (onTap == null) {
      return semanticsLabel == null ? card : Semantics(container: true, label: semanticsLabel, child: card);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      container: true,
      child: card,
    );
  }
}
