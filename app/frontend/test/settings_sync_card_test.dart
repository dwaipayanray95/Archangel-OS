import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/services/prefs_sync_service.dart';
import 'package:archangel/ui/screens/settings/settings_sync_card.dart';
import 'package:archangel/ui/theme.dart';

import 'prefs_sync_fakes.dart';

void main() {
  Future<PrefsSyncService> pump(
    WidgetTester tester,
    FakePrefsServer server, {
    Size size = const Size(900, 900),
    String? serverKey = 'srv',
    Future<void> Function(PrefsSyncService svc)? before,
  }) async {
    final svc = PrefsSyncService(
      transport: server.transport(),
      store: MemoryKvStore(),
      debounce: null,
      pollInterval: null,
      now: () => DateTime.utc(2026, 10, 27, 12),
    );
    addTearDown(svc.dispose);
    await tester.runAsync(() async {
      await svc.bind(serverKey);
      await before?.call(svc);
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ChangeNotifierProvider<PrefsSyncService>.value(
        value: svc,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark, AxAccent.halo),
          home: Scaffold(
            body: SingleChildScrollView(child: SettingsSyncCard(now: () => DateTime.utc(2026, 10, 27, 12, 3))),
          ),
        ),
      ),
    );
    await tester.pump();
    return svc;
  }

  testWidgets('a server without the endpoint says so, quietly', (tester) async {
    await pump(tester, FakePrefsServer()..supported = false, before: (s) => s.syncNow());
    expect(find.text("This server can't sync settings yet. They stay on this device."), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a synced server shows the last sync time', (tester) async {
    await pump(tester, FakePrefsServer(), before: (s) => s.syncNow());
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Last synced 3 min ago.'), findsOneWidget);
  });

  testWidgets('an unreachable server keeps changes queued and says so', (tester) async {
    final server = FakePrefsServer()..unreachable = true;
    await pump(
      tester,
      server,
      before: (s) async {
        await s.setLocal(kPrefAccent, 'ice');
        await s.syncNow();
      },
    );
    expect(find.textContaining('saved here and will sync'), findsOneWidget);
  });

  testWidgets('with no server it says settings stay on this device', (tester) async {
    await pump(tester, FakePrefsServer(), serverKey: null);
    expect(find.textContaining('Pair a server'), findsOneWidget);
  });

  testWidgets('the switch turns the local opt-out on and off', (tester) async {
    final svc = await pump(tester, FakePrefsServer());
    final toggle = find.byKey(const ValueKey('settings-ignore-server-appearance'));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.runAsync(() async {
      await tester.tap(toggle);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(svc.ignoreServerAppearance, isTrue);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });

  testWidgets('it is hidden where no sync service is provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark, AxAccent.halo),
        home: const Scaffold(body: SettingsSyncCard()),
      ),
    );
    expect(find.text('Settings sync'), findsNothing);
  });

  for (final width in [340.0, 390.0]) {
    testWidgets('no overflow at ${width.toInt()} wide, even offline', (tester) async {
      await pump(tester, FakePrefsServer()..unreachable = true, size: Size(width, 700), before: (s) => s.syncNow());
      expect(find.text('Settings sync'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
