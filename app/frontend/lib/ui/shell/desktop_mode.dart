import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/server_registry.dart';
import '../components/ax_glass.dart';
import '../components/ax_wordmark.dart';
import '../theme.dart';
import 'destinations.dart';
import 'server_switcher.dart';
import 'status_strip.dart';

/// Height of Desktop mode's top bar.
const double kDeskTopBarHeight = 48;

/// Space kept free at the bottom for the dock.
const double kDeskDockReserve = 92;

/// Smallest a window may be resized to.
const Size kDeskMinWindow = Size(340, 260);

/// One open window in Desktop mode. Each destination has at most one.
class DeskWindow {
  DeskWindow({required this.section, required this.rect, required this.z});

  final AxSection section;
  Rect rect;
  int z;
  bool minimized = false;
  Rect? restoreRect;

  bool get maximized => restoreRect != null;
}

/// Window manager state for Desktop mode: which destinations are open,
/// where, in which stacking order, and whether the launcher is showing.
///
/// Pure geometry and bookkeeping, no widgets, so it can be unit tested.
class DesktopWindows extends ChangeNotifier {
  final List<DeskWindow> _windows = [];
  int _z = 0;
  bool _launcherOpen = false;
  bool _seeded = false;

  /// The usable area for windows (below the top bar, above the dock).
  Size area = const Size(1200, 700);

  List<DeskWindow> get windows => List.unmodifiable(_windows);

  /// Back-to-front order for painting.
  List<DeskWindow> get stacked => [..._windows]..sort((a, b) => a.z.compareTo(b.z));

  bool get launcherOpen => _launcherOpen;
  bool get isEmpty => _windows.isEmpty;

  DeskWindow? windowFor(AxSection s) {
    for (final w in _windows) {
      if (w.section == s) return w;
    }
    return null;
  }

  bool isOpen(AxSection s) => windowFor(s) != null;

  /// The front-most window that isn't minimized.
  AxSection? get front {
    DeskWindow? best;
    for (final w in _windows) {
      if (w.minimized) continue;
      if (best == null || w.z > best.z) best = w;
    }
    return best?.section;
  }

  /// Destinations currently on screen (open and not minimized).
  Set<AxSection> get visible => {
    for (final w in _windows)
      if (!w.minimized) w.section,
  };

  /// The first layout: Home on the left, Terminal and Files cascaded.
  /// Runs once per session (closing every window later leaves the desk
  /// empty). Doesn't notify: it is called while building.
  void ensureDefaults() {
    if (_seeded) return;
    _seeded = true;
    if (_windows.isNotEmpty) return;
    final a = area;
    final homeW = math.min(440.0, a.width * 0.36);
    _add(AxSection.home, Rect.fromLTWH(24, 16, homeW, math.max(kDeskMinWindow.height, a.height - 32)));
    final right = 24 + homeW + 20;
    final termW = math.max(kDeskMinWindow.width, math.min(640.0, a.width - right - 24));
    _add(AxSection.terminal, Rect.fromLTWH(right, 16, termW, math.max(kDeskMinWindow.height, a.height * 0.52)));
    final filesW = math.max(kDeskMinWindow.width, math.min(680.0, a.width - right - 64));
    final filesTop = math.min(a.height * 0.36, a.height - kDeskMinWindow.height - 8);
    _add(
      AxSection.files,
      Rect.fromLTWH(
        math.min(right + 60, math.max(24, a.width - filesW - 24)),
        math.max(16, filesTop),
        filesW,
        math.max(kDeskMinWindow.height, a.height - filesTop - 16),
      ),
    );
  }

  void _add(AxSection s, Rect r) => _windows.add(DeskWindow(section: s, rect: _clamp(r), z: ++_z));

  /// Opens [s] (or brings it back from the dock) in front of the others.
  void open(AxSection s) {
    final w = windowFor(s);
    if (w == null) {
      final n = _windows.length;
      final width = math.max(kDeskMinWindow.width, math.min(820.0, area.width - 120));
      final height = math.max(kDeskMinWindow.height, math.min(580.0, area.height - 40));
      _add(s, Rect.fromLTWH(60.0 + (n % 6) * 32, 20.0 + (n % 6) * 26, width, height));
    } else {
      w.minimized = false;
      w.z = ++_z;
    }
    _launcherOpen = false;
    notifyListeners();
  }

