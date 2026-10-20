import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'archangeld_connection.dart';
import 'local_kv_store.dart';
import 'pairing_bundle.dart';
import 'wireguard_controller.dart';

const _kProfilesKey = 'server_profiles_v1';
const _kActiveKey = 'server_active_id';

/// Used when an existing single pairing is migrated and nothing better is
/// known about it.
const kDefaultServerName = 'My server';

/// Everything the app needs to reach and manage one Archangel server.
///
/// The token and the WireGuard config are secrets of the same sensitivity
/// as when they were stored as two separate [LocalKvStore] entries, and are
/// stored the same way (plain JSON in the owner-only app-state file, see
/// local_kv_store.dart for why).
@immutable
class ServerProfile {
  final String id;
  final String name;

  /// archangeld `host:port`, reachable only through the tunnel.
  final String host;
  final String token;

  /// wg-quick text for this server's tunnel.
  final String wgConfig;

  /// Public address used for SSH maintenance (update, uninstall, sync).
  final String? sshHost;
  final String sshUser;

  /// Ports the server was installed with - management actions must use
  /// these rather than hard-coded defaults.
  final int appPort;
  final int wgPort;
  final DateTime createdAt;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.token,
    required this.wgConfig,
    this.sshHost,
    this.sshUser = 'ubuntu',
    this.appPort = 8443,
    this.wgPort = 51820,
    required this.createdAt,
  });

  /// The server's WireGuard public key (the `[Peer] PublicKey` of
  /// [wgConfig]), which identifies the server itself: unlike [host] it is
  /// unique per server (every default install uses 10.10.0.1:8443). Null
  /// when the config has none. Computed, so old stored profiles have it too.
  String? get serverKey => wgServerPublicKey(wgConfig);

  ServerProfile copyWith({
    String? name,
    String? host,
    String? token,
    String? wgConfig,
    String? sshHost,
    String? sshUser,
    int? appPort,
    int? wgPort,
  }) => ServerProfile(
    id: id,
    name: name ?? this.name,
    host: host ?? this.host,
    token: token ?? this.token,
    wgConfig: wgConfig ?? this.wgConfig,
    sshHost: sshHost ?? this.sshHost,
    sshUser: sshUser ?? this.sshUser,
    appPort: appPort ?? this.appPort,
    wgPort: wgPort ?? this.wgPort,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'token': token,
    'wgConfig': wgConfig,
    if (sshHost != null) 'sshHost': sshHost,
    'sshUser': sshUser,
    'appPort': appPort,
    'wgPort': wgPort,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory ServerProfile.fromJson(Map<String, dynamic> json) => ServerProfile(
    id: json['id'] as String,
    name: (json['name'] as String?)?.trim().isNotEmpty == true ? json['name'] as String : kDefaultServerName,
    host: json['host'] as String,
    token: json['token'] as String,
    wgConfig: json['wgConfig'] as String? ?? '',
    sshHost: json['sshHost'] as String?,
    sshUser: json['sshUser'] as String? ?? 'ubuntu',
    appPort: (json['appPort'] as num?)?.toInt() ?? 8443,
    wgPort: (json['wgPort'] as num?)?.toInt() ?? 51820,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.id == id &&
      other.name == name &&
      other.host == host &&
      other.token == token &&
      other.wgConfig == wgConfig &&
      other.sshHost == sshHost &&
      other.sshUser == sshUser &&
      other.appPort == appPort &&
      other.wgPort == wgPort;

  @override
  int get hashCode => Object.hash(id, name, host, token, wgConfig, sshHost, sshUser, appPort, wgPort);
}

/// The `[Peer] PublicKey` of a wg-quick config, or null.
String? wgServerPublicKey(String wgConfig) {
  var inPeer = false;
  for (final raw in wgConfig.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      inPeer = line.substring(1, line.length - 1).trim().toLowerCase() == 'peer';
      continue;
    }
    if (!inPeer) continue;
    final eq = line.indexOf('=');
    if (eq == -1) continue;
    if (line.substring(0, eq).trim().toLowerCase() == 'publickey') {
      final v = line.substring(eq + 1).trim();
      return v.isEmpty ? null : v;
    }
  }
  return null;
}

