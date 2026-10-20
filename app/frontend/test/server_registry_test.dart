import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/pairing_bundle.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/services/wireguard_controller.dart';
import 'test_utils.dart';

class _FailingStore extends LocalKvStore {
  _FailingStore({this.failReads = false}) : super.forTesting();
  final bool failReads;
  @override
  Future<void> write(String key, String value) async => throw StateError('disk full');
  @override
  Future<String?> read(String key) async => failReads ? throw StateError('unreadable') : null;
}

class _CountingWg extends WireGuardController {
  int connects = 0;
  @override
  Future<void> connect() async => connects++;
}

/// Fails the first pair() only.
class _OnceFailing extends ArchangeldConnection {
  _OnceFailing(this.inner);
  final ArchangeldConnection inner;
  bool _failed = false;
  @override
  Future<void> pair({required String host, required String token}) async {
    if (!_failed) {
      _failed = true;
      throw StateError('boom');
    }
    return inner.pair(host: host, token: token);
  }

  @override
  String? get token => inner.token;
}

ServerProfile _keyed(String id, String host, String key) => ServerProfile(
  id: id,
  name: 'Server $id',
  host: host,
  token: 'tok-$id',
  wgConfig: '[Interface]\nPrivateKey = k$id\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = $key\nEndpoint = 1.2.3.4:51820\n',
  createdAt: DateTime.utc(2025, 1, 1),
);

ServerProfile _profile(String id, String host, {String? name}) => ServerProfile(
  id: id,
  name: name ?? 'Server $id',
  host: host,
  token: 'tok-$id',
  wgConfig: '[Interface]\nPrivateKey = k$id\nAddress = 10.0.0.2/32\n',
  createdAt: DateTime.utc(2025, 1, 1),
);

