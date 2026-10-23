import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/devops_model.dart';
import '../../components/ax_button.dart';
import '../../components/ax_card.dart';
import '../../components/ax_list_tile.dart';
import '../../components/status_badge.dart';
import '../../theme.dart';
import 'services_logic.dart';

/// Pill tabs with mono counts, horizontally scrolling when narrow.
class ServicesPillTabs extends StatelessWidget {
  const ServicesPillTabs({super.key, required this.currentTab, required this.counts, required this.onSelect});

  final ServicesTab currentTab;
  final Map<ServicesTab, int> counts;
  final ValueChanged<ServicesTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in ServicesTab.values) ...[_buildTabPill(context, ax, c, tab), SizedBox(width: ax.space.sm)],
        ],
      ),
    );
  }

  Widget _buildTabPill(BuildContext context, ArchangelTheme ax, AxPalette c, ServicesTab tab) {
    final isSelected = tab == currentTab;
    final count = counts[tab] ?? 0;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${tab.label} $count',
      child: Material(
        color: isSelected ? c.accentWash : c.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ax.radii.pill),
          side: BorderSide(color: isSelected ? c.accent : c.border),
        ),
        child: InkWell(
          onTap: () => onSelect(tab),
          borderRadius: BorderRadius.circular(ax.radii.pill),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md + 2, vertical: ax.space.xs + 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tab.label,
                  style: ax.typo.label.copyWith(
                    color: isSelected ? c.text : c.textMuted,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                SizedBox(width: ax.space.xs + 2),
                Text(
                  '$count',
                  style: ax.typo.mono.copyWith(color: isSelected ? c.accent : c.textMuted, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A service row in Wide layout (>= 720) reusing AxListTile.
class WideServiceRow extends StatelessWidget {
  const WideServiceRow({super.key, required this.row, required this.actions, this.inlineResult});

  final DevRowModel row;
  final List<Widget> actions;
  final Widget? inlineResult;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final badge = rowStatusBadge(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AxListTile(
          title: row.name,
          titleMono: true,
          subtitle: row.meta.isNotEmpty ? row.meta : null,
          controls: [
            badge,
            if (actions.isNotEmpty) ...[SizedBox(width: ax.space.sm), ...actions],
          ],
        ),
        if (inlineResult != null) Padding(padding: EdgeInsets.fromLTRB(ax.space.md, 0, ax.space.md, ax.space.sm), child: inlineResult!),
        Divider(height: 1, color: c.border.withValues(alpha: 0.3)),
      ],
    );
  }
}

/// A service row in Compact layout (< 720, down to 340).
/// Line 1: name + badge
/// Line 2: meta
/// Line 3: actions
class CompactServiceRow extends StatelessWidget {
  const CompactServiceRow({super.key, required this.row, required this.actions, this.inlineResult});

  final DevRowModel row;
  final List<Widget> actions;
  final Widget? inlineResult;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final badge = rowStatusBadge(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.all(ax.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Line 1: Name + Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(row.name, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w600, color: c.text))),
                  SizedBox(width: ax.space.xs),
                  FittedBox(fit: BoxFit.scaleDown, child: badge),
                ],
              ),
              // Line 2: Meta
              if (row.meta.isNotEmpty) ...[SizedBox(height: 2), Text(row.meta, style: ax.typo.caption.copyWith(color: c.textMuted))],
              // Line 3: Actions
              if (actions.isNotEmpty) ...[SizedBox(height: ax.space.sm), Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)],
              if (inlineResult != null) ...[SizedBox(height: ax.space.xs), inlineResult!],
            ],
          ),
        ),
        Divider(height: 1, color: c.border.withValues(alpha: 0.3)),
      ],
    );
  }
}

/// 4 skeleton placeholder rows during first load.
class ServicesLoadingSkeleton extends StatelessWidget {
  const ServicesLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return AxCard(
      padding: EdgeInsets.all(ax.space.md),
      child: Column(
        children: [
          for (int i = 0; i < 4; i++) ...[
            if (i > 0) SizedBox(height: ax.space.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(4)),
                      ),
                      SizedBox(height: 6),
                      Container(
                        width: 90,
                        height: 10,
                        decoration: BoxDecoration(color: c.surfaceHigh.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 70,
                  height: 24,
                  decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(ax.radii.pill)),
                ),
                SizedBox(width: ax.space.sm),
                Container(
                  width: 60,
                  height: 32,
                  decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(ax.radii.pill)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Per-group error view displayed when that group failed to load.
class GroupErrorView extends StatelessWidget {
  const GroupErrorView({super.key, required this.groupNameLower, required this.onRetry});

  final String groupNameLower;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(ax.space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: c.danger),
            SizedBox(height: ax.space.md),
            Text("Couldn't load $groupNameLower", style: ax.typo.headline.copyWith(color: c.text), textAlign: TextAlign.center),
            SizedBox(height: ax.space.xs),
            Text(
              "Your server didn't answer. Check that it's online, then try again.",
              style: ax.typo.body.copyWith(color: c.textMuted),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ax.space.lg),
            AxButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Displays the read-only deployment content in a dialog (wide) or full sheet (compact).
void showDeploymentContent(BuildContext context, {required String name, required String content, required bool isWide}) {
  if (isWide) {
    showDialog(context: context, builder: (context) => _DeploymentDialog(name: name, content: content));
  } else {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => _DeploymentSheet(name: name, content: content));
  }
}

class _DeploymentDialog extends StatelessWidget {
  const _DeploymentDialog({required this.name, required this.content});

  final String name;
  final String content;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 540),
        child: Padding(
          padding: EdgeInsets.all(ax.space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(name, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w700, fontSize: 16, color: c.text))),
                  const StatusBadge.neutral('Read only'),
                ],
              ),
              SizedBox(height: ax.space.md),
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(ax.space.md),
                  decoration: BoxDecoration(
                    color: c.surfaceHigh,
                    borderRadius: BorderRadius.circular(ax.radii.md),
                    border: Border.all(color: c.border),
                  ),
                  child: SingleChildScrollView(child: SelectableText(content, style: ax.typo.mono.copyWith(fontSize: 12, color: c.text))),
                ),
              ),
              SizedBox(height: ax.space.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AxButton.secondary(
                    label: 'Copy',
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: content));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                    },
                  ),
                  SizedBox(width: ax.space.sm),
                  AxButton.ghost(label: 'Close', onPressed: () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeploymentSheet extends StatelessWidget {
  const _DeploymentSheet({required this.name, required this.content});

  final String name;
  final String content;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        padding: EdgeInsets.all(ax.space.lg),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(ax.radii.lg))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: ax.typo.mono.copyWith(fontWeight: FontWeight.w700, fontSize: 16, color: c.text))),
                const StatusBadge.neutral('Read only'),
              ],
            ),
            SizedBox(height: ax.space.md),
            Expanded(
              child: Container(
                padding: EdgeInsets.all(ax.space.md),
                decoration: BoxDecoration(
                  color: c.surfaceHigh,
                  borderRadius: BorderRadius.circular(ax.radii.md),
                  border: Border.all(color: c.border),
                ),
                child: SingleChildScrollView(child: SelectableText(content, style: ax.typo.mono.copyWith(fontSize: 12, color: c.text))),
              ),
            ),
            SizedBox(height: ax.space.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AxButton.secondary(
                  label: 'Copy',
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                  },
                ),
                SizedBox(width: ax.space.sm),
                AxButton.ghost(label: 'Close', onPressed: () => Navigator.pop(context)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
