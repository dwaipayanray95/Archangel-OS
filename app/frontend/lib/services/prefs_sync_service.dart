import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'archangeld_connection.dart';
import 'local_kv_store.dart';

// Preference sync, phase 2a. The contract is docs/dev/prefs-sync.md.
//
// LocalKvStore stays the source of truth for reads: the "live" keys below
// (the same `appearance_*` keys AppState has always read) hold what the UI
// shows, so the app renders instantly at launch and nothing waits for the
// network. Everything this service adds sits beside them: a per-server
// mirror of what that server holds, plus the queue of changes it has not
// accepted yet.

/// Live key of the theme mode (also read by AppState at launch).
const kPrefThemeMode = 'appearance_theme_mode';

/// Live key of the accent colour.
const kPrefAccent = 'appearance_accent';

/// Live key of the start-up chime.
const kPrefStartupSound = 'appearance_startup_sound';

/// Live key of the UI scale (this device only).
const kPrefUiScale = 'appearance_ui_scale';

/// Live key of the full-screen state (this device only).
const kPrefFullScreen = 'appearance_full_screen';

/// The local "Don't take appearance from my server" switch (this device only).
const kPrefIgnoreServerAppearance = 'prefs_ignore_server_appearance';

/// This install's random id, made once. The server tells devices apart by it.
const kPrefsDeviceIdKey = 'prefs_device_id';

/// The keys the person deliberately set on this device (JSON list). A key
/// that is not in it is a default and loses to any server value.
const kPrefsExplicitKey = 'prefs_explicit';

/// Per-server state lives under this prefix plus the server key.
const kPrefsStatePrefix = 'prefs_sync_state/';

/// How long a write waits before it is sent, so a burst becomes one request.
const Duration kPrefsDebounce = Duration(seconds: 2);

/// How often a reachable server is asked for news.
const Duration kPrefsPollInterval = Duration(minutes: 5);

/// How far a pref travels.
enum PrefScope {
  /// Syncs everywhere.
  cloud,

  /// Syncs between devices of the same shape (`desktop`, `phone`).
  deviceClass,

  /// Never leaves this machine.
  device,
}

/// What the registry knows about one pref.
@immutable
class PrefSpec {
  const PrefSpec(this.scope, {this.appearance = false});

  final PrefScope scope;

  /// Part of the look of the app: the local opt-out switch holds these back.
  final bool appearance;
}

/// Every pref the sync knows about. A key that is not here is never pushed,
/// so nothing leaks by accident. (Layout, dock and the wallpaper are
/// `deviceClass` or `cloud` prefs that arrive with phase 2b.)
const Map<String, PrefSpec> kPrefRegistry = {
  kPrefThemeMode: PrefSpec(PrefScope.cloud, appearance: true),
  kPrefAccent: PrefSpec(PrefScope.cloud, appearance: true),
  kPrefStartupSound: PrefSpec(PrefScope.cloud, appearance: true),
  kPrefUiScale: PrefSpec(PrefScope.device),
  kPrefFullScreen: PrefSpec(PrefScope.device),
  kPrefIgnoreServerAppearance: PrefSpec(PrefScope.device),
};

/// Where the service stands, for the Settings line.
enum PrefsSyncStatus {
  /// No server to sync with: settings stay on this device.
  unpaired,

  /// Paired, nothing exchanged yet.
  idle,
  syncing,
  synced,

  /// The server did not answer (or answered with an error). Changes queue.
  offline,

  /// The server answered 404: it predates this feature. Local only.
  unsupported,
}

/// What a request got back. [body] is the decoded JSON, or null when the
/// reply had none (or it was not JSON).
class PrefsReply {
  const PrefsReply(this.status, [this.body]);

  final int status;
  final Object? body;

  bool get ok => status >= 200 && status < 300;
  bool get notFound => status == 404;
}

