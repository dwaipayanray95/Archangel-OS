import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/monitoring_service.dart';
import '../../services/server_registry.dart';
import '../../services/window_service.dart';
import '../screens/home/home_logic.dart';
import '../components/ax_glass.dart';
import '../components/status_badge.dart';
import '../components/ax_wordmark.dart';
import '../theme.dart';
import 'desktop_customize.dart';
import 'desktop_prefs.dart';
import 'destinations.dart';
import 'server_switcher.dart';
import 'status_strip.dart';

/// Height of Desktop mode's top bar.
const double kDeskTopBarHeight = 42;

/// Width of the health widget in the desktop's top-right corner.
const double kDeskWidgetWidth = 248;

/// How close to an edge a dragged title bar must come to snap.
const double kDeskSnapEdge = 10;

/// Corner threshold along the edge for snapping into quadrant corners.
const double kDeskSnapCorner = 64;

/// Where a dragged window will land when let go.
enum DeskSnap { none, maximize, left, right, topLeft, topRight, bottomLeft, bottomRight, thirdLeft, thirdCenter, thirdRight }

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

  /// How the window is snapped while [restoreRect] is set.
  DeskSnap snapped = DeskSnap.none;

  /// Maximized or snapped to half the screen ("Restore" brings it back).
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
  DeskSnap _snap = DeskSnap.none;

  /// The usable area for windows (below the top bar, above the dock).
  Size area = const Size(1200, 700);

  List<DeskWindow> get windows => List.unmodifiable(_windows);

  /// Back-to-front order for painting.
  List<DeskWindow> get stacked => [..._windows]..sort((a, b) => a.z.compareTo(b.z));

  bool get launcherOpen => _launcherOpen;

  /// The snap a window drag would make right now.
  DeskSnap get snap => _snap;

  /// The outline shown while dragging toward an edge, or null.
  Rect? get snapPreview => snapRect(_snap);

  static bool get _systemAltPressed {
    try {
      return HardwareKeyboard.instance.isAltPressed;
    } catch (_) {
      return false;
    }
  }

  /// The rectangle a window takes when snapped to [snap].
  Rect? snapRect(DeskSnap snap) {
    const g = 8.0;
    final half = (area.width - g * 3) / 2;
    final halfH = (area.height - g * 3) / 2;
    final third = (area.width - g * 4) / 3;
    return switch (snap) {
      DeskSnap.none => null,
      DeskSnap.left => Rect.fromLTWH(g, g, half, area.height - g * 2),
      DeskSnap.right => Rect.fromLTWH(g * 2 + half, g, half, area.height - g * 2),
      DeskSnap.maximize => Rect.fromLTWH(g, g, area.width - g * 2, area.height - g * 2),
      DeskSnap.topLeft => Rect.fromLTWH(g, g, half, halfH),
      DeskSnap.topRight => Rect.fromLTWH(g * 2 + half, g, half, halfH),
      DeskSnap.bottomLeft => Rect.fromLTWH(g, g * 2 + halfH, half, halfH),
      DeskSnap.bottomRight => Rect.fromLTWH(g * 2 + half, g * 2 + halfH, half, halfH),
      DeskSnap.thirdLeft => Rect.fromLTWH(g, g, third, area.height - g * 2),
      DeskSnap.thirdCenter => Rect.fromLTWH(g * 2 + third, g, third, area.height - g * 2),
      DeskSnap.thirdRight => Rect.fromLTWH(g * 3 + third * 2, g, third, area.height - g * 2),
    };
  }

  /// Which snap a pointer at [p] (in window-area coordinates) asks for.
  ///
  /// - Top center: [DeskSnap.maximize]
  /// - 4 Corners: [DeskSnap.topLeft], [DeskSnap.topRight],
  ///   [DeskSnap.bottomLeft], [DeskSnap.bottomRight] (quadrants)
  /// - Left / Right mid-edges: [DeskSnap.left], [DeskSnap.right] (halves)
  /// - Bottom edge: 1:1:1 thirds ([DeskSnap.thirdLeft], [DeskSnap.thirdCenter], [DeskSnap.thirdRight])
  /// - Holding Alt / Option while dragging to any edge: 1:1:1 thirds
  DeskSnap snapAt(Offset p, {bool? altPressed}) {
    final alt = altPressed ?? _systemAltPressed;
    final nearLeft = p.dx <= kDeskSnapEdge;
    final nearRight = p.dx >= area.width - kDeskSnapEdge;
    final nearTop = p.dy <= kDeskSnapEdge;
    final nearBottom = p.dy >= area.height - kDeskSnapEdge;

    if (!nearLeft && !nearRight && !nearTop && !nearBottom) {
      return DeskSnap.none;
    }

    if (alt) {
      if (p.dx < area.width / 3) return DeskSnap.thirdLeft;
      if (p.dx > area.width * 2 / 3) return DeskSnap.thirdRight;
      return DeskSnap.thirdCenter;
    }

    final corner = math.min(kDeskSnapCorner, area.height * 0.25);

    // 1. Check four corners first (triggered near corner along either adjacent edge).
    final isTopCorner = p.dy <= corner;
    final isBottomCorner = p.dy >= area.height - corner;
    final isLeftCorner = p.dx <= corner;
    final isRightCorner = p.dx >= area.width - corner;

    if ((nearTop && isLeftCorner) || (nearLeft && isTopCorner)) {
      return DeskSnap.topLeft;
    }
    if ((nearTop && isRightCorner) || (nearRight && isTopCorner)) {
      return DeskSnap.topRight;
    }
    if ((nearBottom && isLeftCorner) || (nearLeft && isBottomCorner)) {
      return DeskSnap.bottomLeft;
    }
    if ((nearBottom && isRightCorner) || (nearRight && isBottomCorner)) {
      return DeskSnap.bottomRight;
    }

    // 2. Top edge (between corners) -> Maximize
    if (nearTop) {
      return DeskSnap.maximize;
    }

    // 3. Bottom edge (between corners) -> 1:1:1 Thirds
    if (nearBottom) {
      if (p.dx < area.width / 3) return DeskSnap.thirdLeft;
      if (p.dx > area.width * 2 / 3) return DeskSnap.thirdRight;
      return DeskSnap.thirdCenter;
    }

    // 4. Left and Right edges (between corners) -> Halves
    if (nearLeft) return DeskSnap.left;
    if (nearRight) return DeskSnap.right;

    return DeskSnap.none;
  }

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
  ///
  /// [rightInset] keeps the windows clear of the health widget.
  void ensureDefaults({double rightInset = 0}) {
    if (_seeded) return;
    _seeded = true;
    if (_windows.isNotEmpty) return;
    final a = Size(math.max(kDeskMinWindow.width * 2 + 64, area.width - rightInset), area.height);
    final homeW = math.min(380.0, a.width * 0.32);
    _add(AxSection.home, Rect.fromLTWH(20, 12, homeW, math.max(kDeskMinWindow.height, a.height - 24)));
    final right = 20 + homeW + 16;
    final termW = math.max(kDeskMinWindow.width, math.min(600.0, a.width - right - 20));
    _add(AxSection.terminal, Rect.fromLTWH(right, 12, termW, math.max(kDeskMinWindow.height, a.height * 0.50)));
    final filesW = math.max(kDeskMinWindow.width, math.min(620.0, a.width - right - 40));
    final filesTop = math.min(a.height * 0.38, a.height - kDeskMinWindow.height - 8);
    _add(
      AxSection.files,
      Rect.fromLTWH(
        math.min(right + 40, math.max(20, a.width - filesW - 20)),
        math.max(12, filesTop),
        filesW,
        math.max(kDeskMinWindow.height, a.height - filesTop - 12),
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
      w.snapped = DeskSnap.none;
    } else {
      w.restoreRect = w.rect;
      w.snapped = DeskSnap.maximize;
      w.rect = snapRect(DeskSnap.maximize)!;
    }
    w.z = ++_z;
    notifyListeners();
  }

  /// Moves [s] by [delta]. [pointer] (window-area coordinates) drives
  /// edge snapping: near screen edges and corners, a preview shows
  /// where the window will land on [endMove].
  void move(AxSection s, Offset delta, {Offset? pointer, bool? altPressed}) {
    final w = windowFor(s);
    if (w == null) return;
    if (w.maximized) {
      // Dragging a maximized or snapped window restores its size under the pointer.
      final restore = w.restoreRect!;
      w.restoreRect = null;
      w.snapped = DeskSnap.none;
      final x = pointer == null ? w.rect.left : pointer.dx - restore.width / 2;
      w.rect = _clamp(Rect.fromLTWH(x, w.rect.top, restore.width, restore.height));
    }
    w.rect = _clamp(w.rect.shift(delta));
    _snap = pointer == null ? DeskSnap.none : snapAt(pointer, altPressed: altPressed);
    notifyListeners();
  }

  /// Ends a title-bar drag, snapping [s] if it was let go at an edge.
  void endMove(AxSection s) {
    final w = windowFor(s);
    final target = snapRect(_snap);
    if (w != null && target != null) {
      w.restoreRect = w.rect;
      w.snapped = _snap;
      w.rect = target;
    }
    _snap = DeskSnap.none;
    notifyListeners();
  }

  /// "Tidy up windows": lays the windows on screen out in a neat grid.
  void tidy() {
    final shown = stacked.where((w) => !w.minimized).toList()..sort((a, b) => a.section.index.compareTo(b.section.index));
    if (shown.isEmpty) return;
    const g = 12.0;
    final cols = shown.length <= 3 ? shown.length : (shown.length / 2).ceil();
    final rows = (shown.length / cols).ceil();
    final cw = (area.width - g * (cols + 1)) / cols;
    final rh = (area.height - g * (rows + 1)) / rows;
    for (var i = 0; i < shown.length; i++) {
      final c = i % cols;
      final r = i ~/ cols;
      shown[i]
        ..restoreRect = null
        ..rect = _clamp(Rect.fromLTWH(g + c * (cw + g), g + r * (rh + g), cw, rh));
    }
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
        w.rect = snapRect(w.snapped) ?? _clamp(w.rect);
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
/// the destinations, a dock and a launcher, all arranged the way the person
/// likes ([DesktopPrefs]). The main experience on tablets and computers.
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

  void _open(AxSection s) {
    windows.open(s);
    onFocus(s);
  }

  Future<void> _desktopMenu(BuildContext context, Offset at) async {
    final prefs = context.read<DesktopPrefs>();
    final choice = await showDeskMenu(context, at, [
      const DeskMenuItem('wallpaper', 'Change wallpaper…', Icons.wallpaper_outlined),
      const DeskMenuItem('dock', 'Customize dock…', Icons.dock_outlined),
      DeskMenuItem(
        'widget',
        prefs.showWidget ? 'Hide health widget' : 'Show health widget',
        prefs.showWidget ? Icons.visibility_off_outlined : Icons.monitor_heart_outlined,
      ),
      const DeskMenuItem('tidy', 'Tidy up windows', Icons.grid_view_outlined),
      const DeskMenuItem('apps', 'All apps', Icons.apps_rounded),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'wallpaper' || 'dock':
        await showDesktopCustomize(context);
      case 'widget':
        prefs.showWidget = !prefs.showWidget;
      case 'tidy':
        windows.tidy();
      case 'apps':
        windows.toggleLauncher(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DesktopPrefs>();
    final reserve = prefs.reserve;
    final ax = context.ax;
    return Column(
      children: [
        _TopBar(onSimpleLayout: onSimpleLayout, onCustomize: () => showDesktopCustomize(context)),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: DeskWallpaperView(wallpaper: prefs.wallpaper)),
              // The bare desktop: right-click (or long-press) for its menu.
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('desk-surface'),
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapUp: (d) => _desktopMenu(context, d.globalPosition),
                  onLongPressStart: (d) => _desktopMenu(context, d.globalPosition),
                ),
              ),
              if (prefs.showWidget)
                Positioned(
                  top: ax.space.md,
                  right: reserve.right + ax.space.md,
                  width: kDeskWidgetWidth,
                  child: _HealthWidget(onOpen: () => _open(AxSection.activity), onHide: () => prefs.showWidget = false),
                ),
              Positioned.fill(
                left: reserve.left,
                right: reserve.right,
                bottom: reserve.bottom,
                child: LayoutBuilder(
                  builder: (context, box) {
                    windows.fitTo(box.biggest);
                    final front = windows.front;
                    final ghost = windows.snapPreview;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (windows.visible.isEmpty) const IgnorePointer(child: _EmptyDesk()),
                        if (ghost != null)
                          Positioned.fromRect(
                            key: const ValueKey('snap-preview'),
                            rect: ghost,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: ax.colors.accent.withValues(alpha: 0.12),
                                  border: Border.all(color: ax.colors.accent.withValues(alpha: 0.6), width: 1.5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
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
              Positioned.fill(child: _DockHost(prefs: prefs, windows: windows, onOpen: _open)),
              if (windows.launcherOpen) Positioned.fill(child: _Launcher(onClose: () => windows.toggleLauncher(false), onOpen: _open)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Paints a [DeskWallpaper]. [DeskWallpaper.halo] is transparent: the
/// theme's own backdrop shows through.
class DeskWallpaperView extends StatelessWidget {
  const DeskWallpaperView({super.key, required this.wallpaper});
  final DeskWallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    final base = wallpaper.base;
    if (base == null) return const SizedBox.expand();
    final second = wallpaper.secondGlow;
    return IgnorePointer(
      child: DecoratedBox(
        key: ValueKey('wallpaper-${wallpaper.name}'),
        decoration: BoxDecoration(color: base),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (second != null) DecoratedBox(decoration: BoxDecoration(gradient: second)),
            DecoratedBox(decoration: BoxDecoration(gradient: wallpaper.gradient)),
          ],
        ),
      ),
    );
  }
}

/// A small glass card on the desktop: how the server is doing at a glance.
class _HealthWidget extends StatelessWidget {
  const _HealthWidget({required this.onOpen, required this.onHide});
  final VoidCallback onOpen;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final mon = context.watch<MonitoringService>();
    final m = mon.metrics;
    final health = evaluateHealth(connected: mon.isConnected, metrics: m);
    final (IconData icon, Color tone) = switch (health.level) {
      HealthLevel.healthy => (Icons.verified_user_outlined, c.success),
      HealthLevel.warning => (Icons.warning_amber_rounded, c.warning),
      HealthLevel.checking => (Icons.hourglass_empty_rounded, c.info),
      HealthLevel.unreachable => (Icons.cloud_off_outlined, c.danger),
    };
    Future<void> menu(Offset at) async {
      final choice = await showDeskMenu(context, at, const [
        DeskMenuItem('open', 'Open Activity', Icons.show_chart),
        DeskMenuItem('hide', 'Hide widget', Icons.visibility_off_outlined),
      ]);
      if (choice == 'open') onOpen();
      if (choice == 'hide') onHide();
    }

    return Semantics(
      container: true,
      label: 'Server health: ${health.pill}',
      child: GestureDetector(
        key: const ValueKey('health-widget'),
        onTap: onOpen,
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        onLongPressStart: (d) => menu(d.globalPosition),
        child: AxGlass(
          blur: true,
          shadow: true,
          radius: ax.radii.lg,
          padding: EdgeInsets.all(ax.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: tone),
                  SizedBox(width: ax.space.sm),
                  Expanded(child: Text(health.pill, style: ax.typo.label.copyWith(color: c.text))),
                  Text('Server', style: ax.typo.caption.copyWith(color: c.textSubtle)),
                ],
              ),
              SizedBox(height: ax.space.sm),
              if (m == null)
                Text(health.detail, style: ax.typo.caption.copyWith(color: c.textMuted))
              else ...[
                _WidgetMeter(label: 'CPU', percent: m.cpu.usagePercent),
                _WidgetMeter(label: 'Memory', percent: m.memory.usagePercent),
                _WidgetMeter(label: 'Disk', percent: worstDiskPercent(m.disk)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetMeter extends StatelessWidget {
  const _WidgetMeter({required this.label, required this.percent});
  final String label;
  final double percent;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final tone = switch (usageStatus(percent)) {
      AxStatus.error => c.danger,
      AxStatus.warning => c.warning,
      _ => c.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 58, child: Text(label, style: ax.typo.caption.copyWith(color: c.textMuted))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0, 1).toDouble(),
                minHeight: 5,
                color: tone,
                backgroundColor: c.text.withValues(alpha: 0.08),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${percent.round()}%',
              textAlign: TextAlign.right,
              style: ax.typo.mono.copyWith(color: c.text, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of a desktop context menu.
class DeskMenuItem {
  const DeskMenuItem(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

/// A small right-click / long-press menu at [at] (global position).
Future<String?> showDeskMenu(BuildContext context, Offset at, List<DeskMenuItem> items) {
  final ax = context.ax;
  final c = ax.colors;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(at);
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    color: c.glassStrong,
    elevation: 8,
    constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ax.radii.md), side: BorderSide(color: c.glassBorder)),
    items: [
      for (final i in items)
        PopupMenuItem<String>(
          value: i.id,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 40,
          child: Row(
            children: [
              Icon(i.icon, size: 18, color: c.textMuted),
              SizedBox(width: ax.space.sm + 2),
              Flexible(
                child: Text(
                  i.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ax.typo.body.copyWith(color: c.text, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
    ],
  );
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
  const _TopBar({required this.onSimpleLayout, required this.onCustomize});
  final VoidCallback onSimpleLayout;
  final VoidCallback onCustomize;

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
                SizedBox(width: ax.space.sm),
                _MiniButton(label: 'Customize', icon: Icons.tune_rounded, tooltip: 'Customize the desktop', onTap: onCustomize),
                SizedBox(width: ax.space.md),
                const Expanded(child: StatusStrip(showServerName: false, compact: true)),
                SizedBox(width: ax.space.sm),
                const _Clock(),
                SizedBox(width: ax.space.sm),
                _MiniButton(
                  label: 'Full screen',
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'Toggle full screen (F11)',
                  onTap: WindowService.toggleFullScreen,
                ),
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
                      onPanUpdate:
                          (d) => windows.move(
                            s,
                            d.delta,
                            pointer: window.rect.topLeft + d.localPosition,
                            altPressed: HardwareKeyboard.instance.isAltPressed,
                          ),
                      onPanEnd: (_) => windows.endMove(s),
                      onPanCancel: () => windows.endMove(s),
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

/// Places the dock on its edge and, when it hides itself, slides it away
/// until the pointer reaches that edge (or the edge is tapped).
class _DockHost extends StatefulWidget {
  const _DockHost({required this.prefs, required this.windows, required this.onOpen});
  final DesktopPrefs prefs;
  final DesktopWindows windows;
  final void Function(AxSection) onOpen;

  @override
  State<_DockHost> createState() => _DockHostState();
}

class _DockHostState extends State<_DockHost> {
  bool _shown = false;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    if (!_shown) setState(() => _shown = true);
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    final pos = prefs.dockPosition;
    final hidden = prefs.autoHide && !_shown && !widget.windows.launcherOpen;
    final align = switch (pos) {
      DockPosition.bottom => Alignment.bottomCenter,
      DockPosition.left => Alignment.centerLeft,
      DockPosition.right => Alignment.centerRight,
    };
    final away = switch (pos) {
      DockPosition.bottom => const Offset(0, 1.4),
      DockPosition.left => const Offset(-1.4, 0),
      DockPosition.right => const Offset(1.4, 0),
    };
    final dock = MouseRegion(
      onEnter: (_) => prefs.autoHide ? _show() : null,
      onExit: (_) => prefs.autoHide ? _scheduleHide() : null,
      child: Padding(padding: const EdgeInsets.all(14), child: _Dock(prefs: prefs, windows: widget.windows, onOpen: widget.onOpen)),
    );
    return Stack(
      children: [
        if (prefs.autoHide)
          Positioned(
            left: pos == DockPosition.right ? null : 0,
            right: pos == DockPosition.left ? null : 0,
            top: pos == DockPosition.bottom ? null : 0,
            bottom: 0,
            width: pos == DockPosition.bottom ? null : kDockHotZone,
            height: pos == DockPosition.bottom ? kDockHotZone : null,
            child: MouseRegion(
              key: const ValueKey('dock-hot-zone'),
              opaque: false,
              onEnter: (_) => _show(),
              child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _show),
            ),
          ),
        Align(
          alignment: align,
          child: AnimatedSlide(
            offset: hidden ? away : Offset.zero,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: hidden ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(ignoring: hidden, child: dock),
            ),
          ),
        ),
      ],
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.prefs, required this.windows, required this.onOpen});
  final DesktopPrefs prefs;
  final DesktopWindows windows;
  final void Function(AxSection) onOpen;

  Future<void> _iconMenu(BuildContext context, AxSection s, Offset at) async {
    final label = axSectionLabels[s]!;
    final open = windows.isOpen(s);
    final pinned = prefs.isPinned(s);
    final choice = await showDeskMenu(context, at, [
      DeskMenuItem('open', open ? 'Show $label' : 'Open $label', axSectionIcons[s]!),
      if (open) const DeskMenuItem('close', 'Close window', Icons.close),
      DeskMenuItem('pin', pinned ? 'Remove from dock' : 'Keep in dock', pinned ? Icons.push_pin_outlined : Icons.push_pin),
      const DeskMenuItem('customize', 'Customize dock…', Icons.dock_outlined),
    ]);
    if (!context.mounted) return;
    switch (choice) {
      case 'open':
        onOpen(s);
      case 'close':
        windows.close(s);
      case 'pin':
        prefs.togglePin(s);
      case 'customize':
        await showDesktopCustomize(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ax.colors;
    final vertical = prefs.dockPosition != DockPosition.bottom;
    final size = prefs.dockSize;
    final pinned = prefs.pinned;
    // Open windows that aren't kept in the dock appear after a divider.
    final running = [
      for (final s in AxSection.values)
        if (windows.isOpen(s) && !pinned.contains(s)) s,
    ];
    Widget divider() => Container(
      width: vertical ? 28 : 1,
      height: vertical ? 1 : 28,
      margin: EdgeInsets.symmetric(horizontal: vertical ? 0 : 6, vertical: vertical ? 6 : 0),
      color: c.border,
    );
    Widget button(AxSection s) => _DockButton(
      key: ValueKey('dock-${s.name}'),
      icon: axSectionIcons[s]!,
      label: axSectionLabels[s]!,
      size: size,
      vertical: vertical,
      tooltipBelow: false,
      open: windows.isOpen(s),
      onTap: () => onOpen(s),
      onMenu: (at) => _iconMenu(context, s, at),
    );
    return Semantics(
      container: true,
      label: 'Dock',
      child: AxGlass(
        strong: true,
        blur: true,
        shadow: true,
        radius: size.button / 2 + 4,
        padding: EdgeInsets.symmetric(horizontal: vertical ? 8 : 10, vertical: vertical ? 10 : 8),
        child: Flex(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DockButton(
              icon: Icons.apps_rounded,
              label: 'All apps',
              size: size,
              vertical: vertical,
              highlighted: true,
              onTap: () => windows.toggleLauncher(),
            ),
            divider(),
            for (final s in pinned) button(s),
            if (running.isNotEmpty) ...[divider(), for (final s in running) button(s)],
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.size,
    this.vertical = false,
    this.tooltipBelow = false,
    this.onMenu,
    this.open = false,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final DockSize size;
  final bool vertical;
  final bool tooltipBelow;
  final void Function(Offset globalPosition)? onMenu;
  final bool open;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final radius = BorderRadius.circular(size.button * 0.3);
    final dot = Container(width: 4, height: 4, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle));
    return Semantics(
      button: true,
      label: open ? '$label, open' : label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        preferBelow: tooltipBelow,
        child: GestureDetector(
          onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
          onLongPressStart: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
          child: Padding(
            padding: vertical ? const EdgeInsets.symmetric(vertical: 2) : const EdgeInsets.symmetric(horizontal: 2),
            child: Material(
              color: highlighted ? c.accent : Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: SizedBox(
                  width: size.button,
                  height: size.button,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(icon, size: size.icon, color: highlighted ? c.onAccent : c.text),
                      if (open) vertical ? Positioned(left: 3, child: dot) : Positioned(bottom: 3, child: dot),
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
