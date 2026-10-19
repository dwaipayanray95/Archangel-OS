import 'package:flutter/material.dart';

import '../../ui.dart';

/// A Settings card: heading (with an optional help tip and trailing widget),
/// a one-line plain explanation, then the content.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.explanation,
    required this.child,
    this.help,
    this.trailing,
    this.danger = false,
  });

  final String title;
  final String explanation;
  final Widget child;
  final HelpTip? help;
  final Widget? trailing;

  /// Heading in the danger colour (the Danger zone).
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return AxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (danger) ...[
                Icon(Icons.warning_amber_rounded, color: c.danger),
                SizedBox(width: ax.space.sm),
              ],
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(title, style: ax.typo.title.copyWith(color: danger ? c.danger : c.text)),
                ),
              ),
              if (help != null) help!,
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          SizedBox(height: ax.space.xs),
          Text(explanation, style: ax.typo.body.copyWith(color: c.textMuted)),
          SizedBox(height: ax.space.md),
          child,
        ],
      ),
    );
  }
}

/// A label with its value (and optional trailing widgets) that wraps rather
/// than overflows on narrow screens.
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.trailing, this.mono = false});

  final String label;
  final String value;
  final bool mono;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ax.space.xs + 2),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ax.space.md,
        runSpacing: ax.space.xs,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140),
            child: Text(label, style: ax.typo.body.copyWith(color: c.textMuted)),
          ),
          Text(value, style: (mono ? ax.typo.mono : ax.typo.body).copyWith(color: c.text, fontWeight: FontWeight.w600)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

void showSnack(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatSettingsDate(DateTime d) {
  final l = d.toLocal();
  return '${_months[l.month - 1]} ${l.day}, ${l.year}';
}
