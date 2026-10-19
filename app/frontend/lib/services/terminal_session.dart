import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'archangeld_connection.dart';

enum SessionStatus { connecting, connected, closed, error }

/// Server-side session names: mirrors the backend's ^[A-Za-z0-9_-]{1,32}$.
final RegExp terminalSessionNameRe = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Quotes [s] for a POSIX shell: wraps in single quotes and rewrites every
/// embedded `'` as `'\''`, so spaces, `$`, backticks and quotes are inert.
String shellSingleQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// The line typed into a shell to change into [dir].
String cdCommandFor(String dir) => 'cd -- ${shellSingleQuote(dir)}\n';

/// Picks the first unused name: "main", then "shell-2", "shell-3", ...
/// [taken] should hold both server-side sessions and currently open tabs.
String nextSessionName(Iterable<String> taken) {
  final used = taken.toSet();
  if (!used.contains('main')) return 'main';
  var n = 2;
  while (used.contains('shell-$n')) {
    n++;
  }
  return 'shell-$n';
}

/// One entry of GET /api/v1/terminal/sessions.
class TerminalSessionInfo {
  final String name;
  final int windows;
  final bool attached;
  final DateTime? created;

  const TerminalSessionInfo({required this.name, this.windows = 1, this.attached = false, this.created});

  factory TerminalSessionInfo.fromJson(Map<String, dynamic> json) {
    final unix = (json['created_unix'] as num?)?.toInt();
    return TerminalSessionInfo(
      name: json['name'] as String? ?? '',
      windows: (json['windows'] as num?)?.toInt() ?? 1,
      attached: json['attached'] == true || (json['attached'] is num && (json['attached'] as num) > 0),
      created: unix != null && unix > 0 ? DateTime.fromMillisecondsSinceEpoch(unix * 1000) : null,
    );
  }

  /// "running since Oct 19, 14:02" (or just the time when it is today).
  String runningSince(DateTime now) => formatRunningSince(created, now);
}

/// Tolerant parser for the session list body; bad input yields an empty list.
List<TerminalSessionInfo> parseTerminalSessions(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map<String, dynamic>) TerminalSessionInfo.fromJson(e),
    ].where((s) => s.name.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

String formatRunningSince(DateTime? created, DateTime now) {
  if (created == null) return 'running';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int v) => v.toString().padLeft(2, '0');
  final time = '${two(created.hour)}:${two(created.minute)}';
  final sameDay = created.year == now.year && created.month == now.month && created.day == now.day;
  return sameDay ? 'running since $time' : 'running since ${months[created.month - 1]} ${created.day}, $time';
}

/// HTTP side of persistent sessions (list / end).
class TerminalSessionApi {
  /// Returns null when the list could not be fetched (distinct from "none").
  static Future<List<TerminalSessionInfo>?> list(ArchangeldConnection backend) async {
    if (!backend.isPaired || backend.token == null) return null;
    try {
      final res = await http
          .get(backend.terminalSessionsHttpUri(), headers: {'X-Archangel-Token': backend.token!})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return parseTerminalSessions(res.body);
    } catch (e) {
      debugPrint('Error listing terminal sessions: $e');
      return null;
    }
  }

  /// Ends the session on the server. Returns null on success, else a message.
  static Future<String?> end(ArchangeldConnection backend, String name) async {
    if (!backend.isPaired || backend.token == null) return 'Not connected';
    try {
      final res = await http
          .delete(backend.terminalSessionHttpUri(name), headers: {'X-Archangel-Token': backend.token!})
          .timeout(const Duration(seconds: 8));
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
      if (res.statusCode == 200 && (data == null || data['success'] != false)) return null;
      return (data?['message'] as String?) ?? 'Could not end session (HTTP ${res.statusCode})';
    } catch (e) {
      return 'Could not end session: $e';
    }
  }
}

/// One real PTY session over archangeld's /ws/terminal, speaking its exact
/// wire protocol (see backend/internal/wsproto/wsproto.go): JSON frames
/// with a `type`, base64 `data` for stdin/stdout, `cols`/`rows` for resize.
///
/// This deliberately renders raw output (stripped of nothing) rather than
/// interpreting ANSI/VT100 escape sequences - it proves the pipe works
/// end-to-end (real bytes, both directions, over the real endpoint) rather
/// than being a full terminal emulator. A real emulator (cursor movement,
/// color, screen redraws) is separate scope - the `xterm` package is the
/// natural fit on top of this if/when that's wanted.
class TerminalSession extends ChangeNotifier {
  /// Doubles as the server-side persistent session name.
  final String label;
  String get name => label;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  SessionStatus _status = SessionStatus.connecting;
  SessionStatus get status => _status;

  final StringBuffer _output = StringBuffer();
  String get output => _output.toString();

  String? _error;
  String? get error => _error;

  int? _exitCode;
  int? get exitCode => _exitCode;

  /// Latest server `error` frame (e.g. persistence unavailable). Shown as a
  /// dismissible banner, never mixed into terminal output.
  String? _notice;
  String? get notice => _notice;
  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  Completer<void> _firstOutput = Completer<void>();
  Timer? _stallTimer;
  bool _stalled = false;