/// The wire to `/api/v1/prefs`. Throw for anything that stops a reply from
/// arriving (the service treats a throw as "unreachable").
abstract class PrefsTransport {
  Future<PrefsReply> get({int? since});
  Future<PrefsReply> patch(Map<String, Object?> body);
  Future<PrefsReply> delete();
}

/// [PrefsTransport] over plain http to the paired archangeld, with the
/// `X-Archangel-Token` header like the other services.
class HttpPrefsTransport implements PrefsTransport {
  HttpPrefsTransport(this._backend, {http.Client? client, this.timeout = const Duration(seconds: 8)}) : _client = client;

  final ArchangeldConnection _backend;
  final http.Client? _client;
  final Duration timeout;

  Uri _uri({int? since}) {
    final host = _backend.host;
    if (!_backend.isPaired || host == null) throw StateError('Not paired with a backend');
    final uri = Uri.parse('http://$host/api/v1/prefs');
    return since == null ? uri : uri.replace(queryParameters: {'since': '$since'});
  }

  Map<String, String> get _headers => {'X-Archangel-Token': _backend.token ?? '', 'Content-Type': 'application/json'};

  PrefsReply _reply(http.Response res) {
    Object? body;
    try {
      if (res.body.isNotEmpty) body = jsonDecode(res.body);
    } catch (_) {
      body = null;
    }
    return PrefsReply(res.statusCode, body);
  }

  @override
  Future<PrefsReply> get({int? since}) async {
    final uri = _uri(since: since);
    final res = await (_client == null ? http.get(uri, headers: _headers) : _client.get(uri, headers: _headers)).timeout(timeout);
    return _reply(res);
  }

  @override
  Future<PrefsReply> patch(Map<String, Object?> body) async {
    final uri = _uri();
    final data = jsonEncode(body);
    final res = await (_client == null ? http.patch(uri, headers: _headers, body: data) : _client.patch(uri, headers: _headers, body: data))
        .timeout(timeout);
    return _reply(res);
  }

  @override
  Future<PrefsReply> delete() async {
    final uri = _uri();
    final res = await (_client == null ? http.delete(uri, headers: _headers) : _client.delete(uri, headers: _headers)).timeout(timeout);
    return _reply(res);
  }
}

/// One key as the server holds it.
@immutable
class PrefEntry {
  const PrefEntry({required this.value, this.scope = 'cloud', this.rev = 0, this.updatedAt, this.device});

  final String value;
  final String scope;
  final int rev;
  final String? updatedAt;
  final String? device;

  Map<String, Object?> toJson() => {'value': value, 'scope': scope, 'rev': rev, 'updated_at': ?updatedAt, 'device': ?device};

  static PrefEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final value = j['value'];
    if (value is! String) return null;
    return PrefEntry(
      value: value,
      scope: j['scope'] is String ? j['scope'] as String : 'cloud',
      rev: (j['rev'] as num?)?.toInt() ?? 0,
      updatedAt: j['updated_at'] is String ? j['updated_at'] as String : null,
      device: j['device'] is String ? j['device'] as String : null,
    );
  }
}

/// Called with the keys the server changed on this device; a null value
/// means "back to the default". AppState uses it to update what is on screen.
typedef PrefsApplier = void Function(Map<String, String?> changes);

/// Everything remembered for one server.
class _ServerState {
  /// `prefs_synced_rev`: the newest server revision this device has taken in.
  int syncedRev = 0;

  /// The queue: key to the value waiting to be sent. Survives restarts.
  final Map<String, String> dirty = {};

  /// Keys removed here that the server has not been told about yet.
  final Set<String> tombstones = {};

  /// What the server last told us it holds (the per-server cache).
  final Map<String, PrefEntry> entries = {};
  DateTime? lastSync;

  /// Whether the first sync (push local if the server is empty) has happened.
  bool seeded = false;

  /// The server answered 404 last time we asked.
  bool unsupported = false;

  Map<String, Object?> toJson() => {
    'synced_rev': syncedRev,
    'dirty': dirty,
    'tombstones': tombstones.toList(),
    'entries': {for (final e in entries.entries) e.key: e.value.toJson()},
    'last_sync': lastSync?.toUtc().toIso8601String(),
    'seeded': seeded,
    'unsupported': unsupported,
  };

