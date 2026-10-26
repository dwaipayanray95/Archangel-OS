import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/shell/desktop_prefs.dart';

import 'test_utils.dart';

void main() {
  setUp(() async => useTempKvStore());

  test('defaults: Halo wallpaper, medium dock at the bottom, every app pinned', () {
    final p = DesktopPrefs();
    expect(p.wallpaper, DeskWallpaper.halo);
    expect(p.dockPosition, DockPosition.bottom);
    expect(p.dockSize, DockSize.medium);
    expect(p.autoHide, isFalse);
    expect(p.showWidget, isTrue);
    expect(p.showWallpaperWordmark, isTrue);
    expect(p.showWallpaperSubtitle, isTrue);
    expect(p.pinned, AxSection.values);
    expect(p.reserve, EdgeInsets.only(bottom: DockSize.medium.button + 44));
  });

  test('pins can be removed, added back at the end and reordered', () {
    final p = DesktopPrefs()..togglePin(AxSection.home);
    expect(p.isPinned(AxSection.home), isFalse);
    p.togglePin(AxSection.home);
    expect(p.pinned.last, AxSection.home);
    p.movePin(AxSection.home, -1);
    expect(p.pinned[p.pinned.length - 2], AxSection.home);
    p.movePin(AxSection.apps, -5); // out of range: ignored
    expect(p.pinned.length, AxSection.values.length);
  });

  test('the dock reserves space on its own edge; auto-hide keeps only a strip', () {
    final p = DesktopPrefs()
      ..dockPosition = DockPosition.left
      ..dockSize = DockSize.large;
    expect(p.reserve, EdgeInsets.only(left: DockSize.large.button + 44));
    p.autoHide = true;
    expect(p.reserve, const EdgeInsets.only(left: kDockHotZone));
  });

  test('round-trips through JSON and ignores unknown values', () {
    final p = DesktopPrefs()
      ..wallpaper = DeskWallpaper.sunrise
      ..dockPosition = DockPosition.right
      ..dockSize = DockSize.small
      ..autoHide = true
      ..showWidget = false
      ..showWallpaperWordmark = false
      ..showWallpaperSubtitle = false
      ..togglePin(AxSection.files);
    final q = DesktopPrefs()..applyJson(p.toJson());
    expect(q.toJson(), p.toJson());

    final r = DesktopPrefs()
      ..applyJson({
        'wallpaper': 'neon',
        'dock': 'top',
        'pinned': ['home', 'nope'],
      });
    expect(r.wallpaper, DeskWallpaper.halo);
    expect(r.dockPosition, DockPosition.bottom);
    expect(r.showWallpaperWordmark, isTrue);
    expect(r.showWallpaperSubtitle, isTrue);
    expect(r.pinned, [AxSection.home]);
  });

  test('reset puts everything back', () {
    final p = DesktopPrefs()
      ..wallpaper = DeskWallpaper.graphite
      ..showWallpaperWordmark = false
      ..showWallpaperSubtitle = false
      ..togglePin(AxSection.home)
      ..reset();
    expect(p.wallpaper, DeskWallpaper.halo);
    expect(p.showWallpaperWordmark, isTrue);
    expect(p.showWallpaperSubtitle, isTrue);
    expect(p.pinned, AxSection.values);
  });

  test('every fixed wallpaper paints something; Halo uses the theme', () {
    for (final w in DeskWallpaper.values) {
      expect(w.base == null, w == DeskWallpaper.halo);
      expect(w.gradient == null, w == DeskWallpaper.halo);
    }
  });

  test('snapping to screen edges is on by default, saved and reset', () {
    final p = DesktopPrefs();
    expect(p.snapToEdges, isTrue);
    p.snapToEdges = false;
    final q = DesktopPrefs()..applyJson(p.toJson());
    expect(q.snapToEdges, isFalse);
    expect(DesktopPrefs().snapToEdges, isTrue);
    p.reset();
    expect(p.snapToEdges, isTrue);
  });
}
