import 'package:flutter/material.dart';

import '../theme.dart';

enum AxButtonKind { primary, secondary, danger, ghost }

/// The app's button. Keyboard focusable, announces its label to screen
/// readers, and never smaller than the platform's minimum touch target.
///
/// A null [onPressed] disables it; [loading] shows a spinner, keeps the
/// label and ignores taps.
class AxButton extends StatelessWidget {
  const AxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AxButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.small = false,
    this.semanticsLabel,
  });

  const AxButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.small = false,
    this.semanticsLabel,
  }) : kind = AxButtonKind.secondary;

  const AxButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.small = false,
    this.semanticsLabel,
  }) : kind = AxButtonKind.danger;

  const AxButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.small = false,
    this.semanticsLabel,
  }) : kind = AxButtonKind.ghost;

  final String label;
  final VoidCallback? onPressed;
  final AxButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  /// A tighter button for rows and card headers. It keeps the minimum touch
  /// target; only the padding and text shrink.
  final bool small;

  /// Overrides the spoken label when the visible text alone is ambiguous
  /// (for example "Remove" in a list - "Remove web-app").
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final target = axMinTarget(context);
    final enabled = onPressed != null && !loading;

    final (Color bg, Color fg, BorderSide? side) = switch (kind) {
      AxButtonKind.primary => (c.accent, c.onAccent, null),
      AxButtonKind.danger => (c.danger, c.onDanger, null),
      AxButtonKind.secondary => (c.glassStrong, c.text, BorderSide(color: c.outline)),
      AxButtonKind.ghost => (Colors.transparent, c.accent, null),
    };

    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(target, target)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: WidgetStatePropertyAll(
        small
            ? EdgeInsets.symmetric(horizontal: ax.space.md, vertical: ax.space.xs)
            : EdgeInsets.symmetric(horizontal: ax.space.lg + 2, vertical: ax.space.sm),
      ),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.pill))),
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(small ? ax.typo.label.copyWith(fontSize: 13) : ax.typo.label),
      backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.surfaceHigh : bg),
      foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.textSubtle : fg),
      side: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.focused)) return BorderSide(color: c.text, width: 2);
        if (s.contains(WidgetState.disabled)) return side == null ? null : BorderSide(color: c.border);
        return side;
      }),
      overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: 0.12)),
    );

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else if (icon != null)
          Icon(icon, size: small ? 16 : 18),
        if (loading || icon != null) SizedBox(width: ax.space.sm),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );

    final callback = enabled ? onPressed : null;
    final Widget button = kind == AxButtonKind.ghost
        ? TextButton(onPressed: callback, style: style, child: content)
        : FilledButton(onPressed: callback, style: style, child: content);

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: callback,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
