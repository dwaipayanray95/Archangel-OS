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
}
