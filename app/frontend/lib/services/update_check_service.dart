import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_kv_store.dart';

import 'build_config.dart';

export 'build_config.dart' show kGithubRepoSlug;

const _kManifestAssetName = 'version-manifest.json';
const _kCacheMaxAge = Duration(hours: 24);

const _kCacheKey = 'update_check_cache';
final _store = LocalKvStore.instance;

/// Checks GitHub's latest release for whether a newer Archangel/App/
/// Backend version has shipped, by fetching that release's
/// `version-manifest.json` asset (produced by .github/workflows/release.yml
/// - see its per-component freeze logic for why a partial (-b/-f) release
/// never bumps the other two components' numbers). Talks to the public
/// internet (api.github.com), not the WireGuard tunnel - unlike every
/// other backend call in this app.
class UpdateCheckService extends ChangeNotifier {
  UpdateCheckService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  String? _latestArchangel;
  String? get latestArchangel => _latestArchangel;

  String? _latestFrontend;
  String? get latestFrontend => _latestFrontend;

  String? _latestBackend;
  String? get latestBackend => _latestBackend;

  /// The tag whose release assets actually carry the current backend
  /// binary - NOT necessarily the same as the latest release's own tag,
  /// since [latestBackend] can be frozen (unchanged) across several
  /// releases in a row (see release.yml's freeze logic). This is what
  /// BackendUpdateService downloads from - `releases/latest/download/`
  /// would silently 404 on a release that didn't touch the backend.
  String? _backendTag;
  String? get backendTag => _backendTag;

  /// The GitHub Releases page URL for the release the current manifest
  /// came from - what an "update available" badge links to.
  String? _releaseUrl;
  String? get releaseUrl => _releaseUrl;

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
      _latestArchangel = data['archangel'] as String?;
      _latestFrontend = data['frontend'] as String?;
      _latestBackend = data['backend'] as String?;
      _backendTag = data['backendTag'] as String?;
      _releaseUrl = data['releaseUrl'] as String?;
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
      _latestArchangel = manifest['archangel'] as String?;
      _latestFrontend = manifest['frontend'] as String?;
      _latestBackend = manifest['backend'] as String?;
      _backendTag = manifest['backend_tag'] as String?;
      _releaseUrl = release['html_url'] as String?;
      _lastChecked = DateTime.now();

      await _store.write(
        _kCacheKey,
        jsonEncode({
          'archangel': _latestArchangel,
          'frontend': _latestFrontend,
          'backend': _latestBackend,
          'backendTag': _backendTag,
          'releaseUrl': _releaseUrl,
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
