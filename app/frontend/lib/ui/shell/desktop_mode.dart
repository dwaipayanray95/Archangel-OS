import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../main.dart' show ArchangelApp;
import '../../services/archangeld_connection.dart';
import '../../services/monitoring_service.dart';
import '../../services/server_registry.dart';
import '../screens/home/home_logic.dart';
import '../components/ax_glass.dart';
import '../components/status_badge.dart';
import '../components/ax_wordmark.dart';
import '../components/confirm_dialog.dart';
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

/// Margin and spacing gap between arranged windows and the desktop edges.
const double kDeskWindowGap = 4.0;

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

  /// Whether the window is currently being actively dragged or resized by pointer.
  bool isDragging = false;

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
    const g = kDeskWindowGap;
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
    w.isDragging = false;
    if (w.maximized) {
      w.rect = _clamp(w.restoreRect ?? Rect.fromLTWH(60, 20, math.min(820, area.width - 120), math.min(580, area.height - 40)));
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

  /// Snaps [s] to the requested [snap] zone (e.g. left half, right half, maximize).
  void snapWindow(AxSection s, DeskSnap snap) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = false;
    if (snap == DeskSnap.none) {
      if (w.restoreRect != null) {
        w.rect = _clamp(w.restoreRect!);
        w.restoreRect = null;
        w.snapped = DeskSnap.none;
        notifyListeners();
      }
      return;
    }
    final target = snapRect(snap);
    if (target != null) {
      w.restoreRect ??= w.rect;
      w.snapped = snap;
      w.rect = target;
      w.minimized = false;
      w.z = ++_z;
      notifyListeners();
    }
  }

  /// Restores a snapped or maximized window, or minimizes it if already normal.
  void restoreOrMinimize(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = false;
    if (w.snapped != DeskSnap.none || w.restoreRect != null) {
      w.rect = _clamp(w.restoreRect ?? Rect.fromLTWH(60, 20, math.min(820, area.width - 120), math.min(580, area.height - 40)));
      w.restoreRect = null;
      w.snapped = DeskSnap.none;
      w.z = ++_z;
      notifyListeners();
    } else {
      minimize(s);
    }
  }

  void startMove(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = true;
    notifyListeners();
  }

  /// Moves [s] by [delta]. [pointer] (window-area coordinates) drives
  /// edge snapping: near screen edges and corners, a preview shows
  /// where the window will land on [endMove].
  void move(AxSection s, Offset delta, {Offset? pointer, bool? altPressed}) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = true;
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
    if (w != null) {
      w.isDragging = false;
      final target = snapRect(_snap);
      if (target != null) {
        w.restoreRect = w.rect;
        w.snapped = _snap;
        w.rect = target;
      }
    }
    _snap = DeskSnap.none;
    notifyListeners();
  }

  /// "Tidy up windows": lays the windows on screen out in a neat grid.
  void tidy() {
    final shown = stacked.where((w) => !w.minimized).toList()..sort((a, b) => a.section.index.compareTo(b.section.index));
    if (shown.isEmpty) return;
    const g = kDeskWindowGap;
    final cols = shown.length <= 3 ? shown.length : (shown.length / 2).ceil();
    final rows = (shown.length / cols).ceil();
    final cw = (area.width - g * (cols + 1)) / cols;
    final rh = (area.height - g * (rows + 1)) / rows;
    for (var i = 0; i < shown.length; i++) {
      final c = i % cols;
      final r = i ~/ cols;
      shown[i]
        ..isDragging = false
        ..restoreRect = null
        ..rect = _clamp(Rect.fromLTWH(g + c * (cw + g), g + r * (rh + g), cw, rh));
    }
    notifyListeners();
  }

  void startResize(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = true;
    notifyListeners();
  }

  void endResize(AxSection s) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = false;
    notifyListeners();
  }

  void resize(AxSection s, Offset delta) {
    final w = windowFor(s);
    if (w == null) return;
    w.isDragging = true;
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
class DesktopModeView extends StatefulWidget {
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
  State<DesktopModeView> createState() => _DesktopModeViewState();
}

class _DesktopModeViewState extends State<DesktopModeView> {
  bool _switcherOpen = false;
  List<AxSection> _switcherApps = [];
  int _switcherIndex = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (!mounted) return false;

    // Handle Switcher KeyUp (release modifier to commit switch)
    if (_switcherOpen && event is KeyUpEvent) {
      final key = event.logicalKey;
      final isModifierKey =
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight ||
          key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight ||
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight;
      if (isModifierKey) {
        final anyModifierHeld =
            HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isAltPressed || HardwareKeyboard.instance.isControlPressed;
        if (!anyModifierHeld) {
          _commitSwitcher();
          return true;
        }
      }
    }

    if (event is! KeyDownEvent) return false;

    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    // 1. App Switcher Navigation while open
    if (_switcherOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        setState(() => _switcherOpen = false);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab || event.logicalKey == LogicalKeyboardKey.arrowRight) {
        setState(() {
          if (isShift && event.logicalKey == LogicalKeyboardKey.tab) {
            _switcherIndex = (_switcherIndex - 1 + _switcherApps.length) % _switcherApps.length;
          } else {
            _switcherIndex = (_switcherIndex + 1) % _switcherApps.length;
          }
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        setState(() {
          _switcherIndex = (_switcherIndex - 1 + _switcherApps.length) % _switcherApps.length;
        });
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.space) {
        _commitSwitcher();
        return true;
      }
    }

    // 2. Trigger App Switcher HUD (Cmd+Tab, Alt+Tab, Ctrl+Tab)
    if (event.logicalKey == LogicalKeyboardKey.tab && (isMeta || isAlt || isCtrl)) {
      final openWindows = widget.windows.stacked.reversed.toList();
      if (openWindows.isEmpty) return false;

      setState(() {
        _switcherOpen = true;
        _switcherApps = openWindows.map((w) => w.section).toList();
        if (isShift) {
          _switcherIndex = (_switcherApps.length - 1) % _switcherApps.length;
        } else {
          _switcherIndex = _switcherApps.length > 1 ? 1 : 0;
        }
      });
      return true;
    }

    // 3. Window Snapping via Keyboard
    final isSnapModifier = (isAlt && (isMeta || isCtrl));
    final isPlainAltSnap = isAlt && !isMeta && !isCtrl;
    final front = widget.windows.front;

    if (front != null && (isSnapModifier || isPlainAltSnap)) {
      if (isPlainAltSnap) {
        final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
        if (focusedWidget is EditableText) return false;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        widget.windows.snapWindow(front, isShift ? DeskSnap.thirdLeft : DeskSnap.left);
        widget.onFocus(front);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        widget.windows.snapWindow(front, isShift ? DeskSnap.thirdRight : DeskSnap.right);
        widget.onFocus(front);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.windows.snapWindow(front, DeskSnap.maximize);
        widget.onFocus(front);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.windows.restoreOrMinimize(front);
        final nextFront = widget.windows.front;
        if (nextFront != null) widget.onFocus(nextFront);
        return true;
      }
    }

    return false;
  }

  void _commitSwitcher() {
    if (!_switcherOpen) return;
    setState(() => _switcherOpen = false);
    if (_switcherApps.isNotEmpty && _switcherIndex < _switcherApps.length) {
      final target = _switcherApps[_switcherIndex];
      _open(target);
    }
  }

  void _open(AxSection s) {
    widget.windows.open(s);
    widget.onFocus(s);
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
        widget.windows.tidy();
      case 'apps':
        widget.windows.toggleLauncher(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DesktopPrefs>();
    final reserve = prefs.reserve;
    final ax = context.ax;
    return Column(
      children: [
        _TopBar(
          windows: widget.windows,
          onOpen: _open,
          onSimpleLayout: widget.onSimpleLayout,
          onCustomize: () => showDesktopCustomize(context),
        ),
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
                    widget.windows.fitTo(box.biggest);
                    final front = widget.windows.front;
                    final ghost = widget.windows.snapPreview;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(child: IgnorePointer(child: _EmptyDesk(hasWindows: widget.windows.visible.isNotEmpty))),
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
                        for (final w in widget.windows.stacked)
                          w.minimized
                              // Minimized windows stay mounted (offstage) so a
                              // terminal session or half-typed form survives.
                              ? Offstage(
                                key: ValueKey('win-${w.section.name}'),
                                child: TickerMode(
                                  enabled: false,
                                  child: SizedBox(width: w.rect.width, height: w.rect.height, child: widget.buildContent(w.section)),
                                ),
                              )
                              : AnimatedPositioned(
                                key: ValueKey('win-${w.section.name}'),
                                duration: w.isDragging ? Duration.zero : const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                left: w.rect.left,
                                top: w.rect.top,
                                width: w.rect.width,
                                height: w.rect.height,
                                child: _Window(
                                  window: w,
                                  focused: w.section == front,
                                  windows: widget.windows,
                                  onFocus: widget.onFocus,
                                  child: widget.buildContent(w.section),
                                ),
                              ),
                      ],
                    );
                  },
                ),
              ),
              Positioned.fill(child: _DockHost(prefs: prefs, windows: widget.windows, onOpen: _open)),
              if (widget.windows.launcherOpen)
                Positioned.fill(child: _Launcher(onClose: () => widget.windows.toggleLauncher(false), onOpen: _open)),
              if (_switcherOpen && _switcherApps.isNotEmpty)
                Positioned.fill(
                  child: _AppSwitcherHud(
                    apps: _switcherApps,
                    selectedIndex: _switcherIndex,
                    onSelect: (s) => _commitSwitcherTarget(s),
                    onDismiss: () => setState(() => _switcherOpen = false),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _commitSwitcherTarget(AxSection s) {
    setState(() => _switcherOpen = false);
    _open(s);
  }
}

/// Floating keyboard application switcher (Cmd+Tab / Alt+Tab / Ctrl+Tab HUD).
class _AppSwitcherHud extends StatelessWidget {
  const _AppSwitcherHud({required this.apps, required this.selectedIndex, required this.onSelect, required this.onDismiss});

  final List<AxSection> apps;
  final int selectedIndex;
  final ValueChanged<AxSection> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final selectedApp = (selectedIndex >= 0 && selectedIndex < apps.length) ? apps[selectedIndex] : null;

    return Semantics(
      container: true,
      label: 'Application Switcher',
      child: GestureDetector(
        key: const ValueKey('app-switcher-scrim'),
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.32),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                constraints: const BoxConstraints(maxWidth: 680),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 40, offset: const Offset(0, 16)),
                    BoxShadow(color: c.accent.withValues(alpha: 0.22), blurRadius: 22, spreadRadius: 1),
                  ],
                ),
                child: AxGlass(
                  strong: true,
                  blur: true,
                  shadow: false,
                  radius: 22,
                  borderColor: c.accent.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < apps.length; i++) ...[
                                if (i > 0) const SizedBox(width: 12),
                                _AppSwitcherTile(section: apps[i], isSelected: i == selectedIndex, onTap: () => onSelect(apps[i])),
                              ],
                            ],
                          ),
                        ),
                        if (selectedApp != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            axSectionLabels[selectedApp] ?? '',
                            style: ax.typo.title.copyWith(color: c.text, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tab to cycle · Shift+Tab to reverse · Release to switch · Esc to cancel',
                            style: ax.typo.caption.copyWith(color: c.textMuted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
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

class _AppSwitcherTile extends StatelessWidget {
  const _AppSwitcherTile({required this.section, required this.isSelected, required this.onTap});

  final AxSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final label = axSectionLabels[section] ?? '';
    final icon = axSectionIcons[section] ?? Icons.apps;

    return Semantics(
      button: true,
      label: label,
      selected: isSelected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: 80,
            height: 84,
            decoration: BoxDecoration(
              color: isSelected ? c.accent.withValues(alpha: 0.18) : c.text.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? c.accent.withValues(alpha: 0.75) : c.glassBorder.withValues(alpha: 0.6),
                width: isSelected ? 2 : 1,
              ),
              boxShadow:
                  isSelected ? [BoxShadow(color: c.accent.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 4))] : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: isSelected ? c.accent : c.text),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ax.typo.caption.copyWith(
                    color: isSelected ? c.text : c.textMuted,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
  const DeskMenuItem(this.id, this.label, this.icon, {this.isDivider = false, this.trailing, this.danger = false});

  const DeskMenuItem.divider() : id = '', label = '', icon = Icons.circle, isDivider = true, trailing = null, danger = false;

  final String id;
  final String label;
  final IconData icon;
  final bool isDivider;
  final String? trailing;
  final bool danger;
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
        if (i.isDivider)
          const PopupMenuDivider(height: 10)
        else
          PopupMenuItem<String>(
            value: i.id,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            height: 38,
            child: Row(
              children: [
                Icon(i.icon, size: 18, color: i.danger ? c.danger : c.textMuted),
                SizedBox(width: ax.space.sm + 2),
                Expanded(
                  child: Text(
                    i.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ax.typo.body.copyWith(color: i.danger ? c.danger : c.text, fontSize: 13.5),
                  ),
                ),
                if (i.trailing != null) ...[
                  SizedBox(width: ax.space.sm),
                  Text(i.trailing!, style: ax.typo.mono.copyWith(color: c.textSubtle, fontSize: 11)),
                ],
              ],
            ),
          ),
    ],
  );
}

class _EmptyDesk extends StatelessWidget {
  const _EmptyDesk({required this.hasWindows});

  final bool hasWindows;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    final prefs = context.watch<DesktopPrefs>();
    final showWordmark = prefs.showWallpaperWordmark;
    final showSubtitle = prefs.showWallpaperSubtitle && !hasWindows;

    if (!showWordmark && !showSubtitle) {
      return const SizedBox.shrink();
    }

    final isDarkWallpaper =
        prefs.wallpaper == DeskWallpaper.halo ? Theme.of(context).brightness == Brightness.dark : prefs.wallpaper != DeskWallpaper.mist;

    final textColor = isDarkWallpaper ? const Color(0xFFF4F5FB) : const Color(0xFF121420);
    final subtitleColor = isDarkWallpaper ? const Color(0x99F4F5FB) : const Color(0x99121420);

    final dockPos = prefs.dockPosition;
    final subtitleText = switch (dockPos) {
      DockPosition.bottom => 'Open something from the dock below.',
      DockPosition.left => 'Open something from the dock on the left.',
      DockPosition.right => 'Open something from the dock on the right.',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showWordmark) AxWordmark(size: 32, color: textColor, osColor: c.accent),
          if (showWordmark && showSubtitle) SizedBox(height: ax.space.sm),
          if (showSubtitle) Text(subtitleText, style: ax.typo.body.copyWith(color: subtitleColor)),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.windows, required this.onOpen, required this.onSimpleLayout, required this.onCustomize});

  final DesktopWindows windows;
  final void Function(AxSection) onOpen;
  final VoidCallback onSimpleLayout;
  final VoidCallback onCustomize;

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
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
                _ArchangelSystemMenu(windows: windows, onOpen: onOpen, onSimpleLayout: onSimpleLayout, onCustomize: onCustomize),
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

