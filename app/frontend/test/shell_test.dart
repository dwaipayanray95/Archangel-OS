import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/screens/monitoring_screen.dart';
import 'package:archangel/screens/overview_screen.dart';
import 'package:archangel/screens/settings_screen.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/ui/shell/archangel_shell.dart';
import 'package:archangel/ui/shell/more_page.dart';

import 'test_utils.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

T _read<T>(WidgetTester tester) => tester.element(find.byType(ArchangelShell)).read<T>();

ServerProfile _profile(String id, String host) => ServerProfile(
      id: id,
      name: 'Server $id',
      host: host,
      token: 't$id',
      wgConfig: '',
      createdAt: DateTime.utc(2025),
    );

void main() {
  const phone = Size(390, 844);

  group('phone layout', () {
    testWidgets('bottom bar has Home, Apps, Files, Terminal and More - no rail', (tester) async {
      await pumpAppShell(tester, size: phone);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final l in ['Home', 'Apps', 'Files', 'Terminal', 'More']) {
        expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(l)), findsOneWidget, reason: l);
      }
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')), findsNothing);
    });

    testWidgets('More lists Activity, Services, Settings and the server switcher', (tester) async {
      await pumpAppShell(tester, size: phone);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await _settle(tester);

      expect(find.byType(MorePage), findsOneWidget);
      expect(find.byKey(const ValueKey('more-activity')), findsOneWidget);
      expect(find.byKey(const ValueKey('more-services')), findsOneWidget);
      expect(find.byKey(const ValueKey('more-settings')), findsOneWidget);
      expect(find.text('Add a server'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('more-settings')));
      await _settle(tester);
      expect(_read<AppState>(tester).section, AxSection.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
      // Back arrow in the status strip returns to More.
      await tester.tap(find.byTooltip('Back to More'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('more-activity')), findsOneWidget);
    });

    testWidgets('lists the registry\'s servers with the active one selected', (tester) async {
      await pumpAppShell(tester, size: phone, seedRegistry: (registry) async {
        await registry.add(_profile('a', 'h1'));
        await registry.add(_profile('b', 'h2'));
        await registry.setActive('a');
      });
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await _settle(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('server-a')), matching: find.text('Server a')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('server-b')), matching: find.text('Server b')), findsOneWidget);
      // The status strip names the active server too.
      expect(find.text('Server a'), findsNWidgets(2));
      final active = tester.widget<ListTile>(find.descendant(of: find.byKey(const ValueKey('server-a')), matching: find.byType(ListTile)));
      expect(active.selected, isTrue);
    });
  });

  group('server switching', () {
    testWidgets('switching servers re-points the connection and resets the destinations', (tester) async {
      await pumpAppShell(tester, size: phone, seedRegistry: (registry) async {
        await registry.add(_profile('a', '10.0.0.1:8443'));
        await registry.add(_profile('b', '10.0.0.2:8443'));
        await registry.setActive('a');
      });
      final registry = _read<ServerRegistry>(tester);
      final backend = _read<ArchangeldConnection>(tester);
      final wg = _read<WireGuardController>(tester);

      Future<void> switchTo(String id) => tester.runAsync(() async {
            await switchToServer(id, registry: registry, wg: wg, backend: backend);
            while (backend.backendChecking) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });

      await switchTo('a');
      await _settle(tester);
      expect(backend.host, '10.0.0.1:8443');
      final before = tester.state(find.byType(OverviewScreen));

      await switchTo('b');
      await _settle(tester);
      expect(registry.activeId, 'b');
      expect(backend.host, '10.0.0.2:8443');
      expect(backend.token, 'tb');
      expect(tester.state(find.byType(OverviewScreen)), isNot(same(before)));
      expect(find.text('Server b'), findsOneWidget); // status strip
    });

    testWidgets('desktop rail header opens the server sheet with Add a server', (tester) async {
      await pumpAppShell(tester, seedRegistry: (registry) async {
        await registry.add(_profile('a', 'h1'));
      });
      await tester.tap(find.byTooltip('Switch server'));
      await _settle(tester);
      expect(find.text('Your servers'), findsOneWidget);
      expect(find.text('Add a server'), findsOneWidget);
    });
  });

  group('desktop layout', () {
    testWidgets('extended rail at >= 1100 with all seven destinations and the wordmark', (tester) async {
      await pumpAppShell(tester);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.byType(NavigationBar), findsNothing);
      for (final s in AxSection.values) {
        expect(find.descendant(of: find.byType(NavigationRail), matching: find.text(axSectionLabels[s]!)), findsOneWidget, reason: '$s');
      }
      expect(find.text('Archangel'), findsOneWidget);
    });

    testWidgets('compact rail between 720 and 1100', (tester) async {
      await pumpAppShell(tester, size: const Size(900, 700));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short windows scroll the rail instead of overflowing', (tester) async {
      // 7 rail destinations + the server switcher need ~650dp; at 520 the
      // rail must scroll. (Legacy screens themselves are not tuned for this
      // height, so look at a section that is.)
      final app = await pumpAppShell(tester, size: const Size(1400, 520));
      app.go(AxSection.files);
      await _settle(tester);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.ancestor(of: find.byType(NavigationRail), matching: find.byType(SingleChildScrollView)), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rail selection navigates', (tester) async {
      final app = await pumpAppShell(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Files')));
      await _settle(tester);
      expect(app.section, AxSection.files);
    });
  });

  group('destinations', () {
    testWidgets('are built lazily on first visit and kept alive afterwards', (tester) async {
      final app = await pumpAppShell(tester);
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.byType(MonitoringScreen, skipOffstage: false), findsNothing);

      app.go(AxSection.activity);
      await _settle(tester);
      expect(find.byType(MonitoringScreen), findsOneWidget);

      final homeState = tester.state(find.byType(OverviewScreen, skipOffstage: false));
      app.go(AxSection.home);
      await _settle(tester);
      expect(tester.state(find.byType(OverviewScreen)), same(homeState));
      expect(find.byType(MonitoringScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('only the visible destination keeps its service polling', (tester) async {
      final app = await pumpAppShell(tester);
      final mon = _read<MonitoringService>(tester);
      final cont = _read<ContainersService>(tester);
      final dev = _read<DevopsService>(tester);

      expect([mon.active, cont.active, dev.active], [true, true, true]); // Home summarises all three

      app.go(AxSection.files);
      await _settle(tester);
      expect([mon.active, cont.active, dev.active], [false, false, false]);

      app.go(AxSection.apps);
      await _settle(tester);
      expect([mon.active, cont.active, dev.active], [false, true, false]);

      app.go(AxSection.services);
      await _settle(tester);
      expect([mon.active, cont.active, dev.active], [false, false, true]);

      app.go(AxSection.activity);
      await _settle(tester);
      expect([mon.active, cont.active, dev.active], [true, false, false]);
      expect(mon.pollingRateMs, 1000);

      app.go(AxSection.home);
      await _settle(tester);
      expect([mon.active, cont.active, dev.active], [true, true, true]);
      expect(mon.pollingRateMs, 5000);
    });

    testWidgets('phone: nothing polls while the More page is showing', (tester) async {
      await pumpAppShell(tester, size: phone);
      final mon = _read<MonitoringService>(tester);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await _settle(tester);
      expect(mon.active, isFalse);
    });

    testWidgets('switching the connected server rebuilds destinations (fresh per-server state)', (tester) async {
      await pumpAppShell(tester);
      final backend = _read<ArchangeldConnection>(tester);
      Future<void> pair(String host, String token) => tester.runAsync(() async {
            await backend.pair(host: host, token: token);
            // pair() starts a background version check; let it finish.
            while (backend.backendChecking) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
      await pair('10.0.0.1:8443', 'a');
      await _settle(tester);
      final before = tester.state(find.byType(OverviewScreen));

      await pair('10.0.0.2:8443', 'b');
      await _settle(tester);
      expect(tester.state(find.byType(OverviewScreen)), isNot(same(before)));
    });
  });

  group('back button', () {
    testWidgets('goes to Home first, then lets the app exit', (tester) async {
      final app = await pumpAppShell(tester);
      app.go(AxSection.files);
      await _settle(tester);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await _settle(tester);
      expect(app.section, AxSection.home);

      // At Home the shell no longer intercepts back, so the system may exit.
      final route = ModalRoute.of(tester.element(find.byType(ArchangelShell)))!;
      expect(route.popDisposition, isNot(RoutePopDisposition.doNotPop));
    });

    testWidgets('closes the command palette before leaving the section', (tester) async {
      final app = await pumpAppShell(tester);
      app.go(AxSection.files);
      app.openPalette();
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(app.paletteOpen, isFalse);
      expect(app.section, AxSection.files);
    });

    testWidgets('phone: from the More page back goes Home', (tester) async {
      final app = await pumpAppShell(tester, size: phone);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(MorePage), findsNothing);
      expect(app.section, AxSection.home);
    });

    testWidgets('a dialog on top is popped before the shell reacts', (tester) async {
      final app = await pumpAppShell(tester);
      app.go(AxSection.files);
      await _settle(tester);
      showDialog<void>(
        context: tester.element(find.byType(ArchangelShell)),
        builder: (_) => const AlertDialog(title: Text('A dialog')),
      );
      await _settle(tester);
      expect(find.text('A dialog'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.text('A dialog'), findsNothing);
      expect(app.section, AxSection.files);
    });
  });

  group('status strip', () {
    testWidgets('shows the secure connection state in words, not only colour', (tester) async {
      await pumpAppShell(tester);
      expect(find.text('Secure connection off'), findsOneWidget);
    });

    testWidgets('search button opens the palette', (tester) async {
      final app = await pumpAppShell(tester);
      await tester.tap(find.byTooltip('Search (Ctrl K)'));
      await _settle(tester);
      expect(app.paletteOpen, isTrue);
    });
  });
}
