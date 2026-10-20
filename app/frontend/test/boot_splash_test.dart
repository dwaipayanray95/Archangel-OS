import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/ui/boot/boot_splash.dart';
import 'package:archangel/ui/components/ax_wordmark.dart';
import 'package:archangel/ui/theme.dart';

Future<void> _pump(WidgetTester tester, BootKind kind, {bool reduced = false}) async {
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: BootSplash(kind: kind, onDone: () => done = true)),
      ),
    ),
  );
  expect(find.byType(BootSplash), findsOneWidget);
  final total = bootTotalDuration(kind, reduced: reduced);
  await tester.pump(total ~/ 2);
  expect(done, isFalse);
  expect(tester.takeException(), isNull);
  await tester.pump(total ~/ 2 + const Duration(milliseconds: 50));
  expect(done, isTrue);
}

void main() {
  testWidgets('the long one runs 7 s, holds the wordmark 3 s, then fades', (tester) async {
    await _pump(tester, BootKind.first);
    expect(find.byType(AxWordmark), findsOneWidget);
  });

  testWidgets('later launches run ~2 s', (tester) async {
    await _pump(tester, BootKind.short);
  });

  testWidgets('reduce motion shortens it to a fade', (tester) async {
    await _pump(tester, BootKind.first, reduced: true);
  });

  testWidgets('phones: BootGate plays the long one first, then the short one', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    var seen = false;
    BootGate.enabled = true;
    BootGate.hasSeenFirst = () async => seen;
    BootGate.markSeenFirst = () async => seen = true;
    addTearDown(() => BootGate.enabled = false);
    final app = AppState();
    Future<void> launch() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (context, child) => BootGate(child: child!),
            home: const Text('app underneath'),
          ),
        ),
      );
      await tester.pump(); // the saved-flag read resolves
      await tester.pump();
    }

    await launch();
    expect(find.text('app underneath'), findsOneWidget);
    expect(find.byType(BootSplash), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 6000));
    expect(find.byType(BootSplash), findsOneWidget, reason: 'first launch is the long one');
    await tester.pump(const Duration(milliseconds: 4600));
    expect(find.byType(BootSplash), findsNothing);

    await launch();
    await tester.pump(const Duration(milliseconds: 4500));
    expect(find.byType(BootSplash), findsOneWidget, reason: 'the wordmark holds for 3 s');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byType(BootSplash), findsNothing, reason: 'later launches are short');

    app.replayBoot(BootKind.first);
    await tester.pump();
    expect(find.byType(BootSplash), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 10600));
    expect(find.byType(BootSplash), findsNothing);
  });

  testWidgets('tablets and computers play the long one every time', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    BootGate.enabled = true;
    BootGate.hasSeenFirst = () async => true;
    addTearDown(() => BootGate.enabled = false);
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState(),
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            builder: (context, child) => BootGate(child: child!),
            home: const Text('app underneath'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 9000));
      expect(find.byType(BootSplash), findsOneWidget, reason: 'launch ${i + 1} is the long one');
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byType(BootSplash), findsNothing);
    }
  });
}