String _bundleCode({String name = 'laptop', String host = '10.8.0.1:8443', String token = 'tok', String pub = 'pub'}) => base64.encode(
  utf8.encode(
    jsonEncode({
      'v': 1,
      'name': name,
      'host': host,
      'token': token,
      'wg': {
        'private_key': 'priv',
        'address': '10.8.0.2/32',
        'server_public_key': pub,
        'endpoint': '203.0.113.5:51820',
        'allowed_ips': ['10.8.0.0/24'],
      },
    }),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await useTempKvStore();
  });

  Future<ServerRegistry> reloaded() async {
    LocalKvStore.instance.resetForTesting(); // force a re-read from disk
    final r = ServerRegistry();
    await r.load();
    return r;
  }

  test('empty registry has no active server', () async {
    final r = ServerRegistry();
    await r.load();
    expect(r.isLoaded, isTrue);
    expect(r.isEmpty, isTrue);
    expect(r.active, isNull);
    expect(r.activeId, isNull);
  });

  test('profiles and the active id survive a restart', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', '10.0.0.1:8443'));
    await r.add(_profile('b', '10.0.0.2:8443').copyWith(sshHost: '203.0.113.9', sshUser: 'root', appPort: 9000, wgPort: 51821));
    await r.setActive('a');

    final r2 = await reloaded();
    expect(r2.profiles.map((p) => p.id), ['a', 'b']);
    expect(r2.activeId, 'a');
    final b = r2.byId('b')!;
    expect(b.sshHost, '203.0.113.9');
    expect(b.sshUser, 'root');
    expect(b.appPort, 9000);
    expect(b.wgPort, 51821);
    expect(b.token, 'tok-b');
    expect(b.wgConfig, contains('PrivateKey = kb'));
    expect(b, _profile('b', '10.0.0.2:8443').copyWith(sshHost: '203.0.113.9', sshUser: 'root', appPort: 9000, wgPort: 51821));
  });

  test('adding makes the new server active; activate:false keeps the current one', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    expect(r.activeId, 'a');
    await r.add(_profile('b', 'h2'));
    expect(r.activeId, 'b');
    await r.add(_profile('c', 'h3'), activate: false);
    expect(r.activeId, 'b');
  });

  test('adding a server with an existing host updates it instead of duplicating', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1', name: 'Home'));
    await r.add(_profile('zzz', 'h1', name: 'ignored').copyWith(token: 'new-token'));
    expect(r.profiles, hasLength(1));
    expect(r.active!.id, 'a');
    expect(r.active!.name, 'Home');
    expect(r.active!.token, 'new-token');
  });

  test('rename persists and ignores blank names', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    await r.rename('a', '  Office  ');
    await r.rename('a', '   ');
    expect((await reloaded()).byId('a')!.name, 'Office');
  });

  test('removing the active server makes the next one active', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    await r.add(_profile('b', 'h2'));
    await r.add(_profile('c', 'h3'));
    await r.setActive('b');

    await r.remove('b');
    expect(r.profiles.map((p) => p.id), ['a', 'c']);
    expect(r.activeId, 'c'); // the one that took its place

    await r.remove('c'); // last in the list -> falls back to the new last
    expect(r.activeId, 'a');

    final r2 = await reloaded();
    expect(r2.activeId, 'a');
  });

  test('removing a non-active server keeps the active one', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    await r.add(_profile('b', 'h2'));
    await r.remove('a');
    expect(r.activeId, 'b');
  });

  test('removing the last server leaves no active server, also after restart', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    await r.remove('a');
    expect(r.isEmpty, isTrue);
    expect(r.active, isNull);
    final r2 = await reloaded();
    expect(r2.isEmpty, isTrue);
    expect(r2.active, isNull);
  });

  test('a dangling active id falls back to the first profile', () async {
    final r = ServerRegistry();
    await r.load();
    await r.add(_profile('a', 'h1'));
    await r.add(_profile('b', 'h2'));
    await LocalKvStore.instance.write('server_active_id', 'gone');
    final r2 = await reloaded();
    expect(r2.activeId, 'a');
  });

  group('migration of the legacy single pairing', () {
    test('becomes the first profile named "My server"', () async {
      final kv = LocalKvStore.instance;
      await kv.write(kArchangeldHostKey, '10.8.0.1:8443');
      await kv.write(kArchangeldTokenKey, 'legacy-token');
      await kv.write(kWgConfigStorageKey, '[Interface]\nPrivateKey = x\n');

      final r = await reloaded();
      expect(r.profiles, hasLength(1));
      final p = r.active!;
      expect(p.name, kDefaultServerName);
      expect(p.host, '10.8.0.1:8443');
      expect(p.token, 'legacy-token');
      expect(p.wgConfig, contains('PrivateKey = x'));
      expect(p.appPort, 8443);
      expect(p.wgPort, 51820);

      // Migration happens once: a second launch loads the stored list.
      final again = await reloaded();
      expect(again.profiles.single.id, p.id);
    });

    test('is not repeated after the user removed every server', () async {
      final kv = LocalKvStore.instance;
      await kv.write(kArchangeldHostKey, 'h');
      await kv.write(kArchangeldTokenKey, 't');
      final r = await reloaded();
      await r.remove(r.active!.id);
      // The caller (removeActiveServer) clears the legacy keys; simulate it.
      await kv.delete(kArchangeldHostKey);
      await kv.delete(kArchangeldTokenKey);
      expect((await reloaded()).isEmpty, isTrue);
    });

    test('no legacy keys and no list means an empty registry', () async {
      expect((await reloaded()).isEmpty, isTrue);
    });

    test('a half-finished legacy pairing (no token) is not migrated', () async {
      await LocalKvStore.instance.write(kArchangeldHostKey, 'h');
      expect((await reloaded()).isEmpty, isTrue);
    });
  });

  group('server identity', () {
    test('serverKey is read from the [Peer] section only', () {
      expect(_keyed('a', 'h', 'KEY=').serverKey, 'KEY=');
      expect(_profile('a', 'h').serverKey, isNull);
    });

    test('two servers with the same host but different keys both persist', () async {
      final r = ServerRegistry();
      await r.load();
      await r.add(_keyed('a', '10.10.0.1:8443', 'keyA'));
      await r.add(_keyed('b', '10.10.0.1:8443', 'keyB'));
      final r2 = await reloaded();
      expect(r2.profiles.map((p) => p.id), ['a', 'b']);
    });

    test('re-pairing the same key replaces credentials', () async {
      final r = ServerRegistry();
      await r.load();
      await r.add(_keyed('a', '10.10.0.1:8443', 'keyA'));
      await r.add(_keyed('b', '10.10.0.1:8443', 'keyB'));
      final again = await r.add(_keyed('c', '10.10.0.1:8443', 'keyA').copyWith(token: 'fresh'));
      expect(r.profiles, hasLength(2));
      expect(again.id, 'a');
      expect(r.byId('a')!.token, 'fresh');
      expect(r.activeId, 'a');
    });

    test('a corrupt single entry is skipped, the rest load', () async {
      final r = ServerRegistry();
      await r.load();
      await r.add(_profile('a', 'h1'));
      await r.add(_profile('b', 'h2'));
      final list = jsonDecode((await LocalKvStore.instance.read('server_profiles_v1'))!) as List;
      list.insert(1, {'id': 'bad'});
      list.insert(0, 'nonsense');
      await LocalKvStore.instance.write('server_profiles_v1', jsonEncode(list));
      final r2 = await reloaded();
      expect(r2.profiles.map((p) => p.id), ['a', 'b']);
    });

    test('load completes when persisting fails', () async {
      final r = ServerRegistry(store: _FailingStore());
      await r.load();
      expect(r.isLoaded, isTrue);
      final c = ArchangeldConnection(store: _FailingStore(failReads: true));
      await c.load();
      expect(c.isLoaded, isTrue);
      expect(c.isPaired, isFalse);
    });
  });

  group('pairing and switching', () {
    test('pairNewServer adds a profile named from the bundle and points the app at it', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      final bundle = PairingBundle.parse(_bundleCode(name: 'phone'));

      final p = await pairNewServer(registry: r, wg: wg, backend: backend, bundle: bundle, sshHost: '203.0.113.5');

      expect(p.name, 'phone');
      expect(p.sshHost, '203.0.113.5');
      expect(r.activeId, p.id);
      expect(backend.host, '10.8.0.1:8443');
      expect(backend.token, 'tok');
      expect(wg.isPaired, isTrue);
      // Mirrored into the legacy keys so a plain relaunch still loads it.
      expect(await LocalKvStore.instance.read(kArchangeldHostKey), '10.8.0.1:8443');
    });

    test('switchToServer re-points the connection and the tunnel config', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      final a = await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(host: '10.8.0.1:8443', token: 'ta', pub: 'pubA')),
      );
      await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(host: '10.9.0.1:8443', token: 'tb', pub: 'pubB')),
      );
      expect(backend.token, 'tb');

      await switchToServer(a.id, registry: r, wg: wg, backend: backend);
      expect(r.activeId, a.id);
      expect(backend.host, '10.8.0.1:8443');
      expect(backend.token, 'ta');
    });

    test('removeActiveServer activates the next server, then clears everything when none are left', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      final a = await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(host: '10.8.0.1:8443', token: 'ta', pub: 'pubA')),
      );
      await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(host: '10.9.0.1:8443', token: 'tb', pub: 'pubB')),
      );

      await removeActiveServer(registry: r, wg: wg, backend: backend);
      expect(r.activeId, a.id);
      expect(backend.token, 'ta');

      await removeActiveServer(registry: r, wg: wg, backend: backend);
      expect(r.isEmpty, isTrue);
      expect(backend.isPaired, isFalse);
      expect(wg.isPaired, isFalse);
      expect(await LocalKvStore.instance.read(kArchangeldHostKey), isNull);
    });

    test('switching between same-host servers bumps the pairing generation', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      final a = await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(token: 'ta', pub: 'pubA')),
      );
      await pairNewServer(registry: r, wg: wg, backend: backend, bundle: PairingBundle.parse(_bundleCode(token: 'tb', pub: 'pubB')));
      expect(r.profiles, hasLength(2));
      final gen = backend.pairingGeneration;
      await switchToServer(a.id, registry: r, wg: wg, backend: backend);
      expect(backend.pairingGeneration, greaterThan(gen));
      expect(backend.token, 'ta');
    });

    test('activating a profile without a tunnel config unpairs the old tunnel', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      await pairNewServer(registry: r, wg: wg, backend: backend, bundle: PairingBundle.parse(_bundleCode(pub: 'pubA')));
      expect(wg.isPaired, isTrue);
      await activateProfile(_profile('x', 'h9:1').copyWith(wgConfig: ''), wg: wg, backend: backend);
      expect(wg.isPaired, isFalse);
      expect(backend.host, 'h9:1');
    });

    test('pairNewServer rolls back when activation fails', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = WireGuardController();
      final backend = ArchangeldConnection();
      final a = await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(token: 'ta', pub: 'pubA')),
      );
      // fail only the first pair() call (the new server), allow the restore
      final failing = _OnceFailing(backend);
      await expectLater(
        pairNewServer(registry: r, wg: wg, backend: failing, bundle: PairingBundle.parse(_bundleCode(token: 'tb', pub: 'pubB'))),
        throwsStateError,
      );
      expect(r.profiles.map((p) => p.id), [a.id]);
      expect(r.activeId, a.id);
      expect(backend.token, 'ta');
    });

    test('the tunnel is not connected on switch when it was down', () async {
      final r = ServerRegistry();
      await r.load();
      final wg = _CountingWg();
      final backend = ArchangeldConnection();
      final a = await pairNewServer(
        registry: r,
        wg: wg,
        backend: backend,
        bundle: PairingBundle.parse(_bundleCode(token: 'ta', pub: 'pubA')),
      );
      await pairNewServer(registry: r, wg: wg, backend: backend, bundle: PairingBundle.parse(_bundleCode(token: 'tb', pub: 'pubB')));
      await switchToServer(a.id, registry: r, wg: wg, backend: backend);
      expect(wg.connects, 0);
    });
  });
}
