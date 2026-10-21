import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/screens/settings_screen.dart';
import 'package:archangel/services/app_version.dart';
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/ssh_credentials.dart';
import 'package:archangel/services/ssh_transport.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/ui/screens/settings/settings_view.dart';
import 'package:archangel/ui/theme.dart';
import 'package:archangel/widgets/uninstall_dialog.dart';

import '../test_utils.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

ServerProfile _profile(String id, {int appPort = 8443, int wgPort = 51820, String? sshHost}) => ServerProfile(
  id: id,
  name: 'Server $id',
  host: '10.0.0.${id.codeUnitAt(0) - 96}:$appPort',
  token: 'tok-$id',
  wgConfig: '',
  sshHost: sshHost,
  sshUser: 'deploy',
  appPort: appPort,
  wgPort: wgPort,
  createdAt: DateTime.utc(2025),
);

class _Fake implements SshTransport {
  final commands = <String>[];
  @override
  Future<SshExecResult> exec(String command) async {
    commands.add(command);
    return const SshExecResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<void> uploadFile(String remotePath, Uint8List content, {String? chmod}) async {}

  @override
  Future<void> close() async {}
}

class _Harness {
  _Harness(this.app, this.registry, this.backend, this.devicesRequests);
  final AppState app;
  final ServerRegistry registry;
  final ArchangeldConnection backend;
  final List<http.Request> devicesRequests;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps the Settings screen inside the providers the app uses, paired with
/// one or two servers and a mocked backend.
Future<_Harness> _pumpSettings(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
  Brightness brightness = Brightness.dark,
  bool paired = true,
  bool twoServers = true,
  Future<http.Response> Function(http.Request req)? devicesHandler,
  MonitoringService? monitoring,
  Widget Function(Widget child)? wrap,
}) async {
  final registry = ServerRegistry();
  final requests = <http.Request>[];
  final backend = ArchangeldConnection(client: MockClient((_) async => _json({'version': '0.5.0'})));
  final app = AppState();
  await tester.runAsync(() async {
    await useTempKvStore();
    if (paired) {
      final a = await registry.add(_profile('a'));
      if (twoServers) await registry.add(_profile('b'), activate: false);
      await backend.pair(host: a.host, token: a.token);
    }
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final devicesClient = MockClient((req) async {
    requests.add(req);
    if (devicesHandler != null) return devicesHandler(req);
    return _json([
      {'name': 'laptop', 'created_at': '2026-08-14T10:00:00Z', 'tunnel_ip': '10.10.0.2', 'current': true},
      {'name': 'pixel', 'created_at': '2026-09-01T10:00:00Z', 'tunnel_ip': '10.10.0.3'},
    ]);
  });
  final adminClient = MockClient((_) async => _json({'enabled': true}));

  Widget child = const SettingsScreen();
  if (wrap != null) child = wrap(child);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<ServerRegistry>.value(value: registry),
        ChangeNotifierProvider(create: (_) => WireGuardController()),
        ChangeNotifierProvider<ArchangeldConnection>.value(value: backend),
        ChangeNotifierProvider<MonitoringService>(create: (_) => monitoring ?? MonitoringService()),
        ChangeNotifierProvider(create: (_) => DevicesService(client: devicesClient)),
        ChangeNotifierProvider(create: (_) => AdminModeService(client: adminClient)),
        ChangeNotifierProvider(create: (_) => UpdateCheckService()),
      ],
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(brightness, AxAccent.green), home: Scaffold(body: child)),
    ),
  );
  await _settle(tester);
  return _Harness(app, registry, backend, requests);
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await _settle(tester);
}

/// Chooses a section in the list (wide: selects it; narrow: opens it).
Future<void> _open(WidgetTester tester, SettingsSectionId id) async {
  final nav = find.byKey(ValueKey('settings-nav-${id.name}'));
  if (nav.evaluate().isEmpty) return;
  await tester.tap(nav);
  await _settle(tester);
}

/// Narrow only: back to the section list.
Future<void> _back(WidgetTester tester) async {
  final back = find.text('All settings');
  if (back.evaluate().isEmpty) return;
  await tester.tap(back);
  await _settle(tester);
}