  /// Raises [s] to the front. Returns false if it already was.
  bool focus(AxSection s) {
    final w = windowFor(s);
    if (w == null || front == s) return false;
    w.z = ++_z;
    w.minimized = false;
    notifyListeners();
    return true;
  }

  void minimize(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    w.minimized = true;
    notifyListeners();
  }

  void close(AxSection s) {
    _windows.removeWhere((w) => w.section == s);
    notifyListeners();
  }

  void toggleMaximize(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    if (w.maximized) {
      w.rect = _clamp(w.restoreRect!);
      w.restoreRect = null;
    } else {
      w.restoreRect = w.rect;
      w.rect = Rect.fromLTWH(8, 8, area.width - 16, area.height - 16);
    }
    w.z = ++_z;
    notifyListeners();
  }

  void move(AxSection s, Offset delta) {
    final w = windowFor(s);
    if (w == null) return;
    w.restoreRect = null;
    w.rect = _clamp(w.rect.shift(delta));
    notifyListeners();
  }

  void resize(AxSection s, Offset delta) {
    final w = windowFor(s);
    if (w == null) return;
    w.restoreRect = null;
    final r = w.rect;
    w.rect = Rect.fromLTWH(
      r.left,
      r.top,
      (r.width + delta.dx).clamp(kDeskMinWindow.width, math.max(kDeskMinWindow.width, area.width - r.left)).toDouble(),
      (r.height + delta.dy).clamp(kDeskMinWindow.height, math.max(kDeskMinWindow.height, area.height - r.top)).toDouble(),
    );
    notifyListeners();
  }

  /// Re-fits every window after the screen size changes.
  void fitTo(Size newArea) {
    if (newArea == area) return;
    area = newArea;
    for (final w in _windows) {
      if (w.maximized) {
        w.rect = Rect.fromLTWH(8, 8, area.width - 16, area.height - 16);
      } else {
        w.rect = _clamp(w.rect);
      }
    }
  }

  void toggleLauncher([bool? open]) {
    _launcherOpen = open ?? !_launcherOpen;
    notifyListeners();
  }

  /// Keeps a window's title bar reachable and its size within the area.
  Rect _clamp(Rect r) {
    final double w = r.width.clamp(kDeskMinWindow.width, math.max(kDeskMinWindow.width, area.width)).toDouble();
    final double h = r.height.clamp(kDeskMinWindow.height, math.max(kDeskMinWindow.height, area.height)).toDouble();
    final double left = r.left.clamp(-w + 120, math.max(0.0, area.width - 120)).toDouble();
    final double top = r.top.clamp(0.0, math.max(0.0, area.height - 48)).toDouble();
    return Rect.fromLTWH(left, top, w, h);
  }
}

/// Desktop mode: a wallpaper, a top bar, freely arranged windows hosting
/// the destinations, a dock and a launcher. Inspired by desktop operating
/// systems; available on tablets, phones held sideways and computers.
class DesktopModeView extends StatelessWidget {
  const DesktopModeView({
    super.key,
    required this.windows,
    required this.buildContent,
    required this.onFocus,
    required this.onSimpleLayout,
  });

  final DesktopWindows windows;

  /// Builds (or re-parents, via a GlobalKey) the destination for a window.
  final Widget Function(AxSection) buildContent;

