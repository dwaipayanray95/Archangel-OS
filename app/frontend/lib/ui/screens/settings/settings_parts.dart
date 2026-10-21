import 'package:flutter/material.dart';

import '../../ui.dart';

/// A Settings card: an optional header (title and small actions), then rows
/// separated by hairlines, then an optional footnote. Rows are [AxListTile]s
/// with `controls`, or one of the plain message widgets below.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, this.title, this.actions = const [], required this.children, this.footnote, this.danger = false});

  final String? title;
  final List<Widget> actions;
  final List<Widget> children;

  /// Caption under the rows.
  final String? footnote;

  /// Draws the edge of the card in the danger colour.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final divider = Divider(height: 1, thickness: 1, color: c.border);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 || title != null) rows.add(divider);
      rows.add(children[i]);
    }
    return AxCard(
      padding: EdgeInsets.zero,
      borderColor: danger ? c.danger : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: ax.space.md,
                runSpacing: ax.space.sm,
                children: [
                  Semantics(header: true, child: Text(title!, style: ax.typo.title.copyWith(color: c.text))),
                  if (actions.isNotEmpty)
                    Wrap(spacing: ax.space.sm, runSpacing: ax.space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
                ],
              ),
            ),
          ...rows,
          if (footnote != null) ...[
            divider,
            Padding(padding: EdgeInsets.all(ax.space.lg), child: Text(footnote!, style: ax.typo.caption.copyWith(color: c.textMuted))),
          ],
        ],
      ),
    );
  }
}

/// A line of muted text inside a [SettingsCard] (an empty state).
class SettingsMessage extends StatelessWidget {
  const SettingsMessage(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Padding(padding: EdgeInsets.all(ax.space.lg), child: Text(text, style: ax.typo.body.copyWith(color: ax.colors.textMuted)));
  }
}

/// An error line (and optional retry) inside a [SettingsCard].
class SettingsError extends StatelessWidget {
  const SettingsError(this.text, {super.key, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Padding(
      padding: EdgeInsets.all(ax.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: c.danger),
              SizedBox(width: ax.space.sm),
              Expanded(child: Text(text, style: ax.typo.body.copyWith(color: c.danger))),
            ],
          ),
          if (onRetry != null) ...[SizedBox(height: ax.space.sm), AxButton.secondary(label: 'Retry', small: true, onPressed: onRetry)],
        ],
      ),
    );
  }
}

/// A small spinner inside a [SettingsCard] while something loads.
class SettingsLoading extends StatelessWidget {
  const SettingsLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.ax.space.lg),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
