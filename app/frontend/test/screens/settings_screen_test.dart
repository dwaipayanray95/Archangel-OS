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
import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/monitoring_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/ssh_credentials.dart';
import 'package:archangel/services/ssh_transport.dart';
import 'package:archangel/services/update_check_service.dart';
import 'package:archangel/services/wireguard_controller.dart';
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
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.dark,
  bool paired = true,
  bool twoServers = true,
  Future<http.Response> Function(http.Request req)? devicesHandler,
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
        ChangeNotifierProvider(create: (_) => MonitoringService()),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const titles = ['Servers', 'This server', 'Devices', 'Admin mode', 'Security', 'Appearance', 'Updates', 'Danger zone'];

  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets('all sections render without overflow at ${size.width.toInt()} (${brightness.name})', (tester) async {
        await _pumpSettings(tester, size: size, brightness: brightness);
        for (final t in titles) {
          expect(find.text(t, skipOffstage: false), findsWidgets, reason: t);
        }
        // Content that needed the paired backend.
        expect(find.text('laptop', skipOffstage: false), findsOneWidget);
        expect(find.text('This device', skipOffstage: false), findsOneWidget);
        expect(find.text('Admin mode is on', skipOffstage: false), findsOneWidget);
        expect(find.text('Add a server', skipOffstage: false), findsOneWidget);
        expect(find.text('Add a device', skipOffstage: false), findsOneWidget);
        expect(find.text('Active', skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unpaired: no devices or admin sections, still no overflow', (tester) async {
    await _pumpSettings(tester, paired: false);
    expect(find.text('Devices', skipOffstage: false), findsNothing);
    expect(find.text('Admin mode', skipOffstage: false), findsNothing);
    expect(find.text('Servers', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('servers', () {
    testWidgets('Remove explains it only forgets the server on this device and removes a non-active one', (tester) async {
      final h = await _pumpSettings(tester);
      final remove = find.descendant(of: find.byKey(const ValueKey('server-row-b')), matching: find.text('Remove'));
      await tester.ensureVisible(remove);
      await tester.pump();
      await tester.tap(remove);
      await _settle(tester);
      expect(find.textContaining('only forgets the server on this device'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Remove')));
      await _settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(h.registry.profiles.map((p) => p.id), ['a']);
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
      await _tapText(tester, 'Add a device');
      expect(find.text('Device name'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Maria phone');
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
      await _tapText(tester, 'Add a device');
      await tester.enterText(find.byType(TextField), 'tablet');
      await _tapText(tester, 'Create pairing code');
      expect(find.text('Admin mode is off - this action needs it'), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Create pairing code'), findsOneWidget);
    });

    testWidgets('an invalid name is explained without calling the server', (tester) async {
      final h = await _pumpSettings(tester);
      await _tapText(tester, 'Add a device');
      await tester.enterText(find.byType(TextField), '-bad');
      await _tapText(tester, 'Create pairing code');
      expect(find.textContaining('starting with a letter or number'), findsOneWidget);
      expect(h.devicesRequests.where((r) => r.method == 'POST'), isEmpty);
    });
  });

  group('appearance', () {
    testWidgets('picking a theme and accent updates AppState and persists', (tester) async {
      final h = await _pumpSettings(tester);
      await _tapText(tester, 'Light');
      expect(h.app.themeMode, ThemeMode.light);
      await _tapText(tester, 'System');
      expect(h.app.themeMode, ThemeMode.system);
      await _tapText(tester, 'Dark');
      await _tapText(tester, 'Light');
      await tester.tap(find.byKey(const ValueKey('accent-ice')));
      await _settle(tester);
      expect(h.app.accentChoice, AxAccent.ice);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      final reloaded = AppState();
      await tester.runAsync(reloaded.loadAppearance);
      expect(reloaded.themeMode, ThemeMode.light);
      expect(reloaded.accentChoice, AxAccent.ice);
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