class _ArchangelSystemMenu extends StatefulWidget {
  const _ArchangelSystemMenu({required this.windows, required this.onOpen, required this.onSimpleLayout, required this.onCustomize});

  final DesktopWindows windows;
  final void Function(AxSection) onOpen;
  final VoidCallback onSimpleLayout;
  final VoidCallback onCustomize;

  @override
  State<_ArchangelSystemMenu> createState() => _ArchangelSystemMenuState();
}

class _ArchangelSystemMenuState extends State<_ArchangelSystemMenu> {
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    if (_menuOpen) return;
    setState(() => _menuOpen = true);

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      if (mounted) setState(() => _menuOpen = false);
      return;
    }

    final pos = box.localToGlobal(Offset(0, box.size.height + 4));
    final registry = context.read<ServerRegistry>();
    final activeServer = registry.active?.name;
    final isPaired = context.read<ArchangeldConnection>().isPaired;

    final isMac = Platform.isMacOS;
    final choice = await showDeskMenu(context, pos, [
      const DeskMenuItem('about', 'About Archangel OS', Icons.auto_awesome_rounded),
      const DeskMenuItem('settings', 'System Settings…', Icons.settings_outlined),
      const DeskMenuItem.divider(),
      const DeskMenuItem('launcher', 'App Launcher', Icons.apps_rounded),
      const DeskMenuItem('customize', 'Customize Desktop…', Icons.tune_rounded),
      const DeskMenuItem('tidy', 'Tidy Windows', Icons.grid_view_outlined),
      const DeskMenuItem.divider(),
      const DeskMenuItem('simple', 'Switch to Simple Layout', Icons.view_sidebar_outlined),
      const DeskMenuItem.divider(),
      DeskMenuItem('switch_server', 'Switch Server…', Icons.dns_outlined, trailing: activeServer),
      if (isPaired) const DeskMenuItem('restart_server', 'Restart Server…', Icons.restart_alt_rounded),
      const DeskMenuItem.divider(),
      const DeskMenuItem('restart_app', 'Restart App…', Icons.refresh_rounded),
      DeskMenuItem('quit_app', 'Quit Archangel OS', Icons.power_settings_new_rounded, danger: true, trailing: isMac ? '⌘Q' : null),
    ]);

    if (mounted) {
      setState(() => _menuOpen = false);
    }
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'about':
      case 'settings':
        widget.onOpen(AxSection.settings);
      case 'launcher':
        widget.windows.toggleLauncher(true);
      case 'customize':
        widget.onCustomize();
      case 'tidy':
        widget.windows.tidy();
      case 'simple':
        widget.onSimpleLayout();
      case 'switch_server':
        showServerSheet(context);
      case 'restart_server':
        _confirmRestart(context);
      case 'restart_app':
        _confirmRestartApp(context);
      case 'quit_app':
        _confirmQuitApp(context);
    }
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final monitoring = context.read<MonitoringService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showConfirmDialog(
      context,
      title: 'Restart your server?',
      message: 'Your apps stop for about a minute, then start again. Archangel reconnects automatically.',
      confirmLabel: 'Restart',
    );
    if (!ok) return;
    final result = await monitoring.rebootHost();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(result.success ? 'Restarting. Your server will be back in about a minute.' : "Couldn't restart: ${result.message}"),
      ),
    );
  }

  Future<void> _confirmRestartApp(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Restart Archangel OS?',
      message: 'This reloads the app and resets running desktop windows.',
      confirmLabel: 'Restart',
    );
    if (!ok) return;
    _restartApp();
  }

  void _restartApp() {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      runApp(const ArchangelApp());
    }
  }

  Future<void> _confirmQuitApp(BuildContext context) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Quit Archangel OS?',
      message: 'Are you sure you want to exit the application?',
      confirmLabel: 'Quit',
      danger: true,
    );
    if (!ok) return;
    await _quitApp();
  }

  Future<void> _quitApp() async {
    try {
      await SystemNavigator.pop();
    } catch (_) {}
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        exit(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ax = context.ax;
    final c = ax.colors;
    return Semantics(
      button: true,
      label: 'Archangel OS menu',
      child: Tooltip(
        message: 'Archangel OS menu',
        child: Material(
          color: _menuOpen ? c.surfaceHigh : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ax.radii.sm),
            side: BorderSide(color: _menuOpen ? c.border : Colors.transparent),
          ),
          child: InkWell(
            key: const ValueKey('archangel-os-menu'),
            onTap: _openMenu,
            borderRadius: BorderRadius.circular(ax.radii.sm),
            hoverColor: c.surfaceHigh.withValues(alpha: 0.5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: ax.space.xs + 2, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AxWordmark(size: 14.5),
                    SizedBox(width: 2),
                    Icon(
                      _menuOpen ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                      size: 16,
                      color: _menuOpen ? c.accent : c.textMuted,
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

extension on Widget {
  Widget withBottomLine(Color color) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: color))),
    child: this,
  );
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: focused ? 0.38 : 0.16),
                blurRadius: focused ? 32 : 14,
                offset: Offset(0, focused ? 12 : 5),
              ),
              if (focused) BoxShadow(color: c.accent.withValues(alpha: 0.18), blurRadius: 16, spreadRadius: 1),
            ],
          ),
          child: AxGlass(
            strong: true,
            blur: true,
            shadow: false,
            radius: 16,
            borderColor: focused ? c.accent.withValues(alpha: 0.50) : c.glassBorder.withValues(alpha: 0.60),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                        onPanStart: (_) {
                          focus();
                          windows.startMove(s);
                        },
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            height: 44,
                            padding: EdgeInsets.only(left: ax.space.md + 2, right: ax.space.xs),
                            decoration: BoxDecoration(
                              color: focused ? c.accent.withValues(alpha: 0.06) : Colors.transparent,
                              border: Border(bottom: BorderSide(color: focused ? c.accent.withValues(alpha: 0.20) : c.border)),
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
                                    style: ax.typo.label.copyWith(
                                      color: focused ? c.text : c.textMuted,
                                      fontSize: 13,
                                      fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                                    ),
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
                      Expanded(
                        child: AnimatedOpacity(duration: const Duration(milliseconds: 140), opacity: focused ? 1.0 : 0.90, child: child),
                      ),
                    ],
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanStart: (_) => windows.startResize(s),
                      onPanUpdate: (d) => windows.resize(s, d.delta),
                      onPanEnd: (_) => windows.endResize(s),
                      onPanCancel: () => windows.endResize(s),
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
