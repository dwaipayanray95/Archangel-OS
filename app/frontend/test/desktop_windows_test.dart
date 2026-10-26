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
    expect(d.windowFor(AxSection.apps)!.rect.width, 1200 - 8);
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

  testWidgets('dragging to an edge previews after a dwell and then snaps; dragging away restores', (tester) async {
    final d = desk()..open(AxSection.apps);
    final before = d.windowFor(AxSection.apps)!.rect;
    d.startMove(AxSection.apps);
    d.move(AxSection.apps, const Offset(-10, 0), pointer: const Offset(5, 300));
    expect(d.snap, DeskSnap.none, reason: 'no preview before the dwell');
    await tester.pump(kDeskSnapDwell);
    expect(d.snap, DeskSnap.left);
    expect(d.snapPreview, isNotNull);
    d.endMove(AxSection.apps);
    final w = d.windowFor(AxSection.apps)!;
    expect(d.snapPreview, isNull);
    expect(w.rect.left, 4);
    expect(w.rect.width, closeTo((1200 - 12) / 2, 0.01));
    expect(w.maximized, isTrue);

    // Fitting to a new size keeps it on the left half.
    d.fitTo(const Size(1000, 600));
    expect(d.windowFor(AxSection.apps)!.rect.width, closeTo((1000 - 12) / 2, 0.01));

    // Pulling it away gives back its old size.
    d.startMove(AxSection.apps);
    d.move(AxSection.apps, const Offset(40, 40), pointer: const Offset(400, 200));
    expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
    expect(d.windowFor(AxSection.apps)!.rect.size, before.size);
    d.endMove(AxSection.apps);
    expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
  });

  testWidgets('top edge maximizes, right edge takes the right half', (tester) async {
    final d = desk()..open(AxSection.files);
    expect(d.snapAt(const Offset(600, 2)), DeskSnap.maximize);
    expect(d.snapAt(const Offset(1195, 300)), DeskSnap.right);
    expect(d.snapAt(const Offset(600, 300)), DeskSnap.none);
    d.move(AxSection.files, Offset.zero, pointer: const Offset(1195, 300));
    await tester.pump(kDeskSnapDwell);
    d.endMove(AxSection.files);
    expect(d.windowFor(AxSection.files)!.rect.right, closeTo(1200 - 4, 0.01));
  });

  test('trigger margin is reduced to 10 dp to prevent accidental snaps', () {
    final d = desk();
    // 11 dp away from edges does NOT snap:
    expect(d.snapAt(const Offset(11, 300)), DeskSnap.none);
    expect(d.snapAt(const Offset(1200 - 11, 300)), DeskSnap.none);
    expect(d.snapAt(const Offset(600, 11)), DeskSnap.none);
    expect(d.snapAt(const Offset(600, 700 - 11)), DeskSnap.none);

    // Within 10 dp snaps deliberately:
    expect(d.snapAt(const Offset(9, 300)), DeskSnap.left);
    expect(d.snapAt(const Offset(1200 - 9, 300)), DeskSnap.right);
    expect(d.snapAt(const Offset(600, 9)), DeskSnap.maximize);
    expect(d.snapAt(const Offset(600, 700 - 9)), DeskSnap.thirdCenter);
  });

  test('4 corners snap into 1/4 screen quadrants', () {
    final d = desk();
    // Top-left corner:
    expect(d.snapAt(const Offset(5, 5)), DeskSnap.topLeft);
    expect(d.snapAt(const Offset(20, 5)), DeskSnap.topLeft);
    expect(d.snapAt(const Offset(5, 20)), DeskSnap.topLeft);

    // Top-right corner:
    expect(d.snapAt(const Offset(1195, 5)), DeskSnap.topRight);
    expect(d.snapAt(const Offset(1180, 5)), DeskSnap.topRight);
    expect(d.snapAt(const Offset(1195, 20)), DeskSnap.topRight);

    // Bottom-left corner:
    expect(d.snapAt(const Offset(5, 695)), DeskSnap.bottomLeft);
    expect(d.snapAt(const Offset(20, 695)), DeskSnap.bottomLeft);
    expect(d.snapAt(const Offset(5, 680)), DeskSnap.bottomLeft);

    // Bottom-right corner:
    expect(d.snapAt(const Offset(1195, 695)), DeskSnap.bottomRight);
    expect(d.snapAt(const Offset(1180, 695)), DeskSnap.bottomRight);
    expect(d.snapAt(const Offset(1195, 680)), DeskSnap.bottomRight);

    // Geometry check:
    final tl = d.snapRect(DeskSnap.topLeft)!;
    final tr = d.snapRect(DeskSnap.topRight)!;
    final bl = d.snapRect(DeskSnap.bottomLeft)!;
    final br = d.snapRect(DeskSnap.bottomRight)!;

    final expectedW = (1200 - 12) / 2;
    final expectedH = (700 - 12) / 2;

    expect(tl.left, 4.0);
    expect(tl.top, 4.0);
    expect(tl.width, closeTo(expectedW, 0.01));
    expect(tl.height, closeTo(expectedH, 0.01));

    expect(tr.right, closeTo(1200 - 4, 0.01));
    expect(tr.top, 4.0);
    expect(tr.width, closeTo(expectedW, 0.01));
    expect(tr.height, closeTo(expectedH, 0.01));

    expect(bl.left, 4.0);
    expect(bl.bottom, closeTo(700 - 4, 0.01));
    expect(bl.width, closeTo(expectedW, 0.01));
    expect(bl.height, closeTo(expectedH, 0.01));

    expect(br.right, closeTo(1200 - 4, 0.01));
    expect(br.bottom, closeTo(700 - 4, 0.01));
    expect(br.width, closeTo(expectedW, 0.01));
    expect(br.height, closeTo(expectedH, 0.01));
  });

  test('bottom edge snaps into 1:1:1 three-column thirds', () {
    final d = desk();
    // Bottom edge (outside corner zones):
    expect(d.snapAt(const Offset(200, 695)), DeskSnap.thirdLeft);
    expect(d.snapAt(const Offset(600, 695)), DeskSnap.thirdCenter);
    expect(d.snapAt(const Offset(1000, 695)), DeskSnap.thirdRight);

    // Geometry check:
    final t1 = d.snapRect(DeskSnap.thirdLeft)!;
    final t2 = d.snapRect(DeskSnap.thirdCenter)!;
    final t3 = d.snapRect(DeskSnap.thirdRight)!;

    final thirdW = (1200 - 16) / 3;
    expect(t1.left, 4.0);
    expect(t1.width, closeTo(thirdW, 0.01));
    expect(t1.height, 700 - 8);

    expect(t2.left, closeTo(4 + thirdW + 4, 0.01));
    expect(t2.width, closeTo(thirdW, 0.01));
    expect(t2.height, 700 - 8);

    expect(t3.right, closeTo(1200 - 4, 0.01));
    expect(t3.width, closeTo(thirdW, 0.01));
    expect(t3.height, 700 - 8);
  });

  test('holding Alt/Option snaps into thirds along any edge', () {
    final d = desk();
    // Top edge with Alt:
    expect(d.snapAt(const Offset(200, 5), altPressed: true), DeskSnap.thirdLeft);
    expect(d.snapAt(const Offset(600, 5), altPressed: true), DeskSnap.thirdCenter);
    expect(d.snapAt(const Offset(1000, 5), altPressed: true), DeskSnap.thirdRight);

    // Left/Right edges with Alt:
    expect(d.snapAt(const Offset(5, 300), altPressed: true), DeskSnap.thirdLeft);
    expect(d.snapAt(const Offset(1195, 300), altPressed: true), DeskSnap.thirdRight);
  });

  testWidgets('corner and third snaps restore when moved away', (tester) async {
    final d = desk()..open(AxSection.files);
    final initial = d.windowFor(AxSection.files)!.rect;

    // Drag to bottom-left corner and release:
    d.move(AxSection.files, Offset.zero, pointer: const Offset(5, 695));
    await tester.pump(kDeskSnapDwell);
    expect(d.snap, DeskSnap.bottomLeft);
    d.endMove(AxSection.files);
    expect(d.windowFor(AxSection.files)!.maximized, isTrue);
    expect(d.windowFor(AxSection.files)!.snapped, DeskSnap.bottomLeft);

    // Drag away restores:
    d.startMove(AxSection.files);
    d.move(AxSection.files, const Offset(30, 30), pointer: const Offset(300, 300));
    expect(d.windowFor(AxSection.files)!.maximized, isFalse);
    expect(d.windowFor(AxSection.files)!.rect.size, initial.size);
    d.endMove(AxSection.files);

    // Drag to middle third and release:
    d.move(AxSection.files, Offset.zero, pointer: const Offset(600, 695));
    await tester.pump(kDeskSnapDwell);
    expect(d.snap, DeskSnap.thirdCenter);
    d.endMove(AxSection.files);
    expect(d.windowFor(AxSection.files)!.maximized, isTrue);
    expect(d.windowFor(AxSection.files)!.snapped, DeskSnap.thirdCenter);
    expect(d.windowFor(AxSection.files)!.rect, d.snapRect(DeskSnap.thirdCenter));
  });

  test('tidy lays visible windows out without overlaps', () {
    final d = desk()
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

  test('snapWindow snaps to halves and maximize, and restoreOrMinimize toggles', () {
    final d = desk()..open(AxSection.home);
    final initial = d.windowFor(AxSection.home)!.rect;

    // Snap left
    d.snapWindow(AxSection.home, DeskSnap.left);
    expect(d.windowFor(AxSection.home)!.snapped, DeskSnap.left);
    expect(d.windowFor(AxSection.home)!.rect.left, 4);
    expect(d.windowFor(AxSection.home)!.rect.width, closeTo((1200 - 12) / 2, 0.01));

    // Restore via restoreOrMinimize
    d.restoreOrMinimize(AxSection.home);
    expect(d.windowFor(AxSection.home)!.snapped, DeskSnap.none);
    expect(d.windowFor(AxSection.home)!.rect.size, initial.size);

    // Minimize via restoreOrMinimize when already normal
    d.restoreOrMinimize(AxSection.home);
    expect(d.windowFor(AxSection.home)!.minimized, isTrue);

    // Snap maximize un-minimizes and maximizes
    d.snapWindow(AxSection.home, DeskSnap.maximize);
    expect(d.windowFor(AxSection.home)!.minimized, isFalse);
    expect(d.windowFor(AxSection.home)!.maximized, isTrue);
  });

  test('drag and resize operations toggle isDragging state', () {
    final d = desk()..open(AxSection.terminal);
    final w = d.windowFor(AxSection.terminal)!;
    expect(w.isDragging, isFalse);

    d.startMove(AxSection.terminal);
    expect(w.isDragging, isTrue);

    d.endMove(AxSection.terminal);
    expect(w.isDragging, isFalse);

    d.startResize(AxSection.terminal);
    expect(w.isDragging, isTrue);

    d.endResize(AxSection.terminal);
    expect(w.isDragging, isFalse);
  });

  group('deliberate drag snapping', () {
    testWidgets('a quick flick across an edge never snaps', (tester) async {
      final d = desk()..open(AxSection.apps);
      final before = d.windowFor(AxSection.apps)!.rect;
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, const Offset(-10, 0), pointer: const Offset(5, 300));
      await tester.pump(kDeskSnapDwell ~/ 3);
      d.move(AxSection.apps, const Offset(10, 0), pointer: const Offset(300, 300));
      expect(d.snap, DeskSnap.none);
      await tester.pump(kDeskSnapDwell * 2);
      expect(d.snap, DeskSnap.none, reason: 'leaving the zone cancels the dwell');
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
      expect(d.windowFor(AxSection.apps)!.rect.size, before.size);
    });

    testWidgets('releasing before the dwell ends does not snap', (tester) async {
      final d = desk()..open(AxSection.apps);
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, Offset.zero, pointer: const Offset(1195, 300));
      await tester.pump(kDeskSnapDwell ~/ 2);
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
      await tester.pump(kDeskSnapDwell * 2);
      expect(d.snap, DeskSnap.none);
    });

    testWidgets('the window edge reaching the screen edge does not count, only the pointer', (tester) async {
      final d = desk()..open(AxSection.apps);
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, const Offset(-5000, 0), pointer: const Offset(300, 300));
      await tester.pump(kDeskSnapDwell * 2);
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
    });

    testWidgets('dwell in a zone then release snaps', (tester) async {
      final d = desk()..open(AxSection.apps);
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, Offset.zero, pointer: const Offset(5, 300));
      await tester.pump(kDeskSnapDwell);
      expect(d.snapPreview, isNotNull);
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.snapped, DeskSnap.left);
    });

    testWidgets('a snapped window stays until pulled 16 px, then restores its size and does not re-snap', (tester) async {
      final d = desk()..open(AxSection.apps);
      final floating = d.windowFor(AxSection.apps)!.rect.size;
      d.snapWindow(AxSection.apps, DeskSnap.left);
      final snappedRect = d.windowFor(AxSection.apps)!.rect;
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, const Offset(8, 0), pointer: const Offset(10, 300));
      expect(d.windowFor(AxSection.apps)!.rect, snappedRect, reason: 'small movements keep it snapped');
      expect(d.windowFor(AxSection.apps)!.maximized, isTrue);
      d.move(AxSection.apps, const Offset(10, 0), pointer: const Offset(8, 300));
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
      expect(d.windowFor(AxSection.apps)!.rect.size, floating);
      // Still in the edge zone: holding there must not snap it again.
      await tester.pump(kDeskSnapDwell * 2);
      expect(d.snap, DeskSnap.none);
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
    });

    testWidgets('with snapping off, dragging to an edge never snaps; keyboard snapping still works', (tester) async {
      final d = desk()
        ..snapEnabled = false
        ..open(AxSection.apps);
      d.startMove(AxSection.apps);
      d.move(AxSection.apps, Offset.zero, pointer: const Offset(5, 300));
      await tester.pump(kDeskSnapDwell * 2);
      expect(d.snap, DeskSnap.none);
      d.endMove(AxSection.apps);
      expect(d.windowFor(AxSection.apps)!.maximized, isFalse);
      d.snapWindow(AxSection.apps, DeskSnap.left);
      expect(d.windowFor(AxSection.apps)!.snapped, DeskSnap.left);
    });

    test('opening and tidying never snap', () {
      final d = desk()
        ..open(AxSection.apps)
        ..open(AxSection.files);
      d.tidy();
      for (final w in d.windows) {
        expect(w.snapped, DeskSnap.none);
        expect(w.maximized, isFalse);
      }
    });
  });
}
