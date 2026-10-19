import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/containers_service.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:archangel/services/devops_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'package:archangel/ui/shell/connection_state.dart';
import 'package:archangel/ui/shell/status_strip.dart';
import 'package:archangel/ui/theme.dart';

import '../test_utils.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

ServerProfile _profile(String id, {String wg = ''}) => ServerProfile(
      id: id,
      name: 'Server $id',
      host: '10.0.0.${id.codeUnitAt(0) - 96}:8443',
      token: 'tok-$id',
      wgConfig: wg,
      createdAt: DateTime.utc(2025),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('deriveConnectionPhase', () {
    ConnectionPhase d(TunnelStatus t, {bool paired = true, bool? reachable, int failures = 0}) =>
        deriveConnectionPhase(paired: paired, tunnel: t, reachable: reachable, healthFailures: failures);

    test('not paired wins over everything', () {
      expect(d(TunnelStatus.connected, paired: false, reachable: true), ConnectionPhase.notPaired);
    });

    test('a healthy server is connected even when our own tunnel says down', () {
      expect(d(TunnelStatus.disconnected, reachable: true), ConnectionPhase.connected);
      expect(d(TunnelStatus.unsupported, reachable: true), ConnectionPhase.connected);
      expect(d(TunnelStatus.error, reachable: true), ConnectionPhase.connected);
      expect(d(TunnelStatus.connected, reachable: true), ConnectionPhase.connected);
    });

    test('the tunnel being up is not enough to claim a connection', () {
      expect(d(TunnelStatus.connected), ConnectionPhase.reaching);
      expect(d(TunnelStatus.connected, reachable: false, failures: 1), ConnectionPhase.reaching);
    });

    test('keeps failing while the tunnel is up -> server not responding', () {
      expect(d(TunnelStatus.connected, reachable: false, failures: kHealthFailuresBeforeNotResponding),
          ConnectionPhase.serverNotResponding);
    });

    test('tunnel coming up or going down is starting', () {
      expect(d(TunnelStatus.connecting), ConnectionPhase.starting);
      expect(d(TunnelStatus.disconnecting, reachable: false, failures: 3), ConnectionPhase.starting);
    });

    test('before the first check there is no verdict yet; after a failed one it is offline', () {
      expect(d(TunnelStatus.disconnected), ConnectionPhase.starting);
      expect(d(TunnelStatus.disconnected, reachable: false, failures: 1), ConnectionPhase.offline);
      expect(d(TunnelStatus.error, reachable: false, failures: 1), ConnectionPhase.offline);
    });
  });

  group('connectionText', () {
    test('words for every phase', () {
      expect(connectionText(ConnectionPhase.starting), 'Starting secure connection…');
      expect(connectionText(ConnectionPhase.reaching), 'Secure connection up — reaching your server…');
      expect(connectionText(ConnectionPhase.connected, serverName: 'Home'), 'Connected to Home');
      expect(connectionText(ConnectionPhase.connected), 'Connected');
      expect(connectionText(ConnectionPhase.serverNotResponding), "Secure connection is up but your server isn't answering");
      expect(connectionText(ConnectionPhase.offline), 'Not connected');
      expect(connectionText(ConnectionPhase.notPaired), 'No server yet');
    });

    test('only starting and reaching show a spinner', () {
      for (final p in ConnectionPhase.values) {
        expect(connectionIsTransitional(p), p == ConnectionPhase.starting || p == ConnectionPhase.reaching, reason: '$p');
      }
    });
  });

  group('status strip', () {
    Future<WireGuardController> pumpStrip(WidgetTester tester, http.Client client) async {
      final registry = ServerRegistry();
      final backend = ArchangeldConnection(client: client);
      final wg = WireGuardController();
      await tester.runAsync(() async {
        await useTempKvStore();
        await registry.add(_profile('a'));
        await backend.pair(host: '10.0.0.1:8443', token: 'tok-a');
      });
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState()),
          ChangeNotifierProvider<ServerRegistry>.value(value: registry),
          ChangeNotifierProvider<WireGuardController>.value(value: wg),
          ChangeNotifierProvider<ArchangeldConnection>.value(value: backend),
          ChangeNotifierProvider(create: (_) => ContainersService()),
          ChangeNotifierProvider(create: (_) => DevopsService()),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AxAccent.green),
          home: const Scaffold(body: StatusStrip()),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return wg;
    }

    testWidgets('says "Connected to <server>" once health answers, with the tunnel off in this app', (tester) async {
      await pumpStrip(tester, MockClient((req) async {
        expect(req.url.path, '/api/v1/health');
        expect(req.headers.containsKey('X-Archangel-Token'), isFalse); // unauthenticated
        return _json({'status': 'ok', 'version': '0.5.0'});
      }));
      expect(find.text('Connected to Server a'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.text('Secure connection on'), findsNothing);
    });

    testWidgets('says "Not connected" when nothing answers - never "Secure connection on"', (tester) async {
      await pumpStrip(tester, MockClient((_) async => throw http.ClientException('no route')));
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Server a'), findsOneWidget); // name shown beneath
      expect(find.text('Secure connection on'), findsNothing);
    });

    testWidgets('starting shows a spinner and the starting words before the first answer', (tester) async {
      await pumpStrip(tester, MockClient((_) => Future<http.Response>.delayed(const Duration(seconds: 5), () => _json({}))));
      expect(find.text('Starting secure connection…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Dispose the strip (stops its timer), then let the pending request drain.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('ArchangeldConnection.checkReachable', () {
    setUp(() async => useTempKvStore());

    test('records success and failures, and resets when re-paired', () async {
      var ok = true;
      final c = ArchangeldConnection(client: MockClient((_) async {
        if (!ok) throw http.ClientException('down');
        return _json({'version': '1.2.3'});
      }));
      await c.pair(host: '10.0.0.1:8443', token: 't');
      await pumpEventQueue();
      expect(c.reachable, isNull); // the version fetch from pair() is separate
      await c.checkReachable();
      expect(c.reachable, isTrue);
      expect(c.healthFailures, 0);

      // A server that was answering survives a couple of missed checks
      // (slow reply, Wi-Fi blip) and is only treated as gone after
      // kReachabilityGraceFailures failures in a row.
      ok = false;
      await c.checkReachable();
      await c.checkReachable();
      expect(c.reachable, isTrue);
      expect(c.healthFailures, 2);
      await c.checkReachable();
      expect(c.reachable, isFalse);
      expect(c.healthFailures, kReachabilityGraceFailures);

      // One success restores it immediately.
      ok = true;
      await c.checkReachable();
      expect(c.reachable, isTrue);
      expect(c.healthFailures, 0);

      await c.pair(host: '10.0.0.2:8443', token: 't');
      expect(c.reachable, isNull);
      expect(c.healthFailures, 0);
    });

    test('a non-200 answer counts as not reachable; unpaired does nothing', () async {
      final c = ArchangeldConnection(client: MockClient((_) async => http.Response('nope', 502)));
      await c.checkReachable();
      expect(c.reachable, isNull);
      await c.pair(host: '10.0.0.1:8443', token: 't');
      await c.checkReachable();
      expect(c.reachable, isFalse);
    });
  });

  group('DevicesService.create', () {
    Future<DevicesService> svc(http.Client client) async {
      await useTempKvStore();
      final conn = ArchangeldConnection();
      await conn.pair(host: '10.10.0.1:8443', token: 'tok');
      final s = DevicesService(client: client);
      s.init(conn);
      await pumpEventQueue();
      return s;
    }

    test('POSTs the name and returns the one-time bundle', () async {
      http.Request? post;
      final s = await svc(MockClient((req) async {
        if (req.method == 'POST') {
          post = req;
          return _json({'success': true, 'name': 'Maria phone', 'bundle': 'QUJD'});
        }
        return _json([]);
      }));
      final r = await s.create('  Maria phone ');
      expect(r.success, isTrue);
      expect(r.bundle, 'QUJD');
      expect(post!.url.path, '/api/v1/devices');
      expect(post!.headers['X-Archangel-Token'], 'tok');
      expect(jsonDecode(post!.body), {'name': 'Maria phone'});
    });

    test('403 and 409 messages come from the server', () async {
      final s403 = await svc(MockClient((req) async => req.method == 'POST'
          ? _json({'success': false, 'message': 'Admin mode is off - this action needs it'}, 403)
          : _json([])));
      expect((await s403.create('x')).message, 'Admin mode is off - this action needs it');

      final s409 = await svc(MockClient((req) async => req.method == 'POST' ? _json({'success': false}, 409) : _json([])));
      final r = await s409.create('pixel');
      expect(r.success, isFalse);
      expect(r.message, contains('already exists'));
    });

    test('invalid names are rejected before any request', () async {
      var posts = 0;
      final s = await svc(MockClient((req) async {
        if (req.method == 'POST') posts++;
        return _json([]);
      }));
      for (final bad in ['', '   ', '-dash', 'a' * 33, 'semi;colon']) {
        expect((await s.create(bad)).success, isFalse, reason: bad);
      }
      expect(posts, 0);
      expect(DevicesService.isValidDeviceName('Maria.phone_2-x'), isTrue);
    });
  });

  group('switchToServer rollback', () {
    setUp(() async => useTempKvStore());

    test('a failing activation restores the previous server and rethrows', () async {
      final registry = ServerRegistry();
      await registry.load();
      final backend = ArchangeldConnection(client: MockClient((_) async => _json({})));
      final wg = WireGuardController();
      final a = await registry.add(_profile('a'));
      await registry.add(_profile('b', wg: 'this is not a wg-quick config'), activate: false);
      await activateProfile(a, wg: wg, backend: backend);
      expect(backend.host, a.host);
      expect(registry.activeId, a.id);

      await expectLater(
        switchToServer(registry.profiles.last.id, registry: registry, wg: wg, backend: backend),
        throwsA(isA<FormatException>()),
      );
      expect(registry.activeId, a.id);
      expect(backend.host, a.host);
      expect(backend.token, a.token);
    });

    test('a successful switch still ends on the new server', () async {
      final registry = ServerRegistry();
      await registry.load();
      final backend = ArchangeldConnection(client: MockClient((_) async => _json({})));
      final wg = WireGuardController();
      final a = await registry.add(_profile('a'));
      final b = await registry.add(_profile('b'), activate: false);
      await activateProfile(a, wg: wg, backend: backend);
      await switchToServer(b.id, registry: registry, wg: wg, backend: backend);
      expect(registry.activeId, b.id);
      expect(backend.host, b.host);
    });
  });
}
