import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../components/ax_button.dart';
import '../theme.dart';
import 'desktop_prefs.dart';
import 'destinations.dart';

/// "Customize the desktop": wallpaper, where the dock sits, how big it is,
/// whether it hides itself, the health widget and which apps the dock keeps.
Future<void> showDesktopCustomize(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const DesktopCustomizeDialog());
}

class DesktopCustomizeDialog extends StatelessWidget {
  const DesktopCustomizeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final prefs = context.watch<DesktopPrefs>();
    Widget heading(String t) => Padding(
      padding: EdgeInsets.only(top: ax.space.lg, bottom: ax.space.sm),
      child: Text(t, style: ax.typo.label.copyWith(color: c.text)),
    );
    final order = [
      ...prefs.pinned,
      for (final s in AxSection.values)
        if (!prefs.isPinned(s)) s,
    ];
    return Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.xl), side: BorderSide(color: c.glassBorder)),
      insetPadding: EdgeInsets.all(ax.space.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(ax.space.xl, ax.space.xl, ax.space.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customize the desktop', style: ax.typo.headline.copyWith(color: c.text)),
                  SizedBox(height: ax.space.xs),
                  Text('Make it yours. Saved on this device.', style: ax.typo.body.copyWith(color: c.textMuted)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: ax.space.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading('Wallpaper'),
                    Wrap(
                      spacing: ax.space.sm,
                      runSpacing: ax.space.sm,
                      children: [
                        for (final w in DeskWallpaper.values)
                          DeskWallpaperSwatch(wallpaper: w, selected: prefs.wallpaper == w, onTap: () => prefs.wallpaper = w),
                      ],
                    ),
                    heading('Dock position'),
                    SegmentedButton<DockPosition>(
                      key: const ValueKey('dock-position'),
                      segments: const [
                        ButtonSegment(value: DockPosition.left, label: Text('Left'), icon: Icon(Icons.align_horizontal_left)),
                        ButtonSegment(value: DockPosition.bottom, label: Text('Bottom'), icon: Icon(Icons.align_vertical_bottom)),
                        ButtonSegment(value: DockPosition.right, label: Text('Right'), icon: Icon(Icons.align_horizontal_right)),
                      ],
                      selected: {prefs.dockPosition},
                      onSelectionChanged: (v) => prefs.dockPosition = v.first,
                    ),
                    heading('Dock size'),
                    SegmentedButton<DockSize>(
                      key: const ValueKey('dock-size'),
                      segments: const [
                        ButtonSegment(value: DockSize.small, label: Text('Small')),
                        ButtonSegment(value: DockSize.medium, label: Text('Medium')),
                        ButtonSegment(value: DockSize.large, label: Text('Large')),
                      ],
                      selected: {prefs.dockSize},
                      onSelectionChanged: (v) => prefs.dockSize = v.first,
                    ),
                    SizedBox(height: ax.space.md),
                    SwitchListTile(
                      key: const ValueKey('dock-autohide'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Hide the dock automatically', style: ax.typo.body.copyWith(color: c.text)),
                      subtitle: Text('It slides back when you point at its edge.', style: ax.typo.caption.copyWith(color: c.textMuted)),
                      value: prefs.autoHide,
                      onChanged: (v) => prefs.autoHide = v,
                    ),
                    SwitchListTile(
                      key: const ValueKey('show-widget'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show the health widget', style: ax.typo.body.copyWith(color: c.text)),
                      subtitle: Text(
                        'CPU, memory and disk at a glance, on the desktop.',
                        style: ax.typo.caption.copyWith(color: c.textMuted),
                      ),
                      value: prefs.showWidget,
                      onChanged: (v) => prefs.showWidget = v,
                    ),
                    SwitchListTile(
                      key: const ValueKey('show-wallpaper-wordmark'),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Show wordmark on wallpaper', style: ax.typo.body.copyWith(color: c.text)),
                      subtitle: Text(
                        'Display the Archangel OS wordmark on the desktop.',
                        style: ax.typo.caption.copyWith(color: c.textMuted),
                      ),
                      value: prefs.showWallpaperWordmark,
                      onChanged: (v) => prefs.showWallpaperWordmark = v,
                    ),
                    heading('In the dock'),
                    for (final s in order)
                      _PinRow(
                        section: s,
                        pinned: prefs.isPinned(s),
                        canUp: prefs.isPinned(s) && prefs.pinned.first != s,
                        canDown: prefs.isPinned(s) && prefs.pinned.last != s,
                        onToggle: () => prefs.togglePin(s),
                        onMove: (by) => prefs.movePin(s, by),
                      ),
                    SizedBox(height: ax.space.md),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(ax.space.xl, ax.space.sm, ax.space.xl, ax.space.xl),
              child: Row(
                children: [
                  AxButton.ghost(label: 'Reset to default', onPressed: prefs.reset),
                  const Spacer(),
                  AxButton(label: 'Done', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DeskWallpaperSwatch extends StatelessWidget {
  const DeskWallpaperSwatch({super.key, required this.wallpaper, required this.selected, required this.onTap});
  final DeskWallpaper wallpaper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final second = wallpaper.secondGlow;
    final preview =
        wallpaper.base == null
            // Halo: the theme's own glows.
            ? DecoratedBox(
              decoration: BoxDecoration(
                color: c.bg,
                gradient: RadialGradient(center: const Alignment(-0.8, -0.8), radius: 1.3, colors: [c.orbA, c.orbA.withValues(alpha: 0)]),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: const Alignment(0.9, 0.9), radius: 1.2, colors: [c.orbB, c.orbB.withValues(alpha: 0)]),
                ),
              ),
            )
            : DecoratedBox(
              decoration: BoxDecoration(color: wallpaper.base),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (second != null) DecoratedBox(decoration: BoxDecoration(gradient: second)),
                  DecoratedBox(decoration: BoxDecoration(gradient: wallpaper.gradient)),
                ],
              ),
            );
    return Semantics(
      button: true,
      selected: selected,
      label: '${wallpaper.label} wallpaper',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: wallpaper.label,
        child: InkWell(
          key: ValueKey('wall-${wallpaper.name}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(ax.radii.md),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 92,
                height: 58,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(ax.radii.md),
                  border: Border.all(color: selected ? c.accent : c.border, width: selected ? 2 : 1),
                ),
                child: ClipRRect(borderRadius: BorderRadius.circular(ax.radii.md - 3), child: preview),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[Icon(Icons.check_circle, size: 13, color: c.accent), const SizedBox(width: 3)],
                  Text(wallpaper.label, style: ax.typo.caption.copyWith(color: selected ? c.text : c.textMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinRow extends StatelessWidget {
  const _PinRow({
    required this.section,
    required this.pinned,
    required this.canUp,
    required this.canDown,
    required this.onToggle,
    required this.onMove,
  });

  final AxSection section;
  final bool pinned;
  final bool canUp;
  final bool canDown;
  final VoidCallback onToggle;
  final void Function(int by) onMove;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final label = axSectionLabels[section]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(axSectionIcons[section], size: 20, color: pinned ? c.accent : c.textSubtle),
          SizedBox(width: ax.space.md),
          Expanded(child: Text(label, style: ax.typo.body.copyWith(color: pinned ? c.text : c.textMuted))),
          IconButton(tooltip: 'Move $label up', icon: const Icon(Icons.keyboard_arrow_up), onPressed: canUp ? () => onMove(-1) : null),
          IconButton(tooltip: 'Move $label down', icon: const Icon(Icons.keyboard_arrow_down), onPressed: canDown ? () => onMove(1) : null),
          Switch(key: ValueKey('pin-${section.name}'), value: pinned, onChanged: (_) => onToggle()),
        ],
      ),
    );
  }
}
