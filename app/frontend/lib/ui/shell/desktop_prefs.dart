import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/app_state.dart';
import '../../services/local_kv_store.dart';

const _kDesktopPrefsKey = 'desktop_prefs';

/// The strip along the dock's edge that brings a hidden dock back.
const double kDockHotZone = 10;

/// Desktop mode wallpapers. [halo] follows the light/dark theme; the others
/// are fixed scenes.
enum DeskWallpaper {
  halo('Halo'),
  aurora('Aurora'),
  mist('Mist'),
  graphite('Graphite'),
  sunrise('Sunrise');

  const DeskWallpaper(this.label);
  final String label;

  /// The painted background, or null for [halo] (the theme's own wallpaper).
  Gradient? get gradient => switch (this) {
    DeskWallpaper.halo => null,
    DeskWallpaper.aurora => const RadialGradient(center: Alignment(1.1, -1.1), radius: 1.4, colors: [Color(0xB3C04BDB), Color(0x00C04BDB)]),
    DeskWallpaper.mist => const RadialGradient(center: Alignment(-0.6, -0.9), radius: 1.4, colors: [Color(0xFFE9E4FF), Color(0x00E9E4FF)]),
    DeskWallpaper.graphite => const RadialGradient(center: Alignment(0, -1.2), radius: 1.4, colors: [Color(0xFF3A3D52), Color(0x003A3D52)]),
    DeskWallpaper.sunrise => const RadialGradient(
      center: Alignment(-1.1, 1.1),
      radius: 1.3,
      colors: [Color(0xFFFF9E7A), Color(0x00FF9E7A)],
    ),
  };

  /// A second glow layered under [gradient].
  Gradient? get secondGlow => switch (this) {
    DeskWallpaper.aurora => const RadialGradient(center: Alignment(-1.1, 1.1), radius: 1.3, colors: [Color(0x8C1EC8FF), Color(0x001EC8FF)]),
    DeskWallpaper.mist => const RadialGradient(center: Alignment(0.9, 0.9), radius: 1.3, colors: [Color(0xFFDDEFF0), Color(0x00DDEFF0)]),
    DeskWallpaper.sunrise => const RadialGradient(
      center: Alignment(1.1, -1.1),
      radius: 1.3,
      colors: [Color(0xFF8C7BFF), Color(0x008C7BFF)],
    ),
    _ => null,
  };

  Color? get base => switch (this) {
    DeskWallpaper.halo => null,
    DeskWallpaper.aurora => const Color(0xFF05060D),
    DeskWallpaper.mist => const Color(0xFFEEF0F5),
    DeskWallpaper.graphite => const Color(0xFF121420),
    DeskWallpaper.sunrise => const Color(0xFF2A1F3D),
  };
}

enum DockPosition { bottom, left, right }

enum DockSize {
  small(36, 18),
  medium(42, 20),
  large(50, 24);

  const DockSize(this.button, this.icon);
  final double button;
  final double icon;
}

/// How the person has arranged Desktop mode: wallpaper, dock and widget.
/// Saved on this device.
class DesktopPrefs extends ChangeNotifier {
  DeskWallpaper _wallpaper = DeskWallpaper.halo;
  DockPosition _dockPosition = DockPosition.bottom;
  DockSize _dockSize = DockSize.medium;
  bool _autoHide = false;
  bool _showWidget = true;
  bool _showWallpaperWordmark = true;
  bool _showWallpaperSubtitle = true;
  bool _snapToEdges = true;
  List<AxSection> _pinned = List.of(AxSection.values);

  DeskWallpaper get wallpaper => _wallpaper;
  DockPosition get dockPosition => _dockPosition;
  DockSize get dockSize => _dockSize;
  bool get autoHide => _autoHide;
  bool get showWidget => _showWidget;
  bool get showWallpaperWordmark => _showWallpaperWordmark;
  bool get showWallpaperSubtitle => _showWallpaperSubtitle;

  /// Whether dragging a window to a screen edge snaps it (keyboard snapping is always on).
  bool get snapToEdges => _snapToEdges;

