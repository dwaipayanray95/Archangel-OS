import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/server_registry.dart';
import '../components/ax_glass.dart';
import '../components/ax_wordmark.dart';
import '../theme.dart';
import 'destinations.dart';
import 'server_switcher.dart';

/// The glass sidebar of the Simple layout on tablets and computers:
/// wordmark, server switcher, the seven destinations and (when there is
/// room) the switch into Desktop mode.
///
/// [extended] shows labels; the narrow variant is icons with tooltips.
class AxSidebar extends StatelessWidget {
  const AxSidebar({super.key, required this.extended, required this.selected, required this.onSelect, this.onDesktopMode});

  final bool extended;
  final AxSection selected;
  final void Function(AxSection) onSelect;

  /// Null hides the Desktop mode button (window too small for it).
  final VoidCallback? onDesktopMode;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final width = extended ? 248.0 : 84.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(ax.space.md, ax.space.md, 0, ax.space.md),
      child: SizedBox(
        width: width,
        child: AxGlass(
          radius: ax.radii.lg,
          child: LayoutBuilder(
            builder:
                (context, box) => SingleChildScrollView(
                  padding: EdgeInsets.all(extended ? ax.space.md + 2 : ax.space.sm + 2),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - (extended ? 28 : 20)),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (extended)
                            Padding(
                              padding: EdgeInsets.fromLTRB(ax.space.sm, ax.space.xs, ax.space.sm, ax.space.lg),
                              child: const Align(alignment: Alignment.centerLeft, child: AxWordmark()),
                            ),
                          _SwitcherCard(compact: !extended),
                          SizedBox(height: ax.space.md),
                          for (final s in AxSection.values)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: SidebarItem(
                                key: ValueKey('side-${s.name}'),
                                section: s,
                                extended: extended,
                                selected: s == selected,
                                onTap: () => onSelect(s),
                              ),
                            ),
                          const Spacer(),
                          if (onDesktopMode != null) ...[
                            SizedBox(height: ax.space.md),
                            _ModeButton(extended: extended, onTap: onDesktopMode!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

/// One destination row in the sidebar.
class SidebarItem extends StatelessWidget {
  const SidebarItem({super.key, required this.section, required this.extended, required this.selected, required this.onTap});

  final AxSection section;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final label = axSectionLabels[section]!;
    final fg = selected ? c.accent : c.text;
    final item = Material(
      color: selected ? c.accentWash : Colors.transparent,
      borderRadius: BorderRadius.circular(ax.radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ax.radii.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: axMinTarget(context) + 4),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md),
            child: Row(
              mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(selected ? axSectionSelectedIcons[section] : axSectionIcons[section], size: 20, color: fg),
                if (extended) ...[
                  SizedBox(width: ax.space.md),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ax.typo.body.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: extended ? item : Tooltip(message: label, child: item),
    );
  }
}

class _SwitcherCard extends StatelessWidget {
  const _SwitcherCard({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final registry = context.watch<ServerRegistry>();
    final active = registry.active;
    final name = active?.name ?? 'No server';
    return Semantics(
      button: true,
      label: 'Server: $name. Switch server',
      excludeSemantics: true,
      onTap: () => showServerSheet(context),
      child: Tooltip(
        message: 'Switch server',
        child: Material(
          color: c.glassStrong,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md), side: BorderSide(color: c.border)),
          child: InkWell(
            onTap: () => showServerSheet(context),
            borderRadius: BorderRadius.circular(ax.radii.md),
            child: Padding(
              padding: EdgeInsets.all(compact ? ax.space.sm : ax.space.sm + 2),
              child: Row(
                mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(ax.radii.sm)),
                    child: Icon(Icons.dns_outlined, size: 18, color: c.accent),
                  ),
                  if (!compact) ...[
                    SizedBox(width: ax.space.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ax.typo.mono.copyWith(color: c.text, fontWeight: FontWeight.w600),
                          ),
                          if (active != null && active.host.isNotEmpty)
                            Text(
                              active.host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ax.typo.caption.copyWith(color: c.textMuted),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.unfold_more, size: 18, color: c.textMuted),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.extended, required this.onTap});
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    const label = 'Desktop mode';
    final child = OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.pill)),
        minimumSize: Size(axMinTarget(context), axMinTarget(context)),
        padding: EdgeInsets.symmetric(horizontal: ax.space.md),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.desktop_windows_outlined, size: 18),
          if (extended) ...[SizedBox(width: ax.space.sm), Text(label, style: ax.typo.label)],
        ],
      ),
    );
    return Semantics(
      button: true,
      label: 'Switch to Desktop mode',
      excludeSemantics: true,
      onTap: onTap,
      child: extended ? child : Tooltip(message: 'Switch to $label', child: child),
    );
  }
}
