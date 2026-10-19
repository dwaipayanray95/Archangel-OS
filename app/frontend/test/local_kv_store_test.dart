import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:archangel/services/local_kv_store.dart';
import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await useTempKvStore());

  File backing() => File('${dir.path}/archangel_app_state.json');

  test('read returns null for a missing key', () async {
    expect(await LocalKvStore.instance.read('nope'), isNull);
  });

  test('write then read round-trips and persists to disk', () async {
    final store = LocalKvStore.instance;
    await store.write('token', 'abc');
    expect(await store.read('token'), 'abc');
    expect(jsonDecode(await backing().readAsString()), {'token': 'abc'});

    // A fresh load from disk sees the same value.
    store.resetForTesting();
    expect(await store.read('token'), 'abc');
  });

  test('delete removes the key and persists', () async {
    final store = LocalKvStore.instance;
    await store.write('a', '1');
    await store.write('b', '2');
    await store.delete('a');
    store.resetForTesting();
    expect(await store.read('a'), isNull);
    expect(await store.read('b'), '2');
    await store.delete('missing'); // no-op, must not throw
  });

  test('corrupt backing file starts fresh', () async {
    await backing().writeAsString('not json');
    expect(await LocalKvStore.instance.read('x'), isNull);
  });

  test('backing file is owner-only (0600) on Linux/macOS', () async {
    await LocalKvStore.instance.write('wg_private_key', 'secret');
    final mode = (await backing().stat()).mode & 0x1FF;
    expect(mode, 0x180); // 0600
  }, skip: !(Platform.isLinux || Platform.isMacOS));
}