  /// Called when a window comes to the front (keeps AppState.section in step).
  final void Function(AxSection) onFocus;
  final VoidCallback onSimpleLayout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(onSimpleLayout: onSimpleLayout, onLauncher: () => windows.toggleLauncher()),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                bottom: kDeskDockReserve,
                child: LayoutBuilder(
                  builder: (context, box) {
                    windows.fitTo(box.biggest);
                    final front = windows.front;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (windows.visible.isEmpty) const _EmptyDesk(),
                        for (final w in windows.stacked)
                          w.minimized
                              // Minimized windows stay mounted (offstage) so a
                              // terminal session or half-typed form survives.
                              ? Offstage(
                                key: ValueKey('win-${w.section.name}'),
                                child: TickerMode(
                                  enabled: false,
                                  child: SizedBox(width: w.rect.width, height: w.rect.height, child: buildContent(w.section)),
                                ),
                              )
                              : Positioned.fromRect(
                                key: ValueKey('win-${w.section.name}'),
                                rect: w.rect,
                                child: _Window(
                                  window: w,
                                  focused: w.section == front,
                                  windows: windows,
                                  onFocus: onFocus,
                                  child: buildContent(w.section),
                                ),
                              ),
                      ],
                    );
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(
                  child: _Dock(
                    windows: windows,
                    onOpen: (s) {
                      windows.open(s);
                      onFocus(s);
                    },
                  ),
                ),
              ),
              if (windows.launcherOpen)
                Positioned.fill(
                  child: _Launcher(
                    onClose: () => windows.toggleLauncher(false),
                    onOpen: (s) {
                      windows.open(s);
                      onFocus(s);
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyDesk extends StatelessWidget {
  const _EmptyDesk();

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AxWordmark(size: 30),
          SizedBox(height: ax.space.sm),
          Text('Open something from the dock below.', style: ax.typo.body.copyWith(color: ax.colors.textMuted)),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSimpleLayout, required this.onLauncher});
  final VoidCallback onSimpleLayout;
  final VoidCallback onLauncher;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final name = context.watch<ServerRegistry>().active?.name ?? 'No server';
    return AxGlass(
      strong: true,
      blur: true,
      radius: 0,
      borderColor: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kDeskTopBarHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: ax.space.md),
            child: Row(
              children: [
                const AxWordmark(size: 15),
                SizedBox(width: ax.space.md),
                _MiniButton(
                  label: name,
                  mono: true,
                  icon: Icons.dns_outlined,
                  tooltip: 'Switch server',
                  onTap: () => showServerSheet(context),
                ),
                SizedBox(width: ax.space.sm),
                _MiniButton(
                  label: 'Simple layout',
                  icon: Icons.view_sidebar_outlined,
                  tooltip: 'Back to the Simple layout',
                  onTap: onSimpleLayout,
                ),
                SizedBox(width: ax.space.md),
                const Expanded(child: StatusStrip(showServerName: false, compact: true)),
                SizedBox(width: ax.space.sm),
                const _Clock(),
              ],
            ),
          ),
        ),
      ),
    ).withBottomLine(c.border);
  }
}

extension on Widget {
  Widget withBottomLine(Color color) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color))),
    child: this,
  );
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.icon, required this.onTap, this.tooltip, this.mono = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final style = (mono ? ax.typo.mono : ax.typo.caption).copyWith(color: c.text, fontSize: 12.5, fontWeight: FontWeight.w500);
    return Semantics(
      button: true,
      label: tooltip ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          color: c.glass,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.sm), side: BorderSide(color: c.border)),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.sm + 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: c.textMuted),
                    SizedBox(width: ax.space.xs + 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final tod = TimeOfDay.now();
    return Text(
      MaterialLocalizations.of(context).formatTimeOfDay(tod, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context)),
      style: ax.typo.mono.copyWith(color: ax.colors.textMuted, fontSize: 12.5),
    );
  }
}

class _Window extends StatelessWidget {
  const _Window({required this.window, required this.focused, required this.windows, required this.onFocus, required this.child});

  final DeskWindow window;
  final bool focused;
  final DesktopWindows windows;
  final void Function(AxSection) onFocus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final s = window.section;
    final label = axSectionLabels[s]!;
    void focus() {
      if (windows.focus(s)) onFocus(s);
    }

