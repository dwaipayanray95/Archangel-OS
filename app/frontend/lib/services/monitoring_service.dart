import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/system_metrics.dart';
import 'api_error.dart';
import 'archangeld_connection.dart';

enum MonitoringStatus { disconnected, connecting, connected, error }

class ProcessActionResult {
  final bool success;
  final String message;

  const ProcessActionResult({required this.success, required this.message});
}

/// Service responsible for real-time and snapshot metrics, plus process listings.
class MonitoringService extends ChangeNotifier {
  MonitoringStatus _status = MonitoringStatus.disconnected;
  MonitoringStatus get status => _status;

  SystemMetrics? _metrics;
  SystemMetrics? get metrics => _metrics;

  final List<double> _cpuHistory = [];
  List<double> get cpuHistory => List.unmodifiable(_cpuHistory);

  final List<double> _ramHistory = [];
  List<double> get ramHistory => List.unmodifiable(_ramHistory);

  List<LiveProcessInfo> _processes = [];
  List<LiveProcessInfo> get processes => _processes;

  int _totalProcesses = 0;
  int get totalProcesses => _totalProcesses;

  String? _error;
  String? get error => _error;

  DateTime? _lastPolled;
  DateTime? get lastPolled => _lastPolled;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSub;
  Timer? _procTimer;
  Timer? _reconnectTimer;
  ArchangeldConnection? _backend;

  /// Bumped on every (re)connect and on stop, so callbacks from an older
  /// socket can't change the state of the current one.
  int _gen = 0;
  int _failures = 0;
  int _desiredIntervalMs = 2000;

  bool get isConnected => _status == MonitoringStatus.connected;
  int get pollingRateMs => _desiredIntervalMs;

  /// Dynamically changes polling frequency (e.g. 1000ms when viewing Monitoring tab,
  /// 5000ms when on other tabs). Sends dynamic control frame to archangeld.
  void setPollingRateMs(int intervalMs) {
    if (intervalMs < 250 || intervalMs > 30000) return;
    _desiredIntervalMs = intervalMs;

    // Send control message over WebSocket if connected
    if (_wsChannel != null && _status == MonitoringStatus.connected) {
      try {
        _wsChannel!.sink.add(jsonEncode({'action': 'set_rate', 'interval_ms': intervalMs}));
      } catch (e) {
        debugPrint('Failed sending rate control frame: $e');
      }
    }

    // Also adjust process polling cadence (e.g. 2x the metrics cadence)
    _procTimer?.cancel();
    final procInterval = Duration(milliseconds: (intervalMs * 2).clamp(2000, 10000));
    _procTimer = Timer.periodic(procInterval, (_) {
      fetchProcesses();
    });
  }

  bool _active = true;

  /// Whether this service should currently talk to the server. The app
  /// shell turns this off while no destination that shows monitoring data
  /// is visible, so a hidden screen costs no bandwidth or battery.
  bool get active => _active;

  /// Pauses (closes the live stream and process polling) or resumes
  /// polling. Already-loaded data stays so the UI doesn't flash empty.
  void setActive(bool value) {
    if (_active == value) return;
    _active = value;
    if (!value) {
      stop();
    } else if (_backend != null && _backend!.isPaired) {
      _connect();
    }
  }

  void start(ArchangeldConnection backend) {
    // Several places start monitoring at almost the same moment (the shell
    // activating the screen, the screen's own initState); only the first
    // may open a socket.
    if (_backend == backend && (_status == MonitoringStatus.connected || _status == MonitoringStatus.connecting) && _wsChannel != null) {
      return;
    }
    _backend = backend;
    if (!_active) return;
    _connect();
  }

  /// Forgets everything learned from the previous server (used when the
  /// user switches to a different server).
  void reset() {
    stop();
    _metrics = null;
    _cpuHistory.clear();
    _ramHistory.clear();
    _processes = [];
    _totalProcesses = 0;
    _error = null;
    _lastPolled = null;
    notifyListeners();
  }

