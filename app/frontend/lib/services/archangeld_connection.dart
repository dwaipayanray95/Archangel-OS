import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_kv_store.dart';

/// Storage keys of the active server's pairing (also read by ServerRegistry's
/// migration of pre-multi-server installs).
const kArchangeldHostKey = 'archangeld_host';
const kArchangeldTokenKey = 'archangeld_token';
final _store = LocalKvStore.instance;

/// The archangeld connection details: host:port (reachable only over the
/// WireGuard tunnel - see WIREGUARD.md) and the single auth token from
/// `archangeld gen-token`. Stored in the local app-state file (see
/// local_kv_store.dart's doc comment for why this isn't Keychain-backed)
/// rather than plaintext prefs.
class ArchangeldConnection extends ChangeNotifier {
  ArchangeldConnection({http.Client? client}) : _client = client;

  /// Injected in tests; null means the plain top-level `http` functions.
  final http.Client? _client;

  Future<http.Response> _get(Uri uri, Duration timeout) =>
      (_client == null ? http.get(uri) : _client.get(uri)).timeout(timeout);

  /// Result of the latest [checkReachable]: true = the server answered
  /// /api/v1/health, false = it did not, null = not checked yet since the
  /// pairing last changed.
  bool? _reachable;
  bool? get reachable => _reachable;

  /// Consecutive failed [checkReachable] calls.
  int _healthFailures = 0;
  int get healthFailures => _healthFailures;

  Future<void>? _healthInFlight;

  /// Asks the server's unauthenticated /api/v1/health whether it is
  /// reachable right now (through any tunnel - ours or the OS WireGuard
  /// app's). Short timeout; never throws. Calls made while one is running
  /// share its result.
  Future<void> checkReachable({Duration timeout = const Duration(seconds: 3)}) {
    if (!isPaired) return Future.value();
    return _healthInFlight ??= _checkReachable(timeout).whenComplete(() => _healthInFlight = null);
  }

  Future<void> _checkReachable(Duration timeout) async {
    final asked = _host;
    bool ok = false;
    try {
      final res = await _get(healthHttpUri(), timeout);
      ok = res.statusCode == 200;
      if (ok) {
        try {
          final v = (jsonDecode(res.body) as Map<String, dynamic>)['version'];
          if (v is String && v.isNotEmpty) _backendVersion = v;
        } catch (_) {}
      }
    } catch (_) {
      ok = false;
    }
    if (_host != asked) return; // re-paired while the request was in flight
    final changed = _reachable != ok;
    _reachable = ok;
    _healthFailures = ok ? 0 : _healthFailures + 1;
    if (changed || !ok) notifyListeners();
  }

  void _resetReachability() {
    _reachable = null;
    _healthFailures = 0;
  }

  String? _host;
  String? get host => _host;

  String? _token;
  String? get token => _token;

  bool get isPaired => _host != null && _token != null;

  /// The backend's reported version (from /api/v1/health), refreshed by
  /// [refreshBackendVersion]. Null until that succeeds at least once -
  /// this is a purely informational field for the Settings screen, so a
  /// fetch failure just leaves it null rather than surfacing an error.
  String? _backendVersion;
  String? get backendVersion => _backendVersion;

  bool _backendChecking = false;
  bool get backendChecking => _backendChecking;

  String? _backendVersionError;
  String? get backendVersionError => _backendVersionError;

  bool _loaded = false;

