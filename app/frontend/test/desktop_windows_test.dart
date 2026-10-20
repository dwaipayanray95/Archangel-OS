import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/shell/desktop_mode.dart';

void main() {
  DesktopWindows desk() => DesktopWindows()..area = const Size(1200, 700);

  test('seeds Home, Terminal and Files once, inside the area', () {
    final d = desk()..ensureDefaults();
    expect(d.windows.map((w) => w.section), [AxSection.home, AxSection.terminal, AxSection.files]);
    for (final w in d.windows) {
      expect(w.rect.width, greaterThanOrEqualTo(kDeskMinWindow.width));
      expect(w.rect.top, greaterThanOrEqualTo(0));
      expect(w.rect.bottom, lessThanOrEqualTo(700));
    }
    d.close(AxSection.home);
    d.close(AxSection.terminal);
    d.close(AxSection.files);
    d.ensureDefaults();
    expect(d.isEmpty, isTrue, reason: 'closing everything leaves the desk empty');
  });

  test('open raises an existing window and un-minimizes it', () {
    final d = desk()..ensureDefaults();
    d.minimize(AxSection.home);
    expect(d.visible.contains(AxSection.home), isFalse);
    d.open(AxSection.home);
    expect(d.front, AxSection.home);
    expect(d.visible.contains(AxSection.home), isTrue);
    expect(d.windows.where((w) => w.section == AxSection.home).length, 1);
  });

  test('focus returns false when already in front', () {
    final d = desk()..open(AxSection.apps);
    expect(d.focus(AxSection.apps), isFalse);
    d.open(AxSection.files);
    expect(d.focus(AxSection.apps), isTrue);
    expect(d.front, AxSection.apps);
  });

  test('moving keeps the title bar reachable', () {
    final d = desk()..open(AxSection.apps);
    d.move(AxSection.apps, const Offset(-5000, -5000));
    final r = d.windowFor(AxSection.apps)!.rect;
    expect(r.top, 0);
    expect(r.right, greaterThanOrEqualTo(120));
    d.move(AxSection.apps, const Offset(9000, 9000));
    final r2 = d.windowFor(AxSection.apps)!.rect;
    expect(r2.left, lessThanOrEqualTo(1200 - 120));
    expect(r2.top, lessThanOrEqualTo(700 - 48));
  });

  test('resize respects the minimum size; maximize and restore round-trip', () {
    final d = desk()..open(AxSection.apps);
    final before = d.windowFor(AxSection.apps)!.rect;
    d.resize(AxSection.apps, const Offset(-5000, -5000));
    expect(d.windowFor(AxSection.apps)!.rect.size, kDeskMinWindow);
    d.toggleMaximize(AxSection.apps);
    expect(d.windowFor(AxSection.apps)!.maximized, isTrue);
    expect(d.windowFor(AxSection.apps)!.rect.width, 1200 - 16);
    d.toggleMaximize(AxSection.apps);
    expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
    expect(d.windowFor(AxSection.apps)!.rect.size, kDeskMinWindow);
    expect(before.width, greaterThan(kDeskMinWindow.width));
  });

  test('launcher toggles and opening from it closes it', () {
    final d = desk();
    d.toggleLauncher();
    expect(d.launcherOpen, isTrue);
    d.open(AxSection.settings);
    expect(d.launcherOpen, isFalse);
  });

  test('dragging to an edge previews and then snaps; dragging away restores', () {
    final d = desk()..open(AxSection.apps);
    final before = d.windowFor(AxSection.apps)!.rect;
    d.move(AxSection.apps, const Offset(-10, 0), pointer: const Offset(5, 300));
    expect(d.snap, DeskSnap.left);
    expect(d.snapPreview, isNotNull);
    d.endMove(AxSection.apps);
    final w = d.windowFor(AxSection.apps)!;
    expect(d.snapPreview, isNull);
    expect(w.rect.left, 8);
    expect(w.rect.width, closeTo((1200 - 24) / 2, 0.01));
    expect(w.maximized, isTrue);

    // Fitting to a new size keeps it on the left half.
    d.fitTo(const Size(1000, 600));
    expect(d.windowFor(AxSection.apps)!.rect.width, closeTo((1000 - 24) / 2, 0.01));

    // Pulling it away gives back its old size.
    d.move(AxSection.apps, const Offset(40, 40), pointer: const Offset(400, 200));
    expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
    expect(d.windowFor(AxSection.apps)!.rect.size, before.size);
    d.endMove(AxSection.apps);
    expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
  });

  test('top edge maximizes, right edge takes the right half', () {
    final d = desk()..open(AxSection.files);
    expect(d.snapAt(const Offset(600, 2)), DeskSnap.maximize);
    expect(d.snapAt(const Offset(1195, 300)), DeskSnap.right);
    expect(d.snapAt(const Offset(600, 300)), DeskSnap.none);
    d.move(AxSection.files, Offset.zero, pointer: const Offset(1195, 300));
    d.endMove(AxSection.files);
    expect(d.windowFor(AxSection.files)!.rect.right, closeTo(1200 - 8, 0.01));
  });

  test('tidy lays visible windows out without overlaps', () {
    final d =
        desk()
          ..open(AxSection.home)
          ..open(AxSection.apps)
          ..open(AxSection.files)
          ..open(AxSection.terminal);
    d.minimize(AxSection.terminal);
    d.tidy();
    final shown = d.windows.where((w) => !w.minimized).toList();
    expect(shown, hasLength(3));
    for (final a in shown) {
      expect(a.rect.left, greaterThanOrEqualTo(0));
      expect(a.rect.right, lessThanOrEqualTo(1200));
      for (final b in shown) {
        if (!identical(a, b)) expect(a.rect.overlaps(b.rect), isFalse);
      }
    }
  });

  test('defaults keep clear of the health widget', () {
    final d = desk()..ensureDefaults(rightInset: 272);
    for (final w in d.windows) {
      expect(w.rect.right, lessThanOrEqualTo(1200 - 272 + 1));
    }
  });
}
