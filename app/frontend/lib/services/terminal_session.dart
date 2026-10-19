import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';

import 'archangeld_connection.dart';

enum SessionStatus { connecting, connected, closed, error }

/// Server-side session names: mirrors the backend's ^[A-Za-z0-9_-]{1,32}$.
final RegExp terminalSessionNameRe = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

/// Quotes [s] for a POSIX shell: wraps in single quotes and rewrites every
/// embedded `'` as `'\''`, so spaces, `$`, backticks and quotes are inert.
String shellSingleQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

/// The line typed into a shell to change into [dir].
String cdCommandFor(String dir) => 'cd -- ${shellSingleQuote(dir)}\n';

/// True when [dir] is safe to type into a shell line: no C0 control chars
/// (0x00-0x1F) or DEL (0x7F), which readline would interpret before quoting.
bool isSafeShellPath(String dir) {
  for (final u in dir.codeUnits) {
    if (u < 0x20 || u == 0x7f) return false;
  }
  return true;
}

/// Lines of scrollback the emulator keeps per session (oldest dropped first).
const int terminalScrollbackLines = 5000;

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

/// Maps one typed character to its Ctrl-modified control code, or null when
/// the character has no control equivalent (digits, most punctuation).
/// Letters and `@ [ \ ] ^ _` map to 0x00-0x1F; `?` maps to DEL.
String? ctrlCharFor(String ch) {
  if (ch.length != 1) return null;
  final u = ch.codeUnitAt(0);
  if (u >= 0x61 && u <= 0x7a) return String.fromCharCode(u - 0x60);
  if (u >= 0x40 && u <= 0x5f) return String.fromCharCode(u - 0x40);
  if (u == 0x20) return '\x00';
  if (u == 0x3f) return '\x7f';
  return null;
}

/// One real PTY session over archangeld's /ws/terminal, speaking its exact
/// wire protocol (see backend/internal/wsproto/wsproto.go): JSON frames
/// with a `type`, base64 `data` for stdin/stdout, `cols`/`rows` for resize.
///
/// Output is fed to an `xterm` [Terminal] emulator (cursor addressing,
/// colours, alternate screen, scrollback), which is what a tmux-attached
/// shell needs. Keystrokes come back through [Terminal.onOutput] and are sent
/// as stdin frames; the emulator's size changes become resize frames.
class TerminalSession extends ChangeNotifier {
  /// Doubles as the server-side persistent session name.
  final String label;
  String get name => label;

  /// Test seam: builds the socket instead of a real WebSocket.
  final WebSocketChannel Function(Uri uri)? _channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  SessionStatus _status = SessionStatus.connecting;
  SessionStatus get status => _status;

  late Terminal _terminal = _newTerminal();

  /// The emulator for the current connection. It is replaced (not reused) on
  /// reconnect, so widgets must re-read it when this session notifies; see
  /// [terminalEpoch].
  Terminal get terminal => _terminal;

  /// Increments whenever [terminal] is replaced; use it as a widget key.
  int get terminalEpoch => _epoch;
  int _epoch = 0;

  // Streaming UTF-8 decoder: a multibyte character split across two stdout
  // frames is held until its remaining bytes arrive.
  final StringBuffer _decoded = StringBuffer();
  late Sink<List<int>> _utf8 = _newUtf8();

  Sink<List<int>> _newUtf8() =>
      const Utf8Decoder(allowMalformed: true).startChunkedConversion(StringConversionSink.fromStringSink(_decoded));

  bool _gotOutput = false;

  /// True once any server output has arrived on the current connection.
  bool get hasOutput => _gotOutput;

  int _gen = 0;
  bool _disposed = false;

  String? _error;
  String? get error => _error;

  int? _exitCode;
  int? get exitCode => _exitCode;

  /// Latest server `error` frame (e.g. persistence unavailable). Shown as a
  /// dismissible banner, never mixed into terminal output.
  String? _notice;
  String? get notice => _notice;
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  /// Sticky Ctrl from the on-screen accessory bar: the next typed character
  /// (or accessory key) is sent as its Ctrl combination, then it clears.
  bool _ctrlLatched = false;
  bool get ctrlLatched => _ctrlLatched;
  set ctrlLatched(bool v) {
    if (_ctrlLatched == v) return;
    _ctrlLatched = v;
    notifyListeners();
  }

  Completer<void> _firstOutput = Completer<void>();
  Timer? _stallTimer;
  bool _stalled = false;

  /// True when 10 s passed after connecting without any output arriving.
  bool get noDataTimedOut => _stalled && !_gotOutput;

  /// Completes on the first stdout frame, or after [timeout] regardless.
  Future<void> waitForFirstOutput({Duration timeout = const Duration(seconds: 3)}) =>
      _firstOutput.future.timeout(timeout, onTimeout: () {});

  ArchangeldConnection? _backend;
  int _cols = 120;
  int _rows = 32;
  Timer? _pingTimer;

  TerminalSession({required this.label, WebSocketChannel Function(Uri uri)? channelFactory})
      : _channelFactory = channelFactory;

  Terminal _newTerminal() {
    final t = Terminal(maxLines: terminalScrollbackLines);
    t.onOutput = _onTerminalOutput;
    t.onResize = _onTerminalResize;
    return t;
  }

  void _onTerminalResize(int w, int h, int pw, int ph) => resize(w, h);

