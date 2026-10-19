import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/devops_model.dart';
import 'api_error.dart';
import 'archangeld_connection.dart';

class DevopsService extends ChangeNotifier {
  List<DevRowModel> _services = [];
  List<DevRowModel> get services => _services;

  List<DevRowModel> _scheduled = [];
  List<DevRowModel> get scheduled => _scheduled;

  List<DevRowModel> _proxy = [];
  List<DevRowModel> get proxy => _proxy;

  List<DevRowModel> _deployments = [];
  List<DevRowModel> get deployments => _deployments;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Why the last [triggerServiceAction] / [triggerScheduled] failed, in the
  /// server's own words when it gave any (e.g. "Admin mode is off - this
  /// action needs it"). Null after a success.
  String? _lastActionMessage;
  String? get lastActionMessage => _lastActionMessage;

  /// HTTP status of the last failed action (403 = admin mode off, 409/400 =
  /// the server's stop guard, ...). Null after a success or no response.
  int? _lastActionStatus;
  int? get lastActionStatus => _lastActionStatus;

  /// True once the first fetch has finished (successfully or not), so the UI
  /// can tell "still loading" from "nothing here".
  bool _loaded = false;
  bool get hasLoaded => _loaded;

  Timer? _pollTimer;
  ArchangeldConnection? _backend;

  bool _active = true;
  bool get active => _active;

  /// Pauses or resumes polling; the app shell keeps this on only while a
  /// destination that shows services is visible.
  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (_backend != null) {
      _startPolling();
    }
  }

  void init(ArchangeldConnection backend) {
    _backend = backend;
    if (_active) _startPolling();
  }

  void _startPolling() {
    fetchAll();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchAll();
    });
  }

  /// Drops everything loaded from the previous server (server switch).
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _services = [];
    _scheduled = [];
    _proxy = [];
    _deployments = [];
    _loading = false;
    _loaded = false;
    _error = null;
    _lastActionMessage = null;
    _lastActionStatus = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchAll() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _services = [];
      _scheduled = [];
      _proxy = [];
      _deployments = [];
      _loading = false;
      _loaded = true;
      notifyListeners();
      return;
    }

    try {
      final headers = {'X-Archangel-Token': backend.token!};

      // Fetch all 4 sections in parallel for optimal responsiveness
      final results = await Future.wait([
        http.get(backend.devopsServicesHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsScheduledHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsProxyHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
        http.get(backend.devopsDeploymentsHttpUri(), headers: headers).catchError((_) => http.Response('[]', 500)),
      ]);

      var anyFailed = false;

      final svcRes = results[0];
      if (svcRes.statusCode == 200) {
        final decoded = jsonDecode(svcRes.body);
        if (decoded is List) {
          _services = decoded.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        anyFailed = true;
      }

      final schedRes = results[1];
      if (schedRes.statusCode == 200) {
        final decoded = jsonDecode(schedRes.body);
        if (decoded is List) {
          _scheduled = decoded.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        anyFailed = true;
      }

      final proxyRes = results[2];
      if (proxyRes.statusCode == 200) {
        final decoded = jsonDecode(proxyRes.body);
        if (decoded is List) {
          _proxy = decoded.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        anyFailed = true;
      }

      final depRes = results[3];
      if (depRes.statusCode == 200) {
        final decoded = jsonDecode(depRes.body);
        if (decoded is List) {
          _deployments = decoded.map((e) => DevRowModel.fromJson(e as Map<String, dynamic>)).toList();
        }
      } else {
        anyFailed = true;
      }

      // catchError above turns a network failure into a fake 500 response
      // rather than throwing, so Future.wait never rejects on its own - a
      // fully-unreachable backend must still surface as an error here
      // instead of silently leaving stale/empty data with no indication
      // anything went wrong.
      _error = anyFailed ? 'Failed to reach the backend for one or more DevOps sections.' : null;
    } catch (e) {
      debugPrint('Error fetching devops data: $e');
      _error = e.toString();
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  Future<bool> triggerServiceAction(String name, String action) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return false;

    try {
      final res = await http.post(
        backend.devopsServiceActionHttpUri(name, action.toLowerCase()),
        headers: {'X-Archangel-Token': backend.token!},
      );
      fetchAll();
      _lastActionMessage = res.statusCode == 200 ? null : serverMessage(res, 'Failed to $action $name.');
      _lastActionStatus = res.statusCode == 200 ? null : res.statusCode;
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering service action: $e');
      _lastActionMessage = 'Could not reach the backend: $e';
      _lastActionStatus = null;
      return false;
    }
  }

  Future<bool> triggerScheduled(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return false;

    try {
      final res = await http.post(
        backend.devopsScheduledRunHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      fetchAll();
      _lastActionMessage = res.statusCode == 200 ? null : serverMessage(res, 'Failed to trigger $name.');
      _lastActionStatus = res.statusCode == 200 ? null : res.statusCode;
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering scheduled timer: $e');
      _lastActionMessage = 'Could not reach the backend: $e';
      _lastActionStatus = null;
      return false;
    }
  }

  Future<String?> testProxy(String domain) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return null;

    try {
      final res = await http.post(
        backend.devopsProxyTestHttpUri(domain),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['message'] as String?;
      }
    } catch (e) {
      debugPrint('Error testing proxy: $e');
    }
    return null;
  }

  Future<Map<String, String>?> runDeployment(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return null;

    try {
      final res = await http.post(
        backend.devopsDeploymentRunHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      Map<String, dynamic> data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        data = {'message': serverMessage(res, 'The script could not be run.')};
      }
      fetchAll();
      return {
        'ok': res.statusCode == 200 ? 'true' : 'false',
        'message': data['message'] as String? ?? (res.statusCode == 200 ? 'Success' : 'Failed'),
        'output': data['output'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('Error running deployment: $e');
      return {'ok': 'false', 'message': 'Could not reach your server: $e', 'output': ''};
    }
  }

  Future<Map<String, dynamic>> saveDeployment(String name, String content) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return {'success': false, 'message': 'Not connected to backend'};
    }

    try {
      final res = await http.post(
        backend.devopsDeploymentCreateHttpUri(),
        headers: {
          'Content-Type': 'application/json',
          'X-Archangel-Token': backend.token!,
        },
        body: jsonEncode({
          'name': name,
          'content': content,
        }),
      );
      fetchAll();
      String message = res.statusCode == 200 ? 'Success' : 'Failed to save script';
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('message')) {
          message = data['message'] as String;
        }
      } catch (_) {}
      return {
        'success': res.statusCode == 200,
        'message': message,
      };
    } catch (e) {
      debugPrint('Error saving deployment: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<String?> getDeploymentContent(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return null;

    try {
      final res = await http.get(
        backend.devopsDeploymentContentHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['content'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching deployment content: $e');
    }
    return null;
  }

  Future<bool> deleteDeployment(String name) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) return false;

    try {
      final res = await http.delete(
        backend.devopsDeploymentDeleteHttpUri(name),
        headers: {'X-Archangel-Token': backend.token!},
      );
      fetchAll();
      _lastActionMessage = res.statusCode == 200 ? null : serverMessage(res, 'Failed to delete $name.');
      _lastActionStatus = res.statusCode == 200 ? null : res.statusCode;
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error deleting deployment: $e');
      _lastActionMessage = 'Could not reach the backend: $e';
      _lastActionStatus = null;
      return false;
    }
  }
}