  static _ServerState fromJson(Object? j) {
    final s = _ServerState();
    if (j is! Map) return s;
    s.syncedRev = (j['synced_rev'] as num?)?.toInt() ?? 0;
    final dirty = j['dirty'];
    if (dirty is Map) {
      for (final e in dirty.entries) {
        if (e.key is String && e.value is String) s.dirty[e.key as String] = e.value as String;
      }
    }
    final tombs = j['tombstones'];
    if (tombs is List) s.tombstones.addAll(tombs.whereType<String>());
    final entries = j['entries'];
    if (entries is Map) {
      for (final e in entries.entries) {
        final entry = PrefEntry.fromJson(e.value);
        if (e.key is String && entry != null) s.entries[e.key as String] = entry;
      }
    }
    s.lastSync = DateTime.tryParse('${j['last_sync']}');
    s.seeded = j['seeded'] == true;
    s.unsupported = j['unsupported'] == true;
    return s;
  }
}

/// Keeps the settings that should follow a person between their devices in
/// step with the active server, per key, without ever blocking on the
/// network. See docs/dev/prefs-sync.md.
///
/// Every failure (404, unreachable, bad reply) means "local only for now":
/// nothing here throws to a caller or shows an error.
class PrefsSyncService extends ChangeNotifier {
  PrefsSyncService({
    PrefsTransport? transport,
    LocalKvStore? store,
    DateTime Function()? now,
    Map<String, PrefSpec> registry = kPrefRegistry,
    this.debounce = kPrefsDebounce,
    this.pollInterval = kPrefsPollInterval,
    String? deviceClass,
  }) : _transport = transport,
       _store = store ?? LocalKvStore.instance,
       _now = now ?? DateTime.now,
       _registry = registry,
       deviceClass = deviceClass ?? _defaultDeviceClass();

  final PrefsTransport? _transport;
  final LocalKvStore _store;
  final DateTime Function() _now;
  final Map<String, PrefSpec> _registry;

  /// How long a write waits before it is sent. Null turns the timer off
  /// (tests call [flush] themselves).
  final Duration? debounce;

  /// How often a reachable server is asked for news. Null turns the periodic
  /// timer off, which is what tests use so no timer is left pending.
  final Duration? pollInterval;

  /// `desktop` or `phone`, sent with every PATCH.
  final String deviceClass;

  static String _defaultDeviceClass() =>
      defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS ? 'phone' : 'desktop';

  /// AppState sets this so server changes reach what is on screen.
  PrefsApplier? applier;

  // ---- state ----

  bool _globalLoaded = false;
  Future<void>? _globalLoading;
  String? _deviceId;
  final Set<String> _explicit = {};
  bool _ignoreAppearance = false;
  bool _ignoreTouched = false;

  String? _key;
  _ServerState? _state;
  int _bindGen = 0;
  PrefsSyncStatus _status = PrefsSyncStatus.unpaired;
  bool _reachable = true;
  Timer? _debounceTimer;
  Timer? _pollTimer;
  Future<void>? _running;
  bool _again = false;
  bool _againPull = false;
  bool _disposed = false;
  List<String> _lastAdopted = const [];
  final _adopted = StreamController<List<String>>.broadcast();

  /// This install's id (null until [load] has run).
  String? get deviceId => _deviceId;

  /// The server key the prefs are currently namespaced under, or null.
  String? get serverKey => _key;

  PrefsSyncStatus get status => _status;

  /// When this device last finished a full exchange with the active server.
  DateTime? get lastSync => _state?.lastSync;

  /// Changes waiting to be sent to the active server.
  int get pendingCount => (_state?.dirty.length ?? 0) + (_state?.tombstones.length ?? 0);

  /// Whether server values for the app's look are held back on this device.
  bool get ignoreServerAppearance => _ignoreAppearance;

