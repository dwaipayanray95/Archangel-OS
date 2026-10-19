import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';

import 'test_utils.dart';

// pumpAndSettle() never returns here: several widgets (status-dot pulses,
// the terminal cursor) animate on an infinite repeat by design, so settle
// on a fixed number of frames instead.
Future<void> _pump(WidgetTester tester, AppState app, AxSection s) async {
  app.go(s);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('every section renders without overflow or exceptions', (tester) async {
    final app = await pumpAppShell(tester);

    for (final s in AxSection.values) {
      await _pump(tester, app, s);
      expect(tester.takeException(), isNull, reason: 'exception while showing $s');
    }
  });

  testWidgets('phone width shows the bottom bar (with More) and no overflow', (tester) async {
    final app = await pumpAppShell(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);

    for (final s in AxSection.values) {
      await _pump(tester, app, s);
      expect(tester.takeException(), isNull, reason: 'exception at phone width while showing $s');
    }
  });

  testWidgets('command palette opens and filters', (tester) async {
    final app = await pumpAppShell(tester);

    app.openPalette();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('SECTIONS'), findsOneWidget);
  });
}
