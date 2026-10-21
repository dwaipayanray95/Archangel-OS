import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/ui/components/ax_scaled_canvas.dart';

void main() {
  group('AxScaledCanvas', () {
    testWidgets('scales canvas on desktop/wide screen and hit-testing works', (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AxScaledCanvas(scale: 0.85, child: child!),
          home: Scaffold(body: Center(child: ElevatedButton(onPressed: () => tapped = true, child: const Text('Click me')))),
        ),
      );

      expect(find.text('Click me'), findsOneWidget);
      await tester.tap(find.text('Click me'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('leaves scale at 1.0 on phone screen (< 500)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Size? reportedSize;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AxScaledCanvas(scale: 0.85, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                reportedSize = MediaQuery.sizeOf(context);
                return const Text('Phone content');
              },
            ),
          ),
        ),
      );

      expect(reportedSize?.width, 390);
    });
  });
}