  /// True when 10 s passed after connecting without any output arriving.
  bool get noDataTimedOut => _stalled && _output.isEmpty;

  /// Completes on the first stdout frame, or after [timeout] regardless.
  Future<void> waitForFirstOutput({Duration timeout = const Duration(seconds: 3)}) =>
      _firstOutput.future.timeout(timeout, onTimeout: () {});

  ArchangeldConnection? _backend;
  int _cols = 120;
  int _rows = 32;
  Timer? _pingTimer;

  TerminalSession({required this.label});

  void connect(ArchangeldConnection backend, {int cols = 120, int rows = 32}) {
    _backend = backend;
    _cols = cols;
    _rows = rows;
    _startConnection();
  }

  void _startConnection() {
    if (_backend == null) return;
    _sub?.cancel();
    _channel?.sink.close();
    _pingTimer?.cancel();
    _stallTimer?.cancel();
    if (_firstOutput.isCompleted) _firstOutput = Completer<void>();
    _stalled = false;
    _stallTimer = Timer(const Duration(seconds: 10), () {
      _stalled = true;
      if (_output.isEmpty) notifyListeners();
    });

    _status = SessionStatus.connecting;
    _error = null;
    _notice = null;
    notifyListeners();

    final Uri uri;
    try {
      uri = _backend!.terminalWsUri(session: label);
    } on StateError catch (e) {
      _status = SessionStatus.error;
      _error = e.message;
      notifyListeners();
      return;
    }

    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      _status = SessionStatus.error;
      _error = 'Could not open connection: $e';
      notifyListeners();
      return;
    }

    _sub = _channel!.stream.listen(
      _onMessage,
      onDone: () {
        _pingTimer?.cancel();
        if (_status != SessionStatus.error) {
          _status = SessionStatus.closed;
          notifyListeners();
        }
      },
      onError: (e) {
        _pingTimer?.cancel();
        _status = SessionStatus.error;
        _error = e.toString();
        notifyListeners();
      },
      cancelOnError: true,
    );

    _channel!.ready.then((_) {
      if (_status != SessionStatus.connected) {
        _status = SessionStatus.connected;
        notifyListeners();
      }
      resize(_cols, _rows);
      // Periodic ping every 45s to avoid backend 10m idle timeout during quiet sessions
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (_status == SessionStatus.connected) {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        }
      });
    }).catchError((Object e) {
      if (_status != SessionStatus.error) {
        _status = SessionStatus.error;
        _error = 'Could not open connection: $e';
        notifyListeners();
      }
    });
  }

  void reconnect() {
    // The server redraws the attached session, so start from a clean buffer.
    _output.clear();
    _startConnection();
  }

  void clearOutput() {
    _output.clear();
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> frame;
    try {
      frame = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (frame['type']) {
      case 'stdout':
        final data = frame['data'] as String?;
        if (data == null) return;
        try {
          final decoded = utf8.decode(base64.decode(data), allowMalformed: true);
          _appendDecodedText(_cleanAnsi(decoded));
        } catch (_) {
          return;
        }
        if (_status != SessionStatus.connected) _status = SessionStatus.connected;
        if (!_firstOutput.isCompleted) _firstOutput.complete();
        notifyListeners();
      case 'exit':
        _exitCode = frame['code'] as int?;
        _status = SessionStatus.closed;
        _pingTimer?.cancel();
        notifyListeners();
      case 'error':
        // Not necessarily fatal (persistence fallback keeps working); a real
        // failure is followed by a close frame, which sets the status.
        _notice = (frame['message'] as String?) ?? 'Unknown server error';
        notifyListeners();
      case 'pong':
        // Keep-alive acknowledged
        break;
    }
  }

  /// Appends decoded text to buffer, interpreting \b (backspace) properly
  /// rather than leaving non-printable box characters.
  void _appendDecodedText(String text) {
    if (text.isEmpty) return;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\b' || char == '\x7f') {
        // Backspace: remove last character if buffer is not empty
        final current = _output.toString();
        if (current.isNotEmpty) {
          _output.clear();
          _output.write(current.substring(0, current.length - 1));
        }
      } else {
        _output.write(char);
      }
    }
  }

  /// Cleans ANSI escape sequences and normalizes carriage returns for smooth display
  static final RegExp _ansiRegex = RegExp(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])');
  static String _cleanAnsi(String input) {
    // Strip standard ANSI CSI / OSC sequences
    final stripped = input.replaceAll(_ansiRegex, '');
    // Normalize solitary carriage returns that CLI progress indicators use so they don't corrupt rendering
    return stripped.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  /// Types a `cd` into the shell once it has printed something (prompt).
  Future<void> changeDirectory(String dir) async {
    await waitForFirstOutput();
    sendInput(cdCommandFor(dir));
  }

  void sendInput(String text) {
    if (_channel == null || text.isEmpty) return;
    _channel!.sink.add(jsonEncode({
      'type': 'stdin',
      'data': base64.encode(utf8.encode(text)),
    }));
  }

  void resize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    _channel?.sink.add(jsonEncode({'type': 'resize', 'cols': cols, 'rows': rows}));
  }

  /// Detaches: drops the websocket only. The shell keeps running on the server.
  void close() {
    _pingTimer?.cancel();
    _stallTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
