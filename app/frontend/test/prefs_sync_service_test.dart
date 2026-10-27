import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/data/app_state.dart';
import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/prefs_sync_service.dart';
import 'package:archangel/ui/theme.dart';

import 'prefs_sync_fakes.dart';
import 'test_utils.dart';

const _registry = <String, PrefSpec>{...kPrefRegistry, 'old_key': PrefSpec(PrefScope.cloud)};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final services = <PrefsSyncService>[];
  tearDown(() {
    for (final s in services) {
      s.dispose();
    }
    services.clear();
  });

  /// A device: its own store, its own id, talking to [server].
  Future<(PrefsSyncService, MemoryKvStore)> device(
    FakePrefsServer server, {
    String id = 'mac-1',
    MemoryKvStore? store,
    String? serverKey = 'srv',
    Duration? debounce,
    Duration? poll,
  }) async {
    final kv = store ?? MemoryKvStore({kPrefsDeviceIdKey: id});
    final svc = PrefsSyncService(
      transport: server.transport(),
      store: kv,
      registry: _registry,
      debounce: debounce,
      pollInterval: poll,
      now: () => DateTime.utc(2026, 10, 27, 13),
    );
    services.add(svc);
    await svc.bind(serverKey);
    return (svc, kv);
  }

  group('conflicts', () {
    test('two devices change different keys offline and both survive', () async {
      final server = FakePrefsServer();
      final (mac, macKv) = await device(server);
      final (phone, phoneKv) = await device(server, id: 'phone-1');
      server.unreachable = true;
      await mac.setLocal(kPrefAccent, 'ember');
      await phone.setLocal(kPrefThemeMode, 'dark');
      await mac.syncNow();
      expect(mac.status, PrefsSyncStatus.offline);
      server.unreachable = false;

      await mac.syncNow();
      await phone.syncNow();
      await mac.syncNow();

      for (final kv in [macKv, phoneKv]) {
        expect(kv.data[kPrefAccent], 'ember');
        expect(kv.data[kPrefThemeMode], 'dark');
      }
      expect(server.valueOf(kPrefAccent), 'ember');
      expect(server.valueOf(kPrefThemeMode), 'dark');
    });

    test('same key on both sides: the newer server timestamp wins and the other adopts it', () async {
      final server = FakePrefsServer();
      final (mac, macKv) = await device(server);
      final (phone, _) = await device(server, id: 'phone-1');
      await mac.syncNow();
      await phone.syncNow();
      server.unreachable = true;
      await mac.setLocal(kPrefAccent, 'ember');
      await phone.setLocal(kPrefAccent, 'ice');
      server.unreachable = false;

      final changes = <Map<String, String?>>[];
      mac.applier = changes.add;
      final heard = <List<String>>[];
      mac.adopted.listen(heard.add);

      await mac.syncNow(); // reaches the server first
      await phone.syncNow(); // later, so the server stamps it newer
      expect(server.valueOf(kPrefAccent), 'ice');

      await mac.syncNow();
      expect(macKv.data[kPrefAccent], 'ice');
      expect(changes, [
        {kPrefAccent: 'ice'},
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(heard, [
        [kPrefAccent],
      ]);
      expect(mac.lastAdopted, [kPrefAccent]);
    });

    test('a tie on the server clock breaks on the device id and the loser adopts the winner in the same round trip', () async {
      final fixed = DateTime.utc(2026, 10, 27, 12);
      final server = FakePrefsServer(clock: () => fixed);
      final (mac, macKv) = await device(server);
      final (phone, _) = await device(server, id: 'phone-1');
      await mac.syncNow();
      await phone.syncNow();
      server.unreachable = true;
      await phone.setLocal(kPrefAccent, 'ice');
      await mac.setLocal(kPrefAccent, 'ember');
      server.unreachable = false;

      await phone.syncNow();
      expect(server.valueOf(kPrefAccent), 'ice');
      final applied = <Map<String, String?>>[];
      mac.applier = applied.add;
      await mac.syncNow(); // "mac-1" < "phone-1": mac loses
      expect(server.valueOf(kPrefAccent), 'ice');
      expect(macKv.data[kPrefAccent], 'ice');
      expect(mac.pendingCount, 0);
      expect(applied, isNotEmpty);
    });
  });

  test('a key deleted on one device stays deleted after the other syncs', () async {
    final server = FakePrefsServer();
    final (mac, macKv) = await device(server);
    final (phone, phoneKv) = await device(server, id: 'phone-1');
    await mac.setLocal('old_key', 'x');
    await mac.syncNow();
    await phone.syncNow();
    expect(phoneKv.data['old_key'], 'x');

    await mac.deleteLocal('old_key');
    await mac.syncNow();
    expect(server.isDeleted('old_key'), isTrue);

    final applied = <Map<String, String?>>[];
    phone.applier = applied.add;
    await phone.syncNow();
    expect(phoneKv.data.containsKey('old_key'), isFalse);
    expect(applied, [
      {'old_key': null},
    ]);
    await phone.syncNow();
    await mac.syncNow();
    expect(phoneKv.data.containsKey('old_key'), isFalse);
    expect(macKv.data.containsKey('old_key'), isFalse);
    expect(server.valueOf('old_key'), isNull);

    // A device that never had it does not get it back either.
    final (late, lateKv) = await device(server, id: 'tablet-1');
    await late.syncNow();
    expect(lateKv.data.containsKey('old_key'), isFalse);
  });

  group('defaults and explicit', () {
    test('a device that never touched a key takes the server value and does not push its default', () async {
      final server = FakePrefsServer()..seed(kPrefAccent, 'ember');
      final (fresh, kv) = await device(server);
      final applied = <Map<String, String?>>[];
      fresh.applier = applied.add;
      await fresh.syncNow();
      expect(kv.data[kPrefAccent], 'ember');
      expect(applied, [
        {kPrefAccent: 'ember'},
      ]);
      expect(server.patchBodies, isEmpty);
      expect(fresh.status, PrefsSyncStatus.synced);
    });

    test('a value set deliberately to the default is explicit, so it does win', () async {
      final server = FakePrefsServer()..seed(kPrefAccent, 'ember');
      final (svc, kv) = await device(server);
      await svc.setLocal(kPrefAccent, 'halo'); // the default value, chosen on purpose
      expect(jsonDecode(kv.data[kPrefsExplicitKey]!), contains(kPrefAccent));
      await svc.syncNow();
      expect(server.valueOf(kPrefAccent), 'halo');
      expect(kv.data[kPrefAccent], 'halo');
    });

    test('server empty and local customised: local is pushed on the first sync', () async {
      final server = FakePrefsServer();
      final (svc, _) = await device(server, serverKey: null);
      await svc.setLocal(kPrefThemeMode, 'light'); // before any server is bound
      await svc.bind('srv');
      await svc.syncNow();
      expect(server.valueOf(kPrefThemeMode), 'light');
    });

    test('values stored before sync existed count as set by the person', () async {
      final server = FakePrefsServer();
      final kv = MemoryKvStore({kPrefAccent: 'amber'});
      final (svc, _) = await device(server, store: kv);
      await svc.syncNow();
      expect(server.valueOf(kPrefAccent), 'amber');
    });
  });

  group('when the server cannot sync', () {
    test('404 means local-only: nothing throws, the status says so, writes still work', () async {
      final server = FakePrefsServer()..supported = false;
      final (svc, kv) = await device(server);
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.unsupported);
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.flush();
      expect(kv.data[kPrefAccent], 'ice');
      expect(svc.status, PrefsSyncStatus.unsupported);
      expect(server.patchBodies, isEmpty);
    });

    test('the unsupported state is remembered, and a later server that supports it receives the queue', () async {
      final server = FakePrefsServer()..supported = false;
      final (svc, kv) = await device(server);
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.syncNow();
      final (again, _) = await device(server, store: kv);
      expect(again.status, PrefsSyncStatus.unsupported);

      server.supported = true;
      await again.syncNow();
      expect(again.status, PrefsSyncStatus.synced);
      expect(server.valueOf(kPrefAccent), 'ice');
    });

    test('unreachable, server errors and garbage replies are all just offline', () async {
      final server = FakePrefsServer();
      final (svc, kv) = await device(server);
      await svc.setLocal(kPrefAccent, 'ice');

      server.unreachable = true;
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.offline);

      server.unreachable = false;
      server.forceStatus = 500;
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.offline);

      server.forceStatus = 413;
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.offline);

      server.forceStatus = null;
      server.garbage = 'not a document';
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.offline);

      expect(kv.data[kPrefAccent], 'ice');
      expect(svc.pendingCount, 1);
      server.garbage = null;
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.synced);
      expect(svc.pendingCount, 0);
    });

    test('with no server bound everything stays local', () async {
      final server = FakePrefsServer();
      final (svc, kv) = await device(server, serverKey: null);
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.syncNow();
      expect(svc.status, PrefsSyncStatus.unpaired);
      expect(kv.data[kPrefAccent], 'ice');
      expect(server.patchBodies, isEmpty);
      expect(server.getSinces, isEmpty);
    });
  });

  group('offline queue', () {
    test('writes queue offline, survive a restart and push on reconnect', () async {
      final server = FakePrefsServer();
      final (first, kv) = await device(server);
      server.unreachable = true;
      await first.setLocal(kPrefAccent, 'ice');
      await first.setLocal(kPrefStartupSound, 'false');
      await first.flush();
      expect(first.pendingCount, 2);
      first.dispose();

      // "Restart": a new service over the same stored data.
      final (second, _) = await device(server, store: kv);
      expect(second.pendingCount, 2);
      expect(server.valueOf(kPrefAccent), isNull);

      server.unreachable = false;
      second.setReachable(false);
      second.setReachable(true); // the reconnect
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await second.syncNow();
      expect(server.valueOf(kPrefAccent), 'ice');
      expect(server.valueOf(kPrefStartupSound), 'false');
      expect(second.pendingCount, 0);
    });

    test('the queue survives in the real file store too', () async {
      await useTempKvStore();
      final server = FakePrefsServer()..unreachable = true;
      final svc = PrefsSyncService(transport: server.transport(), registry: _registry, debounce: null, pollInterval: null);
      services.add(svc);
      await svc.bind('srv');
      await svc.setLocal(kPrefAccent, 'ice');
      expect(await LocalKvStore.instance.read(kPrefAccent), 'ice');

      LocalKvStore.instance.resetForTesting(); // re-read the file, as a restart does
      final again = PrefsSyncService(transport: server.transport(), registry: _registry, debounce: null, pollInterval: null);
      services.add(again);
      await again.bind('srv');
      expect(again.pendingCount, 1);
      server.unreachable = false;
      await again.syncNow();
      expect(server.valueOf(kPrefAccent), 'ice');
    });

    test('a write is sent after the debounce, as one request', () async {
      final server = FakePrefsServer();
      final (svc, _) = await device(server, debounce: const Duration(milliseconds: 30));
      await svc.syncNow();
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.setLocal(kPrefThemeMode, 'dark');
      expect(server.patchBodies, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(server.patchBodies, hasLength(1));
      expect((server.patchBodies.single['entries'] as Map).keys, containsAll([kPrefAccent, kPrefThemeMode]));
    });
  });

  group('what goes on the wire', () {
    test('device-scope and unknown keys never appear in a PATCH body, and the body follows the contract', () async {
      final server = FakePrefsServer();
      final (svc, _) = await device(server);
      await svc.setLocal(kPrefUiScale, 'large90');
      await svc.setLocal(kPrefFullScreen, 'false');
      await svc.setLocal('some_unregistered_key', 'x');
      await svc.setIgnoreServerAppearance(true);
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.deleteLocal(kPrefUiScale);
      await svc.syncNow();

      expect(server.patchBodies, hasLength(1));
      final body = server.patchBodies.single;
      expect((body['entries'] as Map).keys, [kPrefAccent]);
      expect(body['deleted'], isEmpty);
      expect(body['device'], 'mac-1');
      expect(body['device_class'], isIn(['desktop', 'phone']));
      expect(body['base_rev'], 0);
      final raw = jsonEncode(body);
      for (final secret in [kPrefUiScale, kPrefFullScreen, 'some_unregistered_key', kPrefIgnoreServerAppearance, 'large90']) {
        expect(raw, isNot(contains(secret)));
      }
      expect((body['entries'] as Map)[kPrefAccent], {'value': 'ice', 'scope': 'cloud'});
    });

    test('a device-scope entry coming from the server is ignored', () async {
      final server = FakePrefsServer()
        ..seed(kPrefUiScale, 'small70')
        ..seed(kPrefFullScreen, 'false', scope: 'device');
      final (svc, kv) = await device(server);
      await svc.syncNow();
      expect(kv.data.containsKey(kPrefUiScale), isFalse);
      expect(kv.data.containsKey(kPrefFullScreen), isFalse);
    });

    test('GET asks for news since the last revision it took in', () async {
      final server = FakePrefsServer()..seed(kPrefAccent, 'ember');
      final (svc, _) = await device(server);
      await svc.syncNow();
      server.seed(kPrefThemeMode, 'dark');
      await svc.syncNow();
      expect(server.getSinces, [null, 1]);
    });

    test('the device id is made once and kept', () async {
      final server = FakePrefsServer();
      final kv = MemoryKvStore();
      final (a, _) = await device(server, store: kv);
      await a.load();
      final id = a.deviceId;
      expect(id, isNotNull);
      final (b, _) = await device(server, store: kv);
      await b.load();
      expect(b.deviceId, id);
    });

    test('forgetting the server copy clears it and keeps local values', () async {
      final server = FakePrefsServer();
      final (svc, kv) = await device(server);
      await svc.setLocal(kPrefAccent, 'ice');
      await svc.syncNow();
      expect(server.valueOf(kPrefAccent), 'ice');
      expect(await svc.forgetServerCopy(), isTrue);
      expect(server.valueOf(kPrefAccent), isNull);
      expect(kv.data[kPrefAccent], 'ice');
      server.supported = false;
      expect(await svc.forgetServerCopy(), isFalse);
    });
  });

  group('several servers', () {
    test('switching the active server swaps the applied prefs, from the cache without the network', () async {
      final one = FakePrefsServer()..seed(kPrefAccent, 'ember');
      final two = FakePrefsServer()..seed(kPrefAccent, 'ice');
      final transport = SwitchingTransport({'one': one, 'two': two}, 'one');
      final kv = MemoryKvStore({kPrefsDeviceIdKey: 'mac-1'});
      final svc = PrefsSyncService(transport: transport, store: kv, registry: _registry, debounce: null, pollInterval: null);
      services.add(svc);
      final applied = <Map<String, String?>>[];
      svc.applier = applied.add;

      await svc.bind('one');
      await svc.syncNow();
      expect(kv.data[kPrefAccent], 'ember');

      transport.current = 'two';
      await svc.bind('two');
      expect(kv.data[kPrefAccent], 'ember'); // nothing cached for it yet
      await svc.syncNow();
      expect(kv.data[kPrefAccent], 'ice');

      // Back to the first one: its cached prefs apply at once, no request.
      one.unreachable = true;
      applied.clear();
      transport.current = 'one';
      await svc.bind('one');
      expect(kv.data[kPrefAccent], 'ember');
      expect(applied, [
        {kPrefAccent: 'ember'},
      ]);
      expect(one.getSinces, hasLength(1));
    });

    test('one service rebinding between servers keeps each server queue apart', () async {
      final one = FakePrefsServer();
      final kv = MemoryKvStore({kPrefsDeviceIdKey: 'mac-1'});
      final (svc, _) = await device(one, store: kv, serverKey: 'one');
      await svc.setLocal(kPrefAccent, 'ice');
      expect(svc.pendingCount, 1);
      await svc.bind('two');
      expect(svc.pendingCount, 0);
      expect(svc.serverKey, 'two');
      await svc.bind('one');
      expect(svc.pendingCount, 1);
      await svc.bind(null);
      expect(svc.status, PrefsSyncStatus.unpaired);
    });

    test('"Don\'t take appearance from my server" holds the look back, and turning it off takes it', () async {
      final server = FakePrefsServer()
        ..seed(kPrefAccent, 'ember')
        ..seed(kPrefThemeMode, 'dark');
      final kv = MemoryKvStore({kPrefsDeviceIdKey: 'mac-1', kPrefAccent: 'ice', kPrefsExplicitKey: '[]'});
      final (svc, _) = await device(server, store: kv);
      await svc.setIgnoreServerAppearance(true);
      expect(kv.data[kPrefIgnoreServerAppearance], 'true');
      final applied = <Map<String, String?>>[];
      svc.applier = applied.add;

      await svc.syncNow();
      expect(kv.data[kPrefAccent], 'ice');
      expect(kv.data.containsKey(kPrefThemeMode), isFalse);
      expect(applied, isEmpty);

      await svc.setIgnoreServerAppearance(false);
      expect(kv.data[kPrefAccent], 'ember');
      expect(kv.data[kPrefThemeMode], 'dark');
      expect(applied, hasLength(1));
    });

    test('the opt-out is remembered across a restart', () async {
      final server = FakePrefsServer();
      final (svc, kv) = await device(server);
      await svc.setIgnoreServerAppearance(true);
      final (again, _) = await device(server, store: kv);
      await again.load();
      expect(again.ignoreServerAppearance, isTrue);
    });
  });

  group('AppState', () {
    test('appearance writes go through the sync, and the server changes what is on screen', () async {
      await useTempKvStore();
      final server = FakePrefsServer();
      final svc = PrefsSyncService(transport: server.transport(), debounce: null, pollInterval: null);
      services.add(svc);
      final app = AppState(sync: svc);
      await svc.bind('srv');
      app.accentChoice = AxAccent.ice;
      app.themeMode = ThemeMode.dark;
      app.uiScale = AxUiScale.large90;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await LocalKvStore.instance.read(kPrefAccent), 'ice');

      await svc.syncNow();
      expect(server.valueOf(kPrefAccent), 'ice');
      expect(server.valueOf(kPrefThemeMode), 'dark');
      expect(server.valueOf(kPrefUiScale), isNull);

      server.seed(kPrefAccent, 'amber');
      server.seed(kPrefStartupSound, 'false');
      var notified = 0;
      app.addListener(() => notified++);
      await svc.syncNow();
      expect(app.accentChoice, AxAccent.amber);
      expect(app.startupSound, isFalse);
      expect(notified, greaterThan(0));

      // The next launch reads the live keys exactly as it always did.
      final next = AppState();
      await next.loadAppearance();
      expect(next.accentChoice, AxAccent.amber);
      expect(next.themeMode, ThemeMode.dark);
      expect(next.uiScale, AxUiScale.large90);
    });
  });

  test('no periodic timer is created when pollInterval is null, and one runs when it is set', () async {
    final server = FakePrefsServer();
    final (idle, _) = await device(server);
    await idle.syncNow();
    final baseline = server.getSinces.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.getSinces.length, baseline);

    final (ticking, _) = await device(server, id: 'phone-1', poll: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(server.getSinces.length, greaterThan(baseline + 2));
    ticking.dispose();
    final after = server.getSinces.length;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(server.getSinces.length, after);
  });
}
