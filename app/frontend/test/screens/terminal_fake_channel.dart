// ignore_for_file: depend_on_referenced_packages
// stream_channel is web_socket_channel's own base package; only needed to fake it.
import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:archangel/services/archangeld_connection.dart';
import 'package:archangel/services/terminal_session.dart';

/// An in-memory stand-in for the /ws/terminal socket. [sent] holds the JSON
/// frames the app wrote; [serverSend] plays frames from the "server".
class FakeTerminalChannel extends StreamChannelMixin implements WebSocketChannel {
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  late final _FakeSink _sink = _FakeSink(sent);

  @override
  Stream get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  void serverSend(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));

  void serverStdout(List<int> bytes) => serverSend({'type': 'stdout', 'data': base64.encode(bytes)});

  void serverClose() => _incoming.close();

  void serverError(Object error) => _incoming.addError(error);

  /// Decoded stdin payloads, in order.
  List<String> get stdin => [
    for (final f in sent)
      if (f['type'] == 'stdin') utf8.decode(base64.decode(f['data'] as String)),
  ];

  List<Map<String, dynamic>> get resizes => [
    for (final f in sent)
      if (f['type'] == 'resize') f,
  ];
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.sent);
  final List<Map<String, dynamic>> sent;
  final _done = Completer<void>();

  @override
  void add(dynamic data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => stream.forEach(add);

  @override
  Future close([int? closeCode, String? closeReason]) async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future get done => _done.future;
}

/// A paired connection (no network is touched by pairing itself in tests
/// that only need terminalWsUri; call under `runAsync` with a temp KV store).
Future<ArchangeldConnection> pairedBackend() async {
  final b = ArchangeldConnection();
  await b.pair(host: '10.0.0.1:8443', token: 'tkn');
  return b;
}

/// A connected session over a [FakeTerminalChannel]. Pass a backend from
/// [pairedBackend] to keep session creation in the caller's (fake-async) zone.
(TerminalSession, FakeTerminalChannel) connectedFakeSessionWith(ArchangeldConnection backend, {String name = 'main'}) {
  final ch = FakeTerminalChannel();
  final session = TerminalSession(label: name, channelFactory: (_) => ch);
  session.connect(backend);
  return (session, ch);
}

Future<(TerminalSession, FakeTerminalChannel)> connectedFakeSession({String name = 'main'}) async =>
    connectedFakeSessionWith(await pairedBackend(), name: name);
