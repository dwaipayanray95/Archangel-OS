import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_error.dart';
import 'archangeld_connection.dart';

/// One paired device, as listed by GET /api/v1/devices.
class PairedDevice {
  final String name;
  final DateTime? createdAt;
  final String? tunnelIp;

  /// True for the device making the request (this app).
  final bool current;

  const PairedDevice({required this.name, this.createdAt, this.tunnelIp, this.current = false});

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'];
    final ip = json['tunnel_ip'];
    return PairedDevice(
      name: json['name'] as String? ?? '',
      createdAt: created is String ? DateTime.tryParse(created) : null,
      tunnelIp: ip is String && ip.isNotEmpty ? ip : null,
      current: json['current'] == true,
    );
  }
}

/// Outcome of [DevicesService.create].
class DeviceCreateResult {
  final bool success;
  final String message;
  final String? name;

  /// Base64 pairing code for the new device; only present on success.
  final String? bundle;
  const DeviceCreateResult({required this.success, required this.message, this.name, this.bundle});
}

/// Lists and revokes the devices paired with the backend (the real data
/// behind Settings' device list). Revoking needs Admin mode on server-side;
/// when it's off the backend's 403 message is returned verbatim.
class DevicesService extends ChangeNotifier {
  DevicesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  ArchangeldConnection? _backend;

  List<PairedDevice> _devices = [];
  List<PairedDevice> get devices => _devices;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// True once a fetch has succeeded at least once, so the UI can tell
  /// "no devices" from "haven't loaded".
  bool _loaded = false;
  bool get loaded => _loaded;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    refresh();
  }

  /// Drops state from the previous server (server switch).
  void reset() {
    _devices = [];
    _loaded = false;
    _error = null;
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _devices = [];
      _loaded = false;
      _error = null;
      notifyListeners();
      return;
    }

    _loading = true;
    notifyListeners();
    try {
      final res = await _client.get(
        backend.devicesHttpUri(),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        _devices = decoded is List
            ? decoded.whereType<Map<String, dynamic>>().map(PairedDevice.fromJson).toList()
            : <PairedDevice>[];
        _loaded = true;
        _error = null;
      } else {
        _error = serverMessage(res, 'Could not load devices (HTTP ${res.statusCode})');
      }
    } catch (e) {
      debugPrint('Error fetching devices: $e');
      _error = 'Could not reach the backend: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  static final _nameRule = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.-]{0,31}$');

  /// Whether [name] is acceptable as a new device name (the backend's rule).
  static bool isValidDeviceName(String name) => _nameRule.hasMatch(name);

  /// Plain-language problem with [name], or null when it is fine.
  static String? validateDeviceName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Give the new device a name, like "Maria\'s phone".';
    if (!isValidDeviceName(n)) {
      return 'Use up to 32 letters, numbers, spaces, dots, dashes or underscores, starting with a letter or number.';
    }
    return null;
  }

  /// Creates a pairing code for a new device called [name]. The returned
  /// [DeviceCreateResult.bundle] is shown once - the server doesn't keep it.
  /// Needs Admin mode on the server (403 otherwise, message returned
  /// verbatim); 409 means the name is taken.
  Future<DeviceCreateResult> create(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return const DeviceCreateResult(success: false, message: 'Not connected to your server.');
    }
    final clean = name.trim();
    final problem = validateDeviceName(clean);
    if (problem != null) return DeviceCreateResult(success: false, message: problem);
    try {
      final res = await _client
          .post(
            backend.devicesCreateHttpUri(),
            headers: {'X-Archangel-Token': backend.token!, 'Content-Type': 'application/json'},
            body: jsonEncode({'name': clean}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final bundle = decoded is Map ? decoded['bundle'] : null;
        if (bundle is String && bundle.isNotEmpty) {
          final given = decoded is Map && decoded['name'] is String ? decoded['name'] as String : clean;
          return DeviceCreateResult(success: true, message: 'Created $given.', name: given, bundle: bundle);
        }
        return const DeviceCreateResult(success: false, message: 'The server did not return a pairing code.');
      }
      if (res.statusCode == 409) {
        return DeviceCreateResult(
            success: false, message: serverMessage(res, 'A device called "$clean" already exists. Pick another name.'));
      }
      return DeviceCreateResult(success: false, message: serverMessage(res, 'Could not add the device (HTTP ${res.statusCode})'));
    } catch (e) {
      debugPrint('Error creating device: $e');
      return DeviceCreateResult(success: false, message: 'Could not reach your server: $e');
    }
  }

  /// Revokes [device]. Pass [self] = true only when it is the current
  /// device (the backend refuses that otherwise, since it cuts the
  /// connection the request came over).
  Future<ApiActionResult> revoke(PairedDevice device, {bool self = false}) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return const ApiActionResult(success: false, message: 'Not connected to backend');
    }
    try {
      final res = await _client.delete(
        backend.deviceHttpUri(device.name, self: self),
        headers: {'X-Archangel-Token': backend.token!},
      ).timeout(const Duration(seconds: 15)); // a cut tunnel can hang rather than error
      if (res.statusCode == 200) {
        if (!self) await refresh();
        return ApiActionResult(success: true, message: serverMessage(res, 'Revoked ${device.name}'));
      }
      return ApiActionResult(success: false, message: serverMessage(res, 'Could not revoke ${device.name} (HTTP ${res.statusCode})'));
    } catch (e) {
      debugPrint('Error revoking device: $e');
      if (self) {
        // Revoking this device removes its WireGuard peer while the request
        // is still in flight, so the server's reply usually can't make it
        // back. A dropped connection here almost always means it worked.
        return const ApiActionResult(
          success: true,
          message: 'The connection dropped while revoking this device - the server most likely removed it. '
              'This device has forgotten the pairing.',
        );
      }
      return ApiActionResult(success: false, message: 'Could not reach the backend: $e');
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
