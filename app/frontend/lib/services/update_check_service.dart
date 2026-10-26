import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_version.dart';
import 'local_kv_store.dart';
import 'semver.dart';

import 'build_config.dart';

export 'build_config.dart' show kGithubRepoSlug;

const _kManifestAssetName = 'version-manifest.json';
const _kCacheMaxAge = Duration(hours: 24);

const _kCacheKey = 'update_check_cache';
final _store = LocalKvStore.instance;

/// What a release's `version-manifest.json` says. One version for the whole
/// product: `{"version": "0.8.0", "build": 2, "tag": "v0.8.0"}`.
///
/// Manifests from before the single version only carry `archangel`,
/// `frontend`, `backend`, `frontend_tag` and `backend_tag`. Those still
/// parse: the app compares against `frontend`, the server against
/// `backend`, and downloads come from `backend_tag`. (Current releases write
/// the legacy keys too, all set to the one version, so apps that shipped
/// before this change still see the update.)
class UpdateManifest {
  const UpdateManifest({required this.version, this.build, this.tag, this.appVersion, this.serverVersion});

  /// The headline version to show ("0.8.0").
  final String? version;
  final int? build;

  /// The release tag the server program is downloaded from ("v0.8.0").
  final String? tag;

  /// What the app / server program is compared against. The same as
  /// [version] for a current manifest.
  final String? appVersion;
  final String? serverVersion;

  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final single = _str(json['version']);
    final legacyApp = _str(json['frontend']) ?? _str(json['archangel']);
    final legacyServer = _str(json['backend']) ?? _str(json['archangel']);
    final b = json['build'];
    return UpdateManifest(
      version: single ?? _str(json['archangel']) ?? legacyApp,
      build: b is int ? b : (b is String ? int.tryParse(b) : null),
      tag: _str(json['tag']) ?? _str(json['backend_tag']) ?? _str(json['backendTag']) ?? _str(json['frontend_tag']),
      appVersion: single ?? legacyApp,
      serverVersion: single ?? legacyServer,
    );
  }
}

/// Checks GitHub's latest release for whether a newer Archangel OS has
/// shipped, by fetching that release's `version-manifest.json` asset
/// (produced by .github/workflows/release.yml). There is one version for
/// the app and the server program. Talks to the public internet
/// (api.github.com), not the WireGuard tunnel - unlike every other backend
/// call in this app.
class UpdateCheckService extends ChangeNotifier {
  UpdateCheckService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  UpdateManifest? _manifest;

  /// The newest Archangel OS version, e.g. "0.9.0".
  String? get latestVersion => _manifest?.version;

  /// The newest build number (null for old-style manifests).
  int? get latestBuild => _manifest?.build;

  /// The release tag to download the server program from ("v0.9.0"). Not
  /// necessarily "latest" on GitHub's side - see BackendUpdateService.
  String? get releaseTag => _manifest?.tag;

  /// True when this app is older than the newest release.
  bool get appBehind => isUpdateAvailable(current: AppVersion.current, latest: _manifest?.appVersion);

  /// True when the connected server program ([serverVersion], null if
  /// unknown) is older than the newest release.
  bool serverBehind(String? serverVersion) => isUpdateAvailable(current: serverVersion, latest: _manifest?.serverVersion);

  /// The one notion of "update available": the app OR the connected server
  /// is older than the newest release.
  bool updateAvailable({String? serverVersion}) => appBehind || serverBehind(serverVersion);

  /// The GitHub Releases page URL for the release the current manifest
  /// came from - what an "update available" badge links to.
  String? _releaseUrl;
  String? get releaseUrl => _releaseUrl;

  /// The markdown/text release notes published with the latest release on GitHub.
  String? _releaseNotes;
  String? get releaseNotes => _releaseNotes;

  /// The title or name of the latest release on GitHub (e.g. "Archangel OS 0.9.0").
  String? _releaseName;
  String? get releaseName => _releaseName;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  bool _checking = false;
  bool get checking => _checking;

  /// Restores the last cached check (if any) from local storage, so a
  /// fresh app launch doesn't show "no update info" before the first
  /// network round trip completes.
  Future<void> loadCache() async {
    try {
      final raw = await _store.read(_kCacheKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      // The cache holds the manifest's own keys, so old and new caches parse alike.
      final m = data['manifest'];
      _manifest = UpdateManifest.fromJson(m is Map ? Map<String, dynamic>.from(m) : data);
      _releaseUrl = data['releaseUrl'] as String?;
      _releaseNotes = data['releaseNotes'] as String?;
      _releaseName = data['releaseName'] as String?;
      final checkedAt = data['checkedAt'] as String?;
      if (checkedAt != null) _lastChecked = DateTime.tryParse(checkedAt);
      notifyListeners();
    } catch (_) {
      // corrupt/unreadable cache - just start fresh, not fatal
    }
  }

  /// Fetches the latest release's version manifest. No-ops if the cache
  /// is still fresh (under [_kCacheMaxAge]) unless [force] is set (the
  /// manual "check now" path). A failed/offline check leaves whatever
  /// was last known intact - this only ever informs a badge, never
  /// blocks anything, so silently keeping stale-but-real data is better
  /// than nulling it out on a blip.
  Future<void> checkForUpdates({bool force = false}) async {
    if (!force && _lastChecked != null && DateTime.now().difference(_lastChecked!) < _kCacheMaxAge) {
      return;
    }
    if (_checking) return;
    _checking = true;
    notifyListeners();

    try {
      final releaseRes = await _client.get(
        Uri.parse('https://api.github.com/repos/$kGithubRepoSlug/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      );
      if (releaseRes.statusCode != 200) return;

      final release = jsonDecode(releaseRes.body) as Map<String, dynamic>;
      final assets = (release['assets'] as List<dynamic>?) ?? const [];
      final manifestAsset = assets.cast<Map<String, dynamic>>().where((a) => a['name'] == _kManifestAssetName).firstOrNull;
      if (manifestAsset == null) return;

      final manifestUrl = manifestAsset['browser_download_url'] as String?;
      if (manifestUrl == null) return;

      final manifestRes = await _client.get(Uri.parse(manifestUrl));
      if (manifestRes.statusCode != 200) return;

      final manifest = jsonDecode(manifestRes.body) as Map<String, dynamic>;
      _manifest = UpdateManifest.fromJson(manifest);
      _releaseUrl = release['html_url'] as String?;
      _releaseNotes = release['body'] as String?;
      _releaseName = release['name'] as String?;
      _lastChecked = DateTime.now();

      await _store.write(
        _kCacheKey,
        jsonEncode({
          'manifest': manifest,
          'releaseUrl': _releaseUrl,
          'releaseNotes': _releaseNotes,
          'releaseName': _releaseName,
          'checkedAt': _lastChecked!.toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      // leave previous values in place
    } finally {
      _checking = false;
      notifyListeners();
    }
  }
}