  void _recordSample(SystemMetrics m) {
    _cpuHistory.add(m.cpu.usagePercent.clamp(0.0, 100.0));
    if (_cpuHistory.length > 30) _cpuHistory.removeAt(0);
    _ramHistory.add(m.memory.usagePercent.clamp(0.0, 100.0));
    if (_ramHistory.length > 30) _ramHistory.removeAt(0);
  }

  void _closeSocket() {
    _wsSub?.cancel();
    _wsSub = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

  void stop() {
    _gen++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failures = 0;
    _closeSocket();
    _procTimer?.cancel();
    _procTimer = null;
    _status = MonitoringStatus.disconnected;
    notifyListeners();
  }

  void _connect() {
    if (!_active) return;
    if (_backend == null || !_backend!.isPaired) {
      _status = MonitoringStatus.disconnected;
      notifyListeners();
      return;
    }

    // Never leave an older socket running alongside the new one - its close
    // would otherwise flip the shared status and start yet another
    // reconnect, which made the live stream look like it kept dropping.
    _closeSocket();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final gen = ++_gen;

    if (_metrics == null) {
      _status = MonitoringStatus.connecting;
      _error = null;
      notifyListeners();
    }

    // 1. Initial snapshot fetch via REST
    fetchSnapshot();
    fetchProcesses();

    // 2. Open live WebSocket stream. The ping keeps NAT/firewall state alive
    // and detects a dead socket within ~2 intervals.
    try {
      final channel = IOWebSocketChannel.connect(_backend!.statsWsUri(), pingInterval: const Duration(seconds: 15));
      _wsChannel = channel;
      _wsSub = channel.stream.listen(
        (raw) {
          if (gen != _gen) return;
          _failures = 0;
          _onWsMessage(raw);
        },
        onDone: () {
          if (gen != _gen) return;
          _onSocketLost(null);
        },
        onError: (err) {
          if (gen != _gen) return;
          _onSocketLost(err.toString());
        },
        cancelOnError: true,
      );
    } catch (e) {
      _onSocketLost(e.toString());
    }

    // 3. Periodic process list refresh every 5 seconds
    _procTimer?.cancel();
    _procTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      fetchProcesses();
    });
  }

  /// A dropped stream is retried quietly with backoff (2s, 4s, 8s ... 30s).
  /// The last readings stay on screen and the status only becomes an error
  /// after three failed attempts in a row, so one hiccup doesn't flash
  /// "disconnected" across the app.
  void _onSocketLost(String? error) {
    _failures++;
    if (_failures >= 3) {
      _status = MonitoringStatus.error;
      _error = error ?? 'Lost the live connection to your server';
    } else if (_status != MonitoringStatus.connected) {
      _status = MonitoringStatus.connecting;
    }
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    final seconds = (2 << (_failures - 1).clamp(0, 4)).clamp(2, 30);
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      if (_active && _backend != null && _backend!.isPaired) _connect();
    });
  }

  void _onWsMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
      final m = SystemMetrics.fromJson(data);
      _metrics = m;
      _recordSample(m);
      _lastPolled = DateTime.now();
      if (_status != MonitoringStatus.connected) {
        _status = MonitoringStatus.connected;
        if (_desiredIntervalMs != 2000 && _wsChannel != null) {
          _wsChannel!.sink.add(jsonEncode({'action': 'set_rate', 'interval_ms': _desiredIntervalMs}));
        }
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error parsing ws stats: $e');
    }
  }

  Future<void> fetchSnapshot() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) return;
    final token = backend.token;
    if (token == null || token.isEmpty) return;

    try {
      final res = await http.get(backend.metricsHttpUri(), headers: {'X-Archangel-Token': token});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final m = SystemMetrics.fromJson(data);
        _metrics = m;
        _recordSample(m);
        _lastPolled = DateTime.now();
        if (_status != MonitoringStatus.connected) {
          _status = MonitoringStatus.connected;
        }
        notifyListeners();
      } else {
        debugPrint('fetchSnapshot failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchSnapshot error: $e');
    }
  }

  Future<void> fetchProcesses() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) return;
    final token = backend.token;
    if (token == null || token.isEmpty) return;

    try {
      final res = await http.get(backend.processesHttpUri(), headers: {'X-Archangel-Token': token});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (data['processes'] as List<dynamic>?)?.map((e) => LiveProcessInfo.fromJson(e as Map<String, dynamic>)).toList() ?? [];
        _processes = list;
        _totalProcesses = (data['total_count'] as num?)?.toInt() ?? list.length;
        notifyListeners();
      } else {
        debugPrint('fetchProcesses failed: HTTP ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('fetchProcesses error: $e');
    }
  }

  Future<ProcessActionResult> killProcess(int pid, {bool force = false}) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      return const ProcessActionResult(success: false, message: 'Backend is not paired');
    }
    final token = backend.token;
    if (token == null || token.isEmpty) {
      return const ProcessActionResult(success: false, message: 'Missing authentication token');
    }

    try {
      final res = await http.post(
        backend.processKillHttpUri(pid),
        headers: {'X-Archangel-Token': token, 'Content-Type': 'application/json'},
        body: jsonEncode({'force': force}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return const ProcessActionResult(success: true, message: 'Process terminated');
      } else if (res.statusCode == 401) {
        return const ProcessActionResult(success: false, message: 'Unauthorized (invalid or expired token)');
      } else if (res.statusCode == 403) {
        // 403 is usually "Admin mode is off - this action needs it".
        return ProcessActionResult(success: false, message: serverMessage(res, 'Not allowed (HTTP 403)'));
      } else {
        return ProcessActionResult(success: false, message: 'Server error: ${serverMessage(res, 'HTTP ${res.statusCode}')}');
      }
    } catch (e) {
      return ProcessActionResult(success: false, message: 'Connection failed: $e');
    }
  }

  Future<ProcessActionResult> reniceProcess(int pid, int priority) async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      return const ProcessActionResult(success: false, message: 'Backend is not paired');
    }
    final token = backend.token;
    if (token == null || token.isEmpty) {
      return const ProcessActionResult(success: false, message: 'Missing authentication token');
    }

    try {
      final res = await http.post(
        backend.processReniceHttpUri(pid),
        headers: {'X-Archangel-Token': token, 'Content-Type': 'application/json'},
        body: jsonEncode({'priority': priority}),
      );
      if (res.statusCode == 200) {
        await fetchProcesses();
        return ProcessActionResult(success: true, message: 'Priority updated to $priority');
      } else if (res.statusCode == 401) {
        return const ProcessActionResult(success: false, message: 'Unauthorized (invalid or expired token)');
      } else if (res.statusCode == 403) {
        // 403 is usually "Admin mode is off - this action needs it".
        return ProcessActionResult(success: false, message: serverMessage(res, 'Not allowed (HTTP 403)'));
      } else {
        return ProcessActionResult(success: false, message: 'Server error: ${serverMessage(res, 'HTTP ${res.statusCode}')}');
      }
    } catch (e) {
      return ProcessActionResult(success: false, message: 'Connection failed: $e');
    }
  }

  Future<ProcessActionResult> rebootHost() async {
    final backend = _backend;
    if (backend == null || !backend.isPaired) {
      return const ProcessActionResult(success: false, message: 'Backend is not paired');
    }
    final token = backend.token;
    if (token == null || token.isEmpty) {
      return const ProcessActionResult(success: false, message: 'Missing authentication token');
    }

    try {
      final res = await http.post(backend.systemRebootHttpUri(), headers: {'X-Archangel-Token': token, 'Content-Type': 'application/json'});
      if (res.statusCode == 200) {
        return const ProcessActionResult(success: true, message: 'Reboot initiated successfully');
      } else if (res.statusCode == 401) {
        return const ProcessActionResult(success: false, message: 'Unauthorized (invalid or expired token)');
      } else if (res.statusCode == 403) {
        // 403 is usually "Admin mode is off - this action needs it".
        return ProcessActionResult(success: false, message: serverMessage(res, 'Not allowed (HTTP 403)'));
      } else {
        return ProcessActionResult(success: false, message: 'Server error: ${serverMessage(res, 'HTTP ${res.statusCode}')}');
      }
    } catch (e) {
      return ProcessActionResult(success: false, message: 'Connection failed: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
