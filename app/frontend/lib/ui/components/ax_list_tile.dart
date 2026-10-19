import 'package:flutter/material.dart';

import '../theme.dart';

/// A row with optional leading/trailing widgets, a title and a subtitle.
/// Tappable rows are at least one touch target tall.
class AxListTile extends StatelessWidget {
  const AxListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.semanticsLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final tile = ListTile(
      onTap: onTap,
      selected: selected,
      selectedColor: c.text,
      selectedTileColor: c.accentWash,
      iconColor: c.textMuted,
      textColor: c.text,
      minTileHeight: axMinTarget(context),
      contentPadding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.xs),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md)),
      leading: leading,
      trailing: trailing,
      title: Text(title, style: ax.typo.label.copyWith(color: c.text)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: ax.typo.caption.copyWith(color: c.textMuted)),
    );
    if (semanticsLabel == null) return tile;
    return Semantics(label: semanticsLabel, button: onTap != null, container: true, excludeSemantics: true, onTap: onTap, child: tile);
  }
}
