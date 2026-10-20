import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui.dart';
import 'services_logic.dart';

/// One button on a row.
class RowAction {
  const RowAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.kind = AxButtonKind.secondary,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AxButtonKind kind;
  final bool loading;
}

/// Segmented tabs that wrap onto a second row on a narrow phone instead of
/// squashing or hiding labels.
class ServicesTabBar extends StatelessWidget {
  const ServicesTabBar({super.key, required this.selected, required this.onSelected});

  final ServicesTab selected;
  final ValueChanged<ServicesTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final target = axMinTarget(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(ax.radii.lg), border: Border.all(color: c.border)),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final t in ServicesTab.values)
            Semantics(
              button: true,
              selected: t == selected,
              label: t.label,
              excludeSemantics: true,
              child: Material(
                color: t == selected ? c.accentWash : Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ax.radii.md),
                  side: BorderSide(color: t == selected ? c.accent : Colors.transparent, width: 1.5),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(ax.radii.md),
                  onTap: () => onSelected(t),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: target),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: ax.space.lg),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t == selected) ...[Icon(Icons.check_rounded, size: 16, color: c.text), SizedBox(width: ax.space.xs)],
                          Text(
                            t.label,
                            style: ax.typo.label.copyWith(
                              color: t == selected ? c.text : c.textMuted,
                              fontWeight: t == selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one-line explanation at the top of a tab, with its (i) help.
class TabIntro extends StatelessWidget {
  const TabIntro({super.key, required this.text, required this.helpTitle, required this.helpText});

  final String text;
  final String helpTitle;
  final String helpText;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(text, style: ax.typo.body.copyWith(color: ax.colors.textMuted))),
        HelpTip(title: helpTitle, message: helpText),
      ],
    );
  }
}

/// Prominent message when the server refuses an action (admin mode off, a
/// protected service, ...). Stays until dismissed.
class RefusalBanner extends StatelessWidget {
  const RefusalBanner({super.key, required this.message, required this.onDismiss, this.onOpenSettings, this.title});

  final String message;
  final String? title;
  final VoidCallback onDismiss;

  /// Shown as an "Open Settings" button when the refusal is about Admin mode.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: EdgeInsets.all(ax.space.lg),
        decoration: BoxDecoration(
          color: c.warningWash,
          borderRadius: BorderRadius.circular(ax.radii.md),
          border: Border.all(color: c.warning, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: c.warning),
            SizedBox(width: ax.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title ?? 'That wasn’t allowed', style: ax.typo.title.copyWith(color: c.text)),
                  SizedBox(height: ax.space.xs),
                  Text(message, style: ax.typo.body.copyWith(color: c.text)),
                  if (onOpenSettings != null) ...[
                    SizedBox(height: ax.space.md),
                    AxButton(label: 'Open Settings', icon: Icons.settings_outlined, onPressed: onOpenSettings),
                  ],
                ],
              ),
            ),
            AxIconButton(icon: Icons.close_rounded, tooltip: 'Dismiss message', onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}

/// A calmer notice for "could not refresh" while stale data is still shown.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Container(
      padding: EdgeInsets.all(ax.space.md),
      decoration: BoxDecoration(
        color: c.warningWash,
        borderRadius: BorderRadius.circular(ax.radii.md),
        border: Border.all(color: c.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c.warning),
          SizedBox(width: ax.space.sm),
          Expanded(child: Text(message, style: ax.typo.body.copyWith(color: c.text))),
        ],
      ),
    );
  }
}

/// One item in a Services list: a card on phones, a table-like row on wide
/// screens. [footer] shows under it (for example a "Test" result).
class ServiceRow extends StatelessWidget {
  const ServiceRow({
    super.key,
    required this.name,
    required this.details,
    required this.badge,
    required this.actions,
    required this.wide,
    this.footer,
  });

  final String name;
  final String details;
  final Widget badge;
  final List<RowAction> actions;
  final bool wide;
  final Widget? footer;

  Widget _button(RowAction a) =>
      AxButton(label: a.label, icon: a.icon, kind: a.kind, loading: a.loading, onPressed: a.onPressed, semanticsLabel: '${a.label} $name');

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final nameText = Text(name, style: ax.typo.label.copyWith(color: c.text), overflow: TextOverflow.ellipsis, maxLines: 2);
    final detailText =
        details.isEmpty
            ? null
            : Text(details, style: ax.typo.caption.copyWith(color: c.textMuted), maxLines: 2, overflow: TextOverflow.ellipsis);