String _newId() {
  final r = Random.secure();
  final bytes = List<int>.generate(8, (_) => r.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The list of servers this device is paired with and which one is active.
///
/// This class only owns persistence and the list; bringing a profile's
/// tunnel up and pointing [ArchangeldConnection] at it is done by
/// [activateProfile] (so the registry stays unit-testable without
/// platform plugins). The active profile is mirrored into the keys
/// [ArchangeldConnection] and [WireGuardController] already persist, so
/// those keep loading exactly as before at launch.
class ServerRegistry extends ChangeNotifier {
  ServerRegistry({LocalKvStore? store}) : _store = store ?? LocalKvStore.instance;

  final LocalKvStore _store;

  List<ServerProfile> _profiles = [];
  List<ServerProfile> get profiles => List.unmodifiable(_profiles);

  String? _activeId;
  String? get activeId => _activeId;

  bool _loaded = false;

  /// True once [load] finished (including any migration).
  bool get isLoaded => _loaded;

  bool get isEmpty => _profiles.isEmpty;

  ServerProfile? get active {
    for (final p in _profiles) {
      if (p.id == _activeId) return p;
    }
    return null;
  }

  ServerProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    try {
      final raw = await _store.read(_kProfilesKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List<dynamic>;
        // One malformed entry must not drop the servers that are fine.
        final parsed = <ServerProfile>[];
        for (final e in list) {
          try {
            parsed.add(ServerProfile.fromJson(e as Map<String, dynamic>));
          } catch (_) {}
        }
        _profiles = parsed;
        _activeId = await _store.read(_kActiveKey);
      } else {
        await _migrateLegacy();
      }
    } catch (_) {
      // Unreadable list: fall back to whatever the legacy keys still hold
      // rather than stranding the user on a blank screen.
      _profiles = [];
      _activeId = null;
      try {
        await _migrateLegacy();
      } catch (_) {}
    }
    try {
      if (_profiles.isNotEmpty && byId(_activeId ?? '') == null) {
        _activeId = _profiles.first.id;
        await _persist();
      }
    } catch (_) {
      // The in-memory state is still right; a failed write must not keep
      // the app on the loading spinner.
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// An install from before multi-server support has one pairing in the
  /// legacy keys: it becomes the first profile.
  Future<void> _migrateLegacy() async {
    final host = await _store.read(kArchangeldHostKey);
    final token = await _store.read(kArchangeldTokenKey);
    if (host == null || token == null || host.isEmpty || token.isEmpty) return;
    final wg = await _store.read(kWgConfigStorageKey) ?? '';
    final profile = ServerProfile(
      id: _newId(),
      name: kDefaultServerName,
      host: host,
      token: token,
      wgConfig: wg,
      createdAt: DateTime.now(),
    );
    _profiles = [profile];
    _activeId = profile.id;
    await _persist();
  }

  Future<void> _persist() async {
    await _store.write(_kProfilesKey, jsonEncode([for (final p in _profiles) p.toJson()]));
    final id = _activeId;
    if (id == null) {
      await _store.delete(_kActiveKey);
    } else {
      await _store.write(_kActiveKey, id);
    }
  }

  /// Index of the stored profile for the same server as [profile]: the same
  /// WireGuard server key, or - only when neither has a key - the same host.
  int _indexOfSameServer(ServerProfile profile) {
    final key = profile.serverKey;
    return _profiles.indexWhere((p) => key != null ? p.serverKey == key : p.serverKey == null && p.host == profile.host);
  }

  /// Puts the registry back to an earlier state (rollback after a failed
  /// activation).
  Future<void> restore(List<ServerProfile> profiles, String? activeId) async {
    _profiles = List.of(profiles);
    _activeId = activeId;
    await _persist();
    notifyListeners();
  }

  /// Adds [profile] (or, when a profile for the same server - see
  /// [ServerProfile.serverKey] - exists, updates that one in place so
  /// re-pairing doesn't create duplicates; a different server that happens
  /// to share the host:port is added separately) and returns the stored
  /// profile. Becomes active unless [activate] is false.
  Future<ServerProfile> add(ServerProfile profile, {bool activate = true}) async {
    final existing = _indexOfSameServer(profile);
    ServerProfile stored;
    if (existing >= 0) {
      final old = _profiles[existing];
      stored = old.copyWith(
        host: profile.host,
        token: profile.token,
        wgConfig: profile.wgConfig,
        sshHost: profile.sshHost,
        sshUser: profile.sshUser,
        appPort: profile.appPort,
        wgPort: profile.wgPort,
      );
      _profiles[existing] = stored;
    } else {
      stored = profile;
      _profiles.add(stored);
    }
    if (activate || _activeId == null) _activeId = stored.id;
    await _persist();
    notifyListeners();
    return stored;
  }

  /// Convenience for pairing flows: builds a profile from a parsed bundle.
  ServerProfile profileFromBundle(PairingBundle bundle, {String? name, String? sshHost, String sshUser = 'ubuntu'}) {
    final label = (name ?? bundle.name).trim();
    return ServerProfile(
      id: _newId(),
      name: label.isEmpty ? kDefaultServerName : label,
      host: bundle.host,
      token: bundle.token,
      wgConfig: bundle.tunnel.toWgQuickConfig(),
      sshHost: sshHost,
      sshUser: sshUser,
      createdAt: DateTime.now(),
    );
  }

  Future<void> rename(String id, String name) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    final clean = name.trim();
    if (i < 0 || clean.isEmpty) return;
    _profiles[i] = _profiles[i].copyWith(name: clean);
    await _persist();
    notifyListeners();
  }

  Future<void> update(ServerProfile profile) async {
    final i = _profiles.indexWhere((p) => p.id == profile.id);
    if (i < 0) return;
    _profiles[i] = profile;
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    if (byId(id) == null || _activeId == id) return;
    _activeId = id;
    await _persist();
    notifyListeners();
  }

  /// Removes a profile. If it was active, the profile that took its place
  /// in the list (or the new last one) becomes active; with none left
  /// [active] is null.
  Future<void> remove(String id) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _profiles.removeAt(i);
    if (_activeId == id) {
      _activeId = _profiles.isEmpty ? null : _profiles[min(i, _profiles.length - 1)].id;
    }
    await _persist();
    notifyListeners();
  }
}

bool _tunnelUp(WireGuardController wg) => wg.status == TunnelStatus.connected || wg.status == TunnelStatus.connecting;

/// Points the app at [profile]: brings down the current tunnel, installs the
/// profile's tunnel config, re-points [ArchangeldConnection], and (when
/// [connectTunnel]) brings the new tunnel up. Only one tunnel can exist at
/// a time, so the old one is always disconnected first.
Future<void> activateProfile(
  ServerProfile profile, {
  required WireGuardController wg,
  required ArchangeldConnection backend,
  bool connectTunnel = true,
}) async {
  if (_tunnelUp(wg)) await wg.disconnect();
  if (profile.wgConfig.trim().isNotEmpty) {
    await wg.pair(profile.wgConfig);
  } else {
    // Don't leave the previous server's tunnel config behind while the
    // backend points at this one.
    await wg.unpair();
  }
  await backend.pair(host: profile.host, token: profile.token);
  if (connectTunnel && profile.wgConfig.trim().isNotEmpty) {
    await wg.connect();
  }
}

/// Adds the server described by [bundle] to [registry], makes it active and
/// points the app at it. The tunnel is reconnected only if one was up (a
/// first pairing keeps the existing "pair, then connect from Settings"
/// behaviour; adding a second server while connected moves the tunnel).
/// If activation fails the registry and the live connection are put back
/// as they were, and the error is rethrown.
Future<ServerProfile> pairNewServer({
  required ServerRegistry registry,
  required WireGuardController wg,
  required ArchangeldConnection backend,
  required PairingBundle bundle,
  String? name,
  String? sshHost,
  String sshUser = 'ubuntu',
}) async {
  final wasUp = _tunnelUp(wg);
  final before = registry.profiles;
  final beforeActiveId = registry.activeId;
  final previous = registry.active;
  final stored = await registry.add(registry.profileFromBundle(bundle, name: name, sshHost: sshHost, sshUser: sshUser));
  try {
    await activateProfile(stored, wg: wg, backend: backend, connectTunnel: wasUp);
  } catch (_) {
    try {
      await registry.restore(before, beforeActiveId);
    } catch (_) {}
    await _restoreConnection(previous, wg: wg, backend: backend, connectTunnel: wasUp);
    rethrow;
  }
  return stored;
}

/// Best effort: bring the live connection back to [previous], or clear it
/// when there was none, so no half-applied pairing stays live.
Future<void> _restoreConnection(
  ServerProfile? previous, {
  required WireGuardController wg,
  required ArchangeldConnection backend,
  required bool connectTunnel,
}) async {
  try {
    if (previous != null) {
      await activateProfile(previous, wg: wg, backend: backend, connectTunnel: connectTunnel);
    } else {
      await _clearPairing(wg: wg, backend: backend);
    }
  } catch (_) {
    // Best effort; the original failure is what the caller needs.
  }
}

Future<void> _clearPairing({required WireGuardController wg, required ArchangeldConnection backend}) async {
  try {
    await backend.unpair();
  } catch (_) {}
  try {
    await wg.unpair();
  } catch (_) {}
}

/// Switches to the already-known profile [id]. The tunnel is brought up on
/// the new server only if it was up before.
Future<void> switchToServer(
  String id, {
  required ServerRegistry registry,
  required WireGuardController wg,
  required ArchangeldConnection backend,
}) async {
  final profile = registry.byId(id);
  if (profile == null) return;
  final previous = registry.active;
  final wasUp = _tunnelUp(wg);
  await registry.setActive(id);
  try {
    await activateProfile(profile, wg: wg, backend: backend, connectTunnel: wasUp);
  } catch (_) {
    // Bringing the new server up failed: go back to the one that was
    // working rather than leaving the registry pointing at a server the
    // app isn't actually connected to.
    if (previous != null && previous.id != id) {
      try {
        await registry.setActive(previous.id);
      } catch (_) {}
      await _restoreConnection(previous, wg: wg, backend: backend, connectTunnel: wasUp);
    }
    rethrow;
  }
}

/// Forgets the active server on this device ("Unpair"). If another profile
/// remains it becomes active and its tunnel is brought up (if one was up);
/// with none left the pairing is cleared entirely so the root router shows
/// the setup landing. If activating the next server fails the removal
/// stays, the live pairing is cleared so no stale credentials remain, and
/// the error is rethrown.
Future<void> removeActiveServer({
  required ServerRegistry registry,
  required WireGuardController wg,
  required ArchangeldConnection backend,
}) async {
  final wasUp = _tunnelUp(wg);
  final current = registry.active;
  if (current != null) await registry.remove(current.id);
  final next = registry.active;
  if (next == null) {
    await backend.unpair();
    await wg.unpair();
  } else {
    try {
      await activateProfile(next, wg: wg, backend: backend, connectTunnel: wasUp);
    } catch (_) {
      await _clearPairing(wg: wg, backend: backend);
      rethrow;
    }
  }
}
