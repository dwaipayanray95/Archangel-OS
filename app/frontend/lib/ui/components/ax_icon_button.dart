import 'package:flutter/material.dart';

import '../theme.dart';

/// An icon-only button. [tooltip] is required: it is the accessible name for
/// screen readers and the hover/long-press hint for everyone else.
class AxIconButton extends StatelessWidget {
  const AxIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.color,
    this.showBadge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Color? color;

  /// Draws a small attention dot on the icon (it should also be described in
  /// the [tooltip], e.g. "Notifications (new)").
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final target = axMinTarget(context);
    return IconButton(
      icon: showBadge ? Badge(smallSize: 8, backgroundColor: c.accent, child: Icon(icon)) : Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      constraints: BoxConstraints(minWidth: target, minHeight: target),
      style: IconButton.styleFrom(
        foregroundColor: color ?? (selected ? c.accent : c.textMuted),
        backgroundColor: selected ? c.accentWash : Colors.transparent,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size(target, target),
        disabledForegroundColor: c.textSubtle,
      ),
    );
  }
}
