import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:archangel/services/app_version.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/update_check_service.dart';

import 'test_utils.dart';

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
            {'name': 'version-manifest.json', 'browser_download_url': 'https://example.com/version-manifest.json'},
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
    setUp(() async {
      await useTempKvStore();
    });

    test('a new-style manifest populates version, build, tag and the release URL', () async {
      final svc = UpdateCheckService(
        client: _fakeGithub(manifest: {'version': '0.9.0', 'build': 3, 'tag': 'v0.9.0'}, tag: 'v0.9.0'),
      );

      await svc.checkForUpdates();

      expect(svc.latestVersion, '0.9.0');
      expect(svc.latestBuild, 3);
      expect(svc.releaseTag, 'v0.9.0');
      expect(svc.releaseUrl, contains('/releases/tag/v0.9.0'));
      expect(svc.lastChecked, isNotNull);
    });

    test('a legacy manifest still parses (app vs frontend, server vs backend, backend_tag)', () async {
      final svc = UpdateCheckService(
        client: _fakeGithub(
          manifest: {'archangel': '0.7.1', 'frontend': '0.9.0', 'backend': '0.6.0', 'frontend_tag': 'v0.9.0-f', 'backend_tag': 'v0.6.0-b'},
        ),
      );

      await svc.checkForUpdates();

      expect(svc.latestVersion, '0.7.1');
      expect(svc.latestBuild, isNull);
      expect(svc.releaseTag, 'v0.6.0-b');
      // App is compared with `frontend` (0.9.0 > 0.8.0), the server with `backend`.
      expect(svc.appBehind, isTrue);
      expect(svc.serverBehind('0.5.0'), isTrue);
      expect(svc.serverBehind('0.6.0'), isFalse);
    });

    test('manifest JSON: new keys win over legacy keys, and missing keys give nulls', () {
      final both = UpdateManifest.fromJson({
        'version': '0.8.0',
        'build': 2,
        'tag': 'v0.8.0',
        'archangel': '0.8.0',
        'frontend': '0.8.0',
        'backend': '0.8.0',
        'frontend_tag': 'v0.8.0',
        'backend_tag': 'v0.8.0',
      });
      expect((both.version, both.build, both.tag, both.appVersion, both.serverVersion), ('0.8.0', 2, 'v0.8.0', '0.8.0', '0.8.0'));
      final empty = UpdateManifest.fromJson({});
      expect((empty.version, empty.tag, empty.appVersion), (null, null, null));
    });

    test('"either behind": the app, the server, both or neither', () async {
      Future<UpdateCheckService> svcWith(String latest) async {
        final svc = UpdateCheckService(client: _fakeGithub(manifest: {'version': latest, 'build': 1, 'tag': 'v$latest'}));
        await svc.checkForUpdates();
        return svc;
      }

      final current = AppVersion.current; // 0.8.0 unless a dart-define overrides it
      final same = await svcWith(current);
      expect(same.updateAvailable(serverVersion: current), isFalse);
      expect(same.updateAvailable(serverVersion: null), isFalse); // unknown server never counts

      final serverOld = await svcWith(current);
      expect(serverOld.appBehind, isFalse);
      expect(serverOld.serverBehind('0.0.1'), isTrue);
      expect(serverOld.updateAvailable(serverVersion: '0.0.1'), isTrue);

      final appOld = await svcWith('99.0.0');
      expect(appOld.appBehind, isTrue);
      expect(appOld.serverBehind('99.0.0'), isFalse);
      expect(appOld.updateAvailable(serverVersion: '99.0.0'), isTrue);

      expect(appOld.updateAvailable(serverVersion: '0.0.1'), isTrue); // both
    });

    test('the cache survives a restart (new and old cache shapes)', () async {
      final svc = UpdateCheckService(client: _fakeGithub(manifest: {'version': '0.9.0', 'build': 3, 'tag': 'v0.9.0'}));
      await svc.checkForUpdates();

      final restarted = UpdateCheckService(client: MockClient((_) async => http.Response('', 500)));
      await restarted.loadCache();
      expect(restarted.latestVersion, '0.9.0');
      expect(restarted.releaseTag, 'v0.9.0');

      // A cache written by an older app (per-component keys) still loads.
      await LocalKvStore.instance.write(
        'update_check_cache',
        jsonEncode({'archangel': '0.7.1', 'frontend': '0.7.1', 'backend': '0.6.0', 'backendTag': 'v0.6.0-b'}),
      );
      final old = UpdateCheckService(client: MockClient((_) async => http.Response('', 500)));
      await old.loadCache();
      expect(old.latestVersion, '0.7.1');
      expect(old.releaseTag, 'v0.6.0-b');
      expect(old.serverBehind('0.5.0'), isTrue);
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
        return http.Response(jsonEncode({'archangel': manifestVersion, 'frontend': manifestVersion, 'backend': manifestVersion}), 200);
      });
      final svc = UpdateCheckService(client: client);

      await svc.checkForUpdates();
      expect(svc.latestVersion, '1.0.0');

      manifestVersion = '1.1.0';
      await svc.checkForUpdates(force: true);
      expect(svc.latestVersion, '1.1.0');
    });

    test('a failed fetch leaves previously known values intact', () async {
      final okClient = _fakeGithub(manifest: {'archangel': '2.0.0', 'frontend': '2.0.0', 'backend': '2.0.0'});
      final svc = UpdateCheckService(client: okClient);
      await svc.checkForUpdates();
      expect(svc.latestVersion, '2.0.0');

      // Swap in a client that always fails, force a re-check.
      final failingClient = MockClient((request) async => http.Response('boom', 500));
      final svc2 = UpdateCheckService(client: failingClient);
      // Simulate "previously known values" by loading what svc already
      // wrote to the shared fake secure storage cache.
      await svc2.loadCache();
      final beforeArchangel = svc2.latestVersion;

      await svc2.checkForUpdates(force: true);

      expect(svc2.latestVersion, beforeArchangel);
    });
  });
}