    if (wide) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(flex: 3, child: nameText),
                SizedBox(width: ax.space.md),
                Expanded(flex: 3, child: detailText ?? const SizedBox.shrink()),
                SizedBox(width: ax.space.md),
                SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: badge)),
                SizedBox(
                  width: 400,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: ax.space.xs,
                    runSpacing: ax.space.xs,
                    children: [
                      for (final a in actions)
                        _button(
                          a.kind == AxButtonKind.secondary
                              ? RowAction(
                                label: a.label,
                                icon: a.icon,
                                onPressed: a.onPressed,
                                kind: AxButtonKind.ghost,
                                loading: a.loading,
                              )
                              : a,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (footer != null) Padding(padding: EdgeInsets.only(top: ax.space.xs), child: footer),
          ],
        ),
      );
    }
    return AxCard(
      semanticsLabel: name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nameText,
                    if (detailText != null) ...[const SizedBox(height: 2), detailText],
                  ],
                ),
              ),
              SizedBox(width: ax.space.sm),
              badge,
            ],
          ),
          if (actions.isNotEmpty) ...[
            SizedBox(height: ax.space.md),
            Wrap(spacing: ax.space.sm, runSpacing: ax.space.sm, children: [for (final a in actions) _button(a)]),
          ],
          if (footer != null) ...[SizedBox(height: ax.space.sm), footer!],
        ],
      ),
    );
  }
}

/// Column headings for the wide table layout.
class ServiceTableHeader extends StatelessWidget {
  const ServiceTableHeader({super.key, required this.detailsLabel});
  final String detailsLabel;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    Widget head(String t) => Text(t, style: ax.typo.caption.copyWith(color: ax.colors.textMuted, fontWeight: FontWeight.w700));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ax.space.lg, vertical: ax.space.md),
      child: Row(
        children: [
          Expanded(flex: 3, child: head('Name')),
          SizedBox(width: ax.space.md),
          Expanded(flex: 3, child: head(detailsLabel)),
          SizedBox(width: ax.space.md),
          SizedBox(width: 150, child: head('Status')),
          const SizedBox(width: 400),
        ],
      ),
    );
  }
}

/// Result line shown under a web address after "Test".
class TestResultLine extends StatelessWidget {
  const TestResultLine({super.key, required this.testing, this.result});

  final bool testing;
  final String? result;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    if (testing) {
      return Row(
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
          SizedBox(width: ax.space.sm),
          Text('Testing...', style: ax.typo.caption.copyWith(color: c.textMuted)),
        ],
      );
    }
    final failed = result == null;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(failed ? Icons.error_outline : Icons.check_circle_outline, size: 16, color: failed ? c.danger : c.success),
          SizedBox(width: ax.space.xs + 2),
          Expanded(
            child: Text(
              failed ? 'The test could not run. Check that your server is reachable and try again.' : 'Test result: $result',
              style: ax.typo.caption.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a bottom sheet with a script's output and a Copy button.
Future<void> showRunOutputSheet(
  BuildContext context, {
  required String scriptName,
  required bool ok,
  required String message,
  required String output,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => RunOutputSheet(scriptName: scriptName, ok: ok, message: message, output: output),
  );
}

class RunOutputSheet extends StatefulWidget {
  const RunOutputSheet({super.key, required this.scriptName, required this.ok, required this.message, required this.output});

  final String scriptName;
  final bool ok;
  final String message;
  final String output;

  @override
  State<RunOutputSheet> createState() => _RunOutputSheetState();
}

class _RunOutputSheetState extends State<RunOutputSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.output));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final maxH = MediaQuery.sizeOf(context).height * 0.5;
    final hasOutput = widget.output.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(ax.space.xl, 0, ax.space.xl, ax.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Output of ${widget.scriptName}', style: ax.typo.title.copyWith(color: c.text))),
            SizedBox(height: ax.space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: widget.ok ? const StatusBadge.ok('Finished') : const StatusBadge.error('Did not finish'),
            ),
            if (widget.message.isNotEmpty) ...[
              SizedBox(height: ax.space.sm),
              Text(widget.message, style: ax.typo.body.copyWith(color: c.textMuted)),
            ],
            SizedBox(height: ax.space.md),
            Container(
              constraints: BoxConstraints(maxHeight: maxH),
              padding: EdgeInsets.all(ax.space.md),
              decoration: BoxDecoration(
                color: c.surfaceHigh,
                borderRadius: BorderRadius.circular(ax.radii.md),
                border: Border.all(color: c.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  hasOutput ? widget.output : 'The script finished without printing anything.',
                  style: ax.typo.mono.copyWith(color: hasOutput ? c.text : c.textMuted),
                ),
              ),
            ),
            SizedBox(height: ax.space.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: ax.space.sm,
              runSpacing: ax.space.sm,
              children: [
                if (hasOutput)
                  AxButton.secondary(
                    label: _copied ? 'Copied' : 'Copy',
                    icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                    onPressed: _copy,
                  ),
                AxButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