/// The Remove button of the n-th device row (laptop is first, pixel second).
Finder _removeButton(int index) => find.widgetWithText(TextButton, 'Remove').at(index);

Finder _inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

class _FakeMonitoring extends MonitoringService {
  _FakeMonitoring(this.result);
  final ProcessActionResult result;
  int reboots = 0;

  @override
  Future<ProcessActionResult> rebootHost() async {
    reboots++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layout', () {
    testWidgets('wide: the section list shows and Servers is chosen by default', (tester) async {
      await _pumpSettings(tester);
      for (final id in SettingsSectionId.values) {
        expect(find.byKey(ValueKey('settings-nav-${id.name}')), findsOneWidget, reason: id.name);
      }
      expect(find.text('Archangel v${AppVersion.archangel}'), findsOneWidget);
      expect(find.text('Add a server'), findsOneWidget);
      expect(find.text('Server a'), findsOneWidget);
      expect(find.text('Repair server permissions'), findsNothing);
    });

    testWidgets('wide: clicking Security shows its rows', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.security);
      expect(find.text('SSH key'), findsOneWidget);
      expect(find.text('Secure connection'), findsOneWidget);
      expect(find.text('Repair server permissions'), findsOneWidget);
      expect(find.text('Add a server'), findsNothing);
      // Left out of v1.
      expect(find.text('Firewall'), findsNothing);
      expect(find.text('Lock the app'), findsNothing);
      expect(find.text('Rotate tunnel keys'), findsNothing);
    });

    testWidgets('narrow: the list shows, tapping Appearance opens it, and All settings goes back', (tester) async {
      await _pumpSettings(tester, size: const Size(390, 844));
      expect(find.byKey(const ValueKey('settings-nav-appearance')), findsOneWidget);
      expect(find.text('Add a server'), findsNothing);
      expect(find.text('All settings'), findsNothing);

      await _open(tester, SettingsSectionId.appearance);
      expect(find.text('All settings'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-nav-appearance')), findsNothing);

      await _back(tester);
      expect(find.text('Theme'), findsNothing);
      expect(find.byKey(const ValueKey('settings-nav-appearance')), findsOneWidget);
    });

    testWidgets('Devices and Admin mode are hidden when unpaired', (tester) async {
      for (final size in [const Size(1400, 900), const Size(390, 844)]) {
        await _pumpSettings(tester, size: size, paired: false);
        expect(find.byKey(const ValueKey('settings-nav-devices')), findsNothing);
        expect(find.byKey(const ValueKey('settings-nav-admin')), findsNothing);
        expect(find.byKey(const ValueKey('settings-nav-servers')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings-nav-security')), findsOneWidget);
      }
    });

    for (final size in [const Size(340, 600), const Size(390, 844), const Size(1400, 900)]) {
      for (final brightness in Brightness.values) {
        testWidgets('every section renders without overflow at ${size.width.toInt()} (${brightness.name})', (tester) async {
          await _pumpSettings(tester, size: size, brightness: brightness);
          for (final id in SettingsSectionId.values) {
            await _open(tester, id);
            expect(tester.takeException(), isNull, reason: id.name);
            await _back(tester);
          }
        });
      }
    }
  });

  group('servers', () {
    testWidgets('the active server shows In use and the others a Switch to it button', (tester) async {
      await _pumpSettings(tester);
      expect(find.text('In use'), findsOneWidget);
      expect(find.text('Switch to it'), findsOneWidget);
      expect(find.byTooltip('More for Server a'), findsOneWidget);
      expect(find.byTooltip('More for Server b'), findsOneWidget);
    });

    testWidgets('Switch to it makes that server the active one', (tester) async {
      final h = await _pumpSettings(tester);
      await _tapText(tester, 'Switch to it');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(h.registry.activeId, 'b');
    });

    testWidgets('Rename changes the name', (tester) async {
      final h = await _pumpSettings(tester);
      await tester.tap(find.byTooltip('More for Server b'));
      await _settle(tester);
      await tester.tap(find.text('Rename'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'Lab');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(h.registry.profiles.firstWhere((p) => p.id == 'b').name, 'Lab');
    });

    testWidgets('Remove explains it only forgets the server on this device and removes a non-active one', (tester) async {
      final h = await _pumpSettings(tester);
      await tester.tap(find.byTooltip('More for Server b'));
      await _settle(tester);
      await tester.tap(find.text('Remove'));
      await _settle(tester);
      expect(find.textContaining('only forgets the server on this device'), findsOneWidget);
      await tester.tap(_inDialog('Remove'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(h.registry.profiles.map((p) => p.id), ['a']);
    });
  });

  group('devices', () {
    testWidgets('this device has a chip and a Remove button, and is listed with the paired date and address', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.devices);
      expect(find.text('laptop'), findsOneWidget);
      expect(find.text('pixel'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(find.text('Remove'), findsNWidgets(2));
      expect(find.textContaining('Paired Aug 14, 2026'), findsOneWidget);
      expect(find.textContaining('Only devices listed here can reach your server'), findsOneWidget);
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('removing another device asks first, then calls the server', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.devices);
      await tester.tap(_removeButton(1));
      await _settle(tester);
      expect(find.text('Remove pixel?'), findsOneWidget);
      expect(find.text("It won't be able to reach your server any more."), findsOneWidget);
      await tester.tap(_inDialog('Remove'));
      await _settle(tester);
      expect(h.devicesRequests.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(h.devicesRequests.firstWhere((r) => r.method == 'DELETE').url.path, contains('pixel'));
    });

    testWidgets('cancelling the removal does nothing', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.devices);
      await tester.tap(_removeButton(1));
      await _settle(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(h.devicesRequests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('removing this device needs its name typed', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.devices);
      await tester.tap(_removeButton(0));
      await _settle(tester);
      expect(find.text('Revoke "laptop"?'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Revoke')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'laptop');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Revoke')).onPressed, isNotNull);
      expect(h.devicesRequests.where((r) => r.method == 'DELETE'), isEmpty);
    });

    testWidgets('an error offers Retry', (tester) async {
      await _pumpSettings(tester, devicesHandler: (_) async => _json({'message': 'nope'}, 500));
      await _open(tester, SettingsSectionId.devices);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('admin mode', () {
    testWidgets('shows the switch, the chip and both paragraphs', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.admin);
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Administrator commands allowed'), findsOneWidget);
      expect(find.textContaining('administrator commands (sudo)'), findsOneWidget);
      expect(find.textContaining('safety net against accidental changes'), findsOneWidget);
    });

    testWidgets('turning it off asks first, and Cancel keeps it on', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.admin);
      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(find.text('Turn off Admin mode?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('add a device', () {
    testWidgets('happy path shows the QR code, the selectable code and the warning, then refreshes the list', (tester) async {
      const bundle = 'eyJ2IjoxLCJuYW1lIjoibWFyaWEifQ==';
      http.Request? created;
      final h = await _pumpSettings(
        tester,
        devicesHandler: (req) async {
          if (req.method == 'POST') {
            created = req;
            return _json({'success': true, 'name': 'Maria phone', 'bundle': bundle});
          }
          return _json([]);
        },
      );
      await _open(tester, SettingsSectionId.devices);
      await _tapText(tester, 'Add a device');
      expect(find.text('Device name'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Maria phone');
      await tester.pumpAndSettle();
      await _tapText(tester, 'Create pairing code');

      expect(jsonDecode(created!.body), {'name': 'Maria phone'});
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(bundle), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Copy code'), findsOneWidget);
      expect(find.textContaining("don't share it"), findsOneWidget);
      expect(find.textContaining("It's only shown now"), findsOneWidget);
      expect(find.textContaining('I have a pairing code'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final before = h.devicesRequests.where((r) => r.method == 'GET').length;
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(h.devicesRequests.where((r) => r.method == 'GET').length, greaterThan(before));
    });

    testWidgets('403 shows the server\'s admin-mode message and keeps the form', (tester) async {
      await _pumpSettings(
        tester,
        devicesHandler:
            (req) async =>
                req.method == 'POST' ? _json({'success': false, 'message': 'Admin mode is off - this action needs it'}, 403) : _json([]),
      );
      await _open(tester, SettingsSectionId.devices);
      await _tapText(tester, 'Add a device');
      await tester.enterText(find.byType(TextField), 'tablet');
      await tester.pumpAndSettle();
      await _tapText(tester, 'Create pairing code');
      expect(find.text('Admin mode is off - this action needs it'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Create pairing code'), findsOneWidget);
    });

    testWidgets('an invalid name is explained without calling the server', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.devices);
      await _tapText(tester, 'Add a device');
      await tester.enterText(find.byType(TextField), '-bad');
      await tester.pumpAndSettle();
      await _tapText(tester, 'Create pairing code');
      expect(find.textContaining('starting with a letter or number'), findsOneWidget);
      expect(h.devicesRequests.where((r) => r.method == 'POST'), isEmpty);
    });
  });

  group('appearance', () {
    testWidgets('picking a theme and accent updates AppState and persists', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.appearance);
      await _tapText(tester, 'Pearl');
      expect(h.app.themeMode, ThemeMode.light);
      await _tapText(tester, 'Auto');
      expect(h.app.themeMode, ThemeMode.system);
      await _tapText(tester, 'Dawn');
      await _tapText(tester, 'Pearl');
      await tester.tap(find.byKey(const ValueKey('accent-ice')));
      await _settle(tester);
      expect(h.app.accentChoice, AxAccent.ice);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      final reloaded = AppState();
      await tester.runAsync(reloaded.loadAppearance);
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.accentChoice, AxAccent.ice);
    });

    testWidgets('Layout and Desktop rows follow the screen size, not the window', (tester) async {
      await _pumpSettings(tester, size: const Size(1400, 900));
      await _open(tester, SettingsSectionId.appearance);
      expect(find.byKey(const ValueKey('layout-choice')), findsOneWidget);
      expect(find.text('Customize'), findsOneWidget);

      // A narrow window on a big screen still offers the layout choice.
      await _pumpSettings(
        tester,
        size: const Size(1400, 900),
        wrap: (child) => Align(alignment: Alignment.topLeft, child: SizedBox(width: 340, child: child)),
      );
      await _open(tester, SettingsSectionId.appearance);
      expect(find.byKey(const ValueKey('layout-choice')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpSettings(tester, size: const Size(390, 844));
      await _open(tester, SettingsSectionId.appearance);
      expect(find.byKey(const ValueKey('layout-choice')), findsNothing);
      expect(find.text('Customize'), findsNothing);
    });

    testWidgets('Replay buttons play the chosen start-up animation', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.appearance);
      final before = h.app.bootReplay;
      await _tapText(tester, 'Replay first launch');
      expect(h.app.bootReplay, before + 1);
      expect(h.app.bootReplayKind, BootKind.first);
      await _tapText(tester, 'Replay later launch');
      expect(h.app.bootReplayKind, BootKind.short);
    });
  });

  group('updates', () {
    testWidgets('shows both versions, Check now and the footnote', (tester) async {
      await _pumpSettings(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _open(tester, SettingsSectionId.updates);
      expect(find.text('Archangel OS app'), findsOneWidget);
      expect(find.text('Version ${AppVersion.current}'), findsOneWidget);
      expect(find.text('Server program'), findsOneWidget);
      expect(find.text('Version 0.5.0'), findsOneWidget);
      expect(find.text('Check now'), findsOneWidget);
      expect(find.textContaining('rolls itself back if anything goes wrong'), findsOneWidget);
    });

    testWidgets('the Server program row is hidden when unpaired', (tester) async {
      await _pumpSettings(tester, paired: false);
      await _open(tester, SettingsSectionId.updates);
      expect(find.text('Archangel OS app'), findsOneWidget);
      expect(find.text('Server program'), findsNothing);
    });
  });

  group('danger zone', () {
    testWidgets('Restart server asks first, then confirms when it worked', (tester) async {
      final monitoring = _FakeMonitoring(const ProcessActionResult(success: true, message: 'ok'));
      await _pumpSettings(tester, monitoring: monitoring);
      await _open(tester, SettingsSectionId.danger);
      await _tapText(tester, 'Restart');
      expect(find.text('Restart your server?'), findsOneWidget);
      expect(find.textContaining('This app reconnects by itself.'), findsOneWidget);
      expect(monitoring.reboots, 0);
      await tester.tap(_inDialog('Restart'));
      await _settle(tester);
      expect(monitoring.reboots, 1);
      expect(find.text('Restarting. Your server will be back in about a minute.'), findsOneWidget);
    });

    testWidgets('Restart server says why when it failed', (tester) async {
      final monitoring = _FakeMonitoring(const ProcessActionResult(success: false, message: 'Admin mode is off'));
      await _pumpSettings(tester, monitoring: monitoring);
      await _open(tester, SettingsSectionId.danger);
      await _tapText(tester, 'Restart');
      await tester.tap(_inDialog('Restart'));
      await _settle(tester);
      expect(find.text("Couldn't restart: Admin mode is off"), findsOneWidget);
    });

    testWidgets('cancelling the restart does nothing', (tester) async {
      final monitoring = _FakeMonitoring(const ProcessActionResult(success: true, message: 'ok'));
      await _pumpSettings(tester, monitoring: monitoring);
      await _open(tester, SettingsSectionId.danger);
      await _tapText(tester, 'Restart');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(monitoring.reboots, 0);
    });

    testWidgets('Forget this server asks first and then forgets the active server', (tester) async {
      final h = await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.danger);
      await _tapText(tester, 'Forget');
      expect(find.text('Unpair from "Server a"?'), findsOneWidget);
      await tester.tap(_inDialog('Unpair'));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(h.registry.profiles.map((p) => p.id), ['b']);
    });

    testWidgets('has the three rows with their wording', (tester) async {
      await _pumpSettings(tester);
      await _open(tester, SettingsSectionId.danger);
      expect(find.text('Restart server'), findsOneWidget);
      expect(find.text('Forget this server'), findsOneWidget);
      expect(find.text('Remove Archangel from this server'), findsOneWidget);
    });
  });

  group('uninstall', () {
    testWidgets('uses the active profile\'s ports and SSH address, not 8443/51820', (tester) async {
      final registry = ServerRegistry();
      final backend = ArchangeldConnection(client: MockClient((_) async => _json({})));
      final wg = WireGuardController();
      final fake = _Fake();
      Map<String, String?>? connectedWith;
      final key = Directory.systemTemp.createTempSync('archangel_ssh_test');
      addTearDown(() => key.deleteSync(recursive: true));
      sshCredentialsDirectoryOverride = () async => key;
      addTearDown(() => sshCredentialsDirectoryOverride = null);

      await tester.runAsync(() async {
        await useTempKvStore();
        final p = await registry.add(_profile('a', appPort: 9443, wgPort: 51999, sshHost: '203.0.113.9'));
        await backend.pair(host: p.host, token: p.token);
      });
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerRegistry>.value(value: registry),
            ChangeNotifierProvider<WireGuardController>.value(value: wg),
            ChangeNotifierProvider<ArchangeldConnection>.value(value: backend),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.dark, AxAccent.green),
            home: Builder(
              builder:
                  (context) => Scaffold(
                    body: TextButton(
                      onPressed:
                          () => showUninstallDialog(
                            context,
                            connector: ({
                              required host,
                              required port,
                              required username,
                              required privateKeyPem,
                              required onUnknownHostKey,
                              passphrase,
                            }) async {
                              connectedWith = {'host': host, 'user': username};
                              return fake;
                            },
                          ),
                      child: const Text('open'),
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);

      // Typed confirmation gates the next step.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).onPressed, isNull);
      await tester.enterText(find.byType(TextField), 'UNINSTALL');
      await _settle(tester);
      await tester.tap(find.text('Continue'));
      await _settle(tester);

      // Let the (real file IO) saved-key lookup finish; fields are disabled meanwhile.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _settle(tester);

      // The form starts from the profile's SSH address and user.
      expect(find.widgetWithText(TextField, '203.0.113.9'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'deploy'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Private key'),
        '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----',
      );
      await tester.tap(find.text('Connect & uninstall'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await _settle(tester);

      expect(connectedWith, {'host': '203.0.113.9', 'user': 'deploy'});
      expect(fake.commands.any((c) => c.contains('uninstall.sh 9443 51999')), isTrue, reason: fake.commands.join('\n'));
      expect(fake.commands.any((c) => c.contains('8443 51820')), isFalse);
      // The finished uninstall forgets the server.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(registry.isEmpty, isTrue);
    });
  });
}
