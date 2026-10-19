import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/container_model.dart';
import 'api_error.dart';
import 'archangeld_connection.dart';

class ContainersService extends ChangeNotifier {
  DockerOverviewModel? _overview;
  DockerOverviewModel? get overview => _overview;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  /// Why the last [triggerAction] failed, in the server's own words when it
  /// gave any (e.g. "Docker is not running on this server"). Null after a
  /// success.
  String? _lastActionMessage;
  String? get lastActionMessage => _lastActionMessage;

  Timer? _pollTimer;
  ArchangeldConnection? _backend;

  // Real-time log streaming state
  String? _activeLogContainerId;
  String? get activeLogContainerId => _activeLogContainerId;

  final List<DockerLogEntry> _liveLogs = [];
  List<DockerLogEntry> get liveLogs => _liveLogs;

  WebSocketChannel? _logWs;
  StreamSubscription? _logSub;

  void init(ArchangeldConnection backend) {
    _backend = backend;
    fetchContainers();

    // Poll periodically (every 4s)
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      fetchContainers();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _closeLogsStream();
    super.dispose();
  }

  Future<void> fetchContainers() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _overview = const DockerOverviewModel(
        dockerAvailable: false,
        engineVersion: 'disconnected',
        runningCount: 0,
        stoppedCount: 0,
        totalImagesSize: '0 B',
        containers: [],
        stacks: [],
        stackMeta: {},
      );
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final res = await http.get(
        backend.dockerContainersHttpUri(),
        headers: {'X-Archangel-Token': backend.token!},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _overview = DockerOverviewModel.fromJson(data);
        _error = null;
      } else {
        _error = serverMessage(res, 'Failed to fetch containers (HTTP ${res.statusCode})');
        _overview ??= const DockerOverviewModel(
          dockerAvailable: false,
          engineVersion: 'unreachable',
          runningCount: 0,
          stoppedCount: 0,
          totalImagesSize: '0 B',
          containers: [],
          stacks: [],
          stackMeta: {},
        );
      }
    } catch (e) {
      debugPrint('Error fetching docker containers: $e');
      _error = e.toString();
      _overview ??= const DockerOverviewModel(
        dockerAvailable: false,
        engineVersion: 'unreachable',
        runningCount: 0,
        stoppedCount: 0,
        totalImagesSize: '0 B',
        containers: [],
        stacks: [],
        stackMeta: {},
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> triggerAction(String containerId, String action) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return false;
    }

    try {
      final res = await http.post(
        backend.dockerContainerActionHttpUri(containerId, action),
        headers: {'X-Archangel-Token': backend.token!},
      );

      fetchContainers();
      _lastActionMessage = res.statusCode == 200 ? null : serverMessage(res, 'Failed to $action container.');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('Error triggering container action: $e');
      _lastActionMessage = 'Could not reach the backend: $e';
      return false;
    }
  }

  Future<Map<String, dynamic>> createContainer({
    required String image,
    String? name,
    List<String>? ports,
    List<String>? env,
    String? restart,
    List<String>? volumes,
  }) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      return {'success': false, 'message': 'Not connected to backend'};
    }

    try {
      final payload = {
        'image': image,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (ports != null && ports.isNotEmpty) 'ports': ports,
        if (env != null && env.isNotEmpty) 'env': env,
        if (restart != null && restart.isNotEmpty) 'restart': restart,
        if (volumes != null && volumes.isNotEmpty) 'volumes': volumes,
      };

      final res = await http.post(
        backend.dockerContainerCreateHttpUri(),
        headers: {
          'Content-Type': 'application/json',
          'X-Archangel-Token': backend.token!,
        },
        body: jsonEncode(payload),
      );

      // Error bodies (e.g. 503 "Docker is not running") may not carry the
      // full success/message shape, so don't assume it.
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
      fetchContainers();
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? serverMessage(res, res.statusCode == 200 ? 'Container created' : 'Failed to create container'),
      };
    } catch (e) {
      debugPrint('Error creating container: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<bool> removeContainer(String containerId) async {
    return triggerAction(containerId, 'remove');
  }

  void startLogStream(String containerId) {
    _closeLogsStream();
    _activeLogContainerId = containerId;
    _liveLogs.clear();
    notifyListeners();

    final backend = _backend;
    if (backend == null || !backend.isPaired || backend.token == null) {
      _liveLogs.add(DockerLogEntry(
        ts: DateTime.now().toIso8601String().substring(11, 19),
        level: 'INFO',
        source: 'archangeld',
        text: 'Waiting for backend connection to stream container logs...',
      ));
      notifyListeners();
      return;
    }

    try {
      final uri = backend.dockerContainerLogsWsUri(containerId);
      _logWs = WebSocketChannel.connect(uri);
      _logSub = _logWs!.stream.listen((event) {
        try {
          final data = jsonDecode(event.toString()) as Map<String, dynamic>;
          final entry = DockerLogEntry.fromJson(data);
          _liveLogs.add(entry);
          if (_liveLogs.length > 500) {
            _liveLogs.removeAt(0);
          }
          notifyListeners();
        } catch (_) {}
      }, onError: (err) {
        debugPrint('Log WS error: $err');
      });
    } catch (e) {
      debugPrint('Log connect error: $e');
    }
  }

  void stopLogStream() {
    _closeLogsStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void _closeLogsStream() {
    _logSub?.cancel();
    _logSub = null;
    _logWs?.sink.close();
    _logWs = null;
    _activeLogContainerId = null;
  }
}