    return Listener(
      onPointerDown: (_) => focus(),
      child: Semantics(
        container: true,
        label: '$label window',
        child: AxGlass(
          strong: true,
          blur: true,
          shadow: true,
          radius: 16,
          borderColor: focused ? c.outline.withValues(alpha: 0.45) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onPanUpdate: (d) => windows.move(s, d.delta),
                      onDoubleTap: () => windows.toggleMaximize(s),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: Container(
                          height: 44,
                          padding: EdgeInsets.only(left: ax.space.md + 2, right: ax.space.xs),
                          decoration: BoxDecoration(
                            color: focused ? c.text.withValues(alpha: 0.04) : Colors.transparent,
                            border: Border(bottom: BorderSide(color: c.border)),
                          ),
                          child: Row(
                            children: [
                              Icon(axSectionIcons[s], size: 16, color: focused ? c.accent : c.textMuted),
                              SizedBox(width: ax.space.sm),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ax.typo.label.copyWith(color: c.text, fontSize: 13),
                                ),
                              ),
                              _WinButton(icon: Icons.remove, tooltip: 'Minimise $label', onTap: () => windows.minimize(s)),
                              _WinButton(
                                icon: window.maximized ? Icons.filter_none : Icons.crop_square,
                                tooltip: window.maximized ? 'Restore $label' : 'Maximise $label',
                                onTap: () => windows.toggleMaximize(s),
                              ),
                              _WinButton(icon: Icons.close, tooltip: 'Close $label', onTap: () => windows.close(s)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanUpdate: (d) => windows.resize(s, d.delta),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: Icon(Icons.south_east, size: 12, color: c.textSubtle.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WinButton extends StatelessWidget {
  const _WinButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: c.textMuted,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.windows, required this.onOpen});
  final DesktopWindows windows;
  final void Function(AxSection) onOpen;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      container: true,
      label: 'Dock',
      child: AxGlass(
        strong: true,
        blur: true,
        shadow: true,
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(icon: Icons.apps_rounded, label: 'All apps', highlighted: true, onTap: () => windows.toggleLauncher()),
            Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 6), color: c.border),
            for (final s in AxSection.values)
              _DockButton(icon: axSectionIcons[s]!, label: axSectionLabels[s]!, open: windows.isOpen(s), onTap: () => onOpen(s)),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({required this.icon, required this.label, required this.onTap, this.open = false, this.highlighted = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool open;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      button: true,
      label: open ? '$label, open' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: highlighted ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 22, color: highlighted ? c.onAccent : c.text),
                    if (open)
                      Positioned(
                        bottom: 4,
                        child: Container(width: 4, height: 4, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Launcher extends StatefulWidget {
  const _Launcher({required this.onClose, required this.onOpen});
  final VoidCallback onClose;
  final void Function(AxSection) onOpen;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  String _q = '';

  static const _blurbs = <AxSection, String>{
    AxSection.home: 'Health at a glance',
    AxSection.apps: 'Run and manage apps',
    AxSection.files: 'Browse and download',
    AxSection.terminal: 'Command line',
    AxSection.activity: 'Live charts',
    AxSection.services: 'Background helpers',
    AxSection.settings: 'Servers, devices, updates',
  };

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final q = _q.trim().toLowerCase();
    final items =
        AxSection.values
            .where((s) => q.isEmpty || axSectionLabels[s]!.toLowerCase().contains(q) || _blurbs[s]!.toLowerCase().contains(q))
            .toList();
    return Stack(
      children: [
        Positioned.fill(child: GestureDetector(onTap: widget.onClose, child: ColoredBox(color: c.scrim.withValues(alpha: 0.35)))),
        Align(
          alignment: const Alignment(0, -0.55),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: EdgeInsets.all(ax.space.xl),
              child: AxGlass(
                strong: true,
                blur: true,
                shadow: true,
                radius: ax.radii.xl,
                padding: EdgeInsets.all(ax.space.lg + 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setState(() => _q = v),
                      onSubmitted: (_) {
                        if (items.isNotEmpty) widget.onOpen(items.first);
                      },
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search apps and places'),
                    ),
                    SizedBox(height: ax.space.lg),
                    if (items.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(ax.space.lg),
                        child: Text('Nothing matches "$_q".', style: ax.typo.body.copyWith(color: c.textMuted)),
                      )
                    else
                      Wrap(
                        spacing: ax.space.sm,
                        runSpacing: ax.space.sm,
                        children: [
                          for (final s in items)
                            SizedBox(
                              width: 120,
                              child: Semantics(
                                button: true,
                                label: 'Open ${axSectionLabels[s]}',
                                excludeSemantics: true,
                                onTap: () => widget.onOpen(s),
                                child: InkWell(
                                  onTap: () => widget.onOpen(s),
                                  borderRadius: BorderRadius.circular(ax.radii.md),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: ax.space.md, horizontal: ax.space.xs),
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 54,
                                          height: 54,
                                          decoration: BoxDecoration(color: c.accentWash, borderRadius: BorderRadius.circular(16)),
                                          child: Icon(axSectionIcons[s], color: c.accent, size: 26),
                                        ),
                                        SizedBox(height: ax.space.sm),
                                        Text(axSectionLabels[s]!, style: ax.typo.label.copyWith(color: c.text, fontSize: 13)),
                                        Text(
                                          _blurbs[s]!,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          style: ax.typo.caption.copyWith(color: c.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