  void _onTerminalOutput(String data) {
    var out = data;
    if (_ctrlLatched) {
      _ctrlLatched = false;
      final mapped = ctrlCharFor(data);
      if (mapped != null) out = mapped;
      notifyListeners();
    }
    sendInput(out);
  }

  void connect(ArchangeldConnection backend, {int cols = 120, int rows = 32}) {
    _backend = backend;
    _cols = cols;
    _rows = rows;
    _terminal.onResize = null; // the first size is sent once the socket is ready
    _terminal.resize(cols, rows);
    _terminal.onResize = _onTerminalResize;
    _startConnection();
  }

  /// Drops the old emulator and starts a clean one at the current size. The
  /// server (tmux) redraws the attached session, so nothing is carried over.
  void _resetTerminal() {
    _terminal.onOutput = null;
    _terminal.onResize = null;
    final t = Terminal(maxLines: terminalScrollbackLines);
    t.resize(_cols, _rows);
    t.onOutput = _onTerminalOutput;
    t.onResize = _onTerminalResize;
    _terminal = t;
    _epoch++;
    _utf8.close();
    _decoded.clear();
    _utf8 = _newUtf8();
    _gotOutput = false;
  }

  void _startConnection() {
    if (_backend == null || _disposed) return;
    final gen = ++_gen;
    _sub?.cancel();
    _channel?.sink.close();
    _pingTimer?.cancel();
    _stallTimer?.cancel();
    if (_firstOutput.isCompleted) _firstOutput = Completer<void>();
    _stalled = false;
    _stallTimer = Timer(const Duration(seconds: 10), () {
      if (gen != _gen || _disposed) return;
      _stalled = true;
      if (!_gotOutput) notifyListeners();
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

    final WebSocketChannel channel;
    try {
      channel = (_channelFactory ?? WebSocketChannel.connect)(uri);
      _channel = channel;
    } catch (e) {
      _status = SessionStatus.error;
      _error = 'Could not open connection: $e';
      notifyListeners();
      return;
    }

    _sub = channel.stream.listen(
      (raw) {
        if (gen != _gen) return;
        _onMessage(raw);
      },
      onDone: () {
        if (gen != _gen) return;
        _pingTimer?.cancel();
        if (_status != SessionStatus.error) {
          _status = SessionStatus.closed;
          notifyListeners();
        }
      },
      onError: (e) {
        if (gen != _gen) return;
        _pingTimer?.cancel();
        _status = SessionStatus.error;
        _error = e.toString();
        notifyListeners();
      },
      cancelOnError: true,
    );

    channel.ready.then((_) {
      if (gen != _gen || _disposed) return;
      if (_status != SessionStatus.connected) {
        _status = SessionStatus.connected;
        notifyListeners();
      }
      resize(_cols, _rows);
      // Periodic ping every 45s to avoid backend 10m idle timeout during quiet sessions
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (_status == SessionStatus.connected) {
          channel.sink.add(jsonEncode({'type': 'ping'}));
        }
      });
    }).catchError((Object e) {
      if (gen != _gen || _disposed) return;
      if (_status != SessionStatus.error) {
        _status = SessionStatus.error;
        _error = 'Could not open connection: $e';
        notifyListeners();
      }
    });
  }

  void reconnect() {
    // The server redraws the attached session, so start from a clean screen.
    _resetTerminal();
    _startConnection();
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
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
          _utf8.add(base64.decode(data));
        } catch (_) {
          return;
        }
        final text = _decoded.toString();
        _decoded.clear();
        if (text.isNotEmpty) _terminal.write(text);
        _gotOutput = true;
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

  /// Test seam: delivers one raw JSON frame as if it came from the server.
  @visibleForTesting
  void debugReceive(String rawFrame) => _onMessage(rawFrame);

  /// Presses a named key through the emulator, so application-cursor mode
  /// and friends produce the right escape sequence. Honours (and clears)
  /// the sticky Ctrl latch.
  void pressKey(TerminalKey key) {
    final ctrl = _ctrlLatched;
    if (ctrl) {
      _ctrlLatched = false;
      notifyListeners();
    }
    _terminal.keyInput(key, ctrl: ctrl);
  }

  /// Types [text] as if from the keyboard (honours the Ctrl latch).
  void typeText(String text) => _terminal.textInput(text);

  /// Pastes [text], using bracketed paste when the running program asked.
  void pasteText(String text) {
    if (text.isNotEmpty) _terminal.paste(text);
  }

  /// Types a `cd` into the shell once it has printed something (prompt).
  /// Returns false when nothing was sent (unsafe path, disposed, or not
  /// connected after waiting).
  Future<bool> changeDirectory(String dir) async {
    if (!isSafeShellPath(dir)) return false;
    await waitForFirstOutput();
    if (_disposed || _status != SessionStatus.connected) return false;
    sendInput(cdCommandFor(dir));
    return true;
  }

  void sendInput(String text) {
    if (_disposed || _channel == null || text.isEmpty) return;
    _channel!.sink.add(jsonEncode({
      'type': 'stdin',
      'data': base64.encode(utf8.encode(text)),
    }));
  }

  void resize(int cols, int rows) {
    _cols = cols;
    _rows = rows;
    if (_disposed) return;
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
    if (_disposed) return;
    close();
    _disposed = true;
    _gen++;
    _terminal.onOutput = null;
    _terminal.onResize = null;
    super.dispose();
  }
}
