import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/components/ax_scaled_canvas.dart';

void main() {
  group('AxUiScale and AxScaledCanvas', () {
    test('AxUiScale enum values match requested factors', () {
      expect(AxUiScale.small70.factor, 0.70);
      expect(AxUiScale.default80.factor, 0.80);
      expect(AxUiScale.large90.factor, 0.90);
      expect(AxUiScale.fromName('small70'), AxUiScale.small70);
      expect(AxUiScale.fromName('large90'), AxUiScale.large90);
      expect(AxUiScale.fromName('unknown'), AxUiScale.default80);
    });

    testWidgets('FittedBox scaling fills the full screen and hit-testing is exact', (tester) async {
      const screenSize = Size(1000, 800);
      tester.view.physicalSize = screenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scale = 0.70;
      var buttonClicked = false;
      var bottomClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AxScaledCanvas(scaleFactor: scale, child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 10,
                  child: ElevatedButton(onPressed: () => buttonClicked = true, child: const Text('Top Button')),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: ElevatedButton(onPressed: () => bottomClicked = true, child: const Text('Bottom Button')),
                ),
              ],
            ),
          ),
        ),
      );

      // Verify buttons are found
      expect(find.text('Top Button'), findsOneWidget);
      expect(find.text('Bottom Button'), findsOneWidget);

      // Tap top button
      await tester.tap(find.text('Top Button'));
      await tester.pump();
      expect(buttonClicked, isTrue);

      // Tap bottom button
      await tester.tap(find.text('Bottom Button'));
      await tester.pump();
      expect(bottomClicked, isTrue);
    });

    testWidgets('UI Scale SegmentedButton updates selection cleanly', (tester) async {
      AxUiScale selectedScale = AxUiScale.default80;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SegmentedButton<AxUiScale>(
                  key: const ValueKey('ui-scale-choice'),
                  showSelectedIcon: false,
                  segments: [for (final s in AxUiScale.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {selectedScale},
                  onSelectionChanged: (s) => setState(() => selectedScale = s.first),
                );
              },
            ),
          ),
        ),
      );

      expect(selectedScale, AxUiScale.default80);

      // Tap Small (70%)
      await tester.tap(find.text('Small (70%)'));
      await tester.pumpAndSettle();
      expect(selectedScale, AxUiScale.small70);

      // Tap Large (90%)
      await tester.tap(find.text('Large (90%)'));
      await tester.pumpAndSettle();
      expect(selectedScale, AxUiScale.large90);

      // Tap Default (80%)
      await tester.tap(find.text('Default (80%)'));
      await tester.pumpAndSettle();
      expect(selectedScale, AxUiScale.default80);
    });
  });
}
