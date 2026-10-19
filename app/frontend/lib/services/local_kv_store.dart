import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

/// A plain local-file key/value store, replacing flutter_secure_storage
/// for app state that isn't sensitive enough to need passphrase-derived
/// encryption (see ssh_credentials.dart / credential_crypto.dart for the
/// one thing that is: the SSH private key that grants root on the VPS).
///
/// This holds things like the paired host/token and the WireGuard
/// tunnel config - real secrets, but ones the app needs on every launch
/// to function at all, so gating them behind a passphrase prompt every single
/// time would be worse than what this replaces. flutter_secure_storage
/// on macOS is a thin wrapper over Keychain Services, which requires a
/// stable code-signing entitlement (Keychain Sharing, set up via Xcode)
/// to avoid re-prompting on every read; without it, EVERY separate key
/// read at startup (host, token, wg config, update-check cache - four
/// separate reads, each its own Keychain transaction) was its own
/// native macOS password prompt. Moving this data to one plain JSON
/// file removes the Keychain dependency, and with it every one of those
/// prompts - the file is protected the same way any other file in the
/// user's home directory is (OS login + disk encryption like FileVault,
/// not a second app-level secret).
class LocalKvStore {
  LocalKvStore._(this._fileName);

  final String _fileName;
  Map<String, String>? _cache;

  static final LocalKvStore instance = LocalKvStore._('archangel_app_state.json');

  /// Test seam: when set, the store lives in this directory instead of the
  /// path_provider application support directory (which has no platform
  /// channel under `flutter test`).
  @visibleForTesting
  static Future<Directory> Function()? directoryOverride;

  /// Test seam: drops the in-memory cache so the next access re-reads the
  /// backing file (or starts empty if the override directory changed).
  @visibleForTesting
  void resetForTesting() => _cache = null;

  Future<File> _file() async {
    final dir = await (directoryOverride?.call() ?? getApplicationSupportDirectory());
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final file = await _file();
    if (!await file.exists()) {
      _cache = {};
      return _cache!;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _cache = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // Corrupted/unreadable - start fresh rather than crash the app on
      // launch over stale local state that can just be re-paired.
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(jsonEncode(_cache ?? {}), flush: true);
    // The file holds the auth token and WireGuard private key: restrict it
    // to the owner. Best effort; failures are ignored.
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  Future<String?> read(String key) async => (await _load())[key];

  Future<void> write(String key, String value) async {
    final map = await _load();
    map[key] = value;
    await _persist();
  }

  Future<void> delete(String key) async {
    final map = await _load();
    if (map.remove(key) != null) await _persist();
  }
}