  /// The keys the server last changed on this device (the loser of a
  /// conflict adopts the winner and shows up here).
  List<String> get lastAdopted => _lastAdopted;

  /// Fires with the keys whenever the server changed values on this device.
  Stream<List<String>> get adopted => _adopted.stream;

  // ---- loading ----

  /// Reads the device id, the explicit set and the opt-out switch. Safe to
  /// call any number of times.
  Future<void> load() => _globalLoaded ? Future.value() : (_globalLoading ??= _loadGlobal());

  Future<void> _loadGlobal() async {
    try {
      var id = await _store.read(kPrefsDeviceIdKey);
      if (id == null || id.isEmpty) {
        id = _newDeviceId();
        await _store.write(kPrefsDeviceIdKey, id);
      }
      _deviceId = id;
      final rawExplicit = await _store.read(kPrefsExplicitKey);
      if (rawExplicit != null) {
        try {
          final j = jsonDecode(rawExplicit);
          if (j is List) _explicit.addAll(j.whereType<String>());
        } catch (_) {}
      } else {
        // Installs from before sync: a stored value means the person set it.
        for (final e in _registry.entries) {
          if (e.value.scope != PrefScope.device && await _store.read(e.key) != null) _explicit.add(e.key);
        }
        await _persistExplicit();
      }
      if (!_ignoreTouched) _ignoreAppearance = await _store.read(kPrefIgnoreServerAppearance) == 'true';
    } catch (_) {
      _deviceId ??= _newDeviceId();
    }
    _globalLoaded = true;
  }

