import 'dart:convert';

import 'package:archangel/services/local_kv_store.dart';
import 'package:archangel/services/prefs_sync_service.dart';

/// A [LocalKvStore] that lives in memory, so a service test touches no files
/// (and, in a widget test, queues nothing that could hold up the store).
class MemoryKvStore extends LocalKvStore {
  MemoryKvStore([Map<String, String>? seed]) : data = {...?seed}, super.forTesting();

  final Map<String, String> data;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _Stored {
  _Stored(this.value, this.scope, this.rev, this.updatedAt, this.device);
  final String value;
  final String scope;
  final int rev;
  final DateTime updatedAt;
  final String device;

  Map<String, Object?> toJson() => {
    'value': value,
    'scope': scope,
    'rev': rev,
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'device': device,
  };
}

/// A stand-in for archangeld's `/api/v1/prefs`, following the contract in
/// docs/dev/prefs-sync.md: one revision counter, the server's own clock for
/// `updated_at`, conflicts decided by the larger `updated_at` then the
/// larger device id, and tombstones.
class FakePrefsServer {
  FakePrefsServer({DateTime Function()? clock}) : clock = clock ?? _ticking();

  /// The server's clock. By default it moves one second per call.
  final DateTime Function() clock;

  static DateTime Function() _ticking() {
    var t = DateTime.utc(2026, 10, 27, 12);
    return () => t = t.add(const Duration(seconds: 1));
  }

  int rev = 0;
  final Map<String, _Stored> _entries = {};
  final Map<String, int> _deleted = {};

  /// False answers 404, like a server that predates the endpoint.
  bool supported = true;

  /// True makes every request fail to arrive.
  bool unreachable = false;

  /// When set, every request is answered with this status.
  int? forceStatus;

  /// When set, successful replies carry this body instead.
  Object? garbage;

  final List<Map<String, Object?>> patchBodies = [];
  final List<int?> getSinces = [];
  int deleteCalls = 0;

  String? valueOf(String key) => _entries[key]?.value;
  bool isDeleted(String key) => _deleted.containsKey(key);

  /// Writes a key as another device would have, without a request.
  void seed(String key, String value, {String scope = 'cloud', String device = 'other-device'}) {
    _entries[key] = _Stored(value, scope, ++rev, clock(), device);
    _deleted.remove(key);
  }

  PrefsTransport transport() => _FakeTransport(this);

  Map<String, Object?> _roundTrip(Map<String, Object?> m) => jsonDecode(jsonEncode(m)) as Map<String, Object?>;

  PrefsReply _gate() {
    if (unreachable) throw Exception('unreachable');
    if (!supported) return const PrefsReply(404);
    final f = forceStatus;
    if (f != null) return PrefsReply(f);
    return const PrefsReply(200);
  }

  PrefsReply get(int? since) {
    final gate = _gate();
    if (gate.status != 200) return gate;
    getSinces.add(since);
    if (garbage != null) return PrefsReply(200, garbage);
    final from = since ?? 0;
    return PrefsReply(
      200,
      _roundTrip({
        'server_rev': rev,
        'entries': {
          for (final e in _entries.entries)
            if (e.value.rev > from) e.key: e.value.toJson(),
        },
        'deleted': [
          for (final e in _deleted.entries)
            if (e.value > from) {'key': e.key, 'rev': e.value},
        ],
      }),
    );
  }

  PrefsReply patch(Map<String, Object?> rawBody) {
    final gate = _gate();
    if (gate.status != 200) return gate;
    final body = _roundTrip(rawBody);
    patchBodies.add(body);
    if (garbage != null) return PrefsReply(200, garbage);
    final base = body['base_rev'] as int;
    final device = body['device'] as String;
    final now = clock();
    final entries = (body['entries'] as Map).cast<String, Map>();
    final deleted = (body['deleted'] as List).cast<String>();
    final applied = <String>[];
    final rejected = <String, Object?>{};
    final newRev = rev + 1;
    for (final e in entries.entries) {
      final stored = _entries[e.key];
      if (stored != null && stored.rev > base) {
        final newer = now.isAfter(stored.updatedAt) || (now == stored.updatedAt && device.compareTo(stored.device) > 0);
        if (!newer) {
          rejected[e.key] = stored.toJson();
          continue;
        }
      }
      _entries[e.key] = _Stored(e.value['value'] as String, e.value['scope'] as String, newRev, now, device);
      _deleted.remove(e.key);
      applied.add(e.key);
    }
    for (final k in deleted) {
      _entries.remove(k);
      _deleted[k] = newRev;
      applied.add(k);
    }
    if (applied.isNotEmpty) rev = newRev;
    return PrefsReply(200, {'server_rev': rev, 'applied': applied, 'rejected': rejected});
  }

  PrefsReply delete() {
    final gate = _gate();
    if (gate.status != 200) return gate;
    deleteCalls++;
    _entries.clear();
    _deleted.clear();
    return PrefsReply(200, {'server_rev': ++rev});
  }
}

class _FakeTransport implements PrefsTransport {
  _FakeTransport(this._server);
  final FakePrefsServer _server;

  @override
  Future<PrefsReply> get({int? since}) async => _server.get(since);

  @override
  Future<PrefsReply> patch(Map<String, Object?> body) async => _server.patch(body);

  @override
  Future<PrefsReply> delete() async => _server.delete();
}

/// One transport that talks to whichever server is [current], like the real
/// one follows the paired server.
class SwitchingTransport implements PrefsTransport {
  SwitchingTransport(this.servers, this.current);
  final Map<String, FakePrefsServer> servers;
  String current;

  PrefsTransport get _now => servers[current]!.transport();

  @override
  Future<PrefsReply> get({int? since}) => _now.get(since: since);

  @override
  Future<PrefsReply> patch(Map<String, Object?> body) => _now.patch(body);

  @override
  Future<PrefsReply> delete() => _now.delete();
}