  /// The dock's apps, in order.
  List<AxSection> get pinned => List.unmodifiable(_pinned);

  set wallpaper(DeskWallpaper v) => _set(() => _wallpaper = v);
  set dockPosition(DockPosition v) => _set(() => _dockPosition = v);
  set dockSize(DockSize v) => _set(() => _dockSize = v);
  set autoHide(bool v) => _set(() => _autoHide = v);
  set showWidget(bool v) => _set(() => _showWidget = v);
  set showWallpaperWordmark(bool v) => _set(() => _showWallpaperWordmark = v);
  set showWallpaperSubtitle(bool v) => _set(() => _showWallpaperSubtitle = v);
  set snapToEdges(bool v) => _set(() => _snapToEdges = v);

  bool isPinned(AxSection s) => _pinned.contains(s);

  void togglePin(AxSection s) => _set(() => _pinned.contains(s) ? _pinned.remove(s) : _pinned.add(s));

  /// Moves [s] one place earlier (-1) or later (+1) in the dock.
  void movePin(AxSection s, int by) {
    final i = _pinned.indexOf(s);
    final j = i + by;
    if (i < 0 || j < 0 || j >= _pinned.length) return;
    _set(() {
      _pinned
        ..removeAt(i)
        ..insert(j, s);
    });
  }

  void reset() => _set(() {
    _wallpaper = DeskWallpaper.halo;
    _dockPosition = DockPosition.bottom;
    _dockSize = DockSize.medium;
    _autoHide = false;
    _showWidget = true;
    _showWallpaperWordmark = true;
    _showWallpaperSubtitle = true;
    _snapToEdges = true;
    _pinned = List.of(AxSection.values);
  });

  /// Space the dock takes along its edge, so windows stay clear of it.
  /// A dock that hides itself only keeps a thin strip to bring it back.
  EdgeInsets get reserve {
    final depth = _autoHide ? kDockHotZone : _dockSize.button + 44;
    return switch (_dockPosition) {
      DockPosition.bottom => EdgeInsets.only(bottom: depth),
      DockPosition.left => EdgeInsets.only(left: depth),
      DockPosition.right => EdgeInsets.only(right: depth),
    };
  }

  void _set(VoidCallback change) {
    change();
    notifyListeners();
    _save();
  }

  Map<String, Object> toJson() => {
    'wallpaper': _wallpaper.name,
    'dock': _dockPosition.name,
    'size': _dockSize.name,
    'autoHide': _autoHide,
    'widget': _showWidget,
    'showWordmark': _showWallpaperWordmark,
    'showSubtitle': _showWallpaperSubtitle,
    'snap': _snapToEdges,
    'pinned': [for (final s in _pinned) s.name],
  };

  void applyJson(Map<String, dynamic> j) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values.firstWhere((v) => v.name == name, orElse: () => fallback);
    _wallpaper = pick(DeskWallpaper.values, j['wallpaper'], DeskWallpaper.halo);
    _dockPosition = pick(DockPosition.values, j['dock'], DockPosition.bottom);
    _dockSize = pick(DockSize.values, j['size'], DockSize.medium);
    _autoHide = j['autoHide'] == true;
    _showWidget = j['widget'] != false;
    _showWallpaperWordmark = j['showWordmark'] != false;
    _showWallpaperSubtitle = j['showSubtitle'] != false;
    _snapToEdges = j['snap'] != false;
    final pins = j['pinned'];
    if (pins is List) {
      _pinned = [
        for (final n in pins)
          for (final s in AxSection.values)
            if (s.name == n) s,
      ];
    }
  }

  /// Restores the saved arrangement (call once at start-up).
  Future<void> load() async {
    try {
      final raw = await LocalKvStore.instance.read(_kDesktopPrefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) applyJson(j);
      notifyListeners();
    } catch (_) {
      // A convenience: defaults are fine if storage fails.
    }
  }

  void _save() {
    LocalKvStore.instance.write(_kDesktopPrefsKey, jsonEncode(toJson())).catchError((_) {});
  }
}
