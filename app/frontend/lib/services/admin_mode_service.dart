import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_error.dart';
import 'archangeld_connection.dart';

/// Admin mode = the archangel user's passwordless sudo on the server. It
/// can be switched OFF from the app; switching it back ON needs SSH (see
/// VpsSetupService.enableAdminMode), so this service only exposes
/// [disable] and a [refresh] to pick up the change afterwards.
class AdminModeService extends ChangeNotifier {
  AdminModeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  ArchangeldConnection? _backend;

  /// Null until the first successful status fetch.
  bool? _enabled;
  bool? get enabled => _enabled;

  String? _sudoersPath;
  String? get sudoersPath => _sudoersPath;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    refresh();
  }

  /// Drops state from the previous server (server switch).
  void reset() {
    _enabled = null;
    _sudoersPath = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _enabled = null;
      _sudoersPath = null;
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final res = await _client.get(
        backend.adminModeHttpUri(),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        _apply(jsonDecode(res.body));
        _error = null;
      } else {
        _error = serverMessage(res, 'Could not read Admin mode (HTTP ${res.statusCode})');
      }
    } catch (e) {
      debugPrint('Error fetching admin mode: $e');
      _error = 'Could not reach the backend: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _apply(Object? decoded) {
    if (decoded is! Map) throw const FormatException('Unexpected admin-mode response');
    final enabled = decoded['enabled'];
    if (enabled is! bool) throw const FormatException('Admin-mode response has no "enabled" flag');
    _enabled = enabled;
    final path = decoded['sudoers_path'];
    _sudoersPath = path is String ? path : null;
  }

  /// Turns Admin mode off. The server rejects turning it on (409) - that
  /// has to go over SSH.
  Future<ApiActionResult> disable() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return const ApiActionResult(success: false, message: 'Not connected to backend');
    }
    try {
      final res = await _client.post(
        backend.adminModeHttpUri(),
        headers: {'X-Archangel-Token': backend.token!, 'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': false}),
      );
      if (res.statusCode == 200) {
        try {
          _apply(jsonDecode(res.body));
        } catch (_) {
          await refresh();
        }
        _error = null;
        notifyListeners();
        return const ApiActionResult(success: true, message: 'Admin mode is off');
      }
      return ApiActionResult(success: false, message: serverMessage(res, 'Could not turn off Admin mode (HTTP ${res.statusCode})'));
    } catch (e) {
      debugPrint('Error disabling admin mode: $e');
      return ApiActionResult(success: false, message: 'Could not reach the backend: $e');
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