  /// True once [load] has finished reading storage - see
  /// WireGuardController.isBootstrapped for why the root router needs
  /// this rather than just checking [isPaired] immediately.
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _host = await _store.read(kArchangeldHostKey);
    _token = await _store.read(kArchangeldTokenKey);
    _loaded = true;
    notifyListeners();
    if (isPaired) {
      unawaited(refreshBackendVersion());
    }
  }

  Future<void> pair({required String host, required String token}) async {
    final cleanHost = host.trim();
    final cleanToken = token.trim();
    if (cleanHost.isEmpty) throw const FormatException('Host is required');
    if (cleanToken.isEmpty) throw const FormatException('Token is required');

    await _store.write(kArchangeldHostKey, cleanHost);
    await _store.write(kArchangeldTokenKey, cleanToken);
    _host = cleanHost;
    _token = cleanToken;
    _resetReachability();
    notifyListeners();
    unawaited(refreshBackendVersion());
  }

  Future<void> unpair() async {
    await _store.delete(kArchangeldHostKey);
    await _store.delete(kArchangeldTokenKey);
    _host = null;
    _token = null;
    _backendVersion = null;
    _resetReachability();
    notifyListeners();
  }

  /// `http://<host>/api/v1/health` - unauthenticated, so this is usable
  /// without a token; the health endpoint itself needs none.
  Uri healthHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/health');
  }

  /// Fetches the backend's version from /api/v1/health and caches it.
  /// Sets error state if backend is unreachable (e.g. WireGuard tunnel down).
  Future<void> refreshBackendVersion() async {
    if (!isPaired) return;
    _backendChecking = true;
    _backendVersionError = null;
    notifyListeners();

    try {
      final res = await _get(healthHttpUri(), const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final v = data['version'] as String?;
        if (v != null && v.isNotEmpty) {
          _backendVersion = v;
          _backendVersionError = null;
        }
      } else {
        _backendVersionError = 'HTTP ${res.statusCode}';
      }
    } on TimeoutException {
      _backendVersionError = 'tunnel offline';
    } catch (e) {
      _backendVersionError = 'offline';
    } finally {
      _backendChecking = false;
      notifyListeners();
    }
  }

  /// `ws://<host>/ws/terminal?token=...` - plain ws, not wss: archangeld
  /// doesn't terminate TLS itself (see backend README), it relies on the
  /// WireGuard tunnel for transport encryption instead.
  ///
  /// [session] names the persistent tmux session to attach to (created on
  /// first use); the backend defaults to "main".
  Uri terminalWsUri({String? session}) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/terminal').replace(queryParameters: {
      'token': _token,
      if (session != null) 'session': session,
    });
  }

  /// `ws://<host>/ws/stats?token=...` - real-time metrics stream.
  Uri statsWsUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/stats').replace(queryParameters: {'token': _token});
  }

  /// `http://<host>/api/v1/system/metrics`
  Uri metricsHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/metrics');
  }

  /// `http://<host>/api/v1/system/processes`
  Uri processesHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes');
  }

  /// `http://<host>/api/v1/system/processes/{pid}/kill`
  Uri processKillHttpUri(int pid) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes/$pid/kill');
  }

  /// `http://<host>/api/v1/system/processes/{pid}/renice`
  Uri processReniceHttpUri(int pid) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/processes/$pid/renice');
  }

  /// `http://<host>/api/v1/system/reboot`
  Uri systemRebootHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/reboot');
  }

  /// `http://<host>/api/v1/files/list?path=...`
  Uri filesListHttpUri(String path) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/list').replace(queryParameters: {'path': path});
  }

  /// `http://<host>/api/v1/files/read?path=...&lines=...`
  Uri filesReadHttpUri(String path, {int lines = 300}) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/read').replace(queryParameters: {
      'path': path,
      'lines': lines.toString(),
    });
  }

  /// `http://<host>/api/v1/files/download?path=...`
  Uri filesDownloadHttpUri(String path) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/files/download').replace(queryParameters: {'path': path});
  }

  /// `http://<host>/api/v1/docker/containers`
  Uri dockerContainersHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/docker/containers');
  }

  /// `http://<host>/api/v1/docker/containers/{id}/{action}`
  Uri dockerContainerActionHttpUri(String id, String action) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/docker/containers/$id/$action');
  }

  /// `ws://<host>/ws/docker/containers/{id}/logs?token=...`
  Uri dockerContainerLogsWsUri(String id) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('ws://$_host/ws/docker/containers/$id/logs').replace(queryParameters: {'token': _token});
  }

  /// `http://<host>/api/v1/devops/services`
  Uri devopsServicesHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/services');
  }

  /// `http://<host>/api/v1/devops/services/{name}/{action}`
  Uri devopsServiceActionHttpUri(String name, String action) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/services/$name/$action');
  }

  /// `http://<host>/api/v1/devops/scheduled`
  Uri devopsScheduledHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/scheduled');
  }

  /// `http://<host>/api/v1/devops/scheduled/{name}/run`
  Uri devopsScheduledRunHttpUri(String name) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/scheduled/$name/run');
  }

  /// `http://<host>/api/v1/devops/proxy`
  Uri devopsProxyHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/proxy');
  }

  /// `http://<host>/api/v1/devops/proxy/{domain}/test`
  Uri devopsProxyTestHttpUri(String domain) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/proxy/$domain/test');
  }

  /// `http://<host>/api/v1/devops/deployments`
  Uri devopsDeploymentsHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/deployments');
  }

  /// `http://<host>/api/v1/docker/containers/run`
  Uri dockerContainerCreateHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/docker/containers/run');
  }

  /// `http://<host>/api/v1/devops/deployments/{name}/run`
  Uri devopsDeploymentRunHttpUri(String name) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/deployments/$name/run');
  }

  /// `http://<host>/api/v1/devops/deployments`
  Uri devopsDeploymentCreateHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/deployments');
  }

  /// `http://<host>/api/v1/devops/deployments/{name}/content`
  Uri devopsDeploymentContentHttpUri(String name) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/deployments/$name/content');
  }

  /// `http://<host>/api/v1/devops/deployments/{name}`
  Uri devopsDeploymentDeleteHttpUri(String name) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devops/deployments/$name');
  }

  /// `http://<host>/api/v1/terminal/sessions` - GET lists persistent
  /// terminal sessions.
  Uri terminalSessionsHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/terminal/sessions');
  }

  /// `http://<host>/api/v1/terminal/sessions/{name}` - DELETE ends a session.
  Uri terminalSessionHttpUri(String name) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/terminal/sessions/${Uri.encodeComponent(name)}');
  }

  /// `http://<host>/api/v1/devices` - GET lists paired devices.
  Uri devicesHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/devices');
  }

  /// `http://<host>/api/v1/devices` - POST `{"name": "..."}` creates a
  /// device and returns its pairing bundle.
  Uri devicesCreateHttpUri() => devicesHttpUri();

  /// `http://<host>/api/v1/devices/{name}` - DELETE revokes a device.
  Uri deviceHttpUri(String name, {bool self = false}) {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    final uri = Uri.parse('http://$_host/api/v1/devices/${Uri.encodeComponent(name)}');
    return self ? uri.replace(queryParameters: {'self': 'true'}) : uri;
  }

  /// `http://<host>/api/v1/system/admin-mode` - GET status, POST
  /// `{"enabled": false}` to turn sudo off (turning it on needs SSH).
  Uri adminModeHttpUri() {
    if (!isPaired) {
      throw StateError('Not paired with a backend');
    }
    return Uri.parse('http://$_host/api/v1/system/admin-mode');
  }
}
