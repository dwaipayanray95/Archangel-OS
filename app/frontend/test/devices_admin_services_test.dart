import 'dart:convert';

import 'package:archangel/services/admin_mode_service.dart';
import 'package:archangel/services/api_error.dart';
import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/devices_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

Future<ArchangeldConnection> _pairedConnection() async {
  await useTempKvStore();
  final c = ArchangeldConnection();
  await c.pair(host: '10.10.0.1:8443', token: 'tok');
  return c;
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('serverMessage', () {
    test('prefers the JSON message field', () {
      expect(serverMessage(_json({'success': false, 'message': 'Admin mode is off - this action needs it'}, 403), 'x'), 'Admin mode is off - this action needs it');
    });
    test('falls back to a short plain-text body, then to the fallback', () {
      expect(serverMessage(http.Response('Bad gateway', 502), 'x'), 'Bad gateway');
      expect(serverMessage(http.Response('<html>...</html>', 502), 'fallback'), 'fallback');
      expect(serverMessage(http.Response('', 500), 'fallback'), 'fallback');
      expect(serverMessage(_json({'success': false}, 500), 'fallback'), 'fallback');
    });
  });

  group('DevicesService', () {
    test('parses the device list and the current flag', () async {
      final conn = await _pairedConnection();
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/devices');
        expect(req.headers['X-Archangel-Token'], 'tok');
        return _json([
          {'name': 'macbook', 'created_at': '2026-08-14T10:00:00Z', 'tunnel_ip': '10.10.0.2', 'current': true},
          {'name': 'pixel', 'created_at': 'garbage'},
        ]);
      });
      final svc = DevicesService(client: client);
      svc.init(conn);
      await pumpEventQueue();

      expect(svc.loaded, isTrue);
      expect(svc.error, isNull);
      expect(svc.devices.map((d) => d.name), ['macbook', 'pixel']);
      expect(svc.devices[0].current, isTrue);
      expect(svc.devices[0].tunnelIp, '10.10.0.2');
      expect(svc.devices[0].createdAt, DateTime.utc(2026, 8, 14, 10));
      expect(svc.devices[1].current, isFalse);
      expect(svc.devices[1].createdAt, isNull);
      expect(svc.devices[1].tunnelIp, isNull);
    });

    test('surfaces the server message when listing fails', () async {
      final conn = await _pairedConnection();
      final svc = DevicesService(client: MockClient((_) async => _json({'success': false, 'message': 'failed to read paired devices'}, 500)));
      svc.init(conn);
      await pumpEventQueue();
      expect(svc.error, 'failed to read paired devices');
      expect(svc.loaded, isFalse);
    });

    test('reports an unreachable backend', () async {
      final conn = await _pairedConnection();
      final svc = DevicesService(client: MockClient((_) async => throw http.ClientException('no route')));
      svc.init(conn);
      await pumpEventQueue();
      expect(svc.error, contains('Could not reach the backend'));
    });

    test('revoke sends DELETE, adds self=true only when asked, and refreshes', () async {
      final conn = await _pairedConnection();
      final calls = <String>[];
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''}');
        if (req.method == 'DELETE') return _json({'success': true, 'message': 'revoked'});
        return _json(<Object>[]);
      });
      final svc = DevicesService(client: client);
      svc.init(conn);
      await pumpEventQueue();
      calls.clear();

      final r1 = await svc.revoke(const PairedDevice(name: 'pixel'));
      expect(r1.success, isTrue);
      expect(calls, ['DELETE /api/v1/devices/pixel', 'GET /api/v1/devices']);

      calls.clear();
      final r2 = await svc.revoke(const PairedDevice(name: 'macbook', current: true), self: true);
      expect(r2.success, isTrue);
      expect(calls, ['DELETE /api/v1/devices/macbook?self=true']);
    });

    test('revoke passes through 403 / 404 / 409 messages', () async {
      final conn = await _pairedConnection();
      var status = 403;
      var message = 'Admin mode is off - this action needs it';
      final svc = DevicesService(client: MockClient((req) async {
        if (req.method == 'DELETE') return _json({'success': false, 'message': message}, status);
        return _json(<Object>[]);
      }));
      svc.init(conn);
      await pumpEventQueue();

      var r = await svc.revoke(const PairedDevice(name: 'pixel'));
      expect(r.success, isFalse);
      expect(r.message, 'Admin mode is off - this action needs it');

      status = 409;
      message = 'This is the device you are using';
      r = await svc.revoke(const PairedDevice(name: 'pixel'));
      expect(r.message, 'This is the device you are using');

      status = 404;
      message = 'no such device';
      r = await svc.revoke(const PairedDevice(name: 'ghost'));
      expect(r.message, 'no such device');
    });

    test('a dropped connection counts as success only for self-revoke', () async {
      final conn = await _pairedConnection();
      final svc = DevicesService(client: MockClient((req) async {
        if (req.method == 'DELETE') throw http.ClientException('connection reset');
        return _json(<Object>[]);
      }));
      svc.init(conn);
      await pumpEventQueue();

      final self = await svc.revoke(const PairedDevice(name: 'macbook', current: true), self: true);
      expect(self.success, isTrue);

      final other = await svc.revoke(const PairedDevice(name: 'pixel'));
      expect(other.success, isFalse);
    });
  });

  group('AdminModeService', () {
    test('parses status', () async {
      final conn = await _pairedConnection();
      final svc = AdminModeService(client: MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/v1/system/admin-mode');
        return _json({'enabled': true, 'sudoers_path': '/etc/sudoers.d/archangel'});
      }));
      svc.init(conn);
      await pumpEventQueue();
      expect(svc.enabled, isTrue);
      expect(svc.sudoersPath, '/etc/sudoers.d/archangel');
      expect(svc.error, isNull);
    });

    test('a malformed status body is an error, not a guess', () async {
      final conn = await _pairedConnection();
      final svc = AdminModeService(client: MockClient((_) async => _json({'sudoers_path': 'x'})));
      svc.init(conn);
      await pumpEventQueue();
      expect(svc.enabled, isNull);
      expect(svc.error, isNotNull);
    });

    test('disable POSTs {"enabled": false} and applies the returned state', () async {
      final conn = await _pairedConnection();
      Map<String, dynamic>? posted;
      final svc = AdminModeService(client: MockClient((req) async {
        if (req.method == 'POST') {
          posted = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'enabled': false, 'sudoers_path': '/etc/sudoers.d/archangel'});
        }
        return _json({'enabled': true});
      }));
      svc.init(conn);
      await pumpEventQueue();

      final r = await svc.disable();
      expect(r.success, isTrue);
      expect(posted, {'enabled': false});
      expect(svc.enabled, isFalse);
    });

    test('disable surfaces the server message on failure and keeps the old state', () async {
      final conn = await _pairedConnection();
      final svc = AdminModeService(client: MockClient((req) async {
        if (req.method == 'POST') return _json({'success': false, 'message': 'could not update sudoers'}, 500);
        return _json({'enabled': true});
      }));
      svc.init(conn);
      await pumpEventQueue();

      final r = await svc.disable();
      expect(r.success, isFalse);
      expect(r.message, 'could not update sudoers');
      expect(svc.enabled, isTrue);
    });

    test('is a no-op when not paired', () async {
      await useTempKvStore();
      final svc = AdminModeService(client: MockClient((_) async => fail('must not call the network')));
      svc.init(ArchangeldConnection());
      await pumpEventQueue();
      expect(svc.enabled, isNull);
      final r = await svc.disable();
      expect(r.success, isFalse);
    });
  });
}