  static String _newDeviceId() {
    final r = math.Random.secure();
    return 'dev-${List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void> _persistExplicit() => _store.write(kPrefsExplicitKey, jsonEncode(_explicit.toList()..sort()));

  Future<_ServerState> _loadState(String key) async {
    try {
      final raw = await _store.read('$kPrefsStatePrefix$key');
      if (raw != null) return _ServerState.fromJson(jsonDecode(raw));
    } catch (_) {}
    return _ServerState();
  }

  Future<void> _persistState(String key, _ServerState s) => _store.write('$kPrefsStatePrefix$key', jsonEncode(s.toJson()));

  // ---- binding to the active server ----

  /// Points the service at a server (its [ServerProfile.serverKey]), or at
  /// none. Its cached prefs are applied at once, without the network; call
  /// [syncNow] afterwards to exchange news.
  Future<void> bind(String? serverKey) async {
    final gen = ++_bindGen;
    await load();
    if (gen != _bindGen) return;
    if (serverKey == _key && (serverKey == null || _state != null)) return;
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    if (serverKey == null || _transport == null) {
      _key = serverKey;
      _state = null;
      _setStatus(PrefsSyncStatus.unpaired);
      return;
    }
    final state = await _loadState(serverKey);
    if (gen != _bindGen) return;
    _key = serverKey;
    _state = state;
    _setStatus(
      state.unsupported
          ? PrefsSyncStatus.unsupported
          : state.lastSync != null
          ? PrefsSyncStatus.synced
          : PrefsSyncStatus.idle,
    );
    await _applyDesired(state);
    if (gen != _bindGen) return;
    final every = pollInterval;
    if (every != null && !_disposed) {
      _pollTimer = Timer.periodic(every, (_) {
        if (_reachable) unawaited(syncNow());
      });
    }
  }

  /// Tells the service whether the server is reachable. Coming back
  /// triggers a sync; while it is not, the periodic check stays quiet.
  void setReachable(bool reachable) {
    final was = _reachable;
    _reachable = reachable;
    if (reachable && !was && _state != null) unawaited(syncNow());
  }

  // ---- local writes ----

  /// Stores [value] under [key] on this device (the live key) and, for a
  /// registered key that syncs, queues it for the active server.
  Future<void> setLocal(String key, String value) async {
    final spec = _registry[key];
    final syncs = spec != null && spec.scope != PrefScope.device;
    if (syncs) {
      _explicit.add(key);
      final s = _state;
      if (s != null) {
        s.dirty[key] = value;
        s.tombstones.remove(key);
      }
      notifyListeners();
      _schedulePush();
    }
    await _store.write(key, value);
    if (syncs) await _persistAll();
  }

  /// Removes [key] on this device and queues the removal (a tombstone), so
  /// it stays gone on the other devices.
  Future<void> deleteLocal(String key) async {
    final spec = _registry[key];
    final syncs = spec != null && spec.scope != PrefScope.device;
    if (syncs) {
      _explicit.remove(key);
      final s = _state;
      if (s != null) {
        s.dirty.remove(key);
        s.tombstones.add(key);
      }
      notifyListeners();
      _schedulePush();
    }
    await _store.delete(key);
    if (syncs) await _persistAll();
  }

  Future<void> _persistAll() async {
    final s = _state;
    final k = _key;
    await _persistExplicit();
    if (s != null && k != null) await _persistState(k, s);
  }

  /// The local "Don't take appearance from my server" switch. Turning it
  /// off takes the server's look straight away.
  Future<void> setIgnoreServerAppearance(bool value) async {
    if (_ignoreAppearance == value) return;
    _ignoreAppearance = value;
    _ignoreTouched = true;
    notifyListeners();
    await _store.write(kPrefIgnoreServerAppearance, value.toString());
    final s = _state;
    if (!value && s != null) await _applyDesired(s);
  }

  void _schedulePush() {
    final wait = debounce;
    if (wait == null || _state == null || _disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(wait, () => unawaited(flush()));
  }

  // ---- applying to the live keys ----

  /// Applies what the active server's cache (and our own queue) says should
  /// be live right now. No network.
  Future<void> _applyDesired(_ServerState s) async {
    final want = <String, String?>{};
    for (final k in _registry.keys) {
      final spec = _registry[k]!;
      if (spec.scope == PrefScope.device) continue;
      if (s.tombstones.contains(k)) continue;
      final pending = s.dirty[k];
      final cached = s.entries[k]?.value;
      final v = pending ?? cached;
      if (v != null) want[k] = v;
    }
    await _applyToLive(s, want);
  }

  /// Writes [want] to the live keys where it differs and tells the UI.
  /// Appearance keys are held back while the opt-out switch is on, unless
  /// the value is this device's own pending change.
  Future<void> _applyToLive(_ServerState s, Map<String, String?> want) async {
    final applied = <String, String?>{};
    for (final e in want.entries) {
      final spec = _registry[e.key];
      if (spec == null || spec.scope == PrefScope.device) continue;
      if (spec.appearance && _ignoreAppearance && !s.dirty.containsKey(e.key)) continue;
      final live = await _store.read(e.key);
      if (live == e.value) continue;
      if (e.value == null) {
        await _store.delete(e.key);
        _explicit.remove(e.key);
      } else {
        await _store.write(e.key, e.value!);
      }
      applied[e.key] = e.value;
    }
    if (applied.isEmpty || !identical(_state, s)) return;
    if (applied.containsValue(null)) await _persistExplicit();
    applier?.call(applied);
    _lastAdopted = applied.keys.toList();
    if (!_adopted.isClosed) _adopted.add(_lastAdopted);
    notifyListeners();
  }

  // ---- syncing ----

  /// Asks the server for news, applies what is newer, then sends what is
  /// waiting. Never throws. Calls made while one runs are folded into it.
  Future<void> syncNow() => _request(pull: true);

  /// Sends what is waiting (the debounced path). Never throws.
  Future<void> flush() => _request(pull: false);

  Future<void> _request({required bool pull}) async {
    if (_state == null || _transport == null || _disposed) return;
    final running = _running;
    if (running != null) {
      _again = true;
      _againPull = _againPull || pull;
      return running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      var doPull = pull;
      do {
        _again = false;
        _againPull = false;
        await _cycle(pull: doPull);
        doPull = _againPull;
      } while (_again && _state != null && !_disposed);
    } finally {
      _running = null;
      done.complete();
    }
  }

  Future<void> _cycle({required bool pull}) async {
    final s = _state;
    final key = _key;
    final transport = _transport;
    if (s == null || key == null || transport == null) return;
    bool current() => identical(_state, s) && !_disposed;
    // A push before the first exchange would skip the first-sync rules.
    final doPull = pull || !s.seeded;
    if (!doPull && s.unsupported) return; // a poll or reconnect probes again
    _setStatus(PrefsSyncStatus.syncing);
    try {
      await load();
      final base = s.syncedRev;
      if (doPull) {
        final reply = await transport.get(since: base == 0 ? null : base);
        if (!current()) return;
        if (reply.notFound) {
          await _markUnsupported(s, key);
          return;
        }
        final parsed = reply.ok ? _parseGet(reply.body) : null;
        if (parsed == null) {
          _setStatus(PrefsSyncStatus.offline);
          return;
        }
        await _mergeFromServer(s, parsed, firstSync: !s.seeded);
        if (!current()) return;
        s.syncedRev = parsed.serverRev;
        s.unsupported = false;
        await _persistState(key, s);
      }
      final ok = await _push(s, key, transport, base);
      if (!current() || !ok) return;
      s.lastSync = _now();
      s.unsupported = false;
      await _persistState(key, s);
      _setStatus(PrefsSyncStatus.synced);
    } catch (_) {
      if (current()) _setStatus(PrefsSyncStatus.offline);
    }
  }

  Future<void> _markUnsupported(_ServerState s, String key) async {
    s.unsupported = true;
    _setStatus(PrefsSyncStatus.unsupported);
    try {
      await _persistState(key, s);
    } catch (_) {}
  }

  _GetResult? _parseGet(Object? body) {
    if (body is! Map) return null;
    final rev = (body['server_rev'] as num?)?.toInt();
    if (rev == null) return null;
    final entries = <String, PrefEntry>{};
    final raw = body['entries'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final entry = PrefEntry.fromJson(e.value);
        if (e.key is String && entry != null) entries[e.key as String] = entry;
      }
    }
    final deleted = <String, int>{};
    final rawDeleted = body['deleted'];
    if (rawDeleted is List) {
      for (final d in rawDeleted) {
        if (d is Map && d['key'] is String) deleted[d['key'] as String] = (d['rev'] as num?)?.toInt() ?? 0;
      }
    }
    return _GetResult(rev, entries, deleted);
  }

  /// Takes in what the server sent. A key with a change of ours waiting is
  /// left alone: the PATCH that follows lets the server's rule decide.
  Future<void> _mergeFromServer(_ServerState s, _GetResult r, {required bool firstSync}) async {
    if (firstSync) {
      // Server empty, local customised: push local. Keys that were never
      // set on this device are defaults and take whatever the server has.
      for (final k in _explicit) {
        final spec = _registry[k];
        if (spec == null || spec.scope == PrefScope.device || s.dirty.containsKey(k) || s.tombstones.contains(k)) continue;
        final live = await _store.read(k);
        if (live != null && r.entries[k]?.value != live) s.dirty[k] = live;
      }
      s.seeded = true;
    }
    final want = <String, String?>{};
    for (final e in r.entries.entries) {
      if (e.value.scope == PrefScope.device.name) continue; // never ours to take
      final spec = _registry[e.key];
      if (spec != null && spec.scope == PrefScope.device) continue;
      s.entries[e.key] = e.value;
      if (spec == null || s.dirty.containsKey(e.key) || s.tombstones.contains(e.key)) continue;
      want[e.key] = e.value.value;
    }
    for (final d in r.deleted.entries) {
      final spec = _registry[d.key];
      if (spec != null && spec.scope == PrefScope.device) continue;
      final alive = r.entries[d.key];
      if (alive != null && alive.rev >= d.value) continue;
      s.entries.remove(d.key);
      if (spec == null) continue;
      if (s.tombstones.remove(d.key)) continue; // we deleted it too
      if (s.dirty.containsKey(d.key)) continue; // set again here since: ours wins
      want[d.key] = null;
    }
    await _applyToLive(s, want);
  }

  /// Sends the queue. Returns false when the server did not take it.
  Future<bool> _push(_ServerState s, String key, PrefsTransport transport, int baseRev) async {
    final sent = <String, String>{};
    for (final e in s.dirty.entries) {
      final spec = _registry[e.key];
      // Device-scope and unknown keys never go on the wire.
      if (spec != null && spec.scope != PrefScope.device) sent[e.key] = e.value;
    }
    final sentDeleted = <String>{
      for (final k in s.tombstones)
        if (_registry[k] != null && _registry[k]!.scope != PrefScope.device) k,
    };
    if (sent.isEmpty && sentDeleted.isEmpty) return true;
    final reply = await transport.patch({
      'base_rev': baseRev,
      'device': _deviceId,
      'device_class': deviceClass,
      'entries': {
        for (final e in sent.entries) e.key: {'value': e.value, 'scope': _registry[e.key]!.scope.name},
      },
      'deleted': sentDeleted.toList()..sort(),
    });
    if (!identical(_state, s)) return false;
    if (reply.notFound) {
      await _markUnsupported(s, key);
      return false;
    }
    final body = reply.body;
    if (!reply.ok || body is! Map) {
      _setStatus(PrefsSyncStatus.offline);
      return false;
    }
    final serverRev = (body['server_rev'] as num?)?.toInt() ?? s.syncedRev;
    final rejected = <String, PrefEntry>{};
    final rawRejected = body['rejected'];
    if (rawRejected is Map) {
      for (final e in rawRejected.entries) {
        final entry = PrefEntry.fromJson(e.value);
        if (e.key is String && entry != null) rejected[e.key as String] = entry;
      }
    }
    for (final e in sent.entries) {
      if (rejected.containsKey(e.key)) continue;
      // A value changed again while the request was out stays queued.
      if (s.dirty[e.key] == e.value) s.dirty.remove(e.key);
      s.entries[e.key] = PrefEntry(value: e.value, scope: _registry[e.key]!.scope.name, rev: serverRev, device: _deviceId);
    }
    for (final k in sentDeleted) {
      if (rejected.containsKey(k)) continue;
      s.tombstones.remove(k);
      s.entries.remove(k);
    }
    // The loser of a conflict adopts the winner, even a fresh local change.
    final adopt = <String, String?>{};
    for (final e in rejected.entries) {
      final spec = _registry[e.key];
      if (spec == null || spec.scope == PrefScope.device) continue;
      s.dirty.remove(e.key);
      s.tombstones.remove(e.key);
      s.entries[e.key] = e.value;
      adopt[e.key] = e.value.value;
    }
    await _applyToLive(s, adopt);
    return true;
  }

  /// "Stop syncing and forget what you have of mine": clears this account's
  /// prefs on the server (`DELETE`). Local values are kept. Returns whether
  /// the server did it.
  Future<bool> forgetServerCopy() async {
    final s = _state;
    final key = _key;
    final transport = _transport;
    if (s == null || key == null || transport == null) return false;
    try {
      final reply = await transport.delete();
      if (!identical(_state, s)) return false;
      if (reply.notFound) {
        await _markUnsupported(s, key);
        return false;
      }
      if (!reply.ok) return false;
      final rev = reply.body is Map ? ((reply.body as Map)['server_rev'] as num?)?.toInt() : null;
      s.entries.clear();
      s.dirty.clear();
      s.tombstones.clear();
      s.syncedRev = rev ?? 0;
      s.seeded = false;
      await _persistState(key, s);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _setStatus(PrefsSyncStatus next) {
    _status = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _adopted.close();
    super.dispose();
  }
}

class _GetResult {
  const _GetResult(this.serverRev, this.entries, this.deleted);

  final int serverRev;
  final Map<String, PrefEntry> entries;
  final Map<String, int> deleted;
}
