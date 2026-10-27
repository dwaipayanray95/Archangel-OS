import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/prefs_sync_service.dart';
import 'package:archangel/services/server_registry.dart';
import 'package:archangel/ui/prefs_sync_binder.dart';

import 'prefs_sync_fakes.dart';
import 'test_utils.dart';

ServerProfile _profile(String id, String host) =>
    ServerProfile(id: id, name: 'Server $id', host: host, token: 'tok-$id', wgConfig: '', createdAt: DateTime.utc(2025));

void main() {
  testWidgets('follows the active server and asks it for news', (tester) async {
    final server = FakePrefsServer()..seed(kPrefAccent, 'ember');
    final sync = PrefsSyncService(transport: server.transport(), store: MemoryKvStore(), debounce: null, pollInterval: null);
    addTearDown(sync.dispose);
    final registry = ServerRegistry();
    final backend = ArchangeldConnection(client: MockClient((_) async => http.Response('{}', 500)));
    await tester.runAsync(() async {
      await useTempKvStore();
      await registry.load();
      await backend.load();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerRegistry>.value(value: registry),
          ChangeNotifierProvider<ArchangeldConnection>.value(value: backend),
          ChangeNotifierProvider<PrefsSyncService>.value(value: sync),
        ],
        child: const PrefsSyncBinder(child: SizedBox()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(sync.serverKey, isNull);
    expect(sync.status, PrefsSyncStatus.unpaired);

    await tester.runAsync(() async {
      await registry.add(_profile('a', '10.0.0.1:8443'));
      await backend.pair(host: '10.0.0.1:8443', token: 'tok-a');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(sync.serverKey, 'id-a');
    expect(sync.status, PrefsSyncStatus.synced);
    expect(server.getSinces, isNotEmpty);

    // Half-way through switching (registry moved, connection not yet) it holds off.
    expect(prefsServerKeyFor(registry, backend), 'id-a');
    await tester.runAsync(() => registry.add(_profile('b', '10.0.0.2:8443')));
    expect(prefsServerKeyFor(registry, backend), isNull);
    await tester.runAsync(() async {
      await backend.pair(host: '10.0.0.2:8443', token: 'tok-b');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(sync.serverKey, 'id-b');
  });
}
