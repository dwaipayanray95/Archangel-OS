import 'package:flutter/material.dart';

import '../theme.dart';

enum AxStatus { ok, warning, error, info, neutral }

/// A small pill that always pairs an icon with text, so status never relies
/// on colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.status, this.icon});

  const StatusBadge.ok(this.label, {super.key, this.icon}) : status = AxStatus.ok;
  const StatusBadge.warning(this.label, {super.key, this.icon}) : status = AxStatus.warning;
  const StatusBadge.error(this.label, {super.key, this.icon}) : status = AxStatus.error;
  const StatusBadge.info(this.label, {super.key, this.icon}) : status = AxStatus.info;
  const StatusBadge.neutral(this.label, {super.key, this.icon}) : status = AxStatus.neutral;

  final String label;
  final AxStatus status;

  /// Overrides the status's default icon.
  final IconData? icon;

  static IconData defaultIcon(AxStatus s) => switch (s) {
    AxStatus.ok => Icons.check_circle_outline,
    AxStatus.warning => Icons.warning_amber_rounded,
    AxStatus.error => Icons.error_outline,
    AxStatus.info => Icons.info_outline,
    AxStatus.neutral => Icons.remove_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final (Color fg, Color bg) = switch (status) {
      AxStatus.ok => (c.success, c.successWash),
      AxStatus.warning => (c.warning, c.warningWash),
      AxStatus.error => (c.danger, c.dangerWash),
      AxStatus.info => (c.info, c.infoWash),
      AxStatus.neutral => (c.textMuted, c.surfaceHigh),
    };
    return Semantics(
      label: label,
      container: true,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(ax.radii.pill),
          border: Border.all(color: fg.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? defaultIcon(status), size: 16, color: fg),
            SizedBox(width: ax.space.xs + 2),
            Flexible(child: Text(label, style: ax.typo.caption.copyWith(color: fg, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
