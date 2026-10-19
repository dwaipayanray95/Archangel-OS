import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:archangel/services/update_check_service.dart';

/// Same in-memory fake used by ssh_transport_test.dart - flutter_secure_storage's
/// platform channel has no implementation in a bare test environment.
void _fakeSecureStorage() {
  final store = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return store[call.arguments['key']];
      case 'write':
        store[call.arguments['key'] as String] = call.arguments['value'] as String;
        return null;
      case 'delete':
        store.remove(call.arguments['key']);
        return null;
      case 'containsKey':
        return store.containsKey(call.arguments['key']);
      default:
        return null;
    }
  });
}

http.Client _fakeGithub({required Map<String, dynamic> manifest, String tag = 'v0.4.0'}) {
  return MockClient((request) async {
    if (request.url.host == 'api.github.com') {
      return http.Response(
        jsonEncode({
          'html_url': 'https://github.com/dwaipayanray95/Archangel-OS/releases/tag/$tag',
          'assets': [
            {
              'name': 'version-manifest.json',
              'browser_download_url': 'https://example.com/version-manifest.json',
            },
          ],
        }),
        200,
      );
    }
    if (request.url.toString() == 'https://example.com/version-manifest.json') {
      return http.Response(jsonEncode(manifest), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _fakeSecureStorage();

  group('UpdateCheckService', () {
    test('a fresh fetch populates all three fields and the release URL', () async {
      final svc = UpdateCheckService(
        client: _fakeGithub(manifest: {'archangel': '0.4.0', 'frontend': '0.4.0', 'backend': '0.3.0'}),
      );

      await svc.checkForUpdates();

      expect(svc.latestArchangel, '0.4.0');
      expect(svc.latestFrontend, '0.4.0');
      expect(svc.latestBackend, '0.3.0');
      expect(svc.releaseUrl, contains('/releases/tag/v0.4.0'));
      expect(svc.lastChecked, isNotNull);
    });

    test('a within-cache-window check does not hit the network again', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'html_url': 'https://github.com/x/y/releases/tag/v1.0.0',
              'assets': [
                {'name': 'version-manifest.json', 'browser_download_url': 'https://example.com/m.json'},
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'archangel': '1.0.0', 'frontend': '1.0.0', 'backend': '1.0.0'}), 200);
      });
      final svc = UpdateCheckService(client: client);

      await svc.checkForUpdates();
      final callsAfterFirst = calls;
      await svc.checkForUpdates(); // should no-op, cache is fresh

      expect(calls, callsAfterFirst);
    });

    test('force: true bypasses the cache and re-fetches', () async {
      var manifestVersion = '1.0.0';
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'html_url': 'https://github.com/x/y/releases/tag/v$manifestVersion',
              'assets': [
                {'name': 'version-manifest.json', 'browser_download_url': 'https://example.com/m.json'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'archangel': manifestVersion, 'frontend': manifestVersion, 'backend': manifestVersion}),
          200,
        );
      });
      final svc = UpdateCheckService(client: client);

      await svc.checkForUpdates();
      expect(svc.latestArchangel, '1.0.0');

      manifestVersion = '1.1.0';
      await svc.checkForUpdates(force: true);
      expect(svc.latestArchangel, '1.1.0');
    });

    test('a failed fetch leaves previously known values intact', () async {
      final okClient = _fakeGithub(manifest: {'archangel': '2.0.0', 'frontend': '2.0.0', 'backend': '2.0.0'});
      final svc = UpdateCheckService(client: okClient);
      await svc.checkForUpdates();
      expect(svc.latestArchangel, '2.0.0');

      // Swap in a client that always fails, force a re-check.
      final failingClient = MockClient((request) async => http.Response('boom', 500));
      final svc2 = UpdateCheckService(client: failingClient);
      // Simulate "previously known values" by loading what svc already
      // wrote to the shared fake secure storage cache.
      await svc2.loadCache();
      final beforeArchangel = svc2.latestArchangel;

      await svc2.checkForUpdates(force: true);

      expect(svc2.latestArchangel, beforeArchangel);
    });
  });
}
