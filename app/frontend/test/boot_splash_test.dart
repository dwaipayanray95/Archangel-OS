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
  final total = reduced ? kBootReducedDuration : (kind == BootKind.first ? kBootFirstDuration : kBootShortDuration);
  await tester.pump(total ~/ 2);
  expect(done, isFalse);
  expect(tester.takeException(), isNull);
  await tester.pump(total ~/ 2 + const Duration(milliseconds: 50));
  expect(done, isTrue);
}

void main() {
  testWidgets('first launch runs ~4.3 s and reveals the wordmark', (tester) async {
    await _pump(tester, BootKind.first);
    expect(find.byType(AxWordmark), findsOneWidget);
  });

  testWidgets('later launches run ~2 s', (tester) async {
    await _pump(tester, BootKind.short);
  });

  testWidgets('reduce motion shortens it to a fade', (tester) async {
    await _pump(tester, BootKind.first, reduced: true);
  });

  testWidgets('BootGate plays the long one first, then the short one', (tester) async {
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
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(BootSplash), findsOneWidget, reason: 'first launch is the long one');
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.byType(BootSplash), findsNothing);

    await launch();
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.byType(BootSplash), findsNothing, reason: 'later launches are short');

    app.replayBoot(BootKind.first);
    await tester.pump();
    expect(find.byType(BootSplash), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 4400));
    expect(find.byType(BootSplash), findsNothing);
  });
}
